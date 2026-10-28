extends Node
## End-to-end playthrough bot used as the integration test (godot ... -- --autoplay).
## It plays through the same entry points as touch input (stick vector, action button,
## HUD signals) — it never calls GameModel rules directly — so a pass means the real
## scene wiring works: dispatch, driving, delegation, cutting, carrying, outcome,
## return, story, station board, end shift, save/reload and a failure consequence.
## Options: --seed=N  --quick (skip driving)  --shots=<abs dir> (needs a rendering run)

var main
var failures: Array = []
var steps: Array = []
var shots_dir := ""
var seed_value := 4242
var drive := true
var perf: Dictionary = {}
var _t0 := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.get_slice("=", 1)
		elif a.begins_with("--seed="):
			seed_value = int(a.get_slice("=", 1))
		elif a == "--quick":
			drive = false
	main.bot_active = true
	_t0 = Time.get_ticks_msec()
	_run.call_deferred()


func fail(msg: String) -> void:
	failures.append(msg)
	print("  [autoplay] FAIL: ", msg)


func step(msg: String) -> void:
	steps.append(msg)
	print("  [autoplay] ", msg)


func expect(cond: bool, msg: String) -> void:
	if cond:
		step("ok  " + msg)
	else:
		fail(msg)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _until(cond: Callable, timeout: float, what: String) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		if t > timeout:
			fail("timed out waiting for " + what)
			return false
	return true


func _model() -> GameModel:
	return Game.model


func shot(name: String) -> void:
	if shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [shots_dir, name])
	step("screenshot " + name)


func sample_perf(label: String) -> void:
	await _wait(1.0)
	perf[label] = {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
	}


func drain_dialogue() -> void:
	await _wait(0.3)
	var guard := 0
	while (main.hud.dialogue_panel.visible or not _model().fragments.is_empty()) and guard < 40:
		main._next_line()
		guard += 1
		await _wait(0.15)


## Walks straight at the target; when blocked (e.g. by the truck body) it sidesteps
## perpendicular for a moment, alternating sides, like a player steering around.
func walk_to(p: Vector3, within: float = 0.5, timeout: float = 25.0) -> bool:
	# Route around the parked truck via its nearest corner, as a player would.
	var tr: Truck = main.truck
	var from: Vector3 = main.player.global_position
	if not tr.driving and _crosses_truck(from, p):
		var best := Vector3.ZERO
		var best_len := INF
		for cx in [-2.2, 2.2]:
			for cz in [-4.2, 4.2]:
				var c: Vector3 = tr.global_transform * Vector3(cx, 0, cz)
				var l := from.distance_to(c) + c.distance_to(p)
				if l < best_len and not _crosses_truck(from, c):
					best = c
					best_len = l
		if best_len < INF:
			await _walk_direct(best, 0.6, timeout)
	return await _walk_direct(p, within, timeout)


func _crosses_truck(a: Vector3, b: Vector3) -> bool:
	var inv: Transform3D = main.truck.global_transform.affine_inverse()
	for k in 21:
		var q: Vector3 = inv * a.lerp(b, k / 20.0)
		if absf(q.x) < 1.7 and absf(q.z) < 3.6:
			return true
	return false


func _walk_direct(p: Vector3, within: float, timeout: float) -> bool:
	var t := 0.0
	var last: Vector3 = main.player.global_position
	var stuck := 0.0
	var detour := 0.0
	var side := 1.0
	while true:
		var d: Vector3 = p - main.player.global_position
		d.y = 0.0
		if d.length() <= within:
			main.bot_input = Vector2.ZERO
			await get_tree().physics_frame
			main.player.rescan()
			return true
		var want := d.normalized()
		if detour > 0.0:
			detour -= 1.0 / Engine.physics_ticks_per_second
			want = (want.cross(Vector3.UP) * side + want * 0.15).normalized()
		var local := want.rotated(Vector3.UP, -main.rig.yaw)
		main.bot_input = Vector2(local.x, -local.z) * clampf(d.length() / 0.8, 0.35, 1.0)
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var moved: float = main.player.global_position.distance_to(last)
		last = main.player.global_position
		stuck = stuck + 1.0 / Engine.physics_ticks_per_second if moved < 0.02 else 0.0
		if stuck > 0.25 and detour <= 0.0:
			detour = 1.2
			side = -side
			stuck = 0.0
		if t > timeout:
			main.bot_input = Vector2.ZERO
			fail("could not walk to %s (stuck at %s)" % [p, main.player.global_position])
			main.player.teleport(p)
			return false
	return false


