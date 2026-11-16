class_name Screens
extends Control
## Modal screens built in code from UiKit: phone app, dialogues, kitchen wait, door + stairs, shops, summary, pause.

var world: Node
var stack: Array = []        # [{name, node}]
var _phone_tab = "orders"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiKit.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS


func top_name() -> String:
	return "" if stack.is_empty() else stack[stack.size() - 1]["name"]


func push(name: String, node: Control, pause = false) -> void:
	add_child(node)
	stack.append({"name": name, "node": node, "pause": pause})
	world.release_mouse()
	if pause:
		get_tree().paused = true
	if Game.is_touch() and world.touch:
		world.touch.release_all()


func close_top() -> void:
	if stack.is_empty():
		return
	var s: Dictionary = stack.pop_back()
	s["node"].queue_free()
	if s["pause"]:
		var still = false
		for x in stack:
			still = still or x["pause"]
		get_tree().paused = still
	if stack.is_empty():
		world._capture_mouse()


func close_all() -> void:
	while not stack.is_empty():
		close_top()


func close_named(name: String) -> void:
	for i in range(stack.size() - 1, -1, -1):
		if stack[i]["name"] == name:
			stack[i]["node"].queue_free()
			stack.remove_at(i)
	if stack.is_empty():
		get_tree().paused = false
		world._capture_mouse()


func _modal(min_size: Vector2, bg = UiKit.CREAM, dim = 0.45) -> Array:
	var root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	if dim > 0.0:
		UiKit.dim(root, dim)
	var p = UiKit.panel(min_size, bg)
	UiKit.center(root, p)
	var v = UiKit.vbox(12)
	p.add_child(v)
	return [root, v, p]


# ---------------------------------------------------------------- dialogue
func open_dialog(who: String, text: String, options: Array) -> void:
	var m = _modal(Vector2(820, 0), UiKit.CREAM, 0.25)
	var v: VBoxContainer = m[1]
	var head = UiKit.label(who, 30, UiKit.TURQ_D)
	v.add_child(head)
	var t = UiKit.label(text, 25, UiKit.INK, true)
	t.custom_minimum_size = Vector2(760, 0)
	v.add_child(t)
	var first: Button
	for opt in options:
		var cb: Callable = opt[1]
		var b = UiKit.button(opt[0], func():
			close_named("dialog")
			cb.call(), 760)
		v.add_child(b)
		if first == null:
			first = b
	push("dialog", m[0])
	if first:
		first.grab_focus.call_deferred()


# ---------------------------------------------------------------- phone app «Хоп!»
func open_phone(tab = "") -> void:
	if tab != "":
		_phone_tab = tab
	close_named("phone")
	var root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var phone = PanelContainer.new()
	phone.add_theme_stylebox_override("panel", UiKit.box(Color("2f2a33"), UiKit.INK, 6, 46, 18))
	phone.custom_minimum_size = Vector2(560, 830)
	UiKit.place(phone, Control.PRESET_CENTER_RIGHT, Vector2(-600, -415))
	root.add_child(phone)
	var screen = PanelContainer.new()
	screen.add_theme_stylebox_override("panel", UiKit.box(UiKit.CREAM, Color("2f2a33"), 0, 32, 14))
	phone.add_child(screen)
	var v = UiKit.vbox(10)
	screen.add_child(v)
	var head = UiKit.hbox(10)
	var logo = UiKit.label("Хоп!", 40, UiKit.TURQ_D)
	head.add_child(logo)
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UiKit.label("рейтинг %.1f · тел. %d%%" % [Game.state["rating"], int(world.player.phone)], 20))
	v.add_child(head)
	var tabs = UiKit.hbox(6)
	for tb in [["orders", "Заказы"], ["active", "Мои"], ["map", "Карта"], ["profile", "Профиль"]]:
		var id: String = tb[0]
		var b = UiKit.button(tb[1], func(): open_phone(id), 118, UiKit.TURQ if _phone_tab == id else Color("e8dcc4"))
		b.custom_minimum_size = Vector2(118, 46)
		b.add_theme_font_size_override("font_size", 20)
		tabs.add_child(b)
	v.add_child(tabs)
	var body = ScrollContainer.new()
	body.custom_minimum_size = Vector2(520, 600)
	body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(body)
	var list = UiKit.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(list)
	match _phone_tab:
		"orders":
			_phone_orders(list)
		"active":
			_phone_active(list)
		"map":
			_phone_map(list)
		"profile":
			_phone_profile(list)
	var close = UiKit.button("Закрыть (Tab)", func(): close_named("phone"), 520, Color("e8dcc4"))
	v.add_child(close)
	push("phone", root)
	if not world.orders.changed.is_connected(_phone_refresh):
		world.orders.changed.connect(_phone_refresh)


func _phone_refresh() -> void:
	if top_name() == "phone" and _phone_tab in ["orders", "active"]:
		open_phone()


func _card(bg = Color("ffffff")) -> Array:
	var c = PanelContainer.new()
	c.add_theme_stylebox_override("panel", UiKit.box(bg, UiKit.INK, 3, 18, 12))
	var v = UiKit.vbox(4)
	c.add_child(v)
	return [c, v]


const TRAIT_NOTE = {"polite": "", "capricious": "привередливый клиент!", "no_call": "просит НЕ звонить",
	"leave_at_door": "просит оставить у двери"}
const FOOD_ICON = {"pizza": "🍕", "burger": "🍔", "drink": "🥤", "sushi": "🍣", "coffee": "☕", "icecream": "🍦",
	"cake": "🎂", "lunch": "📦"}


