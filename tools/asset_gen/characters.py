"""
characters.py — гуманоиды v2: военные, мирные, зомби (заменяют плейсхолдеры v0.1 1:1 по именам файлов и узлов).

Отличия от v0.1: сужающийся торс и конечности (не кубики), колени/локти, кисти и ботинки, головы с челюстью,
носом и ушами; снаряжение по роду войск (6Б47, плитник с подсумками, АК-74/АКС-74У/СВД/ПМ), разные силуэты
мирных (пуховик, пальто, платок, худи), зомби с рваной одеждой, рёбрами и светящимися глазами.
Бюджеты (арт-библия §6): пехота/мирные ≤ 900 треугольников, зомби ≤ 500, громила/великан ≤ 1500.
Узлы: body, head, arm_l, arm_r, leg_l, leg_r, weapon (опц.) — пивоты в плече/бедре/шее.
"""
from __future__ import annotations

import math
import random

import numpy as np
import trimesh

from lowpoly import ALONG_X, UP, Model, _rot_matrix


# ----------------------------------------------------------------------------- примитивы

def _hull(pts):
    return trimesh.convex.convex_hull(np.asarray(pts, dtype=float))


def tbox(n, bw, bd, tw, td, h, base, color, rot=None, shift=(0.0, 0.0)):
    """Усечённая «коробка»: низ bw×bd, верх tw×td (смещён на shift по X/Z), высота h, от base вверх."""
    sx, sz = shift
    pts = [(-bw / 2, 0, -bd / 2), (bw / 2, 0, -bd / 2), (bw / 2, 0, bd / 2), (-bw / 2, 0, bd / 2),
           (-tw / 2 + sx, h, -td / 2 + sz), (tw / 2 + sx, h, -td / 2 + sz), (tw / 2 + sx, h, td / 2 + sz), (-tw / 2 + sx, h, td / 2 + sz)]
    m = _hull(pts)
    if rot is not None:
        m.apply_transform(_rot_matrix(rot))
    m.apply_translation(base)
    return n.add(m, color)


def bend(mesh, pivot, rot):
    """Поворот готового меша вокруг точки (статичный изгиб локтя/колена)."""
    m = mesh.copy()
    m.apply_translation(-np.asarray(pivot, dtype=float))
    m.apply_transform(_rot_matrix(rot))
    m.apply_translation(pivot)
    return m


def boxm(size, pos, rot=None):
    m = trimesh.creation.box(extents=size)
    if rot is not None:
        m.apply_transform(_rot_matrix(rot))
    m.apply_translation(pos)
    return m


def tboxm(bw, bd, tw, td, h, base):
    m = _hull([(-bw / 2, 0, -bd / 2), (bw / 2, 0, -bd / 2), (bw / 2, 0, bd / 2), (-bw / 2, 0, bd / 2),
               (-tw / 2, h, -td / 2), (tw / 2, h, -td / 2), (tw / 2, h, td / 2), (-tw / 2, h, td / 2)])
    m.apply_translation(base)
    return m


# ----------------------------------------------------------------------------- тело

ARM_POSES = {
    "down": ((4, 0, 7), (4, 0, -7), 0, 0),
    "rifle": ((-38, 0, 16), (-24, 0, -4), -62, -70),
    "pistol": ((6, 0, 7), (-78, 0, 0), 0, -10),
    "zombie": ((-82, 10, 0), (-70, -12, 0), -10, -25),
    "brute": ((-25, 0, 20), (-38, 0, -20), -30, -30),
    "back": ((26, 0, 18), (26, 0, -18), -20, -20),
    "carry": ((-45, 0, 6), (-45, 0, -6), -50, -50),
    "scream": ((40, 0, 35), (40, 0, -35), -10, -10),
}


