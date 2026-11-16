extends Node3D
## The game world: level + systems + interactions + UI flow. Built entirely at runtime from Task 3/4 JSON.

const INTERACT_R = 2.3

var started = false
var level: Level
var daynight: DayNight
var nav: Nav
var player: Player
var people: People
var traffic: Traffic
var orders: Orders
var events: Events
var story: Story
var fx: Node3D
var ui: CanvasLayer
var hud: Hud
var screens: Screens
var touch: CanvasLayer

var battery = 100.0
var parked = {}             # {kind, node, locked, since}
var interactables: Array = []
var focus = {}
var charging = false
var gps_line: MeshInstance3D
var gps_pin: Node3D
var gps_target = {}
var _gps_t = 0.0
var _gps_path = PackedVector3Array()
var warned_rating = false
var shift_ending = false


func _ready() -> void:
	Game.load_level_data()
	battery = float(Game.state.get("battery", 100.0))
	level = Level.new()
	level.name = "Level"
	add_child(level)
	level.build(Game.layout)
	nav = Nav.new(level)
	daynight = DayNight.new()
	add_child(daynight)
	daynight.setup(level, Game.layout["lighting"])
	daynight.shift_over.connect(_on_shift_over)
	daynight.hour_changed.connect(_on_hour)
	orders = Orders.new()
	add_child(orders)
	orders.setup(self)
	level.add_plates(Game.orders_data["doors"])
	events = Events.new()
	add_child(events)
	events.setup(self)
	story = Story.new()
	add_child(story)
	story.setup(self)
	player = Player.new()
	player.name = "Player"
	add_child(player)
	var ps: Dictionary = Game.population["player"]
	var start = Vector3(ps["pos"][0], ps["pos"][1], ps["pos"][2])
	player.setup(self, start, float(ps["yaw"]))
	daynight.follow = player
	people = People.new()
	add_child(people)
	people.setup(self)
	traffic = Traffic.new()
	add_child(traffic)
	traffic.setup(self)
	fx = Fx.new()
	add_child(fx)
	fx.setup(self)
	_make_gps()
	_park_start_vehicle(start)
	_build_interactables()
	ui = CanvasLayer.new()
	ui.layer = 10
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	hud = Hud.new()
	hud.world = self
	ui.add_child(hud)
	screens = Screens.new()
	screens.world = self
	ui.add_child(screens)
	if Game.is_touch():
		touch = load("res://scripts/ui/touch_controls.gd").new()
		touch.world = self
		add_child(touch)
	orders.changed.connect(func(): hud.refresh_orders())
	started = true
	Sfx.play_music("music_day")
	Sfx.set_loop("city_loop", 0.35)
	_capture_mouse()
	story.start_day()
	story.resume_quests()
	if Game.flag("autotest"):
		var at = load("res://scripts/autotest.gd").new()
		at.world = self
		add_child(at)
	elif Game.flag("tour"):
		var tt = load("res://scripts/shot_tour.gd").new()
		tt.world = self
		add_child(tt)


func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


# ---------------------------------------------------------------- vehicles
func _park_start_vehicle(start: Vector3) -> void:
	var kind: String = Game.state.get("vehicle", "bicycle")
	if kind == "scooter" and not (Game.state["owned"].get("scooter", false) or Game.state.get("rented_today", false)):
		kind = "bicycle"
	var side = Vector3(cos(player.heading), 0, -sin(player.heading))
	park_vehicle(kind, Vehicles.make(kind), start + side * 1.4, player.heading)


func park_vehicle(kind: String, node: Node3D, pos: Vector3, yaw: float) -> void:
	var body = StaticBody3D.new()
	body.collision_layer = 1
	var cs = CollisionShape3D.new()
	var bx = BoxShape3D.new()
	bx.size = Vector3(0.5, 1.0, 1.5)
	cs.shape = bx
	cs.position.y = 0.5
	body.add_child(cs)
	body.add_child(node)
	node.transform = Transform3D.IDENTITY
	add_child(body)
	body.global_position = Vector3(pos.x, level.ground_height(pos), pos.z)
	body.rotation.y = yaw
	Vehicles.apply_upgrades(node, kind)
	parked = {"kind": kind, "node": node, "body": body, "locked": false, "since": 0.0}


