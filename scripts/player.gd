class_name Player
extends CharacterBody3D
## The courier: walking, bicycle / e-bike, e-scooter, e-moped, e-car (specs in Game.VEH). Arcade vehicle model, chase camera, stats, animations.
## Model front is +Z (Blender -Y). heading = rotation.y; forward = (sin h, 0, cos h).

enum Mode { FOOT, BIKE, SCOOTER, MOPED, CAR }

const WALK = 3.0
const RUN = 5.6
const BIKE_MAX = 7.6
const SCOOT_MAX = 9.6
const ANIM_WALK_SPEED = 0.993
const ANIM_RUN_SPEED = 2.274
const CRANK_M = 3.6        # metres per crank turn (ride_bike = 1 s per turn)

var world: Node
var mode = Mode.FOOT
var heading = 0.0
var speed = 0.0            # signed forward speed (m/s)
var steer = 0.0
var lean = 0.0
var control = true
var autopilot: Array = []        # waypoints for scripted driving (trailer)
var autopilot_throttle = 1.0
var busy = 0.0             # seconds of locked control (mount, fall, pickup)
var fallen = 0.0
var carrying = false

var stamina = 100.0
var hunger = 10.0
var phone = 100.0
var wet = 0.0

var visual: Node3D          # model + vehicle, leaned
var model: Node3D
var anim: AnimationPlayer
var held_box: Node3D
var vehicle_kind = ""      # Game.VEH key when riding
var vehicle_model: Node3D
var cur_anim = ""
var cam_pivot: Node3D
var camera: Camera3D
var cyaw = 0.0             # camera yaw in world space (behind = heading + PI)
var cam_pitch = -0.32
var cam_idle = 0.0
var cam_len = 4.2          # wanted camera distance (smoothed)
var cam_dist = 4.2         # actual distance after walls: snaps in, eases out
var cam_avoid = 0.0        # automatic yaw offset that swings the camera to a clear side of a wall
var _avoid_target = 0.0
var _probe_t = 0.0
var _faded = {}            # Level.fade_items index -> current see-through amount
var last_out = Vector3.ZERO  # last floor position outside every building box
var _inside_t = 0.0
var _want_move = false      # the player is pushing the stick / WASD this frame
var _stuck_t = 0.0          # how long they have pushed without getting anywhere while wedged into something
var _stuck_pos = Vector3.ZERO
var _probe = {}             # CollisionShape3D -> slightly smaller copy of its shape for _overlapping()
const CAM_MASK = 1 | 16    # level geometry + camera-only boxes around building bodies (Level.CAM_LAYER)
const FADE = 0.72
var foot_shape: CollisionShape3D
var ride_shape: CollisionShape3D
var car_shape: CollisionShape3D
var last_safe = Vector3.ZERO
var surface = "c"
var on_sidewalk = false
var crash_cd = 0.0
var shake = 0.0
var _step_t = 0.0
var _hint_cd = {}


func setup(w: Node, pos: Vector3, yaw_deg: float) -> void:
	world = w
	collision_layer = 2
	collision_mask = 1 | 4 | 8
	floor_snap_length = 0.45
	safe_margin = 0.02
	floor_max_angle = deg_to_rad(50)
	global_position = pos + Vector3(0, 0.2, 0)
	heading = deg_to_rad(yaw_deg)
	foot_shape = CollisionShape3D.new()
	var cap = CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.5
	foot_shape.shape = cap
	foot_shape.position.y = 0.75
	add_child(foot_shape)
	ride_shape = CollisionShape3D.new()
	# rounded bottom: rolls over small edges instead of hitting them like a flat box
	var rc = CapsuleShape3D.new()
	rc.radius = 0.42
	rc.height = 1.6
	ride_shape.shape = rc
	ride_shape.position.y = 0.8
	ride_shape.disabled = true
	add_child(ride_shape)
	car_shape = CollisionShape3D.new()
	var cb = BoxShape3D.new()
	cb.size = Vector3(1.45, 1.3, 2.6)
	car_shape.shape = cb
	car_shape.position.y = 0.8
	car_shape.disabled = true
	add_child(car_shape)
	visual = Node3D.new()
	add_child(visual)
	var bl = Chars.blob(self, 0.6)
	bl.scale = Vector3(1.0, 1.0, 1.6)
	build_model()
	cam_pivot = Node3D.new()
	cam_pivot.top_level = true
	add_child(cam_pivot)
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.far = 900.0
	camera.near = 0.08
	camera.position = Vector3(0, 0, cam_dist)
	cam_pivot.add_child(camera)
	camera.current = true
	apply_camera_fx()
	cam_pivot.global_position = global_position + Vector3(0, 1.7, 0)
	cyaw = heading + PI
	last_safe = global_position
	last_out = global_position


