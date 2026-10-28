class_name TownBuilder
extends Node3D
## Builds the compact Kettleford test town from primitives and keeps persistent
## world state (roof damage, log piles) visible. Layout is driven by data/locations.json.

const STREET_Z := 0.0
const STREET_HALF := 4.0
const LANE_LEN := 75.0
const ROOF_PITCH := 0.563  # atan(2.4 / 3.8): rise over half-span of the roof prism

var world: WorldState
var _house_roofs: Dictionary = {}  # house id -> Node3D holding roof-state visuals
var _log_piles: Dictionary = {}    # location id -> Node3D
var _barriers: Dictionary = {}     # location id -> Node3D shown while the road is closed


func build(world_state: WorldState) -> void:
	_ground()
	_street(Vector3(55, 0, STREET_Z), Vector3(200, 0, STREET_HALF * 2), true)
	_station()
	var locs := DataDB.locations()
	for id in locs:
		var loc: Dictionary = locs[id]
		if not loc.has("house"):
			continue
		var x := float(loc["anchor"][0])
		_street(Vector3(x, 0, LANE_LEN / 2 + STREET_HALF), Vector3(STREET_HALF * 2, 0, LANE_LEN), false)
		Build.label(self, String(loc["name"]).to_upper(), Vector3(x - 5.5, 3.2, 7), 64, Build.C_CREAM)
		_lane_houses(id, x, float(loc["anchor"][1]), String(loc["house"]))
	_filler()
	set_world(world_state)


## Points the town at a (new) model's world state, e.g. after loading a save.
func set_world(world_state: WorldState) -> void:
	if world and world.changed.is_connected(_on_world_changed):
		world.changed.disconnect(_on_world_changed)
	world = world_state
	world.changed.connect(_on_world_changed)
	refresh()


func refresh() -> void:
	for house in _house_roofs:
		_apply_roof(house)
	for loc in _log_piles:
		_log_piles[loc].visible = world.get_value("%s.log_pile" % loc, false) == true
	for loc in _barriers:
		_barriers[loc].visible = world.get_value("%s.road" % loc, "open") == "closed"


func _on_world_changed(_key: String, _value: Variant) -> void:
	refresh()


func _ground() -> void:
	var g := Build.box(self, Vector3(320, 0.2, 220), Vector3(55, -0.1, 30), Build.C_GRASS)
	g.name = "Ground"
	Build.static_box(self, Vector3(320, 0.2, 220), Vector3(55, -0.1, 30))


func _street(center: Vector3, size: Vector3, along_x: bool) -> void:
	Build.box(self, Vector3(size.x, 0.04, size.z), center + Vector3(0, 0.02, 0), Build.C_ROAD)
	# Pavements either side and a dashed centre line.
	if along_x:
		for side in [-1, 1]:
			Build.box(self, Vector3(size.x, 0.12, 1.6), center + Vector3(0, 0.06, side * (size.z / 2 + 0.8)), Build.C_PAVE)
		var n := int(size.x / 6)
		for i in n:
			Build.box(self, Vector3(2.4, 0.05, 0.18), Vector3(center.x - size.x / 2 + 3 + i * 6, 0.05, center.z), Build.C_LINE)
	else:
		for side in [-1, 1]:
			Build.box(self, Vector3(1.6, 0.12, size.z), center + Vector3(side * (size.x / 2 + 0.8), 0.06, 0), Build.C_PAVE)
		var n := int(size.z / 6)
		for i in n:
			Build.box(self, Vector3(0.18, 0.05, 2.4), Vector3(center.x, 0.05, center.z - size.z / 2 + 3 + i * 6), Build.C_LINE)


