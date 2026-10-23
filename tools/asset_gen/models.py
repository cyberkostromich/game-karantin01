"""
models.py — процедурные low-poly плейсхолдеры для «Карантин: Москва».
Запуск:  python3 models.py  → assets/models/**.glb, assets/textures/palette.png, assets/models/manifest.json

Это ПЛЕЙСХОЛДЕРЫ правильного масштаба, силуэта, цвета и с правильными узлами под анимацию.
Финальные модели заменяют их 1:1 по имени файла и именам узлов (см. docs/05_art_bible.md).
"""
from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

import numpy as np
import trimesh

from lowpoly import ALONG_X, UP, Model, _rot_matrix, save_palette

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "models"
REG: list[tuple[str, str, Model]] = []  # (category, file, model)


def reg(cat: str, m: Model, **meta):
    m.meta.update(meta)
    REG.append((cat, f"{m.name}.glb", m))
    return m


# ======================================================================================
# ГУМАНОИДЫ
# ======================================================================================

def humanoid(name, *, s=1.0, w=1.0, skin="SKIN_A", shirt="OLIVE", pants="OLIVE_D", shoes="SHOE",
             hunch=0.0, arm_pose="down", head_tilt=0.0, stride=0.0, head_scale=1.0):
    """Базовый человек ~1.8 м * s. Узлы: body, head, arm_l, arm_r, leg_l, leg_r. Смотрит в +Z."""
    m = Model(name)
    hip = 0.88 * s
    tor_h = 0.58 * s
    sh_y = hip + tor_h
    lx = 0.12 * w * s
    # ноги
    for side, sx, st in (("l", -1, stride), ("r", 1, -stride)):
        leg = m.node(f"leg_{side}", pivot=(sx * lx, hip, 0))
        leg.box((0.2 * w * s, hip - 0.08 * s, 0.24 * s), (sx * lx, hip / 2 + 0.04 * s, 0), pants)
        leg.box((0.2 * w * s, 0.1 * s, 0.32 * s), (sx * lx, 0.05 * s, 0.04 * s), shoes)
        if st:
            leg.rest_rot = (st, 0, 0)
    # корпус
    body = m.node("body", pivot=(0, hip, 0))
    body.box((0.5 * w * s, tor_h, 0.3 * s), (0, hip + tor_h / 2, 0), shirt)
    body.box((0.48 * w * s, 0.12 * s, 0.28 * s), (0, hip + 0.04 * s, 0), pants)  # пояс/таз
    if hunch:
        body.rest_rot = (hunch, 0, 0)
    # голова
    head = m.node("head", parent="body", pivot=(0, sh_y, 0))
    hs = s * head_scale
    head.box((0.12 * s, 0.08 * s, 0.12 * s), (0, sh_y + 0.04 * s, 0), skin)  # шея
    head.box((0.28 * hs, 0.3 * hs, 0.28 * hs), (0, sh_y + 0.08 * s + 0.15 * hs, 0), skin)
    if head_tilt:
        head.rest_rot = (head_tilt, 0, 0)
    # руки
    ax = 0.25 * w * s + 0.085 * s
    poses = {
        "down": ((4, 0, 6), (4, 0, -6)),
        "rifle": ((-55, -20, 0), (-80, 10, 0)),
        "pistol": ((5, 0, 6), (-80, 0, 0)),
        "zombie": ((-85, 8, 0), (-75, -8, 0)),
        "brute": ((-25, 0, 18), (-40, 0, -18)),
        "back": ((22, 0, 16), (22, 0, -16)),
        "carry": ((-40, 0, 5), (-40, 0, -5)),
    }
    pl, pr = poses[arm_pose]
    for side, sx, pose in (("l", -1, pl), ("r", 1, pr)):
        arm = m.node(f"arm_{side}", parent="body", pivot=(sx * ax, sh_y - 0.05 * s, 0))
        arm.box((0.15 * w * s, 0.56 * s, 0.17 * s), (sx * ax, sh_y - 0.05 * s - 0.28 * s, 0), shirt)
        arm.box((0.13 * w * s, 0.1 * s, 0.14 * s), (sx * ax, sh_y - 0.05 * s - 0.6 * s, 0), skin)  # кисть
        arm.rest_rot = pose
    m.meta.update(hip=hip, sh_y=sh_y, s=s, w=w, ax=ax)
    return m


def head_top(m):
    s = m.meta["s"]
    return m.meta["sh_y"] + 0.08 * s + 0.3 * s


def helmet(m, color="HELMET"):
    s = m.meta["s"]; y = head_top(m)
    m.node("head").box((0.36 * s, 0.13 * s, 0.36 * s), (0, y - 0.03 * s, 0), color)


def armband(m, color="TEAM"):
    s, ax, sh = m.meta["s"], m.meta["ax"], m.meta["sh_y"]
    m.node("arm_l").box((0.17 * s, 0.08 * s, 0.19 * s), (-ax, sh - 0.2 * s, 0), color)


def vest(m, color="OLIVE_D"):
    s, hip = m.meta["s"], m.meta["hip"]
    m.node("body").box((0.54 * m.meta["w"] * s, 0.36 * s, 0.36 * s), (0, hip + 0.36 * s, 0), color)


def rifle(m, length=0.85, color="GUNMETAL", scope=False, parent="arm_r"):
    s, sh = m.meta["s"], m.meta["sh_y"]
    ax = m.meta["ax"]
    wpn = m.node("weapon", parent="body", pivot=(0.08 * s, sh - 0.22 * s, 0.25 * s))
    wpn.box((0.07, 0.1, length), (0.08 * s, sh - 0.22 * s, 0.25 * s + length * 0.25), color)
    wpn.box((0.06, 0.16, 0.08), (0.08 * s, sh - 0.32 * s, 0.25 * s + length * 0.2), color)  # магазин
    if scope:
        wpn.cyl(0.035, 0.28, (0.08 * s, sh - 0.13 * s, 0.25 * s + length * 0.2), "BLACK", sections=6)
    return wpn


def backpack(m, color="OLIVE_D", size=(0.4, 0.45, 0.2)):
    s, hip = m.meta["s"], m.meta["hip"]
    m.node("body").box(size, (0, hip + 0.32 * s, -0.25 * s), color)


# ----------------------------- военные ------------------------------------------------

def unit_assault():
    m = humanoid("unit_assault", arm_pose="rifle", shirt="OLIVE", pants="OLIVE_D")
    vest(m); helmet(m); armband(m); rifle(m)
    s, hip = 1, m.meta["hip"]
    for x in (-0.15, 0, 0.15):
        m.node("body").box((0.1, 0.12, 0.08), (x, hip + 0.2, 0.2), "OLIVE_L")  # подсумки
    backpack(m, size=(0.36, 0.3, 0.16))
    return reg("units", m, unit="assault")


def unit_sniper():
    m = humanoid("unit_sniper", arm_pose="rifle", shirt="CAMO_BROWN", pants="OLIVE_D")
    armband(m)
    rifle(m, length=1.25, scope=True)
    y = head_top(m)
    h = m.node("head")
    h.cyl(0.27, 0.05, (0, y - 0.02, 0), "KHAKI", sections=10, rot=UP)  # панама
    h.box((0.3, 0.1, 0.3), (0, y + 0.02, 0), "KHAKI")
    # маскхалат-накидка
    m.node("body").box((0.6, 0.55, 0.12), (0, m.meta["hip"] + 0.3, -0.2), "OLIVE_L")
    return reg("units", m, unit="sniper")


def unit_medic():
    m = humanoid("unit_medic", arm_pose="pistol", shirt="OLIVE", pants="OLIVE_D")
    helmet(m); armband(m, "MEDIC_WHITE")
    s, hip = 1, m.meta["hip"]
    b = m.node("body")
    b.box((0.44, 0.48, 0.24), (0, hip + 0.32, -0.26), "MEDIC_WHITE")  # медрюкзак
    b.box((0.1, 0.3, 0.02), (0, hip + 0.34, -0.39), "RED_CROSS")
    b.box((0.3, 0.1, 0.02), (0, hip + 0.34, -0.39), "RED_CROSS")
    y = head_top(m)
    m.node("head").box((0.12, 0.04, 0.02), (0, y - 0.02, 0.19), "RED_CROSS")
    # пистолет
    wpn = m.node("weapon", parent="arm_r", pivot=(m.meta["ax"], m.meta["sh_y"] - 0.65, 0))
    wpn.box((0.05, 0.12, 0.2), (m.meta["ax"], m.meta["sh_y"] - 0.7, 0.05), "GUNMETAL")
    return reg("units", m, unit="medic")


def unit_scout():
    m = humanoid("unit_scout", arm_pose="rifle", shirt="KHAKI", pants="CAMO_BROWN")
    armband(m)
    rifle(m, length=0.6)
    y = head_top(m)
    h = m.node("head")
    h.box((0.3, 0.1, 0.3), (0, y, 0), "OLIVE_D")       # кепка
    h.box((0.24, 0.03, 0.14), (0, y - 0.04, 0.2), "OLIVE_D")  # козырёк
    m.node("body").box((0.32, 0.1, 0.32), (0, m.meta["sh_y"] - 0.02, 0), "OLIVE_L")  # шарф
    backpack(m, "CAMO_BROWN", (0.34, 0.5, 0.22))
    m.node("body").cyl(0.04, 0.5, (0.15, m.meta["hip"] + 0.75, -0.3), "GUNMETAL", sections=6, rot=UP)  # антенна рации
    return reg("units", m, unit="scout")


