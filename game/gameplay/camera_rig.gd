class_name CameraRig
extends Node3D
## Elevated third-person follow camera with a higher tactical view.
## Walking uses a fixed, context-chosen yaw so touch movement stays predictable;
## driving swings behind the truck. A SpringArm3D pulls the camera in front of
## buildings instead of letting it clip inside them.

const OFFSETS := {
	"walk": Vector3(0, 7.5, 9.0),
	"drive": Vector3(0, 6.0, 12.0),
	"tactical": Vector3(0, 24.0, 15.0),
}

var target: Node3D
var mode := "walk"
var walk_yaw := 0.0
var yaw := 0.0
var camera: Camera3D
var arm: SpringArm3D
var rain: CPUParticles3D
var _offset: Vector3 = OFFSETS["walk"]
var _excluded: Array = []

const PIVOT_HEIGHT := 1.0


func _ready() -> void:
	arm = SpringArm3D.new()
	arm.collision_mask = 1
	arm.margin = 0.3
	var sh := SphereShape3D.new()
	sh.radius = 0.3
	arm.shape = sh
	arm.position.y = PIVOT_HEIGHT
	add_child(arm)
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.far = 260.0
	arm.add_child(camera)
	camera.make_current()
	_apply_offset()


## Bodies the camera arm ignores (the player and truck shouldn't push the camera around).
func exclude(bodies: Array) -> void:
	_excluded = bodies
	arm.clear_excluded_objects()
	for b in bodies:
		if b is CollisionObject3D:
			arm.add_excluded_object(b.get_rid())


func _apply_offset() -> void:
	var up := _offset.y - PIVOT_HEIGHT
	arm.spring_length = Vector2(up, _offset.z).length()
	arm.rotation.x = -atan2(up, _offset.z)


func set_rain(amount: int) -> void:
	if rain == null:
		rain = CPUParticles3D.new()
		rain.lifetime = 0.9
		rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		rain.emission_box_extents = Vector3(14, 0.5, 14)
		rain.direction = Vector3(0.15, -1, 0)
		rain.spread = 3.0
		rain.gravity = Vector3.ZERO
		rain.initial_velocity_min = 18.0
		rain.initial_velocity_max = 22.0
		var drop := BoxMesh.new()
		drop.size = Vector3(0.02, 0.5, 0.02)
		rain.mesh = drop
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.8, 0.85, 0.95, 0.45)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rain.material_override = m
		rain.position = Vector3(0, 12, 0)
		add_child(rain)
	rain.amount = maxi(1, amount)
	rain.emitting = amount > 0
	rain.visible = amount > 0


func snap() -> void:
	if target == null:
		return
	global_position = target.global_position
	yaw = _target_yaw()
	rotation.y = yaw
	_offset = OFFSETS[mode]
	_apply_offset()


func _target_yaw() -> float:
	if mode == "drive" and target:
		return target.global_rotation.y
	return walk_yaw


func _process(dt: float) -> void:
	if target == null:
		return
	yaw = lerp_angle(yaw, _target_yaw(), minf(1.0, 3.0 * dt))
	rotation.y = yaw
	global_position = global_position.lerp(target.global_position, minf(1.0, 8.0 * dt))
	_offset = _offset.lerp(OFFSETS[mode], minf(1.0, 4.0 * dt))
	_apply_offset()
