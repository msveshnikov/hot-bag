# Горячая сумка — концепт-арт и задачи для Claude Code

Источник: ТЗ «Симулятор доставщика еды» (Claude Docs). Этот файл — его пересказ на язык пайплайна:
питч, рамки вертикального среза, стилевой блок, промпты для ChatGPT и порядок задач task1–task5.
Решения, принятые сверх ТЗ, — в `decisions.md`.

## 1. Питч

Мультяшный 3D-симулятор курьера доставки еды. Камера от третьего лица за спиной курьера и чуть сверху.
Герой приезжает в большой собирательный город (Прага + Москва + Нью-Йорк) с мечтой открыть свой ресторан
и копит на него, развозя заказы. Начинает новичком на старом велосипеде с рейтингом 4,0.
Минутный цикл: открыть приложение «Хоп!» → выбрать заказ (ближний и дешёвый или дальний и выгодный) →
доехать до ресторана → забрать → довезти вовремя и целым → оплата, чаевые, оценка → потратить на зарядку,
еду, ремонт и улучшения. Смена = игровой день со сменой времени суток и погоды. Главный вызов — успевать
и грамотно обходить проблемы реальных курьеров (разряженный самокат, дождь, жара, сломанный лифт,
домофон, неверный адрес, конкуренты, штрафы, угон). Тон — лёгкий юмор: неприятности смешные, не грустные.

Жанр: симулятор работы / аркада с элементами менеджмента. Платформы: Windows, Web, Android.

## 2. Вертикальный срез (прогон 1): Старый город

Один компактный район ~350 × 250 м (дистанции сжаты для игры):

- **Площадь с часовой башней** (вымышленная башня, не копия реального здания) — ориентир, туристы, кафе с террасами.
- **Ресторанная улица** — 5 точек выдачи: пиццерия, бургерная, суши-бар, кофейня, кондитерская (торты).
- **Брусчатые переулки** — узкие, кривые; самокат на брусчатке медленнее и скользит.
- **Жилые дома 4–6 этажей без лифтов** — номера домов и подъездов, домофоны, разноцветные фасады.
- **Главная асфальтовая улица** с трамвайными путями (декор), светофорами и машинами.
- **Набережная с парком** — велодорожка, лестница-сокращение (только пешком/на велосипеде), скамейки.
- **База курьеров** — уличное кафе, где сидит наставник; зарядная станция, велопарковка, ларёк с перекусом.
- **Мост-обрубок и перекрытые улицы** по краям — выходы в районы прогона 2 (закрыты ограждениями «ремонт»).
- Пост полиции, стройка с перекрытием (событие «перекрытие»).

В срезе: велосипед и самокат, приложение с заказами, таймер, состояние и температура еды, рейтинг, деньги,
смена дня (утро → полдень/жара → вечер → ночь) и дождь, конкуренты, трафик и светофоры, полиция и штрафы,
угон, голод и усталость, лестница без лифта, домофон/неверный адрес/клиент не отвечает, капризный клиент.
Сюжет: глава 1 «Первая смена» (обучение у наставника) и глава 2 «Свой самокат» (накопить и купить),
плюс два побочных квеста (бабушкин торт — нельзя трясти; обед для офиса — большой заказ, нужен багажник).

## 3. Стилевой блок

Два варианта, общий первый абзац. Для сцен — `SCENE`, для листов моделей — `SHEET`.

```
STYLE (общий):
Stylized cartoon 3D game art like modern cozy indie games: soft rounded chunky shapes, slightly exaggerated
"puffy" and a bit crooked proportions, simple flat colors with soft gradients, no fine detail, no complex
textures, no photorealism, no anime. Collective European-American big city: old town like Prague, wide
avenues like Moscow, skyline like New York. Consistent palette: warm terracotta and cream facades, sunny
yellow, mint green, sky blue, coral red accents, dark asphalt grey, courier turquoise. Bright cheerful
daylight, soft shadows, readable silhouettes, light humorous mood.

SCENE: wide cinematic 16:9, three-quarter view from above like a third-person chase camera, no text,
no logos, no UI.

SHEET: game-ready model reference, the whole object in frame, neutral light grey background, soft studio
lighting, no text, no logos.
```

Добавка для листов персонажей и транспорта: `turnaround sheet: front view, side view and back view,
orthographic-like, A-pose` (для транспорта — `side, front, back and three-quarter view`).

Последовательность: самая удачная первая картинка (Старый город днём) прикладывается ко всем
следующим запросам с фразой `Keep exactly the same art style as the reference image.`

## 4. Настроения (mood add-ons)

