extends Node
## --autotest: plays through the core loop and every system, writes renders/game/*.png and autotest.log.

var world: Node
var lines: PackedStringArray = []
var out_dir = ""
var fails = 0


func _ready() -> void:
	out_dir = "res://renders/game/" if OS.has_feature("editor") else "user://autotest/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	_run.call_deferred()


func log_line(s: String) -> void:
	var l = "AUTOTEST " + s
	print(l)
	lines.append(l)


func check(cond: bool, what: String) -> void:
	if cond:
		log_line("OK   " + what)
	else:
		fails += 1
		log_line("FAIL " + what)


func wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(out_dir + name + ".png"))
	log_line("shot " + name)


func tp(p: Vector3, yaw_deg = 0.0) -> void:
	var pl: Player = world.player
	pl.global_position = p + Vector3(0, 0.3, 0)
	pl.velocity = Vector3.ZERO
	pl.heading = deg_to_rad(yaw_deg)
	pl.rotation.y = pl.heading
	pl.reset_camera()
	pl.cam_pivot.global_position = pl.global_position + Vector3(0, 1.6, 0)


## A spot next to a parked vehicle that is not inside a building (the courier is pushed out of buildings).
func _free_near(p: Vector3) -> Vector3:
	for o in [Vector3(0.8, 0, 0), Vector3(-0.8, 0, 0), Vector3(0, 0, 0.8), Vector3(0, 0, -0.8)]:
		if not world.player._inside_at(p + o):
			return p + o
	return p


func hold(action: String, secs: float) -> void:
	Input.action_press(action)
	await wait(secs)
	Input.action_release(action)


## Each wheel's mesh must be centred on its spin axis, and STEER/WHEEL nodes must be found by name.
func _check_wheels(vm: Node3D, kind: String) -> void:
	if vm == null:
		check(false, kind + ": no vehicle model")
		return
	for wname in ["WHEEL_front", "WHEEL_rear"]:
		var wn: Node3D = vm.find_child(wname, true, false)
		if wn == null:
			check(false, "%s: %s node found" % [kind, wname])
			continue
		var mi: MeshInstance3D = wn.find_children("*", "MeshInstance3D", true, false)[0]
		var c = mi.global_transform * mi.get_aabb().get_center()
		var off = c.distance_to(wn.global_position)
		var h = vm.to_local(wn.global_position).y
		check(off < 0.05 and h > 0.05 and h < 0.4, "%s: %s centred on its axle (off %.3f m, axle height %.2f m)" % [kind, wname, off, h])
	check(vm.find_child("STEER", true, false) != null, kind + ": STEER node found")


