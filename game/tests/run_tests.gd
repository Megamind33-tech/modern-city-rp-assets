extends SceneTree
## Headless test runner:  godot --headless --path game -s res://tests/run_tests.gd
## Runs every test_* method in every tests/test_*.gd file. Exit code 0 only if all pass.

var failures: Array = []
var passed := 0
var _current := ""


func _initialize() -> void:
	var files: Array = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			var inst: Object = script.new()
			inst.set("runner", self)
			_current = "%s::%s" % [f, name]
			var before := failures.size()
			inst.call(name)
			if failures.size() == before:
				passed += 1
				print("  PASS ", _current)
			if inst is Node:
				inst.free()
	print("\n%d passed, %d failed" % [passed, failures.size()])
	for fail in failures:
		print("  FAIL ", fail)
	quit(0 if failures.is_empty() else 1)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("%s: %s" % [_current, msg])


func eq(a: Variant, b: Variant, msg: String) -> void:
	if a != b:
		failures.append("%s: %s (got %s, expected %s)" % [_current, msg, str(a), str(b)])
