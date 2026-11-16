extends Node
## Global state: progress, settings, catalogue, save/load, input map. Autoload "Game".

const VERSION = "0.1.0"
const SAVE_PATH = "user://save.json"
const SETTINGS_PATH = "user://settings.json"
const LEVEL = "old_town"

const C_TURQ = Color("22b8b0")
const C_TURQ_D = Color("17807b")
const C_CREAM = Color("fbf3e2")
const C_INK = Color("2f2a33")
const C_CORAL = Color("ef6a5b")
const C_SUN = Color("f6c945")
const C_MINT = Color("8fd3b0")
const C_SKY = Color("7ec3e8")

var args: PackedStringArray
var go_play = false     # skip the title menu (next day / continue)
var flags = {}          # parsed debug flags after "--"

var settings = {
	"music": 0.6, "sfx": 0.8, "quality": 1, "mouse_sens": 0.22, "invert_y": false, "touch": "auto",
	"shadows": true, "fullscreen": false,
}

var state = {}

## Catalogue: id -> {name, price, kind, desc}
const SHOP = {
	"scooter": {"name": "Электросамокат", "price": 300, "kind": "vehicle", "desc": "Быстрее велосипеда, но нужна зарядка. Хуже на брусчатке и в дождь."},
	"battery": {"name": "Батарея+", "price": 120, "kind": "upgrade", "max": 2, "desc": "Запас хода самоката +40% за уровень."},
	"motor": {"name": "Мотор+", "price": 150, "kind": "upgrade", "max": 2, "desc": "Скорость самоката +12% за уровень."},
	"tires": {"name": "Широкие шины", "price": 90, "kind": "upgrade", "max": 1, "desc": "Сцепление на брусчатке и в дождь. Меньше проколов."},
	"brakes": {"name": "Тормоза", "price": 60, "kind": "upgrade", "max": 1, "desc": "Резкое торможение не портит еду."},
	"rack": {"name": "Багажник", "price": 110, "kind": "upgrade", "max": 1, "desc": "Два заказа сразу и большие заказы для офисов."},
	"lock": {"name": "Замок", "price": 40, "kind": "upgrade", "max": 1, "desc": "Транспорт не угонят, если пристегнуть (L)."},
	"headlight": {"name": "Фара", "price": 50, "kind": "upgrade", "max": 1, "desc": "Ночью виднее и нет штрафа за езду без света."},
	"mudguards": {"name": "Крылья", "price": 35, "kind": "upgrade", "max": 1, "desc": "Лужи не забрызгивают — рейтинг не падает в дождь."},
	"raincoat": {"name": "Дождевик", "price": 45, "kind": "gear", "desc": "Курьер не мокнет и не устаёт под дождём."},
	"waterproof_bag": {"name": "Непромокаемая сумка", "price": 70, "kind": "gear", "desc": "Еда не промокает."},
	"cooling_pack": {"name": "Хладоэлементы", "price": 40, "kind": "gear", "desc": "Мороженое и суши дольше холодные."},
	"cup_holder": {"name": "Подстаканник", "price": 30, "kind": "gear", "desc": "Напитки почти не проливаются."},
	"soft_bag": {"name": "Мягкая вставка", "price": 55, "kind": "gear", "desc": "Торты и хрупкое меньше страдают от тряски."},
	"helmet_bike": {"name": "Велошлем", "price": 35, "kind": "helmet", "desc": "После падения встаёшь вдвое быстрее."},
	"helmet_half": {"name": "Полушлем", "price": 55, "kind": "helmet", "desc": "Стильно и безопасно."},
	"helmet_retro": {"name": "Ретро-шлем", "price": 80, "kind": "helmet", "desc": "Клиенты чаще дают чаевые (+10%)."},
	"powerbank": {"name": "Павербанк", "price": 15, "kind": "consumable", "desc": "Заряжает телефон или самокат на ходу (+50%)."},
	"energy_drink": {"name": "Энергетик", "price": 8, "kind": "consumable", "desc": "+60 выносливости, но голод растёт быстрее."},
	"snack": {"name": "Перекус", "price": 6, "kind": "consumable", "desc": "Снимает голод."},
	"repair_kit": {"name": "Ремкомплект", "price": 12, "kind": "consumable", "desc": "Заклеить прокол на месте."},
}
const SCOOTER_RENT = 18
const JACKETS = ["#22b8b0", "#3f7fc9", "#5fae4e", "#f2a7a0", "#f6c945", "#b9a3d8", "#33302e"]
const HAIRS = ["short", "ponytail", "curly", "bun"]

