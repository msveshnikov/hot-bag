extends Node
## --trailer <shot>: one scripted shot for the promo video, recorded with Godot's Movie Maker:
##   godot --path . --write-movie renders/trailer/<shot>.avi --fixed-fps 30 --resolution 1920x1080 -- --trailer <shot> --district <d>
## (tools/trailer.py records every shot and edits the video). Each shot sets the hour, weather, vehicle and a route
## the courier drives on autopilot, and a camera move: follow / track (offset in the rider's frame) / world
## (offset in world axes) / dolly (p0 -> p1) / orbit, or a UI screen (phone, garage, dialog, stairs).

const SHOTS = {
	# ---------------- Old Town
	"s01_open": {"d": "old_town", "hour": 9.3, "veh": "bicycle", "at": [10, -12.5, -90], "route": [[-55, -12.5]], "thr": 1.0,
		"cam": {"type": "dolly", "p0": [-16, 22, 12], "p1": [-16, 2.2, -2], "l0": [-12, 2, -16], "l1": [-12, 7, -32]}, "dur": 6.5},
	"s02_side": {"d": "old_town", "hour": 7.9, "veh": "bicycle", "at": [28, -8, -90], "route": [[-55, -8]], "thr": 1.0,
		"cam": {"type": "track", "off": [-2.6, 0.8, 0.8], "look": [0, 1.0, 1.8]}, "dur": 9.0},
	"s03_phone": {"d": "old_town", "hour": 9.2, "veh": "", "at": [-1, -4, 180], "ui": "phone", "hud": true, "dur": 4.5},
	"s04_rest": {"d": "old_town", "hour": 12.2, "veh": "scooter", "at": [-52, -1.5, 90], "route": [[25, -1.5]], "thr": 0.8,
		"cam": {"type": "world", "off": [-3.5, 2.0, -6.5], "look": [2.5, 1.6, 6.0]}, "dur": 5.5},
	"s05_rain": {"d": "old_town", "hour": 16.0, "weather": "rain", "veh": "scooter", "at": [-95, -58, 90], "route": [[70, -58]],
		"cam": {"type": "track", "off": [0.9, 1.3, -4.0], "look": [0, 1.0, 6.0]}, "dur": 5.0},
	"s06_snow": {"d": "old_town", "hour": 11.0, "weather": "snow", "veh": "bicycle", "at": [-50, -14, 90], "route": [[30, -14]],
		"thr": 0.7, "cam": {"type": "orbit", "r": 5.5, "h": 2.0, "a0": 200, "a1": 110}, "dur": 5.5},
	"s10_garage": {"d": "old_town", "hour": 12.0, "veh": "", "at": [60, -24, 180], "ui": "garage", "hud": true, "dur": 5.0},
	"s11_mentor": {"d": "old_town", "hour": 9.5, "veh": "", "at": [48, -23.2, 180], "ui": "mentor", "dur": 4.5},
	"s12_fall": {"d": "old_town", "hour": 13.5, "veh": "bicycle", "at": [-80, -57.5, 90], "route": [[40, -57.5]],
		"fall_at": 1.8, "cam": {"type": "track", "off": [-3.2, 1.2, 1.0], "look": [0, 0.7, 0.5]}, "dur": 4.5},
	"s13_sunset": {"d": "old_town", "hour": 19.35, "veh": "ebike", "at": [-100, -59, 90], "route": [[80, -59]],
		"cam": {"type": "track", "off": [0.7, 1.05, 5.5], "look": [0, 1.2, 0]}, "dur": 6.0},
	"s14_dream": {"d": "old_town", "hour": 20.6, "veh": "", "at": [24, 0.5, 0], "dream": true,
		"cam": {"type": "dolly", "p0": [27, 3.8, -13], "p1": [25.2, 2.3, -3.5], "l0": [24, 3.2, 8], "l1": [24, 3.6, 8]}, "dur": 5.0},
	# ---------------- «Берёзки» at night, the stairwell
	"s07_night": {"d": "berezki", "hour": 22.4, "veh": "scooter", "at": [2, 70, 180], "route": [[2, -70]],
		"cam": {"type": "track", "off": [1.6, 3.2, -7.5], "look": [0, 1.0, 8.0]}, "dur": 6.0},
	"s08_stairs": {"d": "berezki", "hour": 21.0, "veh": "", "at": [0, 10, 0], "ui": "stairs", "hud": true, "dur": 4.5},
	# ---------------- «Сити»
	"s09_city": {"d": "city", "hour": 12.6, "veh": "ecar", "at": [-80, -64, 90], "route": [[80, -64]],
		"cam": {"type": "track", "off": [2.4, 1.3, -6.0], "look": [-1.0, 5.0, 14.0]}, "dur": 6.0},
	# ---------------- Gastro quarter and the Big Park
	"s15_market": {"d": "gastro", "hour": 15.0, "veh": "moped", "at": [8, -36, 90], "route": [[85, -36]],
		"cam": {"type": "world", "off": [-3.0, 2.4, 8.5], "look": [4.0, 2.5, -14.0]}, "dur": 5.0},
	"s16_park": {"d": "gastro", "hour": 16.6, "veh": "bicycle", "at": [-30, -22, -90], "route": [[-95, -22]], "thr": 0.8,
		"cam": {"type": "dolly", "p0": [-50, 22, 34], "p1": [-58, 9, 20], "l0": [-62, 0, -6], "l1": "player"}, "dur": 5.5},
}

