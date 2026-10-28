class_name AssetLib
extends RefCounted
## Loads production art by logical id (game/assets/asset_index.json, written by the
## Blender pipeline). The glb import settings already map every surface onto the shared
## res://assets/materials/palette*.tres materials. Callers fall back to primitives when
## an id is absent, so gameplay and tests never depend on art being present.

const INDEX_PATH := "res://assets/asset_index.json"

static var _index: Dictionary = {}
static var _loaded := false
static var _scenes: Dictionary = {}
static var disabled := false  # set by --no-art for A/B performance comparisons


static func _load_index() -> void:
	if _loaded:
		return
	_loaded = true
	if "--no-art" in OS.get_cmdline_user_args():
		disabled = true
		return
	if not FileAccess.file_exists(INDEX_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
	if parsed is Dictionary:
		_index = parsed.get("assets", {})


static func has(id: String) -> bool:
	_load_index()
	return not disabled and _index.has(id) and ResourceLoader.exists(String(_index[id]["path"]))


static func info(id: String) -> Dictionary:
	_load_index()
	return _index.get(id, {})


## Instances the asset under parent, or returns null if it isn't available.
static func spawn(id: String, parent: Node, pos: Vector3 = Vector3.ZERO, yaw: float = 0.0, scale: Vector3 = Vector3.ONE) -> Node3D:
	if not has(id):
		return null
	var path := String(_index[id]["path"])
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var packed: PackedScene = _scenes[path]
	if packed == null:
		return null
	var node: Node3D = packed.instantiate()
	node.position = pos
	node.rotation.y = yaw
	node.scale = scale
	parent.add_child(node)
	return node


## Adds a box collider matching the asset's declared footprint (size_m in the index).
static func add_box_collider(id: String, parent: Node3D, pos: Vector3, yaw: float = 0.0) -> void:
	var size: Array = info(id).get("size_m", [])
	if size.size() != 3:
		return
	var body := Build.static_box(parent, Vector3(size[0], size[1], size[2]), pos + Vector3(0, float(size[1]) / 2.0, 0))
	body.rotation.y = yaw