def humanoid(name, *, s=1.0, w=1.0, skin="SKIN_A", top="OLIVE", pants="OLIVE_D", shoes="SHOE", hands=None,
             hunch=0.0, pose="down", head_tilt=0.0, stride=0.0, head_scale=1.08, bulky=1.0, coat=None, sleeve=None):
    """Человек ~1.8 м × s. Голова чуть крупнее (арт-библия §2). coat — полы пальто до колен (цвет)."""
    m = Model(name)
    hip = 0.9 * s
    knee = 0.5 * s
    sh_y = hip + 0.56 * s
    lx = 0.105 * w * s
    hands = hands or skin
    sleeve = sleeve or top
    for side, sx, st in (("l", -1, stride), ("r", 1, -stride)):
        leg = m.node(f"leg_{side}", pivot=(sx * lx, hip, 0))
        x = sx * lx
        tbox(leg, 0.15 * w * s, 0.16 * s, 0.2 * w * s, 0.21 * s, hip - knee, (x, knee, 0), pants)       # бедро
        tbox(leg, 0.12 * w * s, 0.13 * s, 0.15 * w * s, 0.16 * s, knee - 0.1 * s, (x, 0.1 * s, 0.01), pants)  # голень
        leg.box((0.15 * w * s, 0.11 * s, 0.28 * s), (x, 0.055 * s, 0.05 * s), shoes)                      # ботинок
        if st:
            leg.rest_rot = (st, 0, 0)
    body = m.node("body", pivot=(0, hip, 0))
    tbox(body, 0.34 * w * s, 0.2 * s, 0.33 * w * s, 0.21 * s, 0.14 * s, (0, hip - 0.06 * s, 0), pants)  # таз
    tbox(body, 0.33 * w * s * bulky, 0.2 * s * bulky, 0.46 * w * s * bulky, 0.25 * s * bulky, sh_y - hip - 0.06 * s,
         (0, hip + 0.06 * s, 0), top)                                                                   # торс
    tbox(body, 0.36 * w * s * bulky, 0.22 * s * bulky, 0.18 * s, 0.14 * s, 0.07 * s, (0, sh_y - 0.02 * s, 0), top)  # плечи
    if coat:
        tbox(body, 0.4 * w * s, 0.26 * s, 0.35 * w * s, 0.23 * s, 0.42 * s, (0, hip - 0.36 * s, 0), coat)  # полы
    if hunch:
        body.rest_rot = (hunch, 0, 0)
    head = m.node("head", parent="body", pivot=(0, sh_y, 0))
    hs = s * head_scale
    head.cyl(0.055 * s, 0.1 * s, (0, sh_y + 0.04 * s, 0), skin, sections=6, rot=UP)                     # шея
    hy = sh_y + 0.09 * s
    tbox(head, 0.2 * hs, 0.22 * hs, 0.25 * hs, 0.26 * hs, 0.13 * hs, (0, hy, 0), skin)                   # челюсть → скулы
    tbox(head, 0.25 * hs, 0.26 * hs, 0.22 * hs, 0.23 * hs, 0.14 * hs, (0, hy + 0.13 * hs, 0), skin)      # черепная коробка
    head.box((0.045 * hs, 0.06 * hs, 0.05 * hs), (0, hy + 0.12 * hs, 0.135 * hs), skin)                 # нос
    for sx in (-1, 1):
        head.box((0.03 * hs, 0.06 * hs, 0.05 * hs), (sx * 0.127 * hs, hy + 0.13 * hs, 0), skin)          # уши
    if head_tilt:
        head.rest_rot = (head_tilt, 0, 0)
    pl, pr, bl, br = ARM_POSES[pose]
    ax = 0.23 * w * s * bulky + 0.06 * s
    for side, sx, prot, eb in (("l", -1, pl, bl), ("r", 1, pr, br)):
        arm = m.node(f"arm_{side}", parent="body", pivot=(sx * ax, sh_y - 0.04 * s, 0))
        x = sx * ax
        top_y = sh_y - 0.04 * s
        elbow = (x, top_y - 0.29 * s, 0)
        arm.add(tboxm(0.1 * s, 0.11 * s, 0.13 * s, 0.13 * s, 0.31 * s, (x, top_y - 0.3 * s, 0)), sleeve)   # плечо
        fore = [tboxm(0.08 * s, 0.09 * s, 0.1 * s, 0.11 * s, 0.27 * s, (x, top_y - 0.56 * s, 0)),
                boxm((0.08 * s, 0.1 * s, 0.11 * s), (x, top_y - 0.62 * s, 0.01))]
        cols = [sleeve, hands]
        for mesh, c in zip(fore, cols):
            arm.add(bend(mesh, elbow, (eb, 0, 0)) if eb else mesh, c)
        arm.rest_rot = prot
    m.meta.update(hip=hip, sh_y=sh_y, s=s, w=w, ax=ax, hy=hy, hs=hs, bulky=bulky)
    return m