func press() -> void:
	main._action_down()
	await get_tree().physics_frame
	main._action_up()
	await _wait(0.1)


func drive_route(points: Array, stop_when: Callable, timeout: float = 120.0) -> bool:
	var t := 0.0
	for wp in points:
		while true:
			if stop_when.call():
				main.bot_input = Vector2.ZERO
				return true
			var tr: Truck = main.truck
			var to: Vector3 = wp - tr.global_position
			to.y = 0.0
			if to.length() < 4.0:
				break
			var fwd := -tr.global_transform.basis.z
			var angle := fwd.signed_angle_to(to.normalized(), Vector3.UP)
			var throttle := 1.0 if absf(angle) < 0.4 else 0.45
			main.bot_input = Vector2(clampf(-angle * 2.5, -1.0, 1.0), throttle)
			await get_tree().physics_frame
			t += 1.0 / Engine.physics_ticks_per_second
			if t > timeout:
				fail("drive timed out near %s" % tr.global_position)
				return false
	main.bot_input = Vector2.ZERO
	return await _until(stop_when, 8.0, "arrival after route")


func _hold_until(cond: Callable, timeout: float) -> void:
	main.player.rescan()
	main._action_down()
	var t := 0.0
	while not cond.call() and t < timeout:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	main._action_up()
	await _wait(0.1)


func truck_point(which: String) -> Vector3:
	return main.truck.global_transform * main.truck.point(which)


