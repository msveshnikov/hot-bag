class_name Story
extends Node
## Chapters, the mentor's tutorial, regular customers' quests, daily tasks, objectives text.

const MENTOR = "Михалыч"

var world: Node
var forced_given = false


func setup(w: Node) -> void:
	world = w
	if Game.state.get("daily", []).is_empty() or int(Game.state.get("daily_day", 0)) != int(Game.state["day"]):
		new_daily()


func step() -> int:
	return int(Game.state["tutorial"])


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
	match int(Game.state["chapter"]):
		2:
			if not Game.state["owned"].get("scooter", false):
				return "Глава 2. Накопи на свой самокат: %s / %d монет (мастерская)" % [Game.money_text(), Game.SHOP["scooter"]["price"]]
			return "Глава 2 пройдена! Свободная смена"
	return "Свободная смена: развози заказы, копи на ресторан мечты"


func chapter_title() -> String:
	var names: Array = Game.events_data.get("chapters", ["Первая смена", "Свой самокат", "Деловой центр (скоро)"])
	var c = int(Game.state["chapter"])
	return "Глава %d. %s" % [c, names[clamp(c - 1, 0, names.size() - 1)]]


func start_day() -> void:
	if step() == 0 and int(Game.state["day"]) == 1:
		world.banner("Глава 1. Первая смена", "Ты приехал в большой город с мечтой о своём ресторане. Начнём с доставки!")


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
			var t: String = tips[randi() % tips.size()]
			var opts = [["Спасибо, Михалыч!", func(): pass]]
			if Game.state["quests"].get("cake") == "offered":
				t = "Бабушка Зина опять заказала торт для внука. Кондитерская «Вишенка», не тряси!"
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
	_daily_progress(res)
	_check_quests()


func on_buy(id: String) -> void:
	if id == "scooter" and int(Game.state["chapter"]) == 2:
		Game.state["chapter"] = 3
		world.banner("Глава 2 пройдена!", "Свой самокат! Продолжение следует: Деловой центр, ночные смены и ресторан мечты.")
		Sfx.play("level_up")
	if id == "rack":
		_check_quests()


func _check_quests() -> void:
	var qs: Dictionary = Game.state["quests"]
	var delivered = int(Game.state["stats"]["delivered"])
	if int(Game.state["chapter"]) >= 2 and qs.get("cake") == "locked" and delivered >= 3:
		qs["cake"] = "offered"
		_quest_offer("cake")
	if int(Game.state["chapter"]) >= 2 and qs.get("office_lunch") == "locked" and Game.upgrade_level("rack") > 0:
		qs["office_lunch"] = "offered"
		_quest_offer("office_lunch")


func _quest_offer(q: String) -> void:
	var qd: Dictionary = Game.orders_data["quests"][q]
	var o: Dictionary = world.orders.make_offer(qd["restaurant"], "", qd["giver"])
	if o.is_empty():
		return
	o["quest"] = q
	o["expires"] = 99999.0
	if q == "office_lunch":
		o["item"] = ["lunch", "Обед на 20 персон", "drink", 3.0]
		o["pay"] = float(o["pay"]) * 2.5
		o["needs"] = "rack"
	else:
		o["item"] = ["cake", "Торт на день рождения", "fragile", 1.5]
	world.orders.offers.append(o)
	world.orders.changed.emit()
	world.banner("Новый квест: " + qd["title"], qd["text"])
	Sfx.play("notify")


func resume_quests() -> void:
	# re-offer quests that were offered but not finished when the game was saved
	for q in ["cake", "office_lunch"]:
		if Game.state["quests"].get(q) == "offered":
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