def head_top(m):
    return m.meta["hy"] + 0.27 * m.meta["hs"]


def eyes(m, color="INFECT_GLOW", dy=0.15, size=0.05):
    hs, hy = m.meta["hs"], m.meta["hy"]
    for x in (-0.055, 0.055):
        m.node("head").box((size * hs, 0.03 * hs, 0.02), (x * hs, hy + dy * hs, 0.128 * hs), color)


def hair(m, color, style="short"):
    hs, hy = m.meta["hs"], m.meta["hy"]
    h = m.node("head")
    top = head_top(m)
    if style == "short":
        h.box((0.24 * hs, 0.05 * hs, 0.25 * hs), (0, top - 0.005, -0.005), color)
        h.box((0.24 * hs, 0.09 * hs, 0.05 * hs), (0, top - 0.07 * hs, -0.11 * hs), color)
    elif style == "long":
        h.box((0.25 * hs, 0.06 * hs, 0.26 * hs), (0, top - 0.005, 0), color)
        tbox(h, 0.27 * hs, 0.09 * hs, 0.25 * hs, 0.07 * hs, 0.3 * hs, (0, top - 0.33 * hs, -0.1 * hs), color)
    elif style == "bald":
        h.box((0.25 * hs, 0.1 * hs, 0.06 * hs), (0, top - 0.12 * hs, -0.11 * hs), color)
    elif style == "scarf":  # платок
        tbox(h, 0.28 * hs, 0.29 * hs, 0.2 * hs, 0.2 * hs, 0.16 * hs, (0, top - 0.12 * hs, -0.01), color)
        h.box((0.1 * hs, 0.1 * hs, 0.04 * hs), (0, hy - 0.02 * hs, -0.12 * hs), color)


def helmet_6b47(m, color="HELMET"):
    hs, top = m.meta["hs"], head_top(m)
    h = m.node("head")
    h.cyl(0.15 * hs, 0.1 * hs, (0, top - 0.02 * hs, 0), color, sections=8, rot=UP, r2=0.11 * hs)
    h.cyl(0.162 * hs, 0.03 * hs, (0, top - 0.07 * hs, 0), color, sections=8, rot=UP)   # обод
    h.box((0.14 * hs, 0.04 * hs, 0.03 * hs), (0, top - 0.05 * hs, 0.15 * hs), "GUNMETAL")  # крепление ПНВ
    h.box((0.06 * hs, 0.04 * hs, 0.06 * hs), (0.14 * hs, top - 0.04 * hs, -0.03), "OLIVE_D")  # фонарь


def plate_carrier(m, color="OLIVE_D", pouches="OLIVE_L"):
    s, hip, sh, b = m.meta["s"], m.meta["hip"], m.meta["sh_y"], m.meta["bulky"]
    n = m.node("body")
    n.box((0.4 * s, 0.38 * s, 0.07 * s), (0, hip + 0.33 * s, 0.13 * s * b), color)
    n.box((0.4 * s, 0.38 * s, 0.07 * s), (0, hip + 0.33 * s, -0.13 * s * b), color)
    for sx in (-1, 1):
        n.box((0.07 * s, 0.05 * s, 0.3 * s), (sx * 0.13 * s, sh - 0.05 * s, 0), color)   # лямки
    if pouches:
        for x in (-0.12, 0.0, 0.12):
            n.box((0.1 * s, 0.13 * s, 0.07 * s), (x * s, hip + 0.22 * s, 0.19 * s * b), pouches)  # подсумки
    n.box((0.36 * s, 0.07 * s, 0.25 * s), (0, hip + 0.03 * s, 0), "GUNMETAL")  # ремень


def armband(m, color="TEAM", side="l"):
    s, ax, sh = m.meta["s"], m.meta["ax"], m.meta["sh_y"]
    sx = -1 if side == "l" else 1
    m.node(f"arm_{side}").box((0.14 * s, 0.07 * s, 0.14 * s), (sx * ax, sh - 0.2 * s, 0), color)


