class_name Stairwell3D
extends SubViewportContainer
## The ride up to the customer in 3D, behind the stairs / lift screens: a cutaway switchback stairwell
## (or a lift cabin) built in code, with the player's own courier model climbing it.
## Screens drive it: `progress` (floors climbed) and `moving` for the stairs, `ride(dur)` for the lift,
## `arrive(cb)` for the knock at the customer's door.

const H = 3.0                 # floor height
const STEPS = 8               # steps per flight (half a floor)
const RUN = 0.28              # tread depth
const RISE = H * 0.5 / STEPS
const L = STEPS * RUN         # flight length along X
const W = 1.1                 # flight width
const GAP = 0.2               # stairwell eye between the flights
const D = 1.4                 # landing depth
const ZF = GAP * 0.5 + W * 0.5    # front flight (goes up to the right)
const ZB = -ZF                    # back flight (goes up to the left)
const ZW = GAP * 0.5 + W          # back wall / open front edge
const XW = L * 0.5 + D            # side walls
const CLIMB_SPEED = 1.632         # stride of the climb_stairs animation, m/s (anim_speeds.json)
const DOORS = ["6b3a2e", "4d5a3c", "7a5b3a", "3e4a5c", "8a3f35", "5c4636"]

var floors := 3
var night := false
var mode := "stairs"
var progress := 0.0           # stairs: floors climbed, 0 .. floors-1
var moving := false
var tired := false
var proc: Callable            # per-frame logic of the screen that owns this view

var sv: SubViewport
var root3: Node3D
var cam: Camera3D
var lamp: OmniLight3D
var courier: Node3D
var ap: AnimationPlayer
var cur_anim := ""
var cut_mats: Array = []
var pts: PackedVector3Array = []
var cum: PackedFloat32Array = []
var marks: Array = []
var door_hinge: Node3D
var _yaw := PI * 0.5
var _last := Vector3.ZERO
var _cut := 100.0
var _arrive_cb: Callable
var _arrive_t := -1.0
var _ride := {}
var _shake := 0.0

static var _cut_shader: Shader
static var _wall_shader: Shader
static var _section_shader: Shader


static func make(kind: String, n_floors: int, is_night: bool) -> Stairwell3D:
	var s = Stairwell3D.new()
	s.mode = kind
	s.floors = max(1, n_floors)
	s.night = is_night
	return s


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	sv = SubViewport.new()
	sv.own_world_3d = true
	# no MSAA on the Compatibility renderer: it leaks memory in the Mali driver (see DayNight.apply_quality)
	sv.msaa_3d = Viewport.MSAA_DISABLED if RenderingServer.get_current_rendering_method() == "gl_compatibility" else Viewport.MSAA_2X
	sv.scaling_3d_scale = get_viewport().scaling_3d_scale
	add_child(sv)
	root3 = Node3D.new()
	sv.add_child(root3)
	_environment()
	courier = Chars.courier()
	root3.add_child(courier)
	ap = courier.find_child("AnimationPlayer", true, false)
	Chars.blob(courier, 0.4)
	cam = Camera3D.new()
	cam.fov = 50.0
	cam.current = true
	sv.add_child(cam)
	if mode == "lift":
		_build_lift()
	else:
		_build_stairs()
		_build_path()
		_place(0.0, 1.0)
	# the city behind the screen does not need to render meanwhile
	get_viewport().disable_3d = true


func _exit_tree() -> void:
	var vp = get_viewport()
	if vp:
		vp.disable_3d = false


func _environment() -> void:
	var env = WorldEnvironment.new()
	var e = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("1d1a18")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("ffe4c4")
	e.ambient_light_energy = 0.5 if night else 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.1
	env.environment = e
	root3.add_child(env)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 24, 0)
	sun.light_energy = 0.35 if night else 0.7
	sun.light_color = Color("fff0dc")
	root3.add_child(sun)
	lamp = OmniLight3D.new()
	lamp.omni_range = 7.0
	lamp.light_energy = 1.7
	lamp.light_color = Color("ffd59a")
	root3.add_child(lamp)