func mount_parked() -> void:
	if parked.is_empty() or player.riding() or player.busy > 0.0:
		return
	if parked["body"].global_position.distance_to(player.global_position) > 2.6:
		toast("Транспорт далеко. Подойди ближе.", 1.5)
		return
	if parked["locked"]:
		parked["locked"] = false
		Sfx.play("lock")
	var node: Node3D = parked["node"]
	var body: StaticBody3D = parked["body"]
	player.global_position = Vector3(body.global_position.x, player.global_position.y, body.global_position.z)
	player.heading = body.rotation.y
	body.remove_child(node)
	body.queue_free()
	player.mount(parked["kind"], node)
	Game.state["vehicle"] = parked["kind"]
	parked = {}
	charging = false


func dismount_here() -> void:
	if not player.riding():
		return
	var kind = player.vehicle_kind
	var pos = player.global_position
	var yaw = player.heading
	var node = player.dismount()
	park_vehicle(kind, node, pos, yaw)
	Sfx.set_loop("motor_loop", 0.0)
	Sfx.set_loop("pedal_loop", 0.0)


func toggle_lock() -> void:
	if parked.is_empty() or parked["body"].global_position.distance_to(player.global_position) > 3.0:
		return
	if Game.upgrade_level("lock") == 0:
		toast("Замка нет. Купи в мастерской (40 монет).", 2.0)
		return
	parked["locked"] = not parked["locked"]
	Sfx.play("lock")
	toast("Транспорт пристёгнут 🔒" if parked["locked"] else "Замок снят", 1.4)


func on_fall() -> void:
	if player.riding():
		dismount_here()
	orders.damage_food(18.0, "crash")


func drain_battery(dist: float) -> void:
	var cap = 1.0 + 0.4 * Game.upgrade_level("battery")
	battery = max(0.0, battery - dist * 0.055 / cap)
	if battery < 15.0:
		player.hint("battery", "Батарея самоката садится! Зарядная станция — у кафе курьеров.")
	if battery <= 0.0:
		player.hint("battery0", "Самокат разряжен. Толкай до зарядки или используй павербанк (X).", 12.0)


func vehicle_stolen(node: Node3D) -> void:
	if not parked.is_empty() and parked["node"] == node:
		var body: StaticBody3D = parked["body"]
		body.remove_child(node)
		body.queue_free()
		parked = {}
	banner("Угон!", "Вор уезжает на твоём транспорте! Догони его, пока не скрылся!")
	Sfx.play("whistle", 0.6)


func vehicle_returned(node: Node3D, kind: String, caught: bool, pos: Vector3) -> void:
	if caught:
		park_vehicle(kind, node, pos, 0.0)
		banner("Пойман!", "Вор бросил транспорт и убежал. Купи замок, чтобы такого не было (L — пристегнуть).")
	else:
		var g = _marker("MARK_shop_garage")
		park_vehicle(kind, node, g + Vector3(2.5, 0, 1.5), 0.0)
		Game.spend(25.0)
		banner("Транспорт нашёлся", "Полиция вернула его в мастерскую. Штрафстоянка −25 монет.")


func _marker(name: String) -> Vector3:
	for m in Game.layout["markers"]:
		if m["name"] == name:
			return _v(m["pos"])
	return Vector3.ZERO


func _markers(name: String) -> Array:
	return Game.layout["markers"].filter(func(m): return m["name"] == name)


