class_name Story
extends Node
## Chapters 1-5, the mentor's tutorial, regular customers' quests in three districts, daily tasks, objectives text.
## Ch1 «Первая смена» and ch2 «Свой самокат» — Old Town; ch3 «Деловой центр» — «Сити» across the bridge;
## ch4 «Ночные смены» — «Берёзки»; ch5 «Ресторан мечты» — buy the empty shop on the square, feed the critic.

const MENTOR = "Михалыч"
const CITY_GOAL = 5
const NIGHT_GOAL = 4
const NIGHT_FROM = 20.0

## quest -> district where it is offered
const QUEST_HOME = {"cake": "old_town", "office_lunch": "old_town", "critic": "old_town",
	"guard_coffee": "city", "board_lunch": "city",
	"night_gamers": "berezki", "hidden_corpus": "berezki", "no_lift": "berezki"}

var world: Node
var forced_given = false


func setup(w: Node) -> void:
	world = w
	if Game.state.get("daily", []).is_empty() or int(Game.state.get("daily_day", 0)) != int(Game.state["day"]):
		new_daily()
	# saves from v0.1 that already finished chapter 2: open the bridge
	if chapter() >= 3 and not Game.unlocked("city"):
		Game.state["unlocked"]["city"] = true
	if chapter() >= 4 and not Game.unlocked("berezki"):
		Game.state["unlocked"]["berezki"] = true


func step() -> int:
	return int(Game.state["tutorial"])


func chapter() -> int:
	return int(Game.state["chapter"])


func here() -> String:
	return Game.district()


func progress(k: String) -> int:
	return int(Game.state.get("progress", {}).get(k, 0))


func _add_progress(k: String) -> int:
	if not Game.state.has("progress"):
		Game.state["progress"] = {}
	Game.state["progress"][k] = progress(k) + 1
	return progress(k)


func offers_allowed() -> bool:
	return step() >= 5


func events_allowed() -> bool:
	return step() >= 5


func objective() -> String:
	match step():
		0:
			return "Поговори с наставником %s (подойди и нажми E)" % MENTOR
		1:
			return "Открой приложение «Хоп!» (Tab) и прими первый заказ"
		2:
			return "Езжай в ресторан по зелёной линии GPS и забери заказ (E у окна выдачи)"
		3:
			return "Довези заказ: номер дома и подъезд — на табличке у двери"
		4:
			return "Вернись к %s у кафе курьеров" % MENTOR
	match chapter():
		2:
			if not Game.state["owned"].get("scooter", false):
				return "Глава 2. Накопи на свой самокат: %s / %d монет (мастерская)" % [Game.money_text(), Game.SHOP["scooter"]["price"]]
			return "Глава 2 пройдена! Свободная смена"
		3:
			if here() != "city":
				return "Глава 3. Мост открыли! Езжай в «Сити» — мост на набережной (GPS)"
			var t = "Глава 3. Доставь заказы в «Сити»: %d / %d" % [progress("city"), CITY_GOAL]
			if not Game.state.get("pass", false):
				t += ". Без пропуска охрана в башнях задерживает"
			return t
		4:
			if here() != "berezki":
				return "Глава 4. Езжай в «Берёзки» — восточный конец проспекта (GPS)"
			return "Глава 4. Ночные заказы в «Берёзках» (после 20:00): %d / %d" % [progress("night"), NIGHT_GOAL]
		5:
			if Game.state.get("dream", "locked") != "open":
				return "Глава 5. Ресторан мечты: накопи %s / %d монет и рейтинг %.1f / %.1f — помещение на Часовой площади" % [
					Game.money_text(), Game.DREAM_PRICE, float(Game.state["rating"]), Game.DREAM_RATING]
			if Game.quest_state("critic") != "done":
				if here() != "old_town":
					return "Глава 5. Критик ждёт ужин из твоего ресторана — возвращайся в Старый город"
				return "Глава 5. Ужин для критика: забери заказ в своём ресторане и довези идеально"
	return "Свободная игра: твой ресторан работает, город твой!"


