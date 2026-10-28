class_name Community
extends RefCounted
## Residents' feelings about the station and what they remember of it.

var residents: Dictionary = {}


func init_from_defs(defs: Dictionary) -> void:
	residents.clear()
	for id in defs:
		residents[id] = {"affinity": int(defs[id].get("affinity", 0)), "memories": []}


func affinity(id: String) -> int:
	return int(residents.get(id, {}).get("affinity", 0))


func adjust(id: String, delta: int) -> void:
	if not residents.has(id):
		return
	residents[id]["affinity"] = clampi(affinity(id) + delta, -100, 100)


func remember(id: String, memory: String) -> void:
	if not residents.has(id):
		return
	var mem: Array = residents[id]["memories"]
	if not mem.has(memory):
		mem.append(memory)


func remembers(id: String, memory: String) -> bool:
	return residents.get(id, {}).get("memories", []).has(memory)


func to_dict() -> Dictionary:
	return residents.duplicate(true)


func from_dict(d: Dictionary) -> void:
	residents = d.duplicate(true)
	for id in residents:
		residents[id]["affinity"] = int(residents[id].get("affinity", 0))