def backpack(m, color="OLIVE_D", size=(0.34, 0.42, 0.2), roll=None):
    s, hip = m.meta["s"], m.meta["hip"]
    n = m.node("body")
    z = -0.16 * s - size[2] / 2
    n.box(size, (0, hip + 0.33 * s, z), color)
    n.box((size[0] * 0.9, 0.07, size[2] * 1.05), (0, hip + 0.33 * s + size[1] / 2, z), color)  # клапан
    if roll:
        n.cyl(0.07, size[0] + 0.06, (0, hip + 0.33 * s - size[1] / 2 - 0.05, z), roll, sections=6, rot=ALONG_X)


def knee_pads(m, color="GUNMETAL"):
    s, lx = m.meta["s"], 0.105 * m.meta["w"] * m.meta["s"]
    for side, sx in (("l", -1), ("r", 1)):
        m.node(f"leg_{side}").box((0.14 * s, 0.1 * s, 0.05 * s), (sx * lx, 0.52 * s, 0.1 * s), color)


# ----------------------------------------------------------------------------- оружие

def _wpn_node(m, length):
    s, sh = m.meta["s"], m.meta["sh_y"]
    y = sh - 0.25 * s
    z = 0.28 * s
    return m.node("weapon", parent="body", pivot=(0.06 * s, y, z)), 0.06 * s, y, z


def ak(m, short=False, color="GUNMETAL", wood="WOOD"):
    L = 0.55 if short else 0.78
    w, x, y, z = _wpn_node(m, L)
    w.box((0.05, 0.09, 0.32), (x, y, z + 0.1), color)                        # ствольная коробка
    w.box((0.055, 0.07, 0.2), (x, y - 0.005, z + 0.33), wood if not short else color)  # цевьё
    w.cyl(0.014, L * 0.42, (x, y + 0.015, z + 0.33 + L * 0.2), color, sections=5)      # ствол
    w.box((0.035, 0.035, 0.05), (x, y + 0.015, z + 0.33 + L * 0.42), color)            # ДТК
    for k, (dz, dy, ang) in enumerate(((0.12, -0.1, 15), (0.16, -0.19, 30))):         # изогнутый магазин
        w.box((0.04, 0.1, 0.06), (x, y + dy, z + dz), "GUNMETAL", rot=(ang, 0, 0))
    w.box((0.035, 0.1, 0.04), (x, y - 0.08, z - 0.02), color, rot=(-15, 0, 0))         # рукоять
    if short:
        w.box((0.02, 0.04, 0.22), (x, y + 0.02, z - 0.15), color)                       # складной приклад
    else:
        w.box((0.045, 0.1, 0.24), (x, y - 0.03, z - 0.17), wood, rot=(8, 0, 0))         # приклад
    w.box((0.03, 0.03, 0.06), (x, y + 0.065, z + 0.17), color)                          # прицел


def svd(m):
    w, x, y, z = _wpn_node(m, 1.2)
    w.box((0.05, 0.08, 0.4), (x, y, z + 0.12), "GUNMETAL")
    w.box((0.055, 0.07, 0.3), (x, y - 0.005, z + 0.45), "WOOD")
    w.cyl(0.013, 0.55, (x, y + 0.01, z + 0.85), "GUNMETAL", sections=5)
    w.box((0.04, 0.12, 0.06), (x, y - 0.1, z + 0.2), "GUNMETAL")                       # магазин
    w.box((0.045, 0.12, 0.28), (x, y - 0.04, z - 0.2), "WOOD", rot=(6, 0, 0))           # приклад-скелет
    w.cyl(0.03, 0.26, (x, y + 0.085, z + 0.14), "BLACK", sections=6)                  # ПСО-1
    w.cyl(0.036, 0.03, (x, y + 0.085, z + 0.28), "GLASS", sections=6)
    for sx in (-1, 1):                                                                # сошки
        w.box((0.012, 0.2, 0.012), (x + sx * 0.03, y - 0.1, z + 0.7), "GUNMETAL", rot=(20, 0, sx * 15))


def pistol(m):
    s, ax, sh = m.meta["s"], m.meta["ax"], m.meta["sh_y"]
    w = m.node("weapon", parent="arm_r", pivot=(ax, sh - 0.66 * s, 0.03))
    w.box((0.04, 0.05, 0.17), (ax, sh - 0.64 * s, 0.08), "GUNMETAL")
    w.box((0.035, 0.09, 0.04), (ax, sh - 0.69 * s, 0.03), "GUNMETAL", rot=(-15, 0, 0))


# ----------------------------------------------------------------------------- военные