# ----------------------------- мирные --------------------------------------------------

def civilians():
    variants = [
        ("civ_adult_a", "CIV_BLUE", "CIV_DENIM", "SKIN_A", "HAIR_D"),
        ("civ_adult_b", "CIV_RED", "CIV_GREY", "SKIN_B", "HAIR_L"),
        ("civ_adult_c", "CIV_YELLOW", "CIV_DENIM", "SKIN_C", "HAIR_D"),
        ("civ_adult_d", "CIV_GREEN", "CHARCOAL", "SKIN_A", "HAIR_L"),
        ("civ_adult_e", "CIV_PURPLE", "CIV_DENIM", "SKIN_B", "HAIR_D"),
    ]
    for name, shirt, pants, skin, hair in variants:
        m = humanoid(name, shirt=shirt, pants=pants, skin=skin, w=0.95, s=0.97)
        y = head_top(m)
        m.node("head").box((0.3, 0.1, 0.3), (0, y - 0.02, -0.01), hair)
        m.node("head").box((0.3, 0.18, 0.08), (0, y - 0.12, -0.12), hair)
        reg("civilians", m, unit="civilian")
    m = humanoid("civ_child", s=0.62, w=1.05, shirt="CIV_ORANGE", pants="CIV_DENIM", head_scale=1.25)
    y = head_top(m)
    m.node("head").box((0.3, 0.09, 0.3), (0, y + 0.06, 0), "HAIR_L")
    reg("civilians", m, unit="child")
    # мирный-рабочий с бревном (для анимации переноски)
    m = humanoid("civ_worker_carry", shirt="CIV_ORANGE", pants="CIV_DENIM", skin="SKIN_B", arm_pose="carry")
    m.node("weapon", parent="body", pivot=(0, m.meta["sh_y"] - 0.35, 0.35)).cyl(
        0.12, 1.4, (0, m.meta["sh_y"] - 0.35, 0.35), "BARK", sections=7, rot=ALONG_X)
    helmet(m, "HAZARD_YELLOW")
    reg("civilians", m, unit="civilian_worker")


# ----------------------------- зомби ---------------------------------------------------

def blood(m, node, pos, size=(0.18, 0.14, 0.02)):
    m.node(node).box(size, pos, "BLOOD")


def zmb_walker(name="zmb_walker", armored=False):
    m = humanoid(name, skin="ZMB_SKIN", shirt="ZMB_CLOTH", pants="ZMB_CLOTH_D",
                 hunch=18, arm_pose="zombie", head_tilt=12, stride=14, w=0.95)
    hip = m.meta["hip"]
    blood(m, "body", (0.08, hip + 0.4, 0.16))
    blood(m, "body", (-0.12, hip + 0.15, 0.16), (0.12, 0.2, 0.02))
    m.node("head").box((0.3, 0.06, 0.3), (0, head_top(m) - 0.02, 0), "HAIR_D")
    m.node("head").box((0.08, 0.04, 0.02), (0.06, m.meta["sh_y"] + 0.24, 0.15), "INFECT_GLOW")  # глаз
    m.node("head").box((0.08, 0.04, 0.02), (-0.06, m.meta["sh_y"] + 0.24, 0.15), "INFECT_GLOW")
    if armored:
        vest(m); helmet(m); armband(m, "OLIVE_D")
    return reg("zombies", m, unit="walker_armored" if armored else "walker")


def zmb_runner():
    m = humanoid("zmb_runner", skin="ZMB_SKIN_D", shirt="CIV_GREY", pants="ZMB_CLOTH_D",
                 hunch=32, arm_pose="back", head_tilt=-18, stride=32, w=0.8)
    blood(m, "body", (0, m.meta["hip"] + 0.3, 0.13))
    for x in (0.06, -0.06):
        m.node("head").box((0.07, 0.04, 0.02), (x, m.meta["sh_y"] + 0.24, 0.15), "INFECT_GLOW")
    return reg("zombies", m, unit="runner")


def zmb_brute():
    m = humanoid("zmb_brute", s=1.3, w=1.7, skin="BRUTE_SKIN", shirt="BRUTE_SKIN", pants="ZMB_CLOTH_D",
                 hunch=22, arm_pose="brute", head_tilt=20, head_scale=0.75)
    s, hip, ax, sh = m.meta["s"], m.meta["hip"], m.meta["ax"], m.meta["sh_y"]
    for side, sx in (("l", -1), ("r", 1)):
        a = m.node(f"arm_{side}")
        a.box((0.42, 0.5, 0.42), (sx * ax, sh - 0.65, 0), "BRUTE_SKIN")   # кулачища
        a.box((0.36, 0.3, 0.36), (sx * ax, sh - 0.12, 0), "ZMB_SKIN_D")    # плечи
    m.node("body").box((1.0, 0.35, 0.5), (0, sh - 0.05, -0.05), "ZMB_SKIN_D")  # горб
    blood(m, "body", (0.15, hip + 0.4, 0.21), (0.3, 0.25, 0.02))
    return reg("zombies", m, unit="brute")


def zmb_screamer():
    m = humanoid("zmb_screamer", w=0.75, skin="ZMB_SKIN", shirt="ZMB_CLOTH", pants="ZMB_CLOTH_D",
                 arm_pose="back", head_tilt=-35, hunch=-6)
    sh = m.meta["sh_y"]
    h = m.node("head")
    h.box((0.18, 0.16, 0.04), (0, sh + 0.17, 0.15), "SCREAM_MOUTH")  # раскрытый рот
    h.box((0.07, 0.04, 0.02), (0.06, sh + 0.3, 0.15), "INFECT_GLOW")
    h.box((0.07, 0.04, 0.02), (-0.06, sh + 0.3, 0.15), "INFECT_GLOW")
    m.node("body").box((0.36, 0.22, 0.05), (0, sh - 0.15, 0.16), "INFECT_GLOW")  # светящиеся вены на груди
    return reg("zombies", m, unit="screamer")


def zmb_spitter():
    m = humanoid("zmb_spitter", w=1.0, skin="ZMB_SKIN_D", shirt="ZMB_CLOTH_D", pants="ZMB_CLOTH_D",
                 hunch=10, arm_pose="down", head_tilt=-10)
    sh = m.meta["sh_y"]
    m.node("body").ball(0.26, (0, sh - 0.02, 0.18), "SPIT_SAC", subdiv=1, scale=(1.0, 0.8, 0.9))  # зоб
    m.node("body").ball(0.32, (0, sh - 0.15, -0.2), "SPIT_SAC", subdiv=1)  # мешок на спине
    m.node("head").box((0.12, 0.06, 0.04), (0, sh + 0.17, 0.15), "INFECT_GLOW")
    return reg("zombies", m, unit="spitter")


def zmb_giant():
    m = humanoid("zmb_giant", s=2.2, w=1.8, skin="BRUTE_SKIN", shirt="ZMB_SKIN_D", pants="ZMB_CLOTH_D",
                 hunch=25, arm_pose="brute", head_tilt=25, head_scale=0.7)
    sh, ax = m.meta["sh_y"], m.meta["ax"]
    rnd = random.Random(7)
    for i in range(7):
        x = rnd.uniform(-0.7, 0.7)
        m.node("body").cone(0.12, 0.6, (x, sh - rnd.uniform(0.1, 0.9), -0.4), "CONCRETE_L",
                            sections=5, rot=(-120, 0, 0))
    for side, sx in (("l", -1), ("r", 1)):
        m.node(f"arm_{side}").box((0.8, 0.9, 0.8), (sx * ax, sh - 1.3, 0), "BRUTE_SKIN")
    m.node("body").box((0.5, 0.4, 0.05), (0, sh - 0.6, 0.38), "INFECT_GLOW")
    return reg("zombies", m, unit="giant")


def zmb_nest():
    m = Model("zmb_nest")
    n = m.node("body")
    rnd = random.Random(3)
    for i in range(14):
        a = rnd.uniform(0, math.tau); r = rnd.uniform(0, 2.4)
        n.ball(rnd.uniform(0.7, 1.5), (math.cos(a) * r, rnd.uniform(0.2, 1.2), math.sin(a) * r),
               rnd.choice(["NEST_FLESH", "NEST_DARK", "NEST_FLESH"]), subdiv=1, scale=(1, 0.7, 1))
    for i in range(8):
        a = i / 8 * math.tau
        n.cyl(0.14, 3.2, (math.cos(a) * 2.6, 0.3, math.sin(a) * 2.6), "NEST_DARK", sections=5,
              rot=(0, math.degrees(-a) + 90, 0))
    pulse = m.node("pulse", pivot=(0, 1.6, 0))
    for i in range(5):
        a = i / 5 * math.tau
        pulse.ball(0.35, (math.cos(a) * 1.1, 1.7 + 0.3 * (i % 2), math.sin(a) * 1.1), "INFECT_GLOW", subdiv=1)
    return reg("zombies", m, unit="nest")


# ======================================================================================
# ТЕХНИКА
# ======================================================================================

