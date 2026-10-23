"""
landmarks.py — ручные модели ориентиров, которые OSM даёт только контуром (docs/04_map_moscow.md §5):
  * чаша арены «Лужники» с одним входом на юге (поле — площадка эвакуации);
  * стены и башни Новодевичьего монастыря с двумя воротами.

Функции возвращают (tris_by_color, blocked_polys): треугольники в мировых метрах (X восток, Y вверх, Z юг)
и полигоны XZ, которые непроходимы в navgrid.
"""
from __future__ import annotations

import math

import numpy as np
from shapely.geometry import LineString, Point, Polygon, box
from shapely.affinity import rotate, translate
from shapely.ops import unary_union


def _quad(a, b, c, d):
    """Две грани a-b-c, a-c-d (обход против часовой при взгляде с лицевой стороны)."""
    return [a, b, c, a, c, d]


def _ray_dist(poly: Polygon, cx, cz, ang, rmax=600.0):
    ray = LineString([(cx, cz), (cx + math.cos(ang) * rmax, cz + math.sin(ang) * rmax)])
    hit = ray.intersection(poly.exterior)
    if hit.is_empty:
        return None
    pts = [hit] if hit.geom_type == "Point" else [g for g in getattr(hit, "geoms", []) if g.geom_type == "Point"]
    if not pts:
        return None
    return max(math.hypot(p.x - cx, p.y - cz) for p in pts)


class Acc:
    def __init__(self):
        self.by_color: dict[str, list] = {}

    def tri(self, color, pts):
        self.by_color.setdefault(color, []).extend(pts)

    def quad(self, color, a, b, c, d):
        self.tri(color, _quad(a, b, c, d))

    def prism(self, poly: Polygon, y0, y1, side, top=None):
        """Вертикальная экструзия полигона с крышкой."""
        import trimesh
        try:
            m = trimesh.creation.extrude_polygon(poly, y1 - y0)
        except Exception:
            return
        M = np.array([[1, 0, 0, 0], [0, 0, 1, 0], [0, 1, 0, 0], [0, 0, 0, 1]], dtype=float)
        m.apply_transform(M)
        m.apply_translation((0, y0, 0))
        tri = m.vertices[m.faces]
        n = m.face_normals
        up = n[:, 1] > 0.7
        self.tri(top or side, tri[up].reshape(-1, 3).tolist())
        self.tri(side, tri[~up].reshape(-1, 3).tolist())

    def flat(self, poly: Polygon, y, color):
        import trimesh
        try:
            v2, f = trimesh.creation.triangulate_polygon(poly)
        except Exception:
            return
        v = np.c_[v2[:, 0], np.full(len(v2), y), v2[:, 1]]
        self.tri(color, v[f][:, ::-1, :].reshape(-1, 3).tolist())

    def result(self):
        return {c: np.array(p, dtype=np.float64).reshape(-1, 3, 3) for c, p in self.by_color.items() if p}


# ====================================================================== арена
# Профиль трибун (t по радиусу 0..1, y). Реальная чаша ~40 м закрывала бы поле от RTS-камеры —
# стилизуем вдвое ниже ради читаемости (арт-библия §2: читаемость сверху важнее реализма).
STAND = [(0.00, 0.0), (0.00, 1.6), (0.45, 7.5), (0.45, 8.5), (0.85, 15.0), (0.85, 18.0), (1.00, 18.0)]
ROOF_Y = 19.0
STAND_COLORS = ["CONCRETE_L", "CIV_RED", "CONCRETE", "CIV_RED", "CONCRETE_L", "CONCRETE_L"]