func _phone_orders(list: VBoxContainer) -> void:
	var offers: Array = world.orders.offers
	if world.player.phone <= 0.0:
		list.add_child(UiKit.label("Телефон разряжен.", 24, UiKit.CORAL, true))
		return
	if offers.is_empty():
		list.add_child(UiKit.label("Новых заказов пока нет. Они приходят каждые 10–20 секунд — с уведомлением.", 22, UiKit.INK, true))
		if not world.story.offers_allowed() and world.story.step() == 0:
			list.add_child(UiKit.label("Сначала поговори с наставником Михалычем.", 22, Color("5d6670"), true))
	for o in offers:
		var c = _card(Color("fffdf6") if o.get("quest", "") == "" else Color("fff1c2"))
		var v: VBoxContainer = c[1]
		var row = UiKit.hbox(8)
		row.add_child(UiKit.label(o["rest_name"], 22, UiKit.TURQ_D))
		var sp = Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sp)
		row.add_child(UiKit.label("%d мон." % int(round(o["pay"])), 26, Color("c98a00")))
		v.add_child(row)
		v.add_child(UiKit.label("%s  »  %s" % [o["item"][1], o["door"]["label"]], 20, UiKit.INK, true))
		var info = "%d м · %d:%02d на доставку · этаж %d · риск: %s" % [int(o["dist"]), int(o["limit"]) / 60, int(o["limit"]) % 60, int(o["floor"]), o["risk"]]
		v.add_child(UiKit.label(info, 17, Color("5d6670"), true))
		var note: String = TRAIT_NOTE.get(o["customer"].get("trait", "polite"), "")
		if o["customer"].get("id", "") != "":
			note = "Постоянный клиент: %s  %s" % [o["customer"]["name"], note]
		if o.get("quest", "") != "":
			note = "КВЕСТ: " + Game.orders_data["quests"][o["quest"]]["title"] + ("  (нужен багажник)" if o.get("needs", "") == "rack" else "")
		if note != "":
			v.add_child(UiKit.label(note, 17, UiKit.CORAL, true))
		if o["expires"] < 900:
			v.add_child(UiKit.label("Исчезнет через %d с" % int(o["expires"]), 16, Color("8f8a80")))
		var br = UiKit.hbox(8)
		var od: Dictionary = o
		br.add_child(UiKit.button("Принять", func():
			if world.orders.accept(od):
				open_phone("active"), 250, Color("3bd16a")))
		br.add_child(UiKit.button("Скрыть", func(): world.orders.decline(od); open_phone(), 200, Color("e8dcc4")))
		v.add_child(br)
		list.add_child(c[0])


func _phone_active(list: VBoxContainer) -> void:
	if world.orders.active.is_empty():
		list.add_child(UiKit.label("Активных заказов нет. Загляни во вкладку «Заказы».", 22, UiKit.INK, true))
	for o in world.orders.active:
		var c = _card()
		var v: VBoxContainer = c[1]
		v.add_child(UiKit.label("%s — %s" % [o["item"][1], o["rest_name"]], 22, UiKit.TURQ_D, true))
		v.add_child(UiKit.label("Клиент: %s · %s · этаж %d" % [o["customer"].get("name", ""), o["door"]["label"], int(o["floor"])], 19, UiKit.INK, true))
		var tl: float = world.orders.time_left(o)
		var st = {"to_restaurant": "Едь в ресторан", "waiting": "Кухня готовит", "carrying": "Вези клиенту"}.get(o["state"], "")
		v.add_child(UiKit.label("%s · %s %d:%02d · оплата %d мон." % [st, "осталось" if tl >= 0 else "опоздание", int(abs(tl)) / 60, int(abs(tl)) % 60, int(o["pay"])], 18, Color("5d6670"), true))
		var note: String = TRAIT_NOTE.get(o["customer"].get("trait", "polite"), "")
		if note != "":
			v.add_child(UiKit.label(note, 17, UiKit.CORAL))
		var br = UiKit.hbox(8)
		var od: Dictionary = o
		if o["state"] == "carrying":
			br.add_child(UiKit.button("Позвонить", func(): close_named("phone"); world.call_customer(), 220, UiKit.TURQ))
		br.add_child(UiKit.button("Отменить", func():
			world.orders.cancel(od, "отказ курьера")
			open_phone("active"), 200, UiKit.CORAL))
		v.add_child(br)
		list.add_child(c[0])


func _phone_map(list: VBoxContainer) -> void:
	var mp = PhoneMap.new()
	mp.world = world
	mp.custom_minimum_size = Vector2(510, 560)
	list.add_child(mp)
	list.add_child(UiKit.label("Зелёная линия — твой маршрут. Красная точка — цель.", 18, Color("5d6670"), true))


func _phone_profile(list: VBoxContainer) -> void:
	var s: Dictionary = Game.state["stats"]
	list.add_child(UiKit.label(world.story.chapter_title(), 26, UiKit.TURQ_D, true))
	list.add_child(UiKit.label(world.story.objective(), 20, UiKit.INK, true))
	list.add_child(UiKit.label("Рейтинг: %.2f из 5   (ниже 3,0 — предупреждение, ниже 2,5 — блокировка)" % Game.state["rating"], 19, UiKit.INK, true))
	list.add_child(UiKit.label("Доставлено: %d · опозданий: %d · чаевые: %d · штрафы: %d · падения: %d" % [int(s["delivered"]), int(s["late"]), int(s["tips"]), int(s["fines"]), int(s["falls"])], 18, Color("5d6670"), true))
	list.add_child(UiKit.label("Задания дня", 24, UiKit.TURQ_D))
	for t in Game.state["daily"]:
		list.add_child(UiKit.label("%s %s — %d/%d (+%d)" % ["[готово]" if t["done"] else "•", t["text"], min(int(t["have"]), int(t["goal"])), int(t["goal"]), int(t["reward"])], 19, UiKit.INK if not t["done"] else Color("17807b"), true))
	list.add_child(UiKit.label("Сумка: перекус %d · энергетик %d · павербанк %d · ремкомплект %d" % [Game.item_count("snack"), Game.item_count("energy_drink"), Game.item_count("powerbank"), Game.item_count("repair_kit")], 18, UiKit.INK, true))
	list.add_child(UiKit.button("Использовать предмет (X)", func(): close_named("phone"); quick_item(), 480))


