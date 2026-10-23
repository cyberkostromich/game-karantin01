"""
icons.py — набор UI-иконок в едином стиле: скруглённый бейдж цвета категории + белый глиф.
viewBox 64×64, глиф в безопасной зоне 12..52. Выход: assets/icons/svg/*.svg, png/64/*.png, png/128/*.png, previews/sheet_icons.png
"""
from __future__ import annotations

from pathlib import Path

import cairosvg
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SVG_DIR = ROOT / "assets" / "icons" / "svg"
PNG_DIR = ROOT / "assets" / "icons" / "png"

CAT = {
    "unit": "#4E5A35", "civ": "#3F6FA8", "zmb": "#2E333B", "res_food": "#C9932A", "res_power": "#E0A100",
    "res_wood": "#8C6239", "res_iron": "#5E6770", "res_people": "#3F6FA8", "res_morale": "#3E9E5E",
    "bld": "#3A4148", "abl": "#E85A12", "status": "#6B6F75", "doc": "#26466B",
}
W = "#FFFFFF"
G = "#9BE564"   # зелень заражения
R = "#D23B3B"
S = 'stroke="#FFFFFF" stroke-width="4" stroke-linecap="round" stroke-linejoin="round" fill="none"'
SF = 'fill="#FFFFFF"'

ICONS: dict[str, tuple[str, str, str]] = {}  # id → (категория, подпись, глиф)


def icon(id_, cat, label, glyph):
    ICONS[id_] = (cat, label, glyph)


# ----------------------------------------------------------------- военные
RIFLE = (f'<g {SF}><path d="M8 27l10-2v10l-10 3z"/><rect x="18" y="25" width="24" height="8" rx="1.5"/>'
         f'<rect x="42" y="27.5" width="14" height="3.5" rx="1"/><path d="M28 33h7l2 11-6 1z"/>'
         f'<path d="M20 33h5l-1 8h-5z"/><rect x="24" y="21" width="10" height="4" rx="1"/></g>')
icon("unit_assault", "unit", "Штурмовик", RIFLE + f'<ellipse cx="47" cy="45" rx="5" ry="6" {SF}/><rect x="44.5" y="36" width="5" height="3" {SF}/>')
icon("unit_sniper", "unit", "Снайпер",
     f'<circle cx="32" cy="32" r="15" {S}/><circle cx="32" cy="32" r="3" {SF}/>'
     f'<path {S} d="M32 10v10M32 44v10M10 32h10M44 32h10"/>')
icon("unit_medic", "unit", "Медик", f'<path {SF} d="M26 12h12v14h14v12H38v14H26V38H12V26h14z"/><path fill="{R}" d="M29 15h6v14h14v6H35v14h-6V35H15v-6h14z"/>')
icon("unit_scout", "unit", "Разведчик",
     f'<circle cx="21" cy="38" r="9" {S}/><circle cx="43" cy="38" r="9" {S}/>'
     f'<path {S} d="M27 32l3-12h4l3 12M18 29l3-9M46 29l-3-9"/>')
icon("unit_bmp", "unit", "БМП",
     f'<path {SF} d="M8 36h48l-5 9H13z"/><path {SF} d="M14 28h30l8 8H12z"/><rect x="26" y="21" width="10" height="7" rx="2" {SF}/>'
     f'<path {S} d="M36 24h20"/><g fill="#4E5A35"><circle cx="18" cy="41" r="2.5"/><circle cx="27" cy="41" r="2.5"/><circle cx="36" cy="41" r="2.5"/><circle cx="45" cy="41" r="2.5"/></g>')
icon("unit_tank", "unit", "Танк",
     f'<rect x="8" y="36" width="44" height="12" rx="6" {SF}/><path {SF} d="M12 30h36l4 6H10z"/>'
     f'<path {SF} d="M20 22h16l4 8H18z"/><path {S} d="M38 25h20"/>'
     f'<g fill="#4E5A35"><circle cx="15" cy="42" r="2.5"/><circle cx="24" cy="42" r="2.5"/><circle cx="33" cy="42" r="2.5"/><circle cx="42" cy="42" r="2.5"/></g>')
icon("unit_heli", "unit", "Вертолёт",
     f'<path {S} d="M10 18h44M32 18v8"/><path {SF} d="M18 28h22c6 0 10 4 10 9s-4 7-9 7H26l-8-6z"/>'
     f'<path {S} d="M20 33H8M8 28v10M28 44l-3 6M40 44l3 6M22 50h24"/>')

