"""
characters.py — детали персонажей, которые меширует Blender (blmesh/bl_worker): Skin-цепочки (повязки,
лямки), эллипсоиды (поля панамы, зоб, кулаки), коробки с фаской (бронежилет, подсумки, оружие), цилиндры.
Сами тела с v4 — модель Kenney (kenney.py, D-11); детали — палитровые и с гладкими нормалями.
"""
from __future__ import annotations

import math

import numpy as np

from lowpoly import _rot_matrix

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