# ---------------------------------------------------------------- interactables
func _build_interactables() -> void:
	for k in Game.orders_data["restaurants"].keys():
		var r: Dictionary = Game.orders_data["restaurants"][k]
		var rest: String = k
		interactables.append({"pos": _v(r["pickup"]), "r": 2.4, "kind": "counter",
			"label": func(): return "Забрать заказ — " + r["name"] if not orders.for_restaurant(rest).is_empty() else "",
			"cb": func(): _counter(rest)})
	for d in Game.orders_data["doors"]:
		var door: Dictionary = d
		interactables.append({"pos": _v(door["pos"]), "r": 2.2, "kind": "door",
			"label": func(): return ("Доставить: " + door["label"]) if not _orders_for_door(door).is_empty() else "",
			"cb": func(): _door(door)})
	interactables.append({"pos": people.mentor.position, "r": 2.8, "kind": "mentor",
		"label": func(): return "Поговорить с Михалычем", "cb": func(): story.talk_mentor()})
	for m in _markers("MARK_charger"):
		interactables.append({"pos": _v(m["pos"]), "r": 2.6, "kind": "charger",
			"label": func(): return ("Зарядить самокат (%d%%)" % int(battery)) if _scooter_near(_v(m["pos"])) else "",
			"cb": func(): _start_charge(_v(m["pos"]))})
	interactables.append({"pos": _marker("MARK_shop_garage"), "r": 2.8, "kind": "garage",
		"label": func(): return "Мастерская: транспорт, улучшения, внешность", "cb": func(): screens.open_garage()})
	interactables.append({"pos": _marker("MARK_shop_kiosk"), "r": 2.6, "kind": "kiosk",
		"label": func(): return "Ларёк: перекус, энергетик, павербанк", "cb": func(): screens.open_kiosk()})
	interactables.append({"pos": _marker("MARK_shop_cafe"), "r": 2.6, "kind": "cafe",
		"label": func(): return "Кафе курьеров: кофе, зарядка телефона", "cb": func(): screens.open_cafe()})
	for m in _markers("INT_bench"):
		var bp = _v(m["pos"])
		interactables.append({"pos": bp, "r": 1.8, "kind": "bench",
			"label": func(): return "Посидеть на скамейке (отдых)" if not player.riding() else "", "cb": func(): _sit(bp, float(m["yaw"]))})


func _orders_for_door(door: Dictionary) -> Array:
	var out = []
	for o in orders.active:
		if o["state"] != "carrying":
			continue
		var pin: Dictionary = o["flags"].get("pin_door", {})
		if o["door"]["id"] == door["id"] and pin.is_empty():
			out.append(o)
		elif not pin.is_empty() and (pin["id"] == door["id"] or o["door"]["id"] == door["id"]):
			out.append(o)
	return out


func _scooter_near(p: Vector3) -> bool:
	if player.mode == Player.Mode.SCOOTER and player.global_position.distance_to(p) < 3.0:
		return true
	return not parked.is_empty() and parked["kind"] == "scooter" and parked["body"].global_position.distance_to(p) < 3.5


func _process(delta: float) -> void:
	if not started:
		return
	_update_focus()
	if not parked.is_empty():
		parked["since"] += delta
		_theft_check()
	if charging:
		if not _scooter_near_any():
			charging = false
		else:
			battery = min(100.0, battery + 9.0 * delta)
			if battery >= 100.0:
				charging = false
				toast("Самокат заряжен на 100%!", 1.5)
	_gps_t -= delta
	if _gps_t <= 0.0:
		_gps_t = 0.7
		_update_gps()
	if gps_pin and gps_pin.visible:
		gps_pin.get_child(0).position.y = 3.2 + sin(Time.get_ticks_msec() / 250.0) * 0.3
	Game.state["battery"] = battery
	if player.mode == Player.Mode.SCOOTER or player.mode == Player.Mode.BIKE:
		Vehicles.lights(player.vehicle_model, daynight.is_dark() and (player.mode == Player.Mode.BIKE or Game.upgrade_level("headlight") > 0))
	var r = float(Game.state["rating"])
	if r < 3.0 and not warned_rating:
		warned_rating = true
		banner("Предупреждение", "Рейтинг ниже 3,0! Ещё немного — и приложение заблокирует аккаунт.")
	if r < 2.5 and not shift_ending:
		shift_ending = true
		screens.open_blocked()


func _scooter_near_any() -> bool:
	for m in _markers("MARK_charger"):
		if _scooter_near(_v(m["pos"])):
			return true
	return false


func _theft_check() -> void:
	if parked["locked"] or int(Game.state["chapter"]) < 2 or not people.thief.is_empty():
		return
	if float(parked["since"]) < 30.0:
		return
	var d: float = parked["body"].global_position.distance_to(player.global_position)
	if d > 14.0 and randf() < 0.0025:
		people.steal(parked["node"], parked["kind"])


