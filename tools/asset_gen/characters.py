"""
characters.py — гуманоиды v3: военные, мирные, зомби (заменяют v0.1 1:1 по именам файлов и узлов).

Тело строится от скелета с пропорциями (рост 1.8 м ≈ 7 голов, голова чуть крупнее для читаемости сверху —
арт-библия §2): конечности, торс и шея — Skin + Subdivision в Blender (плавные переходы бедро→колено→голень,
плечо→локоть→запястье), голова и кисти — эллипсоиды, снаряжение и оружие — коробки с фасками. Нормали
гладкие (blmesh/bl_worker), а не плоские грани выпуклых оболочек, как в v2.
Бюджеты (D-10): военные ≤ 1400 треугольников, мирные ≤ 1000, зомби ≤ 700, громила/великан ≤ 1500.
Узлы: body, head, arm_l, arm_r, leg_l, leg_r, weapon (опц.) — пивоты в плече/бедре/шее (контракт с AgentView);
с v3 у рук и ног есть дочерние forearm_l/r (локоть) и shin_l/r (колено) — для сгибов в анимации.
"""
from __future__ import annotations

import math
import random

import numpy as np

from lowpoly import Model, _rot_matrix

SKIN_K = 1.22  # Subdivision «съедает» радиусы Skin примерно на столько — компенсируем, чтобы задавать реальные


# ----------------------------------------------------------------------------- детали

def _lod(n):
    return n.model.meta.get("lod", 1.0)


def skin(n, pts, radii, color, edges=None, tris=90, sub=1):
    """Цепочка (или дерево по edges) точек с радиусами: число или (rx по X, rz по глубине Z)."""
    rr = []
    for x in radii:
        a, b = (x, x) if not isinstance(x, (tuple, list)) else x
        rr.append([float(a) * SKIN_K, float(b) * SKIN_K])
    e = edges or [(i, i + 1) for i in range(len(pts) - 1)]
    n.piece({"k": "skin", "v": [[float(c) for c in p] for p in pts], "r": rr, "e": [list(x) for x in e], "sub": sub,
             "tris": int(tris * _lod(n))}, color)


def ell(n, c, r, color, rot=None, tris=60, cut=None):
    v = max(2, round(math.sqrt(tris * _lod(n) / 4)))
    spec = {"k": "ell", "pos": [float(x) for x in c], "r": [float(x) for x in r], "rot": rot, "seg": [max(5, 2 * v), v]}
    if cut is not None:
        spec["cut"] = cut
    n.piece(spec, color)


def rbox(n, size, pos, color, rot=None, bevel=None, bseg=1):
    """Коробка с фаской (1 сегмент — 44 треугольника); мелочь < 8 см и плоские нашивки — без фаски (12)."""
    b = min(size) * 0.22 if bevel is None else bevel
    if max(size) < 0.08 or min(size) < 0.025:
        b = 0.0
    n.piece({"k": "rbox", "size": [float(x) for x in size], "pos": [float(x) for x in pos], "rot": rot,
             "bevel": b, "bseg": bseg}, color)


def cyl(n, r, h, pos, color, rot=None, seg=10, r2=None, bevel=0.0):
    spec = {"k": "cyl", "r": r, "h": h, "pos": [float(x) for x in pos], "rot": rot, "seg": seg, "bevel": bevel}
    if r2 is not None:
        spec["r2"] = r2
    n.piece(spec, color)


def _rot_about(p, pivot, rot):
    M = _rot_matrix(rot)[:3, :3]
    return tuple(np.asarray(pivot, dtype=float) + M @ (np.asarray(p, dtype=float) - np.asarray(pivot, dtype=float)))


# ----------------------------------------------------------------------------- тело

# (поворот плеча — rest_rot узла руки, сгиб локтя по X: минус — предплечье вперёд)
ARM_POSES = {
    "down": ((3, 0, 6), (3, 0, -6), -8, -8),
    "rifle": ((-38, 0, 16), (-24, 0, -4), -62, -70),
    "pistol": ((5, 0, 7), (-76, 0, 0), -10, -10),
    "zombie": ((-80, 10, 0), (-68, -12, 0), -12, -25),
    "brute": ((-22, 0, 22), (-36, 0, -22), -32, -32),
    "back": ((26, 0, 18), (26, 0, -18), -24, -24),
    "carry": ((-45, 0, 6), (-45, 0, -6), -50, -50),
    "scream": ((40, 0, 35), (40, 0, -35), -14, -14),
}


def humanoid(name, *, s=1.0, w=1.0, skin_c="SKIN_A", top="OLIVE", pants="OLIVE_D", shoes="SHOE", hands=None,
             hunch=0.0, pose="down", head_tilt=0.0, stride=0.0, head_scale=1.12, bulky=1.0, coat=None, sleeve=None,
             female=False, lod=1.0, limb=1.0):
    """Человек ~1.8 м × s. w — ширина, bulky — объём торса (пуховик, броня), limb — толщина рук/ног.
    lod — множитель детализации (у зомби ниже: их сотни в кадре)."""
    m = Model(name, meta={"lod": lod})
    sw = 0.88 if female else 1.0              # плечи
    hw = 1.08 if female else 1.0              # таз
    hip = 0.92 * s
    sh_y = 1.43 * s
    ax = (0.205 * w * sw * bulky ** 0.5) * s
    m.meta.update(s=s, w=w, hip=hip, sh_y=sh_y, ax=ax, bulky=bulky, sw=sw)
    _legs(m, s, w * hw, pants, shoes, stride, limb)
    _torso(m, s, w, sw, hw, bulky, top, pants, coat, hunch)
    _head(m, s, s * head_scale, skin_c, head_tilt)
    _arms(m, s, ax, sh_y, sleeve or top, hands or skin_c, pose, limb)
    return m


