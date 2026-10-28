class_name DataDB
extends RefCounted
## Read-only access to the JSON definitions in res://data.
## Callers must duplicate() anything they intend to mutate.

static var _cache: Dictionary = {}


static func load_json(path: String) -> Variant:
	if _cache.has(path):
		return _cache[path]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DataDB: cannot open %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("DataDB: invalid JSON in %s" % path)
		return null
	_cache[path] = parsed
	return parsed


static func list(path: String, key: String) -> Array:
	var root: Variant = load_json(path)
	if root is Dictionary and root.has(key):
		return root[key]
	return []


static func by_id(path: String, key: String) -> Dictionary:
	var out := {}
	for entry in list(path, key):
		out[String(entry["id"])] = entry
	return out


static func incidents() -> Dictionary:
	return by_id("res://data/incidents.json", "incidents")


static func locations() -> Dictionary:
	return by_id("res://data/locations.json", "locations")


static func crew() -> Dictionary:
	return by_id("res://data/characters.json", "crew")


static func residents() -> Dictionary:
	return by_id("res://data/characters.json", "residents")


static func projects() -> Dictionary:
	return by_id("res://data/projects.json", "projects")


static func story_events() -> Array:
	return list("res://data/story_events.json", "events")


static func display_name(id: String) -> String:
	var c := crew()
	if c.has(id):
		return c[id]["name"]
	var r := residents()
	if r.has(id):
		return r[id]["name"]
	return id