# ----------------------------------------------------------------- мирные
def person(cx=32, top=12, scale=1.0, fill=W):
    s = scale
    return (f'<circle cx="{cx}" cy="{top + 7 * s}" r="{7 * s}" fill="{fill}"/>'
            f'<path fill="{fill}" d="M{cx - 12 * s} {top + 40 * s}v-9c0-6 5-11 12-11s12 5 12 11v9z"/>')


icon("civ_adult", "civ", "Мирный", person())
icon("civ_child", "civ", "Ребёнок", person(cx=22, top=14, scale=0.95) + person(cx=44, top=26, scale=0.6))

# ----------------------------------------------------------------- зомби
ZB = f'<circle cx="26" cy="17" r="7" fill="{G}"/><path fill="{W}" d="M16 52l4-18c1-5 4-8 9-8h3l6 4h14v6H37l-3-2-2 18z"/>'
icon("zmb_walker", "zmb", "Ходок", ZB)
icon("zmb_runner", "zmb", "Бегун",
     f'<circle cx="36" cy="15" r="6.5" fill="{G}"/><path fill="{W}" d="M18 52l9-14-4-4 6-11c2-3 6-3 8 0l5 9 9 3-2 5-11-3-3 6 6 9h-6l-6-8-6 8z"/>'
     f'<path stroke="{G}" stroke-width="3" stroke-linecap="round" d="M8 26h8M6 34h8M10 42h6"/>')
icon("zmb_brute", "zmb", "Громила",
     f'<circle cx="32" cy="15" r="5.5" fill="{G}"/><path fill="{W}" d="M10 40l4-14c1-4 4-6 8-6h20c4 0 7 2 8 6l4 14h-8l-3-9v21H21V31l-3 9z"/>')
icon("zmb_screamer", "zmb", "Крикун",
     f'<path fill="{W}" d="M22 52V36c0-10 4-18 10-18s10 8 10 18v16z"/><ellipse cx="32" cy="30" rx="4" ry="6" fill="#2E333B"/>'
     f'<path stroke="{G}" stroke-width="3.5" fill="none" stroke-linecap="round" d="M13 20c-4 5-4 13 0 18M50 20c4 5 4 13 0 18M8 15c-6 9-6 19 0 28M56 15c6 9 6 19 0 28"/>')
icon("zmb_spitter", "zmb", "Плевун",
     f'<path fill="{G}" d="M32 10c8 12 14 19 14 27a14 14 0 0 1-28 0c0-8 6-15 14-27z"/><circle cx="27" cy="38" r="4" fill="#2E333B" opacity=".35"/>')
icon("zmb_nest", "zmb", "Гнездо",
     f'<circle cx="32" cy="36" r="13" fill="{W}"/><circle cx="18" cy="26" r="7" fill="{W}"/><circle cx="46" cy="26" r="7" fill="{W}"/>'
     f'<circle cx="32" cy="36" r="5" fill="{G}"/><circle cx="18" cy="26" r="2.5" fill="{G}"/><circle cx="46" cy="26" r="2.5" fill="{G}"/>'
     f'<path stroke="{W}" stroke-width="3" stroke-linecap="round" d="M12 50l8-6M52 50l-8-6M32 50v4"/>')

# ----------------------------------------------------------------- ресурсы
icon("res_food", "res_food", "Еда",
     f'<rect x="16" y="18" width="32" height="32" rx="4" {SF}/><ellipse cx="32" cy="18" rx="16" ry="5" fill="#F2D27A"/>'
     f'<rect x="16" y="28" width="32" height="10" fill="#C9932A" opacity=".55"/>')
icon("res_power", "res_power", "Энергия", f'<path {SF} d="M36 8L16 36h13l-3 20 22-30H35z"/>')
icon("res_wood", "res_wood", "Дерево",
     f'<rect x="8" y="30" width="38" height="14" rx="7" {SF}/><circle cx="46" cy="37" r="7" fill="#E9CFA5"/><circle cx="46" cy="37" r="3" fill="#8C6239" opacity=".5"/>'
     f'<rect x="16" y="16" width="34" height="12" rx="6" {SF}/><circle cx="50" cy="22" r="6" fill="#E9CFA5"/>')
icon("res_iron", "res_iron", "Железо",
     f'<path {SF} d="M32 10l19 11v22L32 54 13 43V21z"/><circle cx="32" cy="32" r="8" fill="#5E6770"/>')
