class_name UiKit
extends RefCounted
## Cheerful flat cartoon UI: rounded thick-outlined turquoise/cream panels, chunky buttons (see concept/ui).

const INK = Color("2f2a33")
const TURQ = Color("22b8b0")
const TURQ_D = Color("137a75")
const CREAM = Color("fbf3e2")
const CORAL = Color("ef6a5b")
const SUN = Color("f6c945")
const MINT = Color("8fd3b0")
const WHITE = Color("ffffff")

static var _theme: Theme


static func box(bg: Color, border = INK, bw = 4, radius = 22, pad = 14) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.shadow_color = Color(0, 0, 0, 0.22)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 4)
	s.anti_aliasing = true
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t = Theme.new()
	t.default_font_size = 24
	var fv = FontVariation.new()
	fv.variation_embolden = 0.6
	t.default_font = fv
	var n = box(SUN, INK, 4, 20, 10)
	n.content_margin_left = 22
	n.content_margin_right = 22
	var h = box(Color("ffd95e"), INK, 4, 20, 10)
	h.content_margin_left = 22
	h.content_margin_right = 22
	var p = box(Color("e0ac1e"), INK, 4, 20, 10)
	p.shadow_size = 1
	var d = box(Color("d9d4c8"), Color("8f8a80"), 4, 20, 10)
	t.set_stylebox("normal", "Button", n)
	t.set_stylebox("hover", "Button", h)
	t.set_stylebox("pressed", "Button", p)
	t.set_stylebox("disabled", "Button", d)
	var f = box(Color(0, 0, 0, 0), WHITE, 3, 22, 8)
	f.shadow_size = 0
	t.set_stylebox("focus", "Button", f)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color("8f8a80"))
	t.set_font_size("font_size", "Button", 26)
	t.set_color("font_color", "Label", INK)
	t.set_stylebox("panel", "PanelContainer", box(CREAM, INK, 5, 28, 22))
	t.set_stylebox("panel", "Panel", box(CREAM, INK, 5, 28, 22))
	var sl = StyleBoxFlat.new()
	sl.bg_color = Color("d9cdb5")
	sl.set_corner_radius_all(8)
	sl.content_margin_top = 6
	sl.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", sl)
	var gr = StyleBoxFlat.new()
	gr.bg_color = TURQ
	gr.set_corner_radius_all(8)
	t.set_stylebox("grabber_area", "HSlider", gr)
	t.set_stylebox("grabber_area_highlight", "HSlider", gr)
	t.set_color("font_color", "CheckBox", INK)
	t.set_color("font_hover_color", "CheckBox", TURQ_D)
	var pb = box(Color("e8dcc4"), INK, 3, 12, 0)
	pb.shadow_size = 0
	var pf = box(TURQ, INK, 0, 10, 0)
	pf.shadow_size = 0
	t.set_stylebox("background", "ProgressBar", pb)
	t.set_stylebox("fill", "ProgressBar", pf)
	t.set_color("font_color", "ProgressBar", INK)
	var tip = box(Color(0.12, 0.12, 0.16, 0.95), TURQ, 2, 10, 8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", CREAM)
	var sc = StyleBoxFlat.new()
	sc.bg_color = Color(0, 0, 0, 0.12)
	sc.set_corner_radius_all(6)
	t.set_stylebox("scroll", "VScrollBar", sc)
	var sg = StyleBoxFlat.new()
	sg.bg_color = TURQ
	sg.set_corner_radius_all(6)
	t.set_stylebox("grabber", "VScrollBar", sg)
	t.set_stylebox("grabber_highlight", "VScrollBar", sg)
	t.set_stylebox("grabber_pressed", "VScrollBar", sg)
	_theme = t
	return t


## Anchor a control to a screen corner/edge with an offset from that anchor; it grows toward the screen inside.
static func place(c: Control, preset: int, off: Vector2) -> void:
	c.set_anchors_preset(preset)
	var sz = c.custom_minimum_size
	c.offset_left = off.x
	c.offset_top = off.y
	c.offset_right = off.x + sz.x
	c.offset_bottom = off.y + sz.y
	var right = preset in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_RIGHT]
	var bottom = preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM]
	var hc = preset in [Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER]
	var vc = preset in [Control.PRESET_CENTER_LEFT, Control.PRESET_CENTER_RIGHT, Control.PRESET_CENTER]
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else (Control.GROW_DIRECTION_BOTH if hc else Control.GROW_DIRECTION_END)
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else (Control.GROW_DIRECTION_BOTH if vc else Control.GROW_DIRECTION_END)


static func full(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func label(text: String, size = 24, color = INK, wrap = false, align = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func title(text: String, size = 44, color = INK) -> Label:
	var l = label(text, size, color, false, HORIZONTAL_ALIGNMENT_CENTER)
	return l


## Bold label with dark outline for use over the 3D view.
static func hud_label(text: String, size = 26, color = WHITE) -> Label:
	var l = label(text, size, color)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", INK)
	return l


static func button(text: String, cb: Callable, min_w = 260, color = SUN) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 58)
	b.theme = theme()
	if color != SUN:
		var n = box(color, INK, 4, 20, 10)
		var h = box(color.lightened(0.15), INK, 4, 20, 10)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", h)
		b.add_theme_stylebox_override("pressed", box(color.darkened(0.15), INK, 4, 20, 10))
		if color.get_luminance() < 0.45:
			b.add_theme_color_override("font_color", WHITE)
			b.add_theme_color_override("font_hover_color", WHITE)
			b.add_theme_color_override("font_pressed_color", WHITE)
	b.pressed.connect(func(): Sfx.play("ui"); cb.call())
	return b


static func panel(min_size = Vector2(600, 400), bg = CREAM) -> PanelContainer:
	var p = PanelContainer.new()
	p.theme = theme()
	p.custom_minimum_size = min_size
	if bg != CREAM:
		p.add_theme_stylebox_override("panel", box(bg, INK, 5, 28, 22))
	return p


static func dim(parent: Control, alpha = 0.5) -> ColorRect:
	var c = ColorRect.new()
	c.color = Color(0.08, 0.1, 0.16, alpha)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(c)
	return c


static func center(parent: Control, child: Control) -> CenterContainer:
	var cc = CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cc)
	cc.add_child(child)
	return cc


static func vbox(sep = 12) -> VBoxContainer:
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep = 12) -> HBoxContainer:
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func bar(value: float, color: Color, w = 180, h = 18) -> ProgressBar:
	var b = ProgressBar.new()
	b.theme = theme()
	b.custom_minimum_size = Vector2(w, h)
	b.show_percentage = false
	b.max_value = 1.0
	b.value = value
	var f = box(color, INK, 0, 9, 0)
	f.shadow_size = 0
	b.add_theme_stylebox_override("fill", f)
	return b


static func stars(r: float) -> String:
	var full = int(floor(r + 0.25))
	var s = ""
	for i in 5:
		s += "★" if i < full else "☆"
	return s
