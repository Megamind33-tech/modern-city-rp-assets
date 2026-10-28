extends RefCounted
## Incident generation, state transitions, task ordering and invalid actions.

var runner


func _model(seed_value: int = 42) -> GameModel:
	var m := GameModel.new()
	m.new_game(seed_value)
	return m


func _on_scene(m: GameModel) -> Dictionary:
	var inst := m.offer_incident()
	m.dispatch("quick")
	m.arrive()
	return inst


func test_generation_is_deterministic() -> void:
	var d := IncidentDirector.new()
	var a := d.generate("fallen_tree", 1234)
	var b := d.generate("fallen_tree", 1234)
	runner.eq(JSON.stringify(a), JSON.stringify(b), "same seed gives identical incident")
	var differs := false
	for s in range(1, 40):
		var c := d.generate("fallen_tree", s)
		if c["severity"] != a["severity"] or c["location"] != a["location"] or c["complications"] != a["complications"]:
			differs = true
	runner.check(differs, "different seeds produce variation")


func test_task_counts_follow_severity() -> void:
	var d := IncidentDirector.new()
	for s in range(1, 30):
		var inst := d.generate("fallen_tree", s)
		var cut := 0
		var logs := 0
		for t in inst["tasks"]:
			if t["id"] == "cut_trunk":
				cut = t["required"]
			if t["id"] == "clear_debris":
				logs = t["required"]
		runner.eq(cut, int(inst["severity"]) + 1, "cuts = severity + 1")
		runner.eq(logs, cut, "one log per cut")
		var has_isolate := false
		for t in inst["tasks"]:
			has_isolate = has_isolate or t["id"] == "isolate_power"
		runner.eq(has_isolate, inst["complications"].has("live_wire"), "isolate task only with live wire")
		if inst["complications"].has("live_wire"):
			runner.check(int(inst["severity"]) >= 2, "live wire respects min severity")


func test_state_machine_rejects_invalid_transitions() -> void:
	var m := _model()
	runner.check(not m.dispatch("quick")["ok"], "cannot dispatch without a call")
	runner.check(not m.arrive(), "cannot arrive without dispatch")
	m.offer_incident()
	runner.eq(m.offer_incident(), {}, "no second call while one is active")
	runner.check(not m.dispatch("teleport")["ok"], "unknown dispatch mode refused")
	runner.check(not m.arrive(), "cannot arrive before dispatch")
	runner.check(m.dispatch("drive")["ok"], "dispatch ok")
	runner.check(not m.dispatch("drive")["ok"], "cannot dispatch twice")
	runner.eq(m.progress_task("cut_trunk", {"equipped": ["chainsaw"]})["reason"], "Not on scene", "no work before arrival")
	runner.check(m.arrive(), "arrive ok")
	runner.eq(m.incidents.active["state"], IncidentDirector.ON_SCENE, "on scene")
	runner.check(not m.return_to_station(), "cannot return before resolving")
	runner.eq(m.end_shift()["ok"], false, "cannot end shift mid-call")


func test_task_prerequisites_and_equipment() -> void:
	var m := _model()
	var inst := _on_scene(m)
	runner.eq(m.progress_task("cut_trunk")["reason"], "Needs the chainsaw from the truck" if not inst["complications"].has("live_wire") else "First: Radio the utility to isolate the line", "cut needs saw/isolation")
	runner.eq(m.progress_task("clear_debris")["reason"], "First: Cut the trunk into sections", "logs need cutting first")
	runner.eq(m.progress_task("reopen_road")["reason"], "First: Cut the trunk into sections", "road needs clearing")
	runner.eq(m.progress_task("fly")["reason"], "Nothing to do here", "unknown task refused")


func _find_seed_with(live_wire: bool) -> int:
	var d := IncidentDirector.new()
	for s in range(1, 500):
		var m := GameModel.new()
		m.new_game(s)
		var inst := m.offer_incident()
		if inst["complications"].has("live_wire") == live_wire:
			return s
	return -1


