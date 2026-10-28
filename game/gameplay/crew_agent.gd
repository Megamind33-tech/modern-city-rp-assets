class_name CrewAgent
extends CharacterBody3D
## On-scene crew member. Small explicit state machine; decisions are re-evaluated on a
## timer (DECIDE_INTERVAL), movement runs per physics tick. The floating status line
## always says what the agent is doing and why it is waiting.

signal work_step_done(task: String, index: int)
signal task_finished(task: String)

enum State { IDLE, FOLLOW, MOVE, WORK }

const SPEED := 4.2
const DECIDE_INTERVAL := 0.25
const WORK_TIME := 1.4

var member_id := ""
var display_name := ""
var rate := 1.0
var state := State.IDLE
var follow_target: Node3D
var task := ""
var targets: Array = []
var _index := 0
var _work_t := 0.0
var _decide_t := 0.0
var _status: Label3D
var _visual: Node3D


func setup(id: String, crew_name: String, work_rate: float) -> void:
	member_id = id
	display_name = crew_name
	rate = work_rate


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = 1.7
	shape.shape = cap
	shape.position.y = 0.85
	add_child(shape)
	# Crew don't block each other or the player; they still collide with the world.
	collision_layer = 2
	collision_mask = 1
	_visual = Build.person(self, Build.C_TEAL, Color(0.55, 0.38, 0.28))
	_status = Build.label(self, "", Vector3(0, 2.3, 0), 30)


func assign(task_id: String, points: Array) -> void:
	task = task_id
	targets = points.duplicate()
	_index = 0
	state = State.MOVE
	_say("On it — %s" % _task_text())


func cancel() -> void:
	task = ""
	targets.clear()
	state = State.FOLLOW if follow_target else State.IDLE


func is_busy() -> bool:
	return task != ""


func _task_text() -> String:
	match task:
		"secure_area":
			return "coning off (%d/%d)" % [mini(_index + 1, targets.size()), targets.size()]
	return task


func _say(text: String) -> void:
	if _status:
		_status.text = "%s: %s" % [display_name.get_slice(" ", 0), text]


func _physics_process(dt: float) -> void:
	_decide_t -= dt
	if _decide_t <= 0.0:
		_decide_t = DECIDE_INTERVAL
		_decide()
	var dest := global_position
	var speed := SPEED * rate
	match state:
		State.MOVE:
			dest = targets[_index]
		State.FOLLOW:
			if follow_target:
				var d := follow_target.global_position
				if global_position.distance_to(d) > 3.0:
					dest = d
		State.WORK:
			_work_t += dt * rate
			if _work_t >= WORK_TIME:
				_work_t = 0.0
				work_step_done.emit(task, _index)
				_index += 1
				if _index >= targets.size():
					var done := task
					task = ""
					state = State.FOLLOW if follow_target else State.IDLE
					_say("Done. Scene's coned off.")
					task_finished.emit(done)
				else:
					state = State.MOVE
					_say(_task_text())
	var to := dest - global_position
	to.y = 0.0
	if to.length() > 0.2:
		var dir := to.normalized()
		velocity = Vector3(dir.x * speed, 0, dir.z * speed)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(-dir.x, -dir.z), minf(1.0, 10.0 * dt))
	else:
		velocity = Vector3.ZERO
	move_and_slide()
	position.y = 0.0


func _decide() -> void:
	if state == State.MOVE and _index < targets.size():
		var d := Vector2(global_position.x, global_position.z).distance_to(Vector2(targets[_index].x, targets[_index].z))
		if d < 0.6:
			state = State.WORK
			_say(_task_text())
	elif state == State.IDLE and follow_target and task == "":
		state = State.FOLLOW
	if state == State.FOLLOW and task == "":
		_say("Standing by")


func teleport(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
