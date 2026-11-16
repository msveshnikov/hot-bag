class_name Level
extends Node3D
## Builds the static level from old_town_layout.json: ground, buildings, props, plates, emissive registry,
## lamps, water, navigation grid. Everything comes from Blender data; nothing is placed by hand.

const EMIT_COLORS = {
	"EMIT_window": Color("ffd27a"), "EMIT_lamp": Color("ffd690"), "EMIT_neon_pink": Color("ff6f9d"),
	"EMIT_neon_teal": Color("38e0d0"), "EMIT_clock": Color("ffe9a8"), "EMIT_sign_pizza": Color("ffd34f"),
	"EMIT_sign_pizza_crust": Color("ffcf7a"), "EMIT_sign_burger": Color("ffb14f"), "EMIT_sign_sushi": Color("fff6e0"),
	"EMIT_sign_coffee": Color("fff7e6"), "EMIT_sign_cake": Color("ff8fb5"), "EMIT_headlight": Color("fff2c0"),
	"EMIT_taxi": Color("ffd94a"), "EMIT_police": Color("4a7dff"), "EMIT_pad": Color("38e0d0"),
}
const ALWAYS_ON = ["EMIT_screen", "EMIT_brake", "EMIT_warn", "EMIT_battery"]

var data: Dictionary
var emit_mats = {}            # name -> Array[StandardMaterial3D]
var lamps: Array[OmniLight3D] = []
var doors_int = {}            # "inst:idx" -> door mesh node (INT_door_*)
var traffic_lights: Array = [] # [{node, crossing, red, yellow, green}]
var grid: PackedByteArray
var gw = 0
var gh = 0
var gorigin = Vector3.ZERO
var cell = 2.0
var water_mat: ShaderMaterial
var scene_cache = {}
var instances: Array = []      # Node3D per layout instance
var plates: Array[Label3D] = []
var map_tex: Texture2D
var map_rect = Rect2()


func build(d: Dictionary) -> void:
	data = d
	_build_grid()
	var g: PackedScene = load(d["ground"])
	if g:
		var gn = g.instantiate()
		add_child(gn)
		_scan(gn)
	var holder = Node3D.new()
	holder.name = "Instances"
	add_child(holder)
	for i in d["instances"].size():
		var it: Dictionary = d["instances"][i]
		var ps: PackedScene = scene_cache.get(it["gltf"])
		if ps == null:
			ps = load(it["gltf"])
			scene_cache[it["gltf"]] = ps
		if ps == null:
			instances.append(null)
			continue
		var n: Node3D = ps.instantiate()
		n.position = Vector3(it["pos"][0], it["pos"][1], it["pos"][2])
		n.rotation.y = deg_to_rad(float(it["yaw"]))
		holder.add_child(n)
		instances.append(n)
		_scan(n, i)
		if it["group"] == "backdrop":
			_strip_backdrop(n)
		_optimize(n, it)
	_water()
	if d.has("map"):
		map_tex = load(d["map"]["image"])
		var r: Array = d["map"]["rect"]
		map_rect = Rect2(Vector2(r[0], r[1]), Vector2(r[2] - r[0], r[3] - r[1]))


func _scan(root: Node, inst = -1) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var mi = n as MeshInstance3D
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var m = mi.mesh.surface_get_material(s)
				if m is StandardMaterial3D:
					var nm = String(m.resource_name)
					if nm.begins_with("EMIT_") or nm.begins_with("TL_"):
						if not emit_mats.has(nm):
							emit_mats[nm] = []
						if not emit_mats[nm].has(m):
							emit_mats[nm].append(m)
							if nm in ALWAYS_ON:
								m.emission_enabled = true
								m.emission = m.albedo_color
								m.emission_energy_multiplier = 1.4
			if n.name.begins_with("INT_door_") and inst >= 0:
				var parts = String(n.name).split("_")
				doors_int["%d:%s" % [inst, parts[parts.size() - 1]]] = n
			if n.name.begins_with("TLAMP_") and inst >= 0:
				pass
		elif n is OmniLight3D:
			var l = n as OmniLight3D
			l.shadow_enabled = false
			l.omni_range = min(l.omni_range, 9.0) if l.omni_range > 0.0 else 9.0
			l.light_energy = clamp(l.light_energy, 0.3, 2.5)
			l.visible = false
			lamps.append(l)
	if inst >= 0 and data["instances"][inst]["asset"] == "traffic_light":
		var tl = {"node": root}
		for k in ["red", "yellow", "green"]:
			tl[k] = root.find_child("TLAMP_" + k, true, false)
			if tl[k]:
				var mi: MeshInstance3D = tl[k]
				var m = StandardMaterial3D.new()
				m.albedo_color = {"red": Color("7a2a25"), "yellow": Color("7a6425"), "green": Color("2a6a35")}[k]
				m.emission_enabled = true
				m.emission = {"red": Color("ff3b2f"), "yellow": Color("ffc72f"), "green": Color("3bff6a")}[k]
				m.emission_energy_multiplier = 0.0
				mi.material_override = m
		traffic_lights.append(tl)