func _update_focus() -> void:
	var best = {}
	var bd = 1e9
	var pp = player.global_position
	for it in interactables:
		var d: float = Vector2(it["pos"].x - pp.x, it["pos"].z - pp.z).length()
		if d > float(it["r"]) or abs(it["pos"].y - pp.y) > 2.5:
			continue
		var lbl: String = it["label"].call()
		if lbl == "":
			continue
		if d < bd:
			bd = d
			best = it.duplicate()
			best["text"] = lbl
	if best.is_empty() and not parked.is_empty() and not player.riding():
		if parked["body"].global_position.distance_to(pp) < 2.6:
			best = {"kind": "vehicle", "text": ("Сесть на %s (F)" % ("велосипед" if parked["kind"] == "bicycle" else "самокат")) + ("  ·  L — снять замок" if parked["locked"] else ("  ·  L — пристегнуть" if Game.upgrade_level("lock") > 0 else "")), "cb": func(): mount_parked()}
	focus = best


func _unhandled_input(event: InputEvent) -> void:
	if not started:
		return
	if event.is_action_pressed("pause"):
		if not ui_free():
			screens.close_top()
		else:
			screens.open_pause()
		get_viewport().set_input_as_handled()
		return
	if not ui_free():
		return
	if event.is_action_pressed("phone"):
		open_phone()
	elif event.is_action_pressed("interact"):
		if not focus.is_empty() and player.busy <= 0.0:
			focus["cb"].call()
	elif event.is_action_pressed("mount"):
		if player.riding():
			dismount_here()
		else:
			mount_parked()
	elif event.is_action_pressed("lock"):
		toggle_lock()
	elif event.is_action_pressed("bell"):
		if player.riding():
			Sfx.play("bell" if player.mode == Player.Mode.BIKE else "horn", 0.7)
	elif event.is_action_pressed("use_item"):
		screens.quick_item()
	elif event.is_action_pressed("call"):
		call_customer()
	elif event.is_action_pressed("cam_reset"):
		player.reset_camera()
	elif event is InputEventMouseButton and event.pressed and not Game.is_touch():
		_capture_mouse()


func _capture_mouse() -> void:
	if Game.is_touch() or Game.flag("autotest") or Game.flag("tour"):
		return
	if ui_free():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func release_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func ui_free() -> bool:
	return screens == null or screens.stack.is_empty()


func ui_phone_open() -> bool:
	return screens != null and screens.top_name() == "phone"


func open_phone() -> void:
	if player.phone <= 0.0:
		toast("Телефон сел! Павербанк (X) или зарядка в кафе.", 2.0)
		return
	Sfx.play("phone_open")
	screens.open_phone()
	if story.step() == 0:
		pass


func toast(text: String, secs = 2.5) -> void:
	if hud:
		hud.toast(text, secs)


func banner(title: String, text: String) -> void:
	if hud:
		hud.banner(title, text)


func dialog(who: String, text: String, options: Array) -> void:
	screens.open_dialog(who, text, options)


# ---------------------------------------------------------------- restaurant counter
func _counter(rest: String) -> void:
	if player.riding():
		dismount_here()
	var list = orders.for_restaurant(rest)
	if list.is_empty():
		return
	var o: Dictionary = list[0]
	var cook = people.cook_for(rest)
	if cook:
		Chars.play(cook, "talk")
	if float(o["cook_left"]) > 0.5:
		o["state"] = "waiting"
		screens.open_wait(o)
		return
	_take(o)


func _take(o: Dictionary) -> void:
	player._play("pickup_bag", true)
	player.busy = 0.9
	var cook = people.cook_for(o["rest"])
	if cook:
		Chars.play(cook, "hand_over")
		get_tree().create_timer(1.2).timeout.connect(func(): if is_instance_valid(cook): Chars.play(cook, "cook_idle"))
	orders.pickup(o)


func take_when_ready(o: Dictionary) -> void:
	_take(o)


