extends Node3D
## Phase 1 playable loop orchestration:
##   station -> call -> dispatch (drive / quick) -> on scene -> hands-on work -> outcome
##   -> return -> story & station board -> end shift -> next call.
## Rules live in GameModel; this script maps them onto scene objects and the HUD.

const STATION_PARK := Vector3(0, 0, -6)
const PLAYER_SPAWN := Vector3(-3.5, 0, -4.0)
const ARRIVE_DIST := 16.0
const RETURN_DIST := 9.0
const FIRST_CALL_DELAY := 6.0
const QUALITY := {
	"low": {"shadows": false, "scale": 0.7, "fps": 30, "rain": 120},
	"medium": {"shadows": true, "scale": 0.85, "fps": 30, "rain": 260},
	"high": {"shadows": true, "scale": 1.0, "fps": 60, "rain": 500},
}

var model: GameModel
var town: TownBuilder
var player: Player
var truck: Truck
var theo: CrewAgent
var rig: CameraRig
var hud: Hud
var site: IncidentSite
var sun: DirectionalLight3D
var env: Environment
var beacon: Node3D
var bot_input := Vector2.ZERO
var bot_active := false

var _call_t := -1.0
var _lines: Array = []
var _speaker := ""
var _ui_t := 0.0
var _cone_hold := 0.0


func _ready() -> void:
	_build_environment()
	town = TownBuilder.new()
	town.name = "Town"
	add_child(town)
	town.build(WorldState.new())
	truck = Truck.new()
	truck.name = "Truck"
	truck.collision_mask = 1 | 4
	add_child(truck)
	truck.place(STATION_PARK, PI)
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.teleport(PLAYER_SPAWN)
	theo = CrewAgent.new()
	theo.name = "Theo"
	add_child(theo)
	theo.teleport(PLAYER_SPAWN + Vector3(-1.5, 0, 0.5))
	theo.follow_target = player
	theo.setup("theo_vance", "Theo Vance", 1.0)
	rig = CameraRig.new()
	add_child(rig)
	rig.target = player
	rig.exclude([player, truck, theo])
	rig.snap()
	beacon = Node3D.new()
	add_child(beacon)
	var col := Build.cyl(beacon, 0.6, 40.0, Vector3(0, 20, 0), Build.C_AMBER)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(1.0, 0.7, 0.2, 0.35)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	col.material_override = bm
	beacon.visible = false
	hud = Hud.new()
	add_child(hud)
	_wire_hud()
	_make_truck_interactions()
	_make_station_board()
	player.blocked.connect(func(r: String) -> void: hud.show_toast(r))
	theo.work_step_done.connect(_on_theo_step)
	theo.task_finished.connect(_on_theo_done)
	Game.model_replaced.connect(_on_model)
	apply_quality(Game.quality)
	hud.set_controls_visible(false)
	if "--autoplay" in OS.get_cmdline_user_args():
		var bot := preload("res://gameplay/autoplay.gd").new()
		bot.main = self
		add_child(bot)
	else:
		hud.open_menu(Game.has_save(), Game.quality)


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.36, 0.52, 0.72)
	sm.sky_horizon_color = Color(0.86, 0.80, 0.72)
	sm.ground_horizon_color = Color(0.70, 0.66, 0.58)
	sm.ground_bottom_color = Color(0.30, 0.32, 0.28)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.80, 0.82)
	env.fog_density = 0.004
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.15
	sun.directional_shadow_max_distance = 45.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)


func apply_quality(q: String) -> void:
	if not QUALITY.has(q):
		q = "medium"
	Game.quality = q
	var c: Dictionary = QUALITY[q]
	sun.shadow_enabled = c["shadows"]
	get_viewport().scaling_3d_scale = c["scale"]
	Engine.max_fps = c["fps"]
	_update_weather()


func _update_weather() -> void:
	var weather: String = model.incidents.active.get("weather", "clearing") if model else "clearing"
	var rainy := weather != "clearing"
	rig.set_rain(QUALITY[Game.quality]["rain"] * (2 if weather == "heavy_rain" else 1) if rainy else 0)
	sun.light_energy = 0.7 if rainy else 1.15
	env.fog_density = 0.012 if rainy else 0.004


# --- Model lifecycle ---------------------------------------------------------

