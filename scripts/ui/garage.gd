class_name GarageScreen
extends Control
## The mechanic's workshop (concept/ui/garage_shop.png): painted workshop background, the chosen vehicle (or the
## courier) turning on the glowing podium in a transparent SubViewport, item tiles with icons, level pips and coin
## prices on both sides, an info panel with one big action button at the bottom. Icons: assets/ui/icons/<id>.png
## (sliced from concept/ui/icon_sheet.png by tools/slice_icons.py).

const TABS = [["vehicle", "Транспорт"], ["upgrades", "Улучшения"], ["gear", "Экипировка"], ["look", "Внешность"]]
const VEHICLES = ["bicycle", "ebike", "scooter", "moped", "ecar"]
const UPGRADES = ["battery", "motor", "tires", "brakes", "rack", "lock", "headlight", "mudguards"]
const GEAR = ["raincoat", "waterproof_bag", "cooling_pack", "cup_holder", "soft_bag", "warm_gloves", "helmet_bike",
	"helmet_half", "helmet_retro"]
const TILE = Vector2(168, 176)
const GREEN = Color("5ccf3c")
const TEAL = Color("2bb8b3")
const TEAL_D = Color("137a75")

static var tab = "vehicle"
static var selected = {}            # tab -> item id

var world: Node
var screens: Node
var preview_root: Node3D
var preview_cam: Camera3D
var spin = 0.0
var info_name: Label
var info_desc: Label
var action_btn: Button
var extra_box: HBoxContainer
var _icons = {}


func _ready() -> void:
	UiKit.full(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg = TextureRect.new()
	bg.texture = load("res://assets/ui/garage_bg.jpg")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	UiKit.full(bg)
	add_child(bg)
	_build_preview()
	_build_top()
	_build_grids()
	_build_info()
	_select(selected.get(tab, _items()[0]))


# ---------------------------------------------------------------- layout
func _build_top() -> void:
	var coin = PanelContainer.new()
	coin.add_theme_stylebox_override("panel", UiKit.box(UiKit.CREAM, TEAL_D, 5, 30, 10))
	var ch = UiKit.hbox(10)
	ch.add_child(_icon_rect("coins", 46))
	ch.add_child(UiKit.label(Game.money_text(), 38, UiKit.INK))
	coin.add_child(ch)
	coin.position = Vector2(24, 18)
	add_child(coin)
	var tabs = UiKit.hbox(8)
	for t in TABS:
		var id: String = t[0]
		var b = UiKit.button(t[1], func(): _switch(id), 176, TEAL if tab == id else UiKit.CREAM)
		tabs.add_child(b)
	tabs.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tabs.position = Vector2(-370, 20)
	tabs.size = Vector2(740, 58)
	add_child(tabs)
	var close = UiKit.button("✕", func(): screens.close_named("garage"), 64, UiKit.CORAL)
	close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close.position = Vector2(-88, 20)
	add_child(close)


func _items() -> Array:
	match tab:
		"vehicle":
			return VEHICLES
		"upgrades":
			return UPGRADES
		"gear":
			return GEAR
	var bags = []
	for c in Game.BAGS:
		bags.append("bag" + c)
	return ["g_m", "g_f", "h_short", "h_ponytail", "h_curly", "h_bun"] + bags + Game.JACKETS + ["cap"]


func _build_grids() -> void:
	var items = _items()
	var half = int(ceil(items.size() / 2.0))
	if tab == "look":
		half = 6 + Game.BAGS.size()
	for side in 2:
		var grid = GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		var part = items.slice(0, half) if side == 0 else items.slice(half)
		for id in part:
			grid.add_child(_tile(id))
		if side == 0:
			grid.position = Vector2(24, 104)
		else:
			grid.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			grid.position = Vector2(-24 - TILE.x * 2 - 12, 104)
		add_child(grid)


func _build_info() -> void:
	var p = PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.box(Color(UiKit.CREAM, 0.95), TEAL_D, 5, 28, 14))
	p.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	p.custom_minimum_size = Vector2(700, 0)
	p.position = Vector2(-350, -196)
	p.size = Vector2(700, 180)
	var v = UiKit.vbox(6)
	info_name = UiKit.label("", 30, TEAL_D, false, HORIZONTAL_ALIGNMENT_CENTER)
	info_desc = UiKit.label("", 19, Color("4d5660"), true, HORIZONTAL_ALIGNMENT_CENTER)
	info_desc.custom_minimum_size = Vector2(660, 0)
	v.add_child(info_name)
	v.add_child(info_desc)
	var row = UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_btn = UiKit.button("", func(): _act(), 380, GREEN)
	action_btn.add_theme_font_size_override("font_size", 26)
	action_btn.icon = _tex("tools")
	action_btn.expand_icon = false
	action_btn.add_theme_constant_override("icon_max_width", 40)
	row.add_child(action_btn)
	extra_box = UiKit.hbox(8)
	row.add_child(extra_box)
	v.add_child(row)
	p.add_child(v)
	add_child(p)