## Soft tilt-shift look of the concept art: the far background is slightly out of focus (Forward+ only;
## the Compatibility renderer of the web build has no depth of field).
func apply_camera_fx() -> void:
	var q = int(Game.settings.get("quality", 1))
	if q < 2 or RenderingServer.get_current_rendering_method() == "gl_compatibility" or Game.flag("nodof"):
		camera.attributes = null
		return
	var ca = CameraAttributesPractical.new()
	ca.dof_blur_far_enabled = true
	ca.dof_blur_far_distance = 38.0
	ca.dof_blur_far_transition = 40.0
	ca.dof_blur_amount = 0.07
	camera.attributes = ca


func build_model() -> void:
	if model:
		model.queue_free()
	var look: Dictionary = Game.state["look"]
	var ps: PackedScene = load("res://assets/characters/courier_%s.gltf" % ("f" if look["gender"] == "f" else "m"))
	model = ps.instantiate()
	visual.add_child(model)
	anim = model.find_child("AnimationPlayer", true, false)
	Chars.setup_anims(anim)
	apply_look()
	cur_anim = ""


func apply_look() -> void:
	var look: Dictionary = Game.state["look"]
	var helmet: String = Game.state.get("helmet", "")
	for n in model.find_children("ACC_*", "", true, false):
		var nm = String(n.name)
		var vis = false
		if nm.begins_with("ACC_hair_"):
			vis = nm == "ACC_hair_" + String(look["hair"]) and (helmet == "" or nm in ["ACC_hair_ponytail"])
			if helmet == "" and look.get("cap", true) and nm in ["ACC_hair_curly", "ACC_hair_bun"]:
				vis = false
		elif nm == "ACC_cap":
			vis = helmet == "" and bool(look.get("cap", true))
		elif nm.begins_with("ACC_helmet_"):
			vis = ("helmet_" + nm.substr(11)) == helmet
		elif nm == "ACC_bag":
			vis = true
		n.visible = vis
	held_box = model.find_child("HELD_box", true, false)
	var phone_n = model.find_child("HELD_phone", true, false)
	if phone_n:
		phone_n.visible = false
	if held_box:
		held_box.visible = false
	Chars.set_jacket(model, Color(look["jacket"]))
	Chars.set_bag(model, Color(look.get("bag", Game.BAGS[0])))


# ---------------------------------------------------------------- vehicles
func riding() -> bool:
	return mode != Mode.FOOT


func max_speed() -> float:
	var m = 1.0
	if stamina < 15.0:
		m *= 0.75
	if hunger > 80.0:
		m *= 0.8
	match mode:
		Mode.FOOT:
			return (RUN if Input.is_action_pressed("sprint") and stamina > 5.0 else WALK) * m
		_:
			var sp: Dictionary = Game.veh(vehicle_kind)
			var flat_k = 0.45 if world.events.flat and mode != Mode.CAR else 1.0
			var snow_k = 1.0 - 0.15 * world.daynight.snow_cover if mode in [Mode.BIKE, Mode.SCOOTER] else 1.0
			if mode == Mode.BIKE:
				var v = float(sp["vmax"])
				if Game.is_electric(vehicle_kind):
					if world.battery <= 0.0:
						v = BIKE_MAX * 0.85   # a heavy bicycle without the motor
					else:
						v *= 1.0 + 0.08 * Game.upgrade_level("motor")
				return v * m * (1.12 if Input.is_action_pressed("sprint") and stamina > 10.0 else 1.0) * flat_k * snow_k
			var s = float(sp["vmax"]) * (1.0 + 0.12 * Game.upgrade_level("motor"))
			if world.battery <= 0.0:
				return 1.2
			if world.battery < 12.0:
				s *= 0.55
			return s * flat_k * snow_k
	return WALK


func surface_mult() -> Array:
	# [speed factor, grip, shake]
	var c = surface
	var rain: float = world.daynight.rain
	var snow: float = world.daynight.snow_cover
	var tires = Game.upgrade_level("tires") > 0
	match mode:
		Mode.FOOT:
			return [(0.85 if c == "g" else 1.0) * (1.0 - 0.1 * snow), 1.0, 0.0]
		Mode.BIKE:
			var f = {"c": 0.92, "g": 0.7, "t": 0.45, "s": 0.95}.get(c, 1.0)
			var gb = 0.9 - rain * 0.2 - snow * (0.2 if tires else 0.35)
			return [f, clamp(gb, 0.3, 1.0), 0.6 if c == "c" else (1.2 if c == "t" else 0.1)]
		Mode.MOPED:
			var fm = {"c": 0.88, "s": 0.8}.get(c, 1.0)
			var gm = 0.92 - rain * 0.25 - snow * (0.25 if tires else 0.45)
			return [fm, clamp(gm, 0.3, 1.0), 0.35 if c == "c" else 0.08]
		Mode.CAR:
			return [0.92 if c == "c" else 1.0, clamp(0.95 - rain * 0.1 - snow * 0.3, 0.4, 1.0), 0.05]
		Mode.SCOOTER:
			var f2 = {"c": 0.72, "g": 0.5, "s": 0.95}.get(c, 1.0)
			var grip = 0.85 - (0.4 if c == "c" else 0.0) - rain * 0.35 - snow * 0.4
			if tires:
				f2 = max(f2, 0.85) if c == "c" else f2
				grip += 0.3
			return [f2, clamp(grip, 0.25, 1.0), 1.0 if c == "c" else 0.15]
	return [1.0, 1.0, 0.0]