def _legs(m, s, w, pants, shoes, stride, limb):
    """Бедро — узел leg_*, голень с ботинком — дочерний shin_* с пивотом в колене (сгиб при ходьбе)."""
    lx = 0.095 * w * s
    k = limb * s
    knee = 0.52 * s
    for side, sx, st in (("l", -1, stride), ("r", 1, -stride)):
        leg = m.node(f"leg_{side}", pivot=(sx * lx, m.meta["hip"], 0))
        x = sx * lx
        # бедро и голень перекрываются на ~5 см за коленом, иначе Subdivision сужает концы и виден «шов»
        skin(leg, [(x, 0.99 * s, 0.0), (x * 1.03, 0.76 * s, 0.006), (x, knee, 0.012), (x, knee - 0.05 * s, 0.01)],
             [(0.1 * w * k, 0.105 * k), (0.085 * w * k, 0.09 * k), (0.062 * k, 0.066 * k), (0.06 * k, 0.064 * k)], pants, tris=64)
        shin = m.node(f"shin_{side}", parent=f"leg_{side}", pivot=(x, knee, 0.012))
        skin(shin, [(x, knee + 0.05 * s, 0.012), (x, knee, 0.012), (x * 0.97, 0.36 * s, -0.008), (x * 0.95, 0.15 * s, 0.0)],
             [(0.058 * k, 0.062 * k), (0.06 * k, 0.064 * k), (0.064 * k, 0.07 * k), (0.046 * k, 0.05 * k)], pants, tris=52)
        # ботинок: голенище + носок одной цепочкой, подошва — фаской
        skin(shin, [(x * 0.95, 0.17 * s, -0.005), (x * 0.95, 0.08 * s, 0.0), (x * 0.95, 0.06 * s, 0.13 * s)],
             [0.056 * k, (0.058 * k, 0.07 * k), (0.05 * k, 0.04 * k)], shoes, tris=40)
        rbox(shin, (0.08 * k, 0.022 * s, 0.17 * s), (x * 0.95, 0.011 * s, 0.045 * s), "BLACK", bevel=0.008)
        if st:
            leg.rest_rot = (st, 0, 0)


def _torso(m, s, w, sw, hw, b, top, pants, coat, hunch):
    body = m.node("body", pivot=(0, m.meta["hip"], 0))
    # таз в цвет штанов, поверх — торс в цвет верха (заправленная куртка); под пальто таз не виден
    if not coat:
        skin(body, [(0, 0.84 * s, 0), (0, 1.03 * s, 0)], [(0.165 * w * hw * s, 0.115 * s), (0.16 * w * s, 0.112 * s)],
             pants, tris=40)
    ax = m.meta["ax"]
    pts = [(0, 0.97 * s, 0), (0, 1.12 * s, 0.0), (0, 1.29 * s, 0.012 * s), (0, 1.41 * s, 0), (0, 1.49 * s, -0.005),
           (-ax * 0.92, 1.405 * s, 0), (ax * 0.92, 1.405 * s, 0)]
    rad = [(0.165 * w * hw * s * b, 0.115 * s * b), (0.15 * w * s * b, 0.104 * s * b),
           (0.185 * w * sw * s * b, 0.125 * s * b), (0.17 * w * sw * s * b, 0.112 * s * b), (0.075 * s, 0.065 * s),
           (0.07 * s * b, 0.068 * s * b), (0.07 * s * b, 0.068 * s * b)]
    skin(body, pts, rad, top, edges=[(0, 1), (1, 2), (2, 3), (3, 4), (3, 5), (3, 6)], tris=150)
    m.meta["torso"] = list(zip([p[1] for p in pts[:5]], rad[:5]))
    if coat:  # полы пальто до колен
        skin(body, [(0, 1.1 * s, 0), (0, 0.86 * s, -0.005), (0, 0.52 * s, -0.012)],
             [(0.152 * w * s * b, 0.106 * s * b), (0.215 * w * hw * s, 0.155 * s), (0.225 * w * hw * s, 0.162 * s)], coat, tris=96)
    if hunch:
        body.rest_rot = (hunch, 0, 0)


def torso_r(m, y):
    """Радиусы торса на высоте y — для колец поверх (пояс, полосы, плитник)."""
    tab = m.meta["torso"]
    for (y0, r0), (y1, r1) in zip(tab, tab[1:]):
        if y0 <= y <= y1:
            t = (y - y0) / (y1 - y0)
            return r0[0] + (r1[0] - r0[0]) * t, r0[1] + (r1[1] - r0[1]) * t
    return tab[-1][1] if y > tab[-1][0] else tab[0][1]


def band(m, y0, h, color, grow=1.06, node="body", tris=36):
    """Кольцо поверх торса, повторяющее его форму."""
    a, b = torso_r(m, y0), torso_r(m, y0 + h)
    skin(m.node(node), [(0, y0, 0), (0, y0 + h, 0)], [(a[0] * grow, a[1] * grow), (b[0] * grow, b[1] * grow)],
         color, tris=tris)