# ---------------------------------------------------------------- materials
func _cut_mat(col: String, rough = 0.85, metal = 0.0) -> ShaderMaterial:
	if _cut_shader == null:
		_cut_shader = Shader.new()
		_cut_shader.code = """
shader_type spatial;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float rough = 0.85;
uniform float metal = 0.0;
uniform float cut_y = 1000.0;
void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// cutaway: everything in the front half above the courier's head is not drawn
	if (wp.y > cut_y && wp.z > -0.05) { discard; }
	ALBEDO = albedo.rgb;
	ROUGHNESS = rough;
	METALLIC = metal;
}
"""
	var m = ShaderMaterial.new()
	m.shader = _cut_shader
	m.set_shader_parameter("albedo", Color(col))
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("metal", metal)
	cut_mats.append(m)
	return m


func _wall_mat(paint: String) -> ShaderMaterial:
	if _wall_shader == null:
		_wall_shader = Shader.new()
		_wall_shader.code = """
shader_type spatial;
uniform vec4 paint : source_color = vec4(0.3, 0.55, 0.5, 1.0);
uniform vec4 white : source_color = vec4(0.9, 0.87, 0.8, 1.0);
uniform float flight = 2.24;
uniform float fh = 3.0;
void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// the painted dado follows the back flight, like in every old stairwell
	float t = clamp((flight * 0.5 - wp.x) / flight, 0.0, 1.0);
	float base = fh * 0.5 + t * fh * 0.5;
	float r = mod(wp.y - base, fh);
	vec3 c = mix(white.rgb, paint.rgb, step(r, 1.4));
	c = mix(c, paint.rgb * 0.55, step(abs(r - 1.4), 0.025));
	c = mix(c, paint.rgb * 0.45, step(r, 0.09));
	c *= 0.94 + 0.06 * sin(wp.x * 3.1 + wp.y * 1.7);
	ALBEDO = c;
	ROUGHNESS = 0.92;
}
"""
	var m = ShaderMaterial.new()
	m.shader = _wall_shader
	m.set_shader_parameter("paint", Color(paint))
	m.set_shader_parameter("flight", L)
	m.set_shader_parameter("fh", H)
	return m


## The cut through the building around the stairwell / lift: warm concrete with the floor slabs as dark bands.
func _section_mat(bands: bool) -> ShaderMaterial:
	if _section_shader == null:
		_section_shader = Shader.new()
		_section_shader.code = """
shader_type spatial;
render_mode unshaded;
uniform float fh = 3.0;
uniform float bands = 1.0;
void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float r = mod(wp.y + 0.22, fh);
	vec3 c = vec3(0.15, 0.13, 0.115);
	c = mix(c, vec3(0.085, 0.075, 0.065), step(r, 0.22) * bands);
	c *= 0.96 + 0.04 * sin(wp.x * 7.0) * sin(wp.y * 5.0);
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
"""
	var m = ShaderMaterial.new()
	m.shader = _section_shader
	m.set_shader_parameter("fh", H)
	m.set_shader_parameter("bands", 1.0 if bands else 0.0)
	return m


func _flat(col: String, emit = false) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(col)
	if emit:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null, rot_z = 0.0) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var b = BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation.z = rot_z
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else root3).add_child(mi)
	return mi


func _mm(size: Vector3, mat: Material, xs: Array) -> void:
	if xs.is_empty():
		return
	var b = BoxMesh.new()
	b.size = size
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = b
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mi = MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root3.add_child(mi)


func _label(text: String, pos: Vector3, size: int, col: Color, parent: Node3D = null, rot_y = 0.0) -> Label3D:
	var l = Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = col
	l.outline_size = 0
	l.position = pos
	l.rotation.y = rot_y
	l.shaded = true
	(parent if parent else root3).add_child(l)
	return l