var world: Node
var shot: Dictionary
var t = 0.0
var cam: Camera3D
var fell = false
var started = false
var vertical = false     # --vertical: 9:16 clips for shorts, the rider stays in the middle of the frame


func _ready() -> void:
	vertical = Game.flag("vertical")
	process_mode = Node.PROCESS_MODE_ALWAYS   # dialogs pause the tree; the camera and the clock must keep going
	shot = SHOTS.get(String(Game.flags["trailer"][0]), {}).duplicate(true)
	_setup.call_deferred()


func _v3(a) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _setup() -> void:
	if shot.is_empty():
		push_error("unknown trailer shot")
		get_tree().quit()
		return
	var pl: Player = world.player
	Game.settings["music"] = 0.0
	Sfx.refresh_volume()
	world.events.process_mode = Node.PROCESS_MODE_DISABLED
	world.daynight.running = false
	world.daynight.hour = float(shot["hour"])
	match shot.get("weather", ""):
		"rain":
			world.daynight.rain_target = 1.0
			world.daynight.rain = 1.0
		"snow":
			world.daynight.set_snow_day(true)
			world.daynight.snow_target = 0.85
			world.daynight.snow = 0.85
		_:
			world.daynight.rain_target = 0.0
			world.daynight.rain = 0.0
	if shot.get("dream", false):
		Game.state["dream"] = "open"
		world.apply_dream()
	var at: Array = shot["at"]
	var p = Vector3(at[0], 0, at[1])
	var veh: String = shot.get("veh", "")
	if pl.riding():
		world.dismount_here()
	if veh != "":
		Game.state["owned"][veh] = true
		world.swap_vehicle(veh)
		world.battery = 100.0
		var vb: Node3D = world.parked["body"]
		vb.global_position = p
		vb.rotation.y = deg_to_rad(at[2])
		_tp(p + Vector3(0.8, 0, 0), at[2])
		world.mount_parked()
	elif shot.get("ui", "") == "mentor":
		var m: Node3D = world.people.mentor
		var fwd = Vector3(sin(m.rotation.y), 0, cos(m.rotation.y))
		# close-up of Михалыч alone: the courier steps out of the frame, no dialog box (the line is subtitled in the edit)
		p = m.global_position + fwd * 6.0 + Vector3(0, 0, 0)
		at = [p.x, p.z, rad_to_deg(m.rotation.y) + 180.0]
		_tp(p, at[2])
		pl.visible = false
		var side = Vector3(cos(m.rotation.y), 0, -sin(m.rotation.y))
		var head = m.global_position + Vector3(0, 1.25, 0)
		var c0 = m.global_position + fwd * 2.9 + side * 0.9 + Vector3(0, 1.55, 0)
		var c1 = m.global_position + fwd * 2.2 + side * 0.6 + Vector3(0, 1.45, 0)
		shot["cam"] = {"type": "dolly", "p0": [c0.x, c0.y, c0.z], "p1": [c1.x, c1.y, c1.z], "l0": [head.x, head.y, head.z],
			"l1": [head.x, head.y, head.z]}
	else:
		_tp(p, at[2])
	pl.global_position = p + Vector3(0, 0.3, 0)
	pl.heading = deg_to_rad(at[2])
	pl.rotation.y = pl.heading
	pl.stamina = 100.0
	pl.hunger = 100.0
	pl.phone = 100.0
	world.ui.visible = bool(shot.get("hud", false))
	if shot.has("cam"):
		cam = Camera3D.new()
		cam.fov = 55.0
		world.add_child(cam)
		cam.current = true
		cam.attributes = pl.camera.attributes
	await get_tree().create_timer(1.2).timeout   # let the world settle (traffic, lights, snow)
	pl.global_position = p + Vector3(0, 0.3, 0)
	pl.speed = 0.0
	match shot.get("ui", ""):
		"phone":
			for i in 4:
				var o = world.orders.make_offer()
				if not o.is_empty():
					world.orders.offers.append(o)
			world.orders.changed.emit()
			world.screens.open_phone("orders")
		"garage":
			world.screens.open_garage("vehicle")
		"mentor":
			Sfx.say("mikhalych", "Голубей не дави, они тут местные. У них профсоюз.")
		"stairs":
			var o = world.orders.make_offer()
			o["floor"] = 16
			o["door"]["lift"] = true
			world.orders.offers.append(o)
			world.orders.accept(o)
			world.screens.open_stairs(o)
			Input.action_press("interact")
	if shot.has("route"):
		var r = []
		for q in shot["route"]:
			r.append(Vector3(q[0], 0, q[1]))
		pl.autopilot = r
		pl.autopilot_throttle = float(shot.get("thr", 1.0))
	started = true
	# the movie keeps the loading frames: tell tools/trailer.py where the shot begins
	var f = FileAccess.open(ProjectSettings.globalize_path("res://renders/trailer/raw/%s.start" % String(Game.flags["trailer"][0])), FileAccess.WRITE)
	if f:
		f.store_string(str(Engine.get_frames_drawn()))