func chapter_title() -> String:
	var names: Array = Game.events_data.get("chapters", ["Первая смена", "Свой самокат", "Деловой центр", "Ночные смены", "Ресторан мечты"])
	var c = chapter()
	return "Глава %d. %s" % [c, names[clamp(c - 1, 0, names.size() - 1)]]


## Where the GPS points when there is no order: the way to the next chapter's district.
func guide_target() -> Dictionary:
	if step() < 5:
		return {}
	var want = ""
	if chapter() == 3 and here() != "city":
		want = "city"
	elif chapter() == 4 and here() != "berezki":
		want = "berezki"
	elif chapter() == 5 and here() != "old_town" and (Game.state.get("dream", "locked") != "open" or Game.quest_state("critic") != "done"):
		want = "old_town"
	elif chapter() == 5 and here() == "old_town" and Game.state.get("dream", "locked") != "open" and _dream_affordable():
		var dr: Dictionary = Game.orders_data["restaurants"].get("dream", {})
		if not dr.is_empty():
			return {"pos": Vector3(dr["pickup"][0], 0, dr["pickup"][2]), "label": "Помещение «Сдаётся»", "kind": "dream"}
	if want == "":
		return {}
	for e in Game.layout.get("district", {}).get("exits", []):
		if e["to"] == want:
			var a: Array = e["rect"][0]
			var b: Array = e["rect"][1]
			return {"pos": Vector3((a[0] + b[0]) * 0.5, 0, (a[2] + b[2]) * 0.5), "label": e["label"], "kind": "exit"}
	# no direct road (e.g. «Сити» -> «Берёзки» is open, the Old Town has both) — any open exit
	return {}


func start_day() -> void:
	if step() == 0 and int(Game.state["day"]) == 1:
		world.banner("Глава 1. Первая смена", "Ты приехал в большой город с мечтой о своём ресторане. Начнём с доставки!")
	elif chapter() == 3 and here() == "old_town" and not Game.state.get("ch3_called", false):
		_start_chapter3()
	elif chapter() == 3 and here() == "city" and progress("city") == 0:
		world.banner("Деловой центр «Сити»", "Стеклянные башни, обеденный пик и щедрые чаевые. Но на входе — охрана, а у дверей — красная разметка: эвакуатор!")
	elif chapter() == 4 and here() == "berezki" and progress("night") == 0:
		world.banner("Спальный район «Берёзки»", "Одинаковые панельки, «корпус 3 строение 2» и лифты, которые ломаются. Ночью заказы дороже!")
	_check_quests()