class PhoneMap:
	extends Control
	var world: Node

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var lv: Level = world.level
		if lv.map_tex == null:
			return
		var r = Rect2(Vector2.ZERO, size)
		var ts = Vector2(lv.map_tex.get_width(), lv.map_tex.get_height())
		var k: float = min(r.size.x / ts.x, r.size.y / ts.y)
		var dr = Rect2(Vector2.ZERO, ts * k)
		draw_texture_rect(lv.map_tex, dr, false)
		var mr: Rect2 = lv.map_rect
		var f = func(p: Vector3) -> Vector2:
			return Vector2((p.x - mr.position.x) / mr.size.x, (p.z - mr.position.y) / mr.size.y) * dr.size
		var path: PackedVector3Array = world.gps_path()
		if path.size() > 1:
			var pts = PackedVector2Array()
			for q in path:
				pts.append(f.call(q))
			draw_polyline(pts, Color(0.15, 0.85, 0.45), 4.0, true)
		for k2 in Game.orders_data["restaurants"].keys():
			var rr: Dictionary = Game.orders_data["restaurants"][k2]
			draw_circle(f.call(Vector3(rr["pickup"][0], 0, rr["pickup"][2])), 6.0, UiKit.SUN)
		draw_circle(f.call(world.people.mentor.position), 6.0, UiKit.TURQ)
		var tgt: Dictionary = world.gps_target
		if not tgt.is_empty():
			draw_circle(f.call(tgt["pos"]), 9.0, UiKit.CORAL)
		var c: Vector2 = f.call(world.player.global_position)
		draw_circle(c, 8.0, UiKit.TURQ_D)
		draw_arc(c, 8.0, 0, TAU, 16, Color.WHITE, 2.0)


# ---------------------------------------------------------------- kitchen wait
func open_wait(o: Dictionary) -> void:
	var m = _modal(Vector2(640, 0), UiKit.CREAM, 0.2)
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.label(o["rest_name"], 30, UiKit.TURQ_D))
	var txt = "Повар: «Ещё чуть-чуть! Ваш %s почти готов»." % o["item"][1]
	if o["flags"].get("delay"):
		txt = "Повар машет руками: «Завал на кухне! Ещё пару минут!» Можно подождать, отменить или взять второй заказ рядом."
	v.add_child(UiKit.label(txt, 22, UiKit.INK, true))
	var bar = UiKit.bar(0.0, UiKit.TURQ, 560, 26)
	v.add_child(bar)
	var take = UiKit.button("Забрать заказ", func():
		close_named("wait")
		world.take_when_ready(o), 560, Color("3bd16a"))
	take.disabled = true
	v.add_child(take)
	v.add_child(UiKit.button("Отойти (заказ подождёт)", func(): o["state"] = "to_restaurant"; close_named("wait"), 560, Color("e8dcc4")))
	v.add_child(UiKit.button("Отменить заказ", func():
		close_named("wait")
		world.orders.cancel(o, "долго готовили"), 560, UiKit.CORAL))
	var total: float = max(1.0, float(o["cook_left"]))
	var tw = m[0].create_tween().set_loops()
	tw.tween_callback(func():
		if not is_instance_valid(bar):
			return
		bar.value = 1.0 - float(o["cook_left"]) / total
		take.disabled = float(o["cook_left"]) > 0.5
		if not take.disabled and take.text == "Забрать заказ":
			take.text = "Готово! Забрать заказ"
			Sfx.play("notify", 0.6)
			take.grab_focus()).set_delay(0.2)
	push("wait", m[0])


# ---------------------------------------------------------------- door, stairs, customer
func open_door(o: Dictionary, door: Dictionary) -> void:
	var m = _modal(Vector2(700, 0), UiKit.CREAM, 0.2)
	var v: VBoxContainer = m[1]
	var cust: Dictionary = o["customer"]
	v.add_child(UiKit.label("%s, %s" % [door["label"], "этаж %d" % int(o["floor"])], 26, UiKit.TURQ_D, true))
	v.add_child(UiKit.label("Клиент: %s. %s" % [cust.get("name", ""), TRAIT_NOTE.get(cust.get("trait", "polite"), "")], 21, UiKit.INK, true))
	var tower = door.get("kind", "house") == "tower"
	if door["lift"] == false:
		v.add_child(UiKit.label("Лифта нет — пешком на %d этаж." % int(o["floor"]), 19, Color("5d6670")))
	elif tower:
		v.add_child(UiKit.label("Бизнес-башня: лифты, на входе охрана%s." % (" (у тебя пропуск)" if Game.state.get("pass", false) else ""), 19, Color("5d6670")))
	else:
		v.add_child(UiKit.label("В доме есть лифт. Если работает...", 19, Color("5d6670")))
	var state = {"waited": 0.0}
	var info = UiKit.label("", 21, UiKit.CORAL, true)
	v.add_child(info)
	var od = o
	v.add_child(UiKit.button("Пройти через турникет" if tower else "Позвонить в домофон", func():
		if tower:
			close_named("door")
			_tower_entry(od, door)
			return
		Sfx.play("intercom")
		world.player._play("ring_intercom", true)
		if od["flags"].get("intercom") and not od["flags"].get("intercom_fixed"):
			info.text = "Домофон молчит — сломан. Позвони клиенту (C), он откроет."
			return
		if od["flags"].get("no_answer") and not od["flags"].get("answered"):
			info.text = "Никто не отвечает... Позвони клиенту или подожди."
			return
		close_named("door")
		_go_up(od, door), 640, UiKit.SUN))
	v.add_child(UiKit.button("Позвонить клиенту", func():
		close_named("door")
		world.call_customer(), 640, UiKit.TURQ))
	var leave = UiKit.button("Оставить у двери", func():
		close_named("door")
		_deliver(od, "door"), 640, Color("e8dcc4"))
	leave.disabled = cust.get("trait", "") != "leave_at_door" and not od["flags"].get("waited_long", false)
	v.add_child(leave)
	v.add_child(UiKit.button("Отойти", func(): close_named("door"), 640, Color("e8dcc4")))
	var tw = m[0].create_tween().set_loops()
	tw.tween_callback(func():
		state["waited"] += 1.0
		if od["flags"].get("no_answer") and state["waited"] >= 8.0 and not od["flags"].get("answered"):
			od["flags"]["answered"] = true
			info.text = "Щёлк! Дверь подъезда открылась — кто-то выходил. Можно подниматься."
		if state["waited"] >= 20.0:
			od["flags"]["waited_long"] = true
			if is_instance_valid(leave):
				leave.disabled = false).set_delay(1.0)
	push("door", m[0])


