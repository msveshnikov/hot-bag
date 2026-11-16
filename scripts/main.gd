extends Node
## Entry: title menu (painted concept art) or straight into the game (next day / --autotest / --tour / --play).

var menu: CanvasLayer


func _ready() -> void:
	if Game.go_play or Game.flag("autotest") or Game.flag("tour") or Game.flag("play"):
		if Game.flag("autotest") or Game.flag("newgame"):
			Game.new_state()
		Game.go_play = false
		_start_game()
	else:
		_show_menu()


func _show_menu() -> void:
	Sfx.play_music("music_menu")
	menu = CanvasLayer.new()
	add_child(menu)
	var root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiKit.theme()
	menu.add_child(root)
	var bg = TextureRect.new()
	bg.texture = load("res://assets/ui/title.jpg")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	root.add_child(bg)
	var title = UiKit.label("Горячая сумка", 96, Color("fff3c4"), false, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_constant_override("outline_size", 22)
	title.add_theme_color_override("font_outline_color", Color("2f2a33"))
	title.custom_minimum_size = Vector2(1000, 0)
	UiKit.place(title, Control.PRESET_CENTER_TOP, Vector2(-500, 40))
	root.add_child(title)
	var sub = UiKit.hud_label("симулятор курьера · Старый город", 30, Color("ffffff"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.custom_minimum_size = Vector2(1000, 0)
	UiKit.place(sub, Control.PRESET_CENTER_TOP, Vector2(-500, 160))
	root.add_child(sub)
	var v = UiKit.vbox(14)
	UiKit.place(v, Control.PRESET_CENTER_LEFT, Vector2(70, -140))
	root.add_child(v)
	var first: Button
	if Game.has_save():
		first = UiKit.button("Продолжить (день %d)" % int(Game.state["day"]), func(): _start_game(), 380)
		v.add_child(first)
	var nb = UiKit.button("Новая игра", func():
		Game.delete_save()
		_start_game(), 380, UiKit.TURQ)
	v.add_child(nb)
	if first == null:
		first = nb
	v.add_child(UiKit.button("Настройки", func(): _settings(root), 380, Color("e8dcc4")))
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		v.add_child(UiKit.button("Выход", func(): get_tree().quit(), 380, Color("e8dcc4")))
	var ver = UiKit.hud_label("v" + Game.VERSION + " · вертикальный срез", 18)
	UiKit.place(ver, Control.PRESET_BOTTOM_RIGHT, Vector2(-330, -40))
	root.add_child(ver)
	first.grab_focus.call_deferred()


func _settings(root: Control) -> void:
	var m = Control.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiKit.dim(m, 0.5)
	var p = UiKit.panel(Vector2(640, 0))
	UiKit.center(m, p)
	var v = UiKit.vbox(12)
	p.add_child(v)
	v.add_child(UiKit.title("Настройки", 40))
	for k in [["music", "Музыка"], ["sfx", "Звуки"]]:
		var key: String = k[0]
		var row = UiKit.hbox(10)
		var l = UiKit.label(k[1], 22)
		l.custom_minimum_size = Vector2(200, 0)
		row.add_child(l)
		var s = HSlider.new()
		s.custom_minimum_size = Vector2(320, 30)
		s.max_value = 1.0
		s.step = 0.01
		s.value = float(Game.settings[key])
		s.value_changed.connect(func(x): Game.settings[key] = x; Sfx.refresh_volume())
		row.add_child(s)
		v.add_child(row)
	for k in [["shadows", "Тени"], ["fullscreen", "Полный экран"]]:
		var key: String = k[0]
		var cb = CheckBox.new()
		cb.text = k[1]
		cb.button_pressed = bool(Game.settings[key])
		cb.toggled.connect(func(x): Game.settings[key] = x)
		v.add_child(cb)
	v.add_child(UiKit.button("Готово", func(): Game.save_settings(); m.queue_free(), 560))
	root.add_child(m)


func _start_game() -> void:
	if menu:
		menu.queue_free()
	var load_l = CanvasLayer.new()
	add_child(load_l)
	var bg = ColorRect.new()
	bg.color = Color("22b8b0")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	load_l.add_child(bg)
	var l = UiKit.hud_label("Загрузка Старого города...", 44)
	UiKit.place(l, Control.PRESET_CENTER, Vector2(-300, -30))
	load_l.add_child(l)
	await get_tree().process_frame
	await get_tree().process_frame
	var w = load("res://scripts/world.gd").new()
	w.name = "World"
	add_child(w)
	load_l.queue_free()
