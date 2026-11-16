extends Node
## --tour x,z,yaw[,hour] ... : screenshots of the game at given spots -> renders/game/tour_N.png

var world: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var dir = "res://renders/game/" if OS.has_feature("editor") else "user://"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	await get_tree().create_timer(2.0).timeout
	if Game.flag("noshadow"):
		world.daynight.sun.shadow_enabled = false
	if Game.flag("nonpc"):
		world.people.process_mode = Node.PROCESS_MODE_DISABLED
		world.people.visible = false
		world.traffic.visible = false
	if Game.flag("noglow"):
		world.daynight.env.glow_enabled = false
		world.daynight.env.fog_enabled = false
	if Game.flag("nofx"):
		world.fx.visible = false
	if Game.flag("dbgcars"):
		var c0 = world.traffic.cars[0]
		var pth = world.traffic.paths[c0["path"]]
		print("PATH len ", pth["len"], " pts ", pth["pts"], " cum ", pth["cum"], " s ", c0["s"], " pos_at ", world.traffic._pos_at(pth, c0["s"]))
		for c in world.traffic.cars:
			var b: Node3D = c["body"]
			print("CAR ", b.global_position, " vis ", b.is_visible_in_tree(), " v ", c["v"], " kids ", b.get_child_count(), " node_in_tree ", c["node"].is_inside_tree(), " node_pos ", c["node"].global_position)
	var spots: Array = Game.flags.get("tour", [])
	var i = 0
	for s in spots:
		var p = String(s).split(",")
		var pl: Player = world.player
		pl.global_position = Vector3(float(p[0]), 0.3, float(p[1]))
		pl.heading = deg_to_rad(float(p[2]))
		pl.rotation.y = pl.heading
		pl.reset_camera()
		if p.size() > 3:
			world.daynight.hour = float(p[3])
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(dir + "tour_%d.png" % i))
		await get_tree().create_timer(2.0).timeout
		print("TOUR shot ", i, " fps ", Engine.get_frames_per_second(), " draw ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " objs ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME), " prims ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		i += 1
	get_tree().quit()