def tracks(n, length, width, height, z0=0.0, wheels=6):
    for sx in (-1, 1):
        x = sx * (width / 2 - 0.3)
        n.box((0.55, height, length), (x, height / 2, z0), "TIRE")
        for i in range(wheels):
            z = z0 - length / 2 + 0.55 + i * (length - 1.1) / (wheels - 1)
            n.cyl(0.33, 0.12, (x + sx * 0.29, 0.38, z), "STEEL_D", sections=8, rot=ALONG_X)


def veh_bmp():
    m = Model("veh_bmp")
    hull = m.node("hull")
    tracks(hull, 6.4, 3.1, 0.75)
    hull.box((2.5, 0.7, 5.6), (0, 1.0, -0.3), "OLIVE")
    hull.wedge((2.5, 0.85, 1.4), (0, 0.65, 3.0), "OLIVE", slope="front")    # лобовой лист
    hull.box((3.1, 0.08, 6.0), (0, 0.78, 0), "OLIVE_D")                     # надгусеничные полки
    hull.box((0.8, 0.5, 0.2), (-0.6, 0.9, -3.2), "OLIVE_D")                 # десантные двери
    hull.box((0.8, 0.5, 0.2), (0.6, 0.9, -3.2), "OLIVE_D")
    hull.box((0.5, 0.18, 0.5), (-0.7, 1.43, 1.6), "OLIVE_D")                # люк мехвода
    hull.box((0.25, 0.25, 0.04), (0.9, 1.1, 3.25), "LIGHT_WARM")            # фары
    hull.box((0.25, 0.25, 0.04), (-0.9, 1.1, 3.25), "LIGHT_WARM")
    hull.box((0.4, 0.3, 0.02), (1.0, 1.2, -3.05), "TEAM")                   # тактический знак
    tur = m.node("turret", parent="hull", pivot=(0, 1.35, 0.4))
    tur.cyl(0.85, 0.55, (0, 1.62, 0.4), "OLIVE", sections=8, rot=UP)
    tur.box((1.0, 0.45, 0.7), (0, 1.62, 1.0), "OLIVE_D")
    tur.box((0.3, 0.3, 0.3), (0.55, 2.0, 0.2), "STEEL_D")                   # прицел
    tur.box((0.22, 0.22, 0.4), (-0.6, 1.75, 0.8), "OLIVE_D")                # ПТУР
    brl = m.node("barrel", parent="turret", pivot=(0, 1.65, 1.3))
    brl.cyl(0.07, 2.5, (0, 1.65, 2.55), "GUNMETAL", sections=6)
    brl.cyl(0.11, 0.4, (0, 1.65, 1.45), "GUNMETAL", sections=6)
    return reg("vehicles", m, unit="bmp")


def veh_tank():
    m = Model("veh_tank")
    hull = m.node("hull")
    tracks(hull, 6.9, 3.6, 0.85, wheels=6)
    hull.box((2.5, 0.65, 6.2), (0, 1.15, -0.1), "OLIVE")
    hull.wedge((2.5, 0.75, 1.2), (0, 0.8, 3.25), "OLIVE", slope="front")
    hull.box((3.6, 0.08, 6.6), (0, 0.88, 0), "OLIVE_D")
    for i in range(6):  # блоки ДЗ на лобовом
        hull.box((0.36, 0.12, 0.3), (-0.95 + i * 0.38, 1.38, 2.95), "OLIVE_L")
    hull.cyl(0.25, 1.2, (-1.2, 1.25, -3.0), "STEEL_D", sections=8, rot=ALONG_X)  # бочки
    hull.cyl(0.25, 1.2, (1.2, 1.25, -3.0), "STEEL_D", sections=8, rot=ALONG_X)
    hull.box((0.4, 0.3, 0.02), (1.1, 1.3, -3.25), "TEAM")
    tur = m.node("turret", parent="hull", pivot=(0, 1.5, 0.0))
    tur.cyl(1.45, 0.7, (0, 1.85, -0.1), "OLIVE", sections=10, rot=UP, r2=1.15)
    tur.box((1.2, 0.5, 1.0), (0, 1.8, 0.95), "OLIVE")
    for i in range(4):
        tur.box((0.3, 0.25, 0.3), (-0.9 + i * 0.6, 2.05, 1.0), "OLIVE_L")
    tur.box((1.6, 0.4, 0.7), (0, 1.85, -1.5), "OLIVE_D")              # корзина
    tur.cyl(0.32, 0.35, (0.55, 2.35, -0.3), "OLIVE_D", sections=8, rot=UP)   # командирская башенка
    tur.cyl(0.04, 0.9, (0.55, 2.6, 0.1), "GUNMETAL", sections=5)       # зенитный пулемёт
    tur.cyl(0.03, 2.2, (-0.7, 3.1, -1.1), "GUNMETAL", sections=4, rot=UP)  # антенна
    brl = m.node("barrel", parent="turret", pivot=(0, 1.9, 1.4))
    brl.cyl(0.11, 4.6, (0, 1.9, 3.7), "OLIVE_D", sections=8)
    brl.cyl(0.17, 0.7, (0, 1.9, 2.4), "OLIVE_D", sections=8)            # эжектор
    return reg("vehicles", m, unit="tank")


def veh_heli():
    m = Model("veh_heli")
    body = m.node("body")
    body.box((2.6, 2.2, 7.0), (0, 1.9, 0.0), "OLIVE")                   # фюзеляж
    body.wedge((2.0, 1.5, 2.2), (0, 1.0, 4.2), "OLIVE", slope="front")  # нос
    body.box((1.7, 0.7, 1.6), (0, 2.25, 3.9), "GLASS")                  # кабина
    body.box((1.2, 0.6, 2.4), (0, 2.95, 0.4), "OLIVE_D")                # двигатели
    body.cyl(0.32, 5.8, (0, 2.15, -5.5), "OLIVE", sections=6, r2=0.18)  # хвостовая балка
    body.box((0.15, 1.6, 1.2), (0, 2.8, -8.2), "OLIVE")                 # киль
    body.box((2.4, 0.08, 0.7), (0, 2.1, -7.6), "OLIVE_D")               # стабилизатор
    for sx in (-1, 1):
        body.box((1.6, 0.12, 0.9), (sx * 1.85, 1.9, 0.3), "OLIVE_D")    # крылья
        body.cyl(0.2, 1.2, (sx * 2.3, 1.65, 0.4), "GUNMETAL", sections=6)  # блоки НАР
        body.box((0.1, 0.6, 0.12), (sx * 0.8, 0.5, 2.6), "STEEL_D")     # стойки шасси
        body.cyl(0.28, 0.2, (sx * 0.9, 0.28, 2.6), "TIRE", sections=8, rot=ALONG_X)
        body.box((0.05, 0.5, 0.5), (sx * 1.11, 2.2, 0.4), "TEAM")
    body.box((0.25, 0.25, 0.6), (0, 0.9, 4.6), "GUNMETAL")              # пулемётная турель
    rot = m.node("rotor_main", parent="body", pivot=(0, 3.45, 0.4))
    rot.cyl(0.25, 0.4, (0, 3.45, 0.4), "STEEL_D", sections=8, rot=UP)
    for i in range(5):
        a = i / 5 * 360
        blade = trimesh.creation.box(extents=(0.38, 0.05, 8.2))
        blade.apply_translation((0, 0, 4.1))
        blade.apply_transform(_rot_matrix((0, a, 0)))
        blade.apply_translation((0, 3.62, 0.4))
        rot.add(blade, "GUNMETAL")
    tail = m.node("rotor_tail", parent="body", pivot=(-0.2, 2.9, -8.4))
    for i in range(3):
        a = i / 3 * 360
        b = trimesh.creation.box(extents=(0.04, 0.2, 1.4)); b.apply_translation((0, 0, 0.7))
        b.apply_transform(_rot_matrix((a, 0, 0)))
        b.apply_translation((-0.2, 2.9, -8.4))
        tail.add(b, "GUNMETAL")
    return reg("vehicles", m, unit="heli")


# ======================================================================================
# ЗДАНИЯ ИГРОКА (footprint по 2 м клеткам из data/buildings.json)
# ======================================================================================

def flag(n, x, z, h=6.0):
    n.cyl(0.05, h, (x, h / 2, z), "STEEL", sections=5, rot=UP)
    n.box((0.04, 0.7, 1.1), (x, h - 0.4, z + 0.55), "TEAM")


def sandbag_row(n, x0, z0, length, along="x", layers=2):
    k = max(1, int(length / 0.6))
    for L in range(layers):
        for i in range(k):
            off = -length / 2 + 0.3 + i * (length - 0.6) / max(1, k - 1) + (0.15 if L % 2 else 0)
            if abs(off) > length / 2: continue
            p = (x0 + off, 0.15 + L * 0.27, z0) if along == "x" else (x0, 0.15 + L * 0.27, z0 + off)
            sz = (0.58, 0.28, 0.36) if along == "x" else (0.36, 0.28, 0.58)
            n.box(sz, p, "SANDBAG")


def windows_row(n, x0, x1, y, z, color="GLASS", step=1.6, w=0.9, h=1.0, face="z"):
    x = x0 + step / 2
    while x < x1:
        if face == "z":
            n.box((w, h, 0.08), (x, y, z), color)
        else:
            n.box((0.08, h, w), (z, y, x), color)
        x += step


