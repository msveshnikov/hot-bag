extends Node
## Global state: progress, settings, catalogue, save/load, input map. Autoload "Game".

const VERSION = "0.4.0"
const SAVE_PATH = "user://save.json"
const SETTINGS_PATH = "user://settings.json"
const DISTRICTS = {
	"old_town": {"title": "Старый город", "short": "Старый город"},
	"city": {"title": "Деловой центр «Сити»", "short": "«Сити»"},
	"berezki": {"title": "Спальный район «Берёзки»", "short": "«Берёзки»"},
	"gastro": {"title": "Гастроквартал и Большой парк", "short": "Гастроквартал"},
}
## Vehicles (run 3): mode = Player.Mode name; drain = battery % per metre (0 = no battery); ban = surface codes the
## vehicle cannot enter (t stairs, p park/plaza paths, g grass, s sidewalk); r = wheel radius for the spin;
## seat = where the rider's model sits (Godot local), box = parked collision size.
const VEH = {
	"bicycle": {"title": "велосипед", "on": "на велосипед", "mode": "bike", "vmax": 7.6, "accel": 4.2, "drain": 0.0,
		"ban": "", "r": 0.3, "box": [0.5, 1.0, 1.5]},
	"ebike": {"title": "электровелосипед", "on": "на электровелосипед", "mode": "bike", "vmax": 9.3, "accel": 5.4,
		"drain": 0.03, "ban": "", "r": 0.3, "box": [0.5, 1.0, 1.5]},
	"scooter": {"title": "самокат", "on": "на самокат", "mode": "scooter", "vmax": 9.6, "accel": 6.0, "drain": 0.055,
		"ban": "t", "r": 0.11, "box": [0.5, 1.0, 1.2]},
	"moped": {"title": "мопед", "on": "на мопед", "mode": "moped", "vmax": 12.2, "accel": 6.5, "drain": 0.04,
		"ban": "tpg", "r": 0.24, "box": [0.6, 1.1, 1.7]},
	"ecar": {"title": "электромобиль", "on": "в электромобиль", "mode": "car", "vmax": 13.5, "accel": 5.2, "drain": 0.035,
		"ban": "tpgs", "r": 0.3, "box": [1.5, 1.5, 2.7], "seat": [0.32, 0.0, -0.22]},
}
const DREAM_PRICE = 1000
const DREAM_RATING = 4.5

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
var booted = false      # the world was started once in this run (travel / next day reuse the state)
var flags = {}          # parsed debug flags after "--"

var settings = {
	"music": 0.0, "sfx": 0.8, "quality": 1, "mouse_sens": 0.22, "invert_y": false, "touch": "auto",
	"shadows": true, "fullscreen": false,
}

var state = {}

