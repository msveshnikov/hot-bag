class_name People
extends Node3D
## Background NPCs, cooks, the mentor, police, rival couriers, thieves (Task 4 population JSON).
## No physics: NPCs walk on walkable grid cells; streamed by distance to the player.

const SPAWN_R = 75.0
const DESPAWN_R = 95.0

var world: Node
var npcs: Array = []        # dicts {data, node, home, target, t}
var cooks = {}
var mentor: Node3D
var police: Array = []      # {data, node, route_i}
var rivals: Array = []      # {data, node, path, i, wait}
var thief = {}
var fine_cd = 0.0
var _tick = 0.0


func setup(w: Node) -> void:
	world = w
	var pop: Dictionary = Game.population
	for n in pop["npcs"]:
		npcs.append({"data": n, "node": null, "home": _v(n["pos"]), "target": _v(n["pos"]), "t": randf() * 3.0})
	for c in pop["cooks"]:
		var node = Chars.make("cook", "cook_idle")
		node.position = _v(c["pos"])
		node.rotation.y = deg_to_rad(float(c["yaw"]))
		add_child(node)
		cooks[c["restaurant"]] = node
	var m: Dictionary = pop["mentor"]
	mentor = Chars.make("mentor", "sip_coffee", ["bag", "hair"])
	mentor.position = _v(m["pos"])
	mentor.rotation.y = deg_to_rad(float(m["yaw"]))
	add_child(mentor)
	var chair: PackedScene = load("res://assets/props/cafe_set_turq.gltf")
	if chair:
		var cs: Node3D = chair.instantiate()
		cs.position = mentor.position + Vector3(0.75, 0, 0).rotated(Vector3.UP, mentor.rotation.y)
		cs.rotation.y = mentor.rotation.y
		add_child(cs)
	for p in pop["police"]:
		var node = Chars.make("police", p.get("anim", "idle"))
		node.position = _v(p["pos"])
		node.rotation.y = deg_to_rad(float(p["yaw"]))
		add_child(node)
		police.append({"data": p, "node": node, "ri": 0})
	for r in pop["rivals"]:
		var node = Node3D.new()
		var body = Chars.make(r["model"], "ride_scooter", ["ACC_bag", "ACC_cap", "ACC_hair_short", "ACC_hair_ponytail"])
		Chars.set_jacket(body, Color(r["jacket"]))
		node.add_child(body)
		var sc = Vehicles.make("scooter")
		node.add_child(sc)
		node.position = _v(r["pos"])
		add_child(node)
		rivals.append({"data": r, "node": node, "path": PackedVector3Array(), "i": 0, "wait": randf() * 4.0, "veh": sc})


func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _process(delta: float) -> void:
	if not world.started:
		return
	var pp: Vector3 = world.player.global_position
	var hour: float = world.daynight.hour
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		for n in npcs:
			var d: Dictionary = n["data"]
			var sch: Array = d["schedule"]
			var want: bool = hour >= sch[0] and hour < sch[1] and n["home"].distance_to(pp) < SPAWN_R
			if world.daynight.rain > 0.6 and d["behaviour"] in ["sit", "photo"]:
				want = false
			if want and n["node"] == null:
				var node = Chars.make(d["model"], d["anim"])
				node.position = n["home"]
				node.rotation.y = deg_to_rad(float(d["yaw"]))
				add_child(node)
				n["node"] = node
			elif not want and n["node"] != null and n["home"].distance_to(pp) > DESPAWN_R * (0.0 if hour >= sch[1] or hour < sch[0] else 1.0):
				n["node"].queue_free()
				n["node"] = null
	for n in npcs:
		if n["node"] and n["data"]["behaviour"] == "wander":
			_wander(n, delta)
	_police(delta, pp)
	_rivals(delta)
	_thief(delta)
	# the mentor and cooks look at the player when close
	if mentor and mentor.position.distance_to(pp) < 6.0:
		var dir = pp - mentor.position
		mentor.rotation.y = lerp_angle(mentor.rotation.y, atan2(dir.x, dir.z), delta * 3.0)


