class_name FloodedCellarSite
extends IncidentSite
## Flood-response site: storm drains backed up into the Mendes cellar.
## Hands-on chain: carry the pump → couple hose sections to the drain → clear the drain
## grate → pull-start the pump in rhythm (pull while the needle is in the green) →
## the water visibly drops while it pumps → check the cellar is safe.

const PUMP_SPOT := Vector3(5.2, 0, -1.6)
const DRAIN := Vector3(3.4, 0, -8.0)
const HATCH := Vector3(7.9, 0, 0.6)
const POOL := Vector3(6.6, 0, 2.0)
const GREEN_MIN := 0.7
const GREEN_MAX := 0.95
const PULL_COOLDOWN := 0.5

var pump: Node3D
var hose_points: Array = []
var debris: Array = []
var gauge := 0.0
var _gauge_t := 0.0
var _cooldown := 0.0
var _water: MeshInstance3D
var _outflow: CPUParticles3D
var _sparks: CPUParticles3D
var _live_label: Label3D
var _prime_it: Interactable
var _hose_nodes: Array = []


func _cone_offsets() -> Array:
	return [Vector3(-2.5, 0, -6.0), Vector3(0.5, 0, -10.0), Vector3(2.5, 0, -10.0), Vector3(-2.5, 0, 2.0), Vector3(2.5, 0, 6.0)]


func _build() -> void:
	# Flood water over the front garden and pavement.
	var wm := BoxMesh.new()
	wm.size = Vector3(3.6, 1.0, 6.0)
	_water = MeshInstance3D.new()
	_water.mesh = wm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.37, 0.62, 0.75, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	_water.material_override = mat
	add_child(_water)
	_set_water(1.0)
	# Cellar hatch against the house front.
	var hatch := Build.box(self, Vector3(1.0, 0.5, 1.4), HATCH + Vector3(0, 0.25, 0), Build.C_NAVY)
	hatch.rotation.z = -0.35
	Build.label(self, "CELLAR", HATCH + Vector3(0, 1.4, 0), 30, Build.C_CREAM)
	# Drain grate in the gutter.
	Build.box(self, Vector3(0.7, 0.05, 0.9), DRAIN + Vector3(0, 0.03, 0), Color(0.15, 0.15, 0.16))
	Build.label(self, "DRAIN", DRAIN + Vector3(0, 1.3, 0), 28, Build.C_AMBER)
	Build.box(self, Vector3(1.2, 0.03, 1.2), PUMP_SPOT + Vector3(0, 0.02, 0), Build.C_AMBER)
	_build_pump()
	_build_hose()
	_build_drain_debris()
	_build_prime()
	_build_make_safe()
	_build_people()
	if inst()["complications"].has("live_wire"):
		_build_fusebox()
	_outflow = CPUParticles3D.new()
	_outflow.position = DRAIN + Vector3(0, 0.3, 0)
	_outflow.amount = 20
	_outflow.lifetime = 0.5
	_outflow.direction = Vector3(-1, 0.4, 0)
	_outflow.spread = 15.0
	_outflow.initial_velocity_min = 1.5
	_outflow.initial_velocity_max = 2.5
	_outflow.scale_amount_min = 0.06
	_outflow.scale_amount_max = 0.1
	var om := BoxMesh.new()
	om.size = Vector3.ONE
	_outflow.mesh = om
	_outflow.material_override = Build.mat(Color(0.55, 0.75, 0.88))
	_outflow.emitting = false
	add_child(_outflow)


func _build_pump() -> void:
	pump = Node3D.new()
	pump.position = Vector3(2.8, 0, -12.0)
	add_child(pump)
	pump.set_meta("pump", true)
	Build.box(pump, Vector3(0.8, 0.5, 0.6), Vector3(0, 0.25, 0), Build.C_AMBER)
	Build.box(pump, Vector3(0.6, 0.25, 0.45), Vector3(0, 0.62, 0), Build.C_NAVY)
	Build.cyl(pump, 0.12, 0.2, Vector3(0.42, 0.3, 0), Color(0.2, 0.2, 0.22))
	var lift := Interactable.make(self, Vector3(2.8, 0, -11.2), "Lift pump", 1.4)
	lift.available = func() -> bool:
		return not model.incidents.is_task_done("place_pump") and player.carrying == null and pump.get_parent() == self
	lift.on_press = func() -> void:
		player.pick_up(pump)
		pump.rotation = Vector3.ZERO
		pump.position = Vector3(0, -0.6, -0.5)
		Audio.play("thud", -8.0, 1.2)
		message.emit("Set it down by the cellar steps")
	var drop := Interactable.make(self, PUMP_SPOT, "Set down pump", 1.8)
	drop.available = func() -> bool: return player.carrying == pump
	drop.on_press = func() -> void:
		var r := model.progress_task("place_pump")
		if not _report(r):
			return
		player.drop_carried()
		_put_pump_on_spot()
		Audio.play("thud", -4.0)


