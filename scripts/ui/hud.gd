class_name Hud
extends Control
## Gameplay HUD in the concept/ui/hud.png style: money + rating, clock + timer, minimap, gauges, food meters,
## interaction prompt, toasts and banners.

var world: Node
var money_l: Label
var rating_l: Label
var clock_l: Label
var obj_l: Label
var prompt: PanelContainer
var prompt_l: Label
var toasts: VBoxContainer
var banner_p: PanelContainer
var banner_t: Label
var banner_b: Label
var banner_time = 0.0
var bars = {}
var food_box: VBoxContainer
var minimap: Control
var speed_l: Label
var weather_l: Label
var _food_t = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiKit.theme()
	# top-left: money + rating
	var tl = UiKit.panel(Vector2(0, 0), Color(1, 1, 1, 0.92))
	tl.position = Vector2(18, 16)
	tl.add_theme_stylebox_override("panel", UiKit.box(Color(UiKit.CREAM, 0.94), UiKit.INK, 4, 22, 10))
	var tlv = UiKit.vbox(2)
	tl.add_child(tlv)
	money_l = UiKit.label("● 0", 34, Color("c98a00"))
	rating_l = UiKit.label("★ 4.0", 26, UiKit.INK)
	tlv.add_child(money_l)
	tlv.add_child(rating_l)
	add_child(tl)
	# top-centre: clock + objective
	var tc = VBoxContainer.new()
	tc.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tc.position = Vector2(-420, 12)
	tc.custom_minimum_size = Vector2(840, 0)
	tc.alignment = BoxContainer.ALIGNMENT_BEGIN
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tc)
	var ch = HBoxContainer.new()
	ch.alignment = BoxContainer.ALIGNMENT_CENTER
	ch.add_theme_constant_override("separation", 18)
	clock_l = UiKit.hud_label("08:00", 36)
	weather_l = UiKit.hud_label("", 26, Color("bfe3f5"))
	ch.add_child(clock_l)
	ch.add_child(weather_l)
	tc.add_child(ch)
	obj_l = UiKit.hud_label("", 22, Color("fff3c4"))
	obj_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	obj_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tc.add_child(obj_l)
	toasts = VBoxContainer.new()
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	toasts.add_theme_constant_override("separation", 6)
	tc.add_child(toasts)
	# top-right: minimap
	minimap = Minimap.new()
	minimap.world = world
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(-250, 16)
	minimap.custom_minimum_size = Vector2(232, 232)
	minimap.size = Vector2(232, 232)
	add_child(minimap)
	# bottom-left gauges
	var bl = UiKit.panel(Vector2(0, 0))
	bl.add_theme_stylebox_override("panel", UiKit.box(Color(UiKit.CREAM, 0.9), UiKit.INK, 4, 22, 12))
	bl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bl.position = Vector2(18, -214)
	var blv = UiKit.vbox(6)
	bl.add_child(blv)
	for k in [["battery", "Самокат", Color("3bd16a")], ["stamina", "Силы", Color("f6c945")], ["hunger", "Сытость", Color("ef8f3a")], ["phone", "Телефон", Color("7ec3e8")]]:
		var row = UiKit.hbox(8)
		var l = UiKit.label(k[1], 18)
		l.custom_minimum_size = Vector2(92, 0)
		row.add_child(l)
		var b = UiKit.bar(1.0, k[2], 150, 18)
		row.add_child(b)
		blv.add_child(row)
		bars[k[0]] = [row, b]
	speed_l = UiKit.label("", 18, Color("5d6670"))
	blv.add_child(speed_l)
	add_child(bl)
	# bottom-right: carried food
	food_box = VBoxContainer.new()
	food_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	food_box.position = Vector2(-330, -260)
	food_box.custom_minimum_size = Vector2(310, 0)
	food_box.alignment = BoxContainer.ALIGNMENT_END
	food_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(food_box)
	# prompt
	prompt = PanelContainer.new()
	prompt.add_theme_stylebox_override("panel", UiKit.box(Color(UiKit.TURQ, 0.95), UiKit.INK, 4, 20, 10))
	prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.position = Vector2(-300, -150)
	prompt.custom_minimum_size = Vector2(600, 0)
	prompt_l = UiKit.label("", 24, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	prompt_l.add_theme_constant_override("outline_size", 6)
	prompt_l.add_theme_color_override("font_outline_color", UiKit.INK)
	prompt.add_child(prompt_l)
	prompt.visible = false
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompt)
	# banner
	banner_p = PanelContainer.new()
	banner_p.add_theme_stylebox_override("panel", UiKit.box(UiKit.SUN, UiKit.INK, 5, 26, 18))
	banner_p.set_anchors_preset(Control.PRESET_CENTER)
	banner_p.position = Vector2(-380, -250)
	banner_p.custom_minimum_size = Vector2(760, 0)
	var bv = UiKit.vbox(6)
	banner_t = UiKit.title("", 38)
	banner_b = UiKit.label("", 24, UiKit.INK, true, HORIZONTAL_ALIGNMENT_CENTER)
	bv.add_child(banner_t)
	bv.add_child(banner_b)
	banner_p.add_child(bv)
	banner_p.visible = false
	banner_p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner_p)
	if Game.is_touch():
		bl.position.y = -330
		bl.scale = Vector2(0.85, 0.85)