icon("res_people", "res_people", "Люди", person(cx=24, top=14, scale=0.85) + person(cx=42, top=18, scale=0.8))
icon("res_morale", "res_morale", "Мораль",
     f'<circle cx="32" cy="32" r="19" {S}/><circle cx="25" cy="27" r="3" {SF}/><circle cx="39" cy="27" r="3" {SF}/>'
     f'<path {S} d="M23 37c5 6 13 6 18 0"/>')

# ----------------------------------------------------------------- статусы
VIRUS = (f'<circle cx="32" cy="32" r="11" fill="{G}"/>' +
         "".join(f'<g transform="rotate({a} 32 32)"><path stroke="{G}" stroke-width="3.5" d="M32 21v-7"/><circle cx="32" cy="12" r="3" fill="{G}"/></g>'
                 for a in range(0, 360, 45)))
icon("st_infected", "status", "Заражён", VIRUS)
icon("st_healing", "status", "Лечение",
     f'<path {SF} d="M32 52S10 38 10 24a11 11 0 0 1 22-3 11 11 0 0 1 22 3c0 14-22 28-22 28z"/><path stroke="{R}" stroke-width="4" stroke-linecap="round" d="M32 24v14M25 31h14"/>')
icon("st_noise", "status", "Шум",
     f'<path {SF} d="M10 26h8l12-10v32L18 38h-8z"/><path {S} d="M38 24c3 4 3 12 0 16M45 18c6 8 6 20 0 28"/>')
icon("st_hungry", "status", "Голод",
     f'<path {S} d="M12 34h40c0 10-9 16-20 16s-20-6-20-16z"/><path {S} d="M24 12v14M20 12v8c0 3 8 3 8 0v-8M42 12c-4 3-4 10 0 14v-14"/>')
icon("st_follow", "status", "Ведомый",
     person(cx=22, top=14, scale=0.8) + f'<path {S} d="M40 22l10 10-10 10M34 32h16"/>')
icon("st_recruit", "status", "Рекрут", person(cx=26, top=14, scale=0.85) + f'<path stroke="{W}" stroke-width="4.5" stroke-linecap="round" d="M46 20v14M39 27h14"/>')
icon("st_low_power", "status", "Нет энергии", f'<path {SF} d="M36 8L16 36h13l-3 20 22-30H35z" opacity=".45"/><path stroke="{R}" stroke-width="5" stroke-linecap="round" d="M14 14l36 36"/>')
icon("st_night", "status", "Ночь", f'<path {SF} d="M40 10a22 22 0 1 0 14 34A18 18 0 0 1 40 10z"/>')
icon("st_day", "status", "День", f'<circle cx="32" cy="32" r="9" {SF}/>' +
     "".join(f'<path {S} transform="rotate({a} 32 32)" d="M32 12v6"/>' for a in range(0, 360, 45)))
icon("st_wave", "status", "Волна", ZB.replace(G, W) + f'<path stroke="{R}" stroke-width="4" stroke-linecap="round" d="M50 12v14M50 32v1"/>')

# ----------------------------------------------------------------- способности
icon("abl_grenade", "abl", "Граната",
     f'<ellipse cx="30" cy="38" rx="13" ry="15" {SF}/><path {SF} d="M24 18h12v6H24z"/><path {S} d="M36 20c8-2 12 2 12 8"/><circle cx="46" cy="14" r="4" {S}/>')
icon("abl_aimed_shot", "abl", "Прицельный выстрел",
     f'<circle cx="32" cy="32" r="16" {S}/><circle cx="32" cy="32" r="7" {S}/><circle cx="32" cy="32" r="2.5" {SF}/>'
     f'<path {S} d="M32 8v8M32 48v8M8 32h8M48 32h8"/>')
icon("abl_antidote", "abl", "Антидот",
     f'<path {SF} d="M40 10l14 14-4 4-3-3-17 17-8 2 2-8 17-17-3-3z"/><path {S} d="M18 46l-8 8"/><path fill="{G}" d="M31 28l6 6-8 8-6 1 1-6z"/>')
icon("abl_flare", "abl", "Сигнальная ракета",
     f'<path {S} d="M18 52l14-26"/><circle cx="36" cy="18" r="6" {SF}/>' +
     "".join(f'<path {S} transform="rotate({a} 36 18)" d="M36 6v-1"/>' for a in range(0, 360, 60)))