func _tp(p: Vector3, yaw_deg: float) -> void:
	var pl: Player = world.player
	pl.global_position = p + Vector3(0, 0.3, 0)
	pl.velocity = Vector3.ZERO
	pl.heading = deg_to_rad(yaw_deg)
	pl.rotation.y = pl.heading
	pl.reset_camera()


func _target(v, pl: Player) -> Vector3:
	if typeof(v) == TYPE_STRING:
		return pl.global_position + Vector3(0, 1.2, 0)
	return _v3(v)


func _process(delta: float) -> void:
	if not started:
		return
	t += delta
	var pl: Player = world.player
	# keep the frame clean: no GPS line, pin, banners or toasts
	world.gps_line.visible = false
	if world.gps_pin:
		world.gps_pin.visible = false
	world.hud.banner_p.visible = false
	world.hud.toasts.visible = false
	if Engine.get_process_frames() % 60 == 0:
		print("TRAILER t=%.1f pos=%s mode=%d speed=%.1f ap=%d busy=%.1f" % [t, pl.global_position, pl.mode, pl.speed, pl.autopilot.size(), pl.busy])
	var dur = float(shot["dur"])
	var k = clamp(t / dur, 0.0, 1.0)
	var e = k * k * (3.0 - 2.0 * k)
	if shot.has("fall_at") and not fell and t >= float(shot["fall_at"]):
		fell = true
		pl.autopilot = []
		pl.fall(2.5)
		get_tree().create_timer(0.05).timeout.connect(func(): pl._play("fall_tumble", true))
	if shot.get("ui", "") == "garage":
		var kinds = ["bicycle", "ebike", "scooter", "moped", "ecar"]
		var idx = min(int(t / (dur / kinds.size())), kinds.size() - 1)
		if GarageScreen.selected.get("vehicle", "") != kinds[idx]:
			for gs in world.screens.find_children("*", "GarageScreen", true, false):
				if not gs.is_queued_for_deletion():
					gs._select(kinds[idx])
	if cam:
		var c: Dictionary = shot["cam"]
		var f = Vector3(sin(pl.heading), 0, cos(pl.heading))
		var right = Vector3(-cos(pl.heading), 0, sin(pl.heading))
		var pp = pl.global_position
		var pos: Vector3
		var look: Vector3
		match c["type"]:
			"dolly":
				pos = _v3(c["p0"]).lerp(_v3(c["p1"]), e)
				look = _target(c["l0"], pl).lerp(_target(c["l1"], pl), e)
			"fixed":
				pos = _v3(c["p0"])
				look = _v3(c["l0"])
			"track":
				var o: Array = c["off"]
				var lk: Array = c["look"]
				pos = pp + right * o[0] + Vector3.UP * o[1] + f * o[2]
				look = pp + right * lk[0] + Vector3.UP * lk[1] + f * lk[2]
				if vertical:
					look = pp + Vector3.UP * 1.0
			"world":
				pos = pp + _v3(c["off"])
				look = pp + _v3(c["look"])
				if vertical:
					look = pp + Vector3.UP * 1.0
			"orbit":
				var a = deg_to_rad(lerp(float(c["a0"]), float(c["a1"]), e))
				pos = pp + Vector3(sin(a) * c["r"], c["h"], cos(a) * c["r"])
				look = pp + Vector3(0, 1.0, 0)
		if fell and vertical:
			# the tumble throws the body ~2 m ahead of the bike: follow it in the narrow frame
			var sh = f * 2.2 * clamp((t - float(shot["fall_at"])) / 0.6, 0.0, 1.0)
			pos += sh
			look += sh + Vector3.DOWN * 0.6 * clamp((t - float(shot["fall_at"])) / 0.6, 0.0, 1.0)
		if t < 0.05 or c["type"] in ["dolly", "fixed"]:
			cam.global_position = pos
		else:
			cam.global_position = cam.global_position.lerp(pos, clamp(8.0 * delta, 0.0, 1.0))
		if cam.global_position.distance_to(look) > 0.1:
			cam.look_at(look, Vector3.UP)
	if t >= dur:
		Input.action_release("interact")
		get_tree().quit()