def unit_assault():
    m = humanoid("unit_assault", pose="rifle", top="OLIVE", pants="OLIVE_D", hands="GUNMETAL", shoes="SHOE")
    helmet_6b47(m); plate_carrier(m); armband(m); ak(m); knee_pads(m)
    backpack(m, size=(0.3, 0.3, 0.14))
    s, hip = 1.0, m.meta["hip"]
    m.node("body").box((0.08, 0.1, 0.06), (0.18, hip + 0.42, 0.2), "OLIVE_L")   # рация на плитнике
    return m


def unit_sniper():
    m = humanoid("unit_sniper", pose="rifle", top="CAMO_BROWN", pants="OLIVE_D", hands="OLIVE_D", sleeve="CAMO_BROWN")
    armband(m); svd(m)
    hs, top = m.meta["hs"], head_top(m)
    h = m.node("head")
    h.cyl(0.21 * hs, 0.03 * hs, (0, top - 0.05 * hs, 0), "KHAKI", sections=10, rot=UP)   # панама
    h.cyl(0.13 * hs, 0.1 * hs, (0, top, 0), "KHAKI", sections=8, rot=UP)
    n = m.node("body")
    hip = m.meta["hip"]
    for k, (x, y, z, c) in enumerate(((-0.12, 0.5, -0.17, "OLIVE_L"), (0.1, 0.35, -0.18, "KHAKI"),
                                      (0.0, 0.2, -0.17, "OLIVE"), (0.14, 0.55, 0.15, "OLIVE_L"))):
        n.box((0.18, 0.16, 0.05), (x, hip + y, z), c, rot=(0, 0, 15 * (k % 2)))     # лохмотья маскхалата
    n.box((0.36, 0.07, 0.24), (0, hip + 0.03, 0), "GUNMETAL")
    return m


def unit_medic():
    m = humanoid("unit_medic", pose="pistol", top="OLIVE", pants="OLIVE_D", hands="MEDIC_WHITE")
    helmet_6b47(m); plate_carrier(m, pouches="MEDIC_WHITE"); armband(m, "MEDIC_WHITE"); armband(m, "TEAM", "r")
    hip = m.meta["hip"]
    b = m.node("body")
    b.box((0.4, 0.46, 0.22), (0, hip + 0.32, -0.29), "MEDIC_WHITE")               # медрюкзак
    b.box((0.08, 0.26, 0.02), (0, hip + 0.34, -0.405), "RED_CROSS")
    b.box((0.26, 0.08, 0.02), (0, hip + 0.34, -0.405), "RED_CROSS")
    hs, top = m.meta["hs"], head_top(m)
    m.node("head").box((0.1 * hs, 0.035 * hs, 0.02), (0, top - 0.03 * hs, 0.155 * hs), "RED_CROSS")
    m.node("head").box((0.035 * hs, 0.1 * hs, 0.02), (0, top - 0.03 * hs, 0.156 * hs), "RED_CROSS")
    pistol(m)
    return m


def unit_scout():
    m = humanoid("unit_scout", pose="rifle", top="KHAKI", pants="CAMO_BROWN", hands="OLIVE_D")
    armband(m); ak(m, short=True)
    hs, top = m.meta["hs"], head_top(m)
    h = m.node("head")
    h.box((0.25 * hs, 0.08 * hs, 0.26 * hs), (0, top - 0.02, 0), "OLIVE_D")           # кепка
    h.box((0.2 * hs, 0.025 * hs, 0.12 * hs), (0, top - 0.06 * hs, 0.17 * hs), "OLIVE_D")  # козырёк
    sh, hip = m.meta["sh_y"], m.meta["hip"]
    b = m.node("body")
    b.box((0.3, 0.09, 0.26), (0, sh - 0.03, 0), "OLIVE_L")                         # шарф-шемаг
    b.box((0.12, 0.07, 0.08), (0.02, hip + 0.42, 0.17), "BLACK")                   # бинокль
    backpack(m, "CAMO_BROWN", (0.3, 0.46, 0.2), roll="OLIVE")
    b.cyl(0.012, 0.75, (0.12, hip + 0.85, -0.34), "GUNMETAL", sections=4, rot=UP)  # антенна рации
    return m


# ----------------------------------------------------------------------------- мирные