icon("abl_camo", "abl", "Маскировка",
     f'<path {S} d="M8 32s9-14 24-14 24 14 24 14-9 14-24 14S8 32 8 32z"/><circle cx="32" cy="32" r="6" {SF}/><path {S} d="M12 52L52 12"/>')
icon("abl_smoke", "abl", "Дым",
     f'<path {SF} d="M18 46a10 10 0 0 1 0-20 13 13 0 0 1 25-3 10 10 0 0 1 3 20z"/><path {S} d="M14 54h32"/>')
icon("abl_ram", "abl", "Таран", f'<path {SF} d="M8 22h20l10 10-10 10H8l10-10z"/><path {S} d="M46 14v36M54 18v28"/>')
icon("abl_napalm", "abl", "Напалм",
     f'<path {SF} d="M32 8c4 10 16 16 16 30a16 16 0 0 1-32 0c0-7 4-12 8-15 0 6 3 9 6 9-3-9 0-17 2-24z"/><path fill="{CAT["abl"]}" d="M32 34c3 4 6 6 6 10a6 6 0 0 1-12 0c0-4 3-6 6-10z"/>')

# ----------------------------------------------------------------- постройки
icon("bld_hq", "bld", "Штаб", f'<path {S} d="M18 54V10"/><path {SF} d="M20 12h26l-6 8 6 8H20z"/><path {S} d="M10 54h44"/>')
icon("bld_tent", "bld", "Палатка", f'<path {SF} d="M32 12L54 50H10z"/><path fill="{CAT["bld"]}" d="M32 30l8 20H24z"/>')
icon("bld_house", "bld", "Жилой модуль",
     f'<path {SF} d="M10 30L32 12l22 18v22H10z"/><rect x="18" y="32" width="8" height="8" fill="{CAT["bld"]}"/><rect x="38" y="32" width="8" height="8" fill="{CAT["bld"]}"/><rect x="28" y="40" width="8" height="12" fill="{CAT["bld"]}"/>')
icon("bld_storage", "bld", "Склад", f'<path {SF} d="M8 52V30a24 18 0 0 1 48 0v22z"/><rect x="22" y="34" width="20" height="18" fill="{CAT["bld"]}"/><path stroke="{W}" stroke-width="3" d="M22 40h20M22 46h20"/>')
icon("bld_kitchen", "bld", "Кухня",
     f'<path {SF} d="M12 30h40v6c0 10-8 16-20 16s-20-6-20-16z"/><path {S} d="M8 30h48M24 22c0-4 4-4 4-8M34 22c0-4 4-4 4-8"/>')
icon("bld_greenhouse", "bld", "Теплица",
     f'<path {S} d="M32 54V30"/><path {SF} d="M32 34c-12 0-18-8-18-18 12 0 18 6 18 18zM32 30c0-10 6-16 18-16 0 10-6 16-18 16z"/>')
icon("bld_sawmill", "bld", "Лесопилка",
     f'<circle cx="32" cy="32" r="14" {SF}/>' +
     "".join(f'<path {SF} transform="rotate({a} 32 32)" d="M30 14l2-6 4 6z"/>' for a in range(0, 360, 30)) +
     f'<circle cx="32" cy="32" r="4" fill="{CAT["bld"]}"/>')
icon("bld_scrapyard", "bld", "Металлоразборка",
     f'<path {S} stroke-width="8" stroke-linecap="butt" d="M18 12v18a14 14 0 0 0 28 0V12"/><path stroke="{R}" stroke-width="8" d="M18 12v6M46 12v6"/>')
icon("bld_generator", "bld", "Генератор",
     f'<rect x="10" y="18" width="44" height="30" rx="4" {SF}/><path fill="{CAT["bld"]}" d="M35 22L24 36h8l-2 10 11-15h-8z"/><path {S} d="M16 52v4M48 52v4"/>')
icon("bld_solar", "bld", "Солнечные панели",
     f'<path {SF} d="M14 36h36l-6 14H8z" transform="translate(4 0)"/><path stroke="{CAT["bld"]}" stroke-width="2.5" d="M24 36l-4 14M36 36l-2 14M14 43h38"/>'
     f'<circle cx="46" cy="18" r="6" {SF}/>')
icon("bld_battery", "bld", "Аккумулятор",
     f'<rect x="10" y="20" width="40" height="24" rx="4" {S}/><rect x="50" y="27" width="4" height="10" {SF}/><rect x="15" y="25" width="10" height="14" {SF}/><rect x="27" y="25" width="10" height="14" {SF}/>')
