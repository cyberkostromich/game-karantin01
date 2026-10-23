"""
vehicles.py — техника v2: БМП-2, Т-90, Ми-8МТВ (заменяют плейсхолдеры v0.1 1:1 по файлам и узлам).
Узлы: hull, turret, barrel (БМП, танк) · body, rotor_main, rotor_tail (вертолёт). Бюджет ≤ 3000 треугольников.
Корпуса — экструзия бокового профиля (ломаный силуэт читается сверху), детали — геометрией.
"""
from __future__ import annotations

import math

import numpy as np
import trimesh
from shapely.geometry import Polygon

from lowpoly import ALONG_X, UP, Model, _rot_matrix
from characters import tbox

_SWAP = np.array([[0, 0, 1, 0], [0, 1, 0, 0], [1, 0, 0, 0], [0, 0, 0, 1]], dtype=float)


def side(n, profile_zy, width, color, x=0.0):
    """Профиль в плоскости (z, y), экструзия по ширине вдоль X с центром в x."""
    m = trimesh.creation.extrude_polygon(Polygon(profile_zy), width)
    m.apply_transform(_SWAP)
    m.apply_translation((x - width / 2, 0, 0))
    m.fix_normals()
    return n.add(m, color)


def wheel(n, r, w, pos, color="STEEL_D", hub="OLIVE_D", sections=8):
    n.cyl(r, w, pos, color, sections=sections, rot=ALONG_X)
    n.cyl(r * 0.45, w + 0.04, pos, hub, sections=6, rot=ALONG_X)


def track_set(n, half_w, tw, length, z0, wheels, r, sprocket_front=True, h_top=0.98):
    """Гусеница с катками, ленивцем, звёздочкой и поддерживающими роликами — с каждой стороны."""
    for sx in (-1, 1):
        x = sx * half_w
        zf, zb = z0 + length / 2, z0 - length / 2
        n.box((tw, 0.07, length - 0.6), (x, h_top, z0), "TIRE")              # верхняя ветвь
        n.box((tw, 0.07, length - 1.4), (x, 0.035, z0), "TIRE")              # нижняя ветвь
        for zz, y, ang in ((zf - 0.45, 0.5, -42), (zb + 0.45, 0.5, 42)):
            n.box((tw, 0.07, 1.1), (x, y, zz), "TIRE", rot=(ang, 0, 0))     # наклонные участки
        for i in range(wheels):
            zz = zb + 0.9 + i * (length - 1.8) / (wheels - 1)
            wheel(n, r, tw * 0.8, (x, r + 0.04, zz))
        for i in range(3):
            n.cyl(0.08, tw * 0.5, (x, h_top - 0.1, zb + 1.4 + i * (length - 2.8) / 2), "STEEL_D", sections=6, rot=ALONG_X)
        sp, idl = (zf - 0.3, zb + 0.3) if sprocket_front else (zb + 0.3, zf - 0.3)
        wheel(n, 0.32, tw * 0.85, (x, 0.72, sp), "GUNMETAL", "STEEL_D", sections=10)
        wheel(n, 0.3, tw * 0.85, (x, 0.62, idl), "STEEL_D")


def smoke_tubes(n, x, y, z, count, ang_y, color="OLIVE_D"):
    for k in range(count):
        n.cyl(0.05, 0.28, (x, y + 0.08 * (k % 2), z - 0.12 * k), color, sections=5, rot=(-30, ang_y, 0))


# ============================================================================== БМП-2