def _head(m, s, hs, skin_c, tilt):
    head = m.node("head", parent="body", pivot=(0, 1.47 * s, 0))
    skin(head, [(0, 1.43 * s, -0.008), (0, 1.585 * s, 0.0)], [(0.052 * s, 0.05 * s), (0.047 * s, 0.045 * s)], skin_c,
         tris=24)
    hc = np.array([0, 1.47 * s + 0.19 * hs, 0])
    m.meta.update(hc=hc, hs=hs)
    ell(head, hc + np.array([0, 0.012, -0.012]) * hs, np.array([0.098, 0.112, 0.108]) * hs, skin_c, tris=96)  # череп
    ell(head, hc + np.array([0, -0.052, 0.022]) * hs, np.array([0.077, 0.072, 0.082]) * hs, skin_c, tris=48)  # челюсть
    ell(head, hc + np.array([0, -0.012, 0.1]) * hs, np.array([0.019, 0.03, 0.026]) * hs, skin_c, tris=12)     # нос
    for sx in (-1, 1):
        ell(head, hc + np.array([sx * 0.097, -0.008, -0.008]) * hs, np.array([0.017, 0.032, 0.026]) * hs, skin_c, tris=12)
    if tilt:
        head.rest_rot = (tilt, 0, 0)


def face(m, color="HAIR_D", y=-0.004, size=1.0):
    """Глаза (тёмные точки — читаемость лица сверху; у зомби — свечение)."""
    hc, hs = m.meta["hc"], m.meta["hs"]
    for sx in (-1, 1):
        ell(m.node("head"), hc + np.array([sx * 0.034, y, 0.09]) * hs, np.array([0.012, 0.01, 0.008]) * hs * size,
            color, tris=8)


def _arms(m, s, ax, sh_y, sleeve, hands, pose, limb):
    """Плечо — узел arm_*, предплечье с кистью — дочерний forearm_* с пивотом в локте (поза — его rest_rot)."""
    pl, pr, bl, br = ARM_POSES[pose]
    k = limb * s
    for side, sx, prot, eb in (("l", -1, pl, bl), ("r", 1, pr, br)):
        arm = m.node(f"arm_{side}", parent="body", pivot=(sx * ax, sh_y, 0))
        x = sx * ax
        elbow = (x * 1.06, sh_y - 0.28 * s, -0.01 * s)
        below = (elbow[0], elbow[1] - 0.04 * s, elbow[2])
        skin(arm, [(x, sh_y + 0.005 * s, 0), (x * 1.03, sh_y - 0.09 * s, 0), elbow, below],
             [0.058 * k, 0.06 * k, 0.047 * k, 0.045 * k], sleeve, tris=48)
        fore = m.node(f"forearm_{side}", parent=f"arm_{side}", pivot=elbow)
        wrist = (x * 1.08, sh_y - 0.52 * s, 0.0)
        skin(fore, [(elbow[0], elbow[1] + 0.04 * s, elbow[2]), elbow, wrist], [0.044 * k, 0.046 * k, 0.036 * k], sleeve, tris=36)
        hand = (x * 1.08, sh_y - 0.595 * s, 0.008 * s)
        ell(fore, hand, (0.038 * k, 0.068 * k, 0.05 * k), hands, tris=40)
        arm.rest_rot = prot
        if eb:
            fore.rest_rot = (eb, 0, 0)
        m.meta[f"hand_{side}"] = _rot_about(hand, elbow, (eb, 0, 0))   # в осях плеча (для предметов на теле)
        m.meta[f"hand0_{side}"] = hand                                   # в осях предплечья (для предметов в руке)
        m.meta[f"elbow_{side}"] = (eb, elbow)


# ----------------------------------------------------------------------------- снаряжение

def hair(m, color, style="short"):
    hc, hs = m.meta["hc"], m.meta["hs"]
    h = m.node("head")
    if style == "short":
        ell(h, hc + np.array([0, 0.042, -0.03]) * hs, np.array([0.103, 0.09, 0.108]) * hs, color, tris=60, cut=-0.2)
    elif style == "long":
        ell(h, hc + np.array([0, 0.035, -0.018]) * hs, np.array([0.106, 0.096, 0.114]) * hs, color, tris=60, cut=-0.3)
        skin(h, [(0, hc[1] + 0.02 * hs, -0.06 * hs), (0, hc[1] - 0.17 * hs, -0.075 * hs)],
             [(0.1 * hs, 0.05 * hs), (0.09 * hs, 0.035 * hs)], color, tris=30)
    elif style == "bald":
        ell(h, hc + np.array([0, -0.01, -0.035]) * hs, np.array([0.1, 0.075, 0.09]) * hs, color, tris=30, cut=-0.1)
    elif style == "scarf":  # платок
        ell(h, hc + np.array([0, 0.025, -0.01]) * hs, np.array([0.112, 0.112, 0.118]) * hs, color, tris=60, cut=-0.45)
        skin(h, [(0, hc[1] - 0.06 * hs, -0.07 * hs), (0, hc[1] - 0.14 * hs, -0.09 * hs)],
             [(0.07 * hs, 0.04 * hs), (0.035 * hs, 0.025 * hs)], color, tris=20)


