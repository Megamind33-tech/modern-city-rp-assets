class_name IncidentSite
extends Node3D
## Shared base for hands-on incident sites: scene cones, messages, the HUD meter and
## helpers that route every rule decision through GameModel.progress_task.
## Subclasses implement _build() and _sync_from_model().

signal message(text: String)

var model: GameModel
var player: Player
var anchor := Vector3.ZERO
var cones: Array = []
var cone_points: Array = []


func setup(game_model: GameModel, p: Player, anchor_pos: Vector3) -> void:
	model = game_model
	player = p
	anchor = anchor_pos
	position = anchor
	_prepare()
	_build()
	_build_cones()
	_sync_from_model()
	if model.incidents.is_task_done("secure_area"):
		show_all_cones()


func inst() -> Dictionary:
	return model.incidents.active


func _done_indices(task: String) -> Array:
	return model.incidents.find_task(task).get("done_indices", [])


func _prepare() -> void:
	pass


func _build() -> void:
	pass


func _sync_from_model() -> void:
	pass


## Meter for the HUD: value 0..1 (or < 0 to hide) and its caption.
func meter() -> Dictionary:
	return {"value": -1.0, "label": ""}


## Stop any running hands-on action (outcome screen, pause).
func stop_actions() -> void:
	pass


## Reports a model result: messages on refusal, chime on task completion.
func _report(r: Dictionary) -> bool:
	if not r["ok"]:
		message.emit(r["reason"])
		return false
	if r.get("completed", false) and not r.has("result"):
		Audio.play("chime", -10.0, 1.5)
	return true


## Default scene-perimeter points (local offsets): road both sides of the hazard.
func _cone_offsets() -> Array:
	return [Vector3(-3.0, 0, -5.0), Vector3(0.0, 0, -5.5), Vector3(3.0, 0, -5.0), Vector3(-3.0, 0, 5.0), Vector3(3.0, 0, 5.0)]


func _build_cones() -> void:
	for off in _cone_offsets():
		cone_points.append(anchor + off)
		var c := Node3D.new()
		c.position = off
		add_child(c)
		if AssetLib.spawn("traffic_cone", c) == null:
			var cone_mesh := CylinderMesh.new()
			cone_mesh.top_radius = 0.04
			cone_mesh.bottom_radius = 0.25
			cone_mesh.height = 0.7
			cone_mesh.radial_segments = 8
			var mi := MeshInstance3D.new()
			mi.mesh = cone_mesh
			mi.material_override = Build.mat(Color(1.0, 0.45, 0.1))
			mi.position.y = 0.35
			c.add_child(mi)
			Build.cyl(c, 0.17, 0.1, Vector3(0, 0.42, 0), Build.C_CREAM, false, 8)
		c.visible = false
		cones.append(c)


func show_cone(i: int) -> void:
	if i >= 0 and i < cones.size() and not cones[i].visible:
		cones[i].visible = true
		Audio.play("cone", -6.0)


func show_all_cones() -> void:
	for i in cones.size():
		show_cone(i)


func hide_cones() -> void:
	for c in cones:
		c.visible = false


## Hold-to-complete interaction helper: calls done() once after `seconds` of holding.
func _hold_interaction(at: Vector3, prompt: String, seconds: float, radius: float, done: Callable) -> Interactable:
	var it := Interactable.make(self, at, prompt, radius)
	it.hold = true
	var held := [0.0]
	it.on_press = func() -> void: held[0] = 0.0
	it.on_hold = func(dt: float) -> void:
		held[0] += dt
		if held[0] >= seconds:
			held[0] = -1000.0
			done.call()
	return it