def bld_hq():
    m = Model("bld_hq")
    n = m.node("body")
    n.box((16, 0.25, 16), (0, 0.12, 0), "CONCRETE_D")              # площадка
    n.box((11, 4.2, 7.5), (0, 2.35, -1.5), "CONCRETE")             # бункер-корпус
    n.box((11.4, 0.4, 7.9), (0, 4.6, -1.5), "CONCRETE_D")          # парапет
    windows_row(n, -5, 5, 2.8, 2.27, color="CHARCOAL", step=2.2, w=1.2, h=0.6)
    n.box((2.2, 2.6, 0.3), (0, 1.55, 2.3), "STEEL_D")              # ворота
    n.cyl(0.08, 9, (4, 8.9, -3.5), "STEEL", sections=5, rot=UP)    # мачта
    n.cyl(0.8, 0.3, (3.0, 5.6, -0.5), "WHITE", sections=10, rot=(-60, 0, 0))  # тарелка
    n.box((2.5, 1.2, 2.0), (-3.5, 5.4, -2.5), "OLIVE")             # генераторный модуль на крыше
    flag(n, -5, 3.6, 7)
    sandbag_row(n, -4.5, 4.4, 5)
    sandbag_row(n, 4.5, 4.4, 5)
    sandbag_row(n, 7.2, 0, 8, along="z")
    sandbag_row(n, -7.2, 0, 8, along="z")
    return reg("buildings", m, building="hq")


def bld_tent():
    m = Model("bld_tent"); n = m.node("body")
    n.box((5.6, 0.1, 5.6), (0, 0.05, 0), "DIRT")
    n.box((4.4, 1.2, 4.8), (0, 0.6, 0), "TARP_GREEN")
    n.roof((4.6, 1.4, 5.0), (0, 1.2, 0), "TARP_GREEN")
    n.box((1.1, 1.6, 0.06), (0, 0.8, 2.42), "OLIVE_D")
    return reg("buildings", m, building="tent")


def bld_house():
    m = Model("bld_house"); n = m.node("body")
    for fl in range(2):
        y = 0.1 + fl * 2.7
        n.box((7.6, 2.6, 11.6), (0, y + 1.3, 0), "PANEL_WHITE")
        n.box((7.65, 0.3, 11.65), (0, y + 2.45, 0), "TILE_BLUE")
        windows_row(n, -5.6, 5.6, y + 1.4, 3.85, step=2.2, face="x")
        windows_row(n, -5.6, 5.6, y + 1.4, -3.85, step=2.2, face="x")
    n.box((1.0, 2.0, 0.1), (2.5, 1.1, 5.85), "TILE_BLUE")
    n.box((1.4, 5.4, 1.2), (-3.5, 2.7, 6.3), "STEEL")              # лестница
    return reg("buildings", m, building="house")


def bld_storage():
    m = Model("bld_storage"); n = m.node("body")
    n.box((9.6, 2.5, 9.6), (0, 1.25, 0), "STEEL")
    arch = [(4.9 * math.cos(math.pi * k / 8), 2.5 + 3.2 * math.sin(math.pi * k / 8)) for k in range(9)]
    n.prism(arch, 9.8, (0, 0, -4.9), "STEEL_D")                    # арочная крыша (ангар)
    n.box((3.6, 3.4, 0.1), (0, 1.7, 4.85), "CONCRETE_D")
    rnd = random.Random(1)
    for i in range(6):
        n.box((1.0, 1.0, 1.0), (rnd.uniform(-4, 4), 0.5 + (i % 2), 5.6 + rnd.uniform(0, 0.4)),
              rnd.choice(["WOOD", "OLIVE", "WOOD_L"]))
    return reg("buildings", m, building="storage")


def bld_kitchen():
    m = Model("bld_kitchen"); n = m.node("body")
    n.box((7.6, 0.1, 7.6), (0, 0.05, 0), "CONCRETE_D")
    for x, z in ((-3.4, -3.4), (3.4, -3.4), (-3.4, 3.4), (3.4, 3.4)):
        n.cyl(0.08, 2.6, (x, 1.3, z), "WOOD", sections=5, rot=UP)
    n.roof((7.8, 1.0, 7.8), (0, 2.6, 0), "TARP_GREEN")
    n.cyl(0.6, 1.4, (-1.8, 1.1, -1.5), "OLIVE", sections=10, rot=ALONG_X)  # полевая кухня-котёл
    n.box((2.4, 0.4, 1.4), (-1.8, 0.4, -1.5), "OLIVE_D")
    n.cyl(0.12, 2.6, (-2.3, 2.6, -1.5), "GUNMETAL", sections=5, rot=UP)    # труба
    for z in (0.6, 2.4):
        n.box((4.0, 0.08, 0.9), (1.0, 0.8, z), "WOOD_L")               # столы
        n.box((4.0, 0.08, 0.3), (1.0, 0.45, z + 0.7), "WOOD")
        n.box((4.0, 0.08, 0.3), (1.0, 0.45, z - 0.7), "WOOD")
    return reg("buildings", m, building="kitchen")


def bld_greenhouse():
    m = Model("bld_greenhouse"); n = m.node("body")
    n.box((9.6, 0.5, 15.6), (0, 0.25, 0), "CONCRETE_D")
    n.box((9.4, 1.2, 15.4), (0, 1.1, 0), "GLASS")
    n.roof((9.4, 2.0, 15.4), (0, 1.7, 0), "GLASS")
    for x in (-3, 0, 3):
        n.box((1.2, 0.5, 13.5), (x, 0.75, 0), "DIRT")
        for z in range(-6, 7, 2):
            n.ball(0.45, (x, 1.15, z), "LEAF", subdiv=0)
    for z in range(-7, 8, 3):
        n.box((9.5, 0.1, 0.1), (0, 1.75, z), "STEEL")
    return reg("buildings", m, building="greenhouse")


def bld_sawmill():
    m = Model("bld_sawmill"); n = m.node("body")
    n.box((9.6, 0.1, 9.6), (0, 0.05, 0), "DIRT")
    for x, z in ((-3.5, -2.5), (3.5, -2.5), (-3.5, 2.5), (3.5, 2.5)):
        n.box((0.25, 3.2, 0.25), (x, 1.6, z), "WOOD")
    n.roof((8.0, 1.2, 6.2), (0, 3.2, 0), "ROOF_D", rot=(0, 90, 0))
    n.box((4.5, 0.9, 1.2), (0, 0.45, 0), "STEEL")                  # пильный стол
    n.cyl(0.6, 0.06, (0, 1.0, 0), "STEEL_D", sections=12, rot=ALONG_X)
    for row in range(3):
        for i in range(4 - row):
            n.cyl(0.25, 3.6, (-3.0 + i * 0.5 + row * 0.25, 0.25 + row * 0.43, 4.3), "BARK", sections=7, rot=ALONG_X)
    for i in range(5):
        n.box((3.2, 0.08, 0.3), (2.6, 0.1 + i * 0.1, -4.2 + (i % 2) * 0.1), "WOOD_L")  # доски
    return reg("buildings", m, building="sawmill")


def bld_scrapyard():
    m = Model("bld_scrapyard"); n = m.node("body")
    n.box((9.6, 0.1, 9.6), (0, 0.05, 0), "DIRT")
    for sx in (-1, 1):
        n.box((0.1, 2.0, 9.6), (sx * 4.8, 1.0, 0), "STEEL")
    n.box((9.6, 2.0, 0.1), (0, 1.0, -4.8), "STEEL")
    rnd = random.Random(5)
    for i in range(16):
        n.box((rnd.uniform(0.6, 1.6), rnd.uniform(0.3, 0.9), rnd.uniform(0.6, 1.8)),
              (rnd.uniform(-3.5, 1), rnd.uniform(0.2, 1.6), rnd.uniform(-3.5, 1.5)),
              rnd.choice(["RUST", "CAR_RED", "CAR_BLUE", "STEEL", "RUST"]), rot=(0, rnd.uniform(0, 90), rnd.uniform(-15, 15)))
    n.box((0.5, 5.0, 0.5), (3.0, 2.5, 3.0), "HAZARD_YELLOW")       # кран
    arm = m.node("crane_arm", pivot=(3.0, 5.0, 3.0))
    arm.box((0.3, 0.3, 6.0), (3.0, 5.1, 0.5), "HAZARD_YELLOW")
    arm.box((0.05, 2.0, 0.05), (3.0, 4.0, -2.3), "GUNMETAL")
    arm.box((0.7, 0.2, 0.7), (3.0, 3.0, -2.3), "STEEL_D")         # магнит
    return reg("buildings", m, building="scrapyard")


def bld_generator():
    m = Model("bld_generator"); n = m.node("body")
    n.box((5.6, 0.2, 5.6), (0, 0.1, 0), "CONCRETE_D")
    n.box((4.0, 2.3, 2.3), (0, 1.35, -0.6), "OLIVE")
    n.box((4.05, 0.15, 2.35), (0, 2.5, -0.6), "OLIVE_D")
    n.cyl(0.15, 1.6, (1.4, 3.2, -1.2), "GUNMETAL", sections=6, rot=UP)
    n.box((0.6, 0.5, 0.05), (-1.2, 1.5, 0.56), "HAZARD_YELLOW")
    for row in range(2):
        for i in range(4):
            n.cyl(0.18, 1.6, (-1.0 + i * 0.38, 0.28 + row * 0.33, 1.6), "BARK", sections=6, rot=ALONG_X)
    return reg("buildings", m, building="generator")