func _process(delta: float) -> void:
	if world == null or not world.started:
		return
	visible = world.screens.top_name() in ["", "phone"] or true
	money_l.text = "● " + Game.money_text()
	var r = float(Game.state["rating"])
	rating_l.text = "%s %.1f" % [UiKit.stars(r), r]
	rating_l.add_theme_color_override("font_color", UiKit.INK if r >= 3.0 else UiKit.CORAL)
	clock_l.text = "День %d · %s" % [int(Game.state["day"]), world.daynight.clock_text()]
	var w = ""
	if world.daynight.rain > 0.4:
		w = "☂ дождь"
	elif world.daynight.heat > 0.5:
		w = "☀ жара"
	elif world.daynight.is_night():
		w = "☾ ночь"
	weather_l.text = w
	var tgt: Dictionary = world.gps_target
	var obj: String = world.story.objective()
	if not tgt.is_empty() and tgt.has("order"):
		var o: Dictionary = tgt["order"]
		var tl: float = world.orders.time_left(o)
		var tm = "%d:%02d" % [int(abs(tl)) / 60, int(abs(tl)) % 60]
		obj = ("➜ %s · %s %s" % [tgt["label"], "опоздание" if tl < 0 else "осталось", tm])
		if tgt["kind"] == "door":
			obj += " · этаж %d" % int(o["floor"])
	obj_l.text = obj
	var p: Player = world.player
	var show_bat: bool = p.mode == Player.Mode.SCOOTER or (not world.parked.is_empty() and world.parked["kind"] == "scooter")
	bars["battery"][0].visible = show_bat
	bars["battery"][1].value = world.battery / 100.0
	bars["stamina"][1].value = p.stamina / 100.0
	bars["hunger"][1].value = 1.0 - p.hunger / 100.0
	bars["phone"][1].value = p.phone / 100.0
	speed_l.text = "%d км/ч%s" % [int(abs(p.speed) * 3.6), "  · прокол!" if world.events.flat else ""]
	# prompt
	var f: Dictionary = world.focus
	if not f.is_empty() and world.ui_free():
		prompt.visible = true
		var key = "E" if f.get("kind", "") != "vehicle" else "F"
		prompt_l.text = ("Нажми " + key + " — " if not Game.is_touch() else "") + String(f["text"])
	else:
		prompt.visible = false
	banner_time -= delta
	if banner_time <= 0.0:
		banner_p.visible = false
	_food_t -= delta
	if _food_t <= 0.0:
		_food_t = 0.25
		_update_food()


func refresh_orders() -> void:
	_food_t = 0.0


