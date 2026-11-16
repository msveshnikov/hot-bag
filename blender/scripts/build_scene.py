"""Task 4: bring the Old Town to life.
blender -b --factory-startup -P build_scene.py -- [--no-render]
Reads assets/levels/old_town_layout.json (Godot coords) and writes:
  assets/levels/old_town_population.json  NPCs, cooks, mentor, police, rivals, traffic, fx
  assets/levels/old_town_orders.json      restaurants, menus, regular customers, address book, order rules
  assets/levels/old_town_events.json      courier problems with weights per chapter
and renders the populated level (characters imported from glTF) into renders/levels/populated_*.png
"""
import sys
import os
import json
import math
import random

sys.path.insert(0, os.path.dirname(__file__))
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LV = os.path.join(ROOT, "assets", "levels")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
NO_RENDER = "--no-render" in ARGS

RESTAURANTS = {
    "pizza": dict(name="Пиццерия «Тесто»", items=[["pizza", "Пицца", "hot", 1.0], ["drink", "Лимонад", "drink", 0.4]],
                  cook=[20, 45], slow=False, price=1.0),
    "burger": dict(name="Бургерная «Двойной»", items=[["burger", "Бургер", "hot", 1.0], ["drink", "Кола", "drink", 0.4]],
                   cook=[15, 35], slow=False, price=0.9),
    "sushi": dict(name="Суши-бар «Волна»", items=[["sushi", "Сет роллов", "cold", 1.0]], cook=[40, 90], slow=True,
                  price=1.3),
    "coffee": dict(name="Кофейня «Пенка»", items=[["coffee", "Капучино", "drink_hot", 0.6],
                                                  ["icecream", "Мороженое", "frozen", 0.7]],
                   cook=[10, 25], slow=False, price=0.8),
    "cake": dict(name="Кондитерская «Вишенка»", items=[["cake", "Торт", "fragile", 1.4],
                                                     ["icecream", "Мороженое", "frozen", 0.7]],
                 cook=[25, 50], slow=False, price=1.2),
}

FOOD_PROPS = {"pizza": "pizza_box", "burger": "paper_bag", "drink": "cup_holder", "sushi": "sushi_box",
              "coffee": "cup_holder", "icecream": "ice_cream_tub", "cake": "cake_box", "lunch": "lunch_crate"}

REGULARS = [
    dict(id="ded", name="Ворчливый дед Борис", model="oldman", trait="capricious", floors_min=5, tip=0.15,
         lines=["Опять холодное принёс?!", "В моё время пиццу на лошадях возили — и то быстрее!",
                "Ладно, ладно... спасибо, сынок."]),
    dict(id="zina", name="Бабушка Зина", model="grandma", trait="polite", floors_min=3, tip=0.9, quest="cake",
         lines=["Ой, проходи, касатик! Чаю?", "Только торт не растряси — внуку на день рождения!",
                "Вот тебе на конфетки!"]),
    dict(id="petya", name="Студент Петя", model="student", trait="no_call", floors_min=3, tip=0.3,
         lines=["Не звони, пожалуйста, у меня пара по зуму!", "О, бургер! Ты лучший!"]),
    dict(id="olya", name="Мама Оля", model="mom", trait="leave_at_door", floors_min=2, tip=0.6,
         lines=["Тсс! Ребёнок спит. Оставьте у двери!", "Спасибо, вы спасли наш вечер."]),
    dict(id="office", name="Офис «Кубик»", model="office", trait="polite", floors_min=4, tip=0.7, quest="office_lunch",
         lines=["Обед на двадцать человек! Только ничего не урони.", "Бухгалтерия будет довольна!"]),
    dict(id="tourist", name="Турист Ганс", model="tourist", trait="polite", floors_min=2, tip=0.8,
         lines=["Дэнкью! Это есть лучший город!", "Можно с вами селфи?"]),
]

RANDOM_LINES = {
    "polite": ["Спасибо большое!", "Как быстро! Вот это сервис.", "Хорошего дня!"],
    "capricious": ["А почему так долго?", "Я хотел без лука... ну ладно.", "Звёзд не будет. Или будет. Посмотрим."],
    "no_call": ["Я же писал — не звонить!", "О, спасибо, что не звонили."],
    "leave_at_door": ["Можно было оставить у двери!", "Спасибо, что оставили у двери."],
}

