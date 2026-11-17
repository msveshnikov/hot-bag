class_name Chars
extends RefCounted
## Helpers for the Task 2 character glTFs (shared skeleton, 40 animations).

const LOOPING = ["idle", "walk", "run", "tired_walk", "climb_stairs", "sneak", "ride_bike", "ride_bike_idle",
	"ride_scooter", "carry", "carry_idle", "knock_door", "phone_check", "phone_call", "lying", "celebrate", "happy",
	"angry", "eat_snack", "sit", "sip_coffee", "talk", "laugh", "wait_impatient", "whistle", "write_ticket",
	"cook_idle", "photo"]

static var _scenes = {}


static func scene(model: String) -> PackedScene:
	if not _scenes.has(model):
		_scenes[model] = load("res://assets/characters/%s.gltf" % model)
	return _scenes[model]


static func setup_anims(ap: AnimationPlayer) -> void:
	if ap == null:
		return
	for lib_name in ap.get_animation_library_list():
		var lib = ap.get_animation_library(lib_name)
		for an in lib.get_animation_list():
			var a = lib.get_animation(an)
			a.loop_mode = Animation.LOOP_LINEAR if String(an) in LOOPING else Animation.LOOP_NONE


## Instance a character, hide accessories except the given ones, start an animation.
static func make(model: String, anim = "idle", keep_acc: Array = []) -> Node3D:
	var ps = scene(model)
	if ps == null:
		return Node3D.new()
	var n: Node3D = ps.instantiate()
	for c in n.find_children("ACC_*", "", true, false):
		c.visible = String(c.name) in keep_acc
	for c in n.find_children("HELD_*", "", true, false):
		c.visible = false
	var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, false)
	setup_anims(ap)
	blob(n, 0.42)
	if ap and ap.has_animation(anim):
		ap.play(anim)
		ap.seek(randf() * 1.5, true)
	return n


## The player's courier as dressed in the garage (gender, hair, cap or helmet, jacket, bag), standing idle.
static func courier() -> Node3D:
	var look: Dictionary = Game.state["look"]
	var ps: PackedScene = load("res://assets/characters/courier_%s.gltf" % ("f" if look["gender"] == "f" else "m"))
	var m: Node3D = ps.instantiate()
	var helmet: String = Game.state.get("helmet", "")
	for a in m.find_children("ACC_*", "", true, false):
		var nm = String(a.name)
		var vis = false
		if nm.begins_with("ACC_hair_"):
			vis = nm == "ACC_hair_" + String(look["hair"]) and (helmet == "" or nm == "ACC_hair_ponytail")
			if helmet == "" and look.get("cap", true) and nm in ["ACC_hair_curly", "ACC_hair_bun"]:
				vis = false
		elif nm == "ACC_cap":
			vis = helmet == "" and bool(look.get("cap", true))
		elif nm.begins_with("ACC_helmet_"):
			vis = ("helmet_" + nm.substr(11)) == helmet
		elif nm == "ACC_bag":
			vis = true
		a.visible = vis
	for h in m.find_children("HELD_*", "", true, false):
		h.visible = false
	set_jacket(m, Color(look["jacket"]))
	set_bag(m, Color(look.get("bag", Game.BAGS[0])))
	var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
	if ap:
		setup_anims(ap)
		if ap.has_animation("idle"):
			ap.play("idle")
	return m


static var _blob_mat: StandardMaterial3D


## Cheap round contact shadow (used when real shadows are off, looks fine with them too).
static func blob(parent: Node3D, radius = 0.45) -> MeshInstance3D:
	if _blob_mat == null:
		var g = Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.45))
		g.set_color(1, Color(0, 0, 0, 0.0))
		var gt = GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		_blob_mat = StandardMaterial3D.new()
		_blob_mat.albedo_texture = gt
		_blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blob_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var q = QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	var mi = MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _blob_mat
	mi.position.y = 0.04
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func play(n: Node, anim: String, blend = 0.2) -> void:
	var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, false)
	if ap and ap.has_animation(anim) and ap.current_animation != anim:
		ap.play(anim, blend)


static func set_bag(n: Node, col: Color) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var mat = m.mesh.surface_get_material(s)
			if mat and String(mat.resource_name) == "bag_turq":
				var d: StandardMaterial3D = mat.duplicate()
				d.albedo_color = col
				if col == Color(Game.BAG_GOLD):
					d.metallic = 0.7
					d.roughness = 0.3
				m.set_surface_override_material(s, d)


static func set_jacket(n: Node, col: Color) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var mat = m.mesh.surface_get_material(s)
			if mat and String(mat.resource_name) in ["jacket", "cloth_5fa9a3"]:
				var d: StandardMaterial3D = mat.duplicate()
				d.albedo_color = col
				m.set_surface_override_material(s, d)