# ---------------------------------------------------------------- mentor
func talk_mentor() -> void:
	match step():
		0:
			world.dialog(MENTOR, "О, новенький! Я Михалыч, тридцать лет в доставке. Видишь велик? Это твой боевой конь. Скрипит, зато не разряжается!", [
				["Здравствуйте! Научите?", func(): _mentor_1()],
				["А можно сразу самокат?", func(): world.dialog(MENTOR, "Ха! Самокат надо заработать. Или арендовать в мастерской. Но сначала — первый заказ!", [["Ладно, давай заказ", func(): _mentor_1()]])],
			])
		4:
			world.dialog(MENTOR, "Ну как, жив? Клиент поставил оценку — это твой рейтинг. Выше рейтинг — дороже заказы. Ниже 3 — предупреждение, ниже 2,5 — бан на день.", [
				["А что дальше?", func(): _mentor_5()],
			])
		_:
			var tips = [
				"Брусчатка трясёт торты. Если везёшь торт — по асфальту или медленно.",
				"Через парк и по лестницам на велике короче. Самокат по лестнице не поедет!",
				"Замок купи. В этом районе велики уводят — моргнуть не успеешь.",
				"Звонить клиенту (C) можно, но некоторые просили не звонить. Читай заметки в заказе!",
				"На станциях у кафе зарядка самоката бесплатная. Телефон заряжай в кафе.",
				"Полиция штрафует за езду по тротуару и на красный. Рядом с постом — по правилам!",
				"Дождь — надбавка к оплате, но еда мокнет. Непромокаемая сумка окупается за два дня.",
				"Бабушка Зина печёт лучшие пирожки... а заказывает торты. Будь с ней ласковым.",
			]
			if chapter() >= 3:
				tips += ["В «Сити» не бросай самокат на красной разметке у башен — эвакуатор быстрее тебя.",
					"Охранник Виктор любит буррито. Подружишься — пропустит без звонков.",
					"В «Берёзках» номера домов придумывал шутник. Смотри на большие цифры на стенах.",
					"Ночью в «Берёзках» лифты ломаются чаще. Энергетик в сумке — твой лучший друг."]
			if chapter() >= 5:
				tips += ["Своё дело — это тоже доставка, только наоборот. Горжусь тобой, %s!" % ("сынок" if Game.state["look"].get("gender", "m") == "m" else "дочка")]
			var t: String = tips[randi() % tips.size()]
			var opts = [["Спасибо, Михалыч!", func(): pass]]
			if Game.quest_state("cake") == "offered":
				t = "Бабушка Зина опять заказала торт для внука. Кондитерская «Вишенка», не тряси!"
			if chapter() == 5 and Game.state.get("dream", "locked") != "open":
				t = "Видишь пустое помещение рядом с кондитерской? «Сдаётся». Собери %d монет и держи рейтинг от %.1f — и это будет твой ресторан." % [Game.DREAM_PRICE, Game.DREAM_RATING]
			world.dialog(MENTOR, t, opts)


func _mentor_1() -> void:
	Game.state["tutorial"] = 1
	world.dialog(MENTOR, "Заказы приходят в приложение «Хоп!» на телефоне (Tab). Выбирай: ближний и дешёвый или дальний и выгодный. Вот, лови первый — пицца, тут рядом.", [
		["Открыть приложение", func(): world.open_phone()],
	])
	_give_forced()


func _give_forced() -> void:
	if forced_given:
		return
	forced_given = true
	var o: Dictionary = world.orders.make_offer("pizza", _near_door("pizza"))
	if o.is_empty():
		o = world.orders.make_offer("pizza")
	o["expires"] = 99999.0
	o["limit"] = float(o["limit"]) + 60.0
	o["customer"]["trait"] = "polite"
	o["customer"]["lines"] = ["Ура, пицца! Спасибо, курьер!", "Как быстро! Держи на чай."]
	o["customer"]["tip"] = 1.0
	o["tutorial"] = true
	world.orders.offers.append(o)
	world.orders.changed.emit()
	Sfx.play("notify")


func _near_door(rest: String) -> String:
	var r: Dictionary = Game.orders_data["restaurants"][rest]
	var pk = Vector3(r["pickup"][0], 0, r["pickup"][2])
	var best = ""
	var bd = 1e9
	for d in Game.orders_data["doors"]:
		var dist = pk.distance_to(Vector3(d["pos"][0], 0, d["pos"][2]))
		if dist > 40.0 and dist < bd:
			bd = dist
			best = d["id"]
	return best


func _mentor_5() -> void:
	Game.state["tutorial"] = 5
	Game.state["chapter"] = 2
	Game.save_game()
	world.dialog(MENTOR, "Дальше — сам. Цель простая: накопи 300 монет на свой самокат. Он быстрее, но его надо заряжать — станции вон там. А пока можно арендовать в мастерской за %d в день. Удачи, и не давай «Молнии» хватать твои заказы!" % Game.SCOOTER_RENT, [
		["Погнали!", func(): world.banner("Глава 2. Свой самокат", "Копи монеты, береги рейтинг, обходи неприятности.")],
	])
	Sfx.play("level_up")


