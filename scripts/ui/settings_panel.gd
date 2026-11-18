class_name SettingsPanel
extends RefCounted
## The one settings panel, shared by the title menu and the in-game pause menu: volumes, mouse sensitivity,
## camera inversion, shadows, fullscreen (desktop only), graphics quality and touch controls.


## Fills `v` with the settings rows. `apply` runs after shadows/quality change (the world re-applies its
## graphics; an empty Callable on the title screen), `done` closes the panel. Returns the control to focus first.
static func fill(v: VBoxContainer, apply: Callable, done: Callable) -> Control:
	var t = UiKit.title("Настройки", 44)
	t.add_theme_font_override("font", UiKit.font(800))
	v.add_child(t)
	var first: Control
	for k in [["music", "Музыка", 0.0, 1.0], ["sfx", "Звуки", 0.0, 1.0], ["mouse_sens", "Чувствительность мыши", 0.02, 0.8]]:
		var key: String = k[0]
		var row = UiKit.hbox(10)
		var l = UiKit.label(k[1], 24)
		l.custom_minimum_size = Vector2(300, 0)
		row.add_child(l)
		var s = HSlider.new()
		s.custom_minimum_size = Vector2(340, 34)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.min_value = k[2]
		s.max_value = k[3]
		s.step = 0.01
		s.value = float(Game.settings[key])
		s.value_changed.connect(func(x): Game.settings[key] = x; Sfx.refresh_volume())
		row.add_child(s)
		v.add_child(row)
		if first == null:
			first = s
	var checks = [["invert_y", "Инвертировать камеру по вертикали"], ["shadows", "Тени"]]
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		checks.append(["fullscreen", "Полный экран"])
	for k in checks:
		var key: String = k[0]
		var cb = CheckBox.new()
		cb.text = k[1]
		cb.add_theme_font_size_override("font_size", 24)
		cb.button_pressed = bool(Game.settings[key])
		cb.toggled.connect(func(x):
			Game.settings[key] = x
			if key == "shadows" and apply.is_valid():
				apply.call())
		v.add_child(cb)
	v.add_child(_choice("Графика", [[0, "Низкая"], [1, "Средняя"], [2, "Высокая"]], int(Game.settings["quality"]),
		func(q):
			Game.settings["quality"] = q
			Game.settings["quality_set"] = true
			if apply.is_valid():
				apply.call()))
	v.add_child(_choice("Сенсорное управление", [["auto", "Авто"], ["on", "Вкл"], ["off", "Выкл"]],
		Game.settings["touch"], func(o): Game.settings["touch"] = o))
	v.add_child(UiKit.button("Готово", func(): Game.save_settings(); done.call(), 660))
	return first


## A label and a row of segmented buttons; the picked one is turquoise, restyled in place on press.
static func _choice(title: String, opts: Array, cur, pick: Callable) -> Control:
	var row = UiKit.hbox(8)
	var l = UiKit.label(title, 24)
	l.custom_minimum_size = Vector2(300, 0)
	row.add_child(l)
	var btns: Array[Button] = []
	for o in opts:
		var b = UiKit.button(o[1], func(): pass, 128)
		b.set_meta("id", o[0])
		btns.append(b)
		row.add_child(b)
	for b in btns:
		b.pressed.connect(func():
			pick.call(b.get_meta("id"))
			for x in btns:
				_style(x, x == b))
		_style(b, b.get_meta("id") == cur)
	return row


static func _style(b: Button, on: bool) -> void:
	var c = UiKit.TURQ if on else Color("e8dcc4")
	b.add_theme_stylebox_override("normal", UiKit.box(c, UiKit.INK, 4, 20, 10))
	b.add_theme_stylebox_override("hover", UiKit.box(c.lightened(0.15), UiKit.INK, 4, 20, 10))
	b.add_theme_stylebox_override("pressed", UiKit.box(c.darkened(0.15), UiKit.INK, 4, 20, 10))