def civ_variants():
    out = []
    # a: мужчина в синем пуховике
    m = humanoid("civ_adult_a", s=0.97, w=0.95, top="CIV_BLUE", pants="CIV_DENIM", skin="SKIN_A", shoes="WHITE", bulky=1.12)
    hair(m, "HAIR_D")
    hip = m.meta["hip"]
    for k in range(3):
        m.node("body").box((0.5 * 0.95, 0.02, 0.29), (0, hip + 0.16 + k * 0.14, 0), "CIV_DENIM")  # стёжка
    out.append(m)
    # b: женщина в красном пальто с сумкой
    m = humanoid("civ_adult_b", s=0.95, w=0.88, top="CIV_RED", pants="SHOE", skin="SKIN_B", coat="CIV_RED")
    hair(m, "HAIR_L", "long")
    m.node("arm_l").box((0.16, 0.2, 0.08), (-m.meta["ax"] - 0.05, m.meta["sh_y"] - 0.55, 0.0), "CAMO_BROWN")
    out.append(m)
    # c: рабочий в жёлтой куртке со светоотражающими полосами
    m = humanoid("civ_adult_c", s=0.98, w=1.0, top="CIV_YELLOW", pants="CIV_DENIM", skin="SKIN_C", shoes="SHOE")
    hip = m.meta["hip"]
    for y in (0.18, 0.36):
        m.node("body").box((0.47, 0.035, 0.27), (0, hip + y, 0), "LIGHT_EMIT")
    hs, top = m.meta["hs"], head_top(m)
    m.node("head").box((0.25 * hs, 0.07 * hs, 0.26 * hs), (0, top - 0.02, 0), "CIV_ORANGE")
    out.append(m)
    # d: пожилая женщина в зелёном пальто и платке
    m = humanoid("civ_adult_d", s=0.92, w=0.95, top="CIV_GREEN", pants="CHARCOAL", skin="SKIN_A", coat="CIV_GREEN", hunch=8)
    hair(m, "CIV_PURPLE", "scarf")
    out.append(m)
    # e: студент в худи с капюшоном и рюкзаком
    m = humanoid("civ_adult_e", s=0.97, w=0.92, top="CIV_PURPLE", pants="CIV_DENIM", skin="SKIN_B", shoes="WHITE")
    hair(m, "HAIR_D")
    hs, hy = m.meta["hs"], m.meta["hy"]
    tbox(m.node("body"), 0.3, 0.12, 0.24, 0.1, 0.16, (0, m.meta["sh_y"] - 0.02, -0.14), "CIV_PURPLE")  # капюшон
    backpack(m, "CIV_GREY", (0.28, 0.36, 0.16))
    out.append(m)
    # ребёнок
    m = humanoid("civ_child", s=0.64, w=1.05, top="CIV_ORANGE", pants="CIV_DENIM", head_scale=1.35, shoes="CIV_RED")
    hs, top = m.meta["hs"], head_top(m)
    m.node("head").cyl(0.14 * hs, 0.12 * hs, (0, top - 0.03 * hs, 0), "CIV_BLUE", sections=8, rot=UP, r2=0.1 * hs)  # шапка
    m.node("head").ball(0.04 * hs, (0, top + 0.05 * hs, 0), "WHITE", subdiv=0)                                     # помпон
    backpack(m, "CIV_YELLOW", (0.22, 0.24, 0.12))
    out.append(m)
    # рабочий с бревном
    m = humanoid("civ_worker_carry", top="CIV_ORANGE", pants="CIV_DENIM", skin="SKIN_B", pose="carry")
    m.node("weapon", parent="body", pivot=(0, m.meta["sh_y"] - 0.35, 0.33)).cyl(
        0.12, 1.4, (0, m.meta["sh_y"] - 0.35, 0.33), "BARK", sections=7, rot=ALONG_X)
    hs, top = m.meta["hs"], head_top(m)
    m.node("head").cyl(0.15 * hs, 0.09 * hs, (0, top - 0.02 * hs, 0), "HAZARD_YELLOW", sections=8, rot=UP, r2=0.12 * hs)
    out.append(m)
    return out


# ----------------------------------------------------------------------------- зомби

def _blood(m, node, pos, size=(0.16, 0.14, 0.02), color="BLOOD"):
    m.node(node).box(size, pos, color)