func mount(kind: String, vm: Node3D) -> void:
	vehicle_kind = kind
	vehicle_model = vm
	if vm.get_parent():
		vm.get_parent().remove_child(vm)
	visual.add_child(vm)
	vm.transform = Transform3D.IDENTITY
	var sp: Dictionary = Game.veh(kind)
	mode = {"bike": Mode.BIKE, "scooter": Mode.SCOOTER, "moped": Mode.MOPED, "car": Mode.CAR}[sp["mode"]]
	foot_shape.disabled = true
	ride_shape.disabled = mode == Mode.CAR
	car_shape.disabled = mode != Mode.CAR
	if sp.has("seat"):
		model.position = Vector3(sp["seat"][0], sp["seat"][1], sp["seat"][2])
	match mode:
		Mode.SCOOTER:
			_play("mount_scooter", true)
		Mode.CAR:
			_play("sit", true)
			Sfx.play("lock", 0.5)
		_:
			_play("mount_bike", true)
	busy = 0.5
	speed = 0.0
	Vehicles.apply_upgrades(vm, kind)


func dismount() -> Node3D:
	var vm = vehicle_model
	var bs: Array = Game.veh(vehicle_kind)["box"] if vehicle_kind != "" else [0.5, 1.0, 1.5]
	if vm:
		visual.remove_child(vm)
	vehicle_model = null
	vehicle_kind = ""
	mode = Mode.FOOT
	foot_shape.disabled = false
	ride_shape.disabled = true
	car_shape.disabled = true
	model.position = Vector3.ZERO
	speed = 0.0
	lean = 0.0
	visual.rotation = Vector3.ZERO
	_play("idle", true)
	# step off to a spot that is clear of walls, props AND the vehicle that is parked right here.
	# (test_move from the old spot failed when a crash had pressed the rider into a wall: every step "hit" the wall,
	# the courier stayed put, the bike was parked inside them and they were stuck between it and the wall)
	var side = Vector3(cos(heading), 0, -sin(heading))
	var back = -Vector3(sin(heading), 0, cos(heading))
	global_position = free_spot(global_position, [side, -side, back, -back], heading, Vector2(bs[0], bs[2]))
	velocity = Vector3.ZERO
	last_out = global_position if not _inside_at(global_position) else last_out
	return vm


## Nearest spot around `from` where the courier on foot stands free: the foot capsule touches nothing, it is not
## inside a building, the ground is about the same height, and it is out of the footprint `box` (x, z) of a vehicle
## parked at `from` with yaw `yaw`. Tries the `prefer` directions first, then a ring; `from` itself if nothing fits.
func free_spot(from: Vector3, prefer: Array, yaw = 0.0, box = Vector2.ZERO) -> Vector3:
	var q = PhysicsShapeQueryParameters3D.new()
	q.shape = foot_shape.shape
	q.collision_mask = collision_mask
	q.exclude = [get_rid()]
	q.margin = 0.03
	var space = get_world_3d().direct_space_state
	var ax = Vector3(cos(yaw), 0, -sin(yaw))
	var az = Vector3(sin(yaw), 0, cos(yaw))
	var dirs: Array = prefer.duplicate()
	for k in 16:
		dirs.append(Vector3(cos(TAU * k / 16.0), 0, sin(TAU * k / 16.0)))
	var base = max(box.x * 0.5 + 0.4, 0.6)
	for dist in [base, base + 0.35, base + 0.8, base + 1.4, base + 2.2]:
		for dv in dirs:
			var p: Vector3 = from + (dv as Vector3).normalized() * dist
			var d = p - from
			if abs(d.dot(ax)) < box.x * 0.5 + 0.32 and abs(d.dot(az)) < box.y * 0.5 + 0.32:
				continue
			if world and world.level:
				var gh: float = world.level.ground_height(p)
				if abs(gh - from.y) > 0.7:
					continue
				p.y = gh
			if _inside_at(p):
				continue
			q.transform = Transform3D(Basis(), p + Vector3(0, foot_shape.position.y + 0.12, 0))
			if space.intersect_shape(q, 1).is_empty():
				return p + Vector3(0, 0.05, 0)
	return from


