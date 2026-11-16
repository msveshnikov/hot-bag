class_name Orders
extends Node
## The core loop: offers in the «Хоп!» app -> restaurant -> food in the bag -> customer -> pay, tips, rating.

signal changed

var world: Node
var data: Dictionary
var rules: Dictionary
var offers: Array = []
var active: Array = []
var next_offer = 3.0
var next_id = 1
var streak = 0
var day_log: Array = []
var rs = RandomNumberGenerator.new()
var forced_offer = false


func setup(w: Node) -> void:
	world = w
	data = Game.orders_data
	rules = data["rules"]
	rs.seed = 1234 + int(Game.state["day"])


func capacity() -> int:
	return 2 if Game.upgrade_level("rack") > 0 and world.player.mode == Player.Mode.SCOOTER else (2 if Game.upgrade_level("rack") > 0 else 1)


func door_by_id(id: String) -> Dictionary:
	for d in data["doors"]:
		if d["id"] == id:
			return d
	return {}


func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


# ---------------------------------------------------------------- offers
func _process(delta: float) -> void:
	if not world.started or get_tree().paused:
		return
	if world.player.phone <= 0.0:
		return
	next_offer -= delta
	var maxo = int(rules["max_offers"])
	if next_offer <= 0.0 and offers.size() < maxo and world.daynight.running and world.story.offers_allowed():
		var iv: Array = rules["offer_interval_s"]
		next_offer = rs.randf_range(iv[0], iv[1]) * (0.8 if world.daynight.is_dark() else 1.0)
		var o = make_offer()
		if not o.is_empty():
			offers.append(o)
			Sfx.play("notify", 0.6)
			changed.emit()
	for o in offers.duplicate():
		o["expires"] -= delta
		if o["expires"] <= 0.0:
			offers.erase(o)
			if world.events.rivals_active():
				world.toast("Заказ «%s» перехватил курьер «Молнии»!" % o["item"][1], 2.5)
			changed.emit()
	for o in active:
		o["elapsed"] += delta
		_food_drift(o, delta)
		if o["state"] == "waiting" or o["state"] == "to_restaurant":
			o["cook_left"] = max(0.0, o["cook_left"] - delta)


func make_offer(rest = "", door_id = "", regular = "") -> Dictionary:
	var rkeys: Array = data["restaurants"].keys().filter(func(k): return not data["restaurants"][k].get("owned_only", false) or Game.state.get("dream", "locked") == "open")
	if rest == "":
		rest = rkeys[rs.randi() % rkeys.size()]
	var r: Dictionary = data["restaurants"][rest]
	var items: Array = r["items"]
	var item: Array = items[rs.randi() % items.size()]
	var cust = {}
	var door = {}
	if regular == "" and rs.randf() < 0.25 and int(Game.state["chapter"]) >= 2:
		var regs: Array = data["regulars"]
		var rg: Dictionary = regs[rs.randi() % regs.size()]
		if not rg.has("quest"):
			regular = rg["id"]
	if regular != "":
		for rg in data["regulars"]:
			if rg["id"] == regular:
				cust = rg.duplicate()
		door = door_by_id(cust["address"])
	elif door_id != "":
		door = door_by_id(door_id)
	else:
		var pk = _v(r["pickup"])
		for _i in 20:
			var d: Dictionary = data["doors"][rs.randi() % data["doors"].size()]
			var dist = pk.distance_to(_v(d["pos"]))
			if dist > 35.0 and dist < 190.0:
				door = d
				break
	if door.is_empty():
		return {}
	if cust.is_empty():
		var traits = ["polite", "polite", "polite", "capricious", "no_call", "leave_at_door"]
		var models = ["office", "student", "mom", "grandma", "tourist", "oldman"]
		var names = ["Анна", "Игорь", "Света", "Пётр", "Лиза", "Марк", "Оля", "Денис", "Вера", "Тимур", "Ника", "Гоша"]
		var t: String = traits[rs.randi() % traits.size()]
		cust = {"id": "", "name": names[rs.randi() % names.size()], "model": models[rs.randi() % models.size()],
			"trait": t, "tip": rs.randf_range(0.2, 0.7), "lines": data["random_lines"][t]}
	var path: PackedVector3Array = world.nav.path(_v(r["pickup"]), _v(door["pos"]), "bicycle")
	var dist = Nav.length(path)
	var floor_n = int(cust.get("floor", rs.randi_range(1, int(door["floors"]))))
	var pay = float(rules["base_pay"]) + float(rules["pay_per_100m"]) * dist / 100.0
	pay *= float(r.get("price", 1.0)) * float(item[3]) * (0.8 + 0.2 * floor_n / 3.0)
	if world.daynight.is_night():
		pay *= 1.0 + float(rules["night_bonus"])
	if world.daynight.rain > 0.4:
		pay *= 1.0 + float(rules["rain_bonus"])
	for rh in rules["rush_hours"]:
		if world.daynight.hour >= rh[0] and world.daynight.hour < rh[1]:
			pay *= 1.0 + float(rules["rush_bonus"])
	var cook: Array = r["cook"]
	var limit = float(rules["time_base_s"]) + float(rules["time_per_100m_s"]) * dist / 100.0 + floor_n * 5.0 + float(cook[0])
	var rt: Array = rules["rival_take_s"]
	var o = {
		"id": next_id, "rest": rest, "rest_name": r["name"], "item": item, "door": door, "customer": cust,
		"floor": floor_n, "pay": snappedf(pay, 0.5), "limit": limit, "dist": dist, "elapsed": 0.0,
		"expires": rs.randf_range(rt[0], rt[1]) * (1.6 if not world.events.rivals_active() else 1.0) + 10.0,
		"state": "offer", "cook_left": rs.randf_range(cook[0], cook[1]), "condition": 100.0, "temp": 100.0,
		"wet": 0.0, "flags": {}, "quest": "", "risk": _risk(item, dist),
	}
	next_id += 1
	return o


