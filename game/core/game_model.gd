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
# Progression (see core/progression.gd)
var xp: int = 0
var streak: int = 0
var best_scores: Dictionary = {}
var goals_today: Array = []
var goals_done: Array = []
var calls_today: int = 0
var stats: Dictionary = {"calls": 0, "gold": 0, "silver": 0, "bronze": 0, "failed": 0}

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
	goals_today = Progression.roll_goals(base_seed, day, possible_defs())
	_fire("new_game")


# --- Incident flow -----------------------------------------------------------

func offer_incident() -> Dictionary:
	if calls_remaining() <= 0:
		return {}
	return incidents.offer_next(day, base_seed, world, self)


## Incident types that could still be offered (used to avoid impossible shift goals).
func possible_defs() -> Array:
	var out: Array = []
	var done: Array = incidents.history.map(func(h: Dictionary) -> String: return h["def_id"])
	for id in incidents.defs:
		var d: Dictionary = incidents.defs[id]
		if int(d.get("phase", 1)) > 1:
			continue
		if d.get("story", false):
			if done.has(id):
				continue
			var ok := true
			for c in d.get("eligible", []):
				if not StoryDirector.condition_met(c, self):
					ok = false
			if not ok:
				continue
		out.append(id)
	return out


func rank() -> Dictionary:
	return Progression.rank_for(xp)


func calls_per_shift() -> int:
	return int(rank().get("calls_per_shift", 2))


func calls_remaining() -> int:
	return maxi(0, calls_per_shift() - calls_today)


## Technique counters reported by sites (chain stalls, missed pump pulls, ...).
func note(stat: String, delta: int = 1) -> void:
	var inst := incidents.active
	if inst.is_empty() or inst["state"] != IncidentDirector.ON_SCENE:
		return
	inst["flags"][stat] = int(inst["flags"].get(stat, 0)) + delta


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
		if t["id"] == "pump_out" and int(equipment.get("pump", 1)) >= 2:
			rate *= 1.3
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
	var graded := Progression.grade(def, inst)
	var rank_before: Dictionary = rank()
	# Clean streak: consecutive successful, safe calls raise council funding.
	if outcome == "success" and not inst["flags"].get("unsafe_cut", false):
		streak += 1
	else:
		streak = 0
	var pdata := Progression.data()
	if streak >= 2:
		var pct := int(pdata["streak_bonus_pct"]) * mini(streak, int(pdata["streak_cap"]))
		var bonus := int(round(float(payout["lines"][0]["amount"]) * pct / 100.0))
		payout["lines"].insert(payout["lines"].size() - 1, {"label": "Clean streak ×%d (+%d%%)" % [streak, pct], "amount": bonus})
		payout["total"] = int(payout["total"]) + bonus
	var total := int(payout["total"])
	if total >= 0:
		economy.earn(total, "Callout %s" % inst["uid"], day)
	else:
		economy.spend(mini(-total, economy.money), "Callout %s" % inst["uid"], day)
	var effects: Array = def["success_effects"] if outcome == "success" else def["failure_effects"]
	apply_effects(effects, inst["context"])
	crew.apply_mission(inst)
	var xp_gain := int(graded["xp"])
	var goals_completed: Array = []
	for gid in goals_today:
		if goals_done.has(gid):
			continue
		var g := Progression.goal(gid)
		if Progression.goal_met(g, inst, graded, streak):
			goals_done.append(gid)
			economy.earn(int(g["reward"]), "Shift goal: %s" % g["text"], day)
			xp_gain += int(g["xp"])
			goals_completed.append({"text": g["text"], "reward": int(g["reward"]), "xp": int(g["xp"])})
	xp += xp_gain
	var prev_best := int(best_scores.get(inst["def_id"], -1))
	var new_best: bool = outcome == "success" and int(graded["score"]) > prev_best
	if new_best:
		best_scores[inst["def_id"]] = int(graded["score"])
	calls_today += 1
	stats["calls"] = int(stats.get("calls", 0)) + 1
	var medal_key: String = graded["medal"] if graded["medal"] != "" else ("failed" if outcome != "success" else "")
	if medal_key != "":
		stats[medal_key] = int(stats.get(medal_key, 0)) + 1
	var rank_after: Dictionary = rank()
	last_result = {
		"grade": graded,
		"xp_gained": xp_gain,
		"new_best": new_best,
		"prev_best": prev_best,
		"goals_completed": goals_completed,
		"rank_up": rank_after if int(rank_after["rank"]) > int(rank_before["rank"]) else {},
		"streak": streak,
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
	calls_today = 0
	for o in overnight:
		world.set_value(o["key"], o["value"])
	overnight.clear()
	crew.rest_day()
	goals_today = Progression.roll_goals(base_seed, day, possible_defs())
	goals_done.clear()
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


## Not-yet-available projects whose only missing requirement is progression (rank or a
## prerequisite upgrade): shown greyed on the board so there is always a visible next goal.
func locked_projects() -> Array:
	var out: Array = []
	var defs := DataDB.projects()
	var ids := defs.keys()
	ids.sort()
	for id in ids:
		if projects_done.has(id):
			continue
		var gated := false
		var ok := true
		var reasons: Array = []
		for c in defs[id].get("requires", []):
			if StoryDirector.condition_met(c, self):
				continue
			if c["type"] == "rank_min":
				gated = true
				reasons.append("Rank %d: %s" % [int(c["value"]), Progression.data()["ranks"][int(c["value"]) - 1]["title"]])
			elif c["type"] == "project_done":
				gated = true
				reasons.append("Needs: %s" % defs[c["value"]]["label"])
			else:
				ok = false
		if gated and ok:
			var p: Dictionary = defs[id].duplicate()
			p["locked_reason"] = ", ".join(reasons)
			out.append(p)
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
			"skill":
				var m := crew.get_member(who)
				if not m.is_empty():
					m["skills"][e["skill"]] = clampi(int(m["skills"].get(e["skill"], 0)) + int(e["delta"]), 0, 100)
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
		"xp": xp,
		"streak": streak,
		"best_scores": best_scores.duplicate(),
		"goals_today": goals_today.duplicate(),
		"goals_done": goals_done.duplicate(),
		"calls_today": calls_today,
		"stats": stats.duplicate(),
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
	xp = int(d.get("xp", 0))
	streak = int(d.get("streak", 0))
	calls_today = int(d.get("calls_today", 0))
	goals_today = d.get("goals_today", []).duplicate()
	goals_done = d.get("goals_done", []).duplicate()
	best_scores = {}
	for k in d.get("best_scores", {}):
		best_scores[k] = int(d["best_scores"][k])
	stats = {}
	for k in d.get("stats", {}):
		stats[k] = int(d["stats"][k])