## Business towers: the guard checks couriers without a pass; lifts take you up.
func _tower_entry(o: Dictionary, door: Dictionary) -> void:
	var cust: Dictionary = o["customer"]
	if cust.get("id", "") == "viktor":
		_customer(o)   # the guard himself is the customer
		return
	if Game.state.get("pass", false) or o["flags"].get("guard_ok", false):
		Sfx.play("ui")
		_go_up(o, door)
		return
	world.people_guard_look()
	open_dialog("Охранник", "— Стоп-стоп! Курьерам без пропуска наверх нельзя. Или клиент спускается, или звонит на пост.", [
		["Позвонить клиенту: пусть закажет пропуск", func():
			o["flags"]["called"] = true
			Sfx.play("ring")
			o["elapsed"] = float(o["elapsed"]) + 20.0
			o["flags"]["guard_ok"] = true
			world.toast("Клиент позвонил на пост. Охранник кивает: проходи! (−20 с)", 2.5)
			_go_up(o, door)],
		["Оставить на ресепшене", func(): _deliver(o, "door")],
		["Отойти", func(): pass],
	])


func _go_up(o: Dictionary, door: Dictionary) -> void:
	if door.get("lift", false) and not o["flags"].get("broken_lift", false):
		open_lift(o)
	else:
		if door.get("lift", false):
			world.banner("Лифт не работает", "Табличка «Лифт на ремонте». Опять. Только пешком!")
		open_stairs(o)


func open_lift(o: Dictionary) -> void:
	var root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg = ColorRect.new()
	bg.color = Color("cfd6da")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var art = Lift.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.floors = int(o["floor"])
	root.add_child(art)
	var title = UiKit.title("Лифт: этаж 1", 40)
	title.custom_minimum_size = Vector2(800, 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.place(title, Control.PRESET_CENTER_TOP, Vector2(-400, 40))
	root.add_child(title)
	var dur = 1.6 + int(o["floor"]) * 0.18
	var s = {"t": 0.0, "done": false}
	Sfx.play("ui")
	art.proc = func(delta: float):
		if s["done"]:
			return
		s["t"] += delta
		var k = clamp(s["t"] / dur, 0.0, 1.0)
		art.progress = k
		title.text = "Лифт: этаж %d" % max(1, int(round(1 + k * (int(o["floor"]) - 1))))
		if k >= 1.0:
			s["done"] = true
			o["elapsed"] = float(o["elapsed"]) + dur * 2.0
			Sfx.play("bell", 0.6)
			close_named("lift")
			_customer(o)
	push("lift", root)


class Lift:
	extends Control
	var floors = 5
	var progress = 0.0
	var proc: Callable

	func _process(delta: float) -> void:
		if proc.is_valid():
			proc.call(delta)
		queue_redraw()

	func _draw() -> void:
		var w = size.x
		var h = size.y
		var cx = w * 0.5
		# shaft with moving floor lines, the cabin in the middle
		var off = fmod(progress * floors * 220.0, 220.0)
		for i in range(-1, 6):
			var y = h * 0.15 + i * 220.0 + off
			draw_rect(Rect2(Vector2(cx - 260, y), Vector2(520, 14)), Color("8d989f"))
		draw_rect(Rect2(Vector2(cx - 170, h * 0.32), Vector2(340, 380)), Color("e9e2d2"))
		draw_rect(Rect2(Vector2(cx - 170, h * 0.32), Vector2(340, 380)), Color("6b7378"), false, 10.0)
		draw_rect(Rect2(Vector2(cx - 4, h * 0.32), Vector2(8, 380)), Color("9aa4ad"))
		# the courier with the bag inside
		var by = h * 0.32 + 250
		draw_rect(Rect2(Vector2(cx - 40, by - 90), Vector2(80, 100)), Color("22b8b0"))
		draw_rect(Rect2(Vector2(cx + 30, by - 100), Vector2(60, 70)), Color("1a8f89"))
		draw_circle(Vector2(cx, by - 130), 38.0, Color("f2c39b"))
		draw_rect(Rect2(Vector2(cx - 36, by - 172), Vector2(76, 24)), Color("22b8b0"))
		draw_circle(Vector2(cx - 12, by - 134), 5.0, Color("2b2320"))
		draw_circle(Vector2(cx + 12, by - 134), 5.0, Color("2b2320"))
		draw_rect(Rect2(Vector2(cx - 30, by + 10), Vector2(22, 70)), Color("56483f"))
		draw_rect(Rect2(Vector2(cx + 8, by + 10), Vector2(22, 70)), Color("56483f"))


func open_stairs(o: Dictionary) -> void:
	var root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg = ColorRect.new()
	bg.color = Color("efe2c8")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var art = Stairwell.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.floors = int(o["floor"])
	root.add_child(art)
	var top = UiKit.vbox(8)
	top.custom_minimum_size = Vector2(800, 0)
	UiKit.place(top, Control.PRESET_CENTER_TOP, Vector2(-400, 30))
	root.add_child(top)
	var stair_word = "Лестница (лифт сломан)" if o["door"].get("lift", false) else "Подъезд без лифта"
	var title = UiKit.title("%s: этаж 1 из %d" % [stair_word, int(o["floor"])], 36)
	top.add_child(title)
	var hint = UiKit.label("Держи E / пробел (или кнопку «Вверх!») чтобы подниматься. Силы тратятся!", 22, UiKit.INK, true, HORIZONTAL_ALIGNMENT_CENTER)
	top.add_child(hint)
	var st_bar = UiKit.bar(world.player.stamina / 100.0, UiKit.SUN, 400, 22)
	top.add_child(st_bar)
	var up = UiKit.button("Вверх!", func(): pass, 300, UiKit.TURQ)
	up.custom_minimum_size = Vector2(300, 90)
	UiKit.place(up, Control.PRESET_CENTER_BOTTOM, Vector2(-150, -140))
	root.add_child(up)
	var s = {"progress": 0.0, "done": false}
	var proc = func(delta: float):
		if s["done"]:
			return
		var holding = Input.is_action_pressed("interact") or Input.is_action_pressed("brake") or up.button_pressed
		if holding:
			var spd = 0.75 if world.player.stamina > 5.0 else 0.32
			s["progress"] += delta * spd
			world.player.stamina = max(0.0, world.player.stamina - 7.0 * delta)
			o["elapsed"] += delta * 2.0   # climbing takes real delivery time
			if int(s["progress"] * 3.0) != int((s["progress"] - delta * spd) * 3.0):
				Sfx.play("step", 0.5, randf_range(0.9, 1.1))
		var fl: int = min(int(o["floor"]), 1 + int(s["progress"]))
		title.text = "%s: этаж %d из %d" % [stair_word, fl, int(o["floor"])]
		art.progress = s["progress"]
		st_bar.value = world.player.stamina / 100.0
		if s["progress"] >= float(o["floor"]) - 0.999:
			s["done"] = true
			close_named("stairs")
			_customer(o)
	art.proc = proc
	push("stairs", root)


class Stairwell:
	extends Control
	var floors = 3
	var progress = 0.0
	var proc: Callable

	func _process(delta: float) -> void:
		if proc.is_valid():
			proc.call(delta)
		queue_redraw()

	func _draw() -> void:
		var w = size.x
		var h = size.y
		var step_w = 70.0
		var step_h = 34.0
		var off = fmod(progress, 1.0) * step_h * 8.0
		for i in range(-2, 22):
			var x = w * 0.5 - 360.0 + i * step_w * 0.5
			var y = h - 120.0 - i * step_h + off
			draw_rect(Rect2(Vector2(x, y), Vector2(step_w * 3.0, step_h)), Color("c9a77c"))
			draw_rect(Rect2(Vector2(x, y), Vector2(step_w * 3.0, 6)), Color("8a6a46"))
		for i in 3:
			var ry = h - 420.0 + i * 200.0 + fmod(off, 200.0)
			draw_rect(Rect2(Vector2(w * 0.5 + 220, ry), Vector2(140, 90)), Color("6b5446"))
			draw_string(get_theme_default_font(), Vector2(w * 0.5 + 255, ry + 60), "%d" % (int(progress) + 2 - i), HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color("fbf3e2"))
		# the courier (simple cartoon)
		var cx = w * 0.5 - 60.0
		var cy = h * 0.55 + sin(progress * 25.0) * 6.0
		draw_rect(Rect2(Vector2(cx - 34, cy - 60), Vector2(68, 76)), Color("22b8b0"))
		draw_rect(Rect2(Vector2(cx - 50, cy - 70), Vector2(36, 62)), Color("1a8f89"))
		draw_circle(Vector2(cx + 4, cy - 92), 34.0, Color("f2c39b"))
		draw_circle(Vector2(cx + 16, cy - 98), 5.0, Color("2b2320"))
		draw_rect(Rect2(Vector2(cx - 30, cy - 130), Vector2(70, 22)), Color("22b8b0"))
		var leg = sin(progress * 25.0) * 14.0
		draw_line(Vector2(cx - 12, cy + 16), Vector2(cx - 12 + leg, cy + 60), Color("5a4436"), 14.0)
		draw_line(Vector2(cx + 14, cy + 16), Vector2(cx + 14 - leg, cy + 60), Color("5a4436"), 14.0)


func _customer(o: Dictionary) -> void:
	var cust: Dictionary = o["customer"]
	var lines: Array = cust.get("lines", ["Спасибо!"])
	var greet: String = lines[0] if lines.size() > 0 else "Спасибо!"
	var t: String = cust.get("trait", "polite")
	if t == "capricious":
		greet = lines[randi() % lines.size()]
	open_dialog(cust.get("name", "Клиент"), "— " + greet, [
		["«Ваш заказ! Приятного аппетита!» (вежливо)", func(): _deliver(o, "polite")],
		["«Доставка со скоростью ветра и ароматом кухни!» (шутка)", func(): _deliver(o, "funny")],
		["«Держите.» (коротко)", func(): _deliver(o, "curt")],
	])


func _deliver(o: Dictionary, reply: String) -> void:
	var res: Dictionary = world.orders.deliver(o, reply)
	world.player.carrying = false
	world.player._play("hand_over", true)
	world.player.busy = 0.8
	var cust: Dictionary = o["customer"]
	var lines: Array = cust.get("lines", [])
	var bye: String = lines[lines.size() - 1] if lines.size() > 1 else "Спасибо!"
	var m = _modal(Vector2(620, 0), UiKit.CREAM, 0.2)
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.title("Доставлено!" if not res["late"] else "Доставлено с опозданием", 36))
	v.add_child(UiKit.label("— " + bye, 22, UiKit.INK, true))
	var sc = CenterContainer.new()
	sc.add_child(Icon.stars(float(res["stars"]), 52.0))
	v.add_child(sc)
	v.add_child(UiKit.label("Оплата %d мон.   Чаевые %d мон.%s" % [int(res["pay"]), int(res["tip"]), ("   Бонус %d мон." % int(res["bonus"])) if res["bonus"] > 0 else ""], 24, UiKit.INK))
	v.add_child(UiKit.label("Рейтинг: %.2f" % Game.state["rating"], 20, Color("5d6670")))
	v.add_child(UiKit.button("Дальше", func(): close_named("result"), 560))
	push("result", m[0])
	world.spawn_customer(o, res)


