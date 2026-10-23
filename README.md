# КАРАНТИН: МОСКВА — пакет для разработки v0.1

Кооперативная RTS-выживалка (1–4 игрока): современная армия против зомби в Москве. Вид сверху 2.5D, low-poly, Godot 4.6.

**Начни с `00_onepager.png`** — концепт на одном экране.

## Состав

```
00_onepager.html / .png      — визуальный концепт
CLAUDE.md                    — правила для ИИ-агента (Claude Code / Cursor), положить в корень проекта
docs/
  01_GDD.md                  — геймдизайн: столпы, цикл, люди, юниты, зомби, заражение, шум, постройки, победа
  02_tech_spec.md            — стек, архитектура sim/view, сеть, контракты команд и снапшотов, бюджеты, ADR
  03_balance.md              — таблицы баланса и волн (СГЕНЕРИРОВАН из data/)
  04_map_moscow.md           — Хамовники/Лужники, зоны, пайплайн OSM → чанки
  05_art_bible.md            — стиль, палитра, масштаб, узлы, бюджеты, анимации, VFX, UI-стиль
  06_asset_list.md           — все ассеты: что есть, что нужно в финале, звук, экраны (СГЕНЕРИРОВАН)
  07_ui_hud.md               — HUD, экраны, управление
  08_roadmap_tasks.md        — вехи M0–M6 и атомарные задачи
data/                        — ЕДИНСТВЕННЫЙ источник цифр: rules, units, zombies, civilians, buildings, tech, doctrines, waves, combat, map_luzhniki
assets/
  models/<категория>/*.glb   — 75 low-poly плейсхолдеров + manifest.json
  textures/palette.png       — общая палитра (один материал на весь мир)
  icons/svg|png/64|png/128   — 67 иконок + svg/glyph без бейджа
previews/                    — листы моделей, иконок, палитры + превью каждой модели
tools/
  asset_gen/                 — генератор моделей, иконок и превью (python3 models.py / icons.py / previews.py)
  osm_city/                  — сборка города из OpenStreetMap (build_city.py + overpass_luzhniki.ql + тестовый сэмпл)
  balance_report.py          — валидация data/ + генерация docs/03_balance.md
  asset_list.py              — генерация docs/06_asset_list.md
  onepager.py                — сборка one-pager
```

## Быстрый старт

```bash
pip install trimesh shapely mapbox_earcut numpy pillow cairosvg
python3 tools/balance_report.py               # проверить конфиги
# собрать реальные Лужники (нужен интернет):
cd tools/osm_city
curl -s -X POST https://overpass-api.de/api/interpreter --data-urlencode data@overpass_luzhniki.ql -o luzhniki.osm.json
python3 build_city.py --osm luzhniki.osm.json --map ../../data/map_luzhniki.json --out ../../assets/city/luzhniki
```

Дальше: создать проект Godot 4.6, положить `data/` и `assets/` внутрь, `CLAUDE.md` в корень, и отдать агенту задачу **M0-1** из `docs/08_roadmap_tasks.md`.

## Важно знать
- Все модели — **плейсхолдеры** правильного масштаба, силуэта и с правильными узлами под анимацию. Финальные модели заменяют их 1:1 по имени файла и узлов.
- Город в пакете — только тестовый квартал; реальная карта собирается скриптом из OSM (из песочницы, где делался пакет, OSM недоступен — скрипт проверен на синтетических данных).
- Рабочее название «Карантин: Москва» — заглушка. Координаты POI в `map_luzhniki.json` приблизительные.
