class_name IncidentDirector
extends RefCounted
## Builds incident instances from data definitions and owns their state machine:
##   offered -> en_route -> on_scene -> resolved
## Generation is deterministic for a given seed. All mutation goes through methods
## that validate the transition and explain refusals in player-facing language.

const OFFERED := "offered"
const EN_ROUTE := "en_route"
const ON_SCENE := "on_scene"
const RESOLVED := "resolved"

var defs: Dictionary
var locations: Dictionary
var active: Dictionary = {}
var history: Array = []
var next_uid: int = 1


func _init() -> void:
	defs = DataDB.incidents()
	locations = DataDB.locations()


func generate(def_id: String, seed_value: int, location_id: String = "", model = null) -> Dictionary:
	var def: Dictionary = defs[def_id]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var options: Array = def["location_options"]
	var pick := rng.randi_range(0, options.size() - 1)
	var loc := location_id if location_id != "" else String(options[pick])
	var sev: Array = def["severity_range"]
	var severity := rng.randi_range(int(sev[0]), int(sev[1]))
	# Modifiers let earlier outcomes reshape this call (e.g. a damaged roof floods worse).
	var loc_def: Dictionary = locations[loc]
	var ctx := {
		"location": loc,
		"location_name": String(loc_def["name"]),
		"house": String(loc_def.get("house", "")),
		"resident": String(loc_def.get("resident", "")),
	}
	ctx["resident_name"] = DataDB.display_name(ctx["resident"])
	var mod_flags := {}
	if model != null:
		for mod in def.get("modifiers", []):
			var ok := true
			for c in mod["when"]:
				var cf: Dictionary = c.duplicate()
				if cf.has("key"):
					cf["key"] = String(cf["key"]).format(ctx)
				if not StoryDirector.condition_met(cf, model):
					ok = false
			if ok:
				severity = clampi(severity + int(mod.get("severity_delta", 0)), 1, 3)
				if mod.has("flag"):
					mod_flags[String(mod["flag"])] = true
	var weathers: Array = def["weather_options"]
	var weather := String(weathers[rng.randi_range(0, weathers.size() - 1)])
	var complications: Array = []
	for c in def.get("complications", []):
		var roll := rng.randf()  # always roll so the sequence is stable across data edits
		if severity >= int(c.get("min_severity", 1)) and roll < float(c["chance"]):
			complications.append(String(c["id"]))
	var tasks: Array = []
	for t in def["tasks"]:
		if t.has("requires_complication") and not complications.has(t["requires_complication"]):
			continue
		var required := 1
		if t.has("count_by_severity"):
			required = int(t["count_by_severity"][severity - 1])
		var auto := 0.0
		if t.has("auto_seconds_by_severity"):
			auto = float(t["auto_seconds_by_severity"][severity - 1])
		tasks.append({
			"auto_seconds": auto,
			"id": String(t["id"]),
			"label": String(t["label"]),
			"required": required,
			"progress": 0,
			"optional": bool(t.get("optional", false)),
			"delegatable": bool(t.get("delegatable", false)),
			"equipment": String(t.get("equipment", "")),
			"after": t.get("after", []).duplicate(),
			"progress_with": String(t.get("progress_with", "")),
			"done_indices": [],
		})
	return {
		"uid": "",
		"def_id": def_id,
		"seed": seed_value,
		"location": loc,
		"severity": severity,
		"weather": weather,
		"complications": complications,
		"tasks": tasks,
		"state": OFFERED,
		"elapsed": 0.0,
		"time_limit": float(def.get("time_limit", 300)),
		"flags": mod_flags,
		"outcome": "",
		"reason": "",
		"dispatch_mode": "",
		"title": String(def["title"]).format(ctx),
		"briefing": String(def["briefing"]).format(ctx),
		"context": ctx,
	}


## Offers the next call. Prefers a different street than last time and skips roads already closed.
## Authored story incidents (story: true) take priority once eligible and happen once.
func offer_next(day: int, base_seed: int, world: WorldState, model = null) -> Dictionary:
	if not active.is_empty():
		return {}
	var done_defs: Array = history.map(func(h: Dictionary) -> String: return h["def_id"])
	var def_ids: Array = []
	var story_ids: Array = []
	for id in defs:
		var d: Dictionary = defs[id]
		if int(d.get("phase", 1)) > 1:
			continue
		var eligible := true
		for c in d.get("eligible", []):
			if model == null or not StoryDirector.condition_met(c, model):
				eligible = false
		if not eligible:
			continue
		if d.get("story", false):
			if not done_defs.has(id):
				story_ids.append(id)
		else:
			def_ids.append(id)
	if not story_ids.is_empty():
		def_ids = story_ids
	def_ids.sort()
	if def_ids.is_empty():
		return {}
	var seed_value := hash([base_seed, day, next_uid])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var def_id: String = def_ids[rng.randi_range(0, def_ids.size() - 1)]
	var last_loc: String = history[-1]["location"] if not history.is_empty() else ""
	var candidates: Array = []
	for loc in defs[def_id]["location_options"]:
		if world.get_value("%s.road" % loc, "open") == "closed":
			continue
		if loc == last_loc:
			continue
		candidates.append(loc)
	if candidates.is_empty():
		candidates = defs[def_id]["location_options"].duplicate()
	var loc_pick: String = candidates[rng.randi_range(0, candidates.size() - 1)]
	var inst := generate(def_id, seed_value, loc_pick, model)
	inst["uid"] = "INC-%04d" % next_uid
	inst["day"] = day
	next_uid += 1
	active = inst
	return inst