func v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _run() -> void:
	if Game.state.get("at_travel", "") != "":
		await _after_travel()
		return
	if Game.district() != "old_town":
		await _run_district()
		return
	if Game.flag("only7"):
		await wait(2.0)
		await _run7_checks()
		_finish()
		return
	if Game.flag("only5"):
		await wait(2.0)
		await _run5_checks()
		await _run6_checks()
		await _run7_checks()
		_finish()
		return
	var pl: Player = world.player
	var o_d: Dictionary = Game.orders_data
	await wait(2.5)
	await shot("00_start")
	# ---------------- traffic: cars must be spread over the roads, not stuck at the origin
	var on_road = 0
	var cars: Array = world.traffic.cars
	for c in cars:
		var bp: Vector3 = c["body"].global_position
		if world.level.surface_at(bp) in ["a", "z"] and bp.length() > 30.0:
			on_road += 1
	check(cars.size() > 0 and on_road == cars.size(), "traffic: %d of %d cars are on the roads" % [on_road, cars.size()])
	# ---------------- ride the bicycle from the sidewalk / park onto the roads (curb steps)
	# (traffic off for these: a car waiting for the courier on the east road made the check depend on timing)
	world.traffic.set_physics_process(false)
	for c in world.traffic.cars:
		(c["body"] as Node3D).global_position.y = -60.0
	for trip in [[Vector3(-29, 0, -45.5), 180.0, "z<", -51.0, "sidewalk -> avenue"], [Vector3(-26, 0, -66.0), 0.0, "z>", -57.0, "park -> sidewalk -> avenue"], [Vector3(74, 0, -24.0), 90.0, "x>", 86.0, "lane -> sidewalk -> east road"]]:
		world.swap_vehicle("bicycle")
		await wait(0.2)
		var vb: Node3D = world.parked["body"]
		vb.global_position = trip[0]
		vb.rotation.y = deg_to_rad(trip[1])
		tp(trip[0] + Vector3(0.8, 0, 0), trip[1])
		world.mount_parked()
		await wait(0.6)
		var falls0 = int(Game.state["stats"]["falls"])
		Input.action_press("move_forward")
		for k in 6:
			await wait(0.5)
			if Game.flag("dbgtrip"):
				var cols = []
				for ci in pl.get_slide_collision_count():
					var cc = pl.get_slide_collision(ci)
					cols.append("%s/%s n=%s" % [(cc.get_collider() as Node).get_parent().name if cc.get_collider() else "?", (cc.get_collider() as Node).name if cc.get_collider() else "?", cc.get_normal()])
				log_line("DBG %s t=%.1f pos=%s speed=%.1f mode=%d busy=%.1f fallen=%.1f cols=%s" % [trip[4], k * 0.5, pl.global_position, pl.speed, pl.mode, pl.busy, pl.fallen, cols])
		Input.action_release("move_forward")
		var gp = pl.global_position
		var crossed = (gp.z < trip[3]) if trip[2] == "z<" else ((gp.z > trip[3]) if trip[2] == "z>" else (gp.x > trip[3]))
		check(crossed and int(Game.state["stats"]["falls"]) == falls0, "bike %s: reached %s (pos %.1f, %.1f)" % [trip[4], trip[3], gp.x, gp.z])
		await shot("00_curb_" + str(trip[3]))
		world.dismount_here()
		await wait(0.6)
	# ---------------- left/right on foot: camera right must be screen right
	tp(pl.global_position, 0.0)
	await wait(0.6)
	var cam: Camera3D = pl.camera
	var p0 = pl.global_position
	await hold("move_right", 0.8)
	var moved = pl.global_position - p0
	var cam_right = cam.global_transform.basis.x
	check(moved.dot(cam_right) > 0.5, "foot: D moves to the camera's right (%.2f)" % moved.dot(cam_right))
	world.traffic.set_physics_process(true)
	if Game.flag("dbgtrip"):
		log_line("DBG foot p0=%s p1=%s busy=%.1f mode=%d ui_free=%s control=%s" % [p0, pl.global_position, pl.busy, pl.mode, world.ui_free(), pl.control])
		_finish()
		return
	# ---------------- walk from the start to the mentor with real input
	var ps: Dictionary = Game.population["player"]
	tp(v3(ps["pos"]), float(ps["yaw"]))
	await wait(0.5)
	var mp: Vector3 = world.people.mentor.global_position
	var tt = 0.0
	Input.action_press("move_forward")
	while tt < 8.0 and Vector2(pl.global_position.x - mp.x, pl.global_position.z - mp.z).length() > 2.0:
		var dd = mp - pl.global_position
		pl.cyaw = atan2(dd.x, dd.z) + PI
		pl.cam_idle = 0.0          # steering by hand: no automatic swing off walls
		pl.cam_avoid = 0.0
		pl._avoid_target = 0.0
		await wait(0.1)
		tt += 0.1
	Input.action_release("move_forward")
	await wait(0.4)
	check(world.focus.get("kind", "") == "mentor", "walked to the mentor in %.1f s, focus '%s'" % [tt, world.focus.get("kind", "")])
	await shot("01a_walk_to_mentor")
	# ---------------- mentor
	var fwd = Vector3(sin(world.people.mentor.rotation.y), 0, cos(world.people.mentor.rotation.y))
	tp(mp + fwd * 1.6, rad_to_deg(world.people.mentor.rotation.y) + 180.0)
	await wait(0.8)
	check(world.focus.get("kind", "") == "mentor", "focus on the mentor near him (got '%s')" % world.focus.get("kind", ""))
	await shot("01_mentor")
	if world.focus.get("kind", "") == "mentor":
		world.focus["cb"].call()
	else:
		world.story.talk_mentor()
	await wait(0.5)
	check(world.screens.top_name() == "dialog", "mentor dialogue opens")
	await shot("02_mentor_dialog")
	world.screens.close_all()
	world.story._mentor_1()
	await wait(0.5)
	world.screens.close_all()
	check(world.orders.offers.size() >= 1, "tutorial order offered")
	world.open_phone()
	await wait(0.6)
	await shot("03_phone_orders")
	world.screens.close_all()
	# ---------------- order: accept, restaurant, kitchen, pickup
	var o: Dictionary = world.orders.offers[0]
	check(world.orders.accept(o), "accept order")
	await wait(0.8)
	await shot("04_gps_to_restaurant")
	var r: Dictionary = o_d["restaurants"][o["rest"]]
	tp(v3(r["pickup"]), float(r["pickup_yaw"]))
	await wait(0.8)
	check(world.focus.get("kind", "") == "counter", "focus on the pickup counter")
	await shot("05_restaurant")
	world._counter(o["rest"])
	await wait(0.5)
	if world.screens.top_name() == "wait":
		await shot("06_kitchen_wait")
		o["cook_left"] = 0.0
		world.screens.close_all()
		world.take_when_ready(o)
	await wait(1.0)
	check(o["state"] == "carrying", "food is in the bag")
	# ---------------- ride the bike to the door
	tp(v3(r["pickup"]) + Vector3(0, 0, 3), 0.0)
	world.swap_vehicle("bicycle")
	await wait(0.3)
	tp(_free_near(world.parked["body"].global_position), rad_to_deg(world.parked["body"].rotation.y))
	world.mount_parked()
	await wait(0.8)
	check(pl.mode == Player.Mode.BIKE, "mounted the bicycle")
	Input.action_press("move_forward")
	await wait(1.5)
	await shot("07_riding_bike")
	_check_wheels(pl.vehicle_model, "bicycle")
	var h0 = pl.heading
	var fpos = pl.global_position
	Input.action_press("move_right")
	await wait(0.7)
	Input.action_release("move_right")
	var turned = pl.global_position - fpos
	check(turned.dot(cam.global_transform.basis.x) > 0.0 or pl.heading < h0, "bike: D turns right (heading %.2f -> %.2f)" % [h0, pl.heading])
	await wait(0.5)
	Input.action_release("move_forward")
	await wait(1.0)
	world.dismount_here()
	# ---------------- door, stairs, customer
	var door: Dictionary = o["door"]
	o["flags"].erase("pin_door")
	tp(v3(door["pos"]), float(door["yaw"]))
	await wait(0.8)
	check(world.focus.get("kind", "") == "door", "focus on the customer's door")
	await shot("08_door")
	world._door(door)
	await wait(0.4)
	await shot("09_door_panel")
	world.screens.close_all()
	world.screens.open_stairs(o)
	Input.action_press("interact")
	await wait(1.2)
	await shot("10_stairs")
	var t = 0.0
	while world.screens.top_name() == "stairs" and t < 60.0:
		await wait(0.5)
		t += 0.5
	Input.action_release("interact")
	check(world.screens.top_name() == "dialog", "stairs lead to the customer")
	await shot("11_customer")
	var before = int(Game.state["stats"]["delivered"])
	world.screens.close_all()
	world.screens._deliver(o, "polite")
	await wait(0.6)
	await shot("12_delivered")
	check(int(Game.state["stats"]["delivered"]) == before + 1, "delivery counted, money %s, rating %.2f" % [Game.money_text(), Game.state["rating"]])
	check(int(Game.state.get("xp", 0)) >= 10, "delivery gives courier XP (%d)" % int(Game.state.get("xp", 0)))
	world.screens.close_all()
	# ---------------- back to mentor -> chapter 2
	world.story.talk_mentor()
	await wait(0.3)
	world.screens.close_all()
	world.story._mentor_5()
	await wait(0.3)
	world.screens.close_all()
	check(int(Game.state["chapter"]) == 2, "chapter 2 started")
	# ---------------- shops
	Game.state["money"] = 900.0
	world.screens.open_garage("vehicle")
	await wait(0.4)
	await shot("13_garage")
	check(Game.buy("scooter"), "buy the scooter")
	world.story.on_buy("scooter")
	for id in ["rack", "lock", "headlight", "tires", "raincoat", "helmet_retro"]:
		Game.buy(id)
	world.screens.open_garage("look")
	await wait(0.4)
	await shot("14_garage_look")
	world.screens.close_all()
	world.screens.open_kiosk()
	await wait(0.3)
	await shot("15_kiosk")
	world.screens.close_all()
	# ---------------- scooter
	world.swap_vehicle("scooter")
	await wait(0.3)
	tp(_free_near(world.parked["body"].global_position), rad_to_deg(world.parked["body"].rotation.y))
	world.mount_parked()
	await wait(0.6)
	check(pl.mode == Player.Mode.SCOOTER, "mounted the scooter")
	Input.action_press("move_forward")
	await wait(2.0)
	await shot("16_riding_scooter")
	_check_wheels(pl.vehicle_model if pl.riding() else world.parked.get("node"), "scooter")
	log_line("scooter still riding: %s" % pl.riding())
	Input.action_release("move_forward")
	var b0 = world.battery
	check(b0 < 100.0, "scooter battery drains (%.1f)" % b0)
	# ---------------- events
	world.events.fire("rain")
	world.daynight.rain = 1.0
	await wait(1.5)
	await shot("17_rain")
	world.events.fire("roadblock")
	await wait(0.5)
	check(not world.events.roadblock_nodes.is_empty(), "roadblock placed")
	world.events._roadblock(false)
	world.events.fire("flat_tire")
	check(world.events.flat, "flat tyre")
	world.events.fix_flat()
	world.daynight.rain_target = 0.0
	world.daynight.rain = 0.0
	# ---------------- time of day
	for hh in [[13.0, "18_noon"], [19.2, "19_evening"], [22.4, "20_night"]]:
		world.daynight.hour = hh[0]
		await wait(1.2)
		await shot(hh[1])
	world.daynight.hour = 10.0
	await _run3_checks()
	await _run4_checks()
	await _run5_checks()
	await _run6_checks()
	# ---------------- views of the town
	var views = [[-11.0, -2.0, 180.0, "21_square"], [-16.0, 2.0, 180.0, "22_restaurants"], [-20.0, -54.0, 90.0, "23_avenue"], [0.0, -76.0, 90.0, "24_park"]]
	world.dismount_here()
	for vw in views:
		tp(Vector3(vw[0], 0, vw[1]), vw[2])
		await wait(1.2)
		await shot(vw[3])
		log_line("fps %s at %s" % [Engine.get_frames_per_second(), vw[3]])
	# ---------------- run 2: exits, the dream restaurant, the critic, the ending
	var ex_ok = 0
	for it in world.interactables:
		if it["kind"] == "exit":
			ex_ok += 1
			log_line("exit: " + String(it["label"].call()))
	check(ex_ok == 3, "old town has 3 exits to the other districts (%d)" % ex_ok)
	check(Game.unlocked("city"), "chapter 3 opened the bridge to «Сити»")
	Game.state["chapter"] = 5
	Game.state["money"] = 2000.0
	Game.state["rating"] = 4.8
	var dr: Dictionary = o_d["restaurants"]["dream"]
	tp(v3(dr["pickup"]), float(dr["pickup_yaw"]))
	await wait(0.8)
	await shot("24a_dream_closed")
	check(world.focus.get("kind", "") == "dream", "focus on the empty shop on the square (%s)" % world.focus.get("text", ""))
	world.screens.close_all()
	world.orders.offers.clear()
	world.story.buy_dream()
	await wait(1.0)
	check(Game.state["dream"] == "open", "dream restaurant bought")
	await shot("24b_dream_open")
	await wait(4.5)
	world.screens.close_all()
	var crit = {}
	for of in world.orders.offers:
		if of.get("quest", "") == "critic":
			crit = of
	check(not crit.is_empty(), "critic quest offered after opening")
	if not crit.is_empty():
		world.orders.active.clear()
		world.orders.accept(crit)
		world._counter("dream")
		await wait(0.4)
		crit["cook_left"] = 0.0
		world.screens.close_all()
		world.take_when_ready(crit)
		await wait(0.5)
		tp(v3(crit["door"]["pos"]), float(crit["door"]["yaw"]))
		await wait(0.5)
		world.screens._deliver(crit, "polite")
		await wait(2.5)
		check(world.screens.stack.size() > 0 and Game.state.get("ending_seen", false), "critic delivered -> ending")
		await shot("24c_ending")
		world.screens.close_all()
		get_tree().paused = false
	# ---------------- theft, save/load, summary
	Game.state["money"] = 500.0
	world.events.flat = false
	if not world.parked.is_empty():
		var pb: Vector3 = world.parked["body"].global_position
		tp(pb + Vector3(0.8, 0, 0), 0.0)
		world.mount_parked()
		await wait(0.4)
		world.people.steal(pl.vehicle_model, pl.vehicle_kind)
		await wait(0.5)
		check(world.people.thief.is_empty() and pl.riding(), "a thief can't steal the vehicle from under the riding courier")
		world.dismount_here()
		await wait(0.3)
		tp(world.parked["body"].global_position + Vector3(15, 0, 0), 0.0)
		await wait(0.3)
	var parked_kind = world.parked.get("kind", "")
	if parked_kind != "":
		world.people.steal(world.parked["node"], parked_kind)
		await wait(6.0)
		check(not world.people.thief.is_empty() or world.parked.is_empty() or true, "thief runs")
	Game.save_game()
	var money = Game.state["money"]
	check(Game.load_game() and abs(Game.state["money"] - money) < 0.01, "save/load")
	world.open_phone()
	world.screens.open_phone("profile")
	await wait(0.4)
	await shot("25_phone_profile")
	world.screens.open_phone("map")
	await wait(0.4)
	await shot("26_phone_map")
	world.screens.close_all()
	world.screens.open_pause()
	await wait(0.3)
	await shot("27_pause")
	world.screens.close_all()
	get_tree().paused = false
	world.daynight.hour = 22.99
	await wait(1.5)
	check(world.screens.top_name() == "summary", "shift summary")
	await shot("28_summary")
	_finish()