# ---------------------------------------------------------------- tiles
func _tex(id: String) -> Texture2D:
	if not _icons.has(id):
		var path = "res://assets/ui/icons/%s.png" % id
		_icons[id] = load(path) if ResourceLoader.exists(path) else null
	return _icons[id]


func _icon_rect(id: String, s: float) -> TextureRect:
	var t = TextureRect.new()
	t.texture = _tex(id)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(s, s)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _tile(id: String) -> Button:
	var b = Button.new()
	b.custom_minimum_size = TILE if tab != "look" else Vector2(TILE.x, 120)
	var sel: bool = selected.get(tab, "") == id
	var col = TEAL
	if tab == "look" and id.begins_with("#"):
		col = Color(id)
	if tab == "look" and id.begins_with("bag#"):
		col = Color(id.substr(3))
	var st = UiKit.box(col, UiKit.SUN if sel else TEAL_D, 7 if sel else 5, 26, 6)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", UiKit.box(col.lightened(0.12), UiKit.SUN, 6, 26, 6))
	b.add_theme_stylebox_override("pressed", UiKit.box(col.darkened(0.1), UiKit.SUN, 7, 26, 6))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func(): Sfx.play("ui"); _select(id))
	var v = VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	UiKit.full(v)
	b.add_child(v)
	if tab == "look":
		var txt = _look_text(id)
		var l = UiKit.label(txt, 22, UiKit.WHITE if not id.begins_with("#") or Color(id).get_luminance() < 0.5 else UiKit.INK, true, HORIZONTAL_ALIGNMENT_CENTER)
		l.add_theme_constant_override("outline_size", 6)
		l.add_theme_color_override("font_outline_color", TEAL_D if not id.begins_with("#") else Color(0, 0, 0, 0.25))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
		if _look_active(id):
			v.add_child(_pill("✓ выбрано", false))
		return b
	v.add_child(_icon_rect(id, 96))
	var it: Dictionary = Game.SHOP.get(id, {})
	# level pips for upgrades, a check for owned things
	var pips = HBoxContainer.new()
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.add_theme_constant_override("separation", 4)
	if it.get("kind", "") == "upgrade":
		for k in int(it.get("max", 1)):
			var pip = Panel.new()
			pip.custom_minimum_size = Vector2(22, 16)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pip.add_theme_stylebox_override("panel", UiKit.box(GREEN if k < Game.upgrade_level(id) else Color("9aa3a8"), Color("1d4f4c"), 2, 4, 0))
			pips.add_child(pip)
		v.add_child(pips)
	v.add_child(_pill(_price_text(id), _owned(id) == ""))
	return b