## The mentor rings the courier's phone (chapters 3-5 happen away from his cafe).
func mentor_call(text: String, title: String, sub: String) -> void:
	Sfx.play("ring")
	world.dialog(MENTOR + " (звонок)", text, [["Понял, Михалыч!", func(): world.banner(title, sub)]])


# ---------------------------------------------------------------- chapters 3-5
func _start_chapter3() -> void:
	Game.state["chapter"] = 3
	Game.state["unlocked"]["city"] = true
	Game.state["ch3_called"] = true
	Game.save_game()
	Sfx.play("level_up")
	mentor_call("Алло! Слыхал? Мост через реку починили! За ним «Сити» — стекло, бетон и офисы. Там обед в полдень, чаевые щедрые, но на входе охрана. Сгоняй, покажи себя: пять доставок — и ты там свой.",
		"Глава 3. Деловой центр", "Мост на набережной открыт. Доставь %d заказов в «Сити»." % CITY_GOAL)


func _start_chapter4() -> void:
	Game.state["chapter"] = 4
	Game.state["unlocked"]["berezki"] = true
	Game.save_game()
	Sfx.play("level_up")
	mentor_call("Ну ты даёшь, «Сити» покорил! Теперь ночные смены. Дорогу на «Берёзки» открыли — это за восточным концом проспекта. Ночью заказы дороже, но дворы тёмные, лифты ломаются, а номера домов... сам увидишь. Четыре ночные доставки — и поговорим о твоей мечте.",
		"Глава 4. Ночные смены", "Дорога в «Берёзки» открыта. Ночью (после 20:00) — %d доставок." % NIGHT_GOAL)


func _start_chapter5() -> void:
	Game.state["chapter"] = 5
	Game.save_game()
	Sfx.play("level_up")
	mentor_call("Слушай внимательно. На Часовой площади, рядом с «Вишенкой», сдаётся помещение. Я договорился с хозяином: %d монет — и оно твоё. Только рейтинг держи от %.1f, он справки наводит. Пора открывать свой ресторан!" % [Game.DREAM_PRICE, Game.DREAM_RATING],
		"Глава 5. Ресторан мечты", "Накопи %d монет и рейтинг %.1f. Помещение — на Часовой площади." % [Game.DREAM_PRICE, Game.DREAM_RATING])


func _dream_affordable() -> bool:
	return float(Game.state["money"]) >= Game.DREAM_PRICE and float(Game.state["rating"]) >= Game.DREAM_RATING


func dream_label() -> String:
	var st: String = Game.state.get("dream", "locked")
	if st == "open":
		return ""
	if chapter() < 5:
		return "Помещение «Сдаётся»... Тут бы ресторан открыть"
	return "Купить помещение под ресторан: %d мон. (рейтинг от %.1f)" % [Game.DREAM_PRICE, Game.DREAM_RATING]


func dream_action() -> void:
	if chapter() < 5:
		world.toast("Дверь заколочена. Табличка: «Сдаётся». Когда-нибудь...", 2.5)
		return
	if not _dream_affordable():
		world.toast("Нужно %d монет (у тебя %s) и рейтинг от %.1f (у тебя %.2f)." % [Game.DREAM_PRICE, Game.money_text(), Game.DREAM_RATING, float(Game.state["rating"])], 3.0)
		Sfx.play("fail")
		return
	world.dialog("Хозяин помещения", "— Михалыч за тебя поручился. %d монет — и ключи твои. По рукам?" % Game.DREAM_PRICE, [
		["По рукам!", func(): buy_dream()],
		["Ещё подумаю", func(): pass],
	])


func buy_dream() -> void:
	Game.spend(float(Game.DREAM_PRICE))
	Game.state["dream"] = "open"
	Game.save_game()
	world.apply_dream()
	Sfx.play("level_up")
	world.banner("Ресторан «Горячая сумка» открыт!", "Вывеска горит, повар на месте. Первый заказ — от самого строгого критика города...")
	world.get_tree().create_timer(4.0).timeout.connect(func(): _check_quests())