func _wander(n: Dictionary, delta: float) -> void:
	var node: Node3D = n["node"]
	var to: Vector3 = n["target"] - node.position
	to.y = 0
	if to.length() < 0.5:
		n["t"] -= delta
		Chars.play(node, "idle")
		if n["t"] <= 0.0:
			n["t"] = randf_range(1.0, 5.0)
			for _i in 6:
				var cand: Vector3 = n["home"] + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * float(n["data"]["radius"])
				if world.level.surface_at(cand) in ["c", "s", "p"] and _line_ok(node.position, cand):
					n["target"] = cand
					break
		return
	var step = to.normalized() * 1.1 * delta
	var nxt = node.position + step
	if not (world.level.surface_at(nxt) in ["c", "s", "p", "z", "g"]):
		n["target"] = node.position
		return
	# keep out of the player's way
	if nxt.distance_to(world.player.global_position) < 0.9:
		return
	node.position = nxt
	node.rotation.y = lerp_angle(node.rotation.y, atan2(to.x, to.z), delta * 6.0)
	Chars.play(node, "walk")


func _line_ok(a: Vector3, b: Vector3) -> bool:
	var n = int(a.distance_to(b) / 1.5) + 1
	for i in n:
		var p = a.lerp(b, float(i) / n)
		if not (world.level.surface_at(p) in ["c", "s", "p", "z", "g"]):
			return false
	return true


# ---------------------------------------------------------------- police
func _police(delta: float, pp: Vector3) -> void:
	fine_cd = max(0.0, fine_cd - delta)
	for p in police:
		var node: Node3D = p["node"]
		var d: Dictionary = p["data"]
		if d["behaviour"] == "patrol":
			var sch: Array = d.get("schedule", [0, 24])
			node.visible = world.daynight.hour >= sch[0] and world.daynight.hour < sch[1]
			if not node.visible:
				continue
			var route: Array = d["route"]
			var tgt = _v(route[p["ri"]])
			var to = tgt - node.position
			to.y = 0
			if to.length() < 0.6:
				p["ri"] = (int(p["ri"]) + 1) % route.size()
			else:
				node.position += to.normalized() * 1.2 * delta
				node.rotation.y = lerp_angle(node.rotation.y, atan2(to.x, to.z), delta * 5.0)
				Chars.play(node, "walk")
		if not node.visible or fine_cd > 0.0:
			continue
		var dist = node.position.distance_to(pp)
		if dist > float(d["see_radius"]):
			continue
		var reason = ""
		if world.player.on_sidewalk:
			reason = "езда по тротуару"
		elif world.traffic.player_runs_red():
			reason = "проезд на красный"
		elif world.daynight.is_dark() and world.player.mode == Player.Mode.SCOOTER and Game.upgrade_level("headlight") == 0 and abs(world.player.speed) > 3.0:
			reason = "езда ночью без фары"
		if reason != "":
			fine_cd = 25.0
			var amount = 10.0 if reason != "проезд на красный" else 18.0
			Game.spend(amount)
			Game.state["stats"]["fines"] += amount
			Sfx.play("whistle")
			Chars.play(node, "whistle")
			node.look_at(Vector3(pp.x, node.position.y, pp.z), Vector3.UP, true)
			world.banner("Штраф −%d" % int(amount), "Полиция: %s. Соблюдай правила рядом с постом!" % reason)