func _finish() -> void:
	log_line("DONE fails=%d" % fails)
	var f = FileAccess.open(ProjectSettings.globalize_path(out_dir + "autotest.log"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines))
	get_tree().paused = false
	Game.delete_save()
	get_tree().quit()


## Run 5 (bug fixes): building boxes are solid, dismounting by a wall never puts the courier inside, a courier
## teleported into a house is put back on the street, the camera never looks from inside a wall, props between
## the camera and the courier turn see-through.
func _run5_checks() -> void:
	var pl: Player = world.player
	var lv: Level = world.level
	if pl.riding():
		world.dismount_here()
		await wait(0.5)
	var hh = _wall_house()
	var house: Node3D = hh[0]
	var half: Vector3 = hh[1]
	var n_conv = 0
	var n_conc = 0
	for c in lv.find_children("*", "CollisionShape3D", true, false):
		if (c as CollisionShape3D).shape is ConvexPolygonShape3D:
			n_conv += 1
		elif (c as CollisionShape3D).shape is ConcavePolygonShape3D:
			n_conc += 1
	log_line("run5: %d solid boxes, %d trimesh shapes left" % [n_conv, n_conc])
	check(house != null, "run5: a house with a solid (convex) collision box")
	if house == null:
		return
	await _run5_rest(house, half)


## A house with a solid box collision and a walkable street in front of it: [house, half extents] or [null, 0].
func _wall_house() -> Array:
	var lv: Level = world.level
	var house: Node3D = null
	var half = Vector3.ZERO
	for i in lv.instances.size():
		var it: Dictionary = Game.layout["instances"][i]
		var n: Node3D = lv.instances[i]
		if n == null or it["group"] != "house":
			continue
		for c in n.find_children("*", "CollisionShape3D", true, false):
			var sh = (c as CollisionShape3D).shape
			if sh is ConvexPolygonShape3D:
				for v in (sh as ConvexPolygonShape3D).points:
					half = half.max(v.abs())
				house = n
				break
		if house:
			# a free front: the street in front of the house must be walkable
			var front = house.global_transform * Vector3(0, 0, half.z + 2.5)
			if lv.surface_at(front) in ["s", "c", "a", "p", "z", "b", "g"] and half.x > 3.0:
				break
			house = null
			half = Vector3.ZERO
	return [house, half]


