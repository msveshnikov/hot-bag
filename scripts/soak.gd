extends Node
## --soak [minutes]: leak hunt. The courier rides on autopilot to random places, the clock runs ×3, every
## ~2.5 minutes the world travels to the next district (scene reload). Every 15 s the object / node / orphan /
## resource counts and static + video memory go to stdout and user://soak.log, so growth over time is visible.

const DISTRICTS = ["old_town", "city", "berezki", "gastro"]
# kept on Engine meta: this script is unloaded with the world on every scene change
var t0: float:
	get: return Engine.get_meta("soak_t0", -1.0)
	set(v): Engine.set_meta("soak_t0", v)
var hop: int:
	get: return Engine.get_meta("soak_hop", 0)
	set(v): Engine.set_meta("soak_hop", v)
var _logged: bool:
	get: return Engine.get_meta("soak_logged", false)
	set(v): Engine.set_meta("soak_logged", v)

var world: Node
var _log_t = 0.0
var _drive_t = 0.0
var _here = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS    # keeps going on the paused end-of-shift screen
	if t0 < 0.0:
		t0 = Time.get_ticks_msec() / 1000.0
		_log("time_s objects nodes orphans resources static_mb video_mb fps district")
	Engine.time_scale = 1.0 if Game.flag("bisect") else 3.0    # bisect: no end of shift (scene reload) mid-run
	Game.state["tutorial"] = 9
	Game.state["chapter"] = 5


func _elapsed() -> float:
	return Time.get_ticks_msec() / 1000.0 - t0


func _log(s: String) -> void:
	print("SOAK " + s)
	var f = FileAccess.open("user://soak.log", FileAccess.READ_WRITE if _logged else FileAccess.WRITE)
	_logged = true
	if f:
		f.seek_end()
		f.store_line(s)


func _process(delta: float) -> void:
	if world == null or not world.started:
		return
	var rd = delta / max(Engine.time_scale, 0.01)   # real seconds
	_here += rd
	_log_t -= rd
	if _log_t <= 0.0:
		_log_t = 15.0
		_log("%.0f %d %d %d %d %.1f %.1f %d %s" % [_elapsed(),
			Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			Engine.get_frames_per_second(), Game.district()])
	var minutes = float(Game.flags["soak"][0]) if not Game.flags["soak"].is_empty() else 10.0
	if _elapsed() > minutes * 60.0:
		_log("done")
		get_tree().quit()
		return
	if world.screens.top_name() == "summary":
		Engine.time_scale = 1.0
		get_tree().paused = false
		world.next_day()
		return
	if not world.ui_free():
		world.screens.close_all()
		get_tree().paused = false
	var pl: Player = world.player
	if pl.busy > 0.0:
		return
	if not pl.riding():
		if not world.parked.is_empty():
			var b: Node3D = world.parked["body"]
			pl.global_position = b.global_position + Vector3(0.6, 0.3, 0)
			world.mount_parked()
		return
	if Game.flag("bisect"):
		_bisect(rd)
	elif _here > 150.0:
		hop += 1
		Engine.time_scale = 1.0
		world.travel_to(DISTRICTS[hop % DISTRICTS.size()])
		return
	_drive_t -= rd
	if pl.autopilot.is_empty() or _drive_t <= 0.0:
		_drive_t = 25.0
		var lv: Level = world.level
		for k in 30:
			var c = Vector2i(randi() % lv.gw, randi() % lv.gh)
			if lv.code_at_cell(c) in ["a", "c", "s"]:
				var path: PackedVector3Array = world.nav.path(pl.global_position, lv.cell_center(c), "bicycle")
				if path.size() > 4:
					pl.autopilot = Array(path)
					pl.autopilot_throttle = 1.0
					break


# ---------------------------------------------------------------- --bisect: find what grows the GPU driver's memory
## Stays in one district; every 60 s turns one subsystem off (and the previous one back on), logging the phase,
## so the memory slope of each minute (adb shell dumpsys meminfo) shows which subsystem feeds the growth.
const PHASES_1 = ["all_on", "no_3d", "no_ui", "no_particles", "no_daynight", "no_label3d", "no_fade", "no_traffic_people", "all_on_again"]
# round 2 (the growth stopped only with 3D off): which part of the 3D scene
const PHASES_2 = ["all_on", "no_chars", "no_traffic", "no_gps", "no_water", "no_level", "no_sky", "no_fade", "no_3d"]
# round 3 (growth went on with every part of the scene hidden): the 3D pass settings themselves
const PHASES = ["all_on", "no_msaa", "no_glow", "no_adjust", "no_shadows", "no_fog", "no_tonemap", "all_off", "no_3d"]
var _phase = -1
var _phase_t = 0.0


func _bisect(rd: float) -> void:
	_phase_t -= rd
	if _phase_t > 0.0:
		return
	_phase_t = 40.0
	if _phase >= 0:
		_set_phase(PHASES[_phase], true)
	_phase += 1
	if _phase >= PHASES.size():
		_log("done")
		get_tree().quit()
		return
	_set_phase(PHASES[_phase], false)
	_log("PHASE %s at %.0f" % [PHASES[_phase], _elapsed()])


func _set_phase(name: String, on: bool) -> void:
	match name:
		"no_3d":
			get_viewport().disable_3d = not on
		"no_ui":
			for c in world.find_children("*", "CanvasLayer", true, false):
				(c as CanvasLayer).visible = on
		"no_particles":
			for p in get_tree().root.find_children("*", "GPUParticles3D", true, false):
				(p as GPUParticles3D).visible = on
		"no_daynight":
			world.daynight.set_process(on)
		"no_label3d":
			for l in get_tree().root.find_children("*", "Label3D", true, false):
				(l as Label3D).visible = on
		"no_fade":
			world.player.set_meta("no_fade", not on)
		"no_msaa":
			get_viewport().msaa_3d = Viewport.MSAA_2X if on else Viewport.MSAA_DISABLED
		"no_glow":
			world.daynight.env.glow_enabled = on
		"no_adjust":
			world.daynight.env.adjustment_enabled = on
		"no_shadows":
			world.daynight.sun.shadow_enabled = on
		"no_fog":
			world.daynight.env.fog_enabled = on
		"no_tonemap":
			world.daynight.env.tonemap_mode = Environment.TONE_MAPPER_FILMIC if on else Environment.TONE_MAPPER_LINEAR
		"all_off":
			for ph in ["no_msaa", "no_glow", "no_adjust", "no_shadows", "no_fog", "no_tonemap"]:
				_set_phase(ph, on)
		"no_chars":
			world.people.visible = on
			world.player.visual.visible = on
		"no_traffic":
			world.traffic.visible = on
		"no_gps":    # stop rebuilding the GPS ribbon (ImmediateMesh) too, not only hide it
			world._gps_t = 0.0 if on else 1.0e9
			world.gps_line.visible = on
			world.gps_pin.visible = on
		"no_water":
			for m in world.level.get_children():
				if m is MeshInstance3D and (m as MeshInstance3D).material_override == world.level.water_mat:
					(m as MeshInstance3D).visible = on
		"no_level":
			world.level.visible = on
		"no_sky":
			var env: Environment = world.daynight.env
			env.background_mode = Environment.BG_SKY if on else Environment.BG_COLOR
		"no_traffic_people":
			world.traffic.visible = on
			world.people.visible = on