# ---------------------------------------------------------------- doors
func _door(door: Dictionary) -> void:
	if player.riding():
		dismount_here()
	var list = _orders_for_door(door)
	if list.is_empty():
		return
	var o: Dictionary = list[0]
	var pin: Dictionary = o["flags"].get("pin_door", {})
	if not pin.is_empty() and pin["id"] == door["id"]:
		Sfx.play("intercom")
		dialog("Домофон", "— Алло? Какой ещё заказ? Мы ничего не заказывали! (Похоже, метка в приложении стоит не там.)", [
			["Позвонить клиенту (C)", func(): call_customer()],
			["Ой, извините", func(): pass],
		])
		return
	screens.open_door(o, door)


func call_customer() -> void:
	var tgt = orders.gps_target()
	if tgt.is_empty() or tgt["kind"] != "door":
		toast("Звонить пока некому — сначала забери заказ.", 1.6)
		return
	var o: Dictionary = tgt["order"]
	o["flags"]["called"] = true
	Sfx.play("ring")
	var cust: Dictionary = o["customer"]
	var pin: Dictionary = o["flags"].get("pin_door", {})
	if not pin.is_empty():
		o["flags"].erase("pin_door")
		dialog(cust.get("name", "Клиент"), "— Ой, метка съехала! Я в доме %d, подъезд %d. Жду!" % [int(o["door"]["number"]), int(o["door"]["entrance"])], [["Еду!", func(): refresh_gps()]])
		return
	if o["flags"].get("no_answer") and not o["flags"].get("answered"):
		if randf() < 0.5:
			toast("Гудки... клиент не отвечает. Попробуй ещё раз или подожди у двери.", 2.5)
			return
		o["flags"]["answered"] = true
	var t: String = cust.get("trait", "polite")
	var line = "— Да-да, я дома! Звоните в домофон."
	if t == "no_call":
		line = "— Я же просил не звонить!.. Ладно, жду."
	elif t == "leave_at_door":
		line = "— Оставьте, пожалуйста, у двери. Спасибо!"
	if o["flags"].get("intercom"):
		o["flags"]["intercom_fixed"] = true
		line = "— Домофон сломан, сейчас открою дверь подъезда!"
	dialog(cust.get("name", "Клиент"), line, [["Понял", func(): pass]])


# ---------------------------------------------------------------- misc interactions
func _start_charge(_p: Vector3) -> void:
	charging = true
	Sfx.play("ui")
	toast("Зарядка... стой рядом со станцией (+9%/с).", 2.0)


func _sit(p: Vector3, yaw: float) -> void:
	player.global_position = Vector3(p.x, player.global_position.y, p.z)
	player.heading = deg_to_rad(yaw + 180.0)
	player._play("sit", true)
	player.busy = 4.0
	var tw = create_tween()
	tw.tween_property(player, "stamina", 100.0, 4.0)
	toast("Курьер отдыхает...", 2.0)


# ---------------------------------------------------------------- GPS
func _make_gps() -> void:
	gps_line = MeshInstance3D.new()
	gps_line.mesh = ImmediateMesh.new()
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.25, 1.0, 0.55, 0.75)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	gps_line.material_override = m
	gps_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gps_line)
	gps_pin = Node3D.new()
	var lbl = Label3D.new()
	lbl.text = "▼"
	lbl.font_size = 180
	lbl.pixel_size = 0.006
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(0.3, 1.0, 0.6)
	lbl.outline_size = 24
	lbl.outline_modulate = Color("1d4a3a")
	lbl.no_depth_test = true
	lbl.fixed_size = false
	gps_pin.add_child(lbl)
	var beam = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.35
	cyl.height = 8.0
	beam.mesh = cyl
	var bm = StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.3, 1.0, 0.6, 0.18)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.material_override = bm
	beam.position.y = 4.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gps_pin.add_child(beam)
	add_child(gps_pin)
	gps_pin.visible = false


func refresh_gps() -> void:
	_gps_t = 0.0