# ---------------------------------------------------------------- the stairwell
func _build_stairs() -> void:
	var top = floors   # one more level above the customer, so the stairs go on
	var concrete = _cut_mat("b8b0a3")
	var slab = _cut_mat("a39b8f")
	var tread_edge = _cut_mat("57504a")
	var metal = _cut_mat("39434a", 0.5, 0.4)
	var wood = _cut_mat("7b4a2b", 0.55)
	var tile = _cut_mat("c4ae8c", 0.7)
	var paint = ["4f8a7e", "5f86a8", "7c9a5a"][floors % 3]
	var wall = _wall_mat(paint)
	var tall = (top + 1) * H + 1.0
	# walls: back, left, right (the front is cut away)
	_box(Vector3(2 * XW + 0.4, tall, 0.2), Vector3(0, tall * 0.5 - 0.3, -ZW - 0.1), wall)
	_box(Vector3(0.2, tall, 2 * ZW + 0.2), Vector3(-XW - 0.1, tall * 0.5 - 0.3, -0.1), wall)
	_box(Vector3(0.2, tall, 2 * ZW + 0.2), Vector3(XW + 0.1, tall * 0.5 - 0.3, -0.1), wall)
	# the cut through the rest of the building, so there is no void around the stairwell
	var sec = _section_mat(true)
	var deep = 2 * ZW + 0.2
	_box(Vector3(12.0, tall + 8.0, deep), Vector3(-XW - 0.2 - 6.0, tall * 0.5 - 4.0, -0.1), sec)
	_box(Vector3(12.0, tall + 8.0, deep), Vector3(XW + 0.2 + 6.0, tall * 0.5 - 4.0, -0.1), sec)
	_box(Vector3(2 * XW + 0.4, 6.0, deep), Vector3(0, -3.3, -0.1), sec)
	# ground floor
	_box(Vector3(2 * XW, 0.3, 2 * ZW), Vector3(0, -0.15, 0), tile)
	var a = atan2(H * 0.5, L)
	var slope_len = sqrt(L * L + H * H * 0.25)
	var steps = []
	var edges = []
	var posts = []
	var slabs = []
	var rails = []
	var landings = []
	for k in top:
		var y = k * H
		for i in STEPS:
			var hh = RISE + 0.16
			var t1 = y + (i + 1) * RISE
			steps.append(Transform3D(Basis(), Vector3(-L * 0.5 + (i + 0.5) * RUN, t1 - hh * 0.5, ZF)))
			edges.append(Transform3D(Basis(), Vector3(-L * 0.5 + i * RUN + 0.02, t1 - 0.012, ZF)))
			posts.append(Transform3D(Basis(), Vector3(-L * 0.5 + (i + 0.5) * RUN, t1 + 0.45, GAP * 0.5 + 0.04)))
			var t2 = y + H * 0.5 + (i + 1) * RISE
			steps.append(Transform3D(Basis(), Vector3(L * 0.5 - (i + 0.5) * RUN, t2 - hh * 0.5, ZB)))
			edges.append(Transform3D(Basis(), Vector3(L * 0.5 - i * RUN - 0.02, t2 - 0.012, ZB)))
			posts.append(Transform3D(Basis(), Vector3(L * 0.5 - (i + 0.5) * RUN, t2 + 0.45, -GAP * 0.5 - 0.04)))
		# the sloped slabs under the flights and the handrails over the well
		slabs.append(Transform3D(Basis(Vector3.BACK, a), Vector3(0, y + H * 0.25 - 0.13, ZF)))
		slabs.append(Transform3D(Basis(Vector3.BACK, -a), Vector3(0, y + H * 0.75 - 0.13, ZB)))
		rails.append(Transform3D(Basis(Vector3.BACK, a), Vector3(0, y + H * 0.25 + RISE * 0.5 + 0.92, GAP * 0.5 + 0.04)))
		rails.append(Transform3D(Basis(Vector3.BACK, -a), Vector3(0, y + H * 0.75 + RISE * 0.5 + 0.92, -GAP * 0.5 - 0.04)))
		# mid landing with a window
		landings.append(Transform3D(Basis(), Vector3(L * 0.5 + D * 0.5, y + H * 0.5 - 0.11, 0)))
		_box(Vector3(0.07, 0.06, GAP + 0.14), Vector3(L * 0.5 + 0.02, y + H * 0.5 + 0.92 + RISE * 0.5, 0), wood)
		_window(Vector3(L * 0.5 + D * 0.5, y + H * 0.5 + 1.35, -ZW + 0.005))
	_mm(Vector3(RUN, RISE + 0.16, W), concrete, steps)
	_mm(Vector3(0.05, 0.03, W), tread_edge, edges)
	_mm(Vector3(0.025, 0.9, 0.025), metal, posts)
	_mm(Vector3(slope_len, 0.16, W), slab, slabs)
	_mm(Vector3(slope_len, 0.055, 0.07), wood, rails)
	for k in range(1, top + 1):
		landings.append(Transform3D(Basis(), Vector3(-L * 0.5 - D * 0.5, k * H - 0.11, 0)))
	_mm(Vector3(D, 0.22, 2 * ZW), tile, landings)
	# floor landings: doors, numbers, a bulb
	var bulb = _flat("fff2c8", true)
	for k in range(0, top + 1):
		var y = k * H
		var fl = k + 1
		_label("%d" % fl, Vector3(-L * 0.5 - D * 0.5, y + 2.45, -ZW + 0.01), 115, Color(paint).darkened(0.45))
		var bm = MeshInstance3D.new()
		var sp = SphereMesh.new()
		sp.radius = 0.07
		sp.height = 0.14
		bm.mesh = sp
		bm.material_override = bulb
		bm.position = Vector3(-L * 0.5 - D * 0.5, y + 2.72, -0.55)
		root3.add_child(bm)
		if k == 0:
			_ground_floor(metal)
			continue
		var target = fl == floors
		var hinge = _door(Vector3(-L * 0.5 - D * 0.5, y, -ZW), 0.0, Color(DOORS[(k * 2) % DOORS.size()]), "%d" % (k * 4 + 1 + (k % 3)))
		_door(Vector3(-XW, y, ZF - 0.1), PI * 0.5, Color(DOORS[(k * 2 + 1) % DOORS.size()]), "")
		_box(Vector3(0.8, 0.02, 0.5), Vector3(-L * 0.5 - D * 0.5, y + 0.01, -ZW + 0.3), _flat("4a3b33" if not target else "8a3a30"))
		if target:
			door_hinge = hinge


