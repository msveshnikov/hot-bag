class_name Fx
extends Node3D
## Effects from the population JSON: steam, fountain, sparks, pigeons, rain puddles.

var world: Node
var puddles: Array[MeshInstance3D] = []
var pigeons: Array = []      # {node, home, state, t, vel}
var _splash_cd = 0.0


func setup(w: Node) -> void:
	world = w
	for f in Game.population.get("fx", []):
		var p = Vector3(f["pos"][0], f["pos"][1], f["pos"][2])
		match f["kind"]:
			"steam":
				add_child(_particles(p, Color(1, 1, 1, 0.35), 12, 2.4, Vector3(0, 0.6, 0), 0.25 * float(f["scale"]), 0.4))
			"fountain":
				add_child(_particles(p, Color(0.7, 0.9, 1.0, 0.7), 60, 1.1, Vector3(-1.2, 2.5, 0), 0.06, 0.25, Vector3(0, -9.8, 0)))
			"sparks":
				add_child(_particles(p, Color(1.0, 0.8, 0.3, 1.0), 20, 0.5, Vector3(0, 2.0, 0), 0.03, 1.2, Vector3(0, -9.8, 0), true))
			"pigeons":
				for k in int(f.get("count", 5)):
					_pigeon(p + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
			"puddle":
				_puddle(p, float(f["scale"]))


func _particles(p: Vector3, col: Color, amount: int, life: float, vel: Vector3, size: float, spread: float,
		grav = Vector3(0, 0.3, 0), emissive = false) -> GPUParticles3D:
	var g = GPUParticles3D.new()
	g.position = p
	g.amount = amount
	g.lifetime = life
	var pm = ParticleProcessMaterial.new()
	pm.direction = vel.normalized()
	pm.initial_velocity_min = vel.length() * 0.7
	pm.initial_velocity_max = vel.length() * 1.2
	pm.spread = spread * 60.0
	pm.gravity = grav
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var curve = Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1, 0.0))
	var ct = CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	g.process_material = pm
	var q = SphereMesh.new()
	q.radius = size
	q.height = size * 2
	q.radial_segments = 6
	q.rings = 3
	var m = StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if col.a < 0.99 else BaseMaterial3D.TRANSPARENCY_DISABLED
	if emissive:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 3.0
	q.material = m
	g.draw_pass_1 = q
	g.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 10, 8))
	return g


func _pigeon(p: Vector3) -> void:
	var n = Node3D.new()
	var body = MeshInstance3D.new()
	var s = SphereMesh.new()
	s.radius = 0.12
	s.height = 0.2
	body.mesh = s
	var m = StandardMaterial3D.new()
	m.albedo_color = Color("8a8f9c")
	body.material_override = m
	body.position.y = 0.12
	n.add_child(body)
	var head = MeshInstance3D.new()
	var hs = SphereMesh.new()
	hs.radius = 0.06
	hs.height = 0.12
	head.mesh = hs
	head.material_override = m
	head.position = Vector3(0, 0.24, 0.1)
	n.add_child(head)
	n.position = p
	n.rotation.y = randf() * TAU
	add_child(n)
	pigeons.append({"node": n, "home": p, "state": "peck", "t": randf() * 2.0, "vel": Vector3.ZERO})


func _puddle(p: Vector3, sc: float) -> void:
	var mi = MeshInstance3D.new()
	var c = CylinderMesh.new()
	c.top_radius = sc
	c.bottom_radius = sc
	c.height = 0.01
	c.radial_segments = 16
	mi.mesh = c
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.6, 0.75, 0.6)
	m.roughness = 0.05
	m.metallic = 0.3
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.position = p + Vector3(0, 0.015, 0)
	mi.scale = Vector3(1.0, 1.0, randf_range(0.5, 0.9))
	mi.rotation.y = randf() * TAU
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	puddles.append(mi)


func _process(delta: float) -> void:
	if world == null or not world.started:
		return
	var rain: float = world.daynight.rain
	var pp: Vector3 = world.player.global_position
	_splash_cd = max(0.0, _splash_cd - delta)
	for pd in puddles:
		pd.visible = rain > 0.3
		if pd.visible and _splash_cd <= 0.0 and world.player.riding() and abs(world.player.speed) > 3.0:
			if Vector2(pd.position.x - pp.x, pd.position.z - pp.z).length() < pd.scale.x * 1.2:
				_splash_cd = 1.0
				Sfx.play("splash", 0.7)
				if Game.upgrade_level("mudguards") == 0:
					world.player.wet = min(100.0, world.player.wet + 15.0)
					world.player.hint("mud", "Брызги из лужи! Крылья спасли бы куртку.", 20.0)
	for pg in pigeons:
		var n: Node3D = pg["node"]
		var d = n.position.distance_to(pp)
		match pg["state"]:
			"peck":
				pg["t"] -= delta
				n.get_child(1).position.y = 0.24 - (0.08 if fmod(pg["t"], 0.6) < 0.15 else 0.0)
				if pg["t"] <= 0.0:
					pg["t"] = randf_range(1.0, 3.0)
					n.rotation.y += randf_range(-1.5, 1.5)
				if d < 3.5:
					pg["state"] = "fly"
					var away = (n.position - pp)
					away.y = 0
					pg["vel"] = away.normalized() * 4.0 + Vector3(0, 3.5, 0)
					pg["t"] = 4.0
			"fly":
				n.position += pg["vel"] * delta
				n.rotation.y = atan2(pg["vel"].x, pg["vel"].z)
				pg["t"] -= delta
				if pg["t"] <= 0.0:
					pg["state"] = "return"
			"return":
				var to: Vector3 = pg["home"] - n.position
				if to.length() < 0.3 or d < 3.5:
					if to.length() < 0.3:
						n.position = pg["home"]
						pg["state"] = "peck"
				else:
					n.position += to.normalized() * min(4.0 * delta, to.length())
