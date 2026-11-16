# Персонажи и транспорт (Task 2)

Общий скелет из 20 костей (root, hips, spine, chest, neck, head, clavicle/upper_arm/forearm/hand, thigh/shin/foot ×2), рост ≈1,75 м, крупная голова.
Скиннинг «сегментный»: каждая часть тела на 100% у одной кости, суставы закрыты сферами — без артефактов весов.
40 процедурных анимаций (24 fps, каждая — отдельная NLA-дорожка → отдельная анимация в glTF).

| Модель | Детали |
|---|---|
| courier_m / courier_f | куртка (материал `jacket` перекрашивается в игре), `ACC_hair_short/ponytail/curly/bun`, `ACC_cap`, `ACC_helmet_bike/half/retro`, `ACC_bag`, `HELD_box`, `HELD_phone` |
| mentor | Михалыч: живот, усы, очки на лбу, выцветшая куртка, старая сумка |
| oldman, office, student, mom, grandma, tourist | жители и постоянные клиенты |
| cook, police, thief | повар, полицейский, вор (конкуренты — курьеры с другим цветом куртки) |
| guard (прогон 2) | охранник башен «Сити»: тёмная форма, кепка, очки, наушник |

Прогон 2: courier_m / courier_f собираются `lib_hero.courier_human` (форма ближе к концепт-листу), имена частей те же.

Скорости без скольжения ног (анимация при скорости 1.0): walk 0.993 м/с, run 2.274 м/с, tired_walk 0.6 м/с, climb_stairs 1.632 м/с, sneak 0.696 м/с, carry 0.993 м/с. Игра масштабирует скорость проигрывания.

Транспорт (`assets/vehicles/`, узлы с осями): bicycle (`WHEEL_front/rear`, `STEER`, `CRANK`, `LIGHT_head`), scooter (+ `EMIT_battery`, `ACC_rack`, `ACC_wide_tires`, `ACC_headlight`), car_hatch, car_taxi, car_van, bus, tram.
Точки посадки согласованы с анимациями `ride_bike` / `ride_scooter` (BIKE/SCOOT в `build_characters.py`).
