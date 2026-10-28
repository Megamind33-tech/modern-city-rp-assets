class_name Progression
extends RefCounted
## Long-term motivation rules (data: data/progression.json):
##  - grade(): every call scores 0–100 on outcome, pace vs par, safety and technique → medal + XP
##  - ranks: station XP unlocks titles, more calls per shift and rank-gated upgrades
##  - shift goals: 3 seeded goals a day with cash/XP rewards
## Pure functions over plain dictionaries so everything is unit-testable.

static func data() -> Dictionary:
	return DataDB.load_json("res://data/progression.json")


static func rank_for(xp: int) -> Dictionary:
	var best: Dictionary = {}
	for r in data()["ranks"]:
		if xp >= int(r["xp"]):
			best = r
	return best


static func next_rank(xp: int) -> Dictionary:
	for r in data()["ranks"]:
		if xp < int(r["xp"]):
			return r
	return {}


## Fraction of the way from the current rank to the next (1.0 at max rank).
static func rank_progress(xp: int) -> float:
	var cur := rank_for(xp)
	var nxt := next_rank(xp)
	if nxt.is_empty():
		return 1.0
	return clampf(float(xp - int(cur["xp"])) / float(int(nxt["xp"]) - int(cur["xp"])), 0.0, 1.0)


static func par_seconds(def: Dictionary, severity: int) -> float:
	var pars: Array = def.get("par_seconds_by_severity", [90, 120, 150])
	return float(pars[clampi(severity, 1, pars.size()) - 1])


## Scores a resolved incident instance.
static func grade(def: Dictionary, inst: Dictionary) -> Dictionary:
	var lines: Array = []
	if inst.get("outcome", "") != "success":
		return {"score": 0, "medal": "", "lines": [{"label": "Call not resolved", "pts": 0}], "xp": 10}
	var flags: Dictionary = inst.get("flags", {})
	lines.append({"label": "Job done", "pts": 50})
	var par := par_seconds(def, int(inst.get("severity", 1)))
	var elapsed := float(inst.get("elapsed", 0.0))
	var pace := int(round(25.0 * clampf((par * 2.5 - elapsed) / (par * 1.5), 0.0, 1.0)))
	lines.append({"label": "Pace (par %d:%02d)" % [int(par) / 60, int(par) % 60], "pts": pace})
	var safe := 15 if flags.get("secured", false) and not flags.get("unsafe_cut", false) else 0
	lines.append({"label": "Scene safety", "pts": safe})
	var faults := int(flags.get("stalls", 0)) + int(flags.get("missed_pulls", 0))
	lines.append({"label": "Technique (%d fault%s)" % [faults, "" if faults == 1 else "s"], "pts": maxi(0, 10 - 3 * faults)})
	var score := 0
	for l in lines:
		score += int(l["pts"])
	var medal := ""
	var xp := score
	for m in data()["medals"]:
		if score >= int(m["min"]):
			medal = m["medal"]
			xp += int(m["xp_bonus"])
			break
	if def.get("story", false):
		xp += int(data().get("story_xp_bonus", 0))
	return {"score": score, "medal": medal, "lines": lines, "xp": xp}


## Picks the day's goals (seeded) from those achievable with the calls that can happen.
static func roll_goals(seed_value: int, day: int, possible_defs: Array) -> Array:
	var pool: Array = []
	for g in data()["goals"]:
		var ok := true
		for c in g["when"]:
			if c["type"] == "def" and not possible_defs.has(c["value"]):
				ok = false
		if ok:
			pool.append(g["id"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, day, "goals"])
	var out: Array = []
	while out.size() < int(data()["goals_per_shift"]) and not pool.is_empty():
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out


static func goal(id: String) -> Dictionary:
	for g in data()["goals"]:
		if g["id"] == id:
			return g
	return {}


static func goal_met(g: Dictionary, inst: Dictionary, graded: Dictionary, streak: int) -> bool:
	if inst.get("outcome", "") != "success":
		return false
	var flags: Dictionary = inst.get("flags", {})
	for c in g["when"]:
		match String(c["type"]):
			"def":
				if inst.get("def_id", "") != c["value"]:
					return false
			"flag":
				if flags.get(c["key"], false) != c["value"]:
					return false
			"flag_max":
				if int(flags.get(c["key"], 0)) > int(c["value"]):
					return false
			"medal":
				if graded.get("medal", "") != c["value"]:
					return false
			"elapsed_max":
				if float(inst.get("elapsed", 0.0)) > float(c["value"]):
					return false
			"streak_min":
				if streak < int(c["value"]):
					return false
	return true
