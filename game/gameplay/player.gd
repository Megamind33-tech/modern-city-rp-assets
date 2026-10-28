class_name Player
extends CharacterBody3D
## Hands-on responder. Movement is camera-relative; input comes from the HUD stick,
## keyboard, or the autoplay bot through move_input. Interaction targets the nearest
## available Interactable, rescanned on a timer rather than every frame.

signal focus_changed(target: Interactable)
signal blocked(reason: String)

const SPEED := 5.2
const SCAN_INTERVAL := 0.1

var move_input := Vector2.ZERO
var camera_yaw := 0.0
var active := true
var carrying: Node3D = null
var has_saw := false:
	set(v):
		has_saw = v
		if saw_mesh:
			saw_mesh.visible = v
var focus: Interactable = null

var visual: Node3D
var saw_mesh: Node3D
var carry_point: Node3D
var _held: Interactable = null
var _scan_t := 0.0
var _walk_t := 0.0


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	shape.shape = cap
	shape.position.y = 0.85
	add_child(shape)
	visual = Build.person(self, Build.C_RED)
	saw_mesh = Node3D.new()
	visual.add_child(saw_mesh)
	saw_mesh.position = Vector3(0.4, 0.8, -0.35)
	Build.box(saw_mesh, Vector3(0.22, 0.25, 0.4), Vector3.ZERO, Build.C_AMBER)
	Build.box(saw_mesh, Vector3(0.06, 0.1, 0.7), Vector3(0, 0, -0.5), Color(0.7, 0.7, 0.72))
	saw_mesh.visible = has_saw
	carry_point = Node3D.new()
	carry_point.position = Vector3(0, 1.75, 0)
	visual.add_child(carry_point)


func equipped() -> Array:
	return ["chainsaw"] if has_saw else []


func _physics_process(dt: float) -> void:
	if not active:
		return
	var dir := Vector3(move_input.x, 0, -move_input.y).rotated(Vector3.UP, camera_yaw)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var speed := SPEED * (0.7 if carrying else 1.0)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * dt
	move_and_slide()
	if dir.length() > 0.1:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-dir.x, -dir.z), minf(1.0, 12.0 * dt))
		_walk_t += dt * 10.0
		visual.position.y = absf(sin(_walk_t)) * 0.07
	else:
		visual.position.y = lerpf(visual.position.y, 0.0, minf(1.0, 10.0 * dt))
	_scan_t -= dt
	if _scan_t <= 0.0:
		_scan_t = SCAN_INTERVAL
		_scan()


func _process(dt: float) -> void:
	if _held == null:
		return
	if not is_instance_valid(_held) or _held != focus or not _held.is_available():
		release()
		return
	var reason := _held.blocked_reason()
	if reason != "":
		blocked.emit(reason)
		release()
		return
	if _held.hold and _held.on_hold.is_valid():
		_held.on_hold.call(dt)


func _scan() -> void:
	var best: Interactable = null
	var best_d := INF
	var here := Vector2(global_position.x, global_position.z)
	for n in get_tree().get_nodes_in_group(Interactable.GROUP):
		var i := n as Interactable
		if i == null or not i.is_available():
			continue
		var d := here.distance_to(Vector2(i.global_position.x, i.global_position.z))
		if d <= i.radius and d < best_d:
			best = i
			best_d = d
	if best != focus:
		if _held != null:
			release()
		focus = best
		focus_changed.emit(focus)


func rescan() -> void:
	_scan_t = 0.0
	_scan()


func press() -> void:
	if not active or focus == null:
		return
	var reason := focus.blocked_reason()
	if reason != "":
		blocked.emit(reason)
		return
	if focus.on_press.is_valid():
		focus.on_press.call()
	if focus != null and focus.hold:
		_held = focus
	rescan()


func release() -> void:
	var h := _held
	_held = null
	if h != null and is_instance_valid(h) and h.on_release.is_valid():
		h.on_release.call()


func is_holding() -> bool:
	return _held != null


func pick_up(obj: Node3D) -> void:
	carrying = obj
	obj.reparent(carry_point, false)
	obj.position = Vector3.ZERO
	obj.rotation = Vector3.ZERO


func drop_carried() -> Node3D:
	var obj := carrying
	carrying = null
	return obj


func teleport(pos: Vector3, yaw: float = 0.0) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	visual.rotation.y = yaw