func _door(at: Vector3, rot: float, col: Color, number: String) -> Node3D:
	# `at` is the middle of the door's bottom edge on the wall; doors open into the stairwell
	var base = Node3D.new()
	base.position = at
	base.rotation.y = rot
	root3.add_child(base)
	_box(Vector3(1.06, 2.18, 0.04), Vector3(0, 1.09, 0.02), _cut_mat("e6dfd2"), base)
	var hinge = Node3D.new()
	hinge.position = Vector3(-0.45, 0, 0.06)
	base.add_child(hinge)
	var leaf = _cut_mat(col.to_html(false), 0.6)
	_box(Vector3(0.9, 2.05, 0.05), Vector3(0.45, 1.025, 0), leaf, hinge)
	_box(Vector3(0.72, 0.5, 0.02), Vector3(0.45, 1.55, 0.03), _cut_mat(col.darkened(0.2).to_html(false), 0.6), hinge)
	_box(Vector3(0.05, 0.05, 0.08), Vector3(0.8, 1.0, 0.05), _cut_mat("c9a64a", 0.3, 0.8), hinge)
	if number != "":
		_box(Vector3(0.2, 0.12, 0.01), Vector3(0.45, 1.88, 0.03), _cut_mat("f2ead8"), hinge)
		_label(number, Vector3(0.45, 1.88, 0.04), 48, Color("2f2a33"), hinge)
	return hinge