EVENTS = [
    dict(id="battery_low", title="Самокат разряжается", text="Индикатор мигает красным. Ищи зарядку!", weight=[0, 1, 2],
         when="scooter", fix=["charger", "powerbank"]),
    dict(id="flat_tire", title="Прокол!", text="Пшшш... колесо сдулось. Ремкомплект или мастерская.",
         weight=[0, 1, 2], when="riding", fix=["repair_kit", "garage"]),
    dict(id="rain", title="Начался дождь", text="Скользко! Еда может промокнуть.", weight=[1, 2, 2], duration=180,
         fix=["raincoat", "waterproof_bag", "wide_tires"]),
    dict(id="heat", title="Жара", text="Мороженое тает, напитки греются.", weight=[1, 1, 1], when="noon", duration=150,
         fix=["cooling_pack", "short_route"]),
    dict(id="roadblock", title="Перекрытие", text="Ремонт дороги! Ищи объезд через дворы и парк.", weight=[0, 1, 2],
         duration=200),
    dict(id="restaurant_delay", title="Кухня не успевает", text="Повар машет рукой: ещё пару минут!",
         weight=[1, 2, 2], fix=["cancel_wait", "second_order"]),
    dict(id="wrong_address", title="Пин стоит не там", text="Метка на карте не у того подъезда. Позвони клиенту.",
         weight=[0, 1, 2], fix=["call"]),
    dict(id="no_answer", title="Клиент не отвечает", text="Звонок, ожидание... можно оставить у двери.",
         weight=[0, 1, 2], fix=["call", "wait", "leave_at_door"]),
    dict(id="broken_lift", title="Лифт сломан", text="Это и так дом без лифта. Ноги, работаем!", weight=[1, 1, 1],
         fix=["stamina", "energy_drink"]),
    dict(id="intercom", title="Домофон не работает", text="Не пускают в подъезд. Позвони клиенту.",
         weight=[0, 1, 2], fix=["call"]),
    dict(id="spilled", title="Перевёрнутая еда", text="Резкое торможение — содержимое сумки перемешалось.",
         weight=[1, 1, 1], when="crash", fix=["careful", "cup_holder", "soft_bag"]),
    dict(id="theft", title="Угон!", text="Кто-то уехал на твоём транспорте! Без замка не оставляй.",
         weight=[0, 1, 2], when="unlocked", fix=["lock", "parking"]),
    dict(id="fine", title="Штраф", text="Полиция: езда по тротуару / на красный. Минус монеты.",
         weight=[1, 1, 1], when="police", fix=["rules"]),
    dict(id="fall", title="Падение", text="Ой! Курьер упал. Шлем снижает время восстановления.",
         weight=[1, 1, 1], when="crash", fix=["helmet"]),
    dict(id="hunger", title="Голод и усталость", text="Скорость падает. Перекус, кофе или скамейка.",
         weight=[1, 1, 1], when="stats", fix=["snack", "coffee", "bench"]),
    dict(id="phone_low", title="Телефон садится", text="Заказы и карта исчезнут! Павербанк или зарядка в кафе.",
         weight=[0, 1, 1], when="stats", fix=["powerbank", "cafe"]),
    dict(id="rivals", title="Конкуренты", text="Курьеры «Молнии» хватают выгодные заказы. Быстрее жми «Принять»!",
         weight=[0, 1, 2], fix=["rating", "speed"]),
    dict(id="capricious", title="Капризный клиент", text="Низкая оценка без причины. Вежливый ответ смягчает.",
         weight=[1, 1, 2], fix=["polite"]),
]

