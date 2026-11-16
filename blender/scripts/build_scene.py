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
LEVEL = ARGS[ARGS.index("--level") + 1] if "--level" in ARGS else "old_town"

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
    # run 2, chapter 5: the hero's own restaurant on the square (orders only after it is bought)
    "dream": dict(name="Ресторан «Горячая сумка»", items=[["dream", "Фирменный обед", "hot", 1.6]], cook=[20, 35],
                  slow=False, price=1.5, owned_only=True),
}

FOOD_PROPS = {"pizza": "pizza_box", "burger": "paper_bag", "drink": "cup_holder", "sushi": "sushi_box",
              "coffee": "cup_holder", "icecream": "ice_cream_tub", "cake": "cake_box", "lunch": "lunch_crate",
              "dream": "lunch_crate", "wok": "paper_bag", "salad": "sushi_box", "burrito": "paper_bag",
              "shawarma": "paper_bag", "pastry": "paper_bag", "pie": "cake_box", "groceries": "lunch_crate",
              "veg": "lunch_crate", "fish": "ice_cream_tub", "cheese": "cake_box", "honey": "paper_bag",
              "dumplings": "sushi_box", "ramen": "paper_bag", "steak": "paper_bag", "pancakes": "pizza_box",
              "cocoa": "cup_holder", "picnic": "lunch_crate"}

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
    dict(id="critic", name="Критик Аркадий Вилкин", model="office", trait="capricious", floors_min=4, tip=1.0,
         quest="critic", lines=["Хм. Подача... приемлемая. Посмотрим, что внутри.",
                                "Это... это превосходно! Напишу в колонке."]),
]

