class_name FallenTreeSite
extends IncidentSite
## Debris-removal incident site: a storm-felled oak across a residential lane.
## Owns the visuals and the hands-on interactions; every rule decision is delegated to
## GameModel.progress_task so the scene can never disagree with the saved simulation.
##
## Chainsaw feel: holding the action cuts, but the chain "binds" if you lean on it.
## Let off before the bind meter fills or the saw stalls for a moment.

const ROAD_HALF := 4.0
const STALL_TIME := 1.2
const BASE_CUT_RATE := 0.42
const BASE_BIND_RATE := 0.55

var n := 0
var cut_progress: Array = []
var bind := 0.0
var stall_t := 0.0
var cutting := -1
var segments: Array = []
var cut_marks: Array = []
var pile_count := 0

var _zone: Node3D
var _trunk_body: StaticBody3D
var _sawdust: CPUParticles3D
var _sparks: CPUParticles3D
var _wire: Node3D
var _cut_rate := BASE_CUT_RATE
var _bind_rate := BASE_BIND_RATE


func _prepare() -> void:
	var level := int(model.equipment.get("chainsaw", 1))
	_cut_rate = BASE_CUT_RATE * (1.35 if level >= 2 else 1.0)
	_bind_rate = BASE_BIND_RATE * (0.7 if level >= 2 else 1.0)
	n = int(model.incidents.find_task("cut_trunk")["required"])
	for i in n:
		cut_progress.append(0.0)


func _build() -> void:
	var seg_len := ROAD_HALF * 2.0 / n
	# Root plate on the -x verge, canopy resting in the +x garden.
	if AssetLib.spawn("root_plate", self, Vector3(-ROAD_HALF - 1.6, 0, 0), PI / 2) == null:
		var root := Build.cyl(self, 1.3, 0.5, Vector3(-ROAD_HALF - 1.6, 1.1, 0), Build.C_BARK, false, 10)
		root.rotation.z = PI / 2
		Build.sphere(self, 0.9, Vector3(-ROAD_HALF - 1.8, 0.6, 0.3), Color(0.35, 0.26, 0.18), 8)
	if AssetLib.spawn("canopy_cluster", self, Vector3(ROAD_HALF + 2.6, 0, 0), -PI / 2) == null:
		var canopy := Node3D.new()
		add_child(canopy)
		for k in 5:
			Build.sphere(canopy, 1.2 + 0.2 * (k % 2), Vector3(ROAD_HALF + 1.4 + k * 0.9, 0.9 + (k % 2) * 0.6, -1.2 + (k % 3) * 1.1), Build.C_LEAF, 8)
		var stub := Build.cyl(canopy, 0.34, 2.4, Vector3(ROAD_HALF + 1.2, 0.4, 0), Build.C_BARK)
		stub.rotation.z = PI / 2
	for i in n:
		var seg := Node3D.new()
		seg.position = Vector3(-ROAD_HALF + seg_len * (i + 0.5), 0.4, 0)
		add_child(seg)
		# log_section is authored 1 m long along X with its pivot at the base centre.
		if AssetLib.spawn("log_section", seg, Vector3(0, -0.36, 0), 0.0, Vector3(seg_len - 0.04, 1, 1)) == null:
			var m := Build.cyl(seg, 0.36, seg_len - 0.04, Vector3.ZERO, Build.C_BARK, false, 10)
			m.rotation.z = PI / 2
			for end in [-1.0, 1.0]:
				var face := Build.cyl(seg, 0.33, 0.02, Vector3(end * (seg_len / 2 - 0.01), 0, 0), Build.C_WOOD)
				face.rotation.z = PI / 2
		segments.append(seg)
		var mark := Build.cyl(self, 0.42, 0.08, seg.position + Vector3(0, 0, 0), Build.C_AMBER)
		mark.rotation.z = PI / 2
		mark.scale = Vector3(1, 1, 1)
		cut_marks.append(mark)
		_make_cut_interaction(i, seg.position)
		_make_log_interaction(i, seg)
	# Truck must not drive through the trunk; crew may step over it (layer 3).
	_trunk_body = Build.static_box(self, Vector3(ROAD_HALF * 2 + 2, 1.0, 0.8), Vector3(0, 0.5, 0))
	_trunk_body.collision_layer = 4
	_trunk_body.collision_mask = 0
	_sawdust = CPUParticles3D.new()
	_sawdust.emitting = false
	_sawdust.amount = 24
	_sawdust.lifetime = 0.6
	_sawdust.direction = Vector3(0, 1, 0.4)
	_sawdust.spread = 35.0
	_sawdust.initial_velocity_min = 2.0
	_sawdust.initial_velocity_max = 3.5
	_sawdust.gravity = Vector3(0, -9, 0)
	_sawdust.scale_amount_min = 0.05
	_sawdust.scale_amount_max = 0.09
	var dust := BoxMesh.new()
	dust.size = Vector3.ONE
	_sawdust.mesh = dust
	_sawdust.material_override = Build.mat(Build.C_WOOD)
	add_child(_sawdust)
	_build_debris_zone()
	_build_reopen()
	if inst()["complications"].has("live_wire"):
		_build_wire()