- **morning**: `Early morning, fresh soft light, long gentle shadows, wet cobblestones drying, few people.`
- **noon_heat**: `Hot summer noon, strong bright sun, short shadows, heat haze, sun umbrellas, people in shorts.`
- **evening**: `Golden hour evening, warm orange light, long shadows, cafe lights turning on, busy streets.`
- **night**: `Night, deep blue sky, warm pools of light from street lamps, lit windows and neon cafe signs, cozy not scary.`
- **rain**: `Rainy day, grey-blue sky, puddles with reflections, umbrellas, glossy wet cobblestones, light drizzle streaks.`
- (прогон 2) **snow**: `Snowy winter day, soft snow on roofs and cars, slush on roads, scarves and hats.`

## 5. Промпты

Каждый промпт = `STYLE` + `SCENE` или `SHEET` + текст ниже. Пишем в ChatGPT `Generate an image:` в начале.

### 5.1 Локации среза (concept/locations/)

**old_town_day** — главный арт, якорь стиля:
```
Old Town district of a cartoon big city: a cobblestone square with a chunky clock tower, colorful puffy
four-to-six storey houses with tiled roofs and numbered entrance doors with intercoms, cafe terraces with
umbrellas, a side street lined with small restaurants (pizza place, burger bar, sushi bar, coffee shop, cake
shop) with pickup counters, a delivery courier in a turquoise jacket with a big square insulated backpack
riding an old bicycle in the foreground, tourists with cameras, pigeons, an electric scooter charging station,
a tram line on the main asphalt street with a traffic light, a river embankment with trees visible at the edge.
```
+ `night`, `rain`, `noon_heat`, `evening` → `old_town_night.png`, `old_town_rain.png`, `old_town_noon.png`,
`old_town_evening.png` (по приоритету: day, night, rain; остальное — если хватит лимита).

**restaurant_street_day**:
```
Narrow restaurant street in a cartoon old town: five tiny restaurants side by side with big friendly shop
signs shaped like food (pizza slice, burger, sushi roll, coffee cup, cake) but no letters, pickup windows with
paper bags waiting, a cook handing a bag to a courier, scooters and bikes parked on a bike rack, string lights
across the street, menu boards, crates and plants.
```

**embankment_park_day**:
```
River embankment with a narrow park: a bicycle path between round cartoon trees, benches, a wide stone
staircase going down to the water as a shortcut, lamp posts, a low stone parapet, a small stone bridge stub
blocked by a "road works" barrier, joggers and a courier on a bicycle, colorful old houses across the river.
```

**courier_base_day**:
```
Courier base corner: a small street cafe where couriers rest, an old veteran courier sitting at a table with
coffee, a row of electric scooter chargers, a bike rack, a snack kiosk, a garage door of a small repair shop
with tools and tires, delivery backpacks on chairs.
```

### 5.2 Пустые локации (concept/empty/)

Те же промпты `old_town_day`, `restaurant_street_day`, `embankment_park_day` +
`Empty scene: no people, no animals, no vehicles, no loose items, only architecture, streets and fixed props.`
→ `old_town_empty.png`, `restaurant_street_empty.png`, `embankment_empty.png`.

### 5.3 Карта мира (concept/locations/world_map.png)

```
Top-down stylized overview map of a compact cartoon city for a delivery game: Old Town with a clock tower
square in the center-left by a winding river, a restaurant street next to it, a park and embankment along the
river, a business district with glass skyscrapers in the north, a residential district with identical panel
apartment blocks in the east, a big restaurant quarter in the south, connected by a few main avenues and
bridges, all close together. Clear readable layout like a game level map, no text, no labels, no frame.
```
Игровая карта — не эта картинка: её перерисовывают с рендера реального уровня (05, align_to_layout).

### 5.4 Персонажи (concept/characters/)

`SHEET` + turnaround для каждого:

- **courier_hero**: `Young food delivery courier, big head, friendly expressive face, bright turquoise jacket
  with reflective stripes, cap, jeans, sneakers, a large square insulated delivery backpack in turquoise with
  a cartoon hot-steam icon, phone holder on the wrist. Male and female variant side by side.`
- **courier_customization**: `Customization sheet for the same courier: 4 hairstyles, 3 helmets (city bike
  helmet, scooter half-helmet, funny retro helmet), jacket colors, delivery backpack upgrades (waterproof
  cover, drink holder, cooling pack pocket, stickers), arranged on a grid.`
- **mentor**: `Old veteran courier, about 60, round belly, grey mustache, sunglasses on the forehead, faded
  turquoise jacket covered with patches and pins, fingerless gloves, a battered old delivery backpack, warm
  sly grin.`
- **residents**: `City residents for a delivery game: grumpy old man in a bathrobe and slippers, office worker
  with a laptop and a tie, student in a hoodie, mom with a baby, sweet grandmother with knitting, tourist with a
  camera and a map, all full body, front view, A-pose.`
- **cook_and_police**: `A restaurant cook in a white uniform holding a paper food bag, and a chubby city
  police officer on foot with a whistle, full body, front and side view, A-pose.`
- **rival_couriers**: `Three rival food couriers of a competing company in coral red, purple and yellow
  jackets on electric scooters, cheeky confident poses, full body.`