# ---------------------------------------------------------------- run 2 districts
CITY_RESTAURANTS = {
    "wok": dict(name="Вок-бар «Палочки»", items=[["wok", "Лапша вок", "hot", 1.0], ["drink", "Морс", "drink", 0.4]],
                cook=[15, 40], slow=False, price=1.1),
    "salad": dict(name="Салат-бар «Зелень»", items=[["salad", "Салат-боул", "cold", 0.9],
                                                   ["drink", "Смузи", "drink", 0.5]], cook=[10, 25], slow=False,
                  price=1.0),
    "burrito": dict(name="«Буррито-бро»", items=[["burrito", "Буррито", "hot", 1.0], ["drink", "Лимонад", "drink", 0.4]],
                    cook=[15, 35], slow=False, price=1.0),
}
CITY_REGULARS = [
    dict(id="zorin", name="Директор Зорин", model="office", trait="capricious", floors_min=18, tip=0.9,
         lines=["У меня совещание через минуту. Вы опоздали на сорок секунд.", "Неплохо. Свободны."]),
    dict(id="kostya", name="Айтишник Костя", model="student", trait="no_call", floors_min=8, tip=0.6,
         lines=["Тсс, у меня созвон! Просто махни рукой.", "Еда! Код скомпилировался!"]),
    dict(id="marina", name="Марина из отдела кадров", model="office", trait="polite", floors_min=6, tip=0.8,
         lines=["Вы наш спаситель! Отдел кадров не ел с утра.", "Возьмите конфетку!"]),
    dict(id="viktor", name="Охранник Виктор", model="guard", trait="polite", floors_min=1, tip=0.5, quest="guard_coffee",
         floor=1, lines=["Пропуск? А, это мне! Ну заходи, курьер, свой человек.", "Буррито! Вот это уважение."]),
    dict(id="board", name="Совет директоров", model="office", trait="capricious", floors_min=19, tip=1.0,
         quest="board_lunch", lines=["Двадцать порций? Всё на месте? Отлично.", "Совет доволен. Это редкость."]),
]
CITY_QUESTS = dict(
    guard_coffee=dict(title="Обед для охранника", giver="viktor", restaurant="burrito", item="burrito", reward=30,
                      text="Охранник Виктор весь день на посту. Принеси ему буррито — и он выпишет тебе пропуск во все "
                           "башни (больше никаких проверок)."),
    board_lunch=dict(title="Совет директоров", giver="board", restaurant="wok", item="lunch", reward=90, needs="rack",
                     text="Совет директоров заказал двадцать порций лапши на верхний этаж. Без багажника не увезти."),
)
BEREZKI_RESTAURANTS = {
    "shawarma": dict(name="Шаурма «Свёрток»", items=[["shawarma", "Шаурма", "hot", 1.0], ["drink", "Айран", "drink", 0.4]],
                     cook=[10, 25], slow=False, price=0.9),
    "bakery": dict(name="«Булочная №5»", items=[["pastry", "Пирожки", "hot", 0.8], ["pie", "Пирог", "fragile", 1.2]],
                   cook=[10, 30], slow=False, price=0.9),
    "grocery": dict(name="Магазин «Всё рядом»", items=[["groceries", "Пакет продуктов", "heavy", 1.3],
                                                      ["icecream", "Пломбир", "frozen", 0.6]], cook=[20, 40],
                    slow=False, price=1.0),
}
BEREZKI_REGULARS = [
    dict(id="semyon", name="Дедушка Семён", model="oldman", trait="polite", floors_min=16, tip=0.9, quest="no_lift",
         lines=["Лифт третий день не ходит, сынок. Спасибо, что дошёл!", "Вот, возьми яблочко с дачи."]),
    dict(id="gamers", name="Геймеры из 9 к.2", model="student", trait="no_call", floors_min=9, tip=0.7,
         quest="night_gamers", lines=["Тише! Мы в рейде! Ставь у двери.", "Еда до конца катки — легенда!"]),
    dict(id="lost", name="Жилец Гена", model="office", trait="capricious", floors_min=10, tip=0.8,
         quest="hidden_corpus", lines=["Ну наконец-то! Нас никто никогда не находит.", "Корпус четыре, я же писал!"]),
    dict(id="nina", name="Тётя Нина", model="grandma", trait="polite", floors_min=5, tip=0.9,
         lines=["Ой, курьерчик! Заходи, пирожков дам!", "Внукам — шаурму, а мне — пирожок."]),
    dict(id="sveta", name="Мама Света", model="mom", trait="leave_at_door", floors_min=6, tip=0.5,
         lines=["Ребёнок спит! Оставь у двери, пожалуйста.", "Спасибо, тихонько!"]),
]
BEREZKI_QUESTS = dict(
    night_gamers=dict(title="Ночной рейд", giver="gamers", restaurant="shawarma", item="shawarma", reward=40,
                      text="Геймеры из «9 к.2» заказали шаурму посреди ночи. Успей до конца катки!"),
    hidden_corpus=dict(title="Корпус 4", giver="lost", restaurant="grocery", item="groceries", reward=45,
                       text="Адрес «Берёзовая, 7 к.4», а GPS такого корпуса не знает. Ищи по большим номерам на "
                            "домах — бабушки подскажут."),
    no_lift=dict(title="Шестнадцатый этаж", giver="semyon", restaurant="bakery", item="pie", reward=50,
                 text="Дедушке Семёну на 16-й этаж нужен пирог. Лифт сломан. Совсем."),
)
# ---------------------------------------------------------------- run 3: «Гастроквартал и Большой парк»
GASTRO_RESTAURANTS = {
    "veg": dict(name="Рынок: овощной ряд", items=[["veg", "Корзина овощей", "heavy", 1.0],
                                                 ["veg", "Ящик мандаринов", "heavy", 1.1]], cook=[8, 20], slow=False,
                price=0.9),
    "fish": dict(name="Рынок: рыбный ряд", items=[["fish", "Свежая рыба во льду", "frozen", 1.3]], cook=[10, 25],
                 slow=False, price=1.1),
    "cheese": dict(name="Рынок: сыр и мёд", items=[["cheese", "Сырная тарелка", "fragile", 1.2],
                                                  ["honey", "Банка мёда", "fragile", 0.9]], cook=[8, 20], slow=False,
                   price=1.0),
    "dumplings": dict(name="Пельменная «Лепим!»", items=[["dumplings", "Пельмени со сметаной", "hot", 1.0],
                                                        ["cocoa", "Какао", "drink_hot", 0.5]], cook=[15, 35],
                      slow=False, price=1.0),
    "ramen": dict(name="Раменная «Сугои»", items=[["ramen", "Рамен", "drink_hot", 1.3],
                                                  ["ramen", "Гёдза", "hot", 0.8]], cook=[20, 45], slow=True,
                  price=1.2),
    "grill": dict(name="Гриль-бар «Уголёк»", items=[["steak", "Стейк", "hot", 1.6], ["steak", "Шашлык", "hot", 1.3]],
                  cook=[25, 55], slow=True, price=1.3),
    "pancakes": dict(name="Блинная «Масленица»", items=[["pancakes", "Блины с вареньем", "hot", 0.8],
                                                       ["cocoa", "Какао с маршмеллоу", "drink_hot", 0.6]],
                     cook=[10, 25], slow=False, price=0.9),
}
GASTRO_REGULARS = [
    dict(id="chef_lev", name="Шеф Лев", model="cook", trait="capricious", floors_min=3, tip=1.0, quest="market_fish",
         lines=["Рыба утренняя? Покажи жабры! ...Годится.", "Без свежей рыбы у меня нет меню. Спасибо!"]),
    dict(id="picnic", name="Студенты на пикнике", model="student", trait="polite", floors_min=0, tip=0.7,
         quest="park_picnic", park=True, lines=["Ура, еда! Садись с нами!", "Лучший пикник в сезоне!"]),
    dict(id="skaters", name="Фигуристы на пруду", model="mom", trait="polite", floors_min=0, tip=0.9,
         quest="skater_cocoa", park=True, lines=["Горячее какао! Ты нас спас, руки ледяные!", "Приезжай кататься!"]),
    dict(id="poet", name="Поэт Аполлон", model="oldman", trait="capricious", floors_min=4, tip=0.4,
         lines=["Курьер, как вестник муз, явился...", "Блины! Это рифма к слову «мечты»."]),
    dict(id="lena", name="Блогер Лена", model="student", trait="no_call", floors_min=3, tip=0.8,
         lines=["Тсс, я в эфире! Сейчас сниму распаковку.", "Подписчики в восторге от рамена!"]),
]
GASTRO_QUESTS = dict(
    market_fish=dict(title="Рыба для шефа", giver="chef_lev", restaurant="fish", item="fish", reward=45,
                     text="Шеф Лев остался без рыбы в разгар ужина. Привези с рынка свежую рыбу во льду — и быстро, "
                          "пока лёд не растаял!"),
    park_picnic=dict(title="Пикник в парке", giver="picnic", restaurant="grill", item="picnic", reward=40,
                     text="Студенты устроили пикник в Большом парке. На моторе в парк не въехать — паркуйся у ворот "
                          "и неси шашлык пешком."),
    skater_cocoa=dict(title="Какао для фигуристов", giver="skaters", restaurant="pancakes", item="cocoa", reward=35,
                      text="Пруд замёрз, на льду катаются! Фигуристы замёрзли и просят горячего какао к катку."),
)

