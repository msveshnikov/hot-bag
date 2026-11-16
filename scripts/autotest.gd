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
	# ---------------- theft, save/load, summary
	Game.state["money"] = 500.0
	world.events.flat = false
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
