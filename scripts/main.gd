extends Node
## Entry: title menu (painted concept art) or straight into the game (next day / --autotest / --tour / --play).

var menu: CanvasLayer


func _ready() -> void:
	if Game.go_play or Game.flag("autotest") or Game.flag("tour") or Game.flag("play") or Game.flag("trailer") or Game.flag("soak"):
		if (Game.flag("autotest") or Game.flag("newgame") or Game.flag("trailer") or Game.flag("soak")) and not Game.booted:
			Game.new_state()
		if Game.flag("district") and not Game.booted:
			Game.state["district"] = Game.flags["district"][0]
		Game.booted = true
		Game.go_play = false
		_start_game()
	else:
		_show_menu()


func _show_menu() -> void:
	Sfx.play_music("music_menu")
	menu = CanvasLayer.new()
	add_child(menu)
	if Game.flag("menushot"):
		Game.state["day"] = 7
		Game.state["money"] = 342.0
	var tm = TitleMenu.new()
	tm.started.connect(_start_game)
	menu.add_child(tm)
	if Game.flag("menushot"):
		_menu_shots(tm, Game.flags["menushot"][0])


## --menushot <dir>: screenshots of the title screen (idle, second button focused, new-game confirm, settings), then quit.
func _menu_shots(tm: TitleMenu, dir: String) -> void:
	var snap = func(n: String):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("menu_%s.png" % n))
	await get_tree().create_timer(2.0).timeout
	await snap.call("idle")
	tm.buttons[1].grab_focus()
	await get_tree().create_timer(0.5).timeout
	await snap.call("focus")
	tm._new_game()
	await get_tree().create_timer(0.5).timeout
	await snap.call("confirm")
	tm.modal.queue_free()
	tm._settings()
	await get_tree().create_timer(0.5).timeout
	await snap.call("settings")
	get_tree().quit()


func _start_game() -> void:
	if menu:
		menu.queue_free()
	var load_l = CanvasLayer.new()
	add_child(load_l)
	var bg = ColorRect.new()
	bg.color = Color("22b8b0")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	load_l.add_child(bg)
	var bag = TitleMenu.Bag.new()
	bag.custom_minimum_size = Vector2(130, 150)
	UiKit.place(bag, Control.PRESET_CENTER, Vector2(-65, -170))
	load_l.add_child(bag)
	var l = UiKit.hud_label("Едем: %s…" % Game.district_title(), 52)
	l.add_theme_font_override("font", UiKit.font(800))
	l.add_theme_constant_override("outline_size", 14)
	l.custom_minimum_size = Vector2(1000, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.place(l, Control.PRESET_CENTER, Vector2(-500, 10))
	load_l.add_child(l)
	await get_tree().process_frame
	await get_tree().process_frame
	var w = load("res://scripts/world.gd").new()
	w.name = "World"
	add_child(w)
	load_l.queue_free()