func _station() -> void:
	var root := Node3D.new()
	root.name = "Station"
	add_child(root)
	# Apron
	Build.box(root, Vector3(24, 0.06, 10), Vector3(0, 0.03, -7.5), Build.C_PAVE)
	if AssetLib.spawn("station_hall", root, Vector3(0, 0, -17.5), PI) != null:
		AssetLib.add_box_collider("station_hall", root, Vector3(0, 0, -17.5), PI)
		var sign_a := Build.label(root, "KETTLEFORD EMERGENCY STATION", Vector3(0, 7.6, -11.8), 64, Build.C_CREAM)
		sign_a.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		_station_props(root)
		return
	# Main hall with two bays (primitive fallback)
	Build.box(root, Vector3(22, 7, 10), Vector3(0, 3.5, -17.5), Build.C_BRICK, true)
	Build.box(root, Vector3(22.6, 0.6, 10.6), Vector3(0, 7.3, -17.5), Build.C_NAVY)
	for bx in [-5.0, 5.0]:
		Build.box(root, Vector3(7, 5, 0.2), Vector3(bx, 2.5, -12.45), Color(0.85, 0.83, 0.78))
		for row in 5:
			Build.box(root, Vector3(7, 0.06, 0.05), Vector3(bx, 0.6 + row, -12.33), Color(0.65, 0.63, 0.6))
	# Tower
	Build.box(root, Vector3(4, 11, 4), Vector3(-13, 5.5, -19), Build.C_BRICK, true)
	Build.prism(root, Vector3(4.4, 2, 4.4), Vector3(-13, 12, -19), Build.C_NAVY)
	Build.sphere(root, 0.35, Vector3(-13, 9.5, -16.9), Build.C_AMBER).material_override = Build.mat(Build.C_AMBER, true)
	var sign := Build.label(root, "KETTLEFORD EMERGENCY STATION", Vector3(0, 6.2, -12.3), 72, Build.C_CREAM)
	sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_station_props(root)


func _station_props(root: Node3D) -> void:
	# Bins, bench, flower tubs: small life signals.
	Build.box(root, Vector3(1.8, 0.5, 0.6), Vector3(9, 0.25, -11.5), Build.C_WOOD, true)
	for fx in [-10.5, 10.5]:
		Build.cyl(root, 0.6, 0.6, Vector3(fx, 0.3, -11.8), Build.C_NAVY)
		Build.sphere(root, 0.55, Vector3(fx, 0.85, -11.8), Color(0.85, 0.4, 0.55), 8)


## Houses face their street: yaw rotates the authored front (−Z) toward the road.
func _house(parent: Node3D, pos: Vector3, yaw: float, wall: Color, house_id: String = "", variant: int = 0) -> void:
	var h := Node3D.new()
	h.position = pos
	h.rotation.y = yaw
	parent.add_child(h)
	var asset_id := "house_%s" % "abcd"[variant % 4]
	if AssetLib.spawn(asset_id, h) != null:
		AssetLib.add_box_collider(asset_id, h, Vector3.ZERO)
	else:
		Build.box(h, Vector3(7, 4, 8), Vector3(0, 2, 0), wall, true)
		var roof := Build.prism(h, Vector3(8.4, 2.4, 7.6), Vector3(0, 5.2, 0), Color(0.36, 0.30, 0.30))
		roof.rotation.y = PI / 2
		Build.box(h, Vector3(1.1, 2.0, 0.1), Vector3(0, 1.0, -4.02), Build.C_NAVY)
		for wx in [-2.4, 2.4]:
			Build.box(h, Vector3(1.4, 1.1, 0.1), Vector3(wx, 2.4, -4.02), Build.C_GLASS)
	if house_id != "":
		var state := Node3D.new()
		state.name = "RoofState"
		h.add_child(state)
		_house_roofs[house_id] = state
		Build.label(h, house_id.trim_prefix("house_").capitalize(), Vector3(0, 2.8, -5.4), 40)


func _apply_roof(house_id: String) -> void:
	var state: Node3D = _house_roofs[house_id]
	for c in state.get_children():
		c.queue_free()
	var roof_state: String = world.get_value("%s.roof" % house_id, "intact")
	# Overlays are authored in house-local space on the front (−Z) roof slope.
	if roof_state == "damaged" and AssetLib.spawn("roof_damage", state) != null:
		return
	if roof_state == "repaired" and AssetLib.spawn("roof_patch", state) != null:
		return
	match roof_state:
		"damaged":
			# Blue tarp and a fallen limb: the damage stays until the station pays to repair it.
			# Primitive fallback: tarp on the front (−Z) slope at ROOF_PITCH.
			var tarp := Build.box(state, Vector3(6.0, 0.1, 3.2), Vector3(0, 5.5, -1.7), Build.C_TARP)
			tarp.rotation.x = -ROOF_PITCH
			var limb := Build.cyl(state, 0.3, 7.0, Vector3(-1.0, 6.0, 1.2), Build.C_BARK)
			limb.rotation = Vector3(0.3, 0.4, 1.25)
			Build.sphere(state, 1.5, Vector3(-3.6, 5.6, 2.2), Build.C_LEAF, 8)
			Build.sphere(state, 1.1, Vector3(-4.2, 1.0, 3.6), Build.C_LEAF, 8)
			for k in 3:
				var d := Build.box(state, Vector3(0.6, 0.15, 0.4), Vector3(-4.6 + k * 0.5, 0.08, -1.0 + k * 0.7), Color(0.36, 0.30, 0.30))
				d.rotation.y = k * 0.7
		"repaired":
			# New tiles read slightly brighter than the old roof.
			var patch := Build.box(state, Vector3(4.0, 0.08, 2.6), Vector3(0, 5.5, -1.7), Color(0.62, 0.38, 0.32))
			patch.rotation.x = -ROOF_PITCH