func _run() -> void:
	Game.save_path = "user://autoplay.save"
	SaveSystem.delete(Game.save_path)
	Game.new_game(seed_value)
	var m := _model()
	step("new game seed=%d" % seed_value)
	expect(main.hud.dialogue_panel.visible, "intro dialogue shown")
	await shot("01_intro")
	await drain_dialogue()
	await sample_perf("station")
	await shot("02_station")

	# --- Call & dispatch ---
	await _until(func() -> bool: return main.hud.dispatch_panel.visible, 20.0, "incoming call")
	var inst: Dictionary = m.incidents.active
	step("call %s: %s sev=%d weather=%s complications=%s" % [inst["uid"], inst["location"], inst["severity"], inst["weather"], inst["complications"]])
	await shot("03_dispatch")
	main.hud.dispatch_panel.visible = false
	main._on_dispatch("drive" if drive else "quick")
	if drive:
		await walk_to(truck_point("driver"), 0.6)
		await press()
		expect(main.truck.driving, "entered truck")
		var x: float = main._site_anchor(inst).x
		var arrived := func() -> bool: return m.incidents.active.get("state", "") == IncidentDirector.ON_SCENE
		await _wait(2.0)
		await shot("04_driving")
		var ok := await drive_route([Vector3(0, 0, 1.5), Vector3(x, 0, 1.5), Vector3(x, 0, 40)], arrived)
		expect(ok, "truck drove to the incident")
	await _until(func() -> bool: return m.incidents.active.get("state", "") == IncidentDirector.ON_SCENE, 10.0, "on scene")
	expect(main.site != null, "incident site spawned")
	await drain_dialogue()
	await shot("05_on_scene")

	# --- Delegate cones, fetch saw, isolate power ---
	main._on_crew_order()
	expect(main.theo.is_busy(), "Theo assigned to cone off")
	await walk_to(truck_point("locker"), 0.5)
	await press()
	expect(main.player.has_saw, "took chainsaw")
	if inst["complications"].has("live_wire"):
		await walk_to(truck_point("radio"), 0.5)
		await press()
		await _until(func() -> bool: return m.incidents.is_task_done("isolate_power"), 15.0, "line isolated")
		expect(m.incidents.is_task_done("isolate_power"), "utility isolated the live line")
	await _until(func() -> bool: return m.incidents.is_task_done("secure_area"), 40.0, "Theo cones")
	expect(m.incidents.active["flags"].get("delegated_secure", false), "Theo secured the scene")
	await shot("06_secured")
	await sample_perf("on_scene")

	# --- Cut, lift, stack ---
	var site: FallenTreeSite = main.site
	var stalls := 0
	for i in site.n:
		var seg: Node3D = site.segments[i]
		await walk_to(seg.global_position + Vector3(0, 0, -1.0), 0.4)
		main.player.rescan()
		main._action_down()
		var t := 0.0
		while not m.incidents.find_task("cut_trunk")["done_indices"].has(i) and t < 25.0:
			if site.stall_t > 0.0:
				stalls += 1
				await _until(func() -> bool: return site.stall_t <= 0.0, 3.0, "stall clear")
			if site.bind > 0.72:
				main._action_up()
				await _until(func() -> bool: return site.bind < 0.1, 3.0, "bind ease")
				main._action_down()
			if i == 0 and t > 0.6 and t < 0.62:
				await shot("07_cutting")
			await get_tree().physics_frame
			t += 1.0 / Engine.physics_ticks_per_second
		main._action_up()
		expect(m.incidents.find_task("cut_trunk")["done_indices"].has(i), "cut section %d (%.1fs)" % [i, t])
		await _wait(0.4)
		await walk_to(seg.global_position + Vector3(0, -seg.global_position.y, -0.9), 0.4)
		await press()
		expect(main.player.carrying == seg, "lifted log %d" % i)
		await walk_to(site._zone.global_position, 0.8)
		if i == 0:
			await shot("08_carrying")
		await press()
		expect(m.incidents.find_task("clear_debris")["done_indices"].has(i), "stacked log %d" % i)
	step("chain stalls during play: %d" % stalls)
	expect(not m.incidents.active["flags"].get("unsafe_cut", false), "no unsafe cut")

	# --- Reopen & outcome ---
	await walk_to(site.global_position + Vector3(0, 0, -3.0), 0.5)
	main._action_down()
	await _until(func() -> bool: return main.hud.result_panel.visible, 5.0, "result panel")
	main._action_up()
	expect(m.last_result.get("outcome", "") == "success", "incident resolved as success")
	expect(m.world.get_value("%s.road" % inst["location"]) == "open", "road recorded open in world state")
	await shot("09_result")

	# --- Return ---
	main.hud.result_panel.visible = false
	main._on_return("drive" if drive else "quick")
	if drive:
		await walk_to(truck_point("driver"), 0.6)
		await press()
		var x2: float = main._site_anchor(inst).x
		var back := func() -> bool: return m.incidents.active.is_empty()
		var ok2 := await drive_route([Vector3(x2, 0, 1.5), Vector3(0, 0, 1.5), Vector3(0, 0, -6)], back)
		expect(ok2, "drove back to the station")
	await _until(func() -> bool: return m.incidents.active.is_empty(), 10.0, "returned")
	expect(m.incidents.history.size() == 1, "one incident in history")
	await drain_dialogue()
	await shot("10_back_at_station")

	# --- Station board, upgrade, end shift ---
	await walk_to(Vector3(-8.5, 0, -11.0), 0.5)
	await press()
	expect(main.hud.dashboard_panel.visible, "station board opened")
	await shot("11_board")
	var money_before := m.economy.money
	main.hud.project_bought.emit("service_chainsaw")
	expect(m.equipment.get("chainsaw", 1) == 2 and m.economy.money == money_before - 150, "chainsaw serviced (£150)")
	main.hud.dashboard_panel.visible = false
	main.hud.end_shift_pressed.emit()
	expect(m.day == 2, "shift ended, day 2")
	await drain_dialogue()
	expect(m.story.fired.has("rosa_pastries") == m.flags.get("helped_rosa_mendes", false), "next-day consequence matches who was helped")

	# --- Save / reload integrity through the real autoload ---
	Game.save_game()
	var before := SaveSystem.canonical(m.to_dict())
	expect(Game.continue_game(), "reloaded save")
	m = _model()
	expect(SaveSystem.canonical(m.to_dict()) == before, "reloaded state identical")

	# --- Day 2: story incident — flooded Mendes cellar (second hands-on family) ---
	await _until(func() -> bool: return main.hud.dispatch_panel.visible, 20.0, "day-2 call")
	var flood: Dictionary = m.incidents.active
	expect(flood["def_id"] == "flooded_cellar", "day-2 call is the Mendes cellar flood")
	expect(flood["flags"].get("tomas_helps", false) == m.flags.get("helped_rosa_mendes", false), "Tomás helps only if Rosa was helped")
	main.hud.dispatch_panel.visible = false
	main._on_dispatch("quick")
	await drain_dialogue()
	await shot("14_flood_arrival")
	var fs: FloodedCellarSite = main.site
	main._on_crew_order()
	await walk_to(truck_point("radio"), 0.5)
	await press()
	await walk_to(fs.to_global(Vector3(2.8, 0, -11.2)), 0.4)
	await press()
	expect(main.player.carrying == fs.pump, "lifted the pump")
	await walk_to(fs.to_global(FloodedCellarSite.PUMP_SPOT), 0.5)
	await press()
	expect(m.incidents.is_task_done("place_pump"), "pump placed at the cellar steps")
	for i in fs.hose_points.size():
		await walk_to(fs.to_global(fs.hose_points[i]), 0.35)
		await _hold_until(func() -> bool: return int(m.incidents.find_task("lay_hose")["progress"]) > i, 4.0)
	expect(m.incidents.is_task_done("lay_hose"), "hose coupled to the drain")
	for j in fs.debris.size():
		await walk_to(fs.debris[j].global_position + Vector3(-0.8, 0, 0), 0.35)
		await _hold_until(func() -> bool: return m.incidents.find_task("clear_drain")["done_indices"].has(j), 4.0)
	expect(m.incidents.is_task_done("clear_drain"), "drain cleared")
	await _until(func() -> bool: return m.incidents.is_task_done("isolate_power"), 15.0, "house supply cut")
	await walk_to(fs.to_global(FloodedCellarSite.PUMP_SPOT + Vector3(-1.0, 0, 0)), 0.4)
	var misses := 0
	var t2 := 0.0
	while not m.incidents.is_task_done("prime_pump") and t2 < 30.0:
		if fs.gauge > 0.76 and fs.gauge < 0.9 and fs._cooldown <= 0.0:
			await press()
		elif misses == 0:
			await press()  # one deliberate early pull to exercise the miss path
			misses += 1
		await get_tree().physics_frame
		t2 += 1.0 / Engine.physics_ticks_per_second
	expect(m.incidents.is_task_done("prime_pump"), "pump primed by rhythm pulls (%d deliberate miss)" % misses)
	await _wait(3.0)
	await shot("15_pumping")
	await _until(func() -> bool: return m.incidents.is_task_done("pump_out"), 90.0, "cellar pumped dry")
	await walk_to(fs.to_global(FloodedCellarSite.HATCH + Vector3(-1.2, 0, 0)), 0.4)
	await _hold_until(func() -> bool: return main.hud.result_panel.visible, 4.0)
	expect(m.last_result.get("outcome", "") == "success", "flood resolved as success")
	expect(m.world.get_value("house_mendes.cellar") == "dry", "cellar state persisted")
	await shot("16_flood_result")
	main.hud.result_panel.visible = false
	main._on_return("quick")
	await drain_dialogue()
	expect(m.story.fired.has("cellar_saved"), "Rosa reacts to the saved cellar")
	main.hud.end_shift_pressed.emit()
	await drain_dialogue()
	expect(m.day == 3, "day 3")

	# --- Day 3: routine call, abandoned -> persistent damage ---
	await _until(func() -> bool: return main.hud.dispatch_panel.visible, 20.0, "day-3 call")
	var inst2: Dictionary = m.incidents.active
	expect(inst2["def_id"] == "fallen_tree" and inst2["location"] != "alder_lane", "routine tree call on another street (%s)" % inst2["location"])
	main.hud.dispatch_panel.visible = false
	main._on_dispatch("quick")
	await drain_dialogue()
	main._on_pause_choice("abandon")
	await _until(func() -> bool: return main.hud.result_panel.visible, 5.0, "failure result")
	expect(m.last_result.get("outcome", "") == "failure", "abandon handled as failure")
	await shot("17_failure")
	main.hud.result_panel.visible = false
	main._on_return("quick")
	var house: String = inst2["context"]["house"]
	expect(m.world.get_value("%s.roof" % house) == "damaged", "roof damage recorded for %s" % house)
	expect(m.available_projects().any(func(p: Dictionary) -> bool: return p["id"] == "repair_roof_%s" % house), "repair project unlocked")
	var look := Node3D.new()
	main.add_child(look)
	look.global_position = main._site_anchor(inst2) + Vector3(10, 0, 3)
	main.rig.target = look
	main.rig.mode = "tactical"
	main.rig.walk_yaw = -PI / 2
	main.rig.snap()
	await _wait(0.5)
	await shot("18_roof_damage_persists")
	main.rig.mode = "walk"
	main.rig.target = main.player
	await drain_dialogue()
	Game.save_game()

	# --- Report ---
	var secs := (Time.get_ticks_msec() - _t0) / 1000.0
	print("\nAUTOPLAY PERF ", JSON.stringify(perf))
	print("AUTOPLAY money=%d day=%d history=%d wall=%.1fs" % [m.economy.money, m.day, m.incidents.history.size(), secs])
	if failures.is_empty():
		print("AUTOPLAY PASS (%d checks)" % steps.size())
		get_tree().quit(0)
	else:
		print("AUTOPLAY FAIL (%d failures)" % failures.size())
		for f in failures:
			print("  - ", f)
		get_tree().quit(1)