var layout: Dictionary
var population: Dictionary
var orders_data: Dictionary
var events_data: Dictionary


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	args = OS.get_cmdline_user_args()
	_parse_flags()
	_build_input_map()
	load_settings()
	new_state()
	if has_save():
		load_game()
	_apply_window()


func _parse_flags() -> void:
	var i = 0
	while i < args.size():
		var a = args[i]
		if a.begins_with("--"):
			var key = a.substr(2)
			var vals: Array = []
			var j = i + 1
			while j < args.size() and not args[j].begins_with("--"):
				vals.append(args[j])
				j += 1
			flags[key] = vals
			i = j
		else:
			i += 1


func flag(name: String) -> bool:
	return flags.has(name)


func load_json(path: String) -> Variant:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("cannot open " + path)
		return {}
	return JSON.parse_string(f.get_as_text())


func load_level_data() -> void:
	if layout.is_empty():
		layout = load_json("res://assets/levels/%s_layout.json" % LEVEL)
		population = load_json("res://assets/levels/%s_population.json" % LEVEL)
		orders_data = load_json("res://assets/levels/%s_orders.json" % LEVEL)
		events_data = load_json("res://assets/levels/%s_events.json" % LEVEL)


# ---------------------------------------------------------------- state
func new_state() -> void:
	state = {
		"version": VERSION, "money": 25.0, "rating": 4.0, "votes": 5, "day": 1, "chapter": 1, "tutorial": 0,
		"owned": {"bicycle": true, "scooter": false}, "vehicle": "bicycle", "rented_today": false,
		"upgrades": {}, "gear": {}, "helmet": "", "items": {"snack": 1, "repair_kit": 0, "powerbank": 0, "energy_drink": 0},
		"look": {"gender": "m", "hair": "short", "jacket": "#22b8b0", "cap": true},
		"quests": {"cake": "locked", "office_lunch": "locked"},
		"stats": {"delivered": 0, "late": 0, "tips": 0.0, "fines": 0.0, "earned": 0.0, "spent": 0.0, "falls": 0},
		"daily": [], "seen_hints": {}, "best_streak": 0,
	}


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> void:
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(state, " "))


func load_game() -> bool:
	if not has_save():
		return false
	var d = load_json(SAVE_PATH)
	if typeof(d) != TYPE_DICTIONARY or d.is_empty():
		return false
	new_state()
	for k in d.keys():
		state[k] = d[k]
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	new_state()


func load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var d = load_json(SETTINGS_PATH)
		if typeof(d) == TYPE_DICTIONARY:
			for k in d.keys():
				settings[k] = d[k]


func save_settings() -> void:
	var f = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))
	_apply_window()


func _apply_window() -> void:
	if OS.has_feature("web") or OS.has_feature("mobile"):
		return
	if flag("autotest") or flag("tour"):
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED)


func is_touch() -> bool:
	if flag("touch"):
		return true
	if settings["touch"] == "on":
		return true
	if settings["touch"] == "off":
		return false
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") or DisplayServer.is_touchscreen_available()


# ---------------------------------------------------------------- economy helpers
func upgrade_level(id: String) -> int:
	return int(state["upgrades"].get(id, 0))


func has_gear(id: String) -> bool:
	return bool(state["gear"].get(id, false))