func _window(at: Vector3) -> void:
	_box(Vector3(1.04, 1.24, 0.03), at, _flat("e6dfd2"))
	var sky = _flat("22355c" if night else "bfe0ef", true)
	_box(Vector3(0.9, 1.1, 0.02), at + Vector3(0, 0, 0.015), sky)
	_box(Vector3(0.04, 1.1, 0.03), at + Vector3(0, 0, 0.03), _flat("e6dfd2"))
	_box(Vector3(0.9, 0.04, 0.03), at + Vector3(0, 0.15, 0.03), _flat("e6dfd2"))
	_box(Vector3(1.1, 0.05, 0.16), at + Vector3(0, -0.62, 0.07), _flat("d9d2c4"))
	if night:
		for i in 3:
			var star = _flat("ffe9a8", true)
			_box(Vector3(0.05, 0.05, 0.01), at + Vector3(-0.3 + i * 0.27, 0.32 - (i % 2) * 0.2, 0.03), star)


func _ground_floor(metal: Material) -> void:
	# mailboxes on the back wall, the street door on the left
	var mb = Node3D.new()
	mb.position = Vector3(-L * 0.5 - D * 0.5, 0, -ZW)
	root3.add_child(mb)
	_box(Vector3(1.1, 0.7, 0.14), Vector3(0, 1.45, 0.07), _cut_mat("6f8796", 0.5, 0.3), mb)
	for r in 3:
		for c in 4:
			_box(Vector3(0.2, 0.15, 0.02), Vector3(-0.39 + c * 0.26, 1.67 - r * 0.21, 0.15), _cut_mat("8aa1ae", 0.4, 0.3), mb)
	_door(Vector3(-XW, 0, ZF - 0.1), PI * 0.5, Color("55606a"), "")


func _build_path() -> void:
	pts = PackedVector3Array()
	marks = []
	for k in floors:
		var y = k * H
		marks.append(pts.size())
		if k == floors - 1 and k > 0:
			pts.append(Vector3(-L * 0.5 - D * 0.42, y, -ZW + 0.62))   # in front of the customer's door
			break
		pts.append(Vector3(-L * 0.5 - D * 0.4, y, ZF))
		if k == floors - 1:
			break
		pts.append(Vector3(-L * 0.5 - RUN * 0.5, y, ZF))
		pts.append(Vector3(L * 0.5 - RUN * 0.5, y + H * 0.5, ZF))
		pts.append(Vector3(L * 0.5 + D * 0.42, y + H * 0.5, ZF * 0.55))
		pts.append(Vector3(L * 0.5 + D * 0.42, y + H * 0.5, ZB * 0.55))
		pts.append(Vector3(L * 0.5 + RUN * 0.5, y + H * 0.5, ZB))
		pts.append(Vector3(-L * 0.5 + RUN * 0.5, y + H, ZB))
		pts.append(Vector3(-L * 0.5 - D * 0.4, y + H, ZB * 0.55))
	cum = PackedFloat32Array()
	cum.append(0.0)
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))


func _sample(d: float) -> Array:
	for i in range(1, pts.size()):
		if d <= cum[i] or i == pts.size() - 1:
			var seg = max(0.0001, cum[i] - cum[i - 1])
			var f = clamp((d - cum[i - 1]) / seg, 0.0, 1.0)
			return [pts[i - 1].lerp(pts[i], f), pts[i] - pts[i - 1]]
	return [pts[0], Vector3.RIGHT]


func _place(p: float, delta: float) -> void:
	var pos: Vector3
	var dir := Vector3.ZERO
	if pts.size() < 2:
		pos = pts[0]
	else:
		var k = clamp(int(floor(p)), 0, marks.size() - 1)
		var d: float
		if k >= marks.size() - 1:
			d = cum[cum.size() - 1]
		else:
			d = lerp(cum[marks[k]], cum[marks[k + 1]], p - k)
		var s = _sample(d)
		pos = s[0]
		dir = s[1]
	var hv = Vector2(dir.x, dir.z)
	if hv.length() > 0.01 and _arrive_t < 0.0:
		_yaw = lerp_angle(_yaw, atan2(hv.x, hv.y), clamp(delta * 9.0, 0.0, 1.0))
	courier.position = pos
	courier.rotation.y = _yaw
	var speed = Vector2(pos.x - _last.x, pos.z - _last.z).length() / max(delta, 0.001)
	_last = pos
	if _arrive_t < 0.0:
		if moving and speed > 0.05:
			var an = "tired_walk" if tired else "climb_stairs"
			_anim(an, clamp(speed / (0.6 if tired else CLIMB_SPEED), 0.6, 2.6))
		else:
			_anim("idle", 1.0)
	# camera: in front of the cutaway, a little above the courier, smoothly following
	var tgt = pos + Vector3(0, 1.0, 0)
	var want = Vector3(clamp(pos.x * 0.55, -1.0, 1.0), tgt.y + 1.25, 5.6)
	var kk = clamp(delta * 4.0, 0.0, 1.0)
	cam.position = want if delta >= 1.0 else cam.position.lerp(want, kk)
	cam.look_at(tgt)
	lamp.position = pos + Vector3(0.3, 2.5, 0.6)
	_cut = pos.y + 2.3 if delta >= 1.0 else lerp(_cut, pos.y + 2.3, kk)
	for m in cut_mats:
		m.set_shader_parameter("cut_y", _cut)