def bld_solar():
    m = Model("bld_solar"); n = m.node("body")
    for i, z in enumerate((-1.6, 0.4, 2.4)):
        n.box((0.1, 0.9, 0.1), (-2, 0.45, z), "STEEL"); n.box((0.1, 0.9, 0.1), (2, 0.45, z), "STEEL")
        n.box((5.0, 0.08, 1.6), (0, 1.05, z - 0.3), "SOLAR_BLUE", rot=(-25, 0, 0))
    return reg("buildings", m, building="solar")


def bld_battery():
    m = Model("bld_battery"); n = m.node("body")
    n.box((3.6, 0.15, 3.6), (0, 0.08, 0), "CONCRETE_D")
    for x in (-0.9, 0.9):
        n.box((1.4, 2.0, 2.4), (x, 1.15, 0), "CONCRETE_L")
        n.box((0.3, 0.15, 0.04), (x, 1.8, 1.22), "GREEN_LIGHT")
    n.box((0.6, 0.4, 0.04), (0, 1.3, 1.25), "HAZARD_YELLOW")
    return reg("buildings", m, building="battery")


def red_cross(n, y, size=2.0, pos=(0, 0)):
    n.box((size, 0.06, size * 0.3), (pos[0], y, pos[1]), "RED_CROSS")
    n.box((size * 0.3, 0.06, size), (pos[0], y, pos[1]), "RED_CROSS")


def bld_medpost():
    m = Model("bld_medpost"); n = m.node("body")
    n.box((7.6, 0.15, 9.6), (0, 0.08, 0), "CONCRETE_L")
    n.box((6.4, 2.4, 8.4), (0, 1.35, 0), "MEDIC_WHITE")
    n.roof((6.6, 1.4, 8.6), (0, 2.55, 0), "MEDIC_WHITE")
    red_cross(n, 3.55, 2.0)
    n.box((0.05, 1.2, 1.2), (3.23, 1.6, 0), "RED_CROSS")
    n.box((0.05, 0.36, 1.2), (3.24, 1.6, 0), "WHITE")
    n.box((1.4, 2.0, 0.1), (0, 1.1, 4.25), "CIV_GREY")
    n.box((0.6, 0.9, 1.8), (2.6, 0.5, 5.2), "WHITE")  # носилки/каталка
    return reg("buildings", m, building="medpost")


def bld_quarantine():
    m = Model("bld_quarantine"); n = m.node("body")
    n.box((7.6, 0.1, 7.6), (0, 0.05, 0), "CONCRETE_D")
    n.box((5.0, 2.6, 4.0), (0, 1.4, -1.0), "CONCRETE_L")
    for i in range(5):
        n.box((0.5, 0.3, 0.05), (-2.0 + i * 1.0, 2.5, 1.03), "HAZARD_YELLOW" if i % 2 == 0 else "BLACK")
    for sx in (-1, 1):
        n.box((0.06, 2.4, 7.4), (sx * 3.7, 1.2, 0), "STEEL")    # сетка-забор
    n.box((7.4, 2.4, 0.06), (0, 1.2, 3.7), "STEEL")
    n.box((0.6, 0.6, 0.05), (0, 1.8, 1.05), "INFECT_GLOW")
    return reg("buildings", m, building="quarantine")


def bld_checkpoint():
    m = Model("bld_checkpoint"); n = m.node("body")
    n.box((2.2, 2.6, 2.2), (-1.8, 1.3, 0), "CONCRETE_L")
    n.box((2.3, 0.2, 2.3), (-1.8, 2.7, 0), "CONCRETE_D")
    n.box((0.05, 0.8, 1.4), (-0.69, 1.6, 0), "GLASS")
    for z in (-3.2, 3.2):
        n.box((1.2, 0.8, 0.6), (1.0, 0.4, z), "CONCRETE")
    n.box((0.3, 1.1, 0.3), (-0.5, 0.55, 2.4), "STEEL")
    bar = m.node("barrier", pivot=(-0.5, 1.0, 2.4))
    for i in range(6):
        bar.box((0.12, 0.12, 0.8), (-0.5, 1.0, 2.0 - i * 0.8), "RED_CROSS" if i % 2 else "WHITE")
    sandbag_row(n, -1.8, -2.0, 2.4)
    return reg("buildings", m, building="checkpoint")


def bld_barracks():
    m = Model("bld_barracks"); n = m.node("body")
    n.box((11.6, 0.2, 11.6), (0, 0.1, 0), "CONCRETE_D")
    n.box((10.0, 6.0, 7.0), (0, 3.1, -1.5), "BRICK")
    n.box((10.2, 0.3, 7.2), (0, 6.2, -1.5), "CONCRETE_D")
    for y in (2.0, 4.6):
        windows_row(n, -4.8, 4.8, y, 2.02, step=1.9, w=1.0, h=1.2)
    n.box((2.0, 2.4, 0.2), (0, 1.3, 2.1), "STEEL_D")
    n.box((3.0, 0.15, 1.2), (0, 2.7, 2.6), "CONCRETE_D")       # козырёк
    flag(n, 4.5, 4.2, 7)
    sandbag_row(n, -3.0, 4.3, 3.0); sandbag_row(n, 3.0, 4.3, 3.0)
    for i in range(3):
        n.box((0.9, 0.5, 0.6), (-4.5 + i * 1.0, 0.45, 4.8), "OLIVE")  # ящики
    return reg("buildings", m, building="barracks")


def bld_motorpool():
    m = Model("bld_motorpool"); n = m.node("body")
    n.box((15.6, 0.2, 15.6), (0, 0.1, 0), "CONCRETE")
    for x in (-7, -2.3, 2.3, 7):
        for z in (-6, 0, 6):
            n.box((0.35, 5.0, 0.35), (x, 2.6, z), "STEEL")
    n.box((14.6, 0.3, 13.0), (0, 5.2, 0), "STEEL_D")
    for x in (-4.6, 0, 4.6):
        n.box((0.2, 0.02, 12), (x, 0.21, 0), "HAZARD_YELLOW")
    for i in range(4):
        n.cyl(0.35, 1.0, (6.8, 0.6, -7.2 + i * 0.75), "CAR_BLUE" if i % 2 else "RUST", sections=8, rot=UP)
    n.box((3.0, 0.8, 1.2), (-6.0, 0.5, -7.0), "OLIVE")             # верстак
    flag(n, 7.6, 7.6, 7)
    return reg("buildings", m, building="motorpool")


def bld_helipad():
    m = Model("bld_helipad"); n = m.node("body")
    n.box((15.6, 0.3, 15.6), (0, 0.15, 0), "CONCRETE")
    n.cyl(5.5, 0.02, (0, 0.31, 0), "HAZARD_YELLOW", sections=24, rot=UP)
    n.cyl(5.1, 0.03, (0, 0.32, 0), "CONCRETE", sections=24, rot=UP)
    n.box((0.7, 0.04, 4.0), (-1.3, 0.35, 0), "WHITE"); n.box((0.7, 0.04, 4.0), (1.3, 0.35, 0), "WHITE")
    n.box((2.0, 0.04, 0.7), (0, 0.35, 0), "WHITE")
    for x in (-7.4, 7.4):
        for z in (-7.4, 7.4):
            n.cyl(0.15, 0.4, (x, 0.5, z), "LIGHT_WARM", sections=6, rot=UP)
    n.cyl(0.05, 4.0, (7.5, 2.0, -7.5), "STEEL", sections=5, rot=UP)
    n.cyl(0.25, 1.2, (7.5, 3.8, -6.9), "SIGNAL_ORANGE", sections=6, r2=0.12)  # колдун
    for i in range(3):
        n.cyl(0.35, 1.0, (-7.0 + i * 0.8, 0.8, 7.0), "OLIVE", sections=8, rot=UP)  # бочки топлива
    return reg("buildings", m, building="helipad")


def bld_workshop():
    m = Model("bld_workshop"); n = m.node("body")
    n.box((9.6, 0.2, 11.6), (0, 0.1, 0), "CONCRETE_D")
    n.box((8.6, 4.0, 10.0), (0, 2.2, 0), "PANEL_BEIGE")
    for z in (-3.75, -1.25, 1.25, 3.75):                          # шедовая крыша
        n.wedge((8.6, 1.4, 2.5), (0, 4.2, z), "ROOF_D", slope="front")
        n.box((8.0, 1.1, 0.06), (0, 4.75, z + 1.18), "GLASS")
    n.box((3.2, 3.0, 0.1), (0, 1.7, 5.05), "STEEL")
    n.cyl(0.05, 4.0, (-3.5, 7.0, -4.0), "STEEL", sections=5, rot=UP)
    n.box((1.4, 0.9, 0.8), (3.2, 0.55, 6.0), "OLIVE")
    return reg("buildings", m, building="workshop")