func _update_gps() -> void:
	gps_target = orders.gps_target()
	if gps_target.is_empty() and story.step() in [0, 4]:
		gps_target = {"pos": people.mentor.position, "label": "Михалыч", "kind": "mentor"}
	var im: ImmediateMesh = gps_line.mesh
	im.clear_surfaces()
	if gps_target.is_empty():
		gps_pin.visible = false
		_gps_path = PackedVector3Array()
		return
	gps_pin.visible = true
	gps_pin.global_position = gps_target["pos"]
	var mode = "foot"
	if player.mode == Player.Mode.BIKE:
		mode = "bicycle"
	elif player.mode == Player.Mode.SCOOTER:
		mode = "scooter"
	_gps_path = nav.path(player.global_position, gps_target["pos"], mode)
	if _gps_path.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var w = 0.32
	for i in range(_gps_path.size() - 1):
		var a = _gps_path[i] + Vector3(0, 0.12, 0)
		var b = _gps_path[i + 1] + Vector3(0, 0.12, 0)
		if i == 0:
			a = player.global_position + Vector3(0, 0.12, 0)
		var d = (b - a)
		d.y = 0
		if d.length() < 0.01:
			continue
		var side = Vector3(-d.z, 0, d.x).normalized() * w
		im.surface_add_vertex(a - side)
		im.surface_add_vertex(a + side)
		im.surface_add_vertex(b + side)
		im.surface_add_vertex(a - side)
		im.surface_add_vertex(b + side)
		im.surface_add_vertex(b - side)
	im.surface_end()


func gps_path() -> PackedVector3Array:
	return _gps_path


# ---------------------------------------------------------------- day flow
func _on_hour(h: int) -> void:
	if h >= 20:
		Sfx.play_music("music_night")
	else:
		Sfx.play_music("music_day")
	if h == 22:
		toast("Скоро конец смены (23:00). Доставь, что успеешь!", 3.0)


func _on_shift_over() -> void:
	if shift_ending:
		return
	shift_ending = true
	for o in orders.active.duplicate():
		orders.cancel(o, "смена закончилась")
	screens.open_summary()


func current_vehicle() -> String:
	if player.riding():
		return player.vehicle_kind
	if not parked.is_empty():
		return parked["kind"]
	return ""


func swap_vehicle(kind: String) -> void:
	if kind == current_vehicle():
		toast("Ты и так на нём.", 1.2)
		return
	if player.riding():
		var node = player.dismount()
		node.queue_free()
	elif not parked.is_empty():
		parked["body"].queue_free()
		parked = {}
	var g = _marker("MARK_shop_garage")
	park_vehicle(kind, Vehicles.make(kind), g + Vector3(2.2, 0, 0.5), 0.0)
	Game.state["vehicle"] = kind
	toast("Механик выкатил %s к мастерской. Садись: F." % ("велосипед" if kind == "bicycle" else "самокат"), 2.5)


func on_bought(id: String) -> void:
	if id == "scooter":
		toast("Самокат твой! Возьми его во вкладке «Транспорт».", 3.0)
	if player.riding():
		Vehicles.apply_upgrades(player.vehicle_model, player.vehicle_kind)
	elif not parked.is_empty():
		Vehicles.apply_upgrades(parked["node"], parked["kind"])
	if id.begins_with("helmet"):
		player.apply_look()


func spawn_customer(o: Dictionary, res: Dictionary) -> void:
	var d: Dictionary = o["door"]
	var c = Chars.make(String(o["customer"].get("model", "office")), "happy" if int(res["stars"]) >= 4 else "angry")
	var dp = _v(d["pos"])
	var yaw = deg_to_rad(float(d["yaw"]))
	c.position = dp + Vector3(sin(yaw), 0, cos(yaw)) * 1.0
	c.rotation.y = yaw + PI
	add_child(c)
	get_tree().create_timer(4.0).timeout.connect(func(): if is_instance_valid(c): c.queue_free())


func to_menu() -> void:
	Sfx.stop_loops()
	Game.save_game()
	Game.go_play = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func next_day() -> void:
	Game.state["day"] = int(Game.state["day"]) + 1
	Game.state["rented_today"] = false
	if not Game.state["owned"].get("scooter", false):
		Game.state["vehicle"] = "bicycle"
	story.new_daily()
	Game.save_game()
	Sfx.stop_loops()
	Game.go_play = true
	get_tree().change_scene_to_file("res://scenes/main.tscn")