func _put_pump_on_spot() -> void:
	pump.reparent(self, false)
	pump.position = PUMP_SPOT
	pump.rotation = Vector3(0, 0.3, 0)
	pump.scale = Vector3.ONE


func _build_hose() -> void:
	var n := int(model.incidents.find_task("lay_hose")["required"])
	for i in n:
		var p: Vector3 = PUMP_SPOT.lerp(DRAIN, float(i + 1) / n)
		hose_points.append(p)
		var mark := Build.cyl(self, 0.18, 0.06, p + Vector3(0, 0.03, 0), Build.C_AMBER)
		mark.name = "HoseMark%d" % i
		var idx := i
		var it := _hold_interaction(p, "Hold: couple hose %d" % (i + 1), 0.8, 1.4, func() -> void:
			if _report(model.progress_task("lay_hose", {"index": idx})):
				_lay_segment(idx)
				Audio.play("click", -4.0, 0.6))
		it.available = func() -> bool:
			return player.carrying == null and int(model.incidents.find_task("lay_hose")["progress"]) == idx
		it.can_use = func() -> String: return model.incidents.check_task("lay_hose", {"index": idx})


func _lay_segment(i: int) -> void:
	var a: Vector3 = PUMP_SPOT if i == 0 else hose_points[i - 1]
	var b: Vector3 = hose_points[i]
	var seg := Build.cyl(self, 0.07, a.distance_to(b), Vector3.ZERO, Color(0.75, 0.2, 0.15), false, 6)
	seg.look_at_from_position(to_global((a + b) / 2 + Vector3(0, 0.08, 0)), to_global(b + Vector3(0, 0.08, 0)), Vector3.UP)
	seg.rotate_object_local(Vector3.RIGHT, PI / 2)
	_hose_nodes.append(seg)
	var mark := get_node_or_null("HoseMark%d" % i)
	if mark:
		mark.visible = false


func _build_drain_debris() -> void:
	var n := int(model.incidents.find_task("clear_drain")["required"])
	for j in n:
		var piece := Node3D.new()
		piece.position = DRAIN + Vector3(-0.5 + j * 0.5, 0, 0.6 - j * 0.5)
		add_child(piece)
		Build.sphere(piece, 0.35, Vector3(0, 0.2, 0), Build.C_LEAF, 6)
		var twig := Build.cyl(piece, 0.05, 1.0, Vector3(0, 0.25, 0), Build.C_BARK, false, 5)
		twig.rotation = Vector3(0, j, PI / 2)
		debris.append(piece)
		var idx := j
		var it := _hold_interaction(piece.position + Vector3(-0.8, 0, 0), "Hold: clear the drain", 1.0, 1.3, func() -> void:
			if _report(model.progress_task("clear_drain", {"index": idx})):
				piece.visible = false
				Audio.play("thud", -10.0, 1.6))
		it.available = func() -> bool: return player.carrying == null and not _done_indices("clear_drain").has(idx)


func _build_prime() -> void:
	_prime_it = Interactable.make(self, PUMP_SPOT + Vector3(-1.0, 0, 0), "Pull start", 1.5)
	_prime_it.available = func() -> bool:
		return model.incidents.is_task_done("place_pump") and not model.incidents.is_task_done("prime_pump") and player.carrying == null
	_prime_it.can_use = func() -> String:
		var reason := model.incidents.check_task("prime_pump")
		if reason == "" and _cooldown > 0.0:
			return "Let the cord rewind…"
		return reason
	_prime_it.prompt_fn = func() -> String: return "Pull when\nin the green"
	_prime_it.on_press = func() -> void:
		_cooldown = PULL_COOLDOWN
		if gauge >= GREEN_MIN and gauge <= GREEN_MAX:
			var r := model.progress_task("prime_pump")
			if _report(r):
				Audio.play("thud", -6.0, 0.7)
				if r.get("completed", false):
					message.emit("Pump's running!")
					Audio.loop_start("engine", -12.0)
				else:
					message.emit("Good pull — again!")
		else:
			Audio.play("stall", -8.0, 1.4)
			message.emit("Too early — pull in the green")