def bld_wall_wood():
    m = Model("bld_wall_wood"); n = m.node("body")
    for x in (-1.9, 0, 1.9):
        n.box((0.25, 2.8, 0.25), (x, 1.4, 0), "BARK")
    for i in range(5):
        n.box((4.0, 0.45, 0.12), (0, 0.3 + i * 0.5, 0.15 * (1 if i % 2 else -1)), "WOOD" if i % 2 else "WOOD_L")
    n.box((0.15, 2.4, 0.12), (0, 1.3, 0.25), "WOOD")              # раскос
    return reg("buildings", m, building="wall_wood")


def bld_wall_concrete():
    m = Model("bld_wall_concrete"); n = m.node("body")
    n.box((4.0, 1.2, 0.8), (0, 0.6, 0), "CONCRETE")
    n.box((4.0, 1.2, 0.6), (0, 1.8, 0), "CONCRETE_L")
    n.box((4.0, 0.12, 0.62), (0, 2.45, 0), "CONCRETE_D")
    for x in (-1.5, 1.5):
        n.box((0.3, 0.3, 0.04), (x, 1.9, 0.32), "HAZARD_YELLOW")
    return reg("buildings", m, building="wall_concrete")


def bld_gate():
    m = Model("bld_gate"); n = m.node("body")
    for x in (-3.1, 3.1):
        n.box((0.5, 3.4, 0.5), (x, 1.7, 0), "CONCRETE")
    for side, sx in (("door_l", -1), ("door_r", 1)):
        d = m.node(side, pivot=(sx * 2.85, 0, 0))
        d.box((2.8, 2.6, 0.15), (sx * 1.45, 1.4, 0), "STEEL")
        d.box((2.8, 0.15, 0.2), (sx * 1.45, 0.6, 0.05), "STEEL_D")
        d.box((2.8, 0.15, 0.2), (sx * 1.45, 2.2, 0.05), "STEEL_D")
        d.box((0.6, 0.3, 0.04), (sx * 1.45, 1.4, 0.1), "TEAM")
    return reg("buildings", m, building="gate")


def bld_tower():
    m = Model("bld_tower"); n = m.node("body")
    for x in (-1.5, 1.5):
        for z in (-1.5, 1.5):
            n.box((0.2, 5.0, 0.2), (x, 2.5, z), "BARK")
    n.box((3.6, 0.2, 3.6), (0, 5.0, 0), "WOOD")
    for x, z, w, d in ((0, 1.75, 3.6, 0.1), (0, -1.75, 3.6, 0.1), (1.75, 0, 0.1, 3.6), (-1.75, 0, 0.1, 3.6)):
        n.box((w, 1.0, d), (x, 5.6, z), "WOOD_L")
    for x in (-1.6, 1.6):
        for z in (-1.6, 1.6):
            n.box((0.12, 1.6, 0.12), (x, 6.9, z), "BARK")
    n.roof((4.0, 1.0, 4.0), (0, 7.7, 0), "TARP_GREEN")
    n.box((0.15, 4.8, 0.6), (0.9, 2.4, 1.8), "WOOD")              # лестница
    sandbag_row(n, 0, 1.55, 3.2, layers=1)
    return reg("buildings", m, building="tower")


def bld_floodlight():
    m = Model("bld_floodlight"); n = m.node("body")
    n.box((0.8, 0.2, 0.8), (0, 0.1, 0), "CONCRETE_D")
    n.cyl(0.08, 5.0, (0, 2.6, 0), "STEEL", sections=6, rot=UP)
    lamp = m.node("lamp", pivot=(0, 5.0, 0))
    lamp.box((0.9, 0.6, 0.5), (0, 5.1, 0.1), "STEEL_D")
    lamp.box((0.8, 0.5, 0.05), (0, 5.05, 0.37), "LIGHT_EMIT")
    lamp.rest_rot = (25, 0, 0)
    return reg("buildings", m, building="floodlight")


def bld_siren():
    m = Model("bld_siren"); n = m.node("body")
    n.box((0.8, 0.2, 0.8), (0, 0.1, 0), "CONCRETE_D")
    n.cyl(0.08, 5.5, (0, 2.85, 0), "STEEL", sections=6, rot=UP)
    head = m.node("speakers", pivot=(0, 5.4, 0))
    for a in (0, 120, 240):
        c = trimesh.creation.cone(radius=0.35, height=0.8, sections=8)
        c.apply_transform(_rot_matrix((180, 0, 0)))
        c.apply_translation((0, 0, 0.9))
        c.apply_transform(_rot_matrix((0, a, 0)))
        c.apply_translation((0, 5.4, 0))
        head.add(c, "STEEL_D")
    head.box((0.25, 0.25, 0.25), (0, 5.4, 0), "SIGNAL_ORANGE")
    return reg("buildings", m, building="siren")


def bld_sandbags():
    m = Model("bld_sandbags"); n = m.node("body")
    sandbag_row(n, 0, 0, 4.0, layers=3)
    return reg("buildings", m, building="sandbags")


# ======================================================================================
# ГОРОД И ПРОПСЫ
# ======================================================================================

def city_panel(name, sections, floors, depth=12.0, color="PANEL_WHITE", accent="TILE_BLUE", sec_w=13.0):
    m = Model(name); n = m.node("body")
    W = sections * sec_w; H = floors * 2.8 + 0.6
    n.box((W, H, depth), (0, H / 2, 0), color)
    n.box((W + 0.2, 0.5, depth + 0.2), (0, H + 0.25, 0), "CONCRETE_D")
    for f in range(floors):
        y = 1.5 + f * 2.8
        for face in (1, -1):
            x = -W / 2 + 1.1
            while x < W / 2 - 0.8:
                n.box((1.3, 1.3, 0.08), (x, y, face * (depth / 2 + 0.01)), "GLASS" if (f + int(x)) % 5 else "LIGHT_WARM")
                x += 2.2
        n.box((W + 0.02, 0.18, depth + 0.02), (0, 0.35 + f * 2.8, 0), accent if f % 3 == 0 else color)
    for s in range(sections):  # подъезды + балконы
        x = -W / 2 + sec_w / 2 + s * sec_w
        n.box((1.6, 2.4, 0.6), (x, 1.2, depth / 2 + 0.3), "CONCRETE_D")
        n.box((2.0, 0.15, 1.0), (x, 2.5, depth / 2 + 0.5), "CONCRETE")
        for f in range(1, floors):
            n.box((2.6, 1.0, 1.0), (x + 3.5, 0.5 + f * 2.8, depth / 2 + 0.5), color)
        n.box((2.2, 2.2, 2.2), (x, H + 1.1, 0), "CONCRETE_D")  # машинное отделение
    return reg("city", m, city="residential")


def city_stalinka():
    m = Model("city_stalinka"); n = m.node("body")
    W, D, H = 42, 16, 24
    n.box((W, H, D), (0, H / 2, 0), "STALIN_YEL")
    n.box((W, 4.0, D + 0.2), (0, 2.0, 0), "BRICK")                     # цоколь-магазины
    n.box((W + 0.8, 0.8, D + 0.8), (0, H + 0.4, 0), "WHITE")            # карниз
    for f in range(7):
        y = 5.4 + f * 2.7
        x = -W / 2 + 1.5
        while x < W / 2 - 1:
            n.box((1.1, 1.6, 0.08), (x, y, D / 2 + 0.01), "GLASS")
            x += 2.4
    n.box((10, 8, 10), (0, H + 4.8, 0), "STALIN_YEL")                   # центральная башенка
    n.box((10.6, 0.6, 10.6), (0, H + 9.0, 0), "WHITE")
    n.cyl(3.5, 6.0, (0, H + 12.3, 0), "STALIN_YEL", sections=8, rot=UP, r2=0.4)
    n.cyl(0.15, 4.0, (0, H + 17, 0), "LEAF_AUTUMN", sections=5, rot=UP)  # шпиль
    for x in range(-18, 19, 6):
        n.box((5.0, 3.0, 0.1), (x, 1.9, D / 2 + 0.12), "CHARCOAL")       # витрины
    return reg("city", m, city="landmark")


def city_shop():
    m = Model("city_shop"); n = m.node("body")
    n.box((12, 4, 8), (0, 2, 0), "PANEL_BEIGE")
    n.box((12.2, 0.3, 8.2), (0, 4.15, 0), "ROOF_D")
    n.box((10, 1.0, 0.2), (0, 3.3, 4.1), "CIV_RED")                    # вывеска (без текста)
    n.box((8, 2.2, 0.08), (0, 1.3, 4.04), "GLASS")
    n.box((1.8, 2.3, 0.1), (0, 1.15, 4.1), "STEEL_D")
    return reg("city", m, city="poi_grocery")


def city_metro_entrance():
    m = Model("city_metro_entrance"); n = m.node("body")
    n.box((14, 0.3, 10), (0, 0.15, 0), "CONCRETE_L")
    n.box((10, 5.0, 7), (0, 2.8, 0), "CONCRETE_L")
    n.box((10.6, 0.6, 7.6), (0, 5.6, 0), "WHITE")
    for x in (-3.5, -1.2, 1.2, 3.5):
        n.box((0.6, 4.5, 0.6), (x, 2.5, 3.8), "WHITE")                  # колонны
    n.box((6, 3.0, 0.1), (0, 1.8, 3.52), "CHARCOAL")
    n.box((1.4, 1.4, 0.2), (0, 6.6, 3.0), "RED_CROSS")                   # красный знак (без логотипа)
    n.box((3.0, 0.6, 0.04), (0, 0.5, 3.6), "NEST_FLESH")                 # следы заражения у входа
    n.ball(0.9, (2.5, 0.4, 4.6), "NEST_FLESH", subdiv=1, scale=(1, 0.5, 1))
    return reg("city", m, city="poi_metro")