func _lane_houses(loc_id: String, x: float, anchor_z: float, house_id: String) -> void:
	var palette := [Color(0.93, 0.86, 0.70), Color(0.80, 0.88, 0.86), Color(0.94, 0.78, 0.66), Color(0.86, 0.84, 0.92)]
	var i := 0
	for z in range(12, int(LANE_LEN), 15):
		for side in [-1, 1]:
			var pos := Vector3(x + side * 12.0, 0, float(z))
			if side == 1 and absf(z - anchor_z) < 8:
				continue  # the incident house is placed explicitly below
			_house(self, pos, side * PI / 2, palette[i % palette.size()], "", i + int(x))
			i += 1
	# Incident house sits on the +x side, its garden oak is what falls.
	_house(self, Vector3(x + 12.5, 0, anchor_z + 3.0), PI / 2, Color(0.97, 0.80, 0.55), house_id, 0 if loc_id == "alder_lane" else 2)
	var pile := Node3D.new()
	pile.name = "LogPile_" + loc_id
	add_child(pile)
	if AssetLib.spawn("log_pile", pile, Vector3(x - 7.2, 0, anchor_z - 4.0), PI / 2) == null:
		for k in 4:
			var lg := Build.cyl(pile, 0.32, 1.9, Vector3(x - 7.2, 0.35 + (k / 2) * 0.6, anchor_z - 4.0 + (k % 2) * 0.7), Build.C_WOOD)
			lg.rotation.z = PI / 2
	_log_piles[loc_id] = pile
	var barrier := Node3D.new()
	barrier.name = "Barrier_" + loc_id
	barrier.position = Vector3(x, 0, 9.0)
	add_child(barrier)
	Build.box(barrier, Vector3(7.0, 0.35, 0.15), Vector3(0, 1.0, 0), Build.C_RED)
	for bx in [-3.2, 3.2]:
		Build.box(barrier, Vector3(0.15, 1.1, 0.15), Vector3(bx, 0.55, 0), Build.C_CREAM)
	Build.label(barrier, "ROAD CLOSED", Vector3(0, 1.9, 0), 40, Build.C_AMBER)
	_barriers[loc_id] = barrier


func _filler() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	# Street trees along the main road and lanes, kept off the carriageway.
	for i in 26:
		var x := rng.randf_range(-30, 145)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var z := side * rng.randf_range(7.5, 10.0)
		if absf(x) < 14 and side < 0:
			continue  # station frontage
		if absf(x - 60) < 7 or absf(x - 120) < 7:
			continue  # lane junctions
		_tree(Vector3(x, 0, z), rng.randf_range(0.8, 1.2), "tree_street")
	var locs := DataDB.locations()
	for id in locs:
		if not locs[id].has("house"):
			continue
		var lane_x := float(locs[id]["anchor"][0])
		var anchor_z := float(locs[id]["anchor"][1])
		for z in range(20, 72, 9):
			if absf(z - anchor_z) < 10:
				continue  # keep the incident verge clear for the log pile
			_tree(Vector3(lane_x - 7.0, 0, float(z) + rng.randf_range(-2, 2)), rng.randf_range(0.7, 1.0), "tree_oak_a" if z % 2 == 0 else "tree_oak_b")
	# Houses along the north side of the main street.
	var cols := [Color(0.92, 0.84, 0.74), Color(0.78, 0.84, 0.90), Color(0.90, 0.76, 0.70)]
	var k := 0
	for x in [30.0, 85.0, 100.0, 140.0]:
		_house(self, Vector3(x, 0, 14), 0.0, cols[k % 3], "", k + 1)
		k += 1


func _tree(pos: Vector3, s: float, asset_id: String = "tree_street") -> void:
	if AssetLib.spawn(asset_id, self, pos, fmod(pos.x * 1.7, TAU), Vector3.ONE * s) != null:
		Build.static_box(self, Vector3(0.5, 2.0, 0.5), pos + Vector3(0, 1.0, 0))
		return
	Build.cyl(self, 0.22 * s, 2.4 * s, pos + Vector3(0, 1.2 * s, 0), Build.C_BARK, true, 6)
	Build.sphere(self, 1.5 * s, pos + Vector3(0, 3.1 * s, 0), Build.C_LEAF, 8)