def helmet_6b47(m, color="HELMET", gear=True):
    hc, hs = m.meta["hc"], m.meta["hs"]
    h = m.node("head")
    ell(h, hc + np.array([0, 0.03, -0.012]) * hs, np.array([0.122, 0.112, 0.132]) * hs, color, tris=90, cut=-0.28)
    ell(h, hc + np.array([0, 0.0, -0.012]) * hs, np.array([0.126, 0.014, 0.136]) * hs, color, tris=40)       # обод
    if gear:
        rbox(h, (0.07 * hs, 0.04 * hs, 0.03 * hs), hc + np.array([0, 0.09, 0.122]) * hs, "GUNMETAL")       # крепление ПНВ
        for sx in (-1, 1):
            rbox(h, (0.018 * hs, 0.03 * hs, 0.12 * hs), hc + np.array([sx * 0.123, 0.02, -0.005]) * hs, "GUNMETAL")  # рельсы
        rbox(h, (0.04 * hs, 0.04 * hs, 0.06 * hs), hc + np.array([0.136, 0.025, 0.02]) * hs, "OLIVE_D")   # фонарь


def plate_carrier(m, color="OLIVE_D", pouches="OLIVE_L", back=True):
    s = m.meta["s"]
    n = m.node("body")
    band(m, 1.08 * s, 0.3 * s, color, 1.12, tris=56)                                    # плитник обхватом
    fy, fr = 1.25 * s, torso_r(m, 1.25 * s)
    rbox(n, (0.3 * s, 0.3 * s, 0.05 * s), (0, fy, fr[1] * 1.05), color, bevel=0.018)  # передняя плита
    if back:  # под рюкзаком задняя плита не видна
        rbox(n, (0.3 * s, 0.32 * s, 0.05 * s), (0, fy, -fr[1] * 1.08), color, bevel=0.018)  # задняя плита
    for sx in (-1, 1):
        rbox(n, (0.065 * s, 0.035 * s, 0.24 * s), (sx * 0.12 * s, 1.43 * s, -0.005), color, bevel=0.01)  # лямки
    if pouches:
        for x in (-0.095, 0.0, 0.095):
            rbox(n, (0.085 * s, 0.12 * s, 0.06 * s), (x * s, 1.17 * s, fr[1] * 1.05 + 0.05 * s), pouches, bevel=0.014)
    band(m, 0.99 * s, 0.055 * s, "GUNMETAL", 1.1, tris=28)                              # ремень
    rbox(n, (0.05 * s, 0.045 * s, 0.02 * s), (0, 1.015 * s, torso_r(m, 1.0 * s)[1] * 1.12), "STEEL", bevel=0.006)  # пряжка


def armband(m, color="TEAM", side="l"):
    s, ax, sh = m.meta["s"], m.meta["ax"], m.meta["sh_y"]
    sx = -1 if side == "l" else 1
    skin(m.node(f"arm_{side}"), [(sx * ax * 1.035, sh - 0.13 * s, 0), (sx * ax * 1.04, sh - 0.19 * s, 0)],
         [0.064 * s, 0.06 * s], color, tris=20)


def backpack(m, color="OLIVE_D", size=(0.32, 0.4, 0.18), roll=None):
    s = m.meta["s"]
    n = m.node("body")
    back = torso_r(m, 1.25 * s)[1]
    z = -back - size[2] / 2 + 0.02
    y = 1.24 * s
    rbox(n, size, (0, y, z), color, bevel=min(size) * 0.35, bseg=2)
    rbox(n, (size[0] * 0.8, size[1] * 0.35, 0.05), (0, y - size[1] * 0.2, z - size[2] / 2), color, bevel=0.02)  # карман
    if roll:
        cyl(n, 0.065, size[0] + 0.06, (0, y + size[1] / 2 + 0.04, z), roll, rot=(0, 90, 0), seg=10)


def knee_pads(m, color="GUNMETAL"):
    s, lx = m.meta["s"], 0.095 * m.meta["w"] * m.meta["s"]
    for side, sx in (("l", -1), ("r", 1)):
        ell(m.node(f"shin_{side}"), (sx * lx, 0.52 * s, 0.06 * s), (0.06 * s, 0.065 * s, 0.035 * s), color, tris=24)


# ----------------------------------------------------------------------------- оружие

def _wpn_node(m):
    s, sh = m.meta["s"], m.meta["sh_y"]
    y = sh - 0.25 * s
    z = 0.28 * s
    return m.node("weapon", parent="body", pivot=(0.06 * s, y, z)), 0.06 * s, y, z


def ak(m, short=False, color="GUNMETAL", wood="WOOD"):
    L = 0.55 if short else 0.78
    w, x, y, z = _wpn_node(m)
    rbox(w, (0.045, 0.085, 0.32), (x, y, z + 0.1), color, bevel=0.008)                      # ствольная коробка
    rbox(w, (0.05, 0.065, 0.19), (x, y - 0.005, z + 0.33), wood if not short else color, bevel=0.012)  # цевьё
    cyl(w, 0.012, L * 0.42, (x, y + 0.015, z + 0.33 + L * 0.2), color, seg=8)               # ствол
    cyl(w, 0.018, 0.05, (x, y + 0.015, z + 0.33 + L * 0.42), color, seg=8)                  # ДТК
    for dz, dy, ang in ((0.12, -0.09, 15), (0.155, -0.175, 32)):                           # изогнутый магазин
        rbox(w, (0.035, 0.1, 0.055), (x, y + dy, z + dz), "GUNMETAL", rot=(ang, 0, 0), bevel=0.008)
    rbox(w, (0.032, 0.09, 0.04), (x, y - 0.08, z - 0.02), color, rot=(-15, 0, 0), bevel=0.008)  # рукоять
    if short:
        rbox(w, (0.018, 0.04, 0.22), (x, y + 0.02, z - 0.15), color, bevel=0.006)           # складной приклад
    else:
        rbox(w, (0.042, 0.1, 0.24), (x, y - 0.03, z - 0.17), wood, rot=(8, 0, 0), bevel=0.014)  # приклад
    rbox(w, (0.028, 0.03, 0.06), (x, y + 0.06, z + 0.17), color, bevel=0.006)               # прицел