def veh_bmp():
    m = Model("veh_bmp")
    hull = m.node("hull")
    track_set(hull, 1.32, 0.48, 6.3, -0.15, 6, 0.36, sprocket_front=True, h_top=0.95)
    hull.box((2.1, 0.55, 5.8), (0, 0.7, -0.2), "OLIVE_D")                      # днище между гусеницами
    side(hull, [(-3.3, 0.95), (-3.35, 1.6), (-2.7, 1.72), (1.0, 1.75), (3.3, 1.02), (3.25, 0.7), (2.8, 0.55),
                (-2.9, 0.55)], 2.9, "OLIVE")                                     # корпус: плоский ребристый лоб
    for k in range(5):                                                           # рёбра верхнего лобового листа
        t = (k + 1) / 6.0
        z, y = 1.0 + t * 2.3, 1.75 - t * 0.73
        hull.box((2.6, 0.04, 0.06), (0, y + 0.02, z), "OLIVE_D", rot=(-18, 0, 0))
    hull.box((2.4, 0.06, 0.3), (0, 1.62, 2.1), "OLIVE_L", rot=(-18, 0, 0))     # волноотражательный щиток
    for sx in (-1, 1):
        hull.box((0.25, 0.18, 0.05), (sx * 0.95, 1.16, 3.23), "LIGHT_WARM")      # фары
        hull.box((0.6, 0.55, 0.12), (sx * 0.62, 1.15, -3.38), "OLIVE_D")         # кормовые двери-баки
        hull.box((0.05, 0.08, 4.8), (sx * 1.46, 1.42, -0.3), "STEEL_D")          # поручни/трос
    for k in range(4):
        hull.box((0.7, 0.05, 0.12), (0.55, 1.77, -2.0 + k * 0.3), "GUNMETAL")    # решётка МТО
    hull.box((0.5, 0.12, 0.5), (-0.75, 1.82, 1.35), "OLIVE_D")                   # люк мехвода
    hull.box((0.45, 0.1, 0.45), (-0.75, 1.82, -1.5), "OLIVE_D")                  # десантные люки
    hull.box((0.45, 0.1, 0.45), (0.0, 1.82, -1.5), "OLIVE_D")
    hull.box((0.4, 0.3, 0.02), (1.47, 1.3, -1.8), "TEAM")                        # тактический знак
    hull.box((0.3, 0.3, 0.03), (-1.0, 1.55, -3.36), "TEAM")
    tur = m.node("turret", parent="hull", pivot=(0, 1.75, 0.25))
    tur.cyl(0.95, 0.5, (0, 2.0, 0.25), "OLIVE", sections=8, rot=UP, r2=0.72)
    tbox(tur, 0.8, 0.5, 0.7, 0.45, 0.36, (0, 1.85, 0.95), "OLIVE_D")              # маска пушки
    tur.box((0.35, 0.35, 0.3), (0.58, 2.38, 0.15), "STEEL_D")                    # прицел
    tur.box((0.42, 0.1, 0.42), (-0.4, 2.29, -0.1), "OLIVE_D")                    # люк командира
    tur.cyl(0.085, 1.25, (0.15, 2.55, 0.3), "OLIVE_D", sections=6)               # ПТУР «Конкурс»
    tur.box((0.08, 0.25, 0.08), (0.15, 2.38, 0.1), "GUNMETAL")
    for sx in (-1, 1):
        smoke_tubes(tur, sx * 0.85, 2.05, 0.35, 3, sx * 35)
    brl = m.node("barrel", parent="turret", pivot=(0, 2.02, 1.15))
    brl.cyl(0.055, 2.5, (0, 2.02, 2.4), "GUNMETAL", sections=6)                  # 2А42
    brl.cyl(0.09, 0.5, (0, 2.02, 1.4), "GUNMETAL", sections=6)
    brl.cyl(0.075, 0.22, (0, 2.02, 3.62), "BLACK", sections=6)                   # дульный тормоз
    brl.cyl(0.03, 0.6, (0.22, 1.95, 1.5), "GUNMETAL", sections=4)                # ПКТ
    return m


# ============================================================================== Т-90