func _on_model(m: GameModel) -> void:
	if model and model.incident_resolved.is_connected(_on_resolved):
		model.incident_resolved.disconnect(_on_resolved)
	model = m
	model.incident_resolved.connect(_on_resolved)
	town.set_world(model.world)
	hud.set_controls_visible(true)
	_clear_site()
	var inst := model.incidents.active
	var state: String = inst.get("state", "")
	match state:
		IncidentDirector.EN_ROUTE, IncidentDirector.ON_SCENE:
			# Resume straight onto the scene: never make the player re-drive after an interruption.
			_place_at_site(inst)
			if state == IncidentDirector.EN_ROUTE:
				_arrive()
			else:
				_spawn_site()
		IncidentDirector.RESOLVED:
			_quick_to_station()
		_:
			_place_at_station()
			if state == IncidentDirector.OFFERED:
				hud.dispatch_banner.visible = true
			else:
				_call_t = FIRST_CALL_DELAY
	_update_weather()
	_next_line()


func _place_at_station() -> void:
	_exit_truck_silent()
	truck.place(STATION_PARK, PI)
	player.teleport(PLAYER_SPAWN)
	theo.teleport(PLAYER_SPAWN + Vector3(-1.5, 0, 0.5))
	rig.walk_yaw = 0.0
	rig.target = player
	rig.mode = "walk"
	rig.snap()


func _site_anchor(inst: Dictionary) -> Vector3:
	var loc: Dictionary = DataDB.locations()[inst["location"]]
	return Vector3(float(loc["anchor"][0]), 0, float(loc["anchor"][1]))


func _place_at_site(inst: Dictionary) -> void:
	_exit_truck_silent()
	var a := _site_anchor(inst)
	truck.place(a + Vector3(0.5, 0, -14.0), PI)
	player.teleport(a + Vector3(-1.6, 0, -11.0), PI)
	theo.teleport(a + Vector3(2.4, 0, -11.0))
	rig.walk_yaw = PI
	rig.target = player
	rig.mode = "walk"
	rig.snap()


func _spawn_site() -> void:
	_clear_site()
	var def_site: String = model.incidents.defs[model.incidents.active["def_id"]].get("site", "fallen_tree")
	site = FloodedCellarSite.new() if def_site == "flooded_cellar" else FallenTreeSite.new()
	site.name = "Site"
	add_child(site)
	site.setup(model, player, _site_anchor(model.incidents.active))
	site.message.connect(func(t: String) -> void: hud.show_toast(t))


func _clear_site() -> void:
	if site:
		site.queue_free()
		site = null
	theo.cancel()
	player.has_saw = false
	if player.carrying:
		player.drop_carried().queue_free()


# --- Incident flow -----------------------------------------------------------

func _offer_call() -> void:
	var inst := model.offer_incident()
	if inst.is_empty():
		return
	Audio.play("alert", -4.0)
	hud.open_dispatch(inst)
	hud.dispatch_banner.visible = true
	Game.save_game()


func _on_dispatch(mode: String) -> void:
	var r := model.dispatch(mode)
	if not r["ok"]:
		hud.show_toast(r["reason"])
		return
	hud.dispatch_banner.visible = false
	_update_weather()
	if mode == "quick":
		_place_at_site(model.incidents.active)
		_arrive()
	else:
		beacon.position = _site_anchor(model.incidents.active)
		beacon.visible = true
		truck.siren = true
		Audio.loop_start("siren", -14.0)
		hud.show_toast("Get in the truck — follow the beacon")
	Game.save_game()


func _arrive() -> void:
	if not model.arrive():
		return
	beacon.visible = false
	truck.siren = false
	Audio.loop_stop("siren")
	if truck.driving:
		truck.speed = 0.0
		_exit_truck()
	rig.walk_yaw = PI
	_spawn_site()
	theo.rate = model.crew.work_rate("theo_vance", "safety")
	Game.save_game()


func _on_resolved(result: Dictionary) -> void:
	player.release()
	if site:
		site.stop_actions()
	Audio.play("chime" if result["outcome"] == "success" else "stall", -4.0)
	hud.open_result(result, model.outcome_text(result))
	Game.save_game()


func _on_return(mode: String) -> void:
	if mode == "quick":
		_quick_to_station()
	else:
		hud.show_toast("Drive back to the station")