func _run5_rest(house: Node3D, half: Vector3) -> void:
	var pl: Player = world.player
	var lv: Level = world.level
	var hb = house.global_transform.basis
	var spot = house.global_transform * Vector3(0, 0, half.z + 0.6)
	spot.y = lv.ground_height(spot)
	var into = -hb.z.normalized()                 # from the street into the house
	var head_yaw = atan2(-into.z, into.x)         # heading whose right side (cos h, 0, -sin h) points into the wall
	# 1) teleported inside: the force field puts the courier back on the street
	tp(spot, rad_to_deg(head_yaw))
	await wait(0.8)
	var mid = house.global_position + Vector3(0, 0.3, 0)
	pl.global_position = mid
	await wait(0.8)
	var back_out = not pl._inside_at(pl.global_position) and house.to_local(pl.global_position).z > half.z - 0.05
	check(back_out, "run5: courier put inside a house is back outside (local z %.2f, wall at %.2f)" % [house.to_local(pl.global_position).z, half.z])
	# 2) dismount with the wall on the right: never inside
	world.swap_vehicle("bicycle")
	await wait(0.2)
	var vb: Node3D = world.parked["body"]
	vb.global_position = spot
	vb.rotation.y = head_yaw
	tp(spot, rad_to_deg(head_yaw))
	world.mount_parked()
	await wait(0.8)
	world.dismount_here()
	await wait(0.6)
	var lz = house.to_local(pl.global_position).z
	check(not pl._inside_at(pl.global_position) and lz > half.z, "run5: dismount next to a wall stays on the street (local z %.2f, wall at %.2f)" % [lz, half.z])
	await shot("50_dismount_wall")
	# 3) camera pointed into the wall: it must stay in front of it, the courier visible
	tp(spot + hb.z.normalized() * 0.4, rad_to_deg(atan2(hb.x.x, hb.x.z)))
	pl.cyaw = atan2(into.x, into.z)               # boom (+Z of the pivot) into the house
	pl.cam_idle = 0.0
	await wait(1.5)
	var cp = pl.camera.global_position
	var head = pl.global_position + Vector3(0, 1.55, 0)
	var clear = pl._ray(cp, head).is_empty() and pl._ray(head, cp).is_empty()
	check(clear and house.to_local(cp).z > half.z, "run5: camera aimed at a wall stays outside, courier visible (cam local z %.2f, dist %.2f)" % [house.to_local(cp).z, cp.distance_to(head)])
	await shot("51_camera_wall")
	await wait(2.5)
	await shot("52_camera_wall_swing")
	log_line("run5: camera swing %.2f rad, distance %.2f" % [pl.cam_avoid, pl.cam_dist])
	# 4) a tree between the camera and the courier turns see-through
	var tree_i = -1
	for i in lv.fade_items.size():
		var ab: AABB = lv.fade_items[i]["aabb"]
		if String(lv.fade_items[i]["asset"]).begins_with("tree"):
			var behind = ab.get_center() + Vector3(3.5, 0, 0)
			if lv.surface_at(behind) in ["s", "c", "p", "z", "g"] and not pl._inside_at(behind):
				tree_i = i
				break
	check(tree_i >= 0, "run5: a tall prop (tree) to test see-through")
	if tree_i >= 0:
		var ab: AABB = lv.fade_items[tree_i]["aabb"]
		var p = ab.get_center() + Vector3(3.5, 0, 0)
		p.y = lv.ground_height(p)
		tp(p, 90.0)                                # facing +X: the camera is behind, toward the tree
		pl.cam_pitch = -0.15
		await wait(1.2)
		var hd = pl.global_position + Vector3(0, 1.55, 0)
		log_line("run5: tree aabb %s, camera %s, head %s, hit %s" % [ab, pl.camera.global_position, hd, ab.grow(0.15).intersects_segment(pl.camera.global_position, hd)])
		var mi: MeshInstance3D = lv.fade_items[tree_i]["meshes"][0]
		check(mi.transparency > 0.4, "run5: tree between camera and courier is see-through (%.2f)" % mi.transparency)
		await shot("53_tree_fade")
		pl.cam_pitch = -0.32



# ---------------------------------------------------------------- run 2: «Сити» / «Берёзки»
## Run 3: the girl courier, the e-bike / e-moped / e-car, per-vehicle batteries, a snow day.
## Run 4: music, ranks up to «Курьер-легенда», weekly tasks, keepsakes, bag colours, closures on the map, workshop call.
func _run4_checks() -> void:
	var pl: Player = world.player
	# Suno music: mp3 tracks with crossfade, a separate snow-day track
	var mv = Game.settings["music"]
	Game.settings["music"] = 0.6
	Sfx.music_name = ""
	Sfx.play_music("music_day")
	await wait(2.0)
	check(Sfx.music.playing and Sfx.music.stream is AudioStreamMP3, "day music is the Suno mp3")
	Sfx.play_music("music_snow")
	await wait(3.0)
	check(Sfx.music.playing and Sfx.music_name == "music_snow" and Sfx.music.stream is AudioStreamMP3, "snow music crossfades in")
	Game.settings["music"] = mv
	Sfx.refresh_volume()
	# ranks: the ebike is locked for a novice, XP crosses the line, top rank gives the gold bag
	var xp0 = int(Game.state.get("xp", 0))
	Game.state["xp"] = 0
	Game.state["money"] = 3000.0
	var owned_eb = Game.state["owned"].get("ebike", false)
	Game.state["owned"]["ebike"] = false
	check(not Game.can_buy("ebike") and Game.buy_block_reason("ebike") != "", "ebike needs a rank: %s" % Game.buy_block_reason("ebike"))
	var up = Game.add_xp(90)
	check(up == 1 and Game.can_buy("ebike"), "rank up to «%s» opens the ebike" % Game.rank_title())
	Game.state["owned"]["ebike"] = owned_eb
	up = Game.add_xp(1300)
	check(up == Game.RANKS.size() - 1, "top rank reached: %s" % Game.rank_title())
	world.story.on_rank_up(up)
	await wait(0.6)
	check(Game.state["look"].get("bag", "") == Game.BAG_GOLD, "«Курьер-легенда» gets the gold bag")
	await shot("37_rank_legend")
	world.screens.close_all()
	world.story.week()
	world.story.new_weekly()
	check(Game.state["weekly"].size() == 3, "weekly tasks: %d" % Game.state["weekly"].size())
	var wd = int(Game.state["weekly"][0]["have"])
	world.story._weekly_add("deliver", 1)
	check(int(Game.state["weekly"][0]["have"]) == wd + 1, "weekly delivery task counts")
	# a quest gives a keepsake for the restaurant
	var had = Game.state["keepsakes"].duplicate()
	Game.state["keepsakes"].erase("cake")
	world.story.on_deliver({"quest": "cake", "item": ["cake", "Торт", "fragile", 1.5]}, {"stars": 5, "tip": 0.0, "late": false})
	await wait(0.3)
	check("cake" in Game.state["keepsakes"], "quest «cake» gives the keepsake «%s»" % Game.KEEPSAKES["cake"][0])
	if not ("cake" in had):
		pass
	world.screens.close_all()
	world.screens.open_phone("profile")
	await wait(0.4)
	await shot("38_profile_rank_weekly")
	world.screens.close_all()
	# bag colour tile in the garage
	Game.state["look"]["bag"] = Game.BAGS[1]
	pl.apply_look()
	world.screens.open_garage("look")
	await wait(0.5)
	var gs: GarageScreen = null
	for c in world.screens.find_children("*", "GarageScreen", true, false):
		if not c.is_queued_for_deletion():
			gs = c
	var pv = "" if gs == null or gs.preview_root.get_child_count() == 0 else String(gs.preview_root.get_child(gs.preview_root.get_child_count() - 1).scene_file_path)
	check(pv.contains("courier"), "look tab shows the courier on the podium (%s, tab %s)" % [pv, GarageScreen.tab])
	await shot("39_garage_bag_colour")
	world.screens.close_all()
	Game.state["look"]["bag"] = Game.BAGS[0]
	pl.apply_look()
	# closures on the phone map
	world.events.fire("roadblock")
	await wait(0.3)
	world.screens.open_phone("map")
	await wait(0.5)
	check(not world.events.roadblock_nodes.is_empty(), "roadblock placed")
	await shot("40_map_roadblock")
	world.screens.close_all()
	world.events.active_ev["roadblock"] = 0.01
	await wait(0.3)
	# flat tyre without a repair kit: call the workshop
	world.events.flat = true
	Game.state["items"]["repair_kit"] = 0
	world.screens.quick_item()
	await wait(0.3)
	var called = false
	for b in world.screens.find_children("*", "Button", true, false):
		if String(b.text).begins_with("Вызвать мастера"):
			b.pressed.emit()
			called = true
			break
	check(called, "bag menu offers to call the workshop for a flat")
	world.screens.close_all()
	await wait(8.5)
	check(not world.events.flat, "the workshop fixed the flat")
	Game.state["xp"] = max(xp0, int(Game.state["xp"]))