func _make_cut_interaction(i: int, at: Vector3) -> void:
	var it := Interactable.make(self, at + Vector3(0, 0, -1.0), "Cut section", 1.6)
	it.hold = true
	it.available = func() -> bool: return not _done_indices("cut_trunk").has(i) and player.carrying == null
	it.can_use = func() -> String: return model.incidents.check_task("cut_trunk", {"equipped": player.equipped(), "index": i})
	it.prompt_fn = func() -> String: return "Stalled!" if stall_t > 0.0 else "Hold: cut section %d" % (i + 1)
	it.on_press = func() -> void: _start_cut(i)
	it.on_hold = func(dt: float) -> void: _hold_cut(i, dt)
	it.on_release = func() -> void: _stop_cut()


func _make_log_interaction(i: int, seg: Node3D) -> void:
	var it := Interactable.make(self, seg.position + Vector3(0, 0, -0.9), "Lift log", 1.6)
	it.available = func() -> bool:
		return _done_indices("cut_trunk").has(i) and not _done_indices("clear_debris").has(i) and player.carrying == null and seg.get_parent() == self
	it.on_press = func() -> void:
		player.pick_up(seg)
		seg.set_meta("log_index", i)
		Audio.play("thud", -8.0, 1.4)
		message.emit("Carry it to the verge pile")


func _build_debris_zone() -> void:
	var zone := Node3D.new()
	zone.position = Vector3(-ROAD_HALF - 3.2, 0, -4.0)
	add_child(zone)
	_zone = zone
	var pad := Build.box(zone, Vector3(2.8, 0.03, 2.4), Vector3(0, 0.03, 0), Build.C_AMBER)
	pad.transparency = 0.0
	Build.label(zone, "LOG PILE", Vector3(0, 1.6, 0), 32, Build.C_AMBER)
	var it := Interactable.make(zone, Vector3.ZERO, "Stack log", 2.4)
	it.available = func() -> bool: return player.carrying != null and player.carrying.has_meta("log_index")
	it.on_press = func() -> void:
		var log_node := player.carrying
		var idx := int(log_node.get_meta("log_index"))
		var r := model.progress_task("clear_debris", {"index": idx})
		if not r["ok"]:
			message.emit(r["reason"])
			return
		player.drop_carried()
		_place_in_pile(log_node)
		Audio.play("thud", -4.0)
		_report(r)


func _place_in_pile(log_node: Node3D) -> void:
	log_node.reparent(_zone, false)
	log_node.position = Vector3(0, 0.35 + (pile_count / 2) * 0.62, -0.4 + (pile_count % 2) * 0.72)
	log_node.rotation = Vector3.ZERO
	log_node.scale = Vector3(0.9, 0.9, 0.9)
	pile_count += 1


func _build_reopen() -> void:
	var it := _hold_interaction(Vector3(0, 0, -3.0), "Hold: reopen the road", 1.2, 2.2, func() -> void:
		hide_cones()
		_trunk_body.queue_free()
		_report(model.progress_task("reopen_road")))
	it.available = func() -> bool: return model.incidents.check_task("reopen_road") == ""