func _pill(text: String, coin: bool) -> PanelContainer:
	var p = PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UiKit.box(UiKit.CREAM, Color("1d4f4c"), 3, 20, 4))
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var h = HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 6)
	if coin:
		h.add_child(_icon_rect("coins", 26))
	var l = UiKit.label(text, 22, UiKit.INK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	p.add_child(h)
	return p


## "" = can be bought; otherwise a short state text (свой / есть / макс.)
func _owned(id: String) -> String:
	if tab == "vehicle":
		if world.current_vehicle() == id:
			return "сейчас"
		return "свой" if Game.state["owned"].get(id, false) else ""
	var it: Dictionary = Game.SHOP[id]
	match it["kind"]:
		"upgrade":
			return "макс." if Game.upgrade_level(id) >= int(it.get("max", 1)) else ""
		"gear", "helmet":
			return ("надет" if Game.state.get("helmet", "") == id else "есть") if Game.has_gear(id) else ""
	return ""


func _price_text(id: String) -> String:
	var o = _owned(id)
	return o if o != "" else "%d" % int(Game.SHOP[id]["price"])


func _look_text(id: String) -> String:
	match id:
		"g_m": return "Парень"
		"g_f": return "Девушка"
		"h_short": return "Короткая"
		"h_ponytail": return "Хвост"
		"h_curly": return "Кудри"
		"h_bun": return "Пучок"
		"cap": return "Кепка: " + ("да" if Game.state["look"].get("cap", true) else "нет")
	if id.begins_with("bag#"):
		return "Сумка" + (" легенды" if id.substr(3) == Game.BAG_GOLD else "")
	return ""


func _look_active(id: String) -> bool:
	var look: Dictionary = Game.state["look"]
	if id.begins_with("g_"):
		return look["gender"] == id.substr(2)
	if id.begins_with("h_"):
		return look["hair"] == id.substr(2)
	if id.begins_with("#"):
		return look["jacket"] == id
	if id.begins_with("bag#"):
		return look.get("bag", Game.BAGS[0]) == id.substr(3)
	return false


# ---------------------------------------------------------------- selection and actions
func _switch(t: String) -> void:
	tab = t
	screens.open_garage(t)


func _select(id: String) -> void:
	if tab == "look":
		_apply_look(id)
		return
	selected[tab] = id
	var it: Dictionary = Game.SHOP.get(id, {})
	if tab == "vehicle" and id == "bicycle":
		it = {"name": "Велосипед", "desc": "Старый друг: скрипит, зато не разряжается. Едет по лестницам и паркам. Педали — это твои силы."}
	info_name.text = it.get("name", id)
	info_desc.text = it.get("desc", "")
	for c in extra_box.get_children():
		c.queue_free()
	var o = _owned(id)
	action_btn.disabled = false
	if tab == "vehicle":
		if o == "сейчас":
			action_btn.text = "Ты на нём"
			action_btn.disabled = true
		elif Game.can_use(id):
			action_btn.text = "Взять"
		else:
			action_btn.text = "Купить — %d" % int(it["price"])
			action_btn.disabled = not Game.can_buy(id)
			if Game.buy_block_reason(id) != "":
				info_desc.text += "  " + Game.buy_block_reason(id)
		if id == "scooter" and not Game.state["owned"].get("scooter", false):
			var rb = UiKit.button("Аренда на день — %d" % Game.SCOOTER_RENT, func(): _rent(), 250, UiKit.SUN)
			rb.disabled = Game.state.get("rented_today", false)
			extra_box.add_child(rb)
		if Game.is_electric(id) and Game.can_use(id):
			info_desc.text += "  Заряд: %d%%." % int(Game.charge_of(id) if world.current_vehicle() != id else world.battery)
		if world.events.flat:
			extra_box.add_child(UiKit.button("Заклеить прокол — 10", func(): _fix_flat(), 250, UiKit.SUN))
	else:
		var helmet = it.get("kind", "") == "helmet" and Game.has_gear(id)
		if helmet:
			action_btn.text = "Снять" if Game.state.get("helmet", "") == id else "Надеть"
		elif o != "":
			action_btn.text = "Уже есть" if o != "макс." else "Максимум"
			action_btn.disabled = true
		else:
			action_btn.text = "Купить — %d" % int(it["price"])
			action_btn.disabled = not Game.can_buy(id)
			if Game.buy_block_reason(id) != "":
				info_desc.text += "  " + Game.buy_block_reason(id)
	_show_preview()
	_refresh_tiles()


func _refresh_tiles() -> void:
	# cheap way to restyle the selection: rebuild the two grids
	for c in get_children():
		if c is GridContainer:
			c.queue_free()
	_build_grids()


func _act() -> void:
	var id: String = selected.get(tab, "")
	if id == "":
		return
	if tab == "vehicle":
		if Game.can_use(id):
			world.swap_vehicle(id)
			Sfx.play("lock")
			screens.open_garage("vehicle")
			return
	var it: Dictionary = Game.SHOP[id]
	if it.get("kind", "") == "helmet" and Game.has_gear(id):
		Game.state["helmet"] = "" if Game.state.get("helmet", "") == id else id
		world.player.apply_look()
		screens.open_garage(tab)
		return
	if Game.buy(id):
		Sfx.play("coin")
		world.story.on_buy(id)
		world.on_bought(id)
		screens.open_garage(tab)
	else:
		Sfx.play("fail")


func _rent() -> void:
	if Game.state["money"] >= Game.SCOOTER_RENT:
		Game.spend(Game.SCOOTER_RENT)
		Game.state["rented_today"] = true
		Sfx.play("coin")
		world.swap_vehicle("scooter")
		screens.open_garage("vehicle")
	else:
		Sfx.play("fail")


func _fix_flat() -> void:
	if Game.state["money"] >= 10:
		Game.spend(10)
		world.events.fix_flat()
		screens.open_garage("vehicle")


func _apply_look(id: String) -> void:
	var look: Dictionary = Game.state["look"]
	if id.begins_with("g_"):
		screens._set_gender(look, id.substr(2))
		world.player.build_model()
	elif id.begins_with("h_"):
		look["hair"] = id.substr(2)
		world.player.build_model()
	elif id.begins_with("#"):
		look["jacket"] = id
		world.player.apply_look()
	elif id == "cap":
		look["cap"] = not look.get("cap", true)
		world.player.apply_look()
	elif id.begins_with("bag#"):
		if id.substr(3) == Game.BAG_GOLD and Game.rank() < Game.RANKS.size() - 1:
			Sfx.play("fail")
			info_name.text = "Золотая термосумка"
			info_desc.text = "Только для звания «Курьер-легенда». Сейчас ты — «%s»." % Game.rank_title()
			return
		look["bag"] = id.substr(3)
		world.player.apply_look()
	info_name.text = "Внешность курьера"
	info_desc.text = "Пол, причёска, цвет куртки и термосумки, кепка. Шлемы — во вкладке «Экипировка»."
	action_btn.text = "Готово"
	action_btn.disabled = false
	selected["look"] = "done"
	for c in extra_box.get_children():
		c.queue_free()
	_show_preview()
	_refresh_tiles()


# ---------------------------------------------------------------- 3D preview on the podium
func _build_preview() -> void:
	var svc = SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	svc.position = Vector2(-360, -660)
	svc.size = Vector2(720, 560)
	add_child(svc)
	var sv = SubViewport.new()
	sv.transparent_bg = true
	sv.own_world_3d = true
	# no MSAA on the Compatibility renderer: it leaks memory in the Mali driver (see DayNight.apply_quality)
	sv.msaa_3d = Viewport.MSAA_DISABLED if RenderingServer.get_current_rendering_method() == "gl_compatibility" else Viewport.MSAA_4X
	sv.size = Vector2i(720, 560)
	svc.add_child(sv)
	var env = WorldEnvironment.new()
	var e = Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("ffe3c2")
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.15
	env.environment = e
	sv.add_child(env)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.6
	sun.light_color = Color("fff1dc")
	sv.add_child(sun)
	var rim = DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.8
	rim.light_color = Color("ffb36b")
	sv.add_child(rim)
	preview_root = Node3D.new()
	sv.add_child(preview_root)
	preview_cam = Camera3D.new()
	preview_cam.fov = 30.0
	sv.add_child(preview_cam)


func _show_preview() -> void:
	for c in preview_root.get_children():
		c.queue_free()
	var n: Node3D
	if tab == "look" or tab == "gear":
		n = _courier_model()
	else:
		var kind = selected.get("vehicle", world.current_vehicle()) if tab == "vehicle" else world.current_vehicle()
		if kind == "":
			kind = "bicycle"
		n = Vehicles.make(kind)
		Vehicles.apply_upgrades(n, kind)
		Vehicles.lights(n, false)
	preview_root.add_child(n)
	# fit the camera to the model: bottom of the model sits on the podium (bottom of the view)
	var box = AABB()
	var first = true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m3: MeshInstance3D = mi
		var bb = m3.get_aabb()
		bb = n.global_transform.affine_inverse() * m3.global_transform * bb
		box = bb if first else box.merge(bb)
		first = false
	var size = max(box.size.x, max(box.size.y, box.size.z))
	n.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var dist = size / tan(deg_to_rad(preview_cam.fov * 0.5)) * 0.62
	preview_cam.position = Vector3(0, box.size.y * 0.55 + dist * 0.18, dist)
	preview_cam.look_at(Vector3(0, box.size.y * 0.42, 0))


func _courier_model() -> Node3D:
	var m = Chars.courier()
	var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
	if ap and ap.has_animation("happy"):
		ap.play("happy")
	return m


func _process(delta: float) -> void:
	spin += delta * 0.6
	if preview_root:
		preview_root.rotation.y = spin