def veh_tank():
    m = Model("veh_tank")
    hull = m.node("hull")
    track_set(hull, 1.55, 0.58, 6.8, -0.05, 6, 0.4, sprocket_front=False, h_top=1.0)
    hull.box((2.4, 0.6, 6.4), (0, 0.72, -0.1), "OLIVE_D")
    side(hull, [(-3.45, 1.0), (-3.5, 1.55), (1.7, 1.62), (3.45, 1.1), (3.4, 0.72), (2.9, 0.55), (-3.1, 0.55)],
         3.3, "OLIVE")
    for sx in (-1, 1):
        hull.box((0.62, 0.05, 6.9), (sx * 1.62, 1.08, 0.0), "OLIVE_D")           # надгусеничные полки
        hull.box((0.06, 0.55, 5.2), (sx * 1.92, 0.82, -0.6), "OLIVE_D")          # резинотканевые экраны
        for k in range(4):
            hull.box((0.12, 0.5, 0.42), (sx * 1.95, 0.85, 1.6 + k * 0.45), "OLIVE_L")  # ДЗ на бортовых экранах
    for row in range(2):                                                         # «Контакт-5» на ВЛД
        for k in range(4):
            t = 0.25 + row * 0.38
            z, y = 1.7 + t * 1.75, 1.62 - t * 0.52
            hull.box((0.68, 0.16, 0.5), (-1.05 + k * 0.7, y + 0.1, z), "OLIVE_L", rot=(-17, 0, 0))
    for sx in (-1, 1):
        hull.cyl(0.3, 1.0, (sx * 0.8, 1.35, -3.65), "STEEL_D", sections=8, rot=ALONG_X)   # бочки
        hull.box((0.2, 0.15, 0.05), (sx * 1.2, 1.25, 3.43), "LIGHT_WARM")
    hull.box((0.5, 0.35, 0.02), (1.95, 1.25, -2.0), "TEAM")
    hull.box((0.7, 0.06, 0.5), (0.6, 1.64, -2.2), "GUNMETAL")                     # решётка МТО
    tur = m.node("turret", parent="hull", pivot=(0, 1.62, -0.1))
    tur.cyl(1.45, 0.6, (0, 1.92, -0.15), "OLIVE", sections=10, rot=UP, r2=1.08)
    for sx in (-1, 1):                                                           # «брови» ДЗ
        tbox(tur, 0.9, 1.1, 0.55, 0.7, 0.42, (sx * 0.78, 1.62, 0.75), "OLIVE_L", shift=(0, -0.2))
        tur.box((0.28, 0.22, 0.25), (sx * 0.6, 2.28, 0.6), "GUNMETAL")           # «Штора»
        tur.box((0.18, 0.12, 0.03), (sx * 0.6, 2.28, 0.74), "BLOOD_L")           # ИК-прожектор
        smoke_tubes(tur, sx * 1.2, 2.05, -0.2, 5, sx * 80)
    tur.box((1.9, 0.48, 0.9), (0, 1.9, -1.55), "OLIVE_D")                        # кормовая ниша/ЗИП
    tur.cyl(0.32, 0.3, (0.5, 2.34, -0.35), "OLIVE_D", sections=8, rot=UP)        # командирская башенка
    tur.cyl(0.035, 1.0, (0.5, 2.6, 0.05), "GUNMETAL", sections=5)                # «Корд»
    tur.box((0.25, 0.2, 0.3), (0.5, 2.55, -0.3), "GUNMETAL")
    tur.cyl(0.11, 1.9, (-0.7, 2.25, -2.0), "OLIVE_D", sections=6, rot=(0, 90, 0))  # труба ОПВТ
    tur.cyl(0.02, 2.4, (-0.6, 3.3, -1.3), "GUNMETAL", sections=4, rot=UP)        # антенна
    brl = m.node("barrel", parent="turret", pivot=(0, 1.98, 1.15))
    brl.cyl(0.09, 5.1, (0, 1.98, 3.7), "OLIVE_D", sections=8)                    # 2А46М
    for k in range(3):
        brl.cyl(0.12, 0.75, (0, 1.98, 1.8 + k * 1.2), "OLIVE", sections=8)       # теплозащитный кожух
    brl.cyl(0.16, 0.6, (0, 1.98, 2.55), "OLIVE_D", sections=8)                   # эжектор
    brl.box((0.75, 0.55, 0.45), (0, 1.98, 1.25), "OLIVE_D")                      # маска
    return m


# ============================================================================== Ми-8МТВ

