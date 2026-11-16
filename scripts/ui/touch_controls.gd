extends CanvasLayer
## On-screen touch controls (phones, touch browsers). Left: floating stick (push past the ring = sprint/boost).
## Right: drag to look. Buttons drive the same InputMap actions as the keyboard.

const STICK_R = 110.0
const SPRINT_AT = 1.3
const LOOK_SENS = 0.006
const MOVE = ["move_left", "move_right", "move_forward", "move_back"]

var world: Node
var pad: Control
var stick_idx = -1
var stick_origin = Vector2.ZERO
var stick_finger = Vector2.ZERO
var sprinting = false
var look_idx = -1
var held = {}
var _release_at = {}
var _was_blocked = false

var buttons = [
	{"id": "interact", "action": "interact", "off": Vector2(-170, -190), "r": 86.0, "label": "Действие"},
	{"id": "mount", "action": "mount", "off": Vector2(-360, -150), "r": 60.0, "label": "Сесть"},
	{"id": "brake", "action": "brake", "off": Vector2(-330, -320), "r": 58.0, "label": "Тормоз", "hold": true},
	{"id": "bell", "action": "bell", "off": Vector2(-180, -380), "r": 50.0, "label": "Дзынь"},
	{"id": "item", "action": "use_item", "off": Vector2(-70, -330), "r": 50.0, "label": "Сумка"},
	{"id": "phone", "event": "phone", "off": Vector2(-70, 0), "top": 290.0, "r": 52.0, "label": "Хоп!"},
	{"id": "call", "action": "call", "off": Vector2(-190, 0), "top": 290.0, "r": 46.0, "label": "Звонок"},
	{"id": "lock", "action": "lock", "off": Vector2(-300, 0), "top": 290.0, "r": 46.0, "label": "Замок"},
	{"id": "menu", "event": "pause", "off": Vector2(-410, 0), "top": 290.0, "r": 44.0, "label": "Меню"},
]


func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	pad = Control.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.draw.connect(_draw_pad)
	add_child(pad)


func _blocked() -> bool:
	return get_tree().paused or world == null or world.player == null or not world.ui_free()


func _center(b: Dictionary) -> Vector2:
	var s = pad.size
	if b.has("top"):
		return Vector2(s.x + b["off"].x, b["top"])
	return s + b["off"]


func _button_at(p: Vector2) -> Dictionary:
	for b in buttons:
		if p.distance_to(_center(b)) <= b["r"] * 1.12:
			return b
	return {}


func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	if _blocked():
		if event is InputEventScreenTouch and not event.pressed:
			_finger_up(event.index)
		# let the phone button still close the phone
		if event is InputEventScreenTouch and event.pressed and world and world.ui_phone_open():
			var b = _button_at(event.position)
			if b.get("id", "") == "phone":
				world.screens.close_named("phone")
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_finger_down(event.index, event.position)
		else:
			_finger_up(event.index)
	else:
		_finger_drag(event.index, event.position, event.relative)


func _finger_down(idx: int, p: Vector2) -> void:
	var b = _button_at(p)
	if not b.is_empty():
		held[idx] = b
		if b.has("action"):
			if b.get("hold", false):
				Input.action_press(b["action"])
			else:
				_tap(b["action"])
		else:
			var ev = InputEventAction.new()
			ev.action = b["event"]
			ev.pressed = true
			Input.parse_input_event(ev)
			release_all()
		pad.queue_redraw()
		return
	if p.x < pad.size.x * 0.45 and p.y > 200.0:
		if stick_idx < 0:
			stick_idx = idx
			stick_origin = p
			stick_finger = p
			_apply_stick()
	elif look_idx < 0:
		look_idx = idx


## Keyboard-style tap: world.gd reacts to is_action_pressed in _unhandled_input.
func _tap(action: String) -> void:
	var ev = InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up = InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event.call_deferred(up)


func _finger_up(idx: int) -> void:
	if held.has(idx):
		var b: Dictionary = held[idx]
		held.erase(idx)
		if b.get("hold", false):
			Input.action_release(b["action"])
		pad.queue_redraw()
	if idx == stick_idx:
		stick_idx = -1
		sprinting = false
		_apply_stick()
	if idx == look_idx:
		look_idx = -1