## True when the active collision shape is pushed into something (a wall, a parked vehicle): not just touching it.
func _overlapping() -> bool:
	var cs: CollisionShape3D = foot_shape if mode == Mode.FOOT else (car_shape if mode == Mode.CAR else ride_shape)
	# a copy shrunk by 6 cm: leaning on a wall is fine, sitting 6+ cm inside one is not
	if not _probe.has(cs):
		var s = cs.shape
		if s is CapsuleShape3D:
			var c = CapsuleShape3D.new()
			c.radius = s.radius - 0.06
			c.height = s.height - 0.12
			_probe[cs] = c
		else:
			var b = BoxShape3D.new()
			b.size = (s as BoxShape3D).size - Vector3(0.12, 0.12, 0.12)
			_probe[cs] = b
	var q = PhysicsShapeQueryParameters3D.new()
	q.shape = _probe[cs]
	q.collision_mask = collision_mask
	q.exclude = [get_rid()]
	q.margin = 0.0
	q.transform = global_transform * cs.transform.translated(Vector3(0, 0.08, 0))
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## True when a point is inside a solid building box of the level (Level._solidify): the courier must never be there.
func _inside_at(p: Vector3) -> bool:
	if world == null or world.level == null:
		return false
	var q = PhysicsPointQueryParameters3D.new()
	q.position = p + Vector3(0, 0.9, 0)
	q.collision_mask = 1
	for r in get_world_3d().direct_space_state.intersect_point(q, 4):
		var c = r.get("collider")
		if c is StaticBody3D and world.level.is_ancestor_of(c):
			return true
	return false


## Force field: if the courier ever ends up inside a building (a teleport, a glitch), put them back on the street.
func _guard_inside(delta: float) -> void:
	_inside_t -= delta
	if _inside_t > 0.0:
		return
	_inside_t = 0.2
	if _inside_at(global_position):
		global_position = last_out + Vector3(0, 0.15, 0)
		velocity = Vector3.ZERO
		speed = 0.0
		hint("inside", "В дома заходить нельзя — только через подъезд (E у двери).", 10.0)
	elif is_on_floor():
		last_out = global_position
	# wedged: pushing for over a second, not moving, and the body sits inside a wall / the parked vehicle
	var moved = Vector2(global_position.x - _stuck_pos.x, global_position.z - _stuck_pos.z).length()
	_stuck_pos = global_position
	if _want_move and busy <= 0.0 and moved < 0.06:
		_stuck_t += 0.2
	else:
		_stuck_t = 0.0
	# 1 s wedged into something; on foot also 4 s of pushing without moving an inch (whatever holds the courier):
	# step to the nearest free spot. (Riding against a wall with the throttle on is not "stuck".)
	var wedged = _stuck_t >= 1.0 and _overlapping()
	if wedged or (_stuck_t >= 4.0 and not riding()):
		_stuck_t = 0.0
		if riding():
			world.dismount_here()     # free_spot() inside dismount() puts the courier clear of it all
		else:
			global_position = free_spot(global_position, [])
		velocity = Vector3.ZERO
		speed = 0.0
		print("unstuck -> ", global_position)


func fall(seconds = 2.5) -> void:
	if fallen > 0.0:
		return
	var helmet: String = Game.state.get("helmet", "")
	if helmet != "":
		seconds *= 0.5
	fallen = seconds + 1.6
	busy = fallen
	speed = 0.0
	Sfx.play("crash")
	Sfx.play("fall")
	Game.state["stats"]["falls"] += 1
	_play("fall_tumble", true)
	world.on_fall()


# ---------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var k = float(Game.settings["mouse_sens"]) * 0.01
		cyaw -= event.relative.x * k
		var inv = -1.0 if Game.settings["invert_y"] else 1.0
		cam_pitch = clamp(cam_pitch - event.relative.y * k * inv, -1.1, 0.25)
		cam_idle = 0.0


