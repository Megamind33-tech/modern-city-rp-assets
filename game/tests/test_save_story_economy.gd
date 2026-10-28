extends RefCounted
## Save integrity/migration, story conditions, projects and economy.

var runner

const PATH := "user://test_slot.save"


func _played_model() -> GameModel:
	var m := GameModel.new()
	m.new_game(77)
	m.offer_incident()
	m.dispatch("quick")
	m.arrive()
	m.progress_task("secure_area", {"by": "player"})
	m.tick(12.5)
	return m


func test_save_load_roundtrip_mid_incident() -> void:
	SaveSystem.delete(PATH)
	var m := _played_model()
	runner.eq(SaveSystem.save(m, PATH), OK, "save ok")
	var r := SaveSystem.load_game(PATH)
	runner.check(r["model"] != null, "loaded")
	runner.eq(r["source"], "main", "from main file")
	var m2: GameModel = r["model"]
	runner.eq(JSON.stringify(m2.to_dict()), JSON.stringify(m.to_dict()), "state identical after roundtrip")
	runner.eq(typeof(m2.economy.money), TYPE_INT, "money stays int")
	runner.eq(m2.incidents.active["state"], IncidentDirector.ON_SCENE, "resumes on scene")
	runner.check(m2.incidents.is_task_done("secure_area"), "progress kept")
	runner.check(m2.progress_task("secure_area")["ok"] == false, "loaded model still validates")
	SaveSystem.delete(PATH)


func test_roundtrip_after_full_day() -> void:
	var m := GameModel.new()
	m.new_game(4242)
	m.offer_incident()
	m.dispatch("quick")
	m.arrive()
	m.progress_task("secure_area", {"by": "theo_vance"})
	for i in int(m.incidents.find_task("cut_trunk")["required"]):
		m.progress_task("cut_trunk", {"equipped": ["chainsaw"], "index": i})
		m.progress_task("clear_debris", {"index": i})
	m.progress_task("reopen_road")
	m.return_to_station()
	m.buy_project("service_chainsaw")
	m.end_shift()
	SaveSystem.save(m, PATH)
	var m2: GameModel = SaveSystem.load_game(PATH)["model"]
	runner.eq(SaveSystem.canonical(m2.to_dict()), SaveSystem.canonical(m.to_dict()), "full-day state survives reload")
	runner.eq(typeof(m2.incidents.history[0]["severity"]), TYPE_INT, "history ints restored")
	runner.eq(m2.equipment["chainsaw"], 2, "upgrade persisted")
	SaveSystem.delete(PATH)


func test_corrupt_save_falls_back_to_backup() -> void:
	SaveSystem.delete(PATH)
	var m := _played_model()
	SaveSystem.save(m, PATH)
	m.economy.earn(5, "second save")
	SaveSystem.save(m, PATH)  # previous good file becomes .bak
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{\"format\":\"emergency-crew-save\",\"version\":1,\"checksum\":\"x\",\"payload\":\"{}\"}")
	f.close()
	var r := SaveSystem.load_game(PATH)
	runner.eq(r["source"], "backup", "used backup")
	runner.eq(r["model"].economy.money, m.economy.money - 5, "backup is the previous save")
	f = FileAccess.open(PATH + ".bak", FileAccess.WRITE)
	f.store_string("garbage")
	f.close()
	runner.eq(SaveSystem.load_game(PATH)["model"], null, "both corrupt -> no model, no crash")
	SaveSystem.delete(PATH)


func test_migration_from_v0() -> void:
	var m := GameModel.new()
	m.new_game(3)
	var d := m.to_dict()
	d["funds"] = d["money"]
	d.erase("money")
	d.erase("equipment")
	var migrated := SaveSystem.migrate(d, 0)
	runner.eq(migrated["money"], m.economy.money, "funds -> money")
	runner.eq(migrated["equipment"], {"chainsaw": 1}, "equipment table added")
	runner.eq(SaveSystem.migrate(d, -5), {}, "unknown old version refused")
	var payload := JSON.stringify(d)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": SaveSystem.FORMAT, "version": 0, "checksum": payload.md5_text(), "payload": payload}))
	f.close()
	var r := SaveSystem.load_game(PATH)
	runner.check(r["model"] != null, "v0 file loads through migration")
	runner.eq(r["model"].economy.money, m.economy.money, "money preserved")
	f = FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": SaveSystem.FORMAT, "version": 99, "checksum": payload.md5_text(), "payload": payload}))
	f.close()
	runner.eq(SaveSystem.load_game(PATH)["model"], null, "newer-version save refused")
	SaveSystem.delete(PATH)


