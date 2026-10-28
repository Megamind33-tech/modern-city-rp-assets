class_name GameModel
extends RefCounted
## The whole simulation state of one save slot, independent of scenes and rendering.
## Every gameplay rule lives here or in the module it owns, so it can be tested headless.

signal fragment_queued(fragment: Dictionary)
signal incident_resolved(result: Dictionary)

const START_MONEY := 400
const ISOLATION_DELAY := 8.0

var day: int = 1
var base_seed: int = 0
var flags: Dictionary = {}
var equipment: Dictionary = {"chainsaw": 1}
var projects_done: Array = []
var overnight: Array = []
var last_result: Dictionary = {}
var fragments: Array = []

var world := WorldState.new()
var economy := Economy.new()
var crew := CrewRoster.new()
var community := Community.new()
var incidents := IncidentDirector.new()
var story := StoryDirector.new()


func new_game(seed_value: int) -> void:
	base_seed = seed_value
	day = 1
	economy.money = START_MONEY
	crew.init_from_defs(DataDB.crew())
	community.init_from_defs(DataDB.residents())
	_fire("new_game")


# --- Incident flow -----------------------------------------------------------

func offer_incident() -> Dictionary:
	return incidents.offer_next(day, base_seed, world, self)


func dispatch(mode: String) -> Dictionary:
	return incidents.dispatch(mode)


func arrive() -> bool:
	if not incidents.arrive():
		return false
	_fire("arrive")
	return true


func progress_task(task_id: String, context: Dictionary = {}) -> Dictionary:
	var ctx := context.duplicate()
	if not ctx.has("equipped"):
		ctx["equipped"] = []
	var r := incidents.add_progress(task_id, ctx)
	if not r["ok"]:
		return r
	if r["warning"] == "unsafe_cut":
		_fire("unsafe_cut")
	if r["all_done"]:
		r["result"] = resolve("success", "road_reopened")
	return r


## The radio call to the utility takes time; the line is isolated by tick().
func request_isolation() -> Dictionary:
	var inst := incidents.active
	if incidents.find_task("isolate_power").is_empty():
		return {"ok": false, "reason": "No live line here"}
	if inst["state"] != IncidentDirector.ON_SCENE:
		return {"ok": false, "reason": "Not on scene"}
	if inst["flags"].has("isolation_eta"):
		return {"ok": false, "reason": "Utility already on the way"}
	inst["flags"]["isolation_eta"] = float(inst["elapsed"]) + ISOLATION_DELAY
	return {"ok": true, "reason": ""}


## 0..1 progress of a timed task (for HUD/visuals).
func auto_fraction(task_id: String) -> float:
	var t := incidents.find_task(task_id)
	if t.is_empty() or float(t.get("auto_seconds", 0.0)) <= 0.0:
		return 0.0
	if incidents.is_task_done(task_id):
		return 1.0
	return clampf(float(incidents.active["flags"].get("auto_" + task_id, 0.0)) / float(t["auto_seconds"]), 0.0, 1.0)


func isolation_pending() -> bool:
	var f: Dictionary = incidents.active.get("flags", {})
	return f.has("isolation_eta") and not incidents.is_task_done("isolate_power")


func tick(dt: float) -> void:
	var inst := incidents.active
	if inst.is_empty() or inst["state"] != IncidentDirector.ON_SCENE:
		return
	var timeout := incidents.tick(dt)
	if isolation_pending() and float(inst["elapsed"]) >= float(inst["flags"]["isolation_eta"]):
		incidents.add_progress("isolate_power", {"by": "utility"})
	# Timed tasks (e.g. pumping) run on their own once their prerequisites are met.
	for t in inst["tasks"]:
		if float(t.get("auto_seconds", 0.0)) <= 0.0 or incidents.check_task(t["id"], {"by": "auto"}) != "":
			continue
		var key: String = "auto_" + t["id"]
		var rate := 1.25 if inst["flags"].get("tomas_helps", false) else 1.0
		inst["flags"][key] = float(inst["flags"].get(key, 0.0)) + dt * rate
		if float(inst["flags"][key]) >= float(t["auto_seconds"]):
			var r := progress_task(t["id"], {"by": "auto"})
			if r.has("result"):
				return
	if timeout == "timeout":
		resolve("failure", "timeout")


func abandon() -> Dictionary:
	return resolve("failure", "abandoned")


func resolve(outcome: String, reason: String) -> Dictionary:
	var inst := incidents.resolve(outcome, reason)
	if inst.is_empty():
		return {}
	var def: Dictionary = incidents.defs[inst["def_id"]]
	var payout := Economy.mission_payout(def, inst)
	var total := int(payout["total"])
	if total >= 0:
		economy.earn(total, "Callout %s" % inst["uid"], day)
	else:
		economy.spend(mini(-total, economy.money), "Callout %s" % inst["uid"], day)
	var effects: Array = def["success_effects"] if outcome == "success" else def["failure_effects"]
	apply_effects(effects, inst["context"])
	crew.apply_mission(inst)
	last_result = {
		"uid": inst["uid"],
		"def_id": inst["def_id"],
		"title": inst["title"],
		"outcome": outcome,
		"reason": reason,
		"elapsed": inst["elapsed"],
		"payout": payout,
		"flags": inst["flags"].duplicate(),
		"location": inst["location"],
	}
	_fire("resolved")
	incident_resolved.emit(last_result)
	return last_result