def veh_heli():
    m = Model("veh_heli")
    body = m.node("body")
    side(body, [(6.6, 1.35), (6.2, 2.35), (5.3, 2.95), (-3.2, 3.0), (-4.4, 2.6), (-4.7, 1.45), (-3.8, 0.75),
                (5.4, 0.78), (6.3, 1.0)], 2.4, "OLIVE")                          # фюзеляж
    side(body, [(6.65, 1.4), (6.25, 2.3), (5.6, 2.75), (5.25, 2.2), (5.6, 1.3)], 2.0, "GLASS")  # остекление кабины
    side(body, [(3.8, 2.98), (3.1, 3.65), (-2.8, 3.62), (-3.5, 3.0)], 1.9, "OLIVE_D")          # капоты двигателей
    for sx in (-1, 1):
        body.cyl(0.32, 0.7, (sx * 0.5, 3.3, 4.0), "STEEL_D", sections=8)        # ПЗУ на входе
        body.cyl(0.2, 0.7, (sx * 1.0, 3.1, -1.6), "GUNMETAL", sections=6, rot=(0, sx * 40, 0))  # выхлоп
        body.cyl(0.42, 2.4, (sx * 1.42, 1.45, 0.4), "OLIVE", sections=8)        # подвесные баки
        body.box((1.4, 0.12, 0.55), (sx * 1.95, 2.05, -1.0), "OLIVE_D")          # фермы подвески
        for k in (0, 1):
            body.cyl(0.21, 1.6, (sx * (2.25 + k * 0.5), 1.8, -0.95), "GUNMETAL", sections=7)   # УБ-32
            body.cyl(0.17, 0.04, (sx * (2.25 + k * 0.5), 1.8, -0.14), "BLACK", sections=7)
        for k in range(4):
            body.box((0.03, 0.42, 0.42), (sx * 1.21, 2.2, 1.6 - k * 1.05), "GLASS")  # круглые иллюминаторы
        body.box((0.15, 0.9, 0.12), (sx * 1.1, 0.4, -1.0), "STEEL_D")            # основные стойки
        body.cyl(0.4, 0.25, (sx * 1.25, 0.4, -1.0), "TIRE", sections=8, rot=ALONG_X)
        body.cyl(0.26, 0.15, (sx * 0.22, 0.28, 4.9), "TIRE", sections=8, rot=ALONG_X)   # передняя стойка
        body.box((0.03, 0.55, 0.55), (sx * 1.21, 2.4, -3.2), "TEAM")
    body.box((0.03, 1.5, 1.2), (-1.21, 1.75, 2.6), "OLIVE_D")                    # сдвижная дверь
    body.cyl(0.45, 6.4, (0, 2.55, -7.5), "OLIVE", sections=8, r2=0.22)            # хвостовая балка
    tbox(body, 0.25, 1.4, 0.18, 0.8, 1.9, (0, 2.5, -10.7), "OLIVE", shift=(0, -0.6))  # концевая балка
    body.box((2.6, 0.08, 0.6), (0, 2.55, -9.4), "OLIVE_D")                       # стабилизатор
    body.box((0.04, 0.5, 0.5), (0.2, 3.2, -10.9), "TEAM")
    body.cyl(0.35, 0.45, (0, 3.85, 0.4), "STEEL_D", sections=8, rot=UP)          # вал
    rot = m.node("rotor_main", parent="body", pivot=(0, 4.15, 0.4))
    rot.cyl(0.4, 0.3, (0, 4.15, 0.4), "STEEL_D", sections=8, rot=UP)
    for i in range(5):
        blade = trimesh.creation.box(extents=(0.5, 0.06, 8.2))
        blade.apply_translation((0, 0, 4.3))
        blade.apply_transform(_rot_matrix((0, i * 72, 0)))
        blade.apply_translation((0, 4.25, 0.4))
        rot.add(blade, "GUNMETAL")
    tail = m.node("rotor_tail", parent="body", pivot=(-0.32, 3.55, -11.2))       # рулевой винт слева
    tail.cyl(0.14, 0.2, (-0.32, 3.55, -11.2), "STEEL_D", sections=6, rot=ALONG_X)
    for i in range(3):
        b = trimesh.creation.box(extents=(0.05, 0.28, 1.9))
        b.apply_translation((0, 0, 0.95))
        b.apply_transform(_rot_matrix((i * 120, 0, 0)))
        b.apply_translation((-0.36, 3.55, -11.2))
        tail.add(b, "GUNMETAL")
    return m


def build_all(reg):
    reg("vehicles", veh_bmp(), unit="bmp")
    reg("vehicles", veh_tank(), unit="tank")
    reg("vehicles", veh_heli(), unit="heli")
