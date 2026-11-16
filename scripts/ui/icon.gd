class_name Icon
extends Control
## Vector icons drawn in code (the web build's font has no ★ ● symbols): "star" (fill 0..1) and "coin".

var kind = "star"
var fill = 1.0


static func make(k: String, sz = 26.0, f = 1.0) -> Icon:
	var i = Icon.new()
	i.kind = k
	i.fill = f
	i.custom_minimum_size = Vector2(sz, sz)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


## A row of five stars for a 1..5 rating.
static func stars(r: float, sz = 24.0) -> HBoxContainer:
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 1)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in 5:
		h.add_child(make("star", sz, clamp(r - k, 0.0, 1.0)))
	return h


static func set_stars(h: HBoxContainer, r: float) -> void:
	for k in h.get_child_count():
		var i: Icon = h.get_child(k)
		var f = clamp(r - k, 0.0, 1.0)
		if abs(f - i.fill) > 0.01:
			i.fill = f
			i.queue_redraw()


func _draw() -> void:
	var c = size * 0.5
	var r = min(size.x, size.y) * 0.5
	if kind == "coin":
		draw_circle(c, r, Color("2f2a33"))
		draw_circle(c, r - 2.5, Color("f6c945"))
		draw_circle(c, r * 0.55, Color("e0ac1e"))
		return
	var pts = PackedVector2Array()
	for k in 10:
		var a = -PI / 2 + k * PI / 5
		var rr = r if k % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, Color("d9cdb5"))
	if fill > 0.01:
		if fill >= 0.99:
			draw_colored_polygon(pts, Color("f2b81f"))
		else:
			# partial star: clip by drawing the filled part as a polygon slice
			var x_cut = c.x - r + 2.0 * r * fill
			var part = Geometry2D.clip_polygons(pts, PackedVector2Array([Vector2(x_cut, c.y - r - 1), Vector2(c.x + r + 1, c.y - r - 1), Vector2(c.x + r + 1, c.y + r + 1), Vector2(x_cut, c.y + r + 1)]))
			for p in part:
				draw_colored_polygon(p, Color("f2b81f"))
	var outline = pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color("2f2a33"), 2.0, true)