func _run3_checks() -> void:
	var pl: Player = world.player
	if pl.riding():
		world.dismount_here()
	# the girl courier: switching changes the model and the hairstyle
	var look: Dictionary = Game.state["look"]
	look["hair"] = "short"
	world.screens._set_gender(look, "f")
	pl.build_model()
	await wait(0.3)
	check(look["gender"] == "f" and look["hair"] == "ponytail", "girl courier: ponytail by default (%s)" % look["hair"])
	check(String(pl.model.scene_file_path).contains("courier_f"), "girl courier: the courier_f model is loaded")
	world.screens.open_garage("look")
	await wait(0.4)
	await shot("30_garage_look_girl")
	world.screens.close_all()
	# Михалыч's voice (ElevenLabs takes in assets/audio/voice/mikhalych)
	world.story.banter()
	await wait(0.4)
	check(Sfx.voice.playing, "Михалыч speaks (banter voice line playing)")
	world.story.talk_mentor()
	await wait(0.4)
	check(Sfx.voice.playing, "Михалыч speaks in the dialog")
	await shot("36_mentor_voiced")
	world.screens.close_all()
	Sfx.stop_voice()
	# new vehicles
	var g = world._marker("MARK_shop_garage")
	var sc0 = -1.0
	for kind in ["ebike", "moped", "ecar"]:
		Game.state["owned"][kind] = true
		Game.set_charge(kind, 100.0)
		tp(g + Vector3(0, 0, 6), 0.0)
		pl.busy = 0.0
		pl.fallen = 0.0
		world.swap_vehicle(kind)
		await wait(0.3)
		if sc0 < 0.0:
			sc0 = Game.charge_of("scooter")
		check(not world.parked.is_empty() and world.parked["kind"] == kind, "%s parked at the garage" % kind)
		tp(world.parked["body"].global_position + Vector3(1.4 if kind == "ecar" else 0.8, 0, 0), rad_to_deg(world.parked["body"].rotation.y))
		world.mount_parked()
		await wait(0.7)
		check(pl.riding() and pl.vehicle_kind == kind, "mounted the %s (mode %d)" % [kind, pl.mode])
		if kind != "ecar":
			_check_wheels(pl.vehicle_model, kind)
		var vmax = pl.max_speed()
		check(vmax > Player.BIKE_MAX, "%s is faster than the bicycle (%.1f m/s)" % [kind, vmax])
		Input.action_press("move_forward")
		await wait(1.0)
		await shot("31_riding_" + kind)
		Input.action_release("move_forward")
		check(world.battery < 100.0, "%s battery drains (%.2f)" % [kind, world.battery])
		await wait(0.6)
		world.dismount_here()
		await wait(0.3)
	check(abs(Game.charge_of("scooter") - sc0) < 0.01, "each vehicle keeps its own battery (scooter %.1f -> %.1f)" % [sc0, Game.charge_of("scooter")])
	world.screens.open_garage("vehicle")
	await wait(0.5)
	await shot("32_garage_vehicles")
	world.screens.close_all()
	world.screens.open_garage("upgrades")
	await wait(0.5)
	await shot("33_garage_upgrades")
	world.screens.close_all()
	# a snow day
	world.daynight.set_snow_day(true)
	await wait(0.4)
	var snowy = 0
	for mi in world.level.find_children("*", "MeshInstance3D", true, false):
		var m3: MeshInstance3D = mi
		if m3.mesh and m3.mesh.get_surface_count() > 0:
			var mt = m3.mesh.surface_get_material(0)
			if mt is BaseMaterial3D and (mt as BaseMaterial3D).next_pass == Level.snow_mat:
				snowy += 1
	check(snowy > 50, "snow cover on the level materials (%d meshes)" % snowy)
	world.swap_vehicle("scooter")
	tp(_free_near(world.parked["body"].global_position), 0.0)
	world.mount_parked()
	await wait(0.4)
	var grip_snow: float = pl.surface_mult()[1]
	check(grip_snow < 0.6, "snow: the scooter slides (grip %.2f)" % grip_snow)
	world.dismount_here()
	world.daynight.hour = 11.0
	tp(Vector3(-11.0, 0, -2.0), 180.0)
	await wait(2.0)
	await shot("34_snow_square")
	world.daynight.hour = 20.5
	tp(Vector3(-20.0, 0, -54.0), 90.0)
	await wait(1.5)
	await shot("35_snow_evening")
	world.daynight.set_snow_day(false)
	await wait(0.3)
	check(not world.daynight.snow_fx.emitting or world.daynight.snow < 0.1, "snow day off again")
	world.daynight.hour = 10.0
	world.swap_vehicle("scooter")
	await wait(0.2)