func restaurant_income() -> int:
	var inc = int(40 + max(0.0, float(Game.state["rating"]) - 4.0) * 60.0)
	Game.earn(float(inc))
	return inc


func on_hour(_h: int) -> void:
	_check_quests()


# ---------------------------------------------------------------- order hooks
func on_accept(_o: Dictionary) -> void:
	if step() == 1:
		Game.state["tutorial"] = 2


func on_pickup(_o: Dictionary) -> void:
	if step() == 2:
		Game.state["tutorial"] = 3


func on_deliver(o: Dictionary, res: Dictionary) -> void:
	if step() == 3:
		Game.state["tutorial"] = 4
	var q: String = o.get("quest", "")
	if q != "":
		Game.state["quests"][q] = "done"
		var qd: Dictionary = Game.orders_data["quests"][q]
		Game.earn(float(qd["reward"]))
		world.banner("Квест выполнен: " + qd["title"], "Награда +%d монет. Клиент тебя запомнил!" % int(qd["reward"]))
		Sfx.play("level_up")
		if q == "guard_coffee":
			Game.state["pass"] = true
			world.get_tree().create_timer(3.0).timeout.connect(func(): world.banner("Пропуск получен!", "Виктор выписал тебе пропуск во все башни «Сити». Больше никаких проверок на входе."))
		if q == "critic":
			Game.state["ending_seen"] = true
			Game.save_game()
			world.get_tree().create_timer(1.5).timeout.connect(func(): world.screens.open_ending())
	# chapter progress
	if here() == "berezki":
		_add_progress("berezki")
	if chapter() == 3 and here() == "city":
		if _add_progress("city") >= CITY_GOAL:
			world.get_tree().create_timer(2.5).timeout.connect(func(): _start_chapter4())
		else:
			world.toast("Глава 3: доставок в «Сити» %d / %d" % [progress("city"), CITY_GOAL], 2.5)
	if chapter() == 4 and here() == "berezki" and world.daynight.hour >= NIGHT_FROM:
		if _add_progress("night") >= NIGHT_GOAL:
			world.get_tree().create_timer(2.5).timeout.connect(func(): _start_chapter5())
		else:
			world.toast("Глава 4: ночных доставок %d / %d" % [progress("night"), NIGHT_GOAL], 2.5)
	_daily_progress(res)
	_check_quests()


func on_buy(id: String) -> void:
	if id == "scooter" and chapter() == 2:
		Game.state["chapter"] = 3
		world.banner("Глава 2 пройдена!", "Свой самокат! Михалыч сейчас позвонит...")
		Sfx.play("level_up")
		world.get_tree().create_timer(3.5).timeout.connect(func(): _start_chapter3())
	if id == "rack":
		_check_quests()


## Offer at most one quest at a time in the current district when its conditions are met.
func _check_quests() -> void:
	var qs: Dictionary = Game.state["quests"]
	var data: Dictionary = Game.orders_data.get("quests", {})
	# the chapter 5 story quest never waits behind a side quest
	if data.has("critic") and here() == "old_town" and chapter() >= 5 and Game.state.get("dream", "locked") == "open" and Game.quest_state("critic") == "locked":
		qs["critic"] = "offered"
		_quest_offer("critic")
		return
	for q in data.keys():
		if Game.quest_state(q) == "offered":
			return
	var ch = chapter()
	var d = here()
	var rack = Game.upgrade_level("rack") > 0
	var hour: float = world.daynight.hour
	var avail = {
		"cake": d == "old_town" and ch >= 2 and int(Game.state["stats"]["delivered"]) >= 3,
		"office_lunch": d == "old_town" and ch >= 2 and rack,
		"critic": d == "old_town" and ch >= 5 and Game.state.get("dream", "locked") == "open",
		"guard_coffee": d == "city" and ch >= 3 and not Game.state.get("pass", false),
		"board_lunch": d == "city" and ch >= 3 and rack and progress("city") >= 2,
		"no_lift": d == "berezki" and ch >= 4,
		"hidden_corpus": d == "berezki" and ch >= 4 and progress("berezki") >= 1,
		"night_gamers": d == "berezki" and ch >= 4 and hour >= 21.0,
	}
	for q in ["critic", "guard_coffee", "cake", "no_lift", "night_gamers", "hidden_corpus", "office_lunch", "board_lunch"]:
		if data.has(q) and bool(avail.get(q, false)) and Game.quest_state(q) == "locked":
			qs[q] = "offered"
			_quest_offer(q)
			return