# ---------------------------------------------------------------- shops
func _shop_row(v: VBoxContainer, id: String, after: Callable) -> void:
	var it: Dictionary = Game.SHOP[id]
	var c = _card()
	var cv: VBoxContainer = c[1]
	var row = UiKit.hbox(10)
	var name = UiKit.label(it["name"], 22, UiKit.TURQ_D)
	name.custom_minimum_size = Vector2(300, 0)
	row.add_child(name)
	var have = ""
	match it["kind"]:
		"upgrade":
			have = "  ур. %d/%d" % [Game.upgrade_level(id), int(it.get("max", 1))]
		"gear", "helmet":
			have = "  (есть)" if Game.has_gear(id) else ""
		"consumable":
			have = "  в сумке: %d" % Game.item_count(id)
		"vehicle":
			have = "  (свой)" if Game.state["owned"].get(id, false) else ""
	row.add_child(UiKit.label(have, 18, Color("17807b")))
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	var b = UiKit.button("%d мон." % int(it["price"]), func():
		if Game.buy(id):
			Sfx.play("coin")
			world.story.on_buy(id)
			world.on_bought(id)
			after.call()
		else:
			Sfx.play("fail"), 130, Color("3bd16a"))
	b.disabled = not Game.can_buy(id)
	if it["kind"] == "helmet" and Game.has_gear(id):
		b.text = "Надеть" if Game.state.get("helmet", "") != id else "Снять"
		b.disabled = false
		b.pressed.connect(func():
			Game.state["helmet"] = "" if Game.state.get("helmet", "") == id else id
			world.player.apply_look()
			after.call())
	row.add_child(b)
	cv.add_child(row)
	cv.add_child(UiKit.label(it["desc"], 17, Color("5d6670"), true))
	v.add_child(c[0])