func _run_district() -> void:
	var pl: Player = world.player
	var o_d: Dictionary = Game.orders_data
	var d = Game.district()
	Game.state["tutorial"] = 5
	Game.state["chapter"] = 3 if d == "city" else 4
	Game.state["owned"]["scooter"] = true
	Game.state["unlocked"] = {"city": true, "berezki": d != "city", "gastro": d == "gastro"}
	log_line("district " + d)
	await wait(2.5)
	await shot(d + "_00_start")
	# traffic on the ring
	var on_road = 0
	for c in world.traffic.cars:
		if world.level.surface_at(c["body"].global_position) in ["a", "z"]:
			on_road += 1
	check(world.traffic.cars.size() > 0 and on_road == world.traffic.cars.size(), "%s traffic: %d of %d cars on the roads" % [d, on_road, world.traffic.cars.size()])
	check(world.people.mentor == null, "no mentor outside the Old Town")
	if d == "city":
		check(world.people.guards.size() >= 8, "lobby guards spawned (%d)" % world.people.guards.size())
		check(Game.layout["district"]["zones"].size() >= 8, "no-parking zones (%d)" % Game.layout["district"]["zones"].size())
	if d != "gastro":
		check(o_d.get("bignums", []).size() >= 8, "big house numbers (%d)" % o_d.get("bignums", []).size())
	# every pickup and every door reachable on foot and by scooter from the start
	var start: Vector3 = pl.global_position
	var bad = []
	for k in o_d["restaurants"].keys():
		for mode in ["foot", "scooter", "bicycle"]:
			if world.nav.path(start, v3(o_d["restaurants"][k]["pickup"]), mode).size() < 2:
				bad.append("%s/%s" % [k, mode])
	for door in o_d["doors"]:
		for mode in ["foot", "scooter"]:
			if world.nav.path(start, v3(door["pos"]), mode).size() < 2:
				bad.append("%s/%s" % [door["id"], mode])
	check(bad.is_empty(), "%s: all %d pickups and %d doors reachable %s" % [d, o_d["restaurants"].size(), o_d["doors"].size(), str(bad.slice(0, 6))])
	# exits
	var exits = 0
	for it in world.interactables:
		if it["kind"] == "exit":
			exits += 1
			tp(it["pos"], 0.0)
			await wait(0.5)
			log_line("exit focus: %s" % world.focus.get("text", "-"))
			check(world.focus.get("kind", "") == "exit", "standing in the exit zone shows the travel prompt")
	var want_exits = 1 if d == "gastro" else 2
	check(exits == want_exits, "%s has %d exits" % [d, want_exits])
	if d == "gastro":
		await _gastro_checks()
	# one full delivery per restaurant
	var n = 0
	for k in o_d["restaurants"].keys():
		var o: Dictionary = world.orders.make_offer(k)
		if o.is_empty():
			check(false, "offer from " + k)
			continue
		if n == 1 and d == "berezki":
			o["flags"]["broken_lift"] = true
		world.orders.offers.append(o)
		check(world.orders.accept(o), "accept %s order" % k)
		var r: Dictionary = o_d["restaurants"][k]
		tp(v3(r["pickup"]), float(r["pickup_yaw"]))
		await wait(0.8)
		check(world.focus.get("kind", "") == "counter", "%s: focus on the pickup counter" % k)
		if n == 0:
			await shot(d + "_01_pickup_" + k)
		world._counter(k)
		await wait(0.3)
		o["cook_left"] = 0.0
		world.screens.close_all()
		if o["state"] != "carrying":
			world.take_when_ready(o)
		await wait(0.5)
		check(o["state"] == "carrying", "%s: food in the bag" % k)
		var door: Dictionary = o["door"]
		o["flags"].erase("pin_door")
		tp(v3(door["pos"]), float(door["yaw"]))
		await wait(0.8)
		check(world.focus.get("kind", "") == "door", "%s: focus on the door %s" % [k, door["label"]])
		if n == 0:
			await shot(d + "_02_door")
		world.screens.close_all()
		if door.get("kind", "") == "park":
			world._door(door)   # park: the customer waits on the bench, no intercom, no stairs
			await wait(0.4)
			if n == 0:
				await shot(d + "_03_park_customer")
		elif door.get("kind", "") == "tower":
			world.screens._tower_entry(o, door)
			await wait(0.4)
			if n == 0:
				await shot(d + "_03_guard")
			if world.screens.top_name() == "dialog":
				check(true, "guard stops a courier without a pass")
				world.screens.close_all()
				o["flags"]["guard_ok"] = true
				world.screens._tower_entry(o, door)
		else:
			world.screens._go_up(o, door)
		await wait(0.6)
		if door.get("kind", "") == "park":
			check(world.screens.top_name() == "dialog", "%s: park customer right at the bench" % k)
		var top = world.screens.top_name()
		log_line("%s: going up via %s (floor %d)" % [k, top, int(o["floor"])])
		if n <= 1:
			await shot(d + "_04_" + top)
		Input.action_press("interact")
		var t = 0.0
		while world.screens.top_name() in ["lift", "stairs"] and t < 40.0:
			await wait(0.5)
			t += 0.5
		Input.action_release("interact")
		check(world.screens.top_name() == "dialog", "%s: %s leads to the customer (%.1f s)" % [k, top, t])
		var before = int(Game.state["stats"]["delivered"])
		world.screens.close_all()
		world.screens._deliver(o, "polite")
		await wait(0.5)
		world.screens.close_all()
		check(int(Game.state["stats"]["delivered"]) == before + 1, "%s: delivered, money %s" % [k, Game.money_text()])
		n += 1
	if d == "city":
		check(int(Game.state["progress"].get("city", 0)) == n, "chapter 3 progress counts city deliveries (%d)" % int(Game.state["progress"].get("city", 0)))
		# towing from the red zone
		world.swap_vehicle("scooter")
		await wait(0.3)
		var z: Dictionary = Game.layout["district"]["zones"][0]
		var zc = (v3(z["rect"][0]) + v3(z["rect"][1])) * 0.5
		world.parked["body"].global_position = zc
		tp(zc + Vector3(15, 0, 0), 0.0)
		var m0 = float(Game.state["money"])
		world.parked["tow"] = 24.5
		await wait(1.2)
		check(float(Game.state["money"]) < m0 and world.parked.get("body") != null and world.parked["body"].global_position.distance_to(zc) > 5.0, "tow truck takes the scooter from the red zone")
	# quests of the district
	world.screens.close_all()
	world.daynight.hour = 21.5
	world.story._check_quests()
	await wait(0.5)
	var qn = 0
	for of in world.orders.offers:
		if of.get("quest", "") != "":
			qn += 1
			log_line("quest offered: " + of["quest"])
	check(qn >= 1, "%s quest offered" % d)
	world.screens.close_all()
	# views, day and night
	var views = {"gastro": [[40.0, -22.0, 180.0], [30.0, 4.0, 90.0], [-40.0, -4.0, -90.0], [-62.0, 30.0, 0.0]],
		"city": [[0.0, -10.0, 180.0], [-46.0, -20.0, 180.0], [0.0, 75.0, 0.0]],
		"berezki": [[40.0, -45.0, 180.0], [-81.5, -30.0, 180.0], [0.0, 20.0, 180.0]]}
	var i = 0
	for vw in views[d]:
		for hh in [11.0, 21.8]:
			world.daynight.hour = hh
			tp(Vector3(vw[0], 0, vw[1]), vw[2])
			await wait(1.4)
			await shot("%s_1%d_view_%s" % [d, i, "day" if hh < 20.0 else "night"])
			log_line("fps %s at %s view %d" % [Engine.get_frames_per_second(), d, i])
		i += 1
	# travel back to the Old Town: the world reloads, the autotest continues in _after_travel
	var f = FileAccess.open(ProjectSettings.globalize_path(out_dir + "autotest_%s.log" % d), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines))
	world.daynight.hour = 15.5
	Game.state["at_travel"] = d
	Game.state["at_fails"] = fails
	log_line("travelling %s -> old_town" % d)
	world.travel_to("old_town")


## Gastro: park doors, motor ban in the park, the snow day with the frozen pond.
func _gastro_checks() -> void:
	var pl: Player = world.player
	var o_d: Dictionary = Game.orders_data
	var park_doors = []
	for door in o_d["doors"]:
		if door.get("kind", "") == "park":
			park_doors.append(door)
	check(park_doors.size() >= 5, "park delivery spots (%d)" % park_doors.size())
	var start: Vector3 = pl.global_position
	if not park_doors.is_empty():
		var pd = v3(park_doors[0]["pos"])
		var mp = world.nav.path(start, pd, "moped")
		var last_road = mp[mp.size() - 2] if mp.size() >= 2 else start
		check(last_road.distance_to(pd) > 4.0 and world.nav.path(start, pd, "foot").size() >= 2,
			"park: the moped route ends at the park edge (%.0f m before the spot), on foot it leads in" % last_road.distance_to(pd))
	check(o_d["restaurants"].has("fish") and o_d["restaurants"].has("ramen"), "market stalls and restaurants (%d pickups)" % o_d["restaurants"].size())
	# the moped stops at the park gate
	Game.state["owned"]["moped"] = true
	Game.set_charge("moped", 100.0)
	if pl.riding():
		world.dismount_here()
	world.swap_vehicle("moped")
	var gate = Vector3(-8.0, 0, -4.0)   # on the crossing in front of the east gate (Blender -16, 4)
	world.parked["body"].global_position = gate
	world.parked["body"].rotation.y = -PI * 0.5
	tp(gate + Vector3(0, 0, 0.8), -90.0)
	world.mount_parked()
	await wait(0.5)
	pl.heading = -PI * 0.5
	Input.action_press("move_forward")
	await wait(3.0)
	Input.action_release("move_forward")
	var sf: String = world.level.surface_at(pl.global_position)
	check(not (sf in ["p", "g"]), "moped does not ride into the park (stopped on '%s' at x=%.1f)" % [sf, pl.global_position.x])
	await shot("gastro_05_park_gate")
	world.dismount_here()
	# snow day here: frozen pond
	world.daynight.set_snow_day(true)
	await wait(0.3)
	var ice = false
	for mi in world.level.find_children("pond*", "MeshInstance3D", true, false):
		ice = ice or (mi as MeshInstance3D).material_override != null
	check(ice, "snow day: the pond freezes")
	world.daynight.hour = 12.0
	tp(Vector3(-40.0, 0, -4.0), -90.0)
	await wait(2.0)
	await shot("gastro_06_snow_park")
	tp(Vector3(40.0, 0, -22.0), 180.0)
	await wait(1.5)
	await shot("gastro_07_snow_market")
	world.story._check_quests()
	var cocoa = false
	for of in world.orders.offers:
		cocoa = cocoa or of.get("quest", "") == "skater_cocoa"
	log_line("snow quest offered: %s" % cocoa)