func _quest_offer(q: String) -> void:
	var qd: Dictionary = Game.orders_data["quests"][q]
	var o: Dictionary = world.orders.make_offer(qd["restaurant"], "", qd["giver"])
	if o.is_empty():
		return
	o["quest"] = q
	o["expires"] = 99999.0
	var r: Dictionary = Game.orders_data["restaurants"][qd["restaurant"]]
	for it in r["items"]:
		if it[0] == qd["item"]:
			o["item"] = it
	match q:
		"office_lunch", "board_lunch":
			o["item"] = ["lunch", "Обед на 20 персон", "drink", 3.0]
			o["pay"] = float(o["pay"]) * 2.5
			o["needs"] = "rack"
		"cake":
			o["item"] = ["cake", "Торт на день рождения", "fragile", 1.5]
		"no_lift":
			o["flags"]["broken_lift"] = true
			o["floor"] = int(o["door"]["floors"])
			o["limit"] = float(o["limit"]) + 40.0
		"night_gamers":
			o["limit"] = float(o["limit"]) * 0.75
		"hidden_corpus":
			o["flags"]["no_gps"] = true
			o["limit"] = float(o["limit"]) + 90.0
		"guard_coffee":
			o["floor"] = 1
		"critic":
			o["pay"] = float(o["pay"]) * 3.0
			o["limit"] = float(o["limit"]) + 30.0
			o["item"] = ["dream", "Ужин для критика", "hot", 2.0]
	world.orders.offers.append(o)
	world.orders.changed.emit()
	world.banner("Новый квест: " + qd["title"], qd["text"])
	Sfx.play("notify")


func resume_quests() -> void:
	# re-offer quests of this district that were offered but not finished when the game was saved
	var data: Dictionary = Game.orders_data.get("quests", {})
	for q in data.keys():
		if Game.quest_state(q) == "offered":
			_quest_offer(q)


# ---------------------------------------------------------------- daily tasks
func new_daily() -> void:
	Game.state["daily"] = [
		{"id": "deliver", "text": "Доставь 4 заказа", "goal": 4, "have": 0, "reward": 15, "done": false},
		{"id": "five", "text": "Получи 3 оценки «5 звёзд»", "goal": 3, "have": 0, "reward": 15, "done": false},
		{"id": "tips", "text": "Собери 10 монет чаевых", "goal": 10, "have": 0, "reward": 12, "done": false},
	]
	Game.state["daily_day"] = int(Game.state["day"])


func _daily_progress(res: Dictionary) -> void:
	for t in Game.state["daily"]:
		if t["done"]:
			continue
		match t["id"]:
			"deliver":
				t["have"] = int(t["have"]) + 1
			"five":
				if int(res["stars"]) >= 5:
					t["have"] = int(t["have"]) + 1
			"tips":
				t["have"] = int(t["have"]) + int(res["tip"])
		if int(t["have"]) >= int(t["goal"]):
			t["done"] = true
			Game.earn(float(t["reward"]))
			world.toast("Задание дня выполнено: %s (+%d)" % [t["text"], int(t["reward"])], 3.0)
			Sfx.play("level_up", 0.6)