ORDER_RULES = dict(
    base_pay=4.0, pay_per_100m=1.6, time_base_s=70.0, time_per_100m_s=32.0, tip_on_time=[0.0, 3.0],
    streak_bonus=[3, 5.0], night_bonus=0.25, rain_bonus=0.3, rush_hours=[[12, 14], [18, 20]], rush_bonus=0.2,
    rival_take_s=[20, 45], max_offers=4, offer_interval_s=[8, 16],
    food=dict(hot=dict(cool_per_s=0.35), drink=dict(spill=1.6), drink_hot=dict(spill=1.8, cool_per_s=0.25),
              frozen=dict(melt_per_s=0.25, heat_mult=2.5), cold=dict(warm_per_s=0.15), fragile=dict(shake=2.5)),
    rating=dict(start=4.0, warn=3.0, ban=2.5),
)


def gpos(p):
    return p


def main():
    layout = json.load(open(os.path.join(LV, "old_town_layout.json"), encoding="utf-8"))
    inst = layout["instances"]
    marks = layout["markers"]
    rs = random.Random(9)

    def M(prefix):
        return [m for m in marks if m["name"].startswith(prefix)]

    # ---------------- address book (deliverable doors)
    doors = []
    plates = {}
    for m in marks:
        if m["name"].startswith("MARK_plate_"):
            plates[(m["inst"], m["name"].split("_")[-1])] = m
    for m in marks:
        if m["name"].startswith("MARK_door_") and "inst" in m:
            h = inst[m["inst"]]
            if h["group"] != "house":
                continue
            k = m["name"].split("_")[-1]
            doors.append(dict(id="%s_%d_%s" % (h["street"], h["number"], k), street=h["street"],
                              street_name=h["street_name"], number=h["number"], entrance=int(k) + 1,
                              floors=h["floors"], lift=False, pos=m["pos"], yaw=m["yaw"],
                              plate=plates.get((m["inst"], k), {}).get("pos"),
                              label="%s, %d, под. %d" % (h["street_name"], h["number"], int(k) + 1)))
    print("doors", len(doors))

    # regulars get fixed addresses with enough floors
    used = set()
    regulars = []
    for r in REGULARS:
        cands = [d for d in doors if d["floors"] >= r["floors_min"] and d["id"] not in used]
        d = rs.choice(cands)
        used.add(d["id"])
        regulars.append(dict(r, address=d["id"], floor=rs.randint(max(2, d["floors"] - 1), d["floors"])))

    restaurants = {}
    for k, v in RESTAURANTS.items():
        pk = [m for m in marks if m["name"] == "MARK_pickup_" + k]
        ck = [m for m in marks if m["name"] == "MARK_cook_" + k]
        pr = [m for m in marks if m["name"] == "MARK_parking_" + k]
        restaurants[k] = dict(v, pickup=pk[0]["pos"], pickup_yaw=pk[0]["yaw"], cook_pos=ck[0]["pos"],
                              cook_yaw=ck[0]["yaw"], parking=pr[0]["pos"] if pr else pk[0]["pos"],
                              prop=FOOD_PROPS[v["items"][0][0]])
    orders = dict(restaurants=restaurants, doors=doors, regulars=regulars, random_lines=RANDOM_LINES,
                  rules=ORDER_RULES, food_props=FOOD_PROPS,
                  quests=dict(
                      cake=dict(title="Торт для внука", giver="zina", restaurant="cake", item="cake", reward=40,
                                text="Бабушка Зина заказала торт на день рождения внука. Не тряси!"),
                      office_lunch=dict(title="Обед на 20 персон", giver="office", restaurant="burger", item="lunch",
                                        reward=60, needs="rack",
                                        text="Офис «Кубик» заказывает огромный обед. Без багажника не увезти.")))

    # ---------------- population
    pop = dict(npcs=[], cooks=[], mentor=None, police=[], rivals=[], thieves=[], traffic={}, fx=[])
    models_day = ["office", "student", "mom", "grandma", "tourist", "oldman"]
    for m in M("MARK_npc"):
        model = rs.choice(models_day)
        beh = rs.choice(["wander", "wander", "wander", "stand", "phone"])
        sched = rs.choice([[7, 23], [8, 20], [10, 22], [17, 23], [7, 12]])
        pop["npcs"].append(dict(id="npc%d" % m["id"], model=model, pos=m["pos"], yaw=m["yaw"], behaviour=beh,
                                radius=rs.uniform(10, 30), schedule=sched,
                                anim={"wander": "walk", "stand": "idle", "phone": "phone_call"}[beh]))
    for g in M("MARK_tourist_group"):
        for k in range(3):
            a = k * 2.1
            p = [g["pos"][0] + math.cos(a) * 1.6, g["pos"][1], g["pos"][2] + math.sin(a) * 1.6]
            pop["npcs"].append(dict(id="tour%d_%d" % (g["id"], k), model="tourist", pos=p, yaw=rs.uniform(-180, 180),
                                    behaviour="photo", radius=3, schedule=[9, 19], anim="photo"))
    # people sitting at cafe tables
    sits = [m for m in marks if m["name"] in ("MARK_sit_a", "MARK_sit_b")]
    for i, m in enumerate(sits):
        if rs.random() < 0.6:
            pop["npcs"].append(dict(id="cafe%d" % i, model=rs.choice(["office", "mom", "tourist", "student", "grandma"]),
                                    pos=m["pos"], yaw=m["yaw"], behaviour="sit", radius=0,
                                    schedule=rs.choice([[9, 21], [12, 23], [8, 14]]),
                                    anim=rs.choice(["sit", "sip_coffee"])))
    for k, r in restaurants.items():
        pop["cooks"].append(dict(id="cook_" + k, model="cook", pos=r["cook_pos"], yaw=r["cook_yaw"], anim="cook_idle",
                                 restaurant=k))
    mm = M("MARK_mentor")[0]
    pop["mentor"] = dict(id="mentor", model="mentor", pos=mm["pos"], yaw=mm["yaw"], anim="sip_coffee", name="Михалыч")
    pol = M("MARK_police")
    pp = M("MARK_police_patrol")[0]
    pop["police"].append(dict(id="police0", model="police", pos=pol[0]["pos"], yaw=pol[0]["yaw"], behaviour="post",
                              see_radius=14.0, anim="idle"))
    pop["police"].append(dict(id="police1", model="police", pos=pp["pos"], yaw=0, behaviour="patrol", route=pp["route"],
                              see_radius=12.0, anim="walk", schedule=[9, 21]))
    for i, m in enumerate(M("MARK_courier_spawn")):
        pop["rivals"].append(dict(id="rival%d" % i, model=["courier_m", "courier_f", "courier_m"][i],
                                  jacket=["#ef6a5b", "#9a6fd1", "#f2c230"][i], vehicle="scooter", pos=m["pos"],
                                  company="Молния", speed=6.5 + i * 0.6))
    for m in M("MARK_thief"):
        pop["thieves"].append(dict(id="thief%d" % m["id"], model="thief", pos=m["pos"], vehicle="bicycle"))
    pop["traffic"] = dict(models=["car_hatch", "car_hatch", "car_taxi", "car_van", "bus"],
                          paints=["#ef6a5b", "#7ec3e8", "#8fd3b0", "#f6b98a", "#b9a3d8", "#f7f3ea", "#5d6670"],
                          count_by_hour=[[0, 3], [7, 9], [10, 7], [12, 9], [17, 10], [20, 6], [23, 3]],
                          speed=8.0, tram=dict(model="tram", period=layout["traffic"]["tram"]["period"]))
    # effects
    for k, r in restaurants.items():
        p = r["pickup"]
        pop["fx"].append(dict(kind="steam", pos=[p[0], 3.2, p[2]], scale=0.8))
    for m in [i for i in inst if i["asset"] == "fountain"]:
        pop["fx"].append(dict(kind="fountain", pos=[m["pos"][0] - 0.6, 3.0, m["pos"][2]], scale=1.0))
    for m in [i for i in inst if i["asset"] == "garage"]:
        pop["fx"].append(dict(kind="sparks", pos=[m["pos"][0] - 2.0, 0.8, m["pos"][2] + 2.5], scale=0.6,
                              schedule=[9, 18]))
    for m in [i for i in inst if i["asset"] == "courier_cafe"]:
        pop["fx"].append(dict(kind="steam", pos=[m["pos"][0], 4.3, m["pos"][2] + 2.8], scale=0.5))
    for (x, z) in ((-11, -12), (-25, -2), (5, -8), (-40, -20)):
        pop["fx"].append(dict(kind="pigeons", pos=[x, 0, z], scale=1.0, count=6))
    grid = layout["grid"]
    cells = [(i, j) for j, row in enumerate(grid["rows"]) for i, c in enumerate(row) if c in ("c", "a")]
    for _ in range(40):
        i, j = rs.choice(cells)
        x = grid["origin"][0] + (i + 0.5) * grid["cell"]
        z = grid["origin"][2] - (j + 0.5) * grid["cell"]
        pop["fx"].append(dict(kind="puddle", pos=[x, 0.03, z], scale=rs.uniform(1.0, 2.4), weather="rain"))
    pop["fx"].append(dict(kind="heat_haze", pos=[0, 0, 0], scale=1.0, weather="heat"))
    pop["player"] = dict(pos=M("MARK_player_start")[0]["pos"], yaw=M("MARK_player_start")[0]["yaw"],
                         vehicle="bicycle")

    events = dict(events=EVENTS, chapters=["Первая смена", "Свой самокат", "Деловой центр (скоро)"],
                  base_interval_s=[70, 120])
    for nm, data in (("population", pop), ("orders", orders), ("events", events)):
        with open(os.path.join(LV, "old_town_%s.json" % nm), "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=1)
    print("npcs", len(pop["npcs"]), "fx", len(pop["fx"]), "regulars", [(r["id"], r["address"]) for r in regulars])

    if NO_RENDER:
        print("DONE")
        return
    render_populated(pop, layout)
    print("DONE")


def render_populated(pop, layout):
    import bpy
    import lib_render as R
    from mathutils import Vector
    bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT, "blender", "old_town.blend"))
    cache = {}

    def load(model):
        if model in cache:
            return cache[model]
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, "assets", "characters", model + ".gltf"))
        new = [o for o in bpy.data.objects if o not in before]
        root = [o for o in new if o.parent is None][0]
        for o in new:
            if o.name.startswith(("ACC_", "HELD_")) and o.name not in ("ACC_cap", "ACC_bag", "ACC_hair_short"):
                o.hide_render = True
        cache[model] = (root, new)
        root.location = (0, 0, -100)
        return cache[model]

    def put(model, pos, yaw, anim):
        root, objs = load(model)
        # duplicate the whole hierarchy (linked data)
        mapping = {}
        for o in objs:
            c = o.copy()
            bpy.context.scene.collection.objects.link(c)
            mapping[o] = c
        for o, c in mapping.items():
            if o.parent in mapping:
                c.parent = mapping[o.parent]
            for md in c.modifiers:
                if md.type == "ARMATURE" and md.object in mapping:
                    md.object = mapping[md.object]
        r = mapping[root]
        # Godot -> Blender
        r.location = (pos[0], -pos[2], pos[1])
        r.rotation_mode = "XYZ"
        r.rotation_euler = (0, 0, math.radians(yaw))
        for c in mapping.values():
            if c.type == "ARMATURE":
                act = bpy.data.actions.get(anim) or next((a for a in bpy.data.actions if a.name.startswith(anim)), None)
                if act:
                    c.animation_data_create()
                    c.animation_data.action = act
        return r

    for n in pop["npcs"]:
        put(n["model"], n["pos"], n["yaw"], n["anim"])
    for n in pop["cooks"] + [pop["mentor"]] + pop["police"]:
        put(n["model"], n["pos"], n["yaw"], n["anim"])
    p = pop["player"]
    put("courier_m", p["pos"], p["yaw"], "idle")
    bpy.context.scene.frame_set(6)
    R.setup_render((1280, 720))
    views = {"square": ((40, -40, 30), (-11, 10, 4)), "restaurants": ((-10, 25, 14), (-14, -8, 2)),
             "base": ((50, 12, 6), (52, 30, 2))}
    for mood in ("day", "evening", "night"):
        R.mood(mood)
        for vn, (loc, tgt) in views.items():
            R.camera(loc=loc, target=tgt, lens=28)
            R.render(os.path.join(ROOT, "renders", "levels", "populated_%s_%s.png" % (vn, mood)))


if __name__ == "__main__":
    main()