func item_count(id: String) -> int:
	return int(state["items"].get(id, 0))


func add_item(id: String, n = 1) -> void:
	state["items"][id] = item_count(id) + n


func use_item(id: String) -> bool:
	if item_count(id) <= 0:
		return false
	state["items"][id] = item_count(id) - 1
	return true


func can_buy(id: String) -> bool:
	var it: Dictionary = SHOP[id]
	if state["money"] < it["price"]:
		return false
	match it["kind"]:
		"vehicle":
			return not state["owned"].get(id, false)
		"upgrade":
			if id in ["battery", "motor", "tires"] and not state["owned"].get("scooter", false) and id != "tires":
				return false
			return upgrade_level(id) < int(it.get("max", 1))
		"gear":
			return not has_gear(id)
		"helmet":
			return not state["gear"].get(id, false)
	return true


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	var it: Dictionary = SHOP[id]
	spend(float(it["price"]))
	match it["kind"]:
		"vehicle":
			state["owned"][id] = true
		"upgrade":
			state["upgrades"][id] = upgrade_level(id) + 1
		"gear":
			state["gear"][id] = true
		"helmet":
			state["gear"][id] = true
			state["helmet"] = id
		"consumable":
			add_item(id)
	save_game()
	return true


func earn(v: float) -> void:
	state["money"] += v
	state["stats"]["earned"] += v


func spend(v: float) -> void:
	state["money"] = max(0.0, state["money"] - v)
	state["stats"]["spent"] += v


func add_rating(stars: float) -> void:
	# moving average over the last ~20 votes, so one bad client hurts but does not ruin
	var n: int = min(int(state["votes"]), 19)
	state["rating"] = clamp((state["rating"] * n + stars) / float(n + 1), 1.0, 5.0)
	state["votes"] = int(state["votes"]) + 1


func money_text(v: float = -1.0) -> String:
	if v < 0.0:
		v = state["money"]
	return "%d" % int(round(v))


# ---------------------------------------------------------------- input map
func _build_input_map() -> void:
	var keys = {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT], "sprint": [KEY_SHIFT], "brake": [KEY_SPACE], "interact": [KEY_E],
		"phone": [KEY_TAB, KEY_Q], "mount": [KEY_F], "pause": [KEY_ESCAPE, KEY_P], "call": [KEY_C], "lock": [KEY_L],
		"bell": [KEY_R], "use_item": [KEY_X], "cam_reset": [KEY_V],
	}
	var pads = {
		"interact": [JOY_BUTTON_A], "mount": [JOY_BUTTON_Y], "phone": [JOY_BUTTON_BACK], "pause": [JOY_BUTTON_START],
		"brake": [JOY_BUTTON_B], "sprint": [JOY_BUTTON_RIGHT_SHOULDER], "bell": [JOY_BUTTON_LEFT_SHOULDER],
		"call": [JOY_BUTTON_X], "lock": [JOY_BUTTON_DPAD_DOWN], "use_item": [JOY_BUTTON_DPAD_UP],
	}
	for a in keys.keys():
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.2)
		for k in keys[a]:
			var e = InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(a, e)
		for b in pads.get(a, []):
			var j = InputEventJoypadButton.new()
			j.button_index = b
			InputMap.action_add_event(a, j)
	var axes = {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0]}
	for a in axes.keys():
		var m = InputEventJoypadMotion.new()
		m.axis = axes[a][0]
		m.axis_value = axes[a][1]
		InputMap.action_add_event(a, m)
	for a in ["look_left", "look_right"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.2)
	var lm = InputEventJoypadMotion.new()
	lm.axis = JOY_AXIS_RIGHT_X
	lm.axis_value = -1.0
	InputMap.action_add_event("look_left", lm)
	var rm = InputEventJoypadMotion.new()
	rm.axis = JOY_AXIS_RIGHT_X
	rm.axis_value = 1.0
	InputMap.action_add_event("look_right", rm)