def svd(m):
    w, x, y, z = _wpn_node(m)
    rbox(w, (0.045, 0.075, 0.4), (x, y, z + 0.12), "GUNMETAL", bevel=0.008)
    rbox(w, (0.05, 0.065, 0.3), (x, y - 0.005, z + 0.45), "WOOD", bevel=0.012)
    cyl(w, 0.012, 0.55, (x, y + 0.01, z + 0.85), "GUNMETAL", seg=8)
    rbox(w, (0.036, 0.11, 0.06), (x, y - 0.09, z + 0.2), "GUNMETAL", bevel=0.008)            # магазин
    rbox(w, (0.042, 0.12, 0.28), (x, y - 0.04, z - 0.2), "WOOD", rot=(6, 0, 0), bevel=0.014)  # приклад
    cyl(w, 0.026, 0.26, (x, y + 0.08, z + 0.14), "BLACK", seg=10)                          # ПСО-1
    cyl(w, 0.032, 0.03, (x, y + 0.08, z + 0.28), "GLASS", seg=10)
    for sx in (-1, 1):                                                                       # сошки
        cyl(w, 0.007, 0.2, (x + sx * 0.03, y - 0.1, z + 0.7), "GUNMETAL", rot=(-70, 0, sx * 15), seg=5)


def pistol(m, aim=-86):
    """ПМ в кисти: строится стволом вперёд и доворачивается в оси предплечья (aim — суммарный наклон руки)."""
    h = m.meta["hand0_r"]
    w = m.node("weapon", parent="forearm_r", pivot=h)
    hx, hy, hz = h
    back = (-aim, 0, 0)
    rbox(w, (0.035, 0.045, 0.17), _rot_about((hx, hy + 0.01, hz + 0.07), h, back), "GUNMETAL", rot=back, bevel=0.008)
    rbox(w, (0.03, 0.08, 0.04), _rot_about((hx, hy - 0.025, hz + 0.01), h, back), "GUNMETAL", rot=(-15 - aim, 0, 0),
         bevel=0.008)


# ----------------------------------------------------------------------------- военные

def unit_assault():
    m = humanoid("unit_assault", pose="rifle", top="OLIVE", pants="OLIVE_D", hands="GUNMETAL", shoes="SHOE", bulky=1.04)
    face(m); helmet_6b47(m); plate_carrier(m, back=False); armband(m); ak(m); knee_pads(m)
    backpack(m, size=(0.28, 0.28, 0.13))
    rbox(m.node("body"), (0.06, 0.1, 0.05), (0.16, 1.33, torso_r(m, 1.33)[1] * 1.12 + 0.03), "OLIVE_L", bevel=0.01)  # рация
    return m


def unit_sniper():
    m = humanoid("unit_sniper", pose="rifle", top="CAMO_BROWN", pants="OLIVE_D", hands="OLIVE_D", sleeve="CAMO_BROWN")
    face(m); armband(m); svd(m)
    hc, hs = m.meta["hc"], m.meta["hs"]
    h = m.node("head")
    ell(h, hc + np.array([0, 0.05, -0.012]) * hs, np.array([0.108, 0.085, 0.116]) * hs, "KHAKI", tris=48, cut=-0.1)  # панама
    ell(h, hc + np.array([0, 0.045, -0.012]) * hs, np.array([0.19, 0.016, 0.2]) * hs, "KHAKI", tris=40)             # поля
    n = m.node("body")
    rnd = random.Random(3)
    for k in range(7):                                                   # лохмотья маскхалата
        a = 2 * math.pi * k / 7 + rnd.uniform(-0.2, 0.2)
        y = rnd.uniform(1.05, 1.38)
        r = torso_r(m, y)
        rbox(n, (0.13, 0.15, 0.03), (math.sin(a) * r[0] * 1.08, y, math.cos(a) * r[1] * 1.12),
             rnd.choice(["OLIVE_L", "KHAKI", "OLIVE"]), rot=(rnd.uniform(-15, 15), math.degrees(a), rnd.uniform(-20, 20)),
             bevel=0.01)
    band(m, 0.99, 0.055, "GUNMETAL", 1.1, tris=28)
    return m


