class_name Build
extends RefCounted
## Primitive mesh helpers with a shared material cache (one material per colour keeps
## draw-call batching possible and avoids thousands of duplicate materials on mobile).
## Placeholder geometry only — see ART_BIBLE.md for the production replacement plan.

const C_GRASS := Color(0.42, 0.62, 0.36)
const C_ROAD := Color(0.24, 0.25, 0.28)
const C_PAVE := Color(0.70, 0.68, 0.63)
const C_LINE := Color(0.95, 0.90, 0.75)
const C_BRICK := Color(0.71, 0.30, 0.24)
const C_RED := Color(0.89, 0.29, 0.23)
const C_AMBER := Color(0.95, 0.66, 0.23)
const C_NAVY := Color(0.11, 0.16, 0.23)
const C_CREAM := Color(0.96, 0.92, 0.85)
const C_TEAL := Color(0.18, 0.61, 0.60)
const C_BARK := Color(0.40, 0.28, 0.18)
const C_WOOD := Color(0.78, 0.62, 0.42)
const C_LEAF := Color(0.30, 0.52, 0.26)
const C_GLASS := Color(0.62, 0.82, 0.90)
const C_TARP := Color(0.20, 0.42, 0.78)

static var _mats: Dictionary = {}


static func mat(c: Color, emissive: bool = false) -> StandardMaterial3D:
	var key := "%s|%s" % [c.to_html(), emissive]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.5
	_mats[key] = m
	return m


static func box(parent: Node, size: Vector3, pos: Vector3, c: Color, collide: bool = false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(parent, mesh, pos, c, collide, size)


static func cyl(parent: Node, radius: float, height: float, pos: Vector3, c: Color, collide: bool = false, segments: int = 10) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return _add(parent, mesh, pos, c, collide, Vector3(radius * 2, height, radius * 2))


static func sphere(parent: Node, radius: float, pos: Vector3, c: Color, segments: int = 10) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = segments
	mesh.rings = maxi(4, segments / 2)
	return _add(parent, mesh, pos, c, false, Vector3.ZERO)


static func prism(parent: Node, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var mesh := PrismMesh.new()
	mesh.size = size
	return _add(parent, mesh, pos, c, false, Vector3.ZERO)


static func capsule(parent: Node, radius: float, height: float, pos: Vector3, c: Color) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 3
	return _add(parent, mesh, pos, c, false, Vector3.ZERO)


static func label(parent: Node, text: String, pos: Vector3, size: int = 48, c: Color = C_CREAM) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.modulate = c
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.6)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos
	parent.add_child(l)
	return l


static func static_box(parent: Node, size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	body.position = pos
	parent.add_child(body)
	return body


static func _add(parent: Node, mesh: Mesh, pos: Vector3, c: Color, collide: bool, col_size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(c)
	mi.position = pos
	parent.add_child(mi)
	if collide:
		static_box(parent, col_size, pos)
	return mi


## A rough stylised person: body capsule, head, and a hi-vis band. Returns the root.
static func person(parent: Node, body_color: Color, head_color: Color = Color(0.87, 0.70, 0.56)) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	capsule(root, 0.32, 1.2, Vector3(0, 0.75, 0), body_color)
	cyl(root, 0.335, 0.12, Vector3(0, 0.95, 0), C_AMBER, false, 10)
	sphere(root, 0.24, Vector3(0, 1.55, 0), head_color)
	box(root, Vector3(0.36, 0.12, 0.12), Vector3(0, 1.58, -0.18), Color(0.15, 0.15, 0.15))
	return root