func _risk(item: Array, dist: float) -> String:
	var k: String = item[2]
	if k in ["fragile", "frozen", "drink_hot"] or dist > 160.0:
		return "высокий"
	if k in ["drink", "cold"] or dist > 100.0:
		return "средний"
	return "низкий"


func accept(o: Dictionary) -> bool:
	if active.size() >= capacity():
		world.toast("Сумка занята! Сначала доставь текущий заказ%s." % ("" if Game.upgrade_level("rack") > 0 else " (багажник даёт +1 место)"), 2.5)
		return false
	if o.get("needs", "") == "rack" and Game.upgrade_level("rack") == 0:
		world.toast("Без багажника этот заказ не увезти. Купи в мастерской.", 2.5)
		return false
	offers.erase(o)
	o["state"] = "to_restaurant"
	active.append(o)
	world.events.on_accept(o)
	world.story.on_accept(o)
	Sfx.play("accept")
	changed.emit()
	world.refresh_gps()
	return true


func decline(o: Dictionary) -> void:
	offers.erase(o)
	changed.emit()


func cancel(o: Dictionary, reason = "Отменён") -> void:
	active.erase(o)
	o["state"] = "failed"
	Game.add_rating(3.0)
	streak = 0
	day_log.append({"name": o["item"][1], "pay": 0.0, "stars": 0, "late": false, "note": reason})
	world.toast("Заказ отменён: %s. Рейтинг немного упал." % reason, 3.0)
	if o["state"] != "to_restaurant":
		world.player.carrying = _any_carried()
	changed.emit()
	world.refresh_gps()


func _any_carried() -> bool:
	for o in active:
		if o["state"] == "carrying":
			return true
	return false


# ---------------------------------------------------------------- restaurant
func for_restaurant(rest: String) -> Array:
	var out = []
	for o in active:
		if o["rest"] == rest and o["state"] in ["to_restaurant", "waiting"]:
			out.append(o)
	return out


func pickup(o: Dictionary) -> void:
	o["state"] = "carrying"
	o["condition"] = 100.0
	o["temp"] = 100.0
	world.player.carrying = true
	Sfx.play("pickup")
	world.toast("Заказ в сумке: %s. Вези к клиенту!" % o["item"][1], 2.2)
	world.story.on_pickup(o)
	world.events.on_pickup(o)
	changed.emit()
	world.refresh_gps()


# ---------------------------------------------------------------- food state
func _food_drift(o: Dictionary, delta: float) -> void:
	if o["state"] != "carrying":
		return
	var f: Dictionary = rules["food"].get(o["item"][2], {})
	var heat: float = world.daynight.heat
	var cool = 0.6 if Game.has_gear("cooling_pack") else 1.0
	if f.has("cool_per_s"):
		o["temp"] = max(0.0, o["temp"] - float(f["cool_per_s"]) * delta * (0.6 if heat > 0.5 else 1.0))
	if f.has("melt_per_s"):
		o["temp"] = max(0.0, o["temp"] - float(f["melt_per_s"]) * delta * cool * (1.0 + heat * (float(f.get("heat_mult", 1.0)) - 1.0)))
	if f.has("warm_per_s"):
		o["temp"] = max(0.0, o["temp"] - float(f["warm_per_s"]) * delta * cool * (1.0 + heat))
	if world.daynight.rain > 0.4 and not Game.has_gear("waterproof_bag"):
		o["wet"] = min(100.0, o["wet"] + 1.2 * delta * world.daynight.rain)


