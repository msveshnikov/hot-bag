class_name DayNight
extends Node3D
## Shift clock (08:00 -> 23:00, 1 game hour = 60 real seconds), sun/sky/fog from the Task 3 lighting presets,
## emission of windows/signs, street lamps, rain and heat.

signal hour_changed(h: int)
signal shift_over

const START_H = 8.0
const END_H = 23.0
const SEC_PER_HOUR = 60.0

var level: Level
var presets: Dictionary
var hour = START_H
var running = true
var rain = 0.0           # 0..1 current
var rain_target = 0.0
var heat = 0.0
var speed = 1.0
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var we: WorldEnvironment
var rain_fx: GPUParticles3D
var _last_h = -1
var _lamp_timer = 0.0
var follow: Node3D


func setup(lv: Level, lighting: Dictionary) -> void:
	level = lv
	presets = lighting
	we = WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky = Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 25.0
	sky_mat.sky_curve = 0.12
	sky_mat.sky_energy_multiplier = 1.1
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.08
	env.tonemap_white = 6.0
	if true:
		env.ssao_radius = 1.4
		env.ssao_intensity = 1.6
		env.ssao_detail = 0.6
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.06
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	apply_quality()
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.5
	add_child(sun)
	_make_rain()
	apply(true)


func apply_quality() -> void:
	var q = int(Game.settings.get("quality", 1))
	sun.shadow_enabled = q >= 1 and bool(Game.settings.get("shadows", true))
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if q < 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 22.0 if q < 2 else 60.0
	if env:
		env.ssao_enabled = q >= 2 and RenderingServer.get_current_rendering_method() != "gl_compatibility"
		env.glow_enabled = q >= 1
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if q == 0 else Viewport.MSAA_2X
	if level:
		level.apply_quality(q)


func _make_rain() -> void:
	rain_fx = GPUParticles3D.new()
	rain_fx.amount = 1600
	rain_fx.lifetime = 0.9
	rain_fx.visibility_aabb = AABB(Vector3(-25, -20, -25), Vector3(50, 40, 50))
	var pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 1, 22)
	pm.direction = Vector3(0.1, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 22.0
	pm.initial_velocity_max = 26.0
	pm.gravity = Vector3(0, -10, 0)
	rain_fx.process_material = pm
	var q = QuadMesh.new()
	q.size = Vector2(0.06, 1.1)
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.85, 0.9, 1.0, 0.6)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	q.material = m
	rain_fx.draw_pass_1 = q
	rain_fx.emitting = false
	add_child(rain_fx)


func _process(delta: float) -> void:
	if running:
		hour += delta * speed / SEC_PER_HOUR
		if hour >= END_H:
			hour = END_H
			running = false
			shift_over.emit()
	var h = int(hour)
	if h != _last_h:
		_last_h = h
		hour_changed.emit(h)
	rain = move_toward(rain, rain_target, delta * 0.15)
	heat = clamp(1.0 - abs(hour - 13.5) / 2.5, 0.0, 1.0) * (1.0 - rain)
	apply(false)
	if follow:
		rain_fx.global_position = follow.global_position + Vector3(0, 14, 0)
	rain_fx.emitting = rain > 0.15
	rain_fx.amount_ratio = clamp(rain, 0.0, 1.0)
	_lamp_timer -= delta
	if _lamp_timer <= 0.0 and follow:
		_lamp_timer = 0.5
		level.set_lamps(is_dark(), follow.global_position)
	Sfx.set_loop("rain_loop", rain * 0.6)


func is_dark() -> bool:
	return hour >= 19.5 or hour < 6.5 or rain > 0.6


func is_night() -> bool:
	return hour >= 21.0 or hour < 6.0


func clock_text() -> String:
	var h = int(hour)
	var m = int((hour - h) * 60.0)
	return "%02d:%02d" % [h, m]


func _key(name: String) -> Dictionary:
	return presets.get(name, {})


func _blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out = {}
	for k in a.keys():
		var va = a[k]
		var vb = b.get(k, va)
		if typeof(va) == TYPE_STRING and String(va).begins_with("#"):
			out[k] = Color(va).lerp(Color(vb), t)
		elif typeof(va) == TYPE_FLOAT or typeof(va) == TYPE_INT:
			out[k] = lerp(float(va), float(vb), t)
		else:
			out[k] = va if t < 0.5 else vb
	return out


func _current() -> Dictionary:
	var keys = [["morning", 8.0], ["noon", 13.0], ["evening", 19.0], ["night", 22.5]]
	var p: Dictionary
	if hour <= 8.0:
		p = _blend(_key("morning"), _key("morning"), 0.0)
	elif hour >= 22.5:
		p = _blend(_key("night"), _key("night"), 0.0)
	else:
		for i in keys.size() - 1:
			if hour >= keys[i][1] and hour <= keys[i + 1][1]:
				var t: float = (hour - keys[i][1]) / (keys[i + 1][1] - keys[i][1])
				t = t * t * (3.0 - 2.0 * t)
				p = _blend(_key(keys[i][0]), _key(keys[i + 1][0]), t)
				break
	if rain > 0.01:
		var r = _key("rain")
		var mix = _blend(p, r, rain * 0.85)
		mix["emission"] = max(float(p.get("emission", 0.0)), float(r.get("emission", 0.0)) * rain)
		p = mix
	return p


func apply(_force: bool) -> void:
	var p = _current()
	if p.is_empty():
		return
	var col = func(k): return p[k] if typeof(p[k]) == TYPE_COLOR else Color(p[k])
	sun.light_color = col.call("sun_color")
	sun.light_energy = float(p["sun_energy"]) * 1.15
	sun.rotation_degrees = Vector3(float(p["sun_pitch"]), float(p["sun_yaw"]), 0)
	sky_mat.sky_top_color = col.call("sky_top")
	sky_mat.sky_horizon_color = col.call("sky_horizon")
	sky_mat.ground_horizon_color = col.call("sky_horizon")
	sky_mat.ground_bottom_color = Color(col.call("sky_horizon")).darkened(0.4)
	env.ambient_light_color = col.call("ambient")
	env.ambient_light_energy = float(p["ambient_energy"]) * 1.25
	env.fog_light_color = col.call("fog_color")
	env.fog_density = float(p["fog_density"]) * 0.6
	level.set_emission(float(p.get("emission", 0.0)))
	if level.water_mat:
		level.water_mat.set_shader_parameter("deep", Color(col.call("sky_top")).lerp(Color("2a8cb0"), 0.6))