LEVELS = {
    "old_town": dict(restaurants=RESTAURANTS, regulars=REGULARS, quests=None, npc_models=[
        "office", "student", "mom", "grandma", "tourist", "oldman"],
        sit_models=["office", "mom", "tourist", "student", "grandma"], tourists=True, pigeons=True),
    "city": dict(restaurants=CITY_RESTAURANTS, regulars=CITY_REGULARS, quests=CITY_QUESTS, npc_models=[
        "office", "office", "office", "student", "tourist", "mom"], sit_models=["office", "office", "student"],
        tourists=False, pigeons=True, rules=dict(tip_mult=1.4, rush_hours=[[12, 14], [18, 19]], rush_bonus=0.45)),
    "berezki": dict(restaurants=BEREZKI_RESTAURANTS, regulars=BEREZKI_REGULARS, quests=BEREZKI_QUESTS, npc_models=[
        "grandma", "grandma", "mom", "student", "oldman", "office"], sit_models=["grandma", "grandma", "oldman"],
        tourists=False, pigeons=False, rules=dict(night_bonus=0.6)),
    "gastro": dict(restaurants=GASTRO_RESTAURANTS, regulars=GASTRO_REGULARS, quests=GASTRO_QUESTS, npc_models=[
        "tourist", "student", "mom", "office", "grandma", "oldman"], sit_models=["tourist", "mom", "student", "office"],
        tourists=True, pigeons=True, rules=dict(tip_mult=1.15)),
}
CHAPTERS = ["Первая смена", "Свой самокат", "Деловой центр", "Ночные смены", "Ресторан мечты"]

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