func _anim(name: String, speed: float) -> void:
	if ap == null:
		return
	if cur_anim != name and ap.has_animation(name):
		cur_anim = name
		ap.play(name, 0.2)
	ap.speed_scale = speed


## The courier knocks at the customer's door, the door opens, then cb runs.
func arrive(cb: Callable) -> void:
	if _arrive_t >= 0.0:
		return
	_arrive_cb = cb
	_arrive_t = 0.0
	_anim("knock_door", 1.0)
	Sfx.play("knock", 0.8)


## Lift: the doors close, the cabin goes up for dur seconds, the doors open, then cb runs.
func ride(dur: float, cb: Callable) -> void:
	_ride = {"t": 0.0, "dur": dur, "cb": cb, "bell": false, "done": false}


func _process(delta: float) -> void:
	if proc.is_valid():
		proc.call(delta)
	if mode == "lift":
		_lift_process(delta)
		return
	if _arrive_t >= 0.0:
		_arrive_t += delta
		_yaw = lerp_angle(_yaw, PI, clamp(delta * 8.0, 0.0, 1.0))
		if door_hinge and _arrive_t > 0.9:
			door_hinge.rotation.y = lerp(door_hinge.rotation.y, -1.35, clamp(delta * 5.0, 0.0, 1.0))
		if _arrive_t > 1.7 and _arrive_cb.is_valid():
			var cb = _arrive_cb
			_arrive_cb = Callable()
			cb.call()
	_place(progress, delta)


# ---------------------------------------------------------------- the lift
var _lift_doors: Array = []
var _lift_display: Label3D
var _lift_cabin: Node3D