func _finger_drag(idx: int, p: Vector2, rel: Vector2) -> void:
	if idx == stick_idx:
		stick_finger = p
		_apply_stick()
	elif idx == look_idx:
		var pl = world.player
		var k = LOOK_SENS * float(Game.settings["mouse_sens"]) / 0.22
		pl.cyaw -= rel.x * k
		pl.cam_pitch = clamp(pl.cam_pitch - rel.y * k * 0.8, -1.1, 0.25)
		pl.cam_idle = 0.0


func _apply_stick() -> void:
	var v = Vector2.ZERO
	if stick_idx >= 0:
		var d = stick_finger - stick_origin
		sprinting = d.length() > STICK_R * SPRINT_AT
		if d.length() > STICK_R * SPRINT_AT * 1.25:
			stick_origin = stick_finger - d.normalized() * STICK_R * SPRINT_AT * 1.25
			d = stick_finger - stick_origin
		v = d / STICK_R
		if v.length() > 1.0:
			v = v.normalized()
		if v.length() < 0.12:
			v = Vector2.ZERO
	_axis("move_left", max(0.0, -v.x))
	_axis("move_right", max(0.0, v.x))
	_axis("move_forward", max(0.0, -v.y))
	_axis("move_back", max(0.0, v.y))
	if sprinting:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")
	pad.queue_redraw()


func _axis(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func release_all() -> void:
	for a in MOVE + ["sprint", "brake", "interact", "mount"]:
		Input.action_release(a)
	held.clear()
	stick_idx = -1
	look_idx = -1
	sprinting = false
	if pad:
		pad.queue_redraw()


func _process(_d: float) -> void:
	var blk = _blocked()
	if blk != _was_blocked:
		_was_blocked = blk
		if blk:
			release_all()
	pad.visible = not blk or (world != null and world.ui_phone_open())
	if not blk:
		pad.queue_redraw()


func _draw_pad() -> void:
	var font: Font = ThemeDB.fallback_font
	if world and world.ui_phone_open():
		_btn(buttons[5], font)
		return
	var active = stick_idx >= 0
	var o = stick_origin if active else Vector2(240, pad.size.y - 260)
	pad.draw_circle(o, STICK_R, Color(0.1, 0.12, 0.18, 0.3 if active else 0.16))
	pad.draw_arc(o, STICK_R, 0, TAU, 48, Color(1, 0.85, 0.3, 0.8) if sprinting else Color(1, 1, 1, 0.45 if active else 0.25), 4.0, true)
	var knob = o
	if active:
		var d = stick_finger - stick_origin
		knob = o + (d.normalized() * min(d.length(), STICK_R) if d.length() > 0.0 else Vector2.ZERO)
	pad.draw_circle(knob, 46.0, Color(0.13, 0.72, 0.69, 0.75 if active else 0.4))
	if not active:
		_text(font, "Едем", o + Vector2(0, STICK_R + 28), 26, Color(1, 1, 1, 0.6))
	for b in buttons:
		_btn(b, font)


func _btn(b: Dictionary, font: Font) -> void:
	var c = _center(b)
	var r: float = b["r"]
	var down = false
	for hb in held.values():
		if hb["id"] == b["id"]:
			down = true
	var bg = Color(0.13, 0.72, 0.69, 0.75 if down else 0.5)
	if b["id"] == "interact" and world and not world.focus.is_empty():
		var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)
		bg = Color(0.96, 0.79, 0.27, 0.6 + 0.3 * pulse)
	pad.draw_circle(c, r, bg)
	pad.draw_arc(c, r, 0, TAU, 48, Color(0.18, 0.16, 0.2, 0.9), 4.0, true)
	_text(font, b["label"], c, 24 if r > 55.0 else 20, Color(1, 1, 1, 0.95))


func _text(font: Font, s: String, center: Vector2, size: int, col: Color) -> void:
	var w = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos = center + Vector2(-w * 0.5, (font.get_ascent(size) - font.get_descent(size)) * 0.5)
	pad.draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0.18, 0.16, 0.2, col.a))
	pad.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
