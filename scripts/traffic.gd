class_name Traffic
extends Node3D
## Cars on the loop roads, the tram on the avenue, traffic lights at the four crossings.

const GAP = 7.5

var world: Node
var paths: Array = []        # {pts: PackedVector3Array, cum: PackedFloat32Array, len, loop}
var cars: Array = []         # {node, body, path, s, v, vmax}
var crossings: Array = []    # {id, rect: Rect2, cycle, offset}
var tram = {}
var t = 0.0
var _count_t = 0.0
var models: Array = []
var paints: Array = []


func setup(w: Node) -> void:
	world = w
	var tr: Dictionary = Game.layout["traffic"]
	for p in tr["paths"]:
		var pts = PackedVector3Array()
		for q in p["points"]:
			pts.append(Vector3(q[0], 0, q[2]))
		if p["loop"]:
			pts.append(pts[0])
		var cum = PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
		paths.append({"pts": pts, "cum": cum, "len": cum[cum.size() - 1], "loop": p["loop"]})
	for c in tr["crossings"]:
		var a: Array = c["rect"][0]
		var b: Array = c["rect"][1]
		var r = Rect2(Vector2(min(a[0], b[0]), min(a[2], b[2])), Vector2(abs(b[0] - a[0]), abs(b[2] - a[2])))
		crossings.append({"id": c["id"], "rect": r, "cycle": c["cycle"], "offset": float(c["offset"])})
	var td: Dictionary = Game.population["traffic"]
	models = td["models"]
	paints = td["paints"]
	_make_tram(td)
	# initial cars
	var n = _wanted_cars()
	for i in n:
		_spawn_car(i % paths.size(), (float(i) / n) * paths[i % paths.size()]["len"])


func _wanted_cars() -> int:
	var h: float = world.daynight.hour if world.daynight else 8.0
	var td: Dictionary = Game.population["traffic"]
	var n = 3
	for e in td["count_by_hour"]:
		if h >= float(e[0]):
			n = int(e[1])
	return n


func _spawn_car(pi: int, s: float) -> void:
	var model: String = models[randi() % models.size()]
	var node = Vehicles.make(model)
	var paint = Color(paints[randi() % paints.size()])
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		for k in m.mesh.get_surface_count():
			var mat = m.mesh.surface_get_material(k)
			if mat and String(mat.resource_name) == "car_paint":
				var d: StandardMaterial3D = mat.duplicate()
				d.albedo_color = paint
				m.set_surface_override_material(k, d)
	var body = AnimatableBody3D.new()
	body.sync_to_physics = false
	body.collision_layer = 4
	body.collision_mask = 0
	var cs = CollisionShape3D.new()
	var bx = BoxShape3D.new()
	var big = model == "bus"
	bx.size = Vector3(2.5 if big else 1.8, 1.6, 10.0 if big else 4.2)
	cs.shape = bx
	cs.position.y = 0.9
	body.add_child(cs)
	body.add_child(node)
	var sh = Chars.blob(body, 1.3)
	sh.scale = Vector3(1.0, 1.0, 2.6 if big else 1.9)
	add_child(body)
	cars.append({"node": node, "body": body, "path": pi, "s": s, "v": 0.0, "vmax": 7.0 + randf() * 2.5 - (2.0 if big else 0.0), "horn": 0.0})


func _make_tram(td: Dictionary) -> void:
	var tr: Dictionary = Game.layout["traffic"]["tram"]
	var a: Array = tr["points"][0]
	var b: Array = tr["points"][1]
	var body = AnimatableBody3D.new()
	body.sync_to_physics = false
	body.collision_layer = 4
	var cs = CollisionShape3D.new()
	var bx = BoxShape3D.new()
	bx.size = Vector3(2.5, 3.0, 14.0)
	cs.shape = bx
	cs.position.y = 1.5
	body.add_child(cs)
	var n = Vehicles.make("tram")
	body.add_child(n)
	body.visible = false
	add_child(body)
	tram = {"body": body, "a": Vector3(a[0], 0, a[2]), "b": Vector3(b[0], 0, b[2]), "period": float(tr["period"]), "rang": false}


func light_state(c: Dictionary) -> String:
	var cy: Array = c["cycle"]
	var total = float(cy[0]) + float(cy[1]) + float(cy[2])
	var x = fmod(t + float(c["offset"]), total)
	if x < float(cy[0]):
		return "green"
	if x < float(cy[0]) + float(cy[1]):
		return "yellow"
	return "red"


func player_runs_red() -> bool:
	var p: Player = world.player
	if not p.riding() or abs(p.speed) < 2.0:
		return false
	var q = Vector2(p.global_position.x, p.global_position.z)
	for c in crossings:
		if c["rect"].has_point(q) and light_state(c) == "green":
			return true
	return false


func _pos_at(path: Dictionary, s: float) -> Array:
	var L: float = path["len"]
	s = fposmod(s, L)
	var cum: PackedFloat32Array = path["cum"]
	var pts: PackedVector3Array = path["pts"]
	for i in range(1, cum.size()):
		if s <= cum[i]:
			var k = (s - cum[i - 1]) / max(0.001, cum[i] - cum[i - 1])
			var p = pts[i - 1].lerp(pts[i], k)
			var d = (pts[i] - pts[i - 1]).normalized()
			return [p, d]
	return [pts[0], (pts[1] - pts[0]).normalized()]