def unit_medic():
    m = humanoid("unit_medic", pose="pistol", top="OLIVE", pants="OLIVE_D", hands="MEDIC_WHITE")
    face(m); helmet_6b47(m, gear=False); plate_carrier(m, pouches="MEDIC_WHITE", back=False)
    armband(m, "MEDIC_WHITE"); armband(m, "TEAM", "r")
    b = m.node("body")
    back = torso_r(m, 1.22)[1]
    rbox(b, (0.36, 0.44, 0.2), (0, 1.2, -back - 0.1), "MEDIC_WHITE", bevel=0.06, bseg=2)   # медрюкзак
    rbox(b, (0.07, 0.22, 0.02), (0, 1.22, -back - 0.205), "RED_CROSS", bevel=0.004)
    rbox(b, (0.22, 0.07, 0.02), (0, 1.22, -back - 0.205), "RED_CROSS", bevel=0.004)
    hc, hs = m.meta["hc"], m.meta["hs"]
    h = m.node("head")
    rbox(h, (0.07 * hs, 0.024 * hs, 0.012), hc + np.array([0, 0.07, 0.128]) * hs, "RED_CROSS", rot=(-20, 0, 0), bevel=0.003)
    rbox(h, (0.024 * hs, 0.07 * hs, 0.012), hc + np.array([0, 0.07, 0.129]) * hs, "RED_CROSS", rot=(-20, 0, 0), bevel=0.003)
    pistol(m)
    return m


def unit_scout():
    m = humanoid("unit_scout", pose="rifle", top="KHAKI", pants="CAMO_BROWN", hands="OLIVE_D", w=0.97)
    face(m); armband(m); ak(m, short=True)
    hc, hs = m.meta["hc"], m.meta["hs"]
    h = m.node("head")
    ell(h, hc + np.array([0, 0.045, -0.012]) * hs, np.array([0.106, 0.085, 0.114]) * hs, "OLIVE_D", tris=48, cut=-0.15)  # кепка
    ell(h, hc + np.array([0, 0.072, 0.1]) * hs, np.array([0.078, 0.012, 0.065]) * hs, "OLIVE_D", rot=(-12, 0, 0), tris=24)  # козырёк
    b = m.node("body")
    band(m, 1.4, 0.07, "OLIVE_L", 1.15, tris=30)                                        # шемаг
    rbox(b, (0.11, 0.06, 0.07), (0.02, 1.3, torso_r(m, 1.3)[1] + 0.04), "BLACK", bevel=0.015)   # бинокль
    band(m, 0.99, 0.055, "GUNMETAL", 1.1, tris=28)
    backpack(m, "CAMO_BROWN", (0.3, 0.44, 0.19), roll="OLIVE")
    cyl(b, 0.008, 0.7, (0.11, 1.62, -0.33), "GUNMETAL", rot=(-90, 0, 0), seg=5)            # антенна рации
    return m


# ----------------------------------------------------------------------------- мирные

def civ_variants():
    out = []
    # a: мужчина в синем пуховике
    m = humanoid("civ_adult_a", s=0.97, w=0.96, top="CIV_BLUE", pants="CIV_DENIM", skin_c="SKIN_A", shoes="WHITE",
                 bulky=1.14, limb=1.05)
    face(m); hair(m, "HAIR_D")
    for k in range(3):
        band(m, (1.08 + k * 0.12) * 0.97, 0.022, "TARP_BLUE", 1.03, tris=28)              # стёжка пуховика
    out.append(m)
    # b: женщина в красном пальто с сумкой
    m = humanoid("civ_adult_b", s=0.95, w=0.9, top="CIV_RED", pants="SHOE", skin_c="SKIN_B", coat="CIV_RED", female=True)
    face(m); hair(m, "HAIR_L", "long")
    hx, hy, hz = m.meta["hand0_l"]
    rbox(m.node("forearm_l"), (0.08, 0.17, 0.22), (hx - 0.03, hy - 0.05, hz), "CAMO_BROWN", bevel=0.025, bseg=2)  # сумка
    out.append(m)
    # c: рабочий в жёлтой куртке со светоотражающими полосами
    m = humanoid("civ_adult_c", s=0.98, w=1.02, top="CIV_YELLOW", pants="CIV_DENIM", skin_c="SKIN_C", shoes="SHOE", bulky=1.05)
    face(m)
    for y in (1.12, 1.27):
        band(m, y * 0.98, 0.035, "LIGHT_EMIT", 1.03, tris=28)
    hc, hs = m.meta["hc"], m.meta["hs"]
    ell(m.node("head"), hc + np.array([0, 0.045, -0.012]) * hs, np.array([0.108, 0.09, 0.116]) * hs, "CIV_ORANGE",
        tris=48, cut=-0.2)                                                                  # шапка
    out.append(m)
    # d: пожилая женщина в зелёном пальто и платке
    m = humanoid("civ_adult_d", s=0.92, w=0.98, top="CIV_GREEN", pants="CHARCOAL", skin_c="SKIN_A", coat="CIV_GREEN",
                 hunch=8, female=True, bulky=1.06)
    face(m); hair(m, "CIV_PURPLE", "scarf")
    out.append(m)
    # e: студент в худи с капюшоном и рюкзаком
    m = humanoid("civ_adult_e", s=0.97, w=0.93, top="CIV_PURPLE", pants="CIV_DENIM", skin_c="SKIN_B", shoes="WHITE")
    face(m); hair(m, "HAIR_D")
    back = torso_r(m, 1.4)[1]
    skin(m.node("body"), [(0, 1.38, -back * 0.7), (0, 1.47, -back * 0.9)], [(0.13, 0.06), (0.1, 0.05)], "CIV_PURPLE",
         tris=30)                                                                           # капюшон
    backpack(m, "CIV_GREY", (0.27, 0.34, 0.15))
    out.append(m)
    # ребёнок: крупная голова, короткие конечности
    m = humanoid("civ_child", s=0.66, w=1.08, top="CIV_ORANGE", pants="CIV_DENIM", head_scale=1.28, shoes="CIV_RED", limb=1.12)
    face(m)
    hc, hs = m.meta["hc"], m.meta["hs"]
    h = m.node("head")
    ell(h, hc + np.array([0, 0.04, -0.012]) * hs, np.array([0.108, 0.1, 0.116]) * hs, "CIV_BLUE", tris=48, cut=-0.2)  # шапка
    ell(h, hc + np.array([0, 0.15, -0.012]) * hs, np.array([0.03, 0.03, 0.03]) * hs, "WHITE", tris=16)            # помпон
    backpack(m, "CIV_YELLOW", (0.2, 0.22, 0.11))
    out.append(m)
    # рабочий с бревном
    m = humanoid("civ_worker_carry", top="CIV_ORANGE", pants="CIV_DENIM", skin_c="SKIN_B", pose="carry", bulky=1.04)
    face(m)
    hl, hr = m.meta["hand_l"], m.meta["hand_r"]
    y = (hl[1] + hr[1]) / 2 - 0.05
    z = 0.33
    w = m.node("weapon", parent="body", pivot=(0, y, z))
    cyl(w, 0.11, 1.4, (0, y, z), "BARK", rot=(0, 90, 0), seg=9, bevel=0.02)
    cyl(w, 0.085, 1.405, (0, y, z), "WOOD_L", rot=(0, 90, 0), seg=9)                       # торцы
    hc, hs = m.meta["hc"], m.meta["hs"]
    h = m.node("head")
    ell(h, hc + np.array([0, 0.045, -0.01]) * hs, np.array([0.118, 0.1, 0.128]) * hs, "HAZARD_YELLOW", tris=48, cut=-0.15)  # каска
    ell(h, hc + np.array([0, 0.03, 0.02]) * hs, np.array([0.13, 0.012, 0.15]) * hs, "HAZARD_YELLOW", tris=24)
    out.append(m)
    return out