def city_substation():
    m = Model("city_substation"); n = m.node("body")
    n.box((20, 0.2, 14), (0, 0.1, 0), "DIRT")
    n.box((6, 4, 5), (-6, 2, -3), "BRICK_L")
    for i in range(3):
        n.box((2.5, 3.0, 2.5), (1 + i * 3.5, 1.6, -3), "STEEL")
        n.cyl(0.25, 1.5, (1 + i * 3.5, 3.9, -3), "CONCRETE_L", sections=6, rot=UP)
    for x in (-8, 0, 8):
        n.box((0.3, 9, 0.3), (x, 4.5, 4), "STEEL")
    n.box((17, 0.25, 0.25), (0, 8.5, 4), "STEEL")
    for sx in (-1, 1):
        n.box((0.05, 2.2, 14), (sx * 10, 1.1, 0), "STEEL")
    n.box((20, 2.2, 0.05), (0, 1.1, 7), "STEEL")
    n.box((0.8, 0.8, 0.05), (-6, 2.5, -0.47), "HAZARD_YELLOW")
    return reg("city", m, city="poi_substation")


def tree(name, kind):
    m = Model(name); n = m.node("body")
    if kind == "birch":
        n.cyl(0.14, 5.5, (0, 2.75, 0), "BIRCH", sections=6, rot=UP)
        for i, (y, r) in enumerate(((4.6, 1.5), (6.0, 1.2), (7.0, 0.8))):
            n.ball(r, (0.2 * (i % 2), y, 0), "LEAF_AUTUMN" if i != 1 else "LEAF", subdiv=0, scale=(1, 1.3, 1))
    elif kind == "poplar":
        n.cyl(0.2, 3, (0, 1.5, 0), "BARK", sections=6, rot=UP)
        n.cone(1.6, 10, (0, 7.5, 0), "LEAF", sections=7, rot=UP)
    elif kind == "linden":
        n.cyl(0.25, 3.5, (0, 1.75, 0), "BARK", sections=6, rot=UP)
        n.ball(2.6, (0, 5.0, 0), "LEAF_AUTUMN", subdiv=1, scale=(1, 0.85, 1))
        n.ball(1.6, (1.2, 6.2, 0.4), "LEAF_RED", subdiv=0)
    elif kind == "pine":
        n.cyl(0.18, 2.5, (0, 1.25, 0), "BARK", sections=6, rot=UP)
        for i, (y, r) in enumerate(((3.0, 2.0), (4.8, 1.6), (6.4, 1.1))):
            n.cone(r, 2.6, (0, y, 0), "PINE", sections=7, rot=UP)
    return reg("props", m, prop="tree", resource={"wood": 40})


def car(name, color, kind="sedan", burnt=False):
    m = Model(name); n = m.node("body")
    c = "RUST" if burnt else color
    if kind == "sedan":
        n.box((1.7, 0.7, 4.1), (0, 0.65, 0), c)
        n.box((1.5, 0.55, 2.0), (0, 1.25, -0.2), c)
        n.box((1.45, 0.45, 0.06), (0, 1.25, 0.82), "CHARCOAL" if burnt else "GLASS")
        n.box((1.45, 0.45, 0.06), (0, 1.25, -1.22), "CHARCOAL" if burnt else "GLASS")
        wheels = [(-0.8, 1.3), (0.8, 1.3), (-0.8, -1.3), (0.8, -1.3)]
    elif kind == "bus":
        n.box((2.5, 2.6, 11.5), (0, 1.75, 0), c)
        for z in range(-5, 5, 2):
            n.box((2.52, 1.0, 1.6), (0, 2.3, z + 0.5), "CHARCOAL" if burnt else "GLASS")
        n.box((2.3, 1.3, 0.06), (0, 2.2, 5.76), "CHARCOAL" if burnt else "GLASS")
        n.cyl(0.03, 3.0, (0.5, 4.0, -2.5), "GUNMETAL", sections=4, rot=(-60, 0, 0))  # штанги троллейбуса
        n.cyl(0.03, 3.0, (-0.5, 4.0, -2.5), "GUNMETAL", sections=4, rot=(-60, 0, 0))
        wheels = [(-1.1, 3.8), (1.1, 3.8), (-1.1, -3.5), (1.1, -3.5)]
    else:  # truck
        n.box((2.3, 2.0, 2.0), (0, 1.5, 2.6), c)
        n.box((2.4, 2.4, 5.0), (0, 1.9, -1.2), "OLIVE" if not burnt else "RUST")
        n.box((2.1, 0.8, 0.06), (0, 2.0, 3.62), "CHARCOAL" if burnt else "GLASS")
        wheels = [(-1.0, 2.6), (1.0, 2.6), (-1.0, -1.0), (1.0, -1.0), (-1.0, -2.6), (1.0, -2.6)]
    for x, z in wheels:
        n.cyl(0.4, 0.3, (x, 0.4, z), "TIRE", sections=8, rot=ALONG_X)
    return reg("props", m, prop="wreck", resource={"iron": 60})


def props_misc():
    m = Model("prop_streetlight"); n = m.node("body")
    n.cyl(0.08, 8, (0, 4, 0), "STEEL_D", sections=6, rot=UP)
    n.box((0.15, 0.15, 1.8), (0, 8, 0.9), "STEEL_D")
    n.box((0.4, 0.15, 0.6), (0, 7.9, 1.8), "LIGHT_WARM")
    reg("props", m, prop="decor")

    m = Model("prop_hedgehog"); n = m.node("body")  # противотанковый ёж
    for rot in ((0, 0, 55), (0, 0, -55), (55, 0, 0), (-55, 0, 0)):
        n.box((0.15, 2.2, 0.15), (0, 0.8, 0), "RUST", rot=rot)
    reg("props", m, prop="barricade")

    m = Model("prop_concrete_block"); n = m.node("body")
    n.box((2.0, 0.9, 0.8), (0, 0.45, 0), "CONCRETE")
    n.box((2.0, 0.15, 0.4), (0, 0.98, 0), "CONCRETE_L")
    reg("props", m, prop="barricade")

    m = Model("prop_bus_stop"); n = m.node("body")
    n.box((4.0, 0.12, 1.6), (0, 2.6, 0), "STEEL_D")
    n.box((4.0, 2.4, 0.06), (0, 1.3, -0.75), "GLASS")
    for x in (-1.9, 1.9):
        n.box((0.1, 2.6, 0.1), (x, 1.3, -0.7), "STEEL_D")
    n.box((2.4, 0.08, 0.4), (0, 0.5, -0.4), "WOOD")
    reg("props", m, prop="decor")

    m = Model("prop_dumpster"); n = m.node("body")
    n.box((1.8, 1.2, 1.1), (0, 0.65, 0), "TILE_TEAL")
    n.box((1.85, 0.08, 1.15), (0, 1.3, -0.05), "STEEL_D", rot=(-10, 0, 0))
    reg("props", m, prop="decor")

    m = Model("prop_bench"); n = m.node("body")
    n.box((1.8, 0.08, 0.5), (0, 0.45, 0), "WOOD")
    n.box((1.8, 0.4, 0.06), (0, 0.75, -0.24), "WOOD")
    for x in (-0.8, 0.8):
        n.box((0.08, 0.45, 0.5), (x, 0.22, 0), "GUNMETAL")
    reg("props", m, prop="decor")

    m = Model("prop_fence_section"); n = m.node("body")
    n.box((3.0, 1.8, 0.05), (0, 0.9, 0), "STEEL")
    for x in (-1.5, 1.5):
        n.box((0.08, 2.0, 0.08), (x, 1.0, 0), "STEEL_D")
    reg("props", m, prop="decor")


def pickups():
    m = Model("pickup_food"); n = m.node("body")
    n.box((0.9, 0.55, 0.6), (0, 0.28, 0), "OLIVE")
    n.box((0.9, 0.55, 0.6), (0.15, 0.83, 0.05), "WOOD_L", rot=(0, 15, 0))
    n.box((0.3, 0.2, 0.02), (0, 0.3, 0.31), "WHITE")
    reg("pickups", m, pickup="food")
    m = Model("pickup_wood"); n = m.node("body")
    for i, (x, y) in enumerate(((-0.25, 0.15), (0.05, 0.15), (0.35, 0.15), (-0.1, 0.42), (0.2, 0.42))):
        n.cyl(0.15, 1.6, (x, y, 0), "BARK", sections=6)
    reg("pickups", m, pickup="wood")
    m = Model("pickup_iron"); n = m.node("body")
    rnd = random.Random(11)
    for i in range(7):
        n.box((rnd.uniform(0.2, 0.6), rnd.uniform(0.08, 0.25), rnd.uniform(0.2, 0.7)),
              (rnd.uniform(-0.4, 0.4), 0.1 + i * 0.06, rnd.uniform(-0.3, 0.3)),
              rnd.choice(["RUST", "STEEL", "STEEL_D"]), rot=(rnd.uniform(-20, 20), rnd.uniform(0, 90), 0))
    reg("pickups", m, pickup="iron")
    m = Model("pickup_antidote"); n = m.node("body")
    n.box((0.6, 0.35, 0.4), (0, 0.18, 0), "MEDIC_WHITE")
    n.box((0.25, 0.04, 0.08), (0, 0.37, 0), "RED_CROSS"); n.box((0.08, 0.04, 0.25), (0, 0.37, 0), "RED_CROSS")
    reg("pickups", m, pickup="antidote")