func _physics_process(delta: float) -> void:
	if not world.started:
		return
	t += delta
	_update_lights()
	_count_t -= delta
	if _count_t <= 0.0:
		_count_t = 5.0
		var want = _wanted_cars()
		if cars.size() < want:
			var pi = randi() % paths.size()
			var s = _free_spot(pi)
			if s >= 0.0:
				_spawn_car(pi, s)
		elif cars.size() > want:
			var c: Dictionary = cars[randi() % cars.size()]
			if c["body"].global_position.distance_to(world.player.global_position) > 60.0:
				c["body"].queue_free()
				cars.erase(c)
	var pp: Vector3 = world.player.global_position
	for c in cars:
		var path: Dictionary = paths[c["path"]]
		var cur = _pos_at(path, c["s"])
		var pos: Vector3 = cur[0]
		var dir: Vector3 = cur[1]
		var target_v: float = c["vmax"]
		# car ahead on the same path
		for o in cars:
			if o == c or o["path"] != c["path"]:
				continue
			var ds = fposmod(float(o["s"]) - float(c["s"]), path["len"])
			if ds < GAP + 3.0:
				target_v = min(target_v, max(0.0, (ds - GAP) * 1.2))
		# traffic lights
		for cr in crossings:
			var st = light_state(cr)
			if st == "green":
				continue
			var r: Rect2 = cr["rect"].grow(1.0)
			if r.has_point(Vector2(pos.x, pos.z)):
				continue
			for k in [3.0, 6.0, 9.0]:
				var ahead: Vector3 = _pos_at(path, c["s"] + k)[0]
				if r.has_point(Vector2(ahead.x, ahead.z)):
					target_v = min(target_v, max(0.0, (k - 3.0) * 1.0))
					break
		# the player in front
		var to_p = pp - pos
		to_p.y = 0
		var fwd_d = to_p.dot(dir)
		var lat = abs(to_p.cross(dir).y)
		if fwd_d > 0.0 and fwd_d < 11.0 and lat < 1.8:
			target_v = min(target_v, max(0.0, (fwd_d - 3.2) * 1.4))
			c["horn"] -= delta
			if fwd_d < 7.0 and c["horn"] <= 0.0:
				c["horn"] = 6.0
				Sfx.play("horn", 0.4)
		if fwd_d > -1.0 and fwd_d < 2.6 and lat < 1.1 and c["v"] > 3.0 and world.player.fallen <= 0.0:
			world.player.fall(2.0)
			world.banner("Бум!", "Машина задела курьера. Переходи дорогу по зебре на зелёный!")
		var acc = 6.0 if target_v < c["v"] else 2.5
		c["v"] = move_toward(c["v"], target_v, acc * delta)
		c["s"] = fposmod(c["s"] + c["v"] * delta, path["len"])
		var body: AnimatableBody3D = c["body"]
		body.global_position = pos
		body.rotation.y = lerp_angle(body.rotation.y, atan2(dir.x, dir.z), clamp(8.0 * delta, 0.0, 1.0))
		_spin(c["node"], c["v"], delta)
	_tram(delta)


func _free_spot(pi: int) -> float:
	var L: float = paths[pi]["len"]
	for _i in 10:
		var s = randf() * L
		var ok = true
		for o in cars:
			if o["path"] == pi and abs(fposmod(float(o["s"]) - s + L / 2.0, L) - L / 2.0) < 15.0:
				ok = false
		var p: Vector3 = _pos_at(paths[pi], s)[0]
		if p.distance_to(world.player.global_position) < 40.0:
			ok = false
		if ok:
			return s
	return -1.0


func _spin(n: Node3D, v: float, delta: float) -> void:
	for w in n.find_children("WHEEL_*", "", true, false):
		(w as Node3D).rotate_object_local(Vector3.RIGHT, v / 0.33 * delta)


func _update_lights() -> void:
	for tl in world.level.traffic_lights:
		var node: Node3D = tl["node"]
		var best = {}
		var bd = 1e9
		for c in crossings:
			var d: float = c["rect"].get_center().distance_to(Vector2(node.global_position.x, node.global_position.z))
			if d < bd:
				bd = d
				best = c
		if best.is_empty():
			continue
		var st = light_state(best)
		for k in ["red", "yellow", "green"]:
			var mi: MeshInstance3D = tl.get(k)
			if mi and mi.material_override:
				(mi.material_override as StandardMaterial3D).emission_energy_multiplier = 3.0 if k == st else 0.0


func _tram(delta: float) -> void:
	if tram.is_empty():
		return
	var period: float = tram["period"]
	var x = fmod(t, period)
	var travel = 26.0
	var body: AnimatableBody3D = tram["body"]
	if x < travel:
		body.visible = true
		var k = x / travel
		var a: Vector3 = tram["a"]
		var b: Vector3 = tram["b"]
		var forward = int(t / period) % 2 == 0
		var p = a.lerp(b, k) if forward else b.lerp(a, k)
		body.global_position = p
		body.rotation.y = atan2((b - a).x, (b - a).z) + (0.0 if forward else PI)
		if not tram["rang"] and p.distance_to(world.player.global_position) < 30.0:
			tram["rang"] = true
			Sfx.play("tram_bell", 0.6)
		if p.distance_to(world.player.global_position) < 4.0 and world.player.fallen <= 0.0:
			world.player.fall(2.5)
			world.banner("Дзынь!", "Трамвай не тормозит. Пути переходи только по зебре.")
	else:
		body.visible = false
		body.global_position = Vector3(0, -50, 0)
		tram["rang"] = false