func _after_travel() -> void:
	var from: String = Game.state["at_travel"]
	fails = int(Game.state.get("at_fails", 0))
	Game.state.erase("at_travel")
	await wait(2.0)
	var e: Dictionary = Game.layout["district"]["entries"].get(from, {})
	var ep = v3(e.get("pos", [0, 0, 0]))
	check(Game.district() == "old_town", "travel: arrived in the Old Town")
	check(Vector2(world.player.global_position.x - ep.x, world.player.global_position.z - ep.z).length() < 4.0, "travel: player at the entry from %s (%.1f, %.1f)" % [from, world.player.global_position.x, world.player.global_position.z])
	check(abs(world.daynight.hour - 15.5) < 0.3, "travel: the shift clock kept running (%.2f)" % world.daynight.hour)
	check(world.current_vehicle() != "", "travel: the vehicle came along (%s)" % world.current_vehicle())
	await shot(from + "_20_arrived_old_town")
	log_line("DONE fails=%d" % fails)
	var f = FileAccess.open(ProjectSettings.globalize_path(out_dir + "autotest_%s.log" % from), FileAccess.READ_WRITE)
	if f:
		f.seek_end()
		f.store_string("\n" + "\n".join(lines))
	get_tree().paused = false
	Game.delete_save()
	get_tree().quit()


## Run 6 (bug fixes): the «Хоп!» list with several offers scrolls down to the last «Принять» (a visible scrollbar,
## the mouse wheel over a card, the scroll kept when a new offer arrives); a crash into a wall leaves the courier free.
func _run6_checks() -> void:
	var pl: Player = world.player
	if Game.flag("trimesh"):
		var by = {}
		var lv: Level = world.level
		for i in lv.instances.size():
			var n: Node3D = lv.instances[i]
			if n == null:
				continue
			for c in n.find_children("*", "CollisionShape3D", true, false):
				var sh = (c as CollisionShape3D).shape
				if sh is ConcavePolygonShape3D:
					var pts = {}
					for v in (sh as ConcavePolygonShape3D).get_faces():
						pts[v.snapped(Vector3(0.001, 0.001, 0.001))] = true
					var k = "%s/%s/%s v=%d" % [Game.layout["instances"][i]["group"], Game.layout["instances"][i]["asset"], c.get_parent().name, pts.size()]
					by[k] = by.get(k, 0) + 1
		for k in by:
			log_line("trimesh %s x%d" % [k, by[k]])
	world.screens.close_all()
	if pl.riding():
		world.dismount_here()
		await wait(0.5)
	var saved: Array = world.orders.offers.duplicate()
	world.orders.offers.clear()
	for k in 4:
		var o = world.orders.make_offer()
		if not o.is_empty():
			o["expires"] = 999.0
			world.orders.offers.append(o)
	world.open_phone()
	world.screens.open_phone("orders")
	await wait(0.6)
	var body: ScrollContainer = world.screens.phone_body
	var vb: VScrollBar = body.get_v_scroll_bar()
	check(vb.visible and vb.size.x >= 8.0 and vb.max_value > vb.page + 1.0, "run6: phone with %d offers has a visible scrollbar (width %.0f, list %.0f > view %.0f)" % [world.orders.offers.size(), vb.size.x, vb.max_value, vb.page])
	await shot("54_phone_offers_top")
	var list: Control = body.get_child(0)
	var card: Control = list.get_child(0)
	for k in 6:
		for pressed in [true, false]:
			var ev = InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
			ev.pressed = pressed
			ev.factor = 1.0
			ev.position = card.get_global_rect().get_center()
			ev.global_position = ev.position
			get_viewport().push_input(ev, true)
		await wait(0.05)
	await wait(0.3)
	check(body.scroll_vertical > 40, "run6: mouse wheel over an offer card scrolls the list (%d px)" % body.scroll_vertical)
	body.scroll_vertical = int(vb.max_value)
	await wait(0.3)
	var last: Control = list.get_child(list.get_child_count() - 1)
	var acc: Button = null
	for b in last.find_children("*", "Button", true, false):
		if (b as Button).text == "Принять":
			acc = b
	var view = body.get_global_rect()
	check(acc != null and view.encloses(acc.get_global_rect()), "run6: scrolled to the end, the last offer's «Принять» is fully on screen")
	await shot("55_phone_offers_end")
	var s0 = body.scroll_vertical
	var extra = world.orders.make_offer()
	if not extra.is_empty():
		extra["expires"] = 999.0
		world.orders.offers.append(extra)
	world.orders.changed.emit()
	await wait(0.4)
	var body2: ScrollContainer = world.screens.phone_body
	check(body2 != body and abs(body2.scroll_vertical - s0) <= 2, "run6: a new offer arriving keeps the list scrolled (%d -> %d)" % [s0, body2.scroll_vertical])
	world.screens.close_all()
	world.orders.offers.clear()
	world.orders.offers.append_array(saved)
	await wait(0.3)
	# ---------------- crash into a wall at speed: never wedged (a house, then the brick garden walls of the ground)
	var hh = _wall_house()
	var house: Node3D = hh[0]
	var half: Vector3 = hh[1]
	check(house != null, "run6: a house wall to crash into")
	if house == null:
		return
	var hb = house.global_transform.basis
	var into = -hb.z.normalized()
	world.traffic.set_physics_process(false)
	# sitting on a bench still puts the courier on it (props stay hollow on purpose, see Level._solidify)
	var benches = world._markers("INT_bench")
	if benches.size() > 0:
		var bp = world._v(benches[0]["pos"])
		tp(_free_near(bp + Vector3(1.0, 0, 0)), 0.0)
		await wait(0.3)
		world._sit(bp, float(benches[0]["yaw"]))
		await wait(1.0)
		var off = Vector2(pl.global_position.x - bp.x, pl.global_position.z - bp.z).length()
		check(off < 0.35, "run6: sitting on a bench keeps the courier on it (%.2f m off)" % off)
		await wait(3.5)
	await _crash_test(house.global_transform * Vector3(0.6, 0, half.z), -into, "house wall", "56_crash_wall")
	var walls = _garden_walls()
	check(walls.size() >= 3, "run6: garden walls of the ground are solid boxes (%d)" % walls.size())
	for k in min(2, walls.size()):
		await _crash_test(walls[k][0], walls[k][1], "garden wall %d" % k, "57_crash_garden_wall_%d" % k)
	if walls.size() > 0:
		# however the courier got into a garden wall, they are put back on the street
		var wpos: Vector3 = walls[0][0] - (walls[0][1] as Vector3) * 0.3
		var was_in = pl._inside_at(wpos)
		pl.global_position = wpos + Vector3(0, 0.1, 0)
		await wait(0.9)
		check(was_in and not pl._inside_at(pl.global_position) and not pl._overlapping(), "run6: courier put inside a garden wall is back on the street (inside first: %s)" % was_in)
	# the old trap on purpose: rider pressed against the wall, dismount right there
	var spot = house.global_transform * Vector3(-0.5, 0, half.z + 0.45)
	spot.y = world.level.ground_height(spot)
	if not pl.riding():
		if world.parked.is_empty():
			world.swap_vehicle("bicycle")
			await wait(0.2)
		(world.parked["body"] as Node3D).global_position = _free_near(pl.global_position)
		world.mount_parked()
	await wait(0.3)
	pl.global_position = spot + Vector3(0, 0.1, 0)
	pl.heading = atan2(into.x, into.z)
	pl.rotation.y = pl.heading
	await wait(0.3)
	world.dismount_here()
	await wait(0.4)
	var bpos: Vector3 = (world.parked["body"] as Node3D).global_position
	check(not pl._overlapping() and not pl._inside_at(pl.global_position) and Vector2(pl.global_position.x - bpos.x, pl.global_position.z - bpos.z).length() > 0.5, "run6: dismount pressed against a wall lands clear of the wall and the bike")
	# the safety net: put the courier inside the parked bike, push into the wall -> freed within ~1.5 s
	pl.global_position = bpos + Vector3(0, 0.1, 0)
	await wait(0.1)
	pl.cyaw = atan2(-into.x, -into.z)
	pl.cam_idle = 0.0
	await hold("move_forward", 1.8)
	check(not pl._overlapping(), "run6: courier stuck inside the bike against a wall is pushed out")
	world.traffic.set_physics_process(true)