func test_live_wire_blocks_cutting_until_isolated() -> void:
	var s := _find_seed_with(true)
	runner.check(s > 0, "found a live-wire seed")
	var m := _model(s)
	_on_scene(m)
	var saw := {"equipped": ["chainsaw"]}
	runner.eq(m.progress_task("cut_trunk", saw)["reason"], "First: Radio the utility to isolate the line", "blocked by live line")
	runner.check(m.request_isolation()["ok"], "radio call accepted")
	runner.check(not m.request_isolation()["ok"], "duplicate radio call refused")
	m.tick(GameModel.ISOLATION_DELAY - 1.0)
	runner.check(not m.incidents.is_task_done("isolate_power"), "not isolated yet")
	m.tick(1.5)
	runner.check(m.incidents.is_task_done("isolate_power"), "isolated after delay")
	runner.check(m.progress_task("cut_trunk", saw.merged({"index": 0}))["ok"], "can cut now")


func test_full_success_flow_and_duplicate_guard() -> void:
	var s := _find_seed_with(false)
	var m := _model(s)
	var inst := _on_scene(m)
	var money_before := m.economy.money
	var n: int = m.incidents.find_task("cut_trunk")["required"]
	var r := m.progress_task("secure_area", {"by": "theo_vance"})
	runner.check(r["ok"] and r["completed"], "cones placed")
	for i in n:
		runner.check(m.progress_task("cut_trunk", {"equipped": ["chainsaw"], "index": i})["ok"], "cut %d" % i)
		runner.eq(m.progress_task("cut_trunk", {"equipped": ["chainsaw"], "index": i})["reason"], "Already done" if i < n - 1 else "Already done", "same section can't be cut twice")
		runner.check(m.progress_task("clear_debris", {"index": i})["ok"], "log %d" % i)
	runner.check(not inst["flags"].get("unsafe_cut", false), "scene was safe")
	var last := m.progress_task("reopen_road")
	runner.check(last["ok"] and last.has("result"), "reopening resolves the incident")
	runner.eq(last["result"]["outcome"], "success", "success outcome")
	var money_after := m.economy.money
	runner.check(money_after > money_before, "paid for the callout")
	runner.eq(m.resolve("success", "again"), {}, "second resolve ignored")
	runner.eq(m.economy.money, money_after, "no duplicate reward")
	runner.eq(m.world.get_value("%s.road" % inst["location"]), "open", "road recorded open")
	runner.check(m.flags.get("helped_%s" % inst["context"]["resident"], false), "helped flag set")
	runner.check(m.return_to_station(), "return ok")
	runner.check(not m.return_to_station(), "second return refused")
	runner.check(m.end_shift()["ok"], "shift ends")
	runner.eq(m.day, 2, "day advanced")


func test_unsafe_cut_is_recorded_and_costs_trust() -> void:
	var s := _find_seed_with(false)
	var m := _model(s)
	_on_scene(m)
	var trust_before: int = m.crew.get_member("maren_holt")["trust"]
	var r := m.progress_task("cut_trunk", {"equipped": ["chainsaw"], "index": 0})
	runner.eq(r["warning"], "unsafe_cut", "warned once")
	runner.check(m.incidents.active["flags"]["unsafe_cut"], "flag set")
	runner.eq(m.crew.get_member("maren_holt")["trust"], trust_before - 10, "captain trust drops")
	var r2 := m.progress_task("cut_trunk", {"equipped": ["chainsaw"], "index": 1})
	runner.eq(r2["warning"], "", "not warned twice")


func test_timeout_fails_and_damage_persists_overnight() -> void:
	var m := _model(_find_seed_with(false))
	var inst := _on_scene(m)
	var house: String = inst["context"]["house"]
	var loc: String = inst["location"]
	m.tick(inst["time_limit"] + 1.0)
	runner.eq(m.last_result.get("outcome", ""), "failure", "timeout fails")
	runner.eq(m.last_result.get("reason", ""), "timeout", "reason recorded")
	runner.eq(m.world.get_value("%s.roof" % house), "damaged", "roof damaged")
	runner.eq(m.world.get_value("%s.road" % loc), "closed", "road still closed tonight")
	m.tick(5.0)
	runner.eq(m.incidents.history.size(), 1, "timeout not double counted")
	m.return_to_station()
	m.end_shift()
	runner.eq(m.world.get_value("%s.road" % loc), "open", "highways crew clears overnight")
	runner.eq(m.world.get_value("%s.roof" % house), "damaged", "roof stays damaged until repaired")


func test_next_tree_call_prefers_another_street() -> void:
	var m := _model(9)
	var first := _on_scene(m)
	m.abandon()
	m.return_to_station()
	# Ask the director directly for a routine call (bypasses day-2 story incidents).
	var second := m.incidents.offer_next(m.day, m.base_seed, m.world)
	runner.check(second["location"] != first["location"], "second tree call on a different street")
	runner.check(second["uid"] != first["uid"], "unique incident ids")


