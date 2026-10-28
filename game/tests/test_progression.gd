extends RefCounted
## Grading, XP/ranks, streaks, shift goals, multi-call shifts and rank-gated upgrades.

var runner


func _model(seed_value: int = 4242) -> GameModel:
	var m := GameModel.new()
	m.new_game(seed_value)
	return m


## Plays the offered tree call to success. cones: secure first; stalls: chain stalls noted.
func _clear_tree(m: GameModel, cones: bool = true, stalls: int = 0, extra_time: float = 0.0) -> Dictionary:
	var inst := m.offer_incident()
	if inst.is_empty() or inst["def_id"] != "fallen_tree":
		return {}
	m.dispatch("quick")
	m.arrive()
	if inst["complications"].has("live_wire"):
		m.request_isolation()
		m.tick(GameModel.ISOLATION_DELAY + 0.1)
	if cones:
		m.progress_task("secure_area", {"by": "theo_vance"})
	for s in stalls:
		m.note("stalls")
	m.tick(extra_time)
	for i in int(m.incidents.find_task("cut_trunk")["required"]):
		m.progress_task("cut_trunk", {"equipped": ["chainsaw"], "index": i})
		m.progress_task("clear_debris", {"index": i})
	var r := m.progress_task("reopen_road")
	m.return_to_station()
	return r.get("result", {})


func test_grade_rewards_pace_safety_technique() -> void:
	var def: Dictionary = DataDB.incidents()["fallen_tree"]
	var perfect := Progression.grade(def, {"outcome": "success", "severity": 1, "elapsed": 40.0, "flags": {"secured": true}})
	runner.eq(perfect["score"], 100, "fast, safe, clean = 100")
	runner.eq(perfect["medal"], "gold", "gold medal")
	var sloppy := Progression.grade(def, {"outcome": "success", "severity": 1, "elapsed": 150.0, "flags": {"stalls": 2}})
	runner.eq(sloppy["score"], 50 + 0 + 0 + 4, "slow, unsafe, two stalls")
	runner.eq(sloppy["medal"], "bronze", "still a bronze for getting it done")
	var mid := Progression.grade(def, {"outcome": "success", "severity": 1, "elapsed": 105.0, "flags": {"secured": true, "stalls": 1}})
	runner.check(mid["score"] > sloppy["score"] and mid["score"] < perfect["score"], "pace scales between par and 2.5x par")
	runner.eq(Progression.grade(def, {"outcome": "failure"})["medal"], "", "no medal on failure")
	runner.check(Progression.grade(DataDB.incidents()["flooded_cellar"], {"outcome": "success", "severity": 1, "elapsed": 60.0, "flags": {"secured": true}})["xp"] > perfect["xp"], "story calls give bonus XP")


func test_ranks_from_xp() -> void:
	runner.eq(int(Progression.rank_for(0)["rank"]), 1, "start rank 1")
	runner.eq(int(Progression.rank_for(250)["rank"]), 2, "rank 2 at 250")
	runner.eq(int(Progression.rank_for(99999)["rank"]), 5, "cap at rank 5")
	runner.check(absf(Progression.rank_progress(125) - 0.5) < 0.01, "half way to rank 2")
	runner.eq(Progression.rank_progress(99999), 1.0, "full bar at max rank")


func test_resolve_awards_xp_best_and_rank_up() -> void:
	var m := _model()
	var r := _clear_tree(m)
	runner.eq(r["grade"]["medal"], "gold", "instant clean clear is gold")
	runner.eq(m.xp, int(r["xp_gained"]), "xp banked")
	runner.check(r["new_best"], "first score is a personal best")
	runner.eq(int(m.best_scores["fallen_tree"]), int(r["grade"]["score"]), "best recorded")
	runner.check(not r["rank_up"].is_empty(), "a gold first call promotes to rank 2")
	runner.eq(int(m.stats["gold"]), 1, "medal counted")