def events_for(level):
    """EVENTS with 5 chapter weights (run 2 adds chapters 3-5) and per-district flavour."""
    out = []
    for e in EVENTS:
        e = dict(e)
        w = list(e["weight"])
        w = w + [w[-1]] * (5 - len(w))
        if level == "berezki" and e["id"] in ("broken_lift", "intercom", "no_answer"):
            w = [x + 2 for x in w]
        if level == "berezki" and e["id"] == "broken_lift":
            e["text"] = "Лифт застрял между этажами. Опять. Ноги, работаем!"
        if level == "city" and e["id"] in ("intercom",):
            w = [0 for _ in w]           # towers have a reception, not an intercom
        if level == "city" and e["id"] == "restaurant_delay":
            w = [x + 1 for x in w]       # the lunch rush
        e["weight"] = w
        out.append(e)
    return out


def main():
    cfg = LEVELS[LEVEL]
    layout = json.load(open(os.path.join(LV, "%s_layout.json" % LEVEL), encoding="utf-8"))
    inst = layout["instances"]
    marks = layout["markers"]
    rs = random.Random(9)

    def M(prefix):
        return [m for m in marks if m["name"].startswith(prefix)]

    # ---------------- address book (deliverable doors)
    doors = []
    plates = {}
    bignums = {}
    guards = {}
    for m in marks:
        if m["name"].startswith("MARK_plate_"):
            plates[(m["inst"], m["name"].split("_")[-1])] = m
        if m["name"] == "MARK_bignum":
            bignums[m["inst"]] = m
        if m["name"] == "MARK_guard":
            guards[m["inst"]] = m
    for m in marks:
        if m["name"].startswith("MARK_door_") and "inst" in m:
            h = inst[m["inst"]]
            if h["group"] != "house":
                continue
            k = m["name"].split("_")[-1]
            entr = int(k) + 1
            corpus = int(h.get("corpus", 0))
            num_txt = "%d" % h["number"] + (" к.%d" % corpus if corpus else "")
            kind = "tower" if h["asset"].startswith("tower") else ("panel" if h["asset"].startswith("panel") else "house")
            if kind == "tower":
                label = "%s, %s" % (h["street_name"], num_txt)
                plate_text = "%s\n%s" % (h["street_name"], num_txt)
            else:
                label = "%s, %s, под. %d" % (h["street_name"], num_txt, entr)
                plate_text = "%s\nпод. %d" % (num_txt, entr)
            d = dict(id="%s_%d_%d_%s" % (h["street"], h["number"], corpus, k) if corpus else
                     "%s_%d_%s" % (h["street"], h["number"], k),
                     street=h["street"], street_name=h["street_name"], number=h["number"], corpus=corpus,
                     entrance=entr, floors=h["floors"], lift=bool(h.get("lift", False)), kind=kind,
                     pos=m["pos"], yaw=m["yaw"], plate=plates.get((m["inst"], k), {}).get("pos"),
                     plate_text=plate_text, label=label, inst=m["inst"])
            if m["inst"] in guards:
                d["guard"] = True
            doors.append(d)
    for m in marks:
        if m["name"] == "MARK_park_spot":
            doors.append(dict(id="P_%d" % m["id"], street="P", street_name="Большой парк", number=0, corpus=0,
                              entrance=1, floors=0, lift=False, kind="park", pos=m["pos"], yaw=m["yaw"], plate=None,
                              plate_text="", label=m["label"], inst=-1))
    print("doors", len(doors))
    # big painted numbers on panel blocks and towers (one per building)
    big = []
    for i, m in bignums.items():
        h = inst[i]
        corpus = int(h.get("corpus", 0))
        big.append(dict(text="%d" % h["number"] + ("к%d" % corpus if corpus else ""), pos=m["pos"], yaw=m["yaw"],
                        size=2.4 if h["asset"].startswith("panel") else 1.6))

    # regulars get fixed addresses with enough floors
    used = set()
    regulars = []
    for r in cfg["regulars"]:
        cands = [d for d in doors if d["floors"] >= r["floors_min"] and d["id"] not in used and
                 (d["kind"] == "park") == bool(r.get("park", False))]
        if r["id"] == "viktor":
            cands = [d for d in doors if d.get("guard")]
        if r["id"] == "lost":
            cands = [d for d in doors if d["number"] == 7 and d["corpus"] == 4] or cands
        if r["id"] == "semyon":
            cands = [d for d in doors if d["number"] == 13] or cands
        if r["id"] == "gamers":
            cands = [d for d in doors if d["number"] == 9 and d["corpus"] == 2] or cands
        if not cands:
            cands = [d for d in doors if d["id"] not in used] or doors
        d = rs.choice(cands)
        used.add(d["id"])
        fl = 0 if d["kind"] == "park" else (r.get("floor") or rs.randint(max(2, min(d["floors"], r["floors_min"])),
                                                                         d["floors"]))
        regulars.append(dict(r, address=d["id"], floor=fl))

    restaurants = {}
    for k, v in cfg["restaurants"].items():
        pk = [m for m in marks if m["name"] == "MARK_pickup_" + k]
        ck = [m for m in marks if m["name"] == "MARK_cook_" + k]
        pr = [m for m in marks if m["name"] == "MARK_parking_" + k]
        if not pk:
            print("WARNING no pickup for", k)
            continue
        restaurants[k] = dict(v, pickup=pk[0]["pos"], pickup_yaw=pk[0]["yaw"], cook_pos=ck[0]["pos"],
                              cook_yaw=ck[0]["yaw"], parking=pr[0]["pos"] if pr else pk[0]["pos"],
                              prop=FOOD_PROPS[v["items"][0][0]])
    rules = json.loads(json.dumps(ORDER_RULES))
    rules.update(cfg.get("rules", {}))
    if LEVEL == "old_town":
        quests = dict(
            cake=dict(title="Торт для внука", giver="zina", restaurant="cake", item="cake", reward=40,
                      text="Бабушка Зина заказала торт на день рождения внука. Не тряси!"),
            office_lunch=dict(title="Обед на 20 персон", giver="office", restaurant="burger", item="lunch",
                              reward=60, needs="rack",
                              text="Офис «Кубик» заказывает огромный обед. Без багажника не увезти."),
            critic=dict(title="Ужин для критика", giver="critic", restaurant="dream", item="dream", reward=200,
                        text="Знаменитый ресторанный критик Аркадий Вилкин заказал первый ужин из твоего ресторана. "
                             "Довези горячим и целым — от его колонки зависит всё!"))
    else:
        quests = cfg["quests"]
    orders = dict(level=LEVEL, restaurants=restaurants, doors=doors, regulars=regulars, random_lines=RANDOM_LINES,
                  rules=rules, food_props=FOOD_PROPS, quests=quests, bignums=big)

    # ---------------- population
    pop = dict(npcs=[], cooks=[], mentor=None, police=[], rivals=[], thieves=[], traffic={}, fx=[], guards=[])
    for m in M("MARK_npc"):
        model = rs.choice(cfg["npc_models"])
        beh = rs.choice(["wander", "wander", "wander", "stand", "phone"])
        sched = rs.choice([[7, 23], [8, 20], [10, 22], [17, 23], [7, 12]])
        pop["npcs"].append(dict(id="npc%d" % m["id"], model=model, pos=m["pos"], yaw=m["yaw"], behaviour=beh,
                                radius=rs.uniform(10, 30), schedule=sched,
                                anim={"wander": "walk", "stand": "idle", "phone": "phone_call"}[beh]))
    for g in M("MARK_tourist_group"):
        for k in range(3):
            a = k * 2.1
            p = [g["pos"][0] + math.cos(a) * 1.6, g["pos"][1], g["pos"][2] + math.sin(a) * 1.6]
            if cfg["tourists"]:
                pop["npcs"].append(dict(id="tour%d_%d" % (g["id"], k), model="tourist", pos=p,
                                        yaw=rs.uniform(-180, 180), behaviour="photo", radius=3, schedule=[9, 19],
                                        anim="photo"))
            else:   # office workers chatting on the plaza
                pop["npcs"].append(dict(id="talk%d_%d" % (g["id"], k), model="office", pos=p,
                                        yaw=math.degrees(math.atan2(-math.cos(a), -math.sin(a))), behaviour="stand",
                                        radius=0, schedule=[8, 20], anim=["talk", "laugh", "sip_coffee"][k]))
    sits = [m for m in marks if m["name"] in ("MARK_sit_a", "MARK_sit_b")]
    for i, m in enumerate(sits):
        if rs.random() < 0.6:
            pop["npcs"].append(dict(id="cafe%d" % i, model=rs.choice(cfg["sit_models"]), pos=m["pos"], yaw=m["yaw"],
                                    behaviour="sit", radius=0, schedule=rs.choice([[9, 21], [12, 23], [8, 14]]),
                                    anim=rs.choice(["sit", "sip_coffee"] if LEVEL != "berezki" else ["sit", "talk"])))
    for k, r in restaurants.items():
        pop["cooks"].append(dict(id="cook_" + k, model="cook", pos=r["cook_pos"], yaw=r["cook_yaw"], anim="cook_idle",
                                 restaurant=k))
    mm = M("MARK_mentor")
    if LEVEL == "old_town" and mm:
        pop["mentor"] = dict(id="mentor", model="mentor", pos=mm[0]["pos"], yaw=mm[0]["yaw"], anim="sip_coffee",
                             name="Михалыч")
    for i, g in guards.items():
        pop["guards"].append(dict(id="guard%d" % i, model="guard", pos=g["pos"], yaw=g["yaw"], anim="idle", inst=i))
    pol = M("MARK_police")
    pp = M("MARK_police_patrol")
    if pol:
        pop["police"].append(dict(id="police0", model="police", pos=pol[0]["pos"], yaw=pol[0]["yaw"], behaviour="post",
                                  see_radius=14.0, anim="idle"))
    if pp:
        pop["police"].append(dict(id="police1", model="police", pos=pp[0]["pos"], yaw=0, behaviour="patrol",
                                  route=pp[0]["route"], see_radius=12.0, anim="walk", schedule=[9, 21]))
    for i, m in enumerate(M("MARK_courier_spawn")):
        pop["rivals"].append(dict(id="rival%d" % i, model=["courier_m", "courier_f", "courier_m"][i % 3],
                                  jacket=["#ef6a5b", "#9a6fd1", "#f2c230"][i % 3], vehicle="scooter", pos=m["pos"],
                                  company="Молния", speed=6.5 + i * 0.6))
    for m in M("MARK_thief"):
        pop["thieves"].append(dict(id="thief%d" % m["id"], model="thief", pos=m["pos"], vehicle="bicycle"))
    tram = layout["traffic"].get("tram")
    pop["traffic"] = dict(models=["car_hatch", "car_hatch", "car_taxi", "car_van", "bus"] if LEVEL != "city" else
                          ["car_taxi", "car_taxi", "car_hatch", "car_van", "bus"],
                          paints=["#ef6a5b", "#7ec3e8", "#8fd3b0", "#f6b98a", "#b9a3d8", "#f7f3ea", "#5d6670"],
                          count_by_hour=[[0, 3], [7, 9], [10, 7], [12, 9], [17, 10], [20, 6], [23, 3]],
                          speed=8.0, tram=dict(model="tram", period=tram["period"]) if tram else None)
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
    if cfg["pigeons"]:
        spots = ((-11, -12), (-25, -2), (5, -8), (-40, -20)) if LEVEL == "old_town" else ((-10, -2), (12, 6), (0, 70))
        for (x, z) in spots:
            pop["fx"].append(dict(kind="pigeons", pos=[x, 0, z], scale=1.0, count=6))
    grid = layout["grid"]
    cells = [(i, j) for j, row in enumerate(grid["rows"]) for i, c in enumerate(row) if c in ("c", "a", "p")]
    for _ in range(40):
        i, j = rs.choice(cells)
        x = grid["origin"][0] + (i + 0.5) * grid["cell"]
        z = grid["origin"][2] - (j + 0.5) * grid["cell"]
        pop["fx"].append(dict(kind="puddle", pos=[x, 0.03, z], scale=rs.uniform(1.0, 2.4), weather="rain"))
    pop["fx"].append(dict(kind="heat_haze", pos=[0, 0, 0], scale=1.0, weather="heat"))
    pop["player"] = dict(pos=M("MARK_player_start")[0]["pos"], yaw=M("MARK_player_start")[0]["yaw"],
                         vehicle="bicycle")

    events = dict(events=events_for(LEVEL), chapters=CHAPTERS, base_interval_s=[70, 120])
    for nm, data in (("population", pop), ("orders", orders), ("events", events)):
        with open(os.path.join(LV, "%s_%s.json" % (LEVEL, nm)), "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=1)
    print("npcs", len(pop["npcs"]), "fx", len(pop["fx"]), "regulars", [(r["id"], r["address"]) for r in regulars])

    if NO_RENDER or LEVEL != "old_town":
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
