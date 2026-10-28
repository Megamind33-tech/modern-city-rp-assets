class_name CrewRoster
extends RefCounted
## Crew members' persistent stats. All stats are clamped 0..100.

var members: Dictionary = {}


func init_from_defs(defs: Dictionary) -> void:
	members.clear()
	for id in defs:
		var d: Dictionary = defs[id]
		members[id] = {
			"id": id,
			"name": d["name"],
			"role": d["role"],
			"skills": _int_dict(d["skills"]),
			"fatigue": 0,
			"morale": int(d.get("morale", 60)),
			"trust": int(d.get("trust", 50)),
			"xp": 0,
			"on_scene": bool(d.get("on_scene", false)),
		}


static func _int_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = int(d[k])
	return out


func get_member(id: String) -> Dictionary:
	return members.get(id, {})


func adjust(id: String, stat: String, delta: int) -> void:
	if not members.has(id):
		return
	var m: Dictionary = members[id]
	if stat == "xp":
		m["xp"] = max(0, int(m["xp"]) + delta)
		return
	m[stat] = clampi(int(m.get(stat, 0)) + delta, 0, 100)


## Applied once per resolved incident to everyone who attended.
func apply_mission(inst: Dictionary) -> void:
	var success: bool = inst.get("outcome", "") == "success"
	var flags: Dictionary = inst.get("flags", {})
	for id in members:
		if not members[id]["on_scene"]:
			continue
		adjust(id, "fatigue", 15 + 5 * int(inst.get("severity", 1)))
		adjust(id, "xp", 20 if success else 8)
		adjust(id, "morale", 6 if success else -8)
		if flags.get("delegated_secure", false) and id == "theo_vance":
			adjust(id, "trust", 5)


func rest_day() -> void:
	for id in members:
		adjust(id, "fatigue", -40)


## Efficiency multiplier used by delegated work (0.6 .. 1.2).
func work_rate(id: String, skill: String) -> float:
	var m := get_member(id)
	if m.is_empty():
		return 1.0
	var s := float(m["skills"].get(skill, 50))
	var fatigue := float(m["fatigue"])
	return clampf(0.6 + s / 100.0 * 0.6 - fatigue / 250.0, 0.6, 1.2)


func to_dict() -> Dictionary:
	return members.duplicate(true)


func from_dict(d: Dictionary) -> void:
	members = d.duplicate(true)
	for id in members:
		var m: Dictionary = members[id]
		for k in ["fatigue", "morale", "trust", "xp"]:
			m[k] = int(m.get(k, 0))
		for s in m["skills"]:
			m["skills"][s] = int(m["skills"][s])