func test_streak_bonus_and_reset() -> void:
	var m := _model()
	m.xp = 650  # rank 3: three calls per shift
	_clear_tree(m)
	var r2 := _clear_tree(m)
	runner.eq(m.streak, 2, "two clean calls")
	runner.check(r2["payout"]["lines"].any(func(l: Dictionary) -> bool: return String(l["label"]).begins_with("Clean streak")), "streak bonus paid")
	var inst := m.offer_incident()
	m.dispatch("quick")
	m.arrive()
	m.abandon()
	runner.eq(m.streak, 0, "failure resets the streak")


func test_calls_per_shift_limit() -> void:
	var m := _model()
	runner.eq(m.calls_per_shift(), 2, "rank 1 has two calls a shift")
	m.xp = 0
	_clear_tree(m)
	m.xp = 0  # keep rank 1 for this test
	_clear_tree(m)
	runner.eq(m.calls_remaining(), 0, "shift's calls used")
	runner.eq(m.offer_incident(), {}, "no third call at rank 1")
	m.end_shift()
	runner.eq(m.calls_today, 0, "new shift resets calls")


func test_goals_seeded_achievable_and_paid() -> void:
	var m := _model(77)
	runner.eq(m.goals_today.size(), 3, "three goals")
	runner.check(not m.goals_today.has("clean_pulls"), "no flood goal before the flood can happen")
	var again := _model(77)
	runner.eq(again.goals_today, m.goals_today, "goals are seeded")
	m.goals_today = ["no_stall", "delegate", "fast"]
	var money_before := m.economy.money
	var r := _clear_tree(m)
	runner.eq(r["goals_completed"].size(), 3, "all three goals met by a clean fast delegated clear")
	runner.check(m.economy.money - money_before > int(r["payout"]["total"]), "goal rewards paid on top")
	var m2 := _model(77)
	m2.goals_today = ["no_stall"]
	var r2 := _clear_tree(m2, true, 1)
	runner.eq(r2["goals_completed"].size(), 0, "a stall fails the no-stall goal")
	m.end_shift()
	runner.eq(m.goals_done.size(), 0, "new goals each day")


func test_rank_gated_upgrades_visible_then_unlocked() -> void:
	var m := _model()
	var locked: Array = m.locked_projects().map(func(p: Dictionary) -> String: return p["id"])
	runner.check(locked.has("cone_trailer") and locked.has("chainsaw_pro"), "future upgrades shown as locked")
	runner.check(not m.available_projects().any(func(p: Dictionary) -> bool: return p["id"] == "cone_trailer"), "not buyable yet")
	m.xp = 250
	runner.check(m.available_projects().any(func(p: Dictionary) -> bool: return p["id"] == "cone_trailer"), "rank 2 unlocks the cone trailer")
	m.xp = 650
	var pro: Array = m.locked_projects().filter(func(p: Dictionary) -> bool: return p["id"] == "chainsaw_pro")
	runner.eq(pro[0]["locked_reason"], "Needs: Priya services the chainsaw", "pro chain needs the service first")
	m.economy.money = 5000
	m.buy_project("service_chainsaw")
	runner.check(m.buy_project("chainsaw_pro")["ok"], "pro chain buyable after service")
	runner.eq(m.equipment["chainsaw"], 3, "chainsaw level 3")
	var theo_safety: int = m.crew.get_member("theo_vance")["skills"]["safety"]
	m.buy_project("theo_training")
	runner.eq(m.crew.get_member("theo_vance")["skills"]["safety"], theo_safety + 25, "training raises Theo's skill")


func test_progression_survives_save() -> void:
	var m := _model()
	_clear_tree(m)
	SaveSystem.save(m, "user://prog.save")
	var m2: GameModel = SaveSystem.load_game("user://prog.save")["model"]
	runner.eq(m2.xp, m.xp, "xp saved")
	runner.eq(m2.goals_today, m.goals_today, "goals saved")
	runner.eq(m2.best_scores, m.best_scores, "bests saved")
	runner.eq(m2.calls_today, 1, "calls today saved")
	runner.eq(SaveSystem.canonical(m2.to_dict()), SaveSystem.canonical(m.to_dict()), "full roundtrip")
	SaveSystem.delete("user://prog.save")