## Catalogue: id -> {name, price, kind, desc}
const SHOP = {
	"scooter": {"name": "Электросамокат", "price": 300, "kind": "vehicle", "desc": "Быстрее велосипеда, но нужна зарядка. Хуже на брусчатке и в дождь."},
	"ebike": {"name": "Электровелосипед", "price": 520, "kind": "vehicle", "desc": "Велосипед с мотором: быстрее, почти не устаёшь, едет по лестницам и паркам. Нужна зарядка."},
	"moped": {"name": "Электромопед", "price": 900, "kind": "vehicle", "desc": "Быстрый и устойчивый на брусчатке. В парк, на лестницы и тротуары нельзя."},
	"ecar": {"name": "Электромобиль", "price": 2200, "kind": "vehicle", "desc": "Самый быстрый по дорогам, не мокнешь в дождь и снег, еда не трясётся. Только по проезжей части, парковаться у тротуара."},
	"battery": {"name": "Батарея+", "price": 120, "kind": "upgrade", "max": 2, "desc": "Запас хода электротранспорта +40% за уровень."},
	"motor": {"name": "Мотор+", "price": 150, "kind": "upgrade", "max": 2, "desc": "Скорость электротранспорта +12% за уровень."},
	"tires": {"name": "Широкие шины", "price": 90, "kind": "upgrade", "max": 1, "desc": "Сцепление на брусчатке и в дождь. Меньше проколов."},
	"brakes": {"name": "Тормоза", "price": 60, "kind": "upgrade", "max": 1, "desc": "Резкое торможение не портит еду."},
	"rack": {"name": "Багажник", "price": 110, "kind": "upgrade", "max": 1, "desc": "Два заказа сразу и большие заказы для офисов."},
	"lock": {"name": "Замок", "price": 40, "kind": "upgrade", "max": 1, "desc": "Транспорт не угонят, если пристегнуть (L)."},
	"headlight": {"name": "Фара", "price": 50, "kind": "upgrade", "max": 1, "desc": "Ночью виднее и нет штрафа за езду без света."},
	"mudguards": {"name": "Крылья", "price": 35, "kind": "upgrade", "max": 1, "desc": "Лужи не забрызгивают — рейтинг не падает в дождь."},
	"warm_gloves": {"name": "Тёплые перчатки и шапка", "price": 50, "kind": "gear", "desc": "В снег курьер не мёрзнет и не теряет силы."},
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
## Thermal bag colours (ТЗ §4: the bag can be decorated); gold is the «Курьер-легенда» reward.
const BAGS = ["#22b8b0", "#ef6a5b", "#8a6fd1", "#e0b040"]
const BAG_GOLD = "#e0b040"

## Courier ranks (ТЗ §9: levels open transport and order types; the top one is «Курьер-легенда»).
## XP: 10 per delivery, +5 on time, +5 for five stars, +40 per quest.
const RANKS = [
	{"xp": 0, "title": "Новичок", "perk": ""},
	{"xp": 80, "title": "Курьер", "perk": "Открыт электровелосипед. Чаевые +4%."},
	{"xp": 220, "title": "Опытный курьер", "perk": "Открыт мопед. Конкуренты реже перехватывают заказы."},
	{"xp": 450, "title": "Профи", "perk": "Открыт электромобиль. Чаевые +12%."},
	{"xp": 800, "title": "Мастер доставки", "perk": "В приложении появляются VIP-заказы с двойной оплатой."},
	{"xp": 1300, "title": "Курьер-легенда", "perk": "Золотая термосумка. Чаевые +20%. Тебя знает весь город!"},
]
const VEH_RANK = {"ebike": 1, "moped": 2, "ecar": 3}
const VIP_RANK = 4

## Quest keepsakes for the dream restaurant (ТЗ §12: rewards include items for your future restaurant).
## Each one hangs in the restaurant and adds to its daily income.
const KEEPSAKES = {
	"cake": ["Бабушкин рецепт", "Тетрадка бабушки Зины с рецептом вишнёвого пирога."],
	"office_lunch": ["Кофемашина «Кубика»", "Офис обновил технику и подарил тебе старую кофемашину."],
	"guard_coffee": ["Пропуск Виктора в рамке", "Первый пропуск в «Сити» — повесишь у кассы."],
	"board_lunch": ["Серебряный поднос", "Совет директоров был в восторге от лапши."],
	"night_gamers": ["Неоновая вывеска «Открыто»", "Геймеры спаяли её из старой клавиатуры."],
	"hidden_corpus": ["Табличка «7 к.4»", "Тот самый корпус, который не знал даже GPS."],
	"no_lift": ["Гантели дедушки Семёна", "«Тебе нужнее, ты по лестницам бегаешь»."],
	"market_fish": ["Медный котёл шефа Льва", "«Уху в нём вари — и о старике вспоминай»."],
	"park_picnic": ["Клетчатые скатерти", "Для летней веранды твоего ресторана."],
	"skater_cocoa": ["Коньки фигуристов", "Повесишь на стену — на счастье."],
}
const HAIRS = ["short", "ponytail", "curly", "bun"]

var layout: Dictionary
var level_loaded = ""
var population: Dictionary
var orders_data: Dictionary
var events_data: Dictionary


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	args = OS.get_cmdline_user_args()
	_parse_flags()
	_build_input_map()
	load_settings()
	if not bool(settings.get("quality_set", false)):
		settings["quality"] = _auto_quality()
	if flag("quality"):
		settings["quality"] = int(flags["quality"][0])
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


func _auto_quality() -> int:
	if OS.has_feature("web") or OS.has_feature("mobile"):
		return 0
	var gpu = RenderingServer.get_video_adapter_name().to_lower()
	if "intel" in gpu or "uhd" in gpu or "llvmpipe" in gpu:
		return 0
	return 1


func flag(name: String) -> bool:
	return flags.has(name)


func load_json(path: String) -> Variant:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("cannot open " + path)
		return {}
	return JSON.parse_string(f.get_as_text())


func district() -> String:
	var d: String = state.get("district", "old_town")
	return d if DISTRICTS.has(d) else "old_town"


func district_title(d = "") -> String:
	return DISTRICTS.get(d if d != "" else district(), DISTRICTS["old_town"])["title"]


func load_level_data() -> void:
	var lv = district()
	if lv != level_loaded:
		layout = load_json("res://assets/levels/%s_layout.json" % lv)
		population = load_json("res://assets/levels/%s_population.json" % lv)
		orders_data = load_json("res://assets/levels/%s_orders.json" % lv)
		events_data = load_json("res://assets/levels/%s_events.json" % lv)
		level_loaded = lv


func unlocked(d: String) -> bool:
	return d == "old_town" or bool(state.get("unlocked", {}).get(d, false))


func quest_state(q: String) -> String:
	return String(state["quests"].get(q, "locked"))


## Ride to another district: keeps the clock, the vehicle and the battery; the world reloads there.
func travel(to: String, hour: float) -> void:
	state["arrive_from"] = district()
	state["district"] = to
	state["hour_resume"] = hour
	save_game()
	go_play = true
	get_tree().change_scene_to_file("res://scenes/main.tscn")


# ---------------------------------------------------------------- state
func new_state() -> void:
	state = {
		"version": VERSION, "money": 25.0, "rating": 4.0, "votes": 5, "day": 1, "chapter": 1, "tutorial": 0,
		"owned": {"bicycle": true, "scooter": false, "ebike": false, "moped": false, "ecar": false}, "vehicle": "bicycle",
		"rented_today": false, "charge": {}, "snow_days": 0,
		"upgrades": {}, "gear": {}, "helmet": "", "items": {"snack": 1, "repair_kit": 0, "powerbank": 0, "energy_drink": 0},
		"look": {"gender": "m", "hair": "short", "jacket": "#22b8b0", "cap": true},
		"quests": {"cake": "locked", "office_lunch": "locked"},
		"district": "old_town", "unlocked": {"city": false, "berezki": false, "gastro": false}, "pass": false, "dream": "locked",
		"progress": {"city": 0, "night": 0, "berezki": 0}, "ending_seen": false,
		"stats": {"delivered": 0, "late": 0, "tips": 0.0, "fines": 0.0, "earned": 0.0, "spent": 0.0, "falls": 0},
		"daily": [], "seen_hints": {}, "best_streak": 0,
		"xp": 0, "keepsakes": [], "weekly": [], "week": -1,
	}


func veh(kind: String) -> Dictionary:
	return VEH.get(kind, VEH["bicycle"])


func is_electric(kind: String) -> bool:
	return float(veh(kind)["drain"]) > 0.0


func owns_electric() -> bool:
	for k in VEH.keys():
		if is_electric(k) and state["owned"].get(k, false):
			return true
	return false


## Can ride this vehicle today (owned, or the scooter rented for the day).
func can_use(kind: String) -> bool:
	return state["owned"].get(kind, false) or (kind == "scooter" and state.get("rented_today", false))


func charge_of(kind: String) -> float:
	return float(state.get("charge", {}).get(kind, 100.0))


func set_charge(kind: String, v: float) -> void:
	if not state.has("charge"):
		state["charge"] = {}
	state["charge"][kind] = clamp(v, 0.0, 100.0)


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
	if not d.has("xp"):
		# saves from before ranks: give credit for what was already done
		var qd = 0
		for q in state["quests"].values():
			if q == "done":
				qd += 1
		state["xp"] = int(state["stats"]["delivered"]) * 14 + qd * 40
		for q in state["quests"].keys():
			if state["quests"][q] == "done" and KEEPSAKES.has(q) and not (q in state["keepsakes"]):
				state["keepsakes"].append(q)
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
	# music is off by default (user request 2026-11-16); mute it once for older saved settings too
	if not bool(settings.get("music_default_off", false)):
		settings["music"] = 0.0
		settings["music_default_off"] = true


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
			return not state["owned"].get(id, false) and rank() >= int(VEH_RANK.get(id, 0))
		"upgrade":
			if id in ["battery", "motor"] and not owns_electric():
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


# ---------------------------------------------------------------- ranks
func rank() -> int:
	var r = 0
	for i in RANKS.size():
		if int(state.get("xp", 0)) >= int(RANKS[i]["xp"]):
			r = i
	return r


func rank_title(r = -1) -> String:
	return RANKS[rank() if r < 0 else r]["title"]


## 0..1 progress to the next rank (1 at the top).
func rank_progress() -> float:
	var r = rank()
	if r >= RANKS.size() - 1:
		return 1.0
	var a = float(RANKS[r]["xp"])
	var b = float(RANKS[r + 1]["xp"])
	return clamp((float(state.get("xp", 0)) - a) / (b - a), 0.0, 1.0)


## Returns the new rank index if this XP crossed a rank line, else -1.
func add_xp(v: int) -> int:
	var before = rank()
	state["xp"] = int(state.get("xp", 0)) + v
	var after = rank()
	return after if after > before else -1


func tip_rank_mult() -> float:
	return [1.0, 1.04, 1.06, 1.12, 1.15, 1.2][rank()]


## Why a shop item can't be bought right now ("" if it can, or only money is missing).
func buy_block_reason(id: String) -> String:
	var it: Dictionary = SHOP[id]
	if it["kind"] == "vehicle" and rank() < int(VEH_RANK.get(id, 0)):
		return "Нужно звание «%s»." % rank_title(int(VEH_RANK[id]))
	if it["kind"] == "upgrade" and id in ["battery", "motor"] and not owns_electric():
		return "Нужен электротранспорт."
	return ""


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