icon("bld_medpost", "bld", "Медпункт",
     f'<path {SF} d="M10 30L32 12l22 18v22H10z"/><path fill="{R}" d="M28 28h8v6h6v8h-6v6h-8v-6h-6v-8h6z"/>')
icon("bld_quarantine", "bld", "Карантин",
     f'<path {SF} d="M32 8l24 42H8z"/><path fill="{CAT["bld"]}" d="M29 22h6l-1 16h-4zM29 42h6v5h-6z"/>')
icon("bld_checkpoint", "bld", "КПП",
     f'<rect x="8" y="22" width="12" height="30" rx="2" {SF}/><path stroke="{W}" stroke-width="7" d="M20 28h36"/>'
     f'<path stroke="{R}" stroke-width="7" d="M28 28h6M42 28h6"/>')
icon("bld_barracks", "bld", "Казарма", f'<path {S} stroke-width="6" d="M14 26l18-12 18 12M14 40l18-12 18 12M14 54l18-12 18 12"/>')
icon("bld_motorpool", "bld", "Автопарк",
     f'<path {SF} d="M44 10a10 10 0 0 0-11 13L12 44a5 5 0 0 0 8 8l21-21a10 10 0 0 0 13-11l-6 6-7-2-2-7z"/>')
icon("bld_helipad", "bld", "Вертолётная площадка",
     f'<circle cx="32" cy="32" r="21" {S}/><path {S} stroke-width="6" d="M24 20v24M40 20v24M24 32h16"/>')
icon("bld_workshop", "bld", "Мастерская",
     f'<circle cx="32" cy="32" r="12" {SF}/>' +
     "".join(f'<rect x="28" y="10" width="8" height="10" rx="2" {SF} transform="rotate({a} 32 32)"/>' for a in range(0, 360, 45)) +
     f'<circle cx="32" cy="32" r="5" fill="{CAT["bld"]}"/>')
icon("bld_wall", "bld", "Стена",
     f'<g {SF}><rect x="8" y="14" width="22" height="10" rx="1"/><rect x="34" y="14" width="22" height="10" rx="1"/>'
     f'<rect x="8" y="27" width="10" height="10" rx="1"/><rect x="21" y="27" width="22" height="10" rx="1"/><rect x="46" y="27" width="10" height="10" rx="1"/>'
     f'<rect x="8" y="40" width="22" height="10" rx="1"/><rect x="34" y="40" width="22" height="10" rx="1"/></g>')
icon("bld_gate", "bld", "Ворота",
     f'<rect x="8" y="12" width="7" height="42" {SF}/><rect x="49" y="12" width="7" height="42" {SF}/>'
     f'<path {S} d="M18 20h12v30H18zM34 20h12v30H34zM18 20l12 30M46 20L34 50"/>')
icon("bld_tower", "bld", "Вышка",
     f'<path {SF} d="M14 18L32 8l18 10z"/><rect x="16" y="20" width="32" height="10" {SF}/><path {S} d="M20 30l-4 24M44 30l4 24M22 40h20M20 50h24"/>')
icon("bld_floodlight", "bld", "Прожектор",
     f'<path {SF} d="M14 14h16l6 10H8z" transform="rotate(20 22 19)"/><path {S} d="M22 28v26M14 54h16"/>'
     f'<path stroke="#FFE3A3" stroke-width="4" stroke-linecap="round" d="M38 26l14 6M36 34l12 12M40 18l14-2"/>')
icon("bld_siren", "bld", "Громкоговоритель",
     f'<path {SF} d="M10 26h8l22-12v36L18 38h-8z"/><path {S} d="M46 24c3 4 3 12 0 16M52 18c6 8 6 20 0 28"/>')
icon("bld_sandbags", "bld", "Мешки с песком",
     f'<g {SF}><rect x="8" y="38" width="15" height="12" rx="6"/><rect x="25" y="38" width="15" height="12" rx="6"/><rect x="42" y="38" width="15" height="12" rx="6"/>'
     f'<rect x="16" y="25" width="15" height="12" rx="6"/><rect x="33" y="25" width="15" height="12" rx="6"/><rect x="24" y="12" width="15" height="12" rx="6"/></g>')

# ----------------------------------------------------------------- доктрины
icon("doc_infantry", "doc", "Мотострелки", RIFLE + f'<path {S} d="M18 52l14-8 14 8"/>')
icon("doc_armor", "doc", "Бронетехника",
     f'<rect x="8" y="34" width="44" height="12" rx="6" {SF}/><path {SF} d="M14 26h28l6 8H12z"/><path {S} d="M40 22h18"/><path {S} d="M18 54l14-4 14 4"/>')
