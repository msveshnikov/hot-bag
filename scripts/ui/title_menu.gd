class_name TitleMenu
extends Control
## Title screen: the painted key art drifting slowly, a big outlined logo with a steaming thermal bag,
## chunky 3D-looking buttons with drawn icons that slide in and swell on hover/focus, floating sunset motes.

signal started

const BTN_W = 480.0
const LOGO_AT = Vector2(64, 30)

var bg: TextureRect
var logo: Control
var buttons: Array[Button] = []
var pill: PanelContainer
var intro := 0.0
var has_save := false
var modal: Control
var t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	theme = UiKit.theme()
	bg = TextureRect.new()
	bg.texture = load("res://assets/ui/title.jpg")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)
	_shade(Vector2(1, 0), [Color(0.04, 0.13, 0.17, 0.82), Color(0.04, 0.13, 0.17, 0.5), Color(0.04, 0.13, 0.17, 0.0)], [0.0, 0.34, 0.62])
	_shade(Vector2(0, 1), [Color(0.04, 0.1, 0.14, 0.0), Color(0.04, 0.1, 0.14, 0.0), Color(0.04, 0.1, 0.14, 0.55)], [0.0, 0.7, 1.0])
	var motes = Motes.new()
	motes.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(motes)
	_build_logo()
	_build_buttons()
	pill = PanelContainer.new()
	var ps = UiKit.box(Color(0.98, 0.95, 0.88, 0.9), UiKit.INK, 3, 18, 8)
	ps.content_margin_left = 16
	ps.content_margin_right = 16
	pill.add_theme_stylebox_override("panel", ps)
	var vl = _text("v%s  ·  главы 1–5" % Game.VERSION, 20, 600, UiKit.INK)
	pill.add_child(vl)
	add_child(pill)
	resized.connect(_layout)
	_layout.call_deferred()
	_intro()


func _shade(dir: Vector2, cols: Array, offs: Array) -> void:
	var g = Gradient.new()
	g.colors = PackedColorArray(cols)
	g.offsets = PackedFloat32Array(offs)
	var gt = GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2.ZERO
	gt.fill_to = dir
	gt.width = 256 if dir.x > 0 else 4
	gt.height = 256 if dir.y > 0 else 4
	var r = TextureRect.new()
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(r)


