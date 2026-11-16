class_name Vehicles
extends RefCounted
## Helpers for the Task 2 vehicle glTFs: WHEEL_* spin about X, STEER turns about Y, CRANK spins.

static var _scenes = {}


static func make(kind: String) -> Node3D:
	if not _scenes.has(kind):
		_scenes[kind] = load("res://assets/vehicles/%s.gltf" % kind)
	var ps: PackedScene = _scenes[kind]
	var n: Node3D = ps.instantiate()
	n.set_meta("wheel_r", float(Game.veh(kind)["r"]))
	# vehicle collision is handled by the rider / parked body, not by the glTF
	for c in n.find_children("*", "StaticBody3D", true, false):
		c.queue_free()
	for l in n.find_children("*", "OmniLight3D", true, false):
		(l as OmniLight3D).visible = false
		(l as OmniLight3D).shadow_enabled = false
	return n


static func apply_upgrades(n: Node3D, kind: String) -> void:
	if n == null:
		return
	if n.find_child("ACC_rack", true, false):
		_vis(n, "ACC_rack", Game.upgrade_level("rack") > 0)
		_vis(n, "ACC_wide_tires", Game.upgrade_level("tires") > 0)
		_vis(n, "ACC_headlight", Game.upgrade_level("headlight") > 0)


static func _vis(n: Node, name: String, v: bool) -> void:
	var c = n.find_child(name, true, false)
	if c:
		c.visible = v


static func spin(n: Node3D, speed: float, steer: float, delta: float, crank_rate: float) -> void:
	if n == null:
		return
	var r: float = n.get_meta("wheel_r", 0.3)
	for wn in n.find_children("WHEEL_*", "", true, false):
		if wn is Node3D and not String(wn.name).ends_with("_mesh"):
			(wn as Node3D).rotate_object_local(Vector3.RIGHT, speed / r * delta)
	var st: Node3D = n.find_child("STEER", true, false)
	if st:
		st.rotation.y = lerp(st.rotation.y, steer * 0.45, 0.2)
	var cr: Node3D = n.find_child("CRANK", true, false)
	if cr:
		cr.rotate_object_local(Vector3.RIGHT, crank_rate * TAU * delta)


static func battery_color(n: Node3D, battery: float) -> void:
	var b: MeshInstance3D = n.find_child("EMIT_battery*", true, false) as MeshInstance3D
	if b == null:
		for c in n.find_children("EMIT_battery*", "MeshInstance3D", true, false):
			b = c
			break
	if b == null:
		return
	var m = b.material_override as StandardMaterial3D
	if m == null:
		m = StandardMaterial3D.new()
		m.emission_enabled = true
		m.emission_energy_multiplier = 2.0
		b.material_override = m
	var col = Color("3bff6a") if battery > 40.0 else (Color("ffc72f") if battery > 15.0 else Color("ff3b2f"))
	if battery <= 15.0 and int(Time.get_ticks_msec() / 300) % 2 == 0:
		col = col.darkened(0.7)
	m.albedo_color = col
	m.emission = col


static func lights(n: Node3D, on: bool) -> void:
	if n == null:
		return
	for l in n.find_children("*", "OmniLight3D", true, false):
		(l as OmniLight3D).visible = on
