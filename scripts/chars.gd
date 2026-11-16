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
	if ap and ap.has_animation(anim):
		ap.play(anim)
		ap.seek(randf() * 1.5, true)
	return n


static func play(n: Node, anim: String, blend = 0.2) -> void:
	var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, false)
	if ap and ap.has_animation(anim) and ap.current_animation != anim:
		ap.play(anim, blend)


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