## Player-facing consequence line for a resolved incident (authored in incidents.json).
func outcome_text(result: Dictionary) -> String:
	var def: Dictionary = incidents.defs.get(result.get("def_id", ""), {})
	var texts: Dictionary = def.get("outcome_text", {})
	var key := "success" if result["outcome"] == "success" else String(result.get("reason", "timeout"))
	var loc: Dictionary = DataDB.locations().get(result.get("location", ""), {})
	var ctx := {"location_name": loc.get("name", ""), "resident_name": DataDB.display_name(String(loc.get("resident", "")))}
	var text := String(texts.get(key, texts.get("timeout", ""))).format(ctx)
	if result["outcome"] == "success" and result.get("flags", {}).get("unsafe_cut", false):
		text += " Maren hasn't forgotten the cones."
	return text


func return_to_station() -> bool:
	if not incidents.clear_resolved():
		return false
	_fire("returned")
	return true


func can_end_shift() -> String:
	if not incidents.active.is_empty():
		return "Finish the current call first"
	return ""


func end_shift() -> Dictionary:
	var reason := can_end_shift()
	if reason != "":
		return {"ok": false, "reason": reason}
	day += 1
	for o in overnight:
		world.set_value(o["key"], o["value"])
	overnight.clear()
	crew.rest_day()
	_fire("day_start")
	return {"ok": true, "reason": ""}


# --- Station projects --------------------------------------------------------

func available_projects() -> Array:
	var out: Array = []
	var defs := DataDB.projects()
	var ids := defs.keys()
	ids.sort()
	for id in ids:
		if projects_done.has(id):
			continue
		var ok := true
		for c in defs[id].get("requires", []):
			if not StoryDirector.condition_met(c, self):
				ok = false
		if ok:
			out.append(defs[id])
	return out


func buy_project(id: String) -> Dictionary:
	var proj: Dictionary = {}
	for p in available_projects():
		if p["id"] == id:
			proj = p
	if proj.is_empty():
		return {"ok": false, "reason": "Not available"}
	if not economy.spend(int(proj["cost"]), proj["label"], day):
		return {"ok": false, "reason": "Not enough funds (need %d)" % int(proj["cost"])}
	projects_done.append(id)
	apply_effects(proj["effects"], {})
	_fire("project_done")
	return {"ok": true, "reason": ""}


# --- Effects & story ---------------------------------------------------------

func apply_effects(effects: Array, ctx: Dictionary) -> void:
	for e in effects:
		var key := String(e.get("key", "")).format(ctx)
		var who := String(e.get("who", "")).format(ctx)
		match String(e["type"]):
			"world":
				world.set_value(key, e["value"])
			"overnight":
				overnight.append({"key": key, "value": e["value"]})
			"flag":
				flags[key] = e["value"]
			"relationship":
				community.adjust(who, int(e["delta"]))
			"memory":
				community.remember(who, String(e["memory"]).format(ctx))
			"crew":
				crew.adjust(who, String(e["stat"]), int(e["delta"]))
			"equipment":
				equipment[key] = int(e["value"])
			_:
				push_warning("GameModel: unknown effect %s" % e["type"])


func _fire(trigger: String) -> void:
	for e in story.evaluate(trigger, self):
		apply_effects(e.get("effects", []), {})
		var frag := {"id": e["id"], "speaker": e["speaker"], "lines": e["lines"]}
		fragments.append(frag)
		fragment_queued.emit(frag)


func pop_fragment() -> Dictionary:
	if fragments.is_empty():
		return {}
	return fragments.pop_front()


# --- Persistence -------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"day": day,
		"base_seed": base_seed,
		"flags": flags.duplicate(true),
		"equipment": equipment.duplicate(),
		"projects_done": projects_done.duplicate(),
		"overnight": overnight.duplicate(true),
		"last_result": last_result.duplicate(true),
		"fragments": fragments.duplicate(true),
		"money": economy.money,
		"ledger": economy.ledger.duplicate(true),
		"world": world.to_dict(),
		"crew": crew.to_dict(),
		"community": community.to_dict(),
		"incidents": incidents.to_dict(),
		"story": story.to_dict(),
	}


func from_dict(d: Dictionary) -> void:
	day = int(d["day"])
	base_seed = int(d["base_seed"])
	flags = d.get("flags", {}).duplicate(true)
	equipment = {}
	for k in d.get("equipment", {}):
		equipment[k] = int(d["equipment"][k])
	projects_done = d.get("projects_done", []).duplicate()
	overnight = d.get("overnight", []).duplicate(true)
	last_result = d.get("last_result", {}).duplicate(true)
	fragments = d.get("fragments", []).duplicate(true)
	economy.money = int(d["money"])
	economy.ledger = d.get("ledger", []).duplicate(true)
	for e in economy.ledger:
		e["day"] = int(e["day"])
		e["delta"] = int(e["delta"])
	world.from_dict(d.get("world", {}))
	crew.from_dict(d["crew"])
	community.from_dict(d.get("community", {}))
	incidents.from_dict(d.get("incidents", {}))
	story.from_dict(d.get("story", {}))