### 5.5 Транспорт (concept/characters/)

- **bicycle_old**: `Old cheap city bicycle with a front basket, a rusty bell, a bent mudguard and a squeaky
  saddle, turnaround sheet side, front, back and three-quarter view.`
- **scooter**: `Electric kick scooter, chunky cartoon proportions, battery indicator on the handlebar, small
  headlight, plus an upgraded version with wide tires, mudguards, a rear rack for a delivery bag and a bright
  headlight, side and three-quarter view.`
- **traffic**: `Cartoon city traffic: tiny round hatchback, a taxi, a delivery van, a city bus and a tram car,
  chunky toy-like proportions, side and three-quarter view, arranged on a grid.`
- (прогон 2) `Small cute electric moped and a tiny electric delivery car, side and three-quarter view.`

### 5.6 Пропсы

- **food_props**: `Set of food delivery props: pizza box, paper bag, drink cup holder, cake box, sushi box,
  ice cream tub, big office lunch crate, arranged on a grid.`
- **street_props**: `Set of street props: scooter charging station, traffic light, road barrier with a stripe,
  construction cone, bench, trash bin, bike rack, lamp post, intercom panel with buttons, house number plate
  without numbers, mailbox, flower pots, cafe table with umbrella, arranged on a grid.`

### 5.7 Интерфейс (concept/ui/)

Стиль UI: `game UI design, bright flat cartoon style, rounded thick-outlined panels in turquoise and cream,
chunky friendly headings, big readable icons, like a cheerful mobile game.`

- **title_screen**: `Title screen of a cartoon delivery game: the courier on a bicycle racing through the old
  town at sunset with steam coming from the backpack, empty space for the game title at the top and four
  rounded menu buttons on the left, no text.` (кнопки и название рисуем кодом)
- **phone_app**: `In-game smartphone courier app held in a cartoon hand: list of delivery order cards with
  restaurant icon, distance, price, timer and food type icon, star rating at the top, phone battery and
  vehicle battery indicators, accept button, flat design, no readable text.`
- **hud**: `Third-person gameplay HUD for a delivery game: order timer, navigation arrow, food condition
  meter with a pizza icon, food temperature, vehicle battery, courier stamina and hunger icons, money and star
  rating corner, minimap circle, cartoon style, no readable text.`
- **garage_shop**: `Upgrade shop screen for a delivery game: a scooter on a turntable in the center with
  upgrade cards around it (battery, motor, tires, brakes, rear rack, lock, headlight, mudguards), coin prices,
  cartoon style, no readable text.`
- **shift_summary**: `End of shift summary screen: earnings, expenses, tips, star rating change, delivered
  orders list, a tired but happy courier sitting on a bench at night, cartoon style, no readable text.`
- (если хватит лимита) **pause_settings**, **account_blocked** (смешной «курьер в бане»).

## 6. Очередь заказа арта (бесплатный ChatGPT ≈ 3 картинки/сутки)

| Пачка | Картинки | Зачем |
|---|---|---|
| 1 | old_town_day, courier_hero, bicycle_old + scooter (одним листом, если получится) | якорь стиля, герой, транспорт → можно стартовать task1 и task2 |
| 2 | old_town_empty, restaurant_street_day, street_props | task1 и task3 |
| 3 | old_town_night, old_town_rain, food_props | настроения, пропсы |
| 4 | mentor, residents, cook_and_police | task2/task4 |
| 5 | phone_app, hud, title_screen | task5 |
| 6 | embankment_park_day, world_map, traffic | task3, карта |
| 7 | rival_couriers, garage_shop, shift_summary | task4/task5 |
| 8 | courier_customization, courier_base_day, embankment_empty | доводка |

Если чего-то не хватает к старту задачи — задача берёт ближайший арт и пишет решение в decisions.md.

## 7. Задачи

`task1.md` → `task5.md` в корне, запускаются строго по порядку, каждая в новой сессии:
1. окружение и пропсы Старого города (Blender);
2. курьер, наставник, жители, повар, полицейский, конкуренты; велосипед, самокат, городской транспорт;
3. пустой уровень Старого города + граф дорог/тротуаров/велодорожек + пресеты освещения;
4. население: жители, туристы, трафик, конкуренты, полиция, точки заказов, эффекты;
5. игра в Godot: управление, приложение, заказы, проблемы курьера, экономика, сюжет глав 1–2, UI, звук,
   сохранение, autotest, сборки и деплой.

## 8. Прогон 2 (после ревью среза)

Деловой центр (охрана, пропуска, обеденный пик, высокие чаевые, сложная парковка), спальный район
(одинаковые корпуса, запутанные номера, ночные заказы, домофоны), большой ресторанный квартал, большой парк;
снег; электровелосипед, мопед, электромобиль; главы 3–5 (деловой центр, ночные смены, финальный большой заказ
и открытие своего ресторана); сшивка районов в один город с картой.