func _text(s: String, size: int, weight: int, col: Color, outline := 0, shadow := 0) -> Label:
	var l = Label.new()
	l.text = s
	l.add_theme_font_override("font", UiKit.font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", UiKit.INK)
	if shadow > 0:
		l.add_theme_color_override("font_shadow_color", Color(0.12, 0.1, 0.14, 0.95))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", shadow)
		l.add_theme_constant_override("shadow_outline_size", outline)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l


func _build_logo() -> void:
	logo = Control.new()
	logo.mouse_filter = MOUSE_FILTER_IGNORE
	logo.size = Vector2(820, 360)
	logo.pivot_offset = Vector2(300, 200)
	add_child(logo)
	var l1 = _text("ГОРЯЧАЯ", 104, 900, Color("fff6d8"), 26, 9)
	l1.position = Vector2(14, 0)
	logo.add_child(l1)
	var l2 = _text("СУМКА", 164, 900, UiKit.SUN, 30, 12)
	l2.position = Vector2(0, 86)
	logo.add_child(l2)
	var w2 = UiKit.font(900).get_string_size("СУМКА", HORIZONTAL_ALIGNMENT_LEFT, -1, 164).x
	var bag = Bag.new()
	bag.size = Vector2(150, 170)
	bag.position = Vector2(w2 + 34, 70)
	bag.rotation = deg_to_rad(8)
	logo.add_child(bag)
	var rib = PanelContainer.new()
	var rs = UiKit.box(UiKit.CORAL, UiKit.INK, 5, 16, 6)
	rs.content_margin_left = 22
	rs.content_margin_right = 22
	rs.shadow_color = Color(0.12, 0.1, 0.14, 0.9)
	rs.shadow_size = 1
	rs.shadow_offset = Vector2(0, 6)
	rib.add_theme_stylebox_override("panel", rs)
	var rl = _text("СИМУЛЯТОР КУРЬЕРА", 32, 800, Color.WHITE, 8)
	var fv = UiKit.font(800).duplicate()
	fv.spacing_glyph = 3
	rl.add_theme_font_override("font", fv)
	rib.add_child(rl)
	rib.position = Vector2(30, 276)
	rib.rotation = deg_to_rad(-2)
	logo.add_child(rib)
	var sub = _text("четыре района большого города — на велике, самокате и мопеде", 23, 600, Color("fff6d8"), 8)
	sub.position = Vector2(40, 342)
	logo.add_child(sub)


func _build_buttons() -> void:
	has_save = Game.has_save() or Game.flag("menushot")
	var has = has_save
	if has:
		var st = Game.state
		var sub = "день %d  ·  %s" % [int(st["day"]), Game.district_title()]
		_button("Продолжить", sub, "play", UiKit.SUN, func(): started.emit())
	_button("Новая игра", "" if has else "первая смена в Старом городе", "new",
		Color("fbf3e2") if has else UiKit.SUN, _new_game)
	_button("Настройки", "", "gear", Color("fbf3e2"), _settings)
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		_button("Выход", "", "exit", Color("e8dcc4"), func(): get_tree().quit())
	for i in buttons.size():
		var b = buttons[i]
		b.focus_neighbor_top = b.get_path_to(buttons[(i - 1 + buttons.size()) % buttons.size()])
		b.focus_neighbor_bottom = b.get_path_to(buttons[(i + 1) % buttons.size()])
	buttons[0].grab_focus.call_deferred()


func _button(title: String, sub: String, icon: String, col: Color, cb: Callable) -> Button:
	var b = Button.new()
	b.custom_minimum_size = Vector2(BTN_W, 104 if sub != "" else 86)
	b.size = b.custom_minimum_size
	var states = {"normal": col, "hover": col.lightened(0.12), "pressed": col.darkened(0.1), "focus": col}
	for k in states:
		var s = UiKit.box(states[k], UiKit.INK, 5, 26, 0)
		s.shadow_color = Color(0.12, 0.1, 0.14, 0.92)
		s.shadow_size = 1
		s.shadow_offset = Vector2(0, 3 if k == "pressed" else 8)
		if k == "focus":
			s.bg_color = Color(0, 0, 0, 0)
			s.border_color = Color.WHITE
			s.set_border_width_all(4)
			s.set_expand_margin_all(6)
			s.shadow_size = 0
		b.add_theme_stylebox_override(k, s)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	row.offset_left = 18
	row.offset_right = -20
	row.mouse_filter = MOUSE_FILTER_IGNORE
	b.add_child(row)
	var ic = BtnIcon.new()
	ic.kind = icon
	ic.glyph = col.lightened(0.25) if col.get_luminance() < 0.8 else UiKit.SUN
	ic.custom_minimum_size = Vector2(60, 60)
	ic.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(ic)
	var tv = VBoxContainer.new()
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.size_flags_horizontal = SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", -4)
	tv.mouse_filter = MOUSE_FILTER_IGNORE
	tv.add_child(_text(title, 40, 800, UiKit.INK))
	if sub != "":
		var sl = _text(sub, 21, 500, Color(0.18, 0.16, 0.2, 0.78))
		sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sl.custom_minimum_size.x = 40
		tv.add_child(sl)
	row.add_child(tv)
	var ch = BtnIcon.new()
	ch.kind = "chev"
	ch.custom_minimum_size = Vector2(26, 40)
	ch.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(ch)
	b.mouse_entered.connect(func(): b.grab_focus())
	b.focus_entered.connect(func(): _hover(b, ch, true))
	b.focus_exited.connect(func(): _hover(b, ch, false))
	b.button_down.connect(func(): create_tween().tween_property(b, "scale", Vector2(0.97, 0.97), 0.06))
	b.button_up.connect(func(): create_tween().tween_property(b, "scale", Vector2(1.05, 1.05), 0.1))
	b.pressed.connect(func(): Sfx.play("ui"); cb.call())
	b.modulate.a = 0.0
	add_child(b)
	buttons.append(b)
	return b


func _hover(b: Button, ch: Control, on: bool) -> void:
	var tw = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "scale", Vector2.ONE * (1.05 if on else 1.0), 0.22)
	tw.tween_property(ch, "nudge", 8.0 if on else 0.0, 0.22)
	if on and intro > 0.9:
		Sfx.play("ui", 0.25, 1.7)