func damage_food(amount: float, reason = "") -> void:
	for o in active:
		if o["state"] != "carrying":
			continue
		var k: String = o["item"][2]
		var mult = 1.0
		if k in ["drink", "drink_hot"]:
			mult = 1.6 * (0.35 if Game.has_gear("cup_holder") else 1.0)
		if k == "fragile":
			mult = 2.0 * (0.5 if Game.has_gear("soft_bag") else 1.0)
		o["condition"] = max(0.0, o["condition"] - amount * mult)
		if reason in ["crash", "brake"] and o["condition"] < 60.0:
			world.player.hint("spilled", "Ой-ой, в сумке что-то перевернулось! Тормози плавнее.", 8.0)
	changed.emit()


func shake_food(amount: float) -> void:
	for o in active:
		if o["state"] == "carrying" and o["item"][2] == "fragile":
			o["condition"] = max(0.0, o["condition"] - amount * (8.0 if not Game.has_gear("soft_bag") else 3.0))
			world.player.hint("shake", "Торт трясётся на брусчатке! Медленнее или по асфальту.", 15.0)


func carried() -> Array:
	return active.filter(func(o): return o["state"] == "carrying")


func time_left(o: Dictionary) -> float:
	return float(o["limit"]) - float(o["elapsed"])


# ---------------------------------------------------------------- delivery
## Called by the door sequence after the stairs and the dialogue. reply: "polite" | "funny" | "curt" | "door"
func deliver(o: Dictionary, reply: String) -> Dictionary:
	active.erase(o)
	o["state"] = "done"
	var late = time_left(o) < 0.0
	var stars = 5.0
	if late:
		var over = -time_left(o) / float(o["limit"])
		stars -= 1.0 + floor(over / 0.2)
	if o["condition"] < 70.0:
		stars -= 1.0
	if o["condition"] < 40.0:
		stars -= 1.0
	var k: String = o["item"][2]
	if k in ["hot", "frozen", "cold", "drink_hot"] and o["temp"] < 35.0:
		stars -= 1.0
	if o["wet"] > 50.0:
		stars -= 0.5
	var cust: Dictionary = o["customer"]
	var t: String = cust.get("trait", "polite")
	match reply:
		"polite":
			stars += 0.3
		"funny":
			stars += 0.5 if t != "capricious" else -0.3
		"curt":
			stars -= 1.0
		"door":
			stars -= 0.3 if t != "leave_at_door" else -0.3
	if t == "capricious" and rs.randf() < 0.4:
		stars -= 1.0 if reply != "polite" else 0.5
	if t == "no_call" and o["flags"].get("called", false):
		stars -= 1.0
	stars = clamp(round(stars), 1.0, 5.0)
	var pay = float(o["pay"])
	var tip = 0.0
	var tp: Array = rules["tip_on_time"]
	if stars >= 4.0 and rs.randf() < float(cust.get("tip", 0.4)) * (1.1 if Game.state.get("helmet", "") == "helmet_retro" else 1.0):
		tip = snappedf((rs.randf_range(tp[0], tp[1]) + (2.0 if stars >= 5.0 else 0.0)) * float(rules.get("tip_mult", 1.0)), 0.5)
	if late:
		pay *= 0.7
	var bonus = 0.0
	if not late:
		streak += 1
		var sb: Array = rules["streak_bonus"]
		if streak % int(sb[0]) == 0:
			bonus = float(sb[1])
			world.toast("Серия из %d заказов без опозданий! Бонус +%d" % [streak, int(bonus)], 2.5)
	else:
		streak = 0
		Game.state["stats"]["late"] += 1
	Game.state["best_streak"] = max(int(Game.state.get("best_streak", 0)), streak)
	var total = pay + tip + bonus
	Game.earn(total)
	Game.state["stats"]["tips"] += tip
	Game.state["stats"]["delivered"] += 1
	Game.add_rating(stars)
	world.player.carrying = _any_carried()
	Sfx.play("deliver")
	Sfx.play("coin", 0.7)
	var res = {"name": o["item"][1], "pay": pay, "tip": tip, "bonus": bonus, "stars": int(stars), "late": late,
		"total": total, "customer": cust.get("name", ""), "note": "", "quest": o.get("quest", "")}
	day_log.append(res)
	world.story.on_deliver(o, res)
	world.events.on_deliver(o, res)
	changed.emit()
	world.refresh_gps()
	return res


## Current GPS target for the most urgent active order.
func gps_target() -> Dictionary:
	var best = {}
	for o in active:
		if best.is_empty() or time_left(o) < time_left(best):
			best = o
	if best.is_empty():
		return {}
	if best["state"] in ["to_restaurant", "waiting"]:
		var r: Dictionary = data["restaurants"][best["rest"]]
		return {"pos": _v(r["pickup"]), "label": best["rest_name"], "order": best, "kind": "restaurant"}
	var d: Dictionary = best["door"]
	if best["flags"].get("pin_door"):
		d = best["flags"]["pin_door"]
	return {"pos": _v(d["pos"]), "label": d["label"], "order": best, "kind": "door"}