func dispatch(mode: String) -> Dictionary:
	if active.is_empty() or active["state"] != OFFERED:
		return {"ok": false, "reason": "No call waiting for dispatch"}
	if mode not in ["drive", "quick"]:
		return {"ok": false, "reason": "Unknown dispatch mode"}
	active["state"] = EN_ROUTE
	active["dispatch_mode"] = mode
	return {"ok": true, "reason": ""}


func arrive() -> bool:
	if active.is_empty() or active["state"] != EN_ROUTE:
		return false
	active["state"] = ON_SCENE
	return true


func find_task(task_id: String) -> Dictionary:
	if active.is_empty():
		return {}
	for t in active["tasks"]:
		if t["id"] == task_id:
			return t
	return {}


func is_task_done(task_id: String) -> bool:
	var t := find_task(task_id)
	return not t.is_empty() and int(t["progress"]) >= int(t["required"])


## Empty string means allowed; otherwise a short reason the player can read.
func check_task(task_id: String, context: Dictionary = {}) -> String:
	if active.is_empty() or active["state"] != ON_SCENE:
		return "Not on scene"
	var t := find_task(task_id)
	if t.is_empty():
		return "Nothing to do here"
	if int(t["progress"]) >= int(t["required"]):
		return "Already done"
	if context.has("index") and t["done_indices"].has(int(context["index"])):
		return "Already done"
	for dep in t["after"]:
		var d := find_task(dep)
		if not d.is_empty() and int(d["progress"]) < int(d["required"]):
			return "First: %s" % d["label"]
	if t["progress_with"] != "":
		var lead := find_task(t["progress_with"])
		if not lead.is_empty() and int(t["progress"]) >= int(lead["progress"]):
			return "First: %s" % lead["label"]
	if float(t.get("auto_seconds", 0.0)) > 0.0 and context.get("by", "") != "auto":
		return "In progress — %s" % String(t["label"]).to_lower()
	if t["equipment"] != "" and not context.get("equipped", []).has(t["equipment"]):
		return "Needs the %s from the truck" % t["equipment"]
	return ""


func add_progress(task_id: String, context: Dictionary = {}) -> Dictionary:
	var reason := check_task(task_id, context)
	if reason != "":
		return {"ok": false, "reason": reason}
	var t := find_task(task_id)
	var flags: Dictionary = active["flags"]
	var warning := ""
	var secure := find_task("secure_area")
	if t["equipment"] != "" and not secure.is_empty() and not is_task_done("secure_area"):
		if not flags.get("unsafe_cut", false):
			warning = "unsafe_cut"
		flags["unsafe_cut"] = true
	t["progress"] = int(t["progress"]) + 1
	if context.has("index"):
		t["done_indices"].append(int(context["index"]))
	var completed := int(t["progress"]) >= int(t["required"])
	if completed and task_id == "secure_area":
		flags["secured"] = true
		if context.get("by", "player") != "player":
			flags["delegated_secure"] = true
	return {"ok": true, "reason": "", "completed": completed, "all_done": all_required_done(), "warning": warning}


func all_required_done() -> bool:
	if active.is_empty():
		return false
	for t in active["tasks"]:
		if not t["optional"] and int(t["progress"]) < int(t["required"]):
			return false
	return true


## Advances the on-scene clock. Returns "timeout" once the time limit is reached.
func tick(dt: float) -> String:
	if active.is_empty() or active["state"] != ON_SCENE:
		return ""
	active["elapsed"] = float(active["elapsed"]) + dt
	if float(active["elapsed"]) >= float(active["time_limit"]):
		return "timeout"
	return ""


func time_left() -> float:
	if active.is_empty():
		return 0.0
	return maxf(0.0, float(active["time_limit"]) - float(active["elapsed"]))


## Returns the resolved instance, or {} if there is nothing to resolve (duplicate guard).
func resolve(outcome: String, reason: String) -> Dictionary:
	if active.is_empty() or active["state"] not in [EN_ROUTE, ON_SCENE]:
		return {}
	active["state"] = RESOLVED
	active["outcome"] = outcome
	active["reason"] = reason
	history.append({
		"uid": active["uid"],
		"def_id": active["def_id"],
		"location": active["location"],
		"severity": active["severity"],
		"outcome": outcome,
		"reason": reason,
		"day": active.get("day", 0),
		"flags": active["flags"].duplicate(),
	})
	return active


func clear_resolved() -> bool:
	if active.is_empty() or active["state"] != RESOLVED:
		return false
	active = {}
	return true


func to_dict() -> Dictionary:
	return {"active": active.duplicate(true), "history": history.duplicate(true), "next_uid": next_uid}


func from_dict(d: Dictionary) -> void:
	active = d.get("active", {}).duplicate(true)
	history = d.get("history", []).duplicate(true)
	for h in history:
		h["day"] = int(h.get("day", 0))
		h["severity"] = int(h.get("severity", 1))
	next_uid = int(d.get("next_uid", 1))
	if not active.is_empty():
		for k in ["severity", "seed", "day"]:
			active[k] = int(active.get(k, 0))
		for t in active["tasks"]:
			t["required"] = int(t["required"])
			t["auto_seconds"] = float(t.get("auto_seconds", 0.0))
			t["progress"] = int(t["progress"])
			var idx: Array = []
			for i in t["done_indices"]:
				idx.append(int(i))
			t["done_indices"] = idx