func _shop_window(title: String, sub: String, build: Callable, name: String) -> void:
	close_named(name)
	var m = _modal(Vector2(860, 0))
	var v: VBoxContainer = m[1]
	var head = UiKit.hbox(10)
	head.add_child(UiKit.label(title, 34, UiKit.TURQ_D))
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UiKit.label(Game.money_text() + " мон.", 32, Color("c98a00")))
	v.add_child(head)
	if sub != "":
		v.add_child(UiKit.label(sub, 19, Color("5d6670"), true))
	var sc = ScrollContainer.new()
	sc.custom_minimum_size = Vector2(820, 560)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list = UiKit.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	v.add_child(sc)
	build.call(list)
	v.add_child(UiKit.button("Закрыть", func(): close_named(name), 820, Color("e8dcc4")))
	push(name, m[0])


var _garage_tab = "vehicle"


func open_garage(tab = "") -> void:
	if tab != "":
		_garage_tab = tab
	_shop_window("Мастерская", "Транспорт, улучшения, экипировка и внешность курьера.", _garage_build, "garage")


func _garage_build(list: VBoxContainer) -> void:
	var tabs = UiKit.hbox(6)
	for tb in [["vehicle", "Транспорт"], ["upgrades", "Улучшения"], ["gear", "Экипировка"], ["look", "Внешность"]]:
		var id: String = tb[0]
		var b = UiKit.button(tb[1], func(): open_garage(id), 190, UiKit.TURQ if _garage_tab == id else Color("e8dcc4"))
		tabs.add_child(b)
	list.add_child(tabs)
	var re = func(): open_garage()
	if _garage_tab == "vehicle":
		_garage_vehicle(list)
	elif _garage_tab == "upgrades":
		for id in ["battery", "motor", "tires", "brakes", "rack", "lock", "headlight", "mudguards"]:
			_shop_row(list, id, re)
	elif _garage_tab == "gear":
		for id in ["raincoat", "waterproof_bag", "cooling_pack", "cup_holder", "soft_bag", "helmet_bike", "helmet_half", "helmet_retro"]:
			_shop_row(list, id, re)
	else:
		_garage_look(list)


func _garage_vehicle(list: VBoxContainer) -> void:
	var owned_s: bool = Game.state["owned"].get("scooter", false)
	var rented: bool = Game.state.get("rented_today", false)
	var cur = world.current_vehicle()
	list.add_child(UiKit.label("Сейчас: %s" % ("велосипед" if cur == "bicycle" else ("самокат" if cur == "scooter" else "нет (угнан?)")), 22))
	var row = UiKit.hbox(10)
	row.add_child(UiKit.button("Взять велосипед", func(): world.swap_vehicle("bicycle"); open_garage(), 380, UiKit.TURQ))
	var sb = UiKit.button("Взять самокат", func(): world.swap_vehicle("scooter"); open_garage(), 380, UiKit.TURQ)
	sb.disabled = not (owned_s or rented)
	row.add_child(sb)
	list.add_child(row)
	if not owned_s:
		var rb = UiKit.button("Арендовать самокат на день — %d мон." % Game.SCOOTER_RENT, func():
			if Game.state["money"] >= Game.SCOOTER_RENT:
				Game.spend(Game.SCOOTER_RENT)
				Game.state["rented_today"] = true
				Sfx.play("coin")
				world.swap_vehicle("scooter")
				open_garage()
			else:
				Sfx.play("fail"), 780, Color("3bd16a"))
		rb.disabled = rented
		list.add_child(rb)
	_shop_row(list, "scooter", func(): open_garage())
	if world.events.flat:
		list.add_child(UiKit.button("Заклеить прокол — 10 мон.", func():
			if Game.state["money"] >= 10:
				Game.spend(10)
				world.events.fix_flat()
				open_garage(), 780, UiKit.SUN))
	list.add_child(UiKit.label("Заряд самоката: %d%%. Станции зарядки — у кафе курьеров." % int(world.battery), 18, Color("5d6670"), true))


func _garage_look(list: VBoxContainer) -> void:
	var look: Dictionary = Game.state["look"]
	var redo = func():
		world.player.build_model()
		open_garage()
	var r1 = UiKit.hbox(8)
	r1.add_child(UiKit.label("Курьер:", 22))
	r1.add_child(UiKit.button("Парень", func(): look["gender"] = "m"; redo.call(), 180, UiKit.TURQ if look["gender"] == "m" else Color("e8dcc4")))
	r1.add_child(UiKit.button("Девушка", func(): look["gender"] = "f"; redo.call(), 180, UiKit.TURQ if look["gender"] == "f" else Color("e8dcc4")))
	list.add_child(r1)
	var r2 = UiKit.hbox(8)
	r2.add_child(UiKit.label("Причёска:", 22))
	for h in [["short", "Короткая"], ["ponytail", "Хвост"], ["curly", "Кудри"], ["bun", "Пучок"]]:
		var hid: String = h[0]
		r2.add_child(UiKit.button(h[1], func(): look["hair"] = hid; redo.call(), 150, UiKit.TURQ if look["hair"] == hid else Color("e8dcc4")))
	list.add_child(r2)
	var r3 = UiKit.hbox(8)
	r3.add_child(UiKit.label("Куртка:", 22))
	for c in Game.JACKETS:
		var cc: String = c
		var b = UiKit.button("  ", func(): look["jacket"] = cc; world.player.apply_look(), 64, Color(cc))
		r3.add_child(b)
	list.add_child(r3)
	list.add_child(UiKit.button("Кепка: " + ("да" if look.get("cap", true) else "нет"), func(): look["cap"] = not look.get("cap", true); world.player.apply_look(); open_garage(), 300))
	list.add_child(UiKit.label("Шлемы покупаются во вкладке «Экипировка».", 18, Color("5d6670")))


func open_kiosk() -> void:
	_shop_window("Ларёк «Перекус»", "Еда для курьера и полезное в сумку.", _kiosk_build, "kiosk")