func _update_food() -> void:
	for c in food_box.get_children():
		c.queue_free()
	for o in world.orders.active:
		var pnl = PanelContainer.new()
		pnl.add_theme_stylebox_override("panel", UiKit.box(Color(UiKit.CREAM, 0.92), UiKit.INK, 4, 18, 10))
		var v = UiKit.vbox(4)
		pnl.add_child(v)
		var st = {"to_restaurant": "→ ресторан", "waiting": "готовится", "carrying": "в сумке"}.get(o["state"], "")
		v.add_child(UiKit.label("%s · %s" % [o["item"][1], st], 20))
		if o["state"] == "carrying":
			var row = UiKit.hbox(6)
			row.add_child(UiKit.label("Целость", 16))
			row.add_child(UiKit.bar(o["condition"] / 100.0, Color("8fd3b0") if o["condition"] > 60 else UiKit.CORAL, 110, 14))
			v.add_child(row)
			var k: String = o["item"][2]
			if k in ["hot", "frozen", "cold", "drink_hot"]:
				var row2 = UiKit.hbox(6)
				row2.add_child(UiKit.label("Горячее" if k in ["hot", "drink_hot"] else "Холод", 16))
				row2.add_child(UiKit.bar(o["temp"] / 100.0, Color("ef6a5b") if k in ["hot", "drink_hot"] else Color("7ec3e8"), 110, 14))
				v.add_child(row2)
			if o["wet"] > 10.0:
				v.add_child(UiKit.label("Промокло: %d%%" % int(o["wet"]), 16, Color("3f7fc9")))
		elif o["state"] == "waiting" or o["state"] == "to_restaurant":
			if o["cook_left"] > 0.5:
				v.add_child(UiKit.label("Кухня: ещё %d с" % int(o["cook_left"]), 16, Color("5d6670")))
			else:
				v.add_child(UiKit.label("Готово, забирай!", 16, Color("17807b")))
		food_box.add_child(pnl)


func toast(text: String, secs = 2.5) -> void:
	var p = PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.box(Color(0.13, 0.14, 0.2, 0.86), UiKit.TURQ, 3, 16, 8))
	var l = UiKit.label(text, 22, UiKit.CREAM, true, HORIZONTAL_ALIGNMENT_CENTER)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.add_child(p)
	while toasts.get_child_count() > 3:
		toasts.get_child(0).queue_free()
		toasts.remove_child(toasts.get_child(0))
	var tw = p.create_tween()
	tw.tween_interval(secs)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


func banner(title: String, text: String) -> void:
	banner_t.text = title
	banner_b.text = text
	banner_p.visible = true
	banner_time = 4.5
	Sfx.play("notify", 0.5)


class Minimap:
	extends Control
	var world: Node
	var span = 110.0   # metres shown edge to edge

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if world == null or world.level == null or world.level.map_tex == null:
			return
		var sz = size
		draw_style_box(UiKit.box(Color(UiKit.CREAM, 0.95), UiKit.INK, 4, 26, 0), Rect2(Vector2.ZERO, sz))
		var lv: Level = world.level
		var mr: Rect2 = lv.map_rect
		var tex: Texture2D = lv.map_tex
		var pp: Vector3 = world.player.global_position
		var ts = Vector2(tex.get_width(), tex.get_height())
		var ppx = Vector2((pp.x - mr.position.x) / mr.size.x, (pp.z - mr.position.y) / mr.size.y) * ts
		var half = span / mr.size.x * ts.x * 0.5
		var src = Rect2(ppx - Vector2(half, half), Vector2(half, half) * 2.0)
		var inner = Rect2(Vector2(8, 8), sz - Vector2(16, 16))
		draw_texture_rect_region(tex, inner, src)
		var to_ui = func(p: Vector3) -> Vector2:
			var t = Vector2((p.x - mr.position.x) / mr.size.x, (p.z - mr.position.y) / mr.size.y) * ts
			return inner.position + (t - src.position) / src.size * inner.size
		var path: PackedVector3Array = world.gps_path()
		if path.size() > 1:
			var pts = PackedVector2Array()
			for q in path:
				pts.append(to_ui.call(q))
			draw_polyline(pts, Color(0.15, 0.85, 0.45), 4.0, true)
		var tgt: Dictionary = world.gps_target
		if not tgt.is_empty():
			var tp: Vector2 = to_ui.call(tgt["pos"])
			tp = tp.clamp(inner.position + Vector2(6, 6), inner.end - Vector2(6, 6))
			draw_circle(tp, 8.0, Color("ef6a5b"))
			draw_arc(tp, 8.0, 0, TAU, 16, UiKit.INK, 2.0)
		var c: Vector2 = to_ui.call(pp)
		var h: float = world.player.heading
		var f = Vector2(sin(h), cos(h))
		var r = Vector2(-f.y, f.x)
		var tri = PackedVector2Array([c + f * 11.0, c - f * 7.0 + r * 7.0, c - f * 7.0 - r * 7.0])
		draw_colored_polygon(tri, UiKit.TURQ)
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), UiKit.INK, 2.0)
		draw_string(get_theme_default_font(), Vector2(sz.x * 0.5 - 6, 26), "С", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiKit.INK)