# ----------------------------------------------------------------------------- зомби

ZL = 0.5  # детализация зомби (MultiMesh на сотни копий)


def _blood(m, node, pos, size=(0.14, 0.12, 0.02), color="BLOOD", rot=None):
    rbox(m.node(node), size, pos, color, rot=rot, bevel=0.005, bseg=1)


def _on_chest(m, y, x=0.0, out=1.0):
    return (x, y, torso_r(m, y)[1] * out)


def ribs(m, side=1):
    b = m.node("body")
    for k in range(3):
        y = 1.22 + k * 0.055
        rbox(b, (0.1, 0.02, 0.02), _on_chest(m, y, side * 0.08, 0.98), "BIRCH", bevel=0.006, bseg=1)


def mouth(m, color="SCREAM_MOUTH", size=(0.05, 0.022, 0.012), y=-0.06):
    hc, hs = m.meta["hc"], m.meta["hs"]
    ell(m.node("head"), hc + np.array([0, y, 0.09]) * hs, np.array(size) * hs, color, tris=12)


def zmb_walker(name="zmb_walker", armored=False):
    m = humanoid(name, skin_c="ZMB_SKIN", top="CIV_GREY" if not armored else "OLIVE", pants="ZMB_CLOTH_D",
                 hunch=18, pose="zombie", head_tilt=14, stride=14, w=0.95, shoes="ZMB_CLOTH_D", sleeve="ZMB_CLOTH",
                 lod=ZL, limb=0.92)
    _blood(m, "body", _on_chest(m, 1.33, 0.07, 1.02), rot=(0, 0, 12))
    _blood(m, "body", _on_chest(m, 1.13, -0.08, 1.02), (0.1, 0.16, 0.02), "BLOOD_L")
    ribs(m, -1)
    face(m, "INFECT_GLOW", size=1.15)
    mouth(m)
    if armored:
        plate_carrier(m, "OLIVE_D", None)
        helmet_6b47(m, "OLIVE_D", gear=False)
        armband(m, "BLOOD")
    else:
        hair(m, "HAIR_D", "bald")
        rbox(m.node("body"), (0.045, 0.26, 0.015), _on_chest(m, 1.3, 0.0, 1.03), "CHARCOAL", bevel=0.005, bseg=1)  # галстук
    return m


def zmb_runner():
    m = humanoid("zmb_runner", skin_c="ZMB_SKIN_D", top="CIV_BLUE", pants="CIV_BLUE", hunch=32, pose="back",
                 head_tilt=-18, stride=32, w=0.84, shoes="WHITE", lod=ZL, limb=0.88)
    for side, sx in (("l", -1), ("r", 1)):     # спортивный костюм: лампасы без логотипов
        x = sx * 0.095 * 0.84
        skin(m.node(f"leg_{side}"), [(x + sx * 0.085, 0.95, 0), (x + sx * 0.062, 0.54, 0.01)], [0.014, 0.013], "WHITE", tris=12)
        skin(m.node(f"shin_{side}"), [(x + sx * 0.06, 0.5, 0.01), (x + sx * 0.045, 0.2, 0)], [0.013, 0.012], "WHITE", tris=12)
    _blood(m, "body", _on_chest(m, 1.25, 0.0, 1.02))
    face(m, "INFECT_GLOW", size=1.15)
    hair(m, "HAIR_L")
    return m