def ribs(m, side=1):
    hip = m.meta["hip"]
    b = m.node("body")
    for k in range(3):
        b.box((0.13, 0.022, 0.02), (side * 0.09, hip + 0.28 + k * 0.06, 0.12), "BIRCH")


def zmb_walker(name="zmb_walker", armored=False):
    m = humanoid(name, skin="ZMB_SKIN", top="CIV_GREY" if not armored else "OLIVE", pants="ZMB_CLOTH_D",
                 hunch=18, pose="zombie", head_tilt=14, stride=14, w=0.95, shoes="ZMB_CLOTH_D", sleeve="ZMB_CLOTH")
    hip = m.meta["hip"]
    _blood(m, "body", (0.08, hip + 0.42, 0.12))
    _blood(m, "body", (-0.1, hip + 0.18, 0.12), (0.12, 0.2, 0.02), "BLOOD_L")
    ribs(m, -1)
    hair(m, "HAIR_D", "bald")
    eyes(m)
    hs, hy = m.meta["hs"], m.meta["hy"]
    m.node("head").box((0.12 * hs, 0.04 * hs, 0.02), (0, hy + 0.05 * hs, 0.125 * hs), "SCREAM_MOUTH")  # рот
    if armored:
        plate_carrier(m, "OLIVE_D", None)
        helmet_6b47(m, "OLIVE_D")
        armband(m, "BLOOD")
    else:
        m.node("body").box((0.05, 0.3, 0.02), (0, m.meta["sh_y"] - 0.2, 0.12), "CHARCOAL")   # галстук
    return m


def zmb_runner():
    m = humanoid("zmb_runner", skin="ZMB_SKIN_D", top="CIV_BLUE", pants="CIV_BLUE", hunch=32, pose="back",
                 head_tilt=-18, stride=32, w=0.82, shoes="WHITE")
    hip, sh, ax = m.meta["hip"], m.meta["sh_y"], m.meta["ax"]
    for side, sx in (("l", -1), ("r", 1)):     # спортивный костюм: лампасы без логотипов
        m.node(f"arm_{side}").box((0.02, 0.5, 0.12), (sx * (ax + 0.06), sh - 0.32, 0), "WHITE")
        m.node(f"leg_{side}").box((0.02, 0.7, 0.14), (sx * 0.19, 0.5, 0), "WHITE")
    _blood(m, "body", (0, hip + 0.3, 0.12))
    eyes(m)
    hair(m, "HAIR_L")
    return m


def zmb_brute():
    m = humanoid("zmb_brute", s=1.22, w=1.65, skin="BRUTE_SKIN", top="BRUTE_SKIN", pants="ZMB_CLOTH_D",
                 hunch=24, pose="brute", head_tilt=22, head_scale=0.72, bulky=1.2, shoes="ZMB_CLOTH_D")
    s, hip, ax, sh = m.meta["s"], m.meta["hip"], m.meta["ax"], m.meta["sh_y"]
    for side, sx in (("l", -1), ("r", 1)):
        a = m.node(f"arm_{side}")
        a.box((0.4, 0.45, 0.4), (sx * ax, sh - 0.78, 0.0), "BRUTE_SKIN")    # кулачища
        a.box((0.38, 0.28, 0.38), (sx * ax, sh - 0.1, 0), "ZMB_SKIN_D")      # дельты
        a.box((0.2, 0.25, 0.04), (sx * ax, sh - 0.45, 0.17), "BLOOD_L")      # содранная кожа
    b = m.node("body")
    tbox(b, 0.9, 0.45, 1.0, 0.5, 0.35, (0, sh - 0.3, -0.12), "ZMB_SKIN_D")   # горб
    _blood(m, "body", (0.15, hip + 0.45, 0.3), (0.3, 0.25, 0.02))
    for k in range(3):
        b.box((0.08, 0.08, 0.3), (-0.3 + k * 0.3, sh + 0.05, -0.25), "CONCRETE_L", rot=(-30, 0, 0))   # обломки арматуры
    eyes(m, size=0.06)
    return m