# ---------------------------------------------------------------- rivals
func _rivals(delta: float) -> void:
	if not world.events.rivals_active():
		for r in rivals:
			r["node"].visible = false
		return
	for r in rivals:
		var node: Node3D = r["node"]
		node.visible = true
		if r["wait"] > 0.0:
			r["wait"] -= delta
			continue
		var path: PackedVector3Array = r["path"]
		if r["i"] >= path.size():
			# new trip: restaurant <-> random door
			var rkeys: Array = Game.orders_data["restaurants"].keys()
			var doors: Array = Game.orders_data["doors"]
			var to: Vector3
			if randf() < 0.5:
				var rr: Dictionary = Game.orders_data["restaurants"][rkeys[randi() % rkeys.size()]]
				to = _v(rr["parking"])
			else:
				to = _v(doors[randi() % doors.size()]["pos"])
			r["path"] = world.nav.path(node.position, to, "scooter")
			r["i"] = 0
			r["wait"] = randf_range(2.0, 6.0)
			continue
		var tgt: Vector3 = path[r["i"]]
		var d = tgt - node.position
		d.y = 0
		var spd: float = float(r["data"]["speed"])
		if node.position.distance_to(world.player.global_position) < 3.0:
			spd *= 0.3
		if d.length() < 0.6:
			r["i"] += 1
		else:
			node.position += d.normalized() * min(spd * delta, d.length())
			node.position.y = world.level.ground_height(node.position)
			node.rotation.y = lerp_angle(node.rotation.y, atan2(d.x, d.z), delta * 6.0)
			Vehicles.spin(r["veh"], spd, 0.0, delta, 0.0)


# ---------------------------------------------------------------- thief
func steal(vehicle_node: Node3D, kind: String) -> void:
	var marks = []
	for m in Game.layout["markers"]:
		if m["name"] == "MARK_thief":
			marks.append(m)
	var start = vehicle_node.global_position + Vector3(6, 0, 6)
	if not marks.is_empty():
		var best: Dictionary = marks[0]
		for m in marks:
			if _v(m["pos"]).distance_to(vehicle_node.global_position) < _v(best["pos"]).distance_to(vehicle_node.global_position):
				best = m
		start = _v(best["pos"])
	var t = Chars.make("thief", "sneak")
	t.position = start
	add_child(t)
	thief = {"node": t, "veh": vehicle_node, "kind": kind, "phase": "sneak", "path": world.nav.path(start, vehicle_node.global_position, "foot"), "i": 0, "time": 0.0}


func _thief(delta: float) -> void:
	if thief.is_empty():
		return
	var t: Node3D = thief["node"]
	thief["time"] += delta
	var path: PackedVector3Array = thief["path"]
	var spd = 2.2 if thief["phase"] == "sneak" else 6.5
	if thief["i"] < path.size():
		var d: Vector3 = path[thief["i"]] - t.position
		d.y = 0
		if d.length() < 0.5:
			thief["i"] += 1
		else:
			t.position += d.normalized() * min(spd * delta, d.length())
			t.position.y = world.level.ground_height(t.position)
			t.rotation.y = atan2(d.x, d.z)
	elif thief["phase"] == "sneak":
		# reached the vehicle: ride away
		thief["phase"] = "escape"
		var veh: Node3D = thief["veh"]
		world.vehicle_stolen(veh)
		if veh.get_parent():
			veh.get_parent().remove_child(veh)
		t.add_child(veh)
		veh.transform = Transform3D.IDENTITY
		Chars.play(t, "ride_bike" if thief["kind"] == "bicycle" else "ride_scooter")
		var far = t.position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 90.0
		thief["path"] = world.nav.path(t.position, far, "bicycle")
		thief["i"] = 0
		thief["time"] = 0.0
		Sfx.play("bell", 0.5, 1.3)
	else:
		_thief_end(false)
		return
	if thief["phase"] == "escape":
		if t.position.distance_to(world.player.global_position) < 1.8:
			_thief_end(true)
		elif thief["time"] > 25.0:
			_thief_end(false)


func _thief_end(caught: bool) -> void:
	var veh: Node3D = thief["veh"]
	var t: Node3D = thief["node"]
	if veh.get_parent() == t:
		t.remove_child(veh)
	world.vehicle_returned(veh, thief["kind"], caught, t.global_position)
	t.queue_free()
	thief = {}


func cook_for(rest: String) -> Node3D:
	return cooks.get(rest)
