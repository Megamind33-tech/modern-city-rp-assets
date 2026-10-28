class_name Interactable
extends Node3D
## A point in the world the player can act on. Behaviour is supplied as callables so
## incident sites can wire interactions to model rules without subclassing.
##   available() -> bool   whether to offer it at all
##   can_use()   -> String "" if allowed, else the reason shown to the player
##   on_press(), on_hold(dt), on_release()

const GROUP := "interactables"

var prompt := "Use"
var radius := 1.8
var hold := false
var available: Callable
var can_use: Callable
var on_press: Callable
var on_hold: Callable
var on_release: Callable
var prompt_fn: Callable


static func make(parent: Node, pos: Vector3, prompt_text: String, r: float = 1.8) -> Interactable:
	var i := Interactable.new()
	i.prompt = prompt_text
	i.radius = r
	i.position = pos
	parent.add_child(i)
	return i


func _ready() -> void:
	add_to_group(GROUP)


func is_available() -> bool:
	return is_visible_in_tree() and (not available.is_valid() or available.call())


func blocked_reason() -> String:
	return can_use.call() if can_use.is_valid() else ""


func get_prompt() -> String:
	return prompt_fn.call() if prompt_fn.is_valid() else prompt