func _flood(m: GameModel) -> Dictionary:
	var inst := m.offer_incident()
	m.dispatch("quick")
	m.arrive()
	return inst


func test_flood_is_day_two_story_incident_once() -> void:
	var m := _model(9)
	_on_scene(m)
	m.abandon()
	m.return_to_station()
	m.end_shift()
	var inst := _flood(m)
	runner.eq(inst["def_id"], "flooded_cellar", "day-2 call is the Mendes cellar")
	runner.eq(inst["location"], "alder_lane", "at Rosa's")
	runner.check(inst["complications"].has("live_wire"), "fuse box hazard always present")
	m.abandon()
	m.return_to_station()
	m.end_shift()
	runner.eq(m.offer_incident()["def_id"], "fallen_tree", "story incident happens once")


func test_earlier_outcomes_reshape_flood() -> void:
	var base := _model(5)
	base.day = 2
	var plain := base.incidents.generate("flooded_cellar", 77, "", base)
	runner.check(not plain["flags"].get("roof_leak", false), "no leak with intact roof")
	runner.check(not plain["flags"].get("tomas_helps", false), "no helper without history")
	var m := _model(5)
	m.world.set_value("house_mendes.roof", "damaged")
	m.flags["helped_rosa_mendes"] = true
	var hit := m.incidents.generate("flooded_cellar", 77, "", m)
	runner.check(hit["flags"].get("roof_leak", false), "damaged roof leaks into the cellar")
	runner.eq(int(hit["severity"]), mini(int(plain["severity"]) + 1, 3), "damaged roof raises severity")
	runner.check(hit["flags"].get("tomas_helps", false), "Tomás helps the crew that helped Rosa")


func _run_flood_to_pumping(m: GameModel) -> Dictionary:
	var inst := m.incidents.active
	runner.eq(m.progress_task("prime_pump")["reason"], "First: Radio the utility to cut the house supply", "power first")
	m.request_isolation()
	m.tick(GameModel.ISOLATION_DELAY + 0.1)
	runner.check(m.progress_task("lay_hose")["reason"].begins_with("First"), "hose needs the pump placed")
	runner.check(m.progress_task("place_pump")["ok"], "pump placed")
	for i in int(m.incidents.find_task("lay_hose")["required"]):
		runner.check(m.progress_task("lay_hose", {"index": i})["ok"], "hose %d" % i)
	for i in int(m.incidents.find_task("clear_drain")["required"]):
		runner.check(m.progress_task("clear_drain", {"index": i})["ok"], "drain %d" % i)
	for i in 3:
		runner.check(m.progress_task("prime_pump")["ok"], "pull %d" % i)
	return inst


func test_flood_flow_and_timed_pumping() -> void:
	var m := _model(5)
	m.day = 2
	_flood(m)
	_run_flood_to_pumping(m)
	var need: float = m.incidents.find_task("pump_out")["auto_seconds"]
	runner.eq(m.progress_task("pump_out")["reason"], "In progress — pump the cellar dry", "pumping can't be skipped by hand")
	runner.eq(m.progress_task("make_safe")["reason"], "First: Pump the cellar dry", "can't sign off a wet cellar")
	m.tick(need * 0.5)
	runner.check(absf(m.auto_fraction("pump_out") - 0.5) < 0.05, "pumping half way")
	m.tick(need * 0.6)
	runner.check(m.incidents.is_task_done("pump_out"), "cellar pumped dry")
	var r := m.progress_task("make_safe")
	runner.eq(r.get("result", {}).get("outcome", ""), "success", "flood resolved")
	runner.eq(m.world.get_value("house_mendes.cellar"), "dry", "cellar state recorded")
	m.return_to_station()
	runner.check(m.story.fired.has("cellar_saved"), "Rosa reacts to the saved cellar")


func test_tomas_speeds_pumping() -> void:
	var m := _model(5)
	m.day = 2
	m.flags["helped_rosa_mendes"] = true
	_flood(m)
	_run_flood_to_pumping(m)
	var need: float = m.incidents.find_task("pump_out")["auto_seconds"]
	m.tick(need * 0.85)
	runner.check(m.incidents.is_task_done("pump_out"), "faster with Tomás holding the torch")
	runner.check(m.story.fired.has("tomas_torch"), "Tomás remembers the tree rescue")
