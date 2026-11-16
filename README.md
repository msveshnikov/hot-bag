# Горячая сумка (Hot Bag)

Мультяшный 3D-симулятор курьера доставки еды. Godot 4.7, все ассеты генерируются Python-скриптами в Blender 5.2
по пайплайну [claude-game-pipeline](https://github.com/msveshnikov/claude-game-pipeline).

- Дизайн-документ и промпты: [Горячая сумка — концепт-арт и задачи для Claude Code.md](Горячая%20сумка%20—%20концепт-арт%20и%20задачи%20для%20Claude%20Code.md)
- Решения и конвенции: [decisions.md](decisions.md)
- Задачи вертикального среза (Старый город): [task1](task1.md) → [task2](task2.md) → [task3](task3.md) →
  [task4](task4.md) → [task5](task5.md), по одной в новой сессии Claude Code.

## Инструменты

- Blender 5.2: `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`
- Godot 4.7.2: `C:\Users\msves\OneDrive\Рабочий стол\Godot_v4.7.2-stable_win64.exe`

## Структура

```
concept/{locations,characters,empty,ui}   концепт-арт из ChatGPT (.gdignore)
concept_art/                              доп. референсы (.gdignore)
blender/scripts/                          генераторы (.gdignore)
assets/{architecture,props,characters,vehicles,textures,levels,ui,audio}
scripts/, scenes/                         игра
renders/                                  превью и скриншоты (.gdignore)
build/                                    сборки (.gdignore, не в git)
```

## Rebuild

Заполняется задачами task1–task5.