func _build_wire() -> void:
	_wire = Node3D.new()
	add_child(_wire)
	var pole := Build.cyl(_wire, 0.14, 7.0, Vector3(ROAD_HALF + 1.0, 3.5, -3.5), Build.C_BARK, true, 6)
	pole.name = "Pole"
	var cable := Build.cyl(_wire, 0.03, 6.2, Vector3(ROAD_HALF - 0.6, 3.3, -1.8), Color(0.05, 0.05, 0.05), false, 4)
	cable.rotation = Vector3(0.5, 0, 0.75)
	_sparks = CPUParticles3D.new()
	_sparks.position = Vector3(ROAD_HALF - 2.0, 0.8, -0.3)
	_sparks.amount = 16
	_sparks.lifetime = 0.35
	_sparks.direction = Vector3(0, 1, 0)
	_sparks.spread = 80.0
	_sparks.initial_velocity_min = 2.0
	_sparks.initial_velocity_max = 4.0
	_sparks.scale_amount_min = 0.04
	_sparks.scale_amount_max = 0.07
	var sm := BoxMesh.new()
	sm.size = Vector3.ONE
	_sparks.mesh = sm
	_sparks.material_override = Build.mat(Color(1.0, 0.85, 0.3), true)
	_wire.add_child(_sparks)
	Build.label(_wire, "LIVE LINE", Vector3(ROAD_HALF - 2.0, 2.0, -0.3), 34, Color(1.0, 0.8, 0.2))


func _sync_from_model() -> void:
	var cut := _done_indices("cut_trunk")
	var cleared := _done_indices("clear_debris")
	for i in n:
		if cut.has(i):
			_mark_cut(i, false)
		if cleared.has(i):
			_place_in_pile(segments[i])
	_update_wire()


func _update_wire() -> void:
	if _sparks:
		var live := not model.incidents.is_task_done("isolate_power")
		_sparks.emitting = live
		_wire.get_child(_wire.get_child_count() - 1).visible = live


func _start_cut(i: int) -> void:
	cutting = i
	Audio.loop_start("saw", -6.0)


func _hold_cut(i: int, dt: float) -> void:
	if cutting != i:
		return
	if stall_t > 0.0:
		return
	bind += _bind_rate * dt
	if bind >= 1.0:
		stall_t = STALL_TIME
		bind = 0.35
		_sawdust.emitting = false
		Audio.loop_stop("saw")
		Audio.play("stall")
		message.emit("Chain bound up! Ease off sooner.")
		return
	cut_progress[i] = float(cut_progress[i]) + _cut_rate * dt
	_sawdust.position = (segments[i] as Node3D).position + Vector3(0, 0.35, -0.2)
	_sawdust.emitting = true
	Audio.loop_set("saw", 1.0 + bind * 0.7 + 0.2, -4.0)
	var seg: Node3D = segments[i]
	seg.position.y = 0.4 + sin(Time.get_ticks_msec() * 0.08) * 0.015
	(cut_marks[i] as Node3D).scale = Vector3.ONE * (1.0 - float(cut_progress[i]) * 0.5)
	(cut_marks[i] as MeshInstance3D).material_override = Build.mat(Build.C_AMBER.lerp(Build.C_RED, bind))
	if float(cut_progress[i]) >= 1.0:
		var r := model.progress_task("cut_trunk", {"equipped": player.equipped(), "index": i})
		_stop_cut()
		if not r["ok"]:
			message.emit(r["reason"])
			return
		if r.get("warning", "") == "unsafe_cut":
			message.emit("Scene wasn't coned off!")
		_mark_cut(i, true)
		_report(r)


func stop_actions() -> void:
	_stop_cut()


func _stop_cut() -> void:
	cutting = -1
	_sawdust.emitting = false
	Audio.loop_stop("saw")


func _mark_cut(i: int, animate: bool) -> void:
	var mark: Node3D = cut_marks[i]
	mark.visible = false
	var seg: Node3D = segments[i]
	var target_rot := Vector3(0, (i % 2 - 0.5) * 0.25, 0)
	if animate:
		var tw := create_tween()
		tw.tween_property(seg, "position:y", 0.36, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(seg, "rotation", target_rot, 0.25)
		Audio.play("thud", -6.0, 0.9)
	else:
		seg.position.y = 0.36
		seg.rotation = target_rot


func _process(dt: float) -> void:
	if stall_t > 0.0:
		stall_t -= dt
		if stall_t <= 0.0 and cutting >= 0:
			Audio.loop_start("saw", -6.0)
	if cutting < 0 or stall_t > 0.0:
		bind = maxf(0.0, bind - 1.3 * dt)
	_update_wire()


## Chain-bind meter for the HUD; hidden when not cutting.
func meter() -> Dictionary:
	return {"value": bind if cutting >= 0 or bind > 0.01 else -1.0, "label": "CHAIN BIND"}