func test_story_intro_and_consequence_next_day() -> void:
	var m := GameModel.new()
	m.new_game(5)
	runner.eq(m.pop_fragment().get("id", ""), "intro_maren", "intro plays on new game")
	runner.eq(m.pop_fragment(), {}, "nothing else queued")
	# Force an Alder Lane success and check Rosa remembers it the next morning.
	m.incidents.active = m.incidents.generate("fallen_tree", 11, "alder_lane")
	m.incidents.active["uid"] = "INC-T"
	m.dispatch("quick")
	m.arrive()
	m.fragments.clear()
	m.resolve("success", "test")
	m.return_to_station()
	var ids: Array = []
	for fr in m.fragments:
		ids.append(fr["id"])
	runner.check(ids.has("rosa_thanks"), "Rosa calls after the rescue")
	runner.check(m.community.remembers("rosa_mendes", "tree_cleared_alder_lane"), "Rosa remembers")
	m.fragments.clear()
	m.end_shift()
	ids.clear()
	for fr in m.fragments:
		ids.append(fr["id"])
	runner.check(ids.has("rosa_pastries"), "pastries appear next day")
	m.fragments.clear()
	m.end_shift()
	runner.check(m.fragments.filter(func(f): return f["id"] == "rosa_pastries").is_empty(), "pastries only once")


func test_failure_unlocks_roof_project_and_repair_persists() -> void:
	var m := GameModel.new()
	m.new_game(5)
	var ids_before: Array = m.available_projects().map(func(p): return p["id"])
	runner.check(not ids_before.has("repair_roof_house_mendes"), "no roof project before damage")
	m.incidents.active = m.incidents.generate("fallen_tree", 11, "alder_lane")
	m.incidents.active["uid"] = "INC-T"
	m.dispatch("quick")
	m.arrive()
	m.abandon()
	m.return_to_station()
	var ids: Array = m.available_projects().map(func(p): return p["id"])
	runner.check(ids.has("repair_roof_house_mendes"), "roof project unlocked by damage")
	m.economy.money = 100
	runner.eq(m.buy_project("repair_roof_house_mendes")["ok"], false, "can't afford")
	runner.eq(m.economy.money, 100, "no money taken on refusal")
	m.economy.money = 1000
	var aff := m.community.affinity("rosa_mendes")
	runner.check(m.buy_project("repair_roof_house_mendes")["ok"], "bought")
	runner.eq(m.world.get_value("house_mendes.roof"), "repaired", "roof repaired")
	runner.eq(m.community.affinity("rosa_mendes"), aff + 20, "Rosa appreciates it")
	runner.eq(m.buy_project("repair_roof_house_mendes")["ok"], false, "can't buy twice")
	runner.check(m.fragments.any(func(f): return f["id"] == "roof_patched_rosa"), "Rosa reacts")


func test_economy_rules() -> void:
	var e := Economy.new()
	e.money = 100
	runner.check(not e.spend(-5, "neg"), "negative spend refused")
	runner.check(not e.spend(101, "too much"), "overspend refused")
	runner.check(e.spend(100, "ok"), "exact spend ok")
	runner.eq(e.money, 0, "balance")
	e.earn(-50, "neg earn")
	runner.eq(e.money, 0, "negative earn ignored")
	var def := {"base_reward": 400, "fuel_cost": 40}
	var fast := Economy.mission_payout(def, {"outcome": "success", "severity": 1, "elapsed": 60.0, "time_limit": 300.0, "flags": {"secured": true}})
	runner.eq(fast["total"], 400 + 60 + 40 - 40, "fast safe payout")
	var unsafe := Economy.mission_payout(def, {"outcome": "success", "severity": 3, "elapsed": 250.0, "time_limit": 300.0, "flags": {"secured": true, "unsafe_cut": true}})
	runner.eq(unsafe["total"], 600 - 40, "no safety bonus after unsafe cut")
	var fail := Economy.mission_payout(def, {"outcome": "failure", "severity": 2})
	runner.eq(fail["total"], 120 - 40, "attendance only on failure")


func test_crew_mission_effects_and_rest() -> void:
	var m := GameModel.new()
	m.new_game(5)
	var theo_before: Dictionary = m.crew.get_member("theo_vance").duplicate(true)
	var maren_before: Dictionary = m.crew.get_member("maren_holt").duplicate(true)
	m.crew.apply_mission({"outcome": "success", "severity": 2, "flags": {"delegated_secure": true}})
	var theo: Dictionary = m.crew.get_member("theo_vance")
	runner.check(theo["fatigue"] > theo_before["fatigue"], "attending crew tire")
	runner.check(theo["xp"] > theo_before["xp"], "and learn")
	runner.eq(theo["trust"], theo_before["trust"] + 5, "delegation builds trust")
	runner.eq(m.crew.get_member("maren_holt")["fatigue"], maren_before["fatigue"], "crew at station unaffected")
	m.crew.rest_day()
	runner.eq(m.crew.get_member("theo_vance")["fatigue"], 0, "rest clears fatigue")
	m.crew.adjust("theo_vance", "morale", 500)
	runner.eq(m.crew.get_member("theo_vance")["morale"], 100, "stats clamp")
