class_name Player
extends CharacterBody3D
## The courier: walking, cycling, e-scooter. Arcade vehicle model, chase camera, stats, animations.
## Model front is +Z (Blender -Y). heading = rotation.y; forward = (sin h, 0, cos h).

enum Mode { FOOT, BIKE, SCOOTER }

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
var vehicle_kind = ""      # "bicycle" / "scooter" when riding
var vehicle_model: Node3D
var cur_anim = ""
var cam_pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var cyaw = 0.0             # camera yaw in world space (behind = heading + PI)
var cam_pitch = -0.32
var cam_idle = 0.0
var foot_shape: CollisionShape3D
var ride_shape: CollisionShape3D
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
	collision_mask = 1 | 4
	floor_snap_length = 0.4
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
	var bx = BoxShape3D.new()
	bx.size = Vector3(0.6, 1.4, 1.5)
	ride_shape.shape = bx
	ride_shape.position.y = 0.75
	ride_shape.disabled = true
	add_child(ride_shape)
	visual = Node3D.new()
	add_child(visual)
	var bl = Chars.blob(self, 0.6)
	bl.scale = Vector3(1.0, 1.0, 1.6)
	build_model()
	cam_pivot = Node3D.new()
	cam_pivot.top_level = true
	add_child(cam_pivot)
	spring = SpringArm3D.new()
	spring.spring_length = 4.6
	spring.margin = 0.3
	spring.collision_mask = 1
	var sh = SphereShape3D.new()
	sh.radius = 0.25
	spring.shape = sh
	spring.add_excluded_object(get_rid())
	cam_pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.far = 900.0
	spring.add_child(camera)
	camera.current = true
	cam_pivot.global_position = global_position + Vector3(0, 1.7, 0)
	cyaw = heading + PI
	last_safe = global_position


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
		Mode.BIKE:
			return BIKE_MAX * m * (1.12 if Input.is_action_pressed("sprint") and stamina > 10.0 else 1.0) * (0.45 if world.events.flat else 1.0)
		Mode.SCOOTER:
			var bat: float = world.battery
			var s = SCOOT_MAX * (1.0 + 0.12 * Game.upgrade_level("motor"))
			if bat <= 0.0:
				return 1.2
			if bat < 12.0:
				s *= 0.55
			return s * (0.45 if world.events.flat else 1.0)
	return WALK


func surface_mult() -> Array:
	# [speed factor, grip, shake]
	var c = surface
	var rain: float = world.daynight.rain
	var tires = Game.upgrade_level("tires") > 0
	match mode:
		Mode.FOOT:
			return [0.85 if c == "g" else 1.0, 1.0, 0.0]
		Mode.BIKE:
			var f = {"c": 0.92, "g": 0.7, "t": 0.45, "s": 0.95}.get(c, 1.0)
			return [f, 0.9 - rain * 0.2, 0.6 if c == "c" else (1.2 if c == "t" else 0.1)]
		Mode.SCOOTER:
			var f2 = {"c": 0.72, "g": 0.5, "s": 0.95}.get(c, 1.0)
			var grip = 0.85 - (0.4 if c == "c" else 0.0) - rain * 0.35
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
	mode = Mode.BIKE if kind == "bicycle" else Mode.SCOOTER
	foot_shape.disabled = true
	ride_shape.disabled = false
	_play("mount_bike" if kind == "bicycle" else "mount_scooter", true)
	busy = 0.5
	speed = 0.0
	Vehicles.apply_upgrades(vm, kind)