func _physics_process(delta: float) -> void:
	if world == null or not world.started:
		return
	crash_cd = max(0.0, crash_cd - delta)
	surface = world.level.surface_at(global_position)
	var ax = 0.0
	var ay = 0.0
	var ok: bool = control and busy <= 0.0 and world.ui_free()
	if ok:
		ax = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
		ay = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	_want_move = Vector2(ax, ay).length() > 0.3
	if not autopilot.is_empty() and mode != Mode.FOOT:
		# trailer / demo driving: steer toward the next waypoint
		var tgt: Vector3 = autopilot[0]
		var d = Vector2(tgt.x - global_position.x, tgt.z - global_position.z)
		if d.length() < 2.2:
			autopilot.remove_at(0)
		else:
			var diff = wrapf(atan2(d.x, d.y) - heading, -PI, PI)
			ax = clamp(-diff * 2.2, -1.0, 1.0)
			ay = autopilot_throttle * (0.6 if abs(diff) > 0.8 else 1.0)
	var lookx = Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
	if abs(lookx) > 0.1:
		cyaw -= lookx * 2.4 * delta
		cam_idle = 0.0
	if busy > 0.0:
		busy -= delta
		if fallen > 0.0:
			fallen -= delta
			if fallen < 1.0 and cur_anim == "lying":
				_play("get_up", true)
			elif cur_anim == "fall_tumble" and not anim.is_playing():
				_play("lying", true)
			if fallen <= 0.0:
				_play("idle", true)
	if mode == Mode.FOOT:
		_foot(delta, ax, ay)
	else:
		_ride(delta, ax, ay)
	_gravity_and_move(delta)
	_guard_inside(delta)
	_stats(delta)
	_camera(delta)
	_animate(delta)
	if global_position.y < float(Game.layout.get("kill_y", -8.0)):
		global_position = last_safe + Vector3(0, 0.5, 0)
		velocity = Vector3.ZERO
		world.toast("Ой! Курьер выбрался на берег. Еда немного промокла.", 3.0)
		world.orders.damage_food(15.0, "water")
	elif is_on_floor() and surface in ["c", "s", "a", "p", "z", "b", "g"]:
		last_safe = global_position