func _intro() -> void:
	var tw = create_tween()
	tw.tween_property(self, "intro", 1.0, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in buttons.size():
		var b = buttons[i]
		var bt = create_tween().set_parallel()
		bt.tween_property(b, "modulate:a", 1.0, 0.3).set_delay(0.35 + i * 0.08)
		bt.tween_method(func(k): b.set_meta("in", k), 0.0, 1.0, 0.5).set_delay(0.35 + i * 0.08) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		b.set_meta("in", 0.0)
	pill.modulate.a = 0.0
	create_tween().tween_property(pill, "modulate:a", 1.0, 0.6).set_delay(0.8)


func _layout() -> void:
	var oy = maxf(0.0, (size.y - 900.0) * 0.5)
	var ox = maxf(0.0, (size.x - 1600.0) * 0.12)
	set_meta("o", Vector2(ox, oy))
	var y = 432.0 + oy
	for b in buttons:
		b.set_meta("y", y)
		b.pivot_offset = Vector2(0, b.size.y * 0.5)
		y += b.size.y + 16
	pill.position = size - pill.get_combined_minimum_size() - Vector2(28, 24)
	_place(0.0)


func _process(delta: float) -> void:
	t += delta
	# slow drift of the key art: always zoomed enough that its edges never show
	var s = 1.06 + 0.03 * sin(t * 0.11)
	bg.size = size
	bg.pivot_offset = size * 0.5
	bg.scale = Vector2(s, s)
	bg.position = Vector2(sin(t * 0.07) * 14.0, cos(t * 0.09) * 8.0)
	_place(delta)


func _place(_d: float) -> void:
	var o: Vector2 = get_meta("o", Vector2.ZERO)
	logo.position = LOGO_AT + o + Vector2(0, (1.0 - intro) * -420.0 + sin(t * 1.5) * 5.0)
	logo.rotation = deg_to_rad(-3.0 + sin(t * 0.8) * 0.7)
	for b in buttons:
		var k: float = b.get_meta("in", 1.0)
		b.position = Vector2(80.0 + o.x - (1.0 - k) * 120.0, b.get_meta("y", 400.0))


func _new_game() -> void:
	if not has_save:
		started.emit()
		return
	var m = _modal()
	var v = m.get_meta("box")
	v.add_child(_text("Начать заново?", 46, 800, UiKit.INK))
	var l = UiKit.label("Сохранённая игра (день %d) будет удалена, и смена начнётся с первого дня." % int(Game.state["day"]), 24, UiKit.INK, true)
	l.custom_minimum_size = Vector2(560, 0)
	v.add_child(l)
	var row = UiKit.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var yes = UiKit.button("Да, заново", func():
		Game.delete_save()
		m.queue_free()
		started.emit(), 260, UiKit.CORAL)
	row.add_child(yes)
	var no = UiKit.button("Отмена", func(): m.queue_free(); buttons[0].grab_focus(), 220, Color("e8dcc4"))
	row.add_child(no)
	v.add_child(row)
	no.grab_focus.call_deferred()


func _modal() -> Control:
	var m = Control.new()
	m.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	UiKit.dim(m, 0.55)
	var p = UiKit.panel(Vector2(640, 0))
	UiKit.center(m, p)
	var v = UiKit.vbox(16)
	p.add_child(v)
	m.set_meta("box", v)
	add_child(m)
	modal = m
	p.pivot_offset = Vector2(320, 150)
	p.scale = Vector2(0.85, 0.85)
	create_tween().tween_property(p, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return m


func _settings() -> void:
	var m = _modal()
	var first = SettingsPanel.fill(m.get_meta("box"), Callable(), func(): m.queue_free(); buttons[0].grab_focus())
	first.grab_focus.call_deferred()


## The logo's thermal bag: turquoise box with lid, handle and a reflective band, three curls of steam rising.
class Bag extends Control:
	var t := 0.0

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var w = size.x
		var h = size.y
		for i in 3:
			var x0 = w * (0.22 + 0.22 * i)
			var pts = PackedVector2Array()
			var cols = PackedColorArray()
			var shadow = PackedVector2Array()
			var fade = 0.75 + 0.25 * sin(t * 1.3 + i * 2.1)
			for j in 16:
				var f = j / 15.0
				var p = Vector2(x0 + sin(f * 5.5 - t * 3.0 + i * 1.9) * w * 0.06 * (0.3 + f), h * 0.3 - f * h * 0.42)
				pts.append(p)
				shadow.append(p + Vector2(2, 3))
				cols.append(Color(1, 1, 1, (1.0 - f) * 0.95 * fade))
			draw_polyline(shadow, Color(0.12, 0.1, 0.14, 0.1 * fade), 11.0, true)
			draw_polyline_colors(pts, cols, 10.0, true)
		# boxy thermal backpack seen 3/4: front face, lighter top, side strip, carry strap, reflective band
		var body = Rect2(w * 0.06, h * 0.36, w * 0.88, h * 0.6)
		var strap = UiKit.box(UiKit.TURQ_D, UiKit.INK, 5, 8, 0)
		strap.shadow_size = 0
		draw_style_box(strap, Rect2(w * 0.32, h * 0.27, w * 0.36, h * 0.13))
		var sb = UiKit.box(UiKit.TURQ, UiKit.INK, 6, 14, 0)
		sb.shadow_color = Color(0.12, 0.1, 0.14, 0.9)
		sb.shadow_size = 1
		sb.shadow_offset = Vector2(0, 7)
		draw_style_box(sb, body)
		var lid = UiKit.box(Color("2fd0c6"), UiKit.INK, 6, 14, 0)
		lid.shadow_size = 0
		draw_style_box(lid, Rect2(body.position, Vector2(body.size.x, body.size.y * 0.3)))
		draw_rect(Rect2(body.position.x + 6, body.position.y + body.size.y * 0.56, body.size.x - 12, body.size.y * 0.14), Color("fbf3e2"))
		draw_rect(Rect2(body.position.x + 6, body.position.y + body.size.y * 0.56 + body.size.y * 0.14, body.size.x - 12, 3), Color(0.12, 0.1, 0.14, 0.35))
		draw_circle(body.position + Vector2(body.size.x * 0.5, body.size.y * 0.3), 6.0, UiKit.INK)
		draw_rect(Rect2(body.position.x + body.size.x * 0.12, body.position.y + body.size.y * 0.4, body.size.x * 0.1, body.size.y * 0.1), Color(1, 1, 1, 0.35))


## Drawn button icons in an ink disc: play, new (sparkle), gear, exit; "chev" is the right-hand chevron.
class BtnIcon extends Control:
	var kind := "play"
	var glyph := Color.WHITE
	var nudge := 0.0:
		set(v):
			nudge = v
			queue_redraw()

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c = size * 0.5
		var r = minf(size.x, size.y) * 0.5
		if kind == "chev":
			var x = c.x - 6 + nudge
			draw_polyline(PackedVector2Array([Vector2(x - 6, c.y - 13), Vector2(x + 7, c.y), Vector2(x - 6, c.y + 13)]),
				UiKit.INK, 7.0, true)
			return
		draw_circle(c, r, UiKit.INK)
		match kind:
			"play":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.28, -r * 0.46), c + Vector2(r * 0.52, 0),
					c + Vector2(-r * 0.28, r * 0.46)]), glyph)
			"new":
				var p = PackedVector2Array()
				for k in 8:
					var a = k * TAU / 8.0 - PI / 2.0
					p.append(c + Vector2(cos(a), sin(a)) * r * (0.64 if k % 2 == 0 else 0.2))
				draw_colored_polygon(p, glyph)
			"gear":
				var p = PackedVector2Array()
				for k in 40:
					var a = (k + 0.5) * TAU / 40.0
					p.append(c + Vector2(cos(a), sin(a)) * r * (0.64 if (k % 5) < 2 else 0.46))
				draw_colored_polygon(p, glyph)
				draw_circle(c, r * 0.2, UiKit.INK)
			"exit":
				draw_rect(Rect2(c + Vector2(-r * 0.5, -r * 0.5), Vector2(r * 0.55, r)), glyph, false, 5.0)
				draw_line(c + Vector2(-r * 0.15, 0), c + Vector2(r * 0.45, 0), glyph, 6.0, true)
				draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.62, 0), c + Vector2(r * 0.3, -r * 0.26),
					c + Vector2(r * 0.3, r * 0.26)]), glyph)


## Soft sunset dust drifting up over the key art.
class Motes extends Control:
	var m: Array = []
	var t := 0.0

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		var rng = RandomNumberGenerator.new()
		rng.seed = 7
		for i in 30:
			m.append([Vector2(rng.randf_range(0.3, 1.0), rng.randf()), rng.randf_range(2.0, 6.0),
				rng.randf_range(0.012, 0.03), rng.randf() * TAU])

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		for e in m:
			var p: Vector2 = e[0]
			var y = fposmod(p.y - t * e[2], 1.1) - 0.05
			var x = p.x + sin(t * 0.4 + e[3]) * 0.012
			var a = 0.12 + 0.12 * sin(t * 1.2 + e[3])
			draw_circle(Vector2(x * size.x, y * size.y), e[1] * 2.2, Color(1, 0.9, 0.7, a * 0.35))
			draw_circle(Vector2(x * size.x, y * size.y), e[1], Color(1, 0.96, 0.85, a))
