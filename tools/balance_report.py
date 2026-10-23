#!/usr/bin/env python3
"""
balance_report.py — валидирует data/*.json и генерирует docs/03_balance.md.
  * проверяет, что все ссылки (здания, технологии, модели, иконки) существуют;
  * считает DPS, стоимость, «эффективность» юнитов;
  * раскладывает волны по ночам для 1–4 игроков;
  * прогоняет упрощённую экономику дня.
Запуск: python3 tools/balance_report.py   (код выхода 1 при ошибках валидации)
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
D = {p.stem: json.loads(p.read_text()) for p in (ROOT / "data").glob("*.json")}
ASSETS = ROOT / "assets"
errors, warns = [], []


def items(d):
    return {k: v for k, v in d.items() if not k.startswith("_") and isinstance(v, dict)}


units = {k: v for k, v in items(D["units"]).items() if k != "abilities"}
abil = D["units"]["abilities"]
zmb = {k: v for k, v in items(D["zombies"]).items() if k != "ai"}
blds = {k: v for k, v in items(D["buildings"]).items() if k != "map_poi"}
tech = items(D["tech"])
rules = D["rules"]
combat = D["combat"]

# ------------------------------------------------------------------ валидация
for k, u in units.items():
    req = u.get("requires", {})
    if req.get("building") and req["building"] not in blds:
        errors.append(f"units.{k}: нет здания {req['building']}")
    if req.get("also_building") and req["also_building"] not in blds:
        errors.append(f"units.{k}: нет здания {req['also_building']}")
    if req.get("tech") and req["tech"] not in tech:
        errors.append(f"units.{k}: нет технологии {req['tech']}")
    for a in u.get("abilities", []):
        if a not in abil:
            errors.append(f"units.{k}: нет способности {a}")
    if u["attack"]["damage_type"] not in combat["damage_types"]:
        errors.append(f"units.{k}: неизвестный тип урона")
    for f in ("model", "icon"):
        if not (ASSETS / u[f]).exists():
            errors.append(f"units.{k}.{f}: файл не найден {u[f]}")
for k, z in zmb.items():
    for f in ("model", "icon"):
        if f in z and not (ASSETS / z[f]).exists():
            errors.append(f"zombies.{k}.{f}: файл не найден {z[f]}")
for k, b in blds.items():
    if b.get("requires_tech") and b["requires_tech"] not in tech:
        errors.append(f"buildings.{k}: нет технологии {b['requires_tech']}")
    for t in b.get("trains", []):
        if t not in units:
            errors.append(f"buildings.{k}: обучает неизвестный юнит {t}")
    for f in ("model", "icon"):
        if f in b and not (ASSETS / b[f]).exists():
            errors.append(f"buildings.{k}.{f}: файл не найден {b[f]}")
for k, t in tech.items():
    for r in t["requires"]:
        if r not in tech:
            errors.append(f"tech.{k}: требует неизвестную {r}")
for k, c in items(D["civilians"]).items():
    for f in ("model",):
        if f in c and not (ASSETS / c[f]).exists():
            errors.append(f"civilians.{k}.model: {c[f]}")
    for m in c.get("models", []):
        if not (ASSETS / m).exists():
            errors.append(f"civilians.{k}.models: {m}")

# ------------------------------------------------------------------ расчёты
def dps(a):
    return a["damage"] * a["rof"] if a else 0


def cost_str(c):
    return " / ".join(str(c.get(r, 0)) for r in ("food", "wood", "iron"))


def wave(n, players):
    W = D["waves"]["formulas"]; m = rules["difficulty_scaling_by_players"][str(players)]
    out = {}
    out["walker"] = round((W["walker"]["a"] + W["walker"]["b"] * n ** W["walker"]["p"]) * m)
    out["runner"] = round(W["runner"]["b"] * (n - 1) ** W["runner"]["p"] * m) if n >= 2 else 0
    out["screamer"] = math.floor(n / 3 * m) if n >= 3 else 0
    out["brute"] = math.floor((n - 2) / 2 * m) if n >= 4 else 0
    out["spitter"] = math.floor((n - 3) / 2 * m) if n >= 5 else 0
    out["giant"] = 1 if n == 12 else 0
    out["hp_total"] = sum(out[k] * zmb[k]["hp"] for k in ("walker", "runner", "screamer", "brute", "spitter", "giant"))
    return out


L = []
w = L.append
w("# Баланс: КАРАНТИН: МОСКВА\n")
w("> **Сгенерировано** `tools/balance_report.py` из `data/*.json`. Не править руками — правьте JSON и перезапускайте.\n")
w(f"> Валидация: **{len(errors)} ошибок**, {len(warns)} предупреждений.\n")
if errors:
    w("\n".join(f"- ❌ {e}" for e in errors) + "\n")

w("## 1. Формулы\n")
w("- `урон = base_damage × combat.damage_types[тип][броня_цели]`")
w("- `DPS = damage × rof` (rof — выстрелов в секунду)")
w("- Время стройки: `build_s / N^0.8`, N — число строителей")
w("- Заражение солдата при попадании: `p = soldier_infect_chance_base × (zombie.infect_chance / 0.15) × (1 / infect_resist)`; мирный — всегда 1.0")
w("- Волна ночи n: `count = round(f(n) × players_mult)`, см. §5")
w("- Еда на рассвете: `(взрослые×1 + дети×0.5 + солдаты×1.5) × (0.7 если кухня укомплектована)`\n")

w("## 2. Урон по броне\n")
ac = combat["armor_classes"]
w("| Тип урона | " + " | ".join(ac) + " |"); w("|---|" + "---|" * len(ac))
for t, row in combat["damage_types"].items():
    w(f"| {t} | " + " | ".join(f"{row[a]:g}" for a in ac) + " |")
w("")

w("## 3. Военные юниты\n")
w("| Юнит | Рекр. | Еда/Дер/Жел | Время | HP | Броня | DPS (осн.) | Дальн. | Скор. | Шум | DPS / 100 ресурсов |")
w("|---|---|---|---|---|---|---|---|---|---|---|")
for k, u in units.items():
    d = dps(u["attack"]) * (1 + u["attack"].get("aoe", 0) * 0.5)
    d2 = dps(u.get("attack_secondary"))
    total_cost = sum(u["cost"].values()) + u["recruits"] * 30  # рекрут оцениваем в 30 ресурсов
    eff = (d + d2) / total_cost * 100
    w(f"| {u['name_ru']} | {u['recruits']} | {cost_str(u['cost'])} | {u['train_s']} с | {u['hp']} | {u['armor']} | "
      f"{dps(u['attack']):g}{' +'+format(d2,'g') if d2 else ''}{' AoE' if u['attack'].get('aoe') else ''} | {u['attack']['range']} | {u['speed']} | {u['noise_attack']} | {eff:.0f} |")
w("\n*Рекрут в эффективности оценён как 30 ресурсов. AoE учтён коэффициентом ×(1 + 0.5·радиус).*\n")

w("### Способности\n")
w("| Способность | КД | Эффект |"); w("|---|---|---|")
for k, a in abil.items():
    eff = {kk: vv for kk, vv in a.items() if kk not in ("name_ru", "cooldown_s")}
    w(f"| {a['name_ru']} (`{k}`) | {a['cooldown_s']} с | {', '.join(f'{kk}={vv}' for kk, vv in eff.items())} |")
w("")

w("## 4. Заражённые\n")
w("| Тип | С ночи | HP | Броня | Скор. | DPS | Дальн. | Заражение солдата | Время убийства штурмовиком |")
w("|---|---|---|---|---|---|---|---|---|")
a_dps = dps(units["assault"]["attack"])
for k, z in zmb.items():
    if z.get("static"):
        w(f"| {z['name_ru']} | — | {z['hp']} | {z['armor']} | — | спавн {z['spawn']['type']} / {z['spawn']['interval_s']} с | — | — | "
          f"{z['hp'] / (a_dps * combat['damage_types']['bullet'][z['armor']]):.0f} с |")
        continue
    at = z.get("attack")
    mult = combat["damage_types"]["bullet"][z["armor"]]
    w(f"| {z['name_ru']} | {z['first_night']} | {z['hp']} | {z['armor']} | {z['speed']} | {dps(at):g} | {at['range'] if at else '—'} | "
      f"{z['infect_chance']:.0%} | {z['hp'] / (a_dps * mult):.1f} с |")
w("")

w("## 5. Ночные волны\n")
for players in (1, 2, 4):
    w(f"### {players} игрок(а) · множитель ×{rules['difficulty_scaling_by_players'][str(players)]}\n")
    w("| Ночь | Ходоки | Бегуны | Крикуны | Громилы | Плевуны | Великан | Σ HP |"); w("|---|---|---|---|---|---|---|---|")
    for n in range(1, rules["day_cycle"]["days_total"] + 1):
        o = wave(n, players)
        w(f"| {n} | {o['walker']} | {o['runner']} | {o['screamer']} | {o['brute']} | {o['spitter']} | {o['giant'] or ''} | {o['hp_total']:,} |".replace(",", " "))
    w("")
w("**Проверка на здравый смысл (4 игрока, ночь 12):** суммарный HP волны против DPS армии ~30 пехотинцев + 4 техники "
  "(≈ 30×25 + 4×100 ≈ 1 150 DPS) → ~" + f"{wave(12, 4)['hp_total'] / 1150:.0f}" +
  " с чистого огня, при ночи 150 с и спавне пачками — напряжённо, но проходимо со стенами и AoE.\n")

w("## 6. Постройки\n")
w("| Здание | Цена (дер/жел) | Время | HP | Энергия | Работники | Выход / работник / день | Требует |")
w("|---|---|---|---|---|---|---|---|")
for k, b in blds.items():
    c = b.get("cost", {})
    pw = b.get("power", None)
    pws = f"{pw:+d}" if isinstance(pw, int) else (f"день {b.get('power_day', 0):+d} / ночь {b.get('power_night', 0):+d}" if "power_day" in b or "power_night" in b else "0")
    y = b.get("yield_per_worker_per_day", {})
    w(f"| {b['name_ru']} | {c.get('wood', 0)} / {c.get('iron', 0)} | {b.get('build_s', 0)} с | {b['hp']} | {pws} | {b.get('workers', '—')} | "
      f"{', '.join(f'{v} {r}' for r, v in y.items()) or '—'} | {b.get('requires_tech') or '—'} |")
w("")

w("## 7. Технологии\n")
w("| Тир | Технология | Цена | Время | Требует | Эффект |"); w("|---|---|---|---|---|---|")
for k, t in sorted(tech.items(), key=lambda kv: kv[1]["tier"]):
    w(f"| {t['tier']} | {t['name_ru']} | {', '.join(f'{v} {r}' for r, v in t['cost'].items())} | {t['research_s']} с | {', '.join(tech[r]['name_ru'] for r in t['requires']) or '—'} | {t['effect']} |")
w("")

w("## 8. Экономика: эталонный день 4 (2 игрока)\n")
pop_civ, pop_child, pop_sold = 22, 2, 12
c = rules["consumption_per_day"]
eat = (pop_civ * c["civilian_adult"] + pop_child * c["child"] + pop_sold * c["soldier"])
w(f"Население: {pop_civ} взрослых мирных, {pop_child} ребёнка, {pop_sold} солдат.\n")
w(f"- Потребление еды: {eat:.1f}/день, с кухней ×0.7 → **{eat * c['kitchen_mult']:.1f}**")
gh = blds["greenhouse"]["yield_per_worker_per_day"]["food"] * 3
w(f"- 2 теплицы × 3 работника = **{gh * 2}** еды/день → дефицит {eat * c['kitchen_mult'] - gh * 2:.1f}, закрывается 1 рейдом в Продуктовый (40–80)")
wd = blds["sawmill"]["yield_per_worker_per_day"]["wood"] * 4
w(f"- Лесопилка 4 работника: **{wd}** дерева/день; генератор жжёт {blds['generator']['upkeep_per_day']['wood']}")
ir = blds["scrapyard"]["yield_per_worker_per_day"]["iron"] * 3
w(f"- Металлоразборка 3 работника: **{ir}** железа/день → танк (120) ≈ {120 / ir:.1f} дня, Вертолётная площадка (150) ≈ {150 / ir:.1f} дня")
workers = 6 + 4 + 3 + 2 + 2 + 2
w(f"- Занято работой: {workers} из {pop_civ} → свободно {pop_civ - workers} на стройку и рекрутинг")
pw_need = 1 * 3 + 1 + 2 * 2 + 2 + 2 + 3 + 1 + 4
w(f"- Энергия: потребление ≈ {pw_need} (3 жилых, кухня, 2 теплицы, медпункт, казарма, мастерская, КПП, 4 прожектора ночью) "
  f"vs Штаб 5 + 2 генератора 12 = 17 → ночью на грани, мотивирует подстанцию (+20) в день 5\n")

(ROOT / "docs" / "03_balance.md").write_text("\n".join(L))
print(f"docs/03_balance.md written · errors={len(errors)} warns={len(warns)}")
for e in errors:
    print("ERR", e)
sys.exit(1 if errors else 0)