const SMALL = ["bench", "trash_bin", "flower_pot", "crates", "mailbox", "bollard", "menu_board", "traffic_cone",
	"string_lights", "bike_rack", "cafe_set", "cafe_set_turq", "bush", "charger_station", "barrier_works"]


## Performance: occluders for buildings, visibility ranges and no shadows for small props.
func _optimize(n: Node3D, it: Dictionary) -> void:
	var g: String = it["group"]
	var asset: String = it["asset"]
	var meshes = n.find_children("*", "MeshInstance3D", true, false)
	if g == "prop" or asset in SMALL:
		# props collide with the player (layer 8) but do not push the camera into the courier's head
		for b in n.find_children("*", "StaticBody3D", true, false):
			(b as StaticBody3D).collision_layer = 8
	if asset in SMALL or g == "prop" and not asset.begins_with("tree") and asset != "fountain" and asset != "parapet":
		for m in meshes:
			var mi: MeshInstance3D = m
			mi.visibility_range_end = 55.0
			mi.visibility_range_end_margin = 5.0
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_far.append([mi, "prop"])
	elif asset.begins_with("tree") or asset in ["parapet", "lamp_post", "traffic_light"]:
		for m in meshes:
			(m as MeshInstance3D).visibility_range_end = 110.0
			if asset != "tree_round" and asset != "tree_round_b":
				(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif g in ["house", "backdrop", "restaurant", "shop", "landmark"]:
		for m in meshes:
			var mi: MeshInstance3D = m
			# small parts of a building (doors, intercoms, signs) fade out in the distance
			if String(mi.name).begins_with("INT_") or mi.get_aabb().size.length() < 3.0:
				mi.visibility_range_end = 60.0
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_far.append([mi, "prop"])
			elif g in ["house", "backdrop"]:
				_far.append([mi, "house"])
		var meta: Dictionary = Game.layout.get("meta", {})
		# box occluder slightly inside the building body
		var aabb = AABB()
		var first = true
		for m in meshes:
			var mi: MeshInstance3D = m
			if not String(mi.name).ends_with("_mesh") and not String(mi.name).ends_with("_body"):
				continue
			var a = mi.transform * mi.get_aabb()
			aabb = a if first else aabb.merge(a)
			first = false
		if not first and aabb.size.x > 3.0 and aabb.size.z > 3.0:
			var occ = OccluderInstance3D.new()
			var bo = BoxOccluder3D.new()
			bo.size = Vector3(aabb.size.x * 0.82, min(aabb.size.y, 14.0) * 0.85, aabb.size.z * 0.82)
			occ.occluder = bo
			occ.position = aabb.get_center() - Vector3(0, aabb.size.y * 0.5 - bo.size.y * 0.5, 0)
			n.add_child(occ)


var _far: Array = []      # [MeshInstance3D, kind]


func apply_quality(q: int) -> void:
	var house_r = [110.0, 170.0, 0.0][q]
	var prop_r = [38.0, 55.0, 80.0][q]
	for e in _far:
		var mi: MeshInstance3D = e[0]
		if not is_instance_valid(mi):
			continue
		mi.visibility_range_end = house_r if e[1] == "house" else prop_r


func _strip_backdrop(n: Node3D) -> void:
	for m in n.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# backdrop houses keep collision but lose interactive parts and lights
	for c in n.find_children("*", "", true, false):
		if c is OmniLight3D:
			lamps.erase(c)
			c.queue_free()


## Emission strength per mood (0 = off).
func set_emission(level: float, wet = false) -> void:
	for nm in emit_mats.keys():
		if nm in ALWAYS_ON or nm.begins_with("TL_"):
			continue
		var col: Color = EMIT_COLORS.get(nm, Color("ffe0a0"))
		for m in emit_mats[nm]:
			var mat: StandardMaterial3D = m
			mat.emission_enabled = level > 0.01
			mat.emission = col
			mat.emission_energy_multiplier = level * (0.55 if nm == "EMIT_window" else 1.3)
	for nm in ["asphalt", "cobble"]:
		pass


func set_lamps(on: bool, near: Vector3, radius = 70.0) -> void:
	var r2 = radius * radius
	for l in lamps:
		if not is_instance_valid(l):
			continue
		l.visible = on and l.global_position.distance_squared_to(near) < r2


func _water() -> void:
	var w: Dictionary = data.get("water", {})
	if w.is_empty():
		return
	var a: Array = w["rect"][0]
	var b: Array = w["rect"][1]
	var mesh = PlaneMesh.new()
	mesh.size = Vector2(abs(b[0] - a[0]) + 600.0, abs(b[2] - a[2]) + 200.0)
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3((a[0] + b[0]) * 0.5, float(w["y"]) + 0.6, min(a[2], b[2]) - 40.0)
	var sh = Shader.new()
	sh.code = """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec4 deep : source_color = vec4(0.16, 0.55, 0.72, 1.0);
uniform vec4 light : source_color = vec4(0.45, 0.82, 0.92, 1.0);
void vertex() {}
float h(vec2 p) { return sin(p.x * 0.35 + TIME * 1.1) * 0.5 + sin(p.y * 0.42 - TIME * 0.8) * 0.5 + sin((p.x + p.y) * 0.9 + TIME * 1.7) * 0.25; }
void fragment() {
	vec2 p = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
	float e = 0.4;
	vec3 n = normalize(vec3(h(p) - h(p + vec2(e, 0.0)), 2.2, h(p) - h(p + vec2(0.0, e))));
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	float s = smoothstep(0.55, 1.0, h(p * 1.7));
	ALBEDO = mix(deep.rgb, light.rgb, 0.35 + 0.35 * s);
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.7;
}
"""
	water_mat = ShaderMaterial.new()
	water_mat.shader = sh
	mi.material_override = water_mat
	add_child(mi)


# ---------------------------------------------------------------- navigation grid
func _build_grid() -> void:
	var g: Dictionary = data["grid"]
	gw = int(g["w"])
	gh = int(g["h"])
	cell = float(g["cell"])
	gorigin = Vector3(g["origin"][0], 0, g["origin"][2])
	grid = PackedByteArray()
	grid.resize(gw * gh)
	var rows: Array = g["rows"]
	for j in gh:
		var r: String = rows[j]
		for i in gw:
			grid[j * gw + i] = r.unicode_at(i)


## Godot world position -> grid cell (i, j). Grid row j grows toward -z (Blender +Y).
func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor((p.x - gorigin.x) / cell)), int(floor((gorigin.z - p.z) / cell)))