def zmb_screamer():
    m = humanoid("zmb_screamer", w=0.72, skin="ZMB_SKIN", top="ZMB_CLOTH", pants="ZMB_CLOTH_D", pose="scream",
                 head_tilt=-35, hunch=-6, shoes="ZMB_CLOTH_D")
    sh, hy, hs = m.meta["sh_y"], m.meta["hy"], m.meta["hs"]
    h = m.node("head")
    h.box((0.16 * hs, 0.14 * hs, 0.05), (0, hy + 0.02 * hs, 0.12 * hs), "SCREAM_MOUTH")       # разорванная пасть
    h.box((0.18 * hs, 0.05 * hs, 0.12 * hs), (0, hy - 0.06 * hs, 0.08 * hs), "ZMB_SKIN_D")    # отвисшая челюсть
    eyes(m, dy=0.18)
    b = m.node("body")
    b.cyl(0.06, 0.16, (0, sh + 0.06, 0.02), "ZMB_SKIN", sections=6, rot=UP)                   # длинная шея
    b.box((0.3, 0.2, 0.04), (0, sh - 0.18, 0.11), "INFECT_GLOW")                              # светящиеся вены
    ribs(m, 1); ribs(m, -1)
    hair(m, "HAIR_L", "long")
    return m


def zmb_spitter():
    m = humanoid("zmb_spitter", w=1.0, skin="ZMB_SKIN_D", top="ZMB_CLOTH_D", pants="ZMB_CLOTH_D", hunch=10,
                 pose="down", head_tilt=-10, shoes="ZMB_CLOTH_D")
    sh, hy, hs = m.meta["sh_y"], m.meta["hy"], m.meta["hs"]
    b = m.node("body")
    b.ball(0.2, (0, sh - 0.02, 0.16), "SPIT_SAC", subdiv=1, scale=(1.0, 0.8, 0.9))    # зоб
    b.ball(0.28, (0.05, sh - 0.15, -0.22), "SPIT_SAC", subdiv=1)                       # мешок на спине
    b.ball(0.16, (-0.16, sh - 0.35, -0.18), "INFECT_GLOW", subdiv=0)
    m.node("head").box((0.11 * hs, 0.06 * hs, 0.04), (0, hy + 0.05 * hs, 0.125 * hs), "INFECT_GLOW")  # капающий рот
    eyes(m)
    return m


def zmb_giant():
    m = humanoid("zmb_giant", s=2.05, w=1.75, skin="BRUTE_SKIN", top="ZMB_SKIN_D", pants="ZMB_CLOTH_D",
                 hunch=25, pose="brute", head_tilt=25, head_scale=0.68, bulky=1.25, shoes="ZMB_CLOTH_D")
    sh, ax = m.meta["sh_y"], m.meta["ax"]
    rnd = random.Random(7)
    b = m.node("body")
    for i in range(8):
        x = rnd.uniform(-0.7, 0.7)
        b.cone(0.1, 0.7, (x, sh - rnd.uniform(0.1, 0.9), -0.45), rnd.choice(["CONCRETE_L", "RUST"]),
               sections=4, rot=(-120 + rnd.uniform(-20, 20), 0, rnd.uniform(-20, 20)))      # арматура из спины
    for side, sx in (("l", -1), ("r", 1)):
        a = m.node(f"arm_{side}")
        a.box((0.75, 0.85, 0.75), (sx * ax, sh - 1.45, 0), "BRUTE_SKIN")
        a.box((0.5, 0.4, 0.5), (sx * ax, sh - 0.2, 0), "CONCRETE_D")                         # бетонный «наплечник»
    b.box((0.5, 0.4, 0.05), (0, sh - 0.6, 0.42), "INFECT_GLOW")
    eyes(m, size=0.07)
    return m


def build_all(reg):
    reg("units", unit_assault(), unit="assault")
    reg("units", unit_sniper(), unit="sniper")
    reg("units", unit_medic(), unit="medic")
    reg("units", unit_scout(), unit="scout")
    for m in civ_variants():
        reg("civilians", m, unit={"civ_child": "child", "civ_worker_carry": "civilian_worker"}.get(m.name, "civilian"))
    reg("zombies", zmb_walker(), unit="walker")
    reg("zombies", zmb_walker("zmb_walker_armored", armored=True), unit="walker_armored")
    reg("zombies", zmb_runner(), unit="runner")
    reg("zombies", zmb_brute(), unit="brute")
    reg("zombies", zmb_screamer(), unit="screamer")
    reg("zombies", zmb_spitter(), unit="spitter")
    reg("zombies", zmb_giant(), unit="giant")
