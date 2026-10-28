class_name CharacterVisual
extends Node3D
## A character's look + animation. Loads the rigged glb by asset id (shared clip names:
## idle, walk, run, carry_walk, work, kneel_work, interact, wave, cheer, sad, talk, ...)
## and cross-fades between clips. Falls back to the primitive figure when art is missing.

const BLEND := 0.2

var anim: AnimationPlayer
var _current := ""


static func create(parent: Node, asset_id: String, fallback_body: Color, fallback_head: Color = Color(0.87, 0.70, 0.56)) -> CharacterVisual:
	var v := CharacterVisual.new()
	parent.add_child(v)
	var art := AssetLib.spawn(asset_id, v)
	if art != null:
		v.anim = art.find_child("AnimationPlayer", true, false) as AnimationPlayer
	else:
		Build.person(v, fallback_body, fallback_head)
	v.play("idle")
	return v


func has_anim() -> bool:
	return anim != null


func play(clip: String, speed: float = 1.0) -> void:
	if anim == null or clip == _current or not anim.has_animation(clip):
		return
	_current = clip
	anim.play(clip, BLEND, speed)


func playing() -> String:
	return _current