func cell_center(c: Vector2i) -> Vector3:
	return Vector3(gorigin.x + (c.x + 0.5) * cell, 0.0, gorigin.z - (c.y + 0.5) * cell)


func code_at_cell(c: Vector2i) -> String:
	if c.x < 0 or c.y < 0 or c.x >= gw or c.y >= gh:
		return "#"
	return char(grid[c.y * gw + c.x])


func surface_at(p: Vector3) -> String:
	return code_at_cell(cell_of(p))


func ground_height(p: Vector3) -> float:
	var h: Dictionary = data.get("heights", {})
	return float(h.get(surface_at(p), 0.0))


func add_plates(doors: Array) -> void:
	var seen = {}
	for d in doors:
		if d.get("plate") == null:
			continue
		var key = "%s_%d" % [d["street"], d["number"]]
		var p: Array = d["plate"]
		var l = Label3D.new()
		l.text = "%d" % int(d["number"]) + ("" if not seen.has(key) else "")
		l.text = d.get("plate_text", "%d\nпод. %d" % [int(d["number"]), int(d["entrance"])])
		if d.get("kind", "house") == "tower":
			l.font_size = 48
		l.font_size = 64
		l.pixel_size = 0.004
		l.outline_size = 14
		l.modulate = Color("fbf3e2")
		l.outline_modulate = Color("2f2a33")
		l.position = Vector3(p[0], p[1], p[2])
		l.rotation.y = deg_to_rad(float(d["yaw"]) + 180.0)
		l.double_sided = false
		l.visibility_range_end = 45.0
		add_child(l)
		plates.append(l)
		seen[key] = true


## Big painted house numbers on the corners of panel blocks and towers (run 2) — readable from far away.
func add_bignums(list: Array) -> void:
	for b in list:
		var l = Label3D.new()
		l.text = String(b["text"])
		l.font_size = 160
		l.pixel_size = 0.012 * float(b.get("size", 2.0)) / 2.0
		l.outline_size = 24
		l.modulate = Color("fbf3e2")
		l.outline_modulate = Color("2f6f8f")
		var p: Array = b["pos"]
		l.position = Vector3(p[0], p[1], p[2])
		l.rotation.y = deg_to_rad(float(b["yaw"]) + 180.0)
		l.double_sided = false
		l.visibility_range_end = 220.0
		add_child(l)
