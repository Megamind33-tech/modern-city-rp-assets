class_name Truck
extends CharacterBody3D
## Arcade-handled rescue truck. Simplified kinematics: no tyre simulation, which keeps
## driving readable on a phone and cheap on CPU.

const MAX_SPEED := 17.0
const MAX_REVERSE := 5.0
const ACCEL := 8.0
const BRAKE := 18.0
const STEER_RATE := 1.7

var drive_input := Vector2.ZERO
var driving := false
var speed := 0.0
var siren := false:
	set(v):
		siren = v
		if not v:
			_set_lights(false, false)

var _lights: Array[MeshInstance3D] = []
var _flash_t := 0.0


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.5, 2.4, 6.4)
	shape.shape = bs
	shape.position = Vector3(0, 1.45, 0)
	add_child(shape)
	_build_visual()


func _build_visual() -> void:
	var v := Node3D.new()
	add_child(v)
	# Chassis, cab (front is -Z), equipment body with roller shutters.
	Build.box(v, Vector3(2.4, 0.5, 6.2), Vector3(0, 0.75, 0), Build.C_NAVY)
	Build.box(v, Vector3(2.4, 1.6, 1.9), Vector3(0, 1.8, -2.1), Build.C_RED)
	Build.box(v, Vector3(2.2, 0.7, 0.1), Vector3(0, 2.15, -3.06), Build.C_GLASS)
	Build.box(v, Vector3(2.4, 2.1, 4.1), Vector3(0, 2.05, 1.0), Build.C_RED)
	for side in [-1.0, 1.0]:
		Build.box(v, Vector3(0.06, 1.3, 3.5), Vector3(side * 1.22, 2.05, 1.0), Color(0.78, 0.78, 0.80))
		Build.box(v, Vector3(0.07, 0.22, 6.0), Vector3(side * 1.22, 1.05, 0.1), Build.C_AMBER)
		for wz in [-2.0, 2.0]:
			var w := Build.cyl(v, 0.5, 0.4, Vector3(side * 1.1, 0.5, wz), Color(0.12, 0.12, 0.13), false, 12)
			w.rotation.z = PI / 2
	for side in [-1.0, 1.0]:
		var l := Build.box(v, Vector3(0.8, 0.18, 0.35), Vector3(side * 0.5, 2.7, -2.1), Color(0.3, 0.3, 0.8))
		_lights.append(l)
	Build.box(v, Vector3(2.2, 0.3, 0.1), Vector3(0, 0.9, -3.12), Color(0.85, 0.85, 0.8))
	var lbl := Build.label(v, "KETTLEFORD 1", Vector3(1.26, 2.5, 1.0), 40)
	lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lbl.rotation.y = PI / 2


## Local offsets of the interaction points around the truck.
func point(which: String) -> Vector3:
	match which:
		"driver":
			return Vector3(-1.9, 0, -2.0)
		"radio":
			return Vector3(1.9, 0, -2.0)
		"locker":
			return Vector3(-1.9, 0, 1.8)
		"cones":
			return Vector3(1.9, 0, 1.8)
	return Vector3.ZERO


func _physics_process(dt: float) -> void:
	if driving:
		var target := drive_input.y * (MAX_SPEED if drive_input.y >= 0 else MAX_REVERSE)
		var rate := ACCEL if signf(target) == signf(speed) or is_zero_approx(speed) else BRAKE
		if absf(target) < absf(speed):
			rate = BRAKE * 0.6
		speed = move_toward(speed, target, rate * dt)
		var grip := clampf(absf(speed) / 5.0, 0.0, 1.0) * signf(speed)
		rotation.y -= drive_input.x * STEER_RATE * grip * dt
	else:
		speed = move_toward(speed, 0.0, BRAKE * dt)
	velocity = -global_transform.basis.z * speed
	velocity.y = 0.0
	move_and_slide()
	position.y = 0.0
	if get_slide_collision_count() > 0:
		speed *= 0.6
	if siren:
		_flash_t += dt
		var phase := int(_flash_t * 6.0) % 2 == 0
		_set_lights(phase, not phase)
	if driving:
		Audio.loop_set("engine", 0.8 + absf(speed) / MAX_SPEED * 1.1, -10.0)


func _set_lights(a: bool, b: bool) -> void:
	if _lights.size() < 2:
		return
	_lights[0].material_override = Build.mat(Color(0.2, 0.4, 1.0), true) if a else Build.mat(Color(0.3, 0.3, 0.8))
	_lights[1].material_override = Build.mat(Color(1.0, 0.25, 0.2), true) if b else Build.mat(Color(0.8, 0.3, 0.3))


func set_driving(on: bool) -> void:
	driving = on
	drive_input = Vector2.ZERO
	if on:
		Audio.loop_start("engine", -10.0)
	else:
		Audio.loop_stop("engine")


func place(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation = Vector3(0, yaw, 0)
	speed = 0.0
	velocity = Vector3.ZERO
