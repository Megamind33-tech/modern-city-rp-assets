class_name Lighting
extends Node
## Art-directed lighting moods for the Living Diorama look (see ART_BIBLE.md):
## warm low key light, cool sky fill, AgX tonemapping, gentle colour grade and aerial
## fog. Weather blends between moods instead of switching instantly.
## Everything here is supported by the Mobile renderer; glow is skipped on Low quality.

const MOODS := {
	"clear": {
		"sun_rot": Vector3(-34, -48, 0), "sun_col": Color(1.0, 0.86, 0.68), "sun_e": 1.55,
		"fill_col": Color(0.55, 0.68, 1.0), "fill_e": 0.35,
		"sky_top": Color(0.30, 0.52, 0.82), "sky_hor": Color(0.98, 0.84, 0.66),
		"gnd_hor": Color(0.74, 0.66, 0.55), "ambient_e": 0.55,
		"fog_col": Color(0.96, 0.84, 0.70), "fog_d": 0.0045,
		"contrast": 1.08, "saturation": 1.14, "exposure": 1.0,
	},
	"rain": {
		"sun_rot": Vector3(-55, -30, 0), "sun_col": Color(0.86, 0.90, 1.0), "sun_e": 0.85,
		"fill_col": Color(0.60, 0.70, 0.90), "fill_e": 0.45,
		"sky_top": Color(0.42, 0.50, 0.60), "sky_hor": Color(0.72, 0.76, 0.80),
		"gnd_hor": Color(0.52, 0.55, 0.56), "ambient_e": 0.75,
		"fog_col": Color(0.70, 0.75, 0.82), "fog_d": 0.011,
		"contrast": 1.04, "saturation": 0.98, "exposure": 1.05,
	},
	"storm": {
		"sun_rot": Vector3(-60, -20, 0), "sun_col": Color(0.78, 0.84, 1.0), "sun_e": 0.6,
		"fill_col": Color(0.55, 0.62, 0.85), "fill_e": 0.5,
		"sky_top": Color(0.30, 0.36, 0.46), "sky_hor": Color(0.56, 0.60, 0.66),
		"gnd_hor": Color(0.40, 0.43, 0.45), "ambient_e": 0.8,
		"fog_col": Color(0.55, 0.60, 0.68), "fog_d": 0.016,
		"contrast": 1.1, "saturation": 0.9, "exposure": 1.1,
	},
}

var env: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var _from: Dictionary = MOODS["clear"]
var _to: Dictionary = MOODS["clear"]
var _t := 1.0


func _ready() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 20.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.fog_enabled = true
	env.fog_sky_affect = 0.35
	env.adjustment_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.shadow_bias = 0.04
	sun.directional_shadow_max_distance = 55.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)
	# Cool, shadowless fill from the opposite side keeps shadow sides readable (diorama look).
	fill = DirectionalLight3D.new()
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-25, 135, 0)
	fill.light_specular = 0.0
	add_child(fill)
	_apply(MOODS["clear"])


func set_mood(weather: String, instant: bool = false) -> void:
	var key := "clear"
	if weather == "heavy_rain":
		key = "storm"
	elif weather in ["gusty_rain", "rain"]:
		key = "rain"
	_from = _current()
	_to = MOODS[key]
	_t = 1.0 if instant else 0.0
	if instant:
		_apply(_to)


func set_quality(shadows: bool, glow: bool) -> void:
	sun.shadow_enabled = shadows
	env.glow_enabled = glow


func _current() -> Dictionary:
	return _blend(_from, _to, _t)


func _process(dt: float) -> void:
	if _t < 1.0:
		_t = minf(1.0, _t + dt / 2.5)
		_apply(_current())


static func _blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k in a:
		var va: Variant = a[k]
		var vb: Variant = b[k]
		if va is Color:
			out[k] = (va as Color).lerp(vb, t)
		elif va is Vector3:
			out[k] = (va as Vector3).lerp(vb, t)
		else:
			out[k] = lerpf(va, vb, t)
	return out


func _apply(m: Dictionary) -> void:
	sun.rotation_degrees = m["sun_rot"]
	sun.light_color = m["sun_col"]
	sun.light_energy = m["sun_e"]
	fill.light_color = m["fill_col"]
	fill.light_energy = m["fill_e"]
	sky_mat.sky_top_color = m["sky_top"]
	sky_mat.sky_horizon_color = m["sky_hor"]
	sky_mat.ground_horizon_color = m["gnd_hor"]
	sky_mat.ground_bottom_color = (m["gnd_hor"] as Color).darkened(0.4)
	env.ambient_light_energy = m["ambient_e"]
	env.fog_light_color = m["fog_col"]
	env.fog_density = m["fog_d"]
	env.adjustment_contrast = m["contrast"]
	env.adjustment_saturation = m["saturation"]
	env.tonemap_exposure = m["exposure"]