func _kiosk_build(list: VBoxContainer) -> void:
	for id in ["snack", "energy_drink", "powerbank", "repair_kit"]:
		_shop_row(list, id, func(): open_kiosk())
	list.add_child(UiKit.button("Съесть шаурму прямо сейчас — 7 мон.", _eat_now, 780, UiKit.SUN))


func _eat_now() -> void:
	if Game.state["money"] >= 7:
		Game.spend(7)
		world.player.hunger = 0.0
		world.player._play("eat_snack", true)
		world.player.busy = 2.0
		Sfx.play("coin")
		close_named("kiosk")
		world.toast("Ням! Сытость восстановлена.", 1.8)
	else:
		Sfx.play("fail")


func open_cafe() -> void:
	_shop_window("Кафе курьеров", "Тут свои. Кофе, розетка и сплетни Михалыча.", _cafe_build, "cafe")


func _cafe_build(list: VBoxContainer) -> void:
	list.add_child(UiKit.button("Капучино (+50 сил) — 4 мон.", _coffee, 780, UiKit.SUN))
	list.add_child(UiKit.button("Зарядить телефон до 100% — 3 мон.", _charge_phone, 780, UiKit.TURQ))
	list.add_child(UiKit.button("Сохранить игру", func(): Game.save_game(); world.toast("Игра сохранена.", 1.5), 780, Color("e8dcc4")))


func _coffee() -> void:
	if Game.state["money"] >= 4:
		Game.spend(4)
		world.player.stamina = min(100.0, world.player.stamina + 50.0)
		Sfx.play("coin")
		close_named("cafe")
		world.toast("Бодрость +50!", 1.6)
	else:
		Sfx.play("fail")


func _charge_phone() -> void:
	if Game.state["money"] >= 3:
		Game.spend(3)
		world.player.phone = 100.0
		Sfx.play("coin")
		close_named("cafe")
		world.toast("Телефон заряжен!", 1.6)
	else:
		Sfx.play("fail")


func quick_item() -> void:
	var p: Player = world.player
	var opts = []
	if Game.item_count("snack") > 0:
		opts.append(["Перекус (%d) — сытость" % Game.item_count("snack"), func():
			Game.use_item("snack")
			p.hunger = max(0.0, p.hunger - 60.0)
			world.toast("Ням!", 1.2)])
	if Game.item_count("energy_drink") > 0:
		opts.append(["Энергетик (%d) — +60 сил" % Game.item_count("energy_drink"), func():
			Game.use_item("energy_drink")
			p.stamina = min(100.0, p.stamina + 60.0)
			p.hunger = min(100.0, p.hunger + 10.0)
			world.toast("Вжух! Силы +60", 1.2)])
	if Game.item_count("powerbank") > 0:
		opts.append(["Павербанк (%d) — телефон 100%%%s" % [Game.item_count("powerbank"), " и самокат +50%" if world.current_vehicle() == "scooter" else ""], func():
			Game.use_item("powerbank")
			p.phone = 100.0
			if world.current_vehicle() == "scooter":
				world.battery = min(100.0, world.battery + 50.0)
			world.toast("Заряжено!", 1.2)])
	if Game.item_count("repair_kit") > 0 and world.events.flat:
		opts.append(["Ремкомплект — заклеить прокол", func():
			Game.use_item("repair_kit")
			world.events.fix_flat()])
	if opts.is_empty():
		world.toast("В сумке нет полезных предметов. Загляни в ларёк.", 2.0)
		return
	opts.append(["Отмена", func(): pass])
	open_dialog("Сумка курьера", "Что используем?", opts)


# ---------------------------------------------------------------- end of shift, pause, settings, ban
func open_summary() -> void:
	var log: Array = world.orders.day_log
	var earned = 0.0
	var tips = 0.0
	var n = 0
	var five = 0
	for r in log:
		earned += float(r.get("total", 0.0))
		tips += float(r.get("tip", 0.0))
		if r.get("pay", 0.0) > 0.0:
			n += 1
		if int(r.get("stars", 0)) >= 5:
			five += 1
	var m = _modal(Vector2(780, 0), UiKit.CREAM, 0.6)
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.title("Смена %d окончена" % int(Game.state["day"]), 42))
	v.add_child(UiKit.label("Доставлено заказов: %d   ·   пять звёзд: %d" % [n, five], 24))
	v.add_child(UiKit.label("Заработано: %d мон. (чаевые %d)" % [int(earned), int(tips)], 24))
	v.add_child(UiKit.label("Рейтинг: %.2f из 5" % Game.state["rating"], 24))
	if Game.state.get("dream", "locked") == "open":
		var inc = world.story.restaurant_income()
		v.add_child(UiKit.label("Твой ресторан «Горячая сумка» принёс за день: +%d мон." % inc, 22, Color("17807b")))
	v.add_child(UiKit.label("Кошелёк: %s мон." % Game.money_text(), 24, Color("c98a00")))
	for t in Game.state["daily"]:
		v.add_child(UiKit.label("%s %s" % ["[готово]" if t["done"] else "[нет]", t["text"]], 19, Color("17807b") if t["done"] else Color("8f8a80")))
	v.add_child(UiKit.label(world.story.objective(), 20, UiKit.TURQ_D, true))
	v.add_child(UiKit.button("Следующий день", func():
		get_tree().paused = false
		world.next_day(), 700, Color("3bd16a")))
	v.add_child(UiKit.button("Выйти в меню", func():
		get_tree().paused = false
		Game.state["day"] = int(Game.state["day"]) + 1
		Game.save_game()
		world.to_menu(), 700, Color("e8dcc4")))
	push("summary", m[0], true)
	Sfx.play("level_up", 0.5)