func _quick_to_station() -> void:
	_place_at_station()
	_finish_return()


func _finish_return() -> void:
	if not model.return_to_station():
		return
	_clear_site()
	_update_weather()
	hud.show_toast("Back at the station. Check the board when you're ready.")
	Game.save_game()
	_next_line()


func _end_shift() -> void:
	var r := model.end_shift()
	if not r["ok"]:
		hud.show_toast(r["reason"])
		return
	hud.show_toast("Day %d" % model.day, 3.0)
	_call_t = FIRST_CALL_DELAY
	Game.save_game()
	_next_line()


# --- Truck ------------------------------------------------------------------

func _make_truck_interactions() -> void:
	var drive := Interactable.make(truck, truck.point("driver"), "Drive", 1.7)
	drive.available = func() -> bool: return player.carrying == null and not truck.driving
	drive.on_press = _enter_truck
	var radio := Interactable.make(truck, truck.point("radio"), "Radio utility", 1.7)
	radio.available = func() -> bool:
		return model != null and not model.incidents.find_task("isolate_power").is_empty() \
			and not model.incidents.active["flags"].has("isolation_eta")
	radio.on_press = func() -> void:
		var r := model.request_isolation()
		if r["ok"]:
			Audio.play("radio")
			hud.show_toast("Utility: \"Isolating that line now, stand by...\"", 3.5)
		else:
			hud.show_toast(r["reason"])
	var locker := Interactable.make(truck, truck.point("locker"), "Chainsaw", 1.7)
	locker.available = func() -> bool: return player.carrying == null and model != null
	locker.prompt_fn = func() -> String: return "Stow\nchainsaw" if player.has_saw else "Take\nchainsaw"
	locker.on_press = func() -> void:
		player.has_saw = not player.has_saw
		Audio.play("click", -6.0, 0.7)
	var cones := Interactable.make(truck, truck.point("cones"), "Place cones", 1.7)
	cones.hold = true
	cones.available = func() -> bool:
		return site != null and model.incidents.check_task("secure_area") == "" and not theo.is_busy()
	cones.prompt_fn = func() -> String: return "Hold:\ncones"
	cones.on_press = func() -> void: _cone_hold = 0.0
	cones.on_hold = func(dt: float) -> void:
		_cone_hold += dt
		if _cone_hold >= 2.5:
			_cone_hold = -100.0
			site.show_all_cones()
			model.progress_task("secure_area", {"by": "player"})
			hud.show_toast("Scene coned off")


func _enter_truck() -> void:
	player.active = false
	player.visible = false
	player.velocity = Vector3.ZERO
	theo.visible = false
	theo.process_mode = Node.PROCESS_MODE_DISABLED
	truck.set_driving(true)
	rig.target = truck
	rig.mode = "drive"
	player.rescan()


func _exit_truck() -> void:
	if absf(truck.speed) > 3.0:
		hud.show_toast("Slow down first")
		return
	_exit_truck_silent()
	player.teleport(truck.global_transform * truck.point("driver"), truck.rotation.y)
	theo.teleport(truck.global_transform * truck.point("radio"))
	rig.walk_yaw = truck.rotation.y if site == null else PI


func _exit_truck_silent() -> void:
	if not truck.driving and player.active:
		return
	truck.set_driving(false)
	player.active = true
	player.visible = true
	theo.visible = true
	theo.process_mode = Node.PROCESS_MODE_INHERIT
	rig.target = player
	rig.mode = "walk"


func _make_station_board() -> void:
	var board := Node3D.new()
	board.position = Vector3(-8.5, 0, -12.0)
	add_child(board)
	Build.box(board, Vector3(2.2, 1.4, 0.12), Vector3(0, 1.6, 0), Build.C_NAVY)
	Build.box(board, Vector3(1.9, 1.1, 0.05), Vector3(0, 1.6, 0.07), Build.C_CREAM)
	Build.box(board, Vector3(0.1, 1.0, 0.1), Vector3(0, 0.5, 0), Build.C_NAVY)
	Build.label(board, "STATION BOARD", Vector3(0, 2.6, 0), 34, Build.C_AMBER)
	var it := Interactable.make(board, Vector3(0, 0, 1.0), "Station\nboard", 2.0)
	it.available = func() -> bool: return model != null and not truck.driving
	it.on_press = func() -> void: hud.open_dashboard(model)