func _build_lift() -> void:
	_lift_cabin = Node3D.new()
	root3.add_child(_lift_cabin)
	var steel = _flat("b9c0c4")
	steel.metallic = 0.5
	steel.roughness = 0.35
	var panel = _flat("8c6a4c")
	panel.roughness = 0.5
	var c = _lift_cabin
	_box(Vector3(1.8, 0.1, 1.8), Vector3(0, -0.05, 0), _flat("4a4a4a"), c)
	_box(Vector3(1.8, 0.1, 1.8), Vector3(0, 2.4, 0), _flat("d8d8d0"), c)
	_box(Vector3(1.8, 2.4, 0.08), Vector3(0, 1.2, -0.94), panel, c)
	_box(Vector3(0.08, 2.4, 1.8), Vector3(-0.94, 1.2, 0), panel, c)
	_box(Vector3(1.6, 0.04, 0.05), Vector3(0, 0.95, -0.88), steel, c)
	# the door wall on the right: two sliding panels, a display above, buttons beside
	_box(Vector3(0.08, 2.4, 0.42), Vector3(0.94, 1.2, -0.69), steel, c)
	_box(Vector3(0.08, 2.4, 0.42), Vector3(0.94, 1.2, 0.69), steel, c)
	_box(Vector3(0.08, 0.3, 1.0), Vector3(0.94, 2.25, 0), steel, c)
	for i in 2:
		var d = _box(Vector3(0.04, 2.1, 0.5), Vector3(0.9, 1.05, -0.25 + i * 0.5), steel, c)
		d.set_meta("closed_z", -0.25 + i * 0.5)
		d.set_meta("open_z", -0.7 + i * 1.4)
		d.position.z = d.get_meta("open_z")
		_lift_doors.append(d)
	_box(Vector3(0.03, 0.18, 0.34), Vector3(0.89, 2.25, 0), _flat("1b1b1b"), c)
	_lift_display = _label("1", Vector3(0.87, 2.25, 0), 70, Color("ff5a3c"), c, -PI * 0.5)
	_lift_display.shaded = false
	_box(Vector3(0.03, 0.5, 0.16), Vector3(0.89, 1.25, -0.66), _flat("2c2c2c"), c)
	for r in 5:
		for q in 2:
			var lit = r == 0 and q == 0
			_box(Vector3(0.02, 0.05, 0.05), Vector3(0.875, 1.43 - r * 0.09, -0.69 + q * 0.07), _flat("ffb35a" if lit else "9a9a9a", lit), c)
	_box(Vector3(0.9, 0.03, 0.4), Vector3(0, 2.34, 0), _flat("fff5d8", true), c)
	_box(Vector3(0.72, 0.16, 0.01), Vector3(-0.45, 2.0, -0.895), _flat("e9e4d8"), c)
	_label("400 кг · 5 чел.", Vector3(-0.45, 2.0, -0.885), 26, Color("2f2a33"), c)
	# the shaft around the cabin, cut open like a doll's house
	var sec = _section_mat(false)
	_box(Vector3(6.0, 12.0, 0.6), Vector3(-0.98 - 3.0, 1.2, 0.68), sec, c)
	_box(Vector3(6.0, 12.0, 0.6), Vector3(0.98 + 3.0, 1.2, 0.68), sec, c)
	_box(Vector3(1.96, 4.0, 0.6), Vector3(0, 2.45 + 2.0, 0.68), sec, c)
	_box(Vector3(1.96, 4.0, 0.6), Vector3(0, -0.1 - 2.0, 0.68), sec, c)
	_box(Vector3(0.05, 3.0, 1.8), Vector3(1.6, 1.3, -0.1), _flat("2a2724"), c)
	courier.position = Vector3(-0.15, 0, 0.15)
	_yaw = PI * 0.5
	courier.rotation.y = _yaw
	_anim("phone_check", 1.0)
	cam.fov = 52.0
	cam.position = Vector3(-0.35, 1.55, 3.3)
	cam.look_at(Vector3(0.15, 1.15, 0))
	lamp.position = Vector3(0, 2.1, 0.3)
	lamp.omni_range = 4.0


func _lift_process(delta: float) -> void:
	if _ride.is_empty():
		return
	var t = _ride["t"] + delta
	_ride["t"] = t
	var dur: float = _ride["dur"]
	var close_k = clamp(t / 0.6, 0.0, 1.0) if t < 0.6 + dur else clamp(1.0 - (t - 0.6 - dur) / 0.6, 0.0, 1.0)
	for d in _lift_doors:
		d.position.z = lerp(float(d.get_meta("open_z")), float(d.get_meta("closed_z")), close_k)
	var k = clamp((t - 0.6) / dur, 0.0, 1.0)
	_lift_display.text = "%d" % max(1, int(round(1 + k * (floors - 1))))
	# a bit of cabin shake while moving
	var moving_now = t > 0.6 and t < 0.6 + dur
	_shake = lerp(_shake, 1.0 if moving_now else 0.0, clamp(delta * 6.0, 0.0, 1.0))
	cam.h_offset = sin(t * 37.0) * 0.004 * _shake
	cam.v_offset = sin(t * 23.0) * 0.006 * _shake
	if t >= 0.6 + dur and not _ride["bell"]:
		_ride["bell"] = true
		Sfx.play("bell", 0.6)
		_anim("idle", 1.0)
	if t > 1.2 + dur:
		_anim("walk", 1.0)
		courier.position.x = min(courier.position.x + delta * 0.99, 1.2)
	if t > 2.0 + dur and not _ride["done"]:
		_ride["done"] = true
		var cb: Callable = _ride["cb"]
		cb.call()