func dismount() -> Node3D:
	var vm = vehicle_model
	if vm:
		visual.remove_child(vm)
	vehicle_model = null
	vehicle_kind = ""
	mode = Mode.FOOT
	foot_shape.disabled = false
	ride_shape.disabled = true
	speed = 0.0
	lean = 0.0
	visual.rotation = Vector3.ZERO
	_play("idle", true)
	# step to the side so the parked vehicle is free
	var side = Vector3(cos(heading), 0, -sin(heading))
	global_position += side * 0.75
	return vm


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
	var cy = cyaw + PI  # camera forward yaw
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
	var accel = 4.2 if mode == Mode.BIKE else 6.0
	if mode == Mode.SCOOTER and world.battery <= 0.0:
		accel = 1.0
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
	# stairs: scooter cannot go down/up stairs
	if mode == Mode.SCOOTER:
		var ahead = global_position + Vector3(sin(heading), 0, cos(heading)) * (1.1 if speed >= 0.0 else -1.1)
		if world.level.surface_at(ahead) == "t":
			speed = 0.0
			hint("stairs", "Самокат по лестнице не проедет. Слезь (F) или найди объезд.")
	var turn_rate: float = lerp(2.6, 1.25, clamp(abs(speed) / 9.0, 0.0, 1.0))
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
	lean = lerp(lean, -steer * clamp(abs(speed) / 7.0, 0.0, 1.0) * 0.32, clamp(6.0 * delta, 0.0, 1.0))
	visual.rotation.z = lean
	# effort
	if mode == Mode.BIKE and ay > 0.05:
		var use = 2.2 * ay * (1.8 if Input.is_action_pressed("sprint") else 1.0)
		if surface == "t":
			use *= 3.0
		stamina = max(0.0, stamina - use * delta)
	elif mode == Mode.SCOOTER and abs(speed) > 0.5:
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
	if world.daynight.rain > 0.5 and not Game.has_gear("raincoat"):
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


func _camera(delta: float) -> void:
	var target = global_position + Vector3(0, 1.55 if mode == Mode.FOOT else 1.75, 0)
	cam_pivot.global_position = cam_pivot.global_position.lerp(target, clamp(14.0 * delta, 0.0, 1.0))
	cam_idle += delta
	var behind = heading + PI
	if mode != Mode.FOOT:
		if cam_idle > 1.2 or abs(speed) > 2.0:
			cyaw = lerp_angle(cyaw, behind, clamp((1.5 + abs(speed) * 0.4) * delta, 0.0, 1.0))
	elif cam_idle > 2.5 and speed > 0.5:
		cyaw = lerp_angle(cyaw, behind, clamp(1.2 * delta, 0.0, 1.0))
	cam_pivot.rotation.y = lerp_angle(cam_pivot.rotation.y, cyaw, clamp(10.0 * delta, 0.0, 1.0))
	cam_pivot.rotation.x = lerp(cam_pivot.rotation.x, cam_pitch, clamp(8.0 * delta, 0.0, 1.0))
	var L = 4.2 if mode == Mode.FOOT else 5.2 + abs(speed) * 0.08
	spring.spring_length = lerp(spring.spring_length, L, clamp(3.0 * delta, 0.0, 1.0))
	camera.fov = lerp(camera.fov, 66.0 + abs(speed) * 0.9, clamp(3.0 * delta, 0.0, 1.0))
	if shake > 0.0:
		shake = max(0.0, shake - delta)
		camera.h_offset = randf_range(-1, 1) * shake * 0.3
		camera.v_offset = randf_range(-1, 1) * shake * 0.3
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func reset_camera() -> void:
	cyaw = heading + PI
	cam_pitch = -0.32
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
			Sfx.set_loop("motor_loop", 0.0)
		Mode.SCOOTER:
			_play("ride_scooter")
			anim.speed_scale = 1.0
			Vehicles.spin(vehicle_model, speed, steer, delta, 0.0)
			Vehicles.battery_color(vehicle_model, world.battery)
			Sfx.set_loop("motor_loop", (0.12 + clamp(abs(speed) / 9.0, 0.0, 1.0) * 0.35) if world.battery > 0 else 0.0,
				0.7 + abs(speed) * 0.09)
			Sfx.set_loop("pedal_loop", 0.0)