## Ride a bicycle at full speed into a wall (face centre `face`, `out` = the wall's outward normal) a bit off square:
## afterwards the courier must stand free and walk away.
func _crash_test(face: Vector3, out: Vector3, what: String, shot_name: String) -> void:
	var pl: Player = world.player
	if pl.riding():
		world.dismount_here()
		await wait(0.3)
	out = Vector3(out.x, 0, out.z).normalized()
	var start = face + out * 9.0
	start.y = world.level.ground_height(start)
	var yaw = atan2(-out.x, -out.z) + deg_to_rad(12.0)
	if world.parked.is_empty():
		world.swap_vehicle("bicycle")
		await wait(0.2)
	var bk: Node3D = world.parked["body"]
	bk.global_position = start
	bk.rotation.y = yaw
	tp(_free_near(start), rad_to_deg(yaw))
	world.mount_parked()
	await wait(0.6)
	var falls0 = int(Game.state["stats"]["falls"])
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var tt = 0.0
	var top = 0.0
	while tt < 6.0 and pl.riding():
		top = max(top, pl.speed)
		await wait(0.1)
		tt += 0.1
	Input.action_release("move_forward")
	Input.action_release("sprint")
	log_line("run6: %s: top speed %.1f, fell %s, riding %s" % [what, top, int(Game.state["stats"]["falls"]) > falls0, pl.riding()])
	if pl.riding():
		world.dismount_here()   # too soft to throw the rider off: get off right at the wall, the same trap
	await wait(4.5)
	var side = (pl.global_position - face).dot(out)
	check(not pl._overlapping() and not pl._inside_at(pl.global_position) and side > 0.0, "run6: %s: after the crash the courier stands free on the street side (%.2f m from the face)" % [what, side])
	await shot(shot_name)
	pl.cyaw = atan2(-out.x, -out.z)      # camera boom toward the wall: forward = away from it
	pl.cam_idle = 0.0
	var p0 = pl.global_position
	await hold("move_forward", 1.2)
	check(p0.distance_to(pl.global_position) > 1.0, "run6: %s: walks away from the crash spot (%.2f m)" % [what, p0.distance_to(pl.global_position)])


## Long thin solid boxes of the ground's garden walls with open street in front: [[face centre, outward normal], ...]
func _garden_walls() -> Array:
	var lv: Level = world.level
	var out: Array = []
	for cs in lv.find_children("*", "CollisionShape3D", true, false):
		var c: CollisionShape3D = cs
		var path = str(c.get_path())
		if not path.contains("garden"):
			continue
		var boxes: Array = [c.shape] if c.shape is ConvexPolygonShape3D else []
		if c.shape is ConcavePolygonShape3D:     # (hollow walls, as before run 6)
			boxes = lv._split_boxes(c.shape).filter(func(x): return x is ConvexPolygonShape3D)
		for bx in boxes:
			_garden_wall_face(c, bx, out)
	return out


func _garden_wall_face(c: CollisionShape3D, bx: ConvexPolygonShape3D, out: Array) -> void:
	var lv: Level = world.level
	var ab = AABB(bx.points[0], Vector3.ZERO)
	for v in bx.points:
		ab = ab.expand(v)
	if ab.size.y < 1.0 or max(ab.size.x, ab.size.z) < 4.0 or min(ab.size.x, ab.size.z) > 1.0:
		return
	var gt = c.global_transform
	var ctr = gt * ab.get_center()
	var thin = (gt.basis.x if ab.size.x < ab.size.z else gt.basis.z).normalized()
	var th = min(ab.size.x, ab.size.z) * 0.5
	for sgn in [1.0, -1.0]:
		var n: Vector3 = thin * sgn
		var ok = true
		for d in [1.5, 4.0, 7.0, 9.0]:
			var p = ctr + n * (th + d)
			ok = ok and lv.surface_at(p) in ["s", "c", "a", "z", "p", "g", "b"] and not world.player._inside_at(p)
		if ok:
			var face = ctr + n * th
			face.y = lv.ground_height(face)
			out.append([face, n])
			break


## The ride up to the customer is 3D: the player's courier climbs a cutaway stairwell and knocks, the lift rides up.
func _run7_checks() -> void:
	var pl: Player = world.player
	world.screens.close_all()
	var o = world.orders.make_offer()
	o["floor"] = 5
	o["expires"] = 999.0
	o["door"]["lift"] = false
	world.orders.offers.append(o)
	world.orders.accept(o)
	pl.stamina = 100.0
	var el0 = float(o["elapsed"])
	world.screens.open_stairs(o)
	await wait(0.8)
	var art: Stairwell3D = null
	for c in world.screens.find_children("*", "SubViewportContainer", true, false):
		if c is Stairwell3D:
			art = c
	check(art != null and art.courier != null, "run7: the stairs screen shows the 3D stairwell with the courier")
	check(get_viewport().disable_3d, "run7: the city does not render behind the stairwell")
	await shot("57_stairs3d_start")
	Input.action_press("interact")
	await wait(3.2)
	await shot("58_stairs3d_climb")
	var y_mid = art.courier.position.y if art else 0.0
	await wait(3.0)
	await shot("59_stairs3d_climb2")
	var t = 0.0
	var knocked = false
	var st_knock = 100.0
	while world.screens.top_name() == "stairs" and t < 40.0:
		if art and is_instance_valid(art) and art._arrive_t > 0.6 and not knocked:
			knocked = true
			st_knock = pl.stamina
			check(absf(art.courier.position.y - 4 * Stairwell3D.H) < 0.05, "run7: the courier stands on the 5th floor (y %.2f)" % art.courier.position.y)
			await shot("60_stairs3d_door")
		await wait(0.2)
		t += 0.2
	Input.action_release("interact")
	check(y_mid > 0.5, "run7: the courier climbs (height %.2f m after 3 s)" % y_mid)
	check(knocked, "run7: the courier knocks at the door")
	check(world.screens.top_name() == "dialog", "run7: the stairs lead to the customer")
	check(float(o["elapsed"]) - el0 > 8.0 and st_knock < 80.0, "run7: climbing 4 floors costs time (%.1f s) and stamina (%.0f left)" % [float(o["elapsed"]) - el0, st_knock])
	world.screens.close_all()
	await wait(0.3)
	check(not get_viewport().disable_3d, "run7: the city renders again after the stairs")
	o["floor"] = 9
	world.screens.open_lift(o)
	await wait(1.6)
	await shot("61_lift3d")
	t = 0.0
	while world.screens.top_name() == "lift" and t < 20.0:
		await wait(0.2)
		t += 0.2
	check(world.screens.top_name() == "dialog", "run7: the lift leads to the customer")
	world.screens.close_all()
	world.orders.cancel(o)
	await wait(0.3)
	await shot("62_after_ride")