func _foot(delta: float, ax: float, ay: float) -> void:
	var input = Vector2(ax, ay)
	if input.length() > 1.0:
		input = input.normalized()
	var cy = cam_pivot.rotation.y + PI  # forward of the camera as seen on screen (incl. the auto swing off walls)
	var fwd = Vector3(sin(cy), 0, cos(cy))
	var right = Vector3(-cos(cy), 0, sin(cy))
	var dir = fwd * input.y + right * input.x
	var target = dir * max_speed() * surface_mult()[0]
	var hv = Vector3(velocity.x, 0, velocity.z)
	hv = hv.move_toward(target, (18.0 if dir.length() > 0.1 else 22.0) * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if hv.length() > 0.3:
		var want = atan2(hv.x, hv.z)
		heading = lerp_angle(heading, want, clamp(12.0 * delta, 0.0, 1.0))
	rotation.y = heading
	speed = hv.length()
	if Input.is_action_pressed("sprint") and speed > WALK + 0.2:
		stamina = max(0.0, stamina - 9.0 * delta)


func _ride(delta: float, ax: float, ay: float) -> void:
	var sm = surface_mult()
	var vmax: float = max_speed() * sm[0]
	var sp: Dictionary = Game.veh(vehicle_kind)
	var electric = Game.is_electric(vehicle_kind)
	var accel = float(sp["accel"])
	if electric and world.battery <= 0.0:
		accel = 3.6 if mode == Mode.BIKE else 1.0
	var braking = Input.is_action_pressed("brake") and control
	if ay > 0.05:
		if speed < 0.0:
			speed = move_toward(speed, 0.0, 12.0 * delta)
		else:
			speed = move_toward(speed, vmax * ay, accel * delta * (1.0 if speed < vmax else 3.0))
	elif ay < -0.05:
		if speed > 0.3:
			speed = move_toward(speed, 0.0, 9.0 * delta)
			_hard_brake_check(9.0)
		else:
			speed = move_toward(speed, -1.6, 3.0 * delta)
	else:
		speed = move_toward(speed, 0.0, 1.4 * delta)
	if braking:
		var dec = 11.0 if Game.upgrade_level("brakes") > 0 else 13.0
		if speed > 4.0:
			_hard_brake_check(dec)
		speed = move_toward(speed, 0.0, dec * delta)
	# stairs / park / sidewalk bans per vehicle (Game.VEH "ban")
	var ban: String = sp["ban"]
	if ban != "" and abs(speed) > 0.05:
		var reach = 1.9 if mode == Mode.CAR else 1.1
		var ahead = global_position + Vector3(sin(heading), 0, cos(heading)) * (reach if speed >= 0.0 else -reach)
		var sa: String = world.level.surface_at(ahead)
		if sa != "" and ban.contains(sa) and not ban.contains(surface):
			speed = 0.0
			match sa:
				"t":
					hint("stairs", "По лестнице на этом не проехать. Слезь (F) или найди объезд.")
				"s":
					hint("ban_s", "Электромобиль — только по проезжей части. Припаркуйся у тротуара (F) и дойди пешком.")
				_:
					hint("ban_p", "В парк и на пешеходные дорожки на моторе нельзя. Оставь транспорт (F) и иди пешком.")
	var turn_rate: float = lerp(2.6, 1.25, clamp(abs(speed) / 9.0, 0.0, 1.0)) * (0.8 if mode == Mode.CAR else 1.0)
	steer = move_toward(steer, -ax, 5.0 * delta)
	if abs(speed) > 0.2:
		heading += steer * turn_rate * delta * sign(speed) * clamp(abs(speed) / 1.5, 0.3, 1.0)
	rotation.y = heading
	var fwd = Vector3(sin(heading), 0, cos(heading))
	var hv = Vector3(velocity.x, 0, velocity.z)
	var want = fwd * speed
	hv = hv.lerp(want, clamp(float(sm[1]) * 9.0 * delta, 0.0, 1.0))
	velocity.x = hv.x
	velocity.z = hv.z
	lean = lerp(lean, -steer * clamp(abs(speed) / 7.0, 0.0, 1.0) * (0.04 if mode == Mode.CAR else 0.32), clamp(6.0 * delta, 0.0, 1.0))
	visual.rotation.z = lean
	# effort
	if mode == Mode.BIKE and ay > 0.05:
		var use = 2.2 * ay * (1.8 if Input.is_action_pressed("sprint") else 1.0)
		if surface == "t":
			use *= 3.0
		if electric and world.battery > 0.0:
			use *= 0.3
		stamina = max(0.0, stamina - use * delta)
	if electric and abs(speed) > 0.5:
		world.drain_battery(abs(speed) * delta)
	if float(sm[2]) > 0.0 and abs(speed) > 3.0:
		world.orders.shake_food(float(sm[2]) * abs(speed) * delta * 0.04)
		shake = max(shake, float(sm[2]) * 0.02)


func _hard_brake_check(dec: float) -> void:
	if crash_cd > 0.0 or abs(speed) < 5.0:
		return
	crash_cd = 1.2
	if Game.upgrade_level("brakes") == 0:
		world.orders.damage_food(4.0 + abs(speed) * 0.6, "brake")
	Sfx.play("brake", 0.6)


func _gravity_and_move(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = max(velocity.y, -1.0)
	var before = Vector3(velocity.x, 0, velocity.z)
	move_and_slide()
	if mode != Mode.FOOT:
		var after = Vector3(velocity.x, 0, velocity.z)
		var fwd = Vector3(sin(heading), 0, cos(heading))
		var lost = before.dot(fwd) - after.dot(fwd)
		if get_slide_collision_count() > 0 and lost > 1.0:
			speed = after.dot(fwd)
			if lost > 4.5 and crash_cd <= 0.0:
				crash_cd = 1.5
				_crash(lost)


func _crash(impact: float) -> void:
	shake = 0.35
	world.orders.damage_food(impact * 4.0, "crash")
	Sfx.play("crash", clamp(impact / 8.0, 0.3, 1.0))
	if impact > 6.5:
		fall(2.5)
	else:
		world.toast("Бум! Аккуратнее — еда в сумке!", 1.6)


func _stats(delta: float) -> void:
	var h_rate = 0.55
	if world.daynight.heat > 0.3:
		h_rate += 0.25
	hunger = min(100.0, hunger + h_rate * delta / 6.0)
	if mode != Mode.BIKE or speed < 0.5:
		stamina = min(100.0, stamina + (6.0 if speed < 0.5 else 2.5) * delta)
	if world.daynight.snow > 0.3 and mode != Mode.CAR and not Game.has_gear("warm_gloves"):
		stamina = max(0.0, stamina - 0.35 * delta)
		hint("cold", "Брр, холодно! Тёплые перчатки и шапка — в мастерской (вкладка «Экипировка»).", 60.0)
	if world.daynight.rain > 0.5 and mode != Mode.CAR and not Game.has_gear("raincoat"):
		wet = min(100.0, wet + 2.0 * delta)
		stamina = max(0.0, stamina - 0.4 * delta)
	else:
		wet = max(0.0, wet - 3.0 * delta)
	phone = max(0.0, phone - delta * 0.028)
	if stamina < 12.0:
		hint("tired", "Курьер выдохся! Перекус, кофе или скамейка (E).")
	if hunger > 80.0:
		hint("hungry", "Желудок урчит. Купи перекус в ларьке или используй из сумки (X).")
	if phone < 15.0:
		hint("phone", "Телефон садится! Павербанк (X) или зарядка в кафе.")
	on_sidewalk = surface == "s" and mode != Mode.FOOT and speed > 3.0


func hint(id: String, text: String, cd = 25.0) -> void:
	var now = Time.get_ticks_msec() / 1000.0
	if now < float(_hint_cd.get(id, -1000.0)):
		return
	_hint_cd[id] = now + cd
	world.toast(text, 3.5)


## Chase camera. The courier must always be visible:
## - rays from the head to the camera against buildings (and camera-only boxes around balconies and roofs):
##   the camera snaps in front of a wall at once and eases back out when the view clears;
## - if a wall keeps blocking the view, the camera swings sideways to a clear angle (only while the player is
##   not turning it by hand), and returns behind the courier when the way is clear again;
## - trees, lamp posts, stops and other props between the camera and the courier turn see-through.
func _camera(delta: float) -> void:
	var head = global_position + Vector3(0, 1.55 if mode == Mode.FOOT else (2.1 if mode == Mode.CAR else 1.75), 0)
	var piv = cam_pivot.global_position.lerp(head, clamp(16.0 * delta, 0.0, 1.0))
	if piv.distance_squared_to(head) > 0.01 and _ray(head, piv).size() > 0:
		piv = head    # the lagging pivot cut a corner through a wall
	cam_pivot.global_position = piv
	if cam_idle == 0.0 and cam_avoid != 0.0:
		# the player took the camera: keep the current view, drop the automatic offset
		cyaw += cam_avoid
		cam_avoid = 0.0
		_avoid_target = 0.0
	cam_idle += delta
	var behind = heading + PI
	if mode != Mode.FOOT:
		if cam_idle > 1.0 or abs(speed) > 1.5:
			cyaw = lerp_angle(cyaw, behind, clamp((1.1 + abs(speed) * 0.22) * delta, 0.0, 1.0))
	elif cam_idle > 2.5 and speed > 0.5:
		cyaw = lerp_angle(cyaw, behind, clamp(1.2 * delta, 0.0, 1.0))
	var L = 4.2 if mode == Mode.FOOT else (6.6 if mode == Mode.CAR else 5.2) + abs(speed) * 0.08
	cam_len = lerp(cam_len, L, clamp(3.0 * delta, 0.0, 1.0))
	_probe_t -= delta
	if _probe_t <= 0.0:
		_probe_t = 0.15
		_probe_avoid(piv)
	cam_avoid = lerp_angle(cam_avoid, _avoid_target, clamp(2.2 * delta, 0.0, 1.0))
	cam_pivot.rotation.y = lerp_angle(cam_pivot.rotation.y, cyaw + cam_avoid, clamp(9.0 * delta, 0.0, 1.0))
	cam_pivot.rotation.x = lerp(cam_pivot.rotation.x, cam_pitch, clamp(8.0 * delta, 0.0, 1.0))
	var free = _cam_free(piv, cam_pivot.global_transform.basis, cam_len)
	if free < cam_dist:
		cam_dist = free
	else:
		cam_dist = lerp(cam_dist, free, clamp(2.5 * delta, 0.0, 1.0))
	camera.position = Vector3(0, 0, cam_dist)
	_fade_props(head, delta)
	camera.fov = lerp(camera.fov, 66.0 + abs(speed) * 0.9, clamp(3.0 * delta, 0.0, 1.0))
	if shake > 0.0:
		shake = max(0.0, shake - delta)
		camera.h_offset = randf_range(-1, 1) * shake * 0.3
		camera.v_offset = randf_range(-1, 1) * shake * 0.3
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var ex: Array[RID] = [get_rid()]
	if not world.parked.is_empty() and is_instance_valid(world.parked["body"]):
		ex.append((world.parked["body"] as StaticBody3D).get_rid())   # the parked bike must not shove the camera
	var q = PhysicsRayQueryParameters3D.create(a, b, CAM_MASK, ex)
	q.hit_from_inside = false
	return get_world_3d().direct_space_state.intersect_ray(q)


## Free distance from the head along the camera boom (+Z of the pivot basis): centre ray + four rays around it
## (the near plane is wider than a point). A box the head is inside of (a shop awning) is ignored by the rays.
func _cam_free(from: Vector3, b: Basis, length: float) -> float:
	var dir = b.z.normalized()
	var best = length
	for o in [Vector3.ZERO, b.x * 0.3, -b.x * 0.3, b.y * 0.25, -b.y * 0.2]:
		var off: Vector3 = o
		var h = _ray(from + off * 0.3, from + off + dir * (length + 0.3))
		if not h.is_empty():
			best = min(best, (h["position"] - from).dot(dir) - 0.3)
	return clamp(best, 0.35, length)


## Look for a clear angle when a wall hides the courier; come back behind them when the way is clear.
func _probe_avoid(piv: Vector3) -> void:
	var pitch = cam_pivot.rotation.x
	var want = cam_len * 0.8
	var free_home = _cam_free(piv, Basis.from_euler(Vector3(pitch, cyaw, 0)), cam_len)
	if free_home >= want or cam_idle < 0.7:
		_avoid_target = 0.0
		return
	var free_now = _cam_free(piv, Basis.from_euler(Vector3(pitch, cyaw + _avoid_target, 0)), cam_len)
	if _avoid_target != 0.0 and free_now >= want:
		return    # keep the clear angle found before (no flip-flopping)
	var sgn = 1.0 if _avoid_target >= 0.0 else -1.0
	var best = _avoid_target
	var best_free = free_now
	for a in [0.45, 0.85, 1.25, 1.65]:
		for s in [sgn, -sgn]:
			var f = _cam_free(piv, Basis.from_euler(Vector3(pitch, cyaw + a * s, 0)), cam_len)
			if f > best_free + 0.4:
				best_free = f
				best = a * s
		if best_free >= want:
			break
	_avoid_target = best


## Props between the camera and the courier (trees, lamp posts, stops, kiosks) fade to see-through.
func _fade_props(head: Vector3, delta: float) -> void:
	if has_meta("no_fade"):
		if get_meta("no_fade"):
			return
	var items: Array = world.level.fade_items
	var cp = camera.global_position
	var chest = head - Vector3(0, 0.5, 0)
	for i in items.size():
		var it: Dictionary = items[i]
		var ab: AABB = it["aabb"]
		var want = 0.0
		if ab.get_center().distance_squared_to(head) < 900.0:
			var g = ab.grow(0.15)
			if g.has_point(cp):
				want = 1.0     # the camera is inside the crown: hide it, a see-through crown still tints the screen
			elif g.intersects_segment(cp, head) or g.intersects_segment(cp, chest):
				want = FADE
		var cur: float = _faded.get(i, 0.0)
		if want == cur:
			continue
		cur = move_toward(cur, want, 4.0 * delta)
		for m in it["meshes"]:
			var mi: MeshInstance3D = m
			if is_instance_valid(mi):
				mi.transparency = cur
		if cur <= 0.0:
			_faded.erase(i)
		else:
			_faded[i] = cur


func reset_camera() -> void:
	cyaw = heading + PI
	cam_pitch = -0.32
	cam_avoid = 0.0
	_avoid_target = 0.0
	cam_pivot.rotation.y = cyaw


# ---------------------------------------------------------------- animation
func _play(name: String, force = false) -> void:
	if anim == null or not anim.has_animation(name):
		return
	if name == cur_anim and not force:
		return
	cur_anim = name
	anim.play(name, 0.18)


func _animate(delta: float) -> void:
	if held_box:
		held_box.visible = carrying and mode == Mode.FOOT
	if busy > 0.0:
		return
	var hs = Vector3(velocity.x, 0, velocity.z).length()
	match mode:
		Mode.FOOT:
			if hs < 0.25:
				if world.ui_phone_open():
					_play("phone_check")
				else:
					_play("carry_idle" if carrying else "idle")
				anim.speed_scale = 1.0
			elif hs < 3.6:
				_play("carry" if carrying else ("tired_walk" if stamina < 12.0 else "walk"))
				anim.speed_scale = hs / (ANIM_WALK_SPEED * (0.6 if cur_anim == "tired_walk" else 1.0))
			else:
				_play("run")
				anim.speed_scale = hs / ANIM_RUN_SPEED
			_step_t += hs * delta
			if _step_t > 0.8 and is_on_floor():
				_step_t = 0.0
				Sfx.play("step", 0.25, randf_range(0.9, 1.1))
			Sfx.set_loop("pedal_loop", 0.0)
			Sfx.set_loop("motor_loop", 0.0)
		Mode.BIKE:
			if abs(speed) < 0.3:
				_play("ride_bike_idle")
				anim.speed_scale = 1.0
			else:
				_play("ride_bike")
				anim.speed_scale = max(0.2, abs(speed) / CRANK_M)
			Vehicles.spin(vehicle_model, speed, steer, delta, anim.speed_scale if cur_anim == "ride_bike" else 0.0)
			Sfx.set_loop("pedal_loop", clamp(abs(speed) / 7.0, 0.0, 1.0) * 0.45, 0.8 + abs(speed) * 0.05)
			var e_on = Game.is_electric(vehicle_kind) and world.battery > 0.0 and abs(speed) > 0.5
			Sfx.set_loop("motor_loop", 0.12 if e_on else 0.0, 1.1 + abs(speed) * 0.05)
			if Game.is_electric(vehicle_kind):
				Vehicles.battery_color(vehicle_model, world.battery)
		_:
			var ride_anim = "ride_scooter" if mode == Mode.SCOOTER else ("sit" if mode == Mode.CAR else "ride_bike_idle")
			_play(ride_anim)
			anim.speed_scale = 1.0
			Vehicles.spin(vehicle_model, speed, steer, delta, 0.0)
			Vehicles.battery_color(vehicle_model, world.battery)
			var vol = (0.12 + clamp(abs(speed) / 12.0, 0.0, 1.0) * 0.35) if world.battery > 0 else 0.0
			Sfx.set_loop("motor_loop", vol * (0.6 if mode == Mode.CAR else 1.0),
				(0.55 if mode == Mode.CAR else 0.7) + abs(speed) * (0.06 if mode != Mode.SCOOTER else 0.09))
			Sfx.set_loop("pedal_loop", 0.0)
