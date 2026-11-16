# Список ассетов окружения (Task 1)

Все ассеты — Python-генераторы в `blender/scripts/build_architecture.py` и `build_props.py`, glTF в `assets/architecture/`, `assets/props/`, превью в `renders/previews/`.

## Архитектура
| Ассет | Тип | Габариты |
|---|---|---|
| `bridge_stub` | bridge | 10.0×26.0 м, h 1 |
| `clock_tower` | landmark | 8.6×8.6 м, h 40 |
| `courier_cafe` | shop | 7.0×5.0 м, h 3.6 |
| `garage` | shop | 8.0×8.0 м, h 4.8 |
| `house_a` | house | 8×10 м, h 12.6 |
| `house_b` | house | 7×10 м, h 15.6 |
| `house_c` | house | 9×10 м, h 12.6 |
| `house_d` | house | 8×11 м, h 18.6 |
| `house_e` | house | 10×10 м, h 12.6 |
| `house_f` | house | 7×9 м, h 15.6 |
| `house_g` | house | 8×10 м, h 12.6 |
| `house_h` | house | 9×11 м, h 15.6 |
| `house_i` | house | 7×10 м, h 12.6 |
| `house_j` | house | 8×10 м, h 18.6 |
| `house_k` | house | 10×11 м, h 15.6 |
| `house_l` | house | 8×10 м, h 12.6 |
| `parapet` | wall | 4×0.8 м, h 1.3 |
| `police_booth` | booth | 2.4×2.4 м, h 3.4 |
| `quay_wall` | wall | 8.0×1 м, h 3.0 |
| `restaurant_burger` | restaurant | 6.6×7.0 м, h 4.4 |
| `restaurant_cake` | restaurant | 6.6×7.0 м, h 4.4 |
| `restaurant_coffee` | restaurant | 6.6×7.0 м, h 4.4 |
| `restaurant_pizza` | restaurant | 6.6×7.0 м, h 4.4 |
| `restaurant_sushi` | restaurant | 6.6×7.0 м, h 4.4 |
| `snack_kiosk` | shop | 3×2.4 м, h 3.5 |
| `stairs_wide` | stairs | 5.0×4.800000000000001 м, h 3.0 |

Интерактивное в домах: `INT_door_<дом>_<n>` (pivot на петле), `INT_intercom_*`, маркеры `MARK_door_<n>` (точка доставки), `MARK_plate_<n>` (табличка с номером, в игре — Label3D).
Рестораны: `INT_counter_<еда>`, `MARK_pickup_*`, `MARK_cook_*`, `MARK_parking_*`. База: `MARK_mentor`, `MARK_shop_cafe`, `MARK_shop_garage`, `MARK_shop_kiosk`.

## Пропсы
tree_round, tree_round_b, bush, bench (`INT_bench`), lamp_post (`LIGHT_*`), traffic_light (`TLAMP_red/yellow/green`), charger_station (`INT_charger`, `MARK_charger`), bike_rack, trash_bin, flower_pot, cafe_set, cafe_set_turq, barrier_works, traffic_cone, bollard, fountain, mailbox, crates, menu_board, string_lights, tram_stop.

## Еда (assets/props/food/)
pizza_box, paper_bag, cup_holder, cake_box, sushi_box, ice_cream_tub, lunch_crate.

## Текстуры (numpy, `blender/scripts/make_textures.py`)
cobble, asphalt, sidewalk, roof_tiles, plaster, brick, wood, grass, park_path, water, stone.
