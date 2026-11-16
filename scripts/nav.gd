class_name Nav
extends RefCounted
## GPS routes on the Task 3 navigation grid (AStarGrid2D), one solver per travel mode.
## Codes: # blocked, a asphalt, s sidewalk, c cobble, p park path, g grass, t stairs, q quay, w water, b bridge, z zebra

const COST = {
	"foot": {"a": 3.0, "s": 1.0, "c": 1.0, "p": 1.0, "g": 1.3, "t": 1.4, "q": 1.0, "b": 1.0, "z": 1.0},
	"bicycle": {"a": 1.4, "s": 1.6, "c": 1.15, "p": 0.9, "g": 1.8, "t": 2.4, "q": 1.0, "b": 1.0, "z": 1.0},
	"scooter": {"a": 1.0, "s": 1.6, "c": 1.35, "p": 1.0, "g": 2.5, "q": 1.0, "b": 1.0, "z": 1.0},
	"car": {"a": 1.0, "z": 1.0},
	"moped": {"a": 1.0, "c": 1.15, "z": 1.0, "b": 1.0, "q": 1.0},
	"ecar": {"a": 1.0, "c": 1.2, "z": 1.0, "b": 1.0},
}

var level: Level
var solvers = {}
var blocked_rects: Array[Rect2] = []   # temporary blocks (road works), in Godot x/z


func _init(lv: Level) -> void:
	level = lv
	for mode in COST.keys():
		solvers[mode] = _make(mode)


func _make(mode: String) -> AStarGrid2D:
	var a = AStarGrid2D.new()
	a.region = Rect2i(0, 0, level.gw, level.gh)
	a.cell_size = Vector2(1, 1)
	a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	a.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	a.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	a.update()
	var costs: Dictionary = COST[mode]
	for j in level.gh:
		for i in level.gw:
			var c = char(level.grid[j * level.gw + i])
			if not costs.has(c):
				a.set_point_solid(Vector2i(i, j), true)
			else:
				a.set_point_weight_scale(Vector2i(i, j), costs[c])
	return a


func set_block(rect: Rect2, on: bool) -> void:
	# rect in Godot x/z; blocks cells for every mode
	if on:
		blocked_rects.append(rect)
	else:
		blocked_rects.erase(rect)
	var c0 = level.cell_of(Vector3(rect.position.x, 0, rect.position.y))
	var c1 = level.cell_of(Vector3(rect.end.x, 0, rect.end.y))
	for j in range(min(c0.y, c1.y), max(c0.y, c1.y) + 1):
		for i in range(min(c0.x, c1.x), max(c0.x, c1.x) + 1):
			var p = Vector2i(i, j)
			if p.x < 0 or p.y < 0 or p.x >= level.gw or p.y >= level.gh:
				continue
			var code = level.code_at_cell(p)
			for mode in solvers.keys():
				var a: AStarGrid2D = solvers[mode]
				if on:
					a.set_point_solid(p, true)
				else:
					a.set_point_solid(p, not COST[mode].has(code))


func _nearest_free(a: AStarGrid2D, c: Vector2i) -> Vector2i:
	if a.is_in_boundsv(c) and not a.is_point_solid(c):
		return c
	for r in range(1, 8):
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				var p = c + Vector2i(di, dj)
				if a.is_in_boundsv(p) and not a.is_point_solid(p):
					return p
	return c


func path(from: Vector3, to: Vector3, mode: String) -> PackedVector3Array:
	var a: AStarGrid2D = solvers.get(mode, solvers["foot"])
	var c0 = _nearest_free(a, level.cell_of(from))
	var c1 = _nearest_free(a, level.cell_of(to))
	var ids = a.get_id_path(c0, c1, true)
	var out = PackedVector3Array()
	for id in ids:
		var p = level.cell_center(id)
		p.y = level.ground_height(p)
		out.append(p)
	if out.size() > 0:
		out[out.size() - 1] = Vector3(to.x, level.ground_height(to), to.z)
	return _simplify(out)


func _simplify(pts: PackedVector3Array) -> PackedVector3Array:
	if pts.size() < 3:
		return pts
	var out = PackedVector3Array([pts[0]])
	for i in range(1, pts.size() - 1):
		var d1 = (pts[i] - pts[i - 1]).normalized()
		var d2 = (pts[i + 1] - pts[i]).normalized()
		if d1.dot(d2) < 0.999 or abs(pts[i].y - pts[i - 1].y) > 0.1:
			out.append(pts[i])
	out.append(pts[pts.size() - 1])
	return out


static func length(pts: PackedVector3Array) -> float:
	var L = 0.0
	for i in range(1, pts.size()):
		L += pts[i].distance_to(pts[i - 1])
	return L
