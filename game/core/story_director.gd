class_name StoryDirector
extends RefCounted
## Selects authored narrative fragments whose conditions match the current game state.
## No runtime text generation: everything shown is written in data/story_events.json.

var events: Array = []
var fired: Dictionary = {}  # event id -> day first fired


func _init() -> void:
	events = DataDB.story_events()


## Returns events to play for this trigger and marks them fired.
func evaluate(trigger: String, model) -> Array:
	var out: Array = []
	for e in events:
		if e["trigger"] != trigger:
			continue
		if fired.has(e["id"]) and not e.get("repeatable", false):
			continue
		var ok := true
		for c in e.get("conditions", []):
			if not condition_met(c, model):
				ok = false
				break
		if ok:
			fired[e["id"]] = model.day
			out.append(e)
	return out


static func condition_met(c: Dictionary, model) -> bool:
	var last: Dictionary = model.incidents.history[-1] if not model.incidents.history.is_empty() else {}
	match String(c["type"]):
		"flag":
			return model.flags.get(c["key"], false) == c["value"]
		"flag_any_prefix":
			for k in model.flags:
				if String(k).begins_with(c["key"]) and model.flags[k]:
					return true
			return false
		"world":
			return model.world.get_value(c["key"]) == c["value"]
		"day_min":
			return model.day >= int(c["value"])
		"last_outcome":
			return last.get("outcome", "") == c["value"]
		"last_location":
			return last.get("location", "") == c["value"]
		"last_flag":
			return last.get("flags", {}).get(c["key"], false) == c["value"]
		"last_def":
			return last.get("def_id", "") == c["value"]
		"active_flag":
			return model.incidents.active.get("flags", {}).get(c["key"], false) == c["value"]
		"active_def":
			return model.incidents.active.get("def_id", "") == c["value"]
		"complication":
			return model.incidents.active.get("complications", []).has(c["id"])
		"rank_min":
			return int(model.rank().get("rank", 1)) >= int(c["value"])
		"project_done":
			return model.projects_done.has(c["value"])
		"relationship_min":
			return model.community.affinity(c["who"]) >= int(c["value"])
	push_warning("StoryDirector: unknown condition %s" % c["type"])
	return false


func to_dict() -> Dictionary:
	return fired.duplicate()


func from_dict(d: Dictionary) -> void:
	fired = {}
	for k in d:
		fired[k] = int(d[k])