def test_district():
    """Мини-квартал для прототипа до подключения OSM: 120×120 м, панельки, дороги, река, парк."""
    m = Model("city_test_district"); n = m.node("ground")
    n.box((120, 0.1, 120), (0, -0.05, 0), "GRASS")
    n.box((120, 0.12, 12), (0, 0.01, 0), "ASPHALT")              # проспект
    n.box((12, 0.12, 120), (-20, 0.01, 0), "ASPHALT")
    for z in range(-55, 60, 8):
        n.box((0.3, 0.13, 3), (-20, 0.02, z), "WHITE")
    for x in range(-55, 60, 8):
        n.box((3, 0.13, 0.3), (x, 0.02, 0), "WHITE")
    n.box((120, 0.05, 18), (0, -0.2, 50), "WATER")              # река
    n.box((120, 1.2, 1.2), (0, 0.0, 40.4), "CONCRETE")           # набережная
    b = m.node("buildings")
    # кварталы — простые коробки разной этажности (финальный город — из OSM)
    rnd = random.Random(42)
    blocks = [(-45, -35, 20, 14, 27, "PANEL_WHITE"), (5, -30, 38, 12, 27, "PANEL_WHITE"),
              (40, -32, 14, 14, 50, "PANEL_BEIGE"), (5, -12, 30, 10, 15, "BRICK_L"),
              (-45, 20, 18, 30, 24, "STALIN_YEL"), (12, 22, 36, 12, 15, "PANEL_BEIGE")]
    for x, z, w, d, h, col in blocks:
        b.box((w, h, d), (x, h / 2, z), col)
        b.box((w + 0.2, 0.4, d + 0.2), (x, h + 0.2, z), "CONCRETE_D")
        for f in range(int((h - 1.5) // 2.8)):
            b.box((w + 0.04, 0.9, d * 0.7), (x, f * 2.8 + 1.8, z), "GLASS" if col != "BRICK_L" else "CHARCOAL")
    t = m.node("trees")
    for i in range(30):
        x, z = rnd.uniform(30, 58), rnd.uniform(8, 36)
        t.cyl(0.15, 2.5, (x, 1.25, z), "BARK", sections=5, rot=UP)
        t.ball(1.6, (x, 3.4, z), rnd.choice(["LEAF", "LEAF_AUTUMN", "LEAF_AUTUMN"]), subdiv=0)
    rnd2 = random.Random(9)
    c = m.node("wrecks")
    for i in range(8):
        x = rnd2.uniform(-55, 55); col = rnd2.choice(["CAR_RED", "CAR_BLUE", "CAR_WHITE", "RUST"])
        c.box((1.7, 1.2, 4.1), (x, 0.6, rnd2.uniform(-4, 4)), col, rot=(0, rnd2.uniform(-40, 40), 0))
    return reg("city", m, city="test_district")


# ======================================================================================

def city_radio_mast():
    """Решётчатая радиомачта ~42 м (POI «Радиовышка»): четыре пояса, раскосы, тарелки."""
    m = Model("city_radio_mast"); n = m.node("body")
    n.box((8, 0.3, 8), (0, 0.15, 0), "CONCRETE_D")
    n.box((3, 2.6, 2.4), (2.6, 1.3, 2.6), "CONCRETE_L")                   # аппаратная
    levels = [0.3, 10, 20, 30, 40]
    for i in range(len(levels) - 1):
        y0, y1 = levels[i], levels[i + 1]
        r0, r1 = 2.2 - i * 0.45, 2.2 - (i + 1) * 0.45
        for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            a = np.array([sx * r0, y0, sz * r0]); b = np.array([sx * r1, y1, sz * r1])
            mid = (a + b) / 2; L = np.linalg.norm(b - a)
            seg = trimesh.creation.box(extents=(0.18, L, 0.18))
            d = (b - a) / L
            ax = np.cross([0, 1, 0], d); ang = math.acos(np.clip(d[1], -1, 1))
            if np.linalg.norm(ax) > 1e-6:
                seg.apply_transform(trimesh.transformations.rotation_matrix(ang, ax / np.linalg.norm(ax)))
            seg.apply_translation(mid)
            n.add(seg, "SIGNAL_ORANGE" if i % 2 else "WHITE")
        n.box((2 * r1 + 0.2, 0.15, 2 * r1 + 0.2), (0, y1, 0), "STEEL_D")
    n.cyl(0.06, 6, (0, 43, 0), "STEEL", sections=5, rot=UP)
    n.cyl(0.9, 0.3, (0.8, 34, 0.8), "WHITE", sections=10, rot=(-70, 45, 0))  # тарелки
    n.cyl(0.7, 0.3, (-0.8, 26, -0.6), "WHITE", sections=10, rot=(-70, -120, 0))
    n.box((0.3, 0.3, 0.3), (0, 46, 0), "RED_CROSS")                           # заградительный огонь
    return reg("city", m, city="poi_radio_tower")


def city_mgu():
    """Силуэт Главного здания МГУ (задник за картой, ~240 м): ступенчатая башня, шпиль, крылья."""
    m = Model("city_mgu"); n = m.node("body")
    n.box((90, 60, 40), (0, 30, 0), "STALIN_YEL")
    for sx in (-1, 1):
        n.box((70, 40, 30), (sx * 75, 20, 10), "STALIN_YEL")
        n.box((22, 70, 22), (sx * 115, 35, 10), "STALIN_YEL")
        n.cyl(6, 18, (sx * 115, 79, 10), "STALIN_YEL", sections=8, rot=UP, r2=1.5)
        n.cyl(0.6, 12, (sx * 115, 94, 10), "LEAF_AUTUMN", sections=5, rot=UP)
    for i, (w, h) in enumerate(((64, 40), (48, 36), (34, 30), (24, 20))):
        y0 = 60 + sum(hh for _, hh in ((64, 40), (48, 36), (34, 30), (24, 20))[:i])
        n.box((w, h, w * 0.7), (0, y0 + h / 2, 0), "STALIN_YEL")
        n.box((w + 2, 1.5, w * 0.7 + 2), (0, y0 + h, 0), "WHITE")
    n.cyl(8, 26, (0, 199, 0), "STALIN_YEL", sections=8, rot=UP, r2=2.5)
    n.cyl(0.9, 30, (0, 227, 0), "LEAF_AUTUMN", sections=6, rot=UP)            # шпиль
    n.ball(2.2, (0, 238, 0), "HAZARD_YELLOW", subdiv=0)                       # звезда (условно)
    return reg("city", m, city="landmark_backdrop")


def build_all():
    import characters, vehicles
    characters.build_all(reg)
    zmb_nest()
    vehicles.build_all(reg)
    for f in (bld_hq, bld_tent, bld_house, bld_storage, bld_kitchen, bld_greenhouse, bld_sawmill, bld_scrapyard,
              bld_generator, bld_solar, bld_battery, bld_medpost, bld_quarantine, bld_checkpoint, bld_barracks,
              bld_motorpool, bld_helipad, bld_workshop, bld_wall_wood, bld_wall_concrete, bld_gate, bld_tower,
              bld_floodlight, bld_siren, bld_sandbags):
        f()
    city_panel("city_panel_9fl", 3, 9)
    city_panel("city_panel_17fl", 1, 17, depth=16, color="PANEL_BEIGE", accent="TILE_TEAL", sec_w=18)
    city_panel("city_khrushchevka_5fl", 4, 5, color="BRICK_L", accent="BRICK", sec_w=12)
    city_stalinka(); city_shop(); city_metro_entrance(); city_substation(); city_radio_mast(); city_mgu()
    for nm, k in (("prop_tree_birch", "birch"), ("prop_tree_poplar", "poplar"), ("prop_tree_linden", "linden"),
                  ("prop_tree_pine", "pine")):
        tree(nm, k)
    car("prop_wreck_sedan_red", "CAR_RED"); car("prop_wreck_sedan_white", "CAR_WHITE")
    car("prop_wreck_sedan_burnt", "CAR_RED", burnt=True)
    car("prop_wreck_trolleybus", "CAR_BLUE", kind="bus"); car("prop_wreck_truck", "CAR_WHITE", kind="truck")
    props_misc(); pickups(); test_district()


def main():
    build_all()
    save_palette(ROOT / "assets" / "textures" / "palette.png")
    manifest = []
    for cat, fn, m in REG:
        p = OUT / cat / fn
        m.save(p)
        st = m.stats()
        manifest.append({"file": f"models/{cat}/{fn}", "category": cat, "nodes": m.order,
                         "tris": st["tris"], "size_m": st["size_m"], **m.meta})
        print(f"{cat:10s} {fn:34s} tris={st['tris']:5d} size={st['size_m']}")
    # чистим служебные мета-поля
    for e in manifest:
        for k in ("hip", "sh_y", "s", "w", "ax"):
            e.pop(k, None)
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1))
    print(len(manifest), "models")


if __name__ == "__main__":
    main()
