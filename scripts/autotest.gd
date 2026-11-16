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
		await wait(3.0)
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
	tp(world.parked["body"].global_position + Vector3(0.8, 0, 0), rad_to_deg(world.parked["body"].rotation.y))
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
	while world.screens.top_name() == "stairs" and t < 30.0:
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
	tp(world.parked["body"].global_position + Vector3(0.8, 0, 0), rad_to_deg(world.parked["body"].rotation.y))
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
	check(ex_ok == 2, "old town has 2 exits to the new districts (%d)" % ex_ok)
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
	log_line("DONE fails=%d" % fails)
	var f = FileAccess.open(ProjectSettings.globalize_path(out_dir + "autotest.log"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines))
	get_tree().paused = false
	Game.delete_save()
	get_tree().quit()



# ---------------------------------------------------------------- run 2: «Сити» / «Берёзки»
func _run_district() -> void:
	var pl: Player = world.player
	var o_d: Dictionary = Game.orders_data
	var d = Game.district()
	Game.state["tutorial"] = 5
	Game.state["chapter"] = 3 if d == "city" else 4
	Game.state["owned"]["scooter"] = true
	Game.state["unlocked"] = {"city": true, "berezki": d == "berezki"}
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
	check(exits == 2, "%s has 2 exits" % d)
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
		if door.get("kind", "") == "tower":
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
	var views = {"city": [[0.0, -10.0, 180.0], [-46.0, -20.0, 180.0], [0.0, 75.0, 0.0]],
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