def arena_mesh(outer: Polygon, inner: Polygon | None, segments=96, gate_width=16.0):
    """Чаша стадиона по реальному контуру. Вход — разрыв трибун строго на юг (+Z)."""
    if inner is None or inner.area < 1000:
        c = outer.centroid
        inner = Polygon([(c.x + (x - c.x) * 0.6, c.y + (z - c.y) * 0.6) for x, z in outer.exterior.coords])
    cx, cz = inner.centroid.x, inner.centroid.y
    acc = Acc()
    ri, ro = [], []
    for k in range(segments):
        a = 2 * math.pi * k / segments
        ri.append(_ray_dist(inner, cx, cz, a) or 60.0)
        ro.append(max((_ray_dist(outer, cx, cz, a) or 140.0), ri[-1] + 30.0))
    gate_ang = math.pi / 2  # +Z = юг
    blocked = []
    for k in range(segments):
        k2 = (k + 1) % segments
        a1, a2 = 2 * math.pi * k / segments, 2 * math.pi * (k + 1) / segments
        am = (a1 + a2) / 2
        rmid = (ri[k] + ro[k]) / 2
        lateral = abs(rmid * math.sin(am - gate_ang))
        if math.cos(am - gate_ang) > 0 and lateral < gate_width * 0.75:
            continue  # проход на поле
        u1 = (math.cos(a1), math.sin(a1)); u2 = (math.cos(a2), math.sin(a2))

        def P(t, y, kk, u):
            r = ri[kk] + (ro[kk] - ri[kk]) * t
            return (cx + u[0] * r, y, cz + u[1] * r)

        aisle = (k % 8 == 0)
        for j in range(len(STAND) - 1):
            (t0, y0), (t1, y1) = STAND[j], STAND[j + 1]
            col = STAND_COLORS[j]
            if aisle and col == "CIV_RED":
                col = "WHITE"
            acc.quad(col, P(t0, y0, k, u1), P(t0, y0, k2, u2), P(t1, y1, k2, u2), P(t1, y1, k, u1))
        # внешний фасад: чередуем бетон и стекло — силуэт «Лужников» сверху и сбоку
        fcol = "GLASS" if k % 2 else "CONCRETE_L"
        acc.quad(fcol, P(1, 36, k, u1), P(1, 36, k2, u2), P(1, 0, k2, u2), P(1, 0, k, u1))
        # крыша-козырёк над верхним ярусом
        acc.quad("WHITE", P(0.62, 37.5, k, u1), P(0.62, 37.5, k2, u2), P(1.0, 37.5, k2, u2), P(1.0, 37.5, k, u1))
        acc.quad("CONCRETE", P(1.0, 36.0, k, u1), P(1.0, 36.0, k2, u2), P(0.62, 36.0, k2, u2), P(0.62, 36.0, k, u1))
        acc.quad("CONCRETE_L", P(0.62, 36.0, k, u1), P(0.62, 36.0, k2, u2), P(0.62, 37.5, k2, u2), P(0.62, 37.5, k, u1))
        blocked.append(Polygon([P(0, 0, k, u1)[::2], P(0, 0, k2, u2)[::2], P(1, 0, k2, u2)[::2], P(1, 0, k, u1)[::2]]))
        # торцы у прохода
        prev_open = _gate_seg(k - 1, segments, ri, ro, gate_ang, gate_width)
        next_open = _gate_seg(k + 1, segments, ri, ro, gate_ang, gate_width)
        if prev_open:
            _cap(acc, [P(t, y, k, u1) for t, y in STAND])
        if next_open:
            _cap(acc, [P(t, y, k2, u2) for t, y in STAND][::-1])
    _pitch(acc, inner, cx, cz)
    gate_poly = _gate_floor(cx, cz, ri, ro, segments, gate_width)
    acc.flat(gate_poly, 0.05, "CONCRETE")
    info = {"center": [round(cx, 1), round(cz, 1)],
            "inner_r": [round(min(ri), 1), round(max(ri), 1)], "outer_r": [round(min(ro), 1), round(max(ro), 1)],
            "gate": [round(cx, 1), round(cz + (ri[segments // 4] + ro[segments // 4]) / 2, 1)],
            "gate_outer": [round(cx, 1), round(cz + ro[segments // 4] + 6, 1)],
            "field_poly": [[round(x, 1), round(z, 1)] for x, z in inner.simplify(2.0).exterior.coords]}
    return acc.result(), unary_union(blocked).buffer(0.5), info


def _gate_seg(k, n, ri, ro, gate_ang, gate_width):
    k %= n
    am = 2 * math.pi * (k + 0.5) / n
    rmid = (ri[k] + ro[k]) / 2
    return math.cos(am - gate_ang) > 0 and abs(rmid * math.sin(am - gate_ang)) < gate_width * 0.75


def _cap(acc, prof):
    base = [(p[0], 0.0, p[2]) for p in prof]
    for a, b, a0, b0 in zip(prof[:-1], prof[1:], base[:-1], base[1:]):
        acc.quad("CONCRETE", a0, b0, b, a)


def _gate_floor(cx, cz, ri, ro, n, w):
    k = n // 4
    return box(cx - w, cz + ri[k] - 4, cx + w, cz + ro[k] + 8)


def _pitch(acc, inner: Polygon, cx, cz):
    acc.flat(inner, 0.03, "GRASS_D")
    mrr = inner.minimum_rotated_rectangle
    xs, zs = mrr.exterior.coords.xy
    e0 = (xs[1] - xs[0], zs[1] - zs[0]); e1 = (xs[2] - xs[1], zs[2] - zs[1])
    major = e0 if math.hypot(*e0) > math.hypot(*e1) else e1
    ang = math.degrees(math.atan2(major[1], major[0]))
    L, W = 105.0, 68.0
    for s in range(10):  # полосы газона
        strip = box(-L / 2 + s * L / 10, -W / 2, -L / 2 + (s + 1) * L / 10, W / 2)
        acc.flat(_place(strip, ang, cx, cz), 0.06, "GRASS" if s % 2 == 0 else "LEAF")
    lines = [box(-L / 2, -W / 2, L / 2, -W / 2 + 0.3), box(-L / 2, W / 2 - 0.3, L / 2, W / 2),
             box(-L / 2, -W / 2, -L / 2 + 0.3, W / 2), box(L / 2 - 0.3, -W / 2, L / 2, W / 2),
             box(-0.15, -W / 2, 0.15, W / 2),
             Point(0, 0).buffer(9.15, 16).difference(Point(0, 0).buffer(8.85, 16)),
             box(-L / 2, -20.15, -L / 2 + 16.5, 20.15).difference(box(-L / 2, -19.85, -L / 2 + 16.2, 19.85)),
             box(L / 2 - 16.5, -20.15, L / 2, 20.15).difference(box(L / 2 - 16.2, -19.85, L / 2, 19.85))]
    for ln in lines:
        acc.flat(_place(ln, ang, cx, cz), 0.08, "WHITE")


def _place(g, ang, cx, cz):
    return translate(rotate(g, ang, origin=(0, 0)), cx, cz)


# ====================================================================== форт
def fortress_mesh(hull: Polygon, gate_dirs=((0, -1), (0, 1)), gate_w=8.0, wall_t=3.2, wall_h=9.0):
    """Стены монастыря по выпуклой оболочке реальных стен OSM; башни — в вершинах, ворота — на севере и юге."""
    acc = Acc()
    ring = hull.exterior
    c = hull.centroid
    gates = []
    for dx, dz in gate_dirs:
        far = LineString([(c.x, c.y), (c.x + dx * 2000, c.y + dz * 2000)])
        hit = far.intersection(ring)
        if not hit.is_empty:
            p = hit if hit.geom_type == "Point" else list(hit.geoms)[0]
            gates.append((p.x, p.y))
    wall = ring.buffer(wall_t / 2, cap_style=2, join_style=2)
    for gx, gz in gates:
        wall = wall.difference(Point(gx, gz).buffer(gate_w / 2 + 0.5, 8).envelope)
    blocked = []
    for p in ([wall] if wall.geom_type == "Polygon" else list(wall.geoms)):
        acc.prism(p, 0.0, wall_h, "BRICK")
        acc.prism(p, wall_h, wall_h + 0.6, "WHITE")
        blocked.append(p)
    # зубцы
    L = ring.length
    d = 0.0
    while d < L:
        pt = ring.interpolate(d)
        if all(math.hypot(pt.x - gx, pt.y - gz) > gate_w for gx, gz in gates):
            acc.prism(Point(pt.x, pt.y).buffer(0.8, 4), wall_h + 0.6, wall_h + 2.0, "BRICK")
        d += 3.2
    # башни
    pts = list(hull.simplify(6.0).exterior.coords)[:-1]
    towers = []
    for x, z in pts:
        towers.append((x, z, 5.0, 17.0))
    for gx, gz in gates:
        towers.append((gx + gate_w, gz, 4.0, 22.0))
        towers.append((gx - gate_w, gz, 4.0, 22.0))
    for x, z, r, h in towers:
        oct_ = Point(x, z).buffer(r, 2)
        acc.prism(oct_, 0.0, h, "BRICK")
        acc.prism(Point(x, z).buffer(r + 0.3, 2), h, h + 0.8, "WHITE")
        _tent_roof(acc, x, z, r + 0.3, h + 0.8, 7.0)
        blocked.append(oct_)
    info = {"center": [round(c.x, 1), round(c.y, 1)], "gates": [[round(x, 1), round(z, 1)] for x, z in gates],
            "hull": [[round(x, 1), round(z, 1)] for x, z in hull.exterior.coords]}
    return acc.result(), unary_union(blocked), info


def _tent_roof(acc, x, z, r, y, h, n=8):
    for k in range(n):
        a1, a2 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        p1 = (x + math.cos(a1) * r, y, z + math.sin(a1) * r)
        p2 = (x + math.cos(a2) * r, y, z + math.sin(a2) * r)
        acc.tri("OLIVE_D" if k % 2 else "OLIVE", [p1, (x, y + h, z), p2])
