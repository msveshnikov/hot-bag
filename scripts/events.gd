class_name Events
extends Node
## Courier problems (Task 4 old_town_events.json): random scheduler weighted by chapter + state triggers.

var world: Node
var list: Array = []
var timer = 60.0
var pending = {}          # flags applied to the next accepted order
var active_ev = {}        # id -> seconds left
var flat = false
var roadblock_rect = Rect2()
var roadblock_nodes: Array[Node3D] = []
var log: Array = []
var rs = RandomNumberGenerator.new()


func setup(w: Node) -> void:
	world = w
	list = Game.events_data.get("events", [])
	rs.seed = 77 + int(Game.state["day"])
	var iv: Array = Game.events_data.get("base_interval_s", [70, 120])
	timer = rs.randf_range(iv[0], iv[1]) * 0.6


func chapter_idx() -> int:
	return clamp(int(Game.state["chapter"]) - 1, 0, 2)


func rivals_active() -> bool:
	return int(Game.state["chapter"]) >= 2


func _process(delta: float) -> void:
	if not world.started or get_tree().paused or not world.story.events_allowed():
		return
	for k in active_ev.keys():
		active_ev[k] -= delta
		if active_ev[k] <= 0.0:
			active_ev.erase(k)
			_end(k)
	timer -= delta
	if timer <= 0.0:
		var iv: Array = Game.events_data.get("base_interval_s", [70, 120])
		var f = 1.0 - 0.15 * chapter_idx()
		timer = rs.randf_range(iv[0], iv[1]) * f
		_fire_random()


func _eligible(e: Dictionary) -> bool:
	var id: String = e["id"]
	if active_ev.has(id) or pending.has(id):
		return false
	var p: Player = world.player
	match id:
		"battery_low":
			return p.mode == Player.Mode.SCOOTER and world.battery > 25.0
		"flat_tire":
			return p.riding() and not flat and abs(p.speed) > 2.0
		"rain":
			return world.daynight.rain_target < 0.5 and world.daynight.hour < 21.5
		"heat":
			return false  # natural at noon
		"roadblock":
			return roadblock_nodes.is_empty()
		"restaurant_delay", "wrong_address", "no_answer", "intercom", "broken_lift":
			return true
		_:
			return false


func _fire_random() -> void:
	var ci = chapter_idx()
	var pool = []
	var total = 0.0
	for e in list:
		var w = float(e["weight"][ci])
		if w > 0.0 and _eligible(e):
			pool.append([e, w])
			total += w
	if pool.is_empty():
		return
	var r = rs.randf() * total
	for pe in pool:
		r -= pe[1]
		if r <= 0.0:
			fire(pe[0]["id"])
			return


func ev(id: String) -> Dictionary:
	for e in list:
		if e["id"] == id:
			return e
	return {"id": id, "title": id, "text": ""}


func announce(id: String) -> void:
	var e = ev(id)
	world.banner(e["title"], e["text"])
	log.append(id)


func fire(id: String) -> void:
	match id:
		"battery_low":
			world.battery = min(world.battery, 14.0)
			announce(id)
		"flat_tire":
			flat = true
			announce(id)
			Sfx.play("splash", 0.5, 0.6)
		"rain":
			world.daynight.rain_target = 1.0
			active_ev["rain"] = float(ev(id).get("duration", 180))
			announce(id)
		"roadblock":
			_roadblock(true)
			active_ev["roadblock"] = float(ev(id).get("duration", 200))
			announce(id)
		"restaurant_delay", "wrong_address", "no_answer", "intercom", "broken_lift":
			pending[id] = true
			# applied on the next accepted order; announce when it bites
		_:
			announce(id)


func _end(id: String) -> void:
	match id:
		"rain":
			world.daynight.rain_target = 0.0
			world.toast("Дождь закончился. Лужи скоро высохнут.", 2.5)
		"roadblock":
			_roadblock(false)
			world.toast("Перекрытие сняли — дорога свободна.", 2.5)


func _roadblock(on: bool) -> void:
	var ms: Array = []
	for m in Game.layout["markers"]:
		if m["name"] == "MARK_roadblock":
			ms.append(m)
	if ms.is_empty():
		return
	if on:
		var m: Dictionary = ms[rs.randi() % ms.size()]
		var r: Array = m["rect"]   # Blender x0,y0,x1,y1
		roadblock_rect = Rect2(Vector2(r[0], -r[3]), Vector2(r[2] - r[0], r[3] - r[1]))
		world.nav.set_block(roadblock_rect, true)
		var ps: PackedScene = load("res://assets/props/barrier_works.gltf")
		var cone: PackedScene = load("res://assets/props/traffic_cone.gltf")
		var c = roadblock_rect.get_center()
		var along_x = roadblock_rect.size.x >= roadblock_rect.size.y
		for k in 4:
			var t = (k - 1.5) / 1.5
			var n: Node3D = ps.instantiate()
			if along_x:
				n.position = Vector3(c.x + t * roadblock_rect.size.x * 0.4, 0, c.y)
			else:
				n.position = Vector3(c.x, 0, c.y + t * roadblock_rect.size.y * 0.4)
				n.rotation.y = PI / 2
			world.add_child(n)
			roadblock_nodes.append(n)
		for k in 3:
			var cn: Node3D = cone.instantiate()
			cn.position = Vector3(c.x + randf_range(-2, 2), 0, c.y + randf_range(-2, 2))
			world.add_child(cn)
			roadblock_nodes.append(cn)
		world.refresh_gps()
	else:
		world.nav.set_block(roadblock_rect, false)
		for n in roadblock_nodes:
			n.queue_free()
		roadblock_nodes.clear()
		world.refresh_gps()


# ---------------------------------------------------------------- hooks from orders
func on_accept(o: Dictionary) -> void:
	if world.story.events_allowed() == false:
		return
	if pending.has("restaurant_delay"):
		pending.erase("restaurant_delay")
		o["cook_left"] = float(o["cook_left"]) + 45.0
		o["flags"]["delay"] = true
	if pending.has("wrong_address"):
		pending.erase("wrong_address")
		# the pin points to a neighbouring door of the same street
		var best = {}
		var bd = 1e9
		for d in Game.orders_data["doors"]:
			if d["id"] == o["door"]["id"]:
				continue
			var dist = Vector3(d["pos"][0], 0, d["pos"][2]).distance_to(Vector3(o["door"]["pos"][0], 0, o["door"]["pos"][2]))
			if dist > 6.0 and dist < bd:
				bd = dist
				best = d
		if not best.is_empty():
			o["flags"]["pin_door"] = best
	for k in ["no_answer", "intercom", "broken_lift"]:
		if pending.has(k):
			pending.erase(k)
			o["flags"][k] = true


func on_pickup(o: Dictionary) -> void:
	if o["flags"].get("delay"):
		pass


func on_deliver(_o: Dictionary, _res: Dictionary) -> void:
	pass


func fix_flat() -> bool:
	if not flat:
		return false
	flat = false
	world.toast("Колесо как новое!", 2.0)
	return true