# --- Crew -------------------------------------------------------------------

func _on_crew_order() -> void:
	if site == null or theo.is_busy():
		return
	var reason := model.incidents.check_task("secure_area")
	if reason != "":
		hud.show_toast(reason)
		return
	theo.assign("secure_area", site.cone_points)
	Audio.play("click", -6.0, 1.3)


func _on_theo_step(task: String, index: int) -> void:
	if task == "secure_area" and site:
		site.show_cone(index)


func _on_theo_done(task: String) -> void:
	if task != "secure_area" or model == null:
		return
	var r := model.progress_task("secure_area", {"by": "theo_vance"})
	if r["ok"]:
		var line := "Saw's all yours." if model.incidents.active.get("def_id", "") == "fallen_tree" else "Nobody's wandering in now."
		hud.show_toast("Theo: \"Scene's coned. %s\"" % line)


# --- HUD & input ------------------------------------------------------------

func _wire_hud() -> void:
	hud.action_down.connect(_action_down)
	hud.action_up.connect(_action_up)
	hud.crew_order.connect(_on_crew_order)
	hud.tactical_toggled.connect(func() -> void:
		if not truck.driving:
			rig.mode = "tactical" if rig.mode == "walk" else "walk")
	hud.dispatch_chosen.connect(_on_dispatch)
	hud.return_chosen.connect(_on_return)
	hud.dialogue_next.connect(_next_line)
	hud.project_bought.connect(func(id: String) -> void:
		var r := model.buy_project(id)
		if not r["ok"]:
			hud.show_toast(r["reason"])
		else:
			Audio.play("chime", -8.0)
			Game.save_game()
		hud.open_dashboard(model)
		_next_line())
	hud.end_shift_pressed.connect(_end_shift)
	hud.new_game_pressed.connect(func() -> void: Game.new_game())
	hud.continue_pressed.connect(func() -> void:
		if not Game.continue_game():
			hud.show_toast("Save could not be loaded — starting fresh")
			Game.new_game())
	hud.pause_choice.connect(_on_pause_choice)
	hud.quality_chosen.connect(func(q: String) -> void:
		apply_quality(q)
		Game.save_settings()
		if hud.menu_panel.visible:
			hud.open_menu(Game.has_save(), Game.quality)
		elif hud.pause_panel.visible:
			hud.open_pause(_has_call(), Game.quality))
	hud.volume_changed.connect(func(v: float) -> void:
		Game.volume = v
		Audio.set_master_volume(v)
		Game.save_settings())


func _has_call() -> bool:
	return model != null and model.incidents.active.get("state", "") in [IncidentDirector.EN_ROUTE, IncidentDirector.ON_SCENE]


func _on_pause_choice(choice: String) -> void:
	match choice:
		"open":
			hud.open_pause(_has_call(), Game.quality)
		"menu":
			Game.save_game()
			get_tree().reload_current_scene()
		"abandon":
			model.abandon()


func _action_down() -> void:
	if truck.driving:
		_exit_truck()
		return
	player.press()


func _action_up() -> void:
	player.release()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and not e.echo:
		var k := e as InputEventKey
		match k.keycode:
			KEY_E, KEY_SPACE:
				if k.pressed:
					_action_down()
				else:
					_action_up()
			KEY_TAB:
				if k.pressed:
					hud.tactical_toggled.emit()
			KEY_ESCAPE:
				if k.pressed and model:
					hud.open_pause(_has_call(), Game.quality)
			KEY_Q:
				if k.pressed:
					_on_crew_order()


func _move_vector() -> Vector2:
	if bot_active:
		return bot_input
	var v := hud.stick.value
	var kb := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_down", "ui_up"))
	if Input.is_physical_key_pressed(KEY_A):
		kb.x -= 1
	if Input.is_physical_key_pressed(KEY_D):
		kb.x += 1
	if Input.is_physical_key_pressed(KEY_W):
		kb.y += 1
	if Input.is_physical_key_pressed(KEY_S):
		kb.y -= 1
	if kb.length() > 0.1:
		v = kb.limit_length(1.0)
	return v


func _dialogue_open() -> bool:
	return hud.dialogue_panel.visible


