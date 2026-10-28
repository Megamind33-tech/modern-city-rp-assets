class_name AssetLib
extends RefCounted
## Loads production art by logical id (game/assets/asset_index.json, written by the
## Blender pipeline). Every mesh gets one shared palette material so the whole town
## renders from a single texture. Callers fall back to primitives when an id is absent,
## so gameplay and tests never depend on art being present.

const INDEX_PATH := "res://assets/asset_index.json"
const PALETTE_PATH := "res://assets/palette.png"

static var _index: Dictionary = {}
static var _loaded := false
static var _scenes: Dictionary = {}
static var _palette_mat: StandardMaterial3D
static var _emissive_mat: StandardMaterial3D
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


static func palette_material() -> StandardMaterial3D:
	if _palette_mat == null:
		_palette_mat = StandardMaterial3D.new()
		_palette_mat.roughness = 0.85
		_palette_mat.vertex_color_use_as_albedo = true
		if ResourceLoader.exists(PALETTE_PATH):
			_palette_mat.albedo_texture = load(PALETTE_PATH)
	return _palette_mat


static func emissive_material() -> StandardMaterial3D:
	if _emissive_mat == null:
		_emissive_mat = palette_material().duplicate()
		_emissive_mat.emission_enabled = true
		_emissive_mat.emission_texture = _emissive_mat.albedo_texture
		_emissive_mat.emission_energy_multiplier = 1.6
	return _emissive_mat


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
	_apply_materials(node)
	parent.add_child(node)
	return node


static func _apply_materials(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var emissive := false
		if mi.mesh:
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				if m and m.resource_name.contains("emissive"):
					emissive = true
		mi.material_override = emissive_material() if emissive else palette_material()
	for c in n.get_children():
		_apply_materials(c)


## Adds a box collider matching the asset's declared footprint (size_m in the index).
static func add_box_collider(id: String, parent: Node3D, pos: Vector3, yaw: float = 0.0) -> void:
	var size: Array = info(id).get("size_m", [])
	if size.size() != 3:
		return
	var body := Build.static_box(parent, Vector3(size[0], size[1], size[2]), pos + Vector3(0, float(size[1]) / 2.0, 0))
	body.rotation.y = yaw