## Chapter 5 finale: the critic loved the food, the restaurant is open.
func open_ending() -> void:
	var st: Dictionary = Game.state["stats"]
	var m = _modal(Vector2(860, 0), UiKit.CREAM, 0.7)
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.title("Ресторан мечты открыт!", 46, UiKit.TURQ_D))
	v.add_child(UiKit.label("Критик Аркадий Вилкин написал в колонке: «Лучший ужин сезона. Привёз его сам хозяин — на старом велике и с горячей сумкой за спиной»." , 22, UiKit.INK, true))
	v.add_child(UiKit.label("Ты приехал в большой город новичком с рейтингом 4,0 — а теперь у тебя свой ресторан на Часовой площади.", 21, UiKit.INK, true))
	v.add_child(UiKit.label("Дней в городе: %d   ·   доставок: %d   ·   чаевых: %d мон.   ·   падений: %d" % [int(Game.state["day"]), int(st["delivered"]), int(st["tips"]), int(st.get("falls", 0))], 20, Color("5d6670"), true))
	v.add_child(UiKit.label("Рейтинг: %.2f   ·   лучшая серия без опозданий: %d" % [float(Game.state["rating"]), int(Game.state.get("best_streak", 0))], 20, Color("5d6670")))
	v.add_child(UiKit.label("Спасибо, что играл! Ресторан приносит доход каждый день, а заказы из него приходят в «Хоп!». Город твой — катайся дальше.", 21, UiKit.TURQ_D, true))
	var sc = CenterContainer.new()
	sc.add_child(Icon.stars(5.0, 56.0))
	v.add_child(sc)
	v.add_child(UiKit.button("Продолжить смену", func():
		get_tree().paused = false
		close_named("ending"), 700, Color("3bd16a")))
	push("ending", m[0], true)
	Sfx.play("level_up")


func open_blocked() -> void:
	for o in world.orders.active.duplicate():
		world.orders.cancel(o, "аккаунт заблокирован")
	var m = _modal(Vector2(760, 0), Color("ffe0dc"), 0.6)
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.title("Аккаунт заблокирован", 42, UiKit.CORAL))
	v.add_child(UiKit.label("Приложение «Хоп!» считает, что курьеру нужен выходной: рейтинг упал ниже 2,5. Михалыч разводит руками: «Бывает. Завтра начнём с чистого листа — но аккуратнее!»", 22, UiKit.INK, true))
	v.add_child(UiKit.button("Отдохнуть до завтра", func():
		Game.state["rating"] = 3.2
		Game.state["votes"] = 5
		close_named("blocked")
		open_summary(), 700, UiKit.SUN))
	push("blocked", m[0], true)
	Sfx.play("fail")


func open_pause() -> void:
	var m = _modal(Vector2(520, 0), UiKit.CREAM, 0.55)
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.title("Пауза", 44))
	v.add_child(UiKit.label(world.story.chapter_title(), 22, UiKit.TURQ_D, false, HORIZONTAL_ALIGNMENT_CENTER))
	var b = UiKit.button("Продолжить", func(): close_named("pause"), 460)
	v.add_child(b)
	v.add_child(UiKit.button("Настройки", func(): open_settings(), 460, UiKit.TURQ))
	v.add_child(UiKit.button("Управление", func(): open_controls(), 460, Color("e8dcc4")))
	v.add_child(UiKit.button("Сохранить и выйти в меню", func():
		Game.save_game()
		get_tree().paused = false
		world.to_menu(), 460, UiKit.CORAL))
	push("pause", m[0], true)
	b.grab_focus.call_deferred()


func open_controls() -> void:
	var t = "Движение — WASD / стик · Ускорение — Shift · Тормоз — пробел\nДействие — E · Сесть/слезть — F · Телефон «Хоп!» — Tab\nПозвонить клиенту — C · Замок — L · Звонок/гудок — R\nПредмет из сумки — X · Камера — мышь, V — сброс · Пауза — Esc"
	if Game.is_touch():
		t = "Левый стик — движение (дальше от центра — быстрее).\nСвайп справа — камера. Кнопки: действие, сесть/слезть, тормоз, телефон, звонок, предмет."
	open_dialog("Управление", t, [["Понятно", func(): pass]])


func open_settings() -> void:
	var m = _modal(Vector2(700, 0), UiKit.CREAM, 0.5)
	var v: VBoxContainer = m[1]
	v.add_child(UiKit.title("Настройки", 40))
	for k in [["music", "Музыка"], ["sfx", "Звуки"], ["mouse_sens", "Чувствительность мыши"]]:
		var key: String = k[0]
		var row = UiKit.hbox(10)
		var l = UiKit.label(k[1], 22)
		l.custom_minimum_size = Vector2(300, 0)
		row.add_child(l)
		var s = HSlider.new()
		s.custom_minimum_size = Vector2(320, 30)
		s.min_value = 0.02 if key == "mouse_sens" else 0.0
		s.max_value = 0.8 if key == "mouse_sens" else 1.0
		s.step = 0.01
		s.value = float(Game.settings[key])
		s.value_changed.connect(func(x): Game.settings[key] = x; Sfx.refresh_volume())
		row.add_child(s)
		v.add_child(row)
	for k in [["invert_y", "Инвертировать камеру по вертикали"], ["shadows", "Тени"], ["fullscreen", "Полный экран"]]:
		var key: String = k[0]
		var cb = CheckBox.new()
		cb.text = k[1]
		cb.button_pressed = bool(Game.settings[key])
		cb.toggled.connect(func(x):
			Game.settings[key] = x
			if key == "shadows" and world.daynight:
				world.daynight.apply_quality())
		v.add_child(cb)
	var qr = UiKit.hbox(8)
	qr.add_child(UiKit.label("Графика:", 22))
	for opt in [[0, "Низкая"], [1, "Средняя"], [2, "Высокая"]]:
		var qid: int = opt[0]
		qr.add_child(UiKit.button(opt[1], func():
			Game.settings["quality"] = qid
			Game.settings["quality_set"] = true
			world.daynight.apply_quality()
			Game.save_settings()
			close_named("settings")
			open_settings(), 150, UiKit.TURQ if int(Game.settings["quality"]) == qid else Color("e8dcc4")))
	v.add_child(qr)
	var tr = UiKit.hbox(8)
	tr.add_child(UiKit.label("Сенсорное управление:", 22))
	for opt in [["auto", "Авто"], ["on", "Вкл"], ["off", "Выкл"]]:
		var oid: String = opt[0]
		tr.add_child(UiKit.button(opt[1], func(): Game.settings["touch"] = oid; Game.save_settings(); close_named("settings"); open_settings(), 110, UiKit.TURQ if Game.settings["touch"] == oid else Color("e8dcc4")))
	v.add_child(tr)
	v.add_child(UiKit.button("Готово", func(): Game.save_settings(); close_named("settings"), 640))
	push("settings", m[0], true)