func _next_line() -> void:
	if model == null:
		return
	if _lines.is_empty():
		var frag := model.pop_fragment()
		if frag.is_empty():
			hud.hide_dialogue()
			return
		_lines = frag["lines"].duplicate()
		_speaker = DataDB.display_name(frag["speaker"])
	hud.show_dialogue(_speaker, _lines.pop_front())


func _process(dt: float) -> void:
	if model == null:
		return
	var blocked := hud.any_modal()
	var mv := Vector2.ZERO if blocked else _move_vector()
	if truck.driving:
		truck.drive_input = mv
	else:
		player.move_input = mv
		player.camera_yaw = rig.yaw
	if not blocked:
		model.tick(dt)
	if not blocked and not _dialogue_open():
		if model.incidents.active.is_empty() and _call_t > 0.0:
			_call_t -= dt
			if _call_t <= 0.0:
				_offer_call()
	if not model.fragments.is_empty() and not _dialogue_open() and _lines.is_empty():
		_next_line()
	var state: String = model.incidents.active.get("state", "")
	if truck.driving and state == IncidentDirector.EN_ROUTE:
		if _flat_dist(truck.global_position, _site_anchor(model.incidents.active)) < ARRIVE_DIST:
			_arrive()
	if truck.driving and state == IncidentDirector.RESOLVED:
		if _flat_dist(truck.global_position, STATION_PARK) < RETURN_DIST:
			_exit_truck_silent()
			_quick_to_station()
	_ui_t -= dt
	if _ui_t <= 0.0:
		_ui_t = 0.15
		_refresh_hud(blocked)


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _refresh_hud(blocked: bool) -> void:
	hud.set_status(model.day, model.economy.money)
	var inst := model.incidents.active
	var state: String = inst.get("state", "")
	hud.set_timer(model.incidents.time_left() if state == IncidentDirector.ON_SCENE else -1.0)
	hud.set_objectives(_objective_lines())
	hud.set_controls_visible(not blocked)
	if blocked:
		return
	if truck.driving:
		hud.set_action("Exit\ntruck", absf(truck.speed) < 3.0, "")
	elif player.focus:
		var reason := player.focus.blocked_reason()
		hud.set_action(player.focus.get_prompt(), reason == "", reason)
	else:
		hud.set_action("", false, "")
	var can_order := site != null and not theo.is_busy() and model.incidents.check_task("secure_area") == ""
	hud.crew_button.visible = can_order and not truck.driving
	hud.crew_button.text = "Theo: cone it off"
	hud.crew_status.text = theo._status.text if site != null else ""
	var meter: Dictionary = site.meter() if site else {"value": -1.0, "label": ""}
	hud.set_bind(meter["value"], meter["label"], meter.get("color"))


func _objective_lines() -> Array:
	var inst := model.incidents.active
	var out: Array = []
	match inst.get("state", ""):
		"":
			if model.fragments.is_empty() and _call_t <= 0.0:
				out.append({"text": "Check the station board or end your shift", "done": false})
			else:
				out.append({"text": "Stand by for calls", "done": false})
		IncidentDirector.OFFERED:
			pass
		IncidentDirector.EN_ROUTE:
			var d := _flat_dist(truck.global_position, _site_anchor(inst))
			out.append({"text": "Drive to %s  (%d m)" % [inst["context"]["location_name"], int(d)], "done": false})
		IncidentDirector.ON_SCENE:
			out.append({"text": inst["title"], "done": false})
			for t in inst["tasks"]:
				var label: String = t["label"]
				if int(t["required"]) > 1:
					label += "  %d/%d" % [int(t["progress"]), int(t["required"])]
				elif float(t.get("auto_seconds", 0.0)) > 0.0 and model.incidents.check_task(t["id"], {"by": "auto"}) == "":
					label += "  %d%%" % int(model.auto_fraction(t["id"]) * 100)
				if t["optional"]:
					label += "  (recommended)"
				out.append({"text": ("✔ " if int(t["progress"]) >= int(t["required"]) else "• ") + label, "done": int(t["progress"]) >= int(t["required"])})
			if model.isolation_pending():
				out.append({"text": "  Utility isolating the line…", "done": false})
		IncidentDirector.RESOLVED:
			out.append({"text": "Return to the station", "done": false})
	return out