def zmb_brute():
    m = humanoid("zmb_brute", s=1.22, w=1.55, skin_c="BRUTE_SKIN", top="BRUTE_SKIN", pants="ZMB_CLOTH_D",
                 hunch=24, pose="brute", head_tilt=10, head_scale=0.95, bulky=1.25, shoes="ZMB_CLOTH_D", lod=1.05, limb=1.9)
    ax, sh = m.meta["ax"], m.meta["sh_y"]
    for side, sx in (("l", -1), ("r", 1)):
        a = m.node(f"arm_{side}")
        hx, hy, hz = m.meta[f"hand0_{side}"]
        ell(m.node(f"forearm_{side}"), (hx, hy - 0.05, hz), (0.16, 0.19, 0.17), "BRUTE_SKIN", tris=60)  # кулачища
        ell(a, (sx * ax * 1.05, sh - 0.04, 0), (0.17, 0.15, 0.17), "ZMB_SKIN_D", tris=60)  # дельты
        _blood(m, f"arm_{side}", (sx * ax * 1.12, sh - 0.4, 0.07), (0.03, 0.2, 0.12), "BLOOD_L")
    b = m.node("body")
    ell(b, (0, sh - 0.12, -0.2), (0.34, 0.2, 0.22), "ZMB_SKIN_D", tris=90)           # горб
    _blood(m, "body", _on_chest(m, 1.45, 0.12, 1.02), (0.24, 0.2, 0.02))
    for k in range(3):
        cyl(b, 0.022, 0.32, (-0.25 + k * 0.25, sh + 0.12, -0.3), "RUST", rot=(-55, 0, -20 + k * 20), seg=5)  # арматура
    face(m, "INFECT_GLOW", size=1.3)
    mouth(m, size=(0.06, 0.03, 0.012))
    return m


def zmb_screamer():
    m = humanoid("zmb_screamer", w=0.74, skin_c="ZMB_SKIN", top="ZMB_CLOTH", pants="ZMB_CLOTH_D", pose="scream",
                 head_tilt=-35, hunch=-6, shoes="ZMB_CLOTH_D", lod=ZL, limb=0.8, female=True)
    mouth(m, size=(0.055, 0.06, 0.02), y=-0.07)                                          # разорванная пасть
    face(m, "INFECT_GLOW", y=0.03, size=1.2)
    b = m.node("body")
    rbox(b, (0.05, 0.16, 0.015), _on_chest(m, 1.3, 0.05, 1.02), "INFECT_GLOW", rot=(0, 0, 20))  # светящиеся вены
    ribs(m, 1); ribs(m, -1)
    hair(m, "HAIR_L", "long")
    return m


def zmb_spitter():
    m = humanoid("zmb_spitter", w=1.0, skin_c="ZMB_SKIN_D", top="ZMB_CLOTH_D", pants="ZMB_CLOTH_D", hunch=10,
                 pose="down", head_tilt=-10, shoes="ZMB_CLOTH_D", lod=ZL)
    sh = m.meta["sh_y"]
    b = m.node("body")
    ell(b, _on_chest(m, sh - 0.03, 0.0, 1.2), (0.15, 0.12, 0.13), "SPIT_SAC", tris=48)   # зоб
    ell(b, (0.05, sh - 0.16, -0.25), (0.25, 0.25, 0.22), "SPIT_SAC", tris=60)           # мешок на спине
    ell(b, (-0.15, sh - 0.33, -0.2), (0.12, 0.12, 0.12), "INFECT_GLOW", tris=24)
    mouth(m, "INFECT_GLOW", (0.045, 0.025, 0.014))
    face(m, "INFECT_GLOW", size=1.15)
    return m


def zmb_giant():
    m = humanoid("zmb_giant", s=2.05, w=1.6, skin_c="BRUTE_SKIN", top="ZMB_SKIN_D", pants="ZMB_CLOTH_D",
                 hunch=25, pose="brute", head_tilt=25, head_scale=0.72, bulky=1.3, shoes="ZMB_CLOTH_D", lod=1.05, limb=1.9)
    sh, ax = m.meta["sh_y"], m.meta["ax"]
    rnd = random.Random(7)
    b = m.node("body")
    for _ in range(7):
        x = rnd.uniform(-0.6, 0.6)
        cyl(b, 0.05, 0.75, (x, sh - rnd.uniform(0.1, 0.8), -0.5), rnd.choice(["CONCRETE_L", "RUST"]),
            rot=(-120 + rnd.uniform(-20, 20), 0, rnd.uniform(-20, 20)), seg=5, r2=0.01)    # арматура из спины
    for side, sx in (("l", -1), ("r", 1)):
        a = m.node(f"arm_{side}")
        hx, hy, hz = m.meta[f"hand0_{side}"]
        ell(m.node(f"forearm_{side}"), (hx, hy - 0.1, hz), (0.3, 0.34, 0.3), "BRUTE_SKIN", tris=60)
        rbox(a, (0.42, 0.34, 0.42), (sx * ax * 1.05, sh - 0.12, 0), "CONCRETE_D", rot=(8, 15 * sx, 10 * sx), bevel=0.05)  # наплечник
    rbox(b, (0.42, 0.32, 0.04), _on_chest(m, sh - 0.45, 0.0, 1.03), "INFECT_GLOW", bevel=0.01, bseg=1)
    face(m, "INFECT_GLOW", size=1.4)
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