icon("doc_aviation", "doc", "Армейская авиация",
     f'<path {SF} d="M32 14l6 12 18 4-18 4-6 16-6-16-18-4 18-4z"/>')
icon("doc_civil_defense", "doc", "Гражданская оборона",
     f'<path {SF} d="M32 8l20 8v14c0 12-8 20-20 26-12-6-20-14-20-26V16z"/>'
     f'<path fill="#26466B" d="M29 20h6v8h8v6h-8v8h-6v-8h-8v-6h8z"/>')


_TAG = __import__("re").compile(r"<([a-zA-Z]+)((?:\s+[a-zA-Z:-]+=\"[^\"]*\")*)\s*(/?)>")
_ATTR = __import__("re").compile(r'([a-zA-Z:-]+)="([^"]*)"')


def _dedupe(svg: str) -> str:
    """Убирает дубли атрибутов в теге (последний выигрывает) — удобно писать {S} stroke-width=\"8\"."""
    def fix(m):
        attrs = {}
        for k, v in _ATTR.findall(m.group(2)):
            attrs[k] = v
        a = "".join(f' {k}="{v}"' for k, v in attrs.items())
        return f"<{m.group(1)}{a}{' /' if m.group(3) else ''}>"
    return _TAG.sub(fix, svg)


def svg_doc(cat, glyph):
    glyph = _dedupe(glyph)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">'
            f'<rect x="2" y="2" width="60" height="60" rx="14" fill="{CAT[cat]}"/>'
            f'<rect x="2" y="2" width="60" height="60" rx="14" fill="none" stroke="#000" stroke-opacity=".18" stroke-width="2"/>'
            f'<g transform="translate(32 32) scale(.86) translate(-32 -32)">{glyph}</g></svg>')


def glyph_only(glyph):
    glyph = _dedupe(glyph)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">{glyph}</svg>')


def main():
    SVG_DIR.mkdir(parents=True, exist_ok=True)
    (SVG_DIR / "glyph").mkdir(exist_ok=True)
    for sz in (64, 128):
        (PNG_DIR / str(sz)).mkdir(parents=True, exist_ok=True)
    for id_, (cat, label, glyph) in ICONS.items():
        doc = svg_doc(cat, glyph)
        (SVG_DIR / f"{id_}.svg").write_text(doc)
        (SVG_DIR / "glyph" / f"{id_}.svg").write_text(glyph_only(glyph))  # без бейджа — для HUD/мини-карты
        for sz in (64, 128):
            cairosvg.svg2png(bytestring=doc.encode(), write_to=str(PNG_DIR / str(sz) / f"{id_}.png"),
                             output_width=sz, output_height=sz)
    # контакт-лист
    F_B = "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf"; F_R = "/usr/share/fonts/opentype/inter/Inter-Regular.otf"
    cols, cell = 10, 150
    items = list(ICONS.items())
    rows = (len(items) + cols - 1) // cols
    img = Image.new("RGB", (cols * cell + 48, rows * cell + 120), (238, 236, 230))
    d = ImageDraw.Draw(img)
    d.text((24, 22), "UI-ИКОНКИ", font=ImageFont.truetype(F_B, 34), fill=(34, 38, 44))
    d.text((24, 66), f"КАРАНТИН: МОСКВА · {len(items)} иконок · SVG + PNG 64/128 + глифы без бейджа",
           font=ImageFont.truetype(F_R, 18), fill=(120, 124, 130))
    d.rectangle((24, 96, 84, 100), fill=(255, 106, 31))
    fl = ImageFont.truetype(F_R, 13)
    for i, (id_, (cat, label, _)) in enumerate(items):
        x, y = 24 + (i % cols) * cell, 116 + (i // cols) * cell
        ic = Image.open(PNG_DIR / "128" / f"{id_}.png").convert("RGBA").resize((96, 96), Image.LANCZOS)
        img.paste(ic, (x + (cell - 96) // 2, y), ic)
        tw = d.textlength(label, font=fl)
        d.text((x + (cell - tw) / 2, y + 102), label, font=fl, fill=(34, 38, 44))
    img.save(ROOT / "previews" / "sheet_icons.png", optimize=True)
    print(len(ICONS), "icons")


if __name__ == "__main__":
    main()