func _build_make_safe() -> void:
	var it := _hold_interaction(HATCH + Vector3(-1.2, 0, 0), "Hold: check the cellar", 1.2, 1.6, func() -> void:
		hide_cones()
		Audio.loop_stop("engine")
		_report(model.progress_task("make_safe")))
	it.available = func() -> bool: return model.incidents.check_task("make_safe") == ""


func _build_people() -> void:
	var rosa := Build.person(self, Color(0.43, 0.29, 0.42), Color(0.85, 0.64, 0.49))
	rosa.position = Vector3(8.0, 0, 5.6)
	rosa.rotation.y = PI / 2
	Build.label(rosa, "Rosa", Vector3(0, 2.2, 0), 28)
	if inst()["flags"].get("tomas_helps", false):
		var tomas := Build.person(self, Color(0.30, 0.42, 0.56), Color(0.85, 0.64, 0.49))
		tomas.position = HATCH + Vector3(-0.6, 0, -1.2)
		tomas.scale = Vector3.ONE * 0.7
		tomas.rotation.y = PI / 2
		Build.label(tomas, "Tomás (torch)", Vector3(0, 2.6, 0), 34)
		var torch := Build.cyl(tomas, 0.06, 0.35, Vector3(0.35, 1.0, -0.2), Build.C_AMBER)
		torch.material_override = Build.mat(Build.C_AMBER, true)


func _build_fusebox() -> void:
	_sparks = CPUParticles3D.new()
	_sparks.position = HATCH + Vector3(0, 0.6, 0)
	_sparks.amount = 14
	_sparks.lifetime = 0.35
	_sparks.direction = Vector3(-1, 1, 0)
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 2.0
	_sparks.initial_velocity_max = 3.5
	_sparks.scale_amount_min = 0.04
	_sparks.scale_amount_max = 0.07
	var sm := BoxMesh.new()
	sm.size = Vector3.ONE
	_sparks.mesh = sm
	_sparks.material_override = Build.mat(Color(1.0, 0.85, 0.3), true)
	add_child(_sparks)
	_live_label = Build.label(self, "LIVE: FUSE BOX", HATCH + Vector3(0, 2.0, 0), 32, Color(1.0, 0.8, 0.2))


func _sync_from_model() -> void:
	if model.incidents.is_task_done("place_pump"):
		_put_pump_on_spot()
	for i in int(model.incidents.find_task("lay_hose")["progress"]):
		_lay_segment(i)
	for j in _done_indices("clear_drain"):
		debris[int(j)].visible = false
	if model.incidents.is_task_done("prime_pump") and not model.incidents.is_task_done("pump_out"):
		Audio.loop_start("engine", -12.0)


func _set_water(level: float) -> void:
	var h := 0.02 + 0.32 * level
	_water.scale = Vector3(1, h, 1)
	_water.position = POOL + Vector3(0, h / 2.0, 0)


func meter() -> Dictionary:
	if player.focus == _prime_it and _prime_it.is_available():
		var good := gauge >= GREEN_MIN and gauge <= GREEN_MAX
		return {"value": gauge, "label": "PULL IN THE GREEN", "color": Color(0.4, 0.85, 0.4) if good else Color(0.95, 0.66, 0.23)}
	if model.incidents.is_task_done("prime_pump") and not model.incidents.is_task_done("pump_out"):
		return {"value": model.auto_fraction("pump_out"), "label": "PUMPING", "color": Color(0.37, 0.62, 0.75)}
	return {"value": -1.0, "label": ""}


func stop_actions() -> void:
	Audio.loop_stop("engine")


func _process(dt: float) -> void:
	_gauge_t += dt
	gauge = 0.5 + 0.5 * sin(_gauge_t * 3.2)
	_cooldown = maxf(0.0, _cooldown - dt)
	var pumping := model.incidents.is_task_done("prime_pump") and not model.incidents.is_task_done("pump_out")
	var f := model.auto_fraction("pump_out")
	_set_water(1.0 - f)
	_outflow.emitting = pumping
	if pumping:
		pump.position.y = absf(sin(_gauge_t * 40.0)) * 0.02
	if _sparks:
		var live := not model.incidents.is_task_done("isolate_power")
		_sparks.emitting = live
		_live_label.visible = live
