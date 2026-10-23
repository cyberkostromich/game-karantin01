#!/usr/bin/env python3
"""
build_city.py — собирает low-poly город из выгрузки OpenStreetMap (Overpass JSON).

Выход (в --out):
  chunks/chunk_<cx>_<cz>.glb   — кварталы 128×128 м: узлы buildings / ground / water
  landmarks/*.glb              — арена «Лужники» (чаша с южным входом), стены Новодевичьего
  navgrid.png                  — сетка 2 м: 0 = непроходимо, 128 = бездорожье, 200 = тротуар, 255 = дорога
  minimap.png                  — цветная подложка миникарты (1 пикс = 4 м)
  resources.json               — деревья (wood), остовы (iron), лут-POI
  spawns.json                  — укрытия мирных у входов зданий (residential/shop/school/hospital/rooftop/metro_exit)
  pois.json                    — POI сценария, привязанные к реальным объектам OSM (станции метро, стадион)
  zones.json                   — геометрия арены, форта, высоты
  report.json                  — статистика

Система координат: X → восток, Z → юг (север = -Z), Y вверх, 1 ед. = 1 м, (0,0) = center из map-json.

Пример:
  curl -s -X POST https://overpass-api.de/api/interpreter --data-urlencode data@overpass_luzhniki.ql -o luzhniki.osm.json
  python3 build_city.py --osm luzhniki.osm.json --map ../../data/map_luzhniki.json --out ../../assets/city/luzhniki

Зависимости: pip install trimesh shapely mapbox_earcut numpy pillow scipy
"""
from __future__ import annotations

import argparse
import json
import math
import random
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np
import trimesh
from PIL import Image, ImageDraw
from shapely.geometry import LineString, MultiPolygon, Point, Polygon, box
from shapely.ops import unary_union

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "asset_gen"))
from lowpoly import _MATERIAL, PALETTE, hex_rgb, uv_for  # noqa: E402  (общая палитра)
from landmarks import arena_mesh, fortress_mesh  # noqa: E402

ROAD_WIDTH = {"motorway": 24, "trunk": 20, "primary": 16, "secondary": 12, "tertiary": 10,
              "motorway_link": 8, "trunk_link": 8, "primary_link": 8, "secondary_link": 7, "tertiary_link": 7,
              "residential": 7, "unclassified": 7, "living_street": 6, "service": 4.5,
              "pedestrian": 6, "footway": 2.5, "path": 2, "cycleway": 2.5, "steps": 3, "track": 3}
CAR_ROADS = {"motorway", "trunk", "primary", "secondary", "tertiary", "residential", "unclassified", "service",
             "living_street", "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link"}
WRECK_ROADS = {"primary", "secondary", "tertiary", "trunk"}
DEFAULT_LEVELS = {"apartments": 9, "residential": 9, "house": 2, "detached": 2, "garage": 1, "garages": 1, "shed": 1,
                  "commercial": 4, "retail": 2, "office": 8, "industrial": 2, "warehouse": 2, "school": 4,
                  "kindergarten": 2, "hospital": 6, "university": 6, "church": 3, "cathedral": 5, "stadium": 4,
                  "yes": 5, "construction": 3, "kiosk": 1, "service": 1, "transportation": 2, "train_station": 3,
                  "dormitory": 9, "government": 5, "guardhouse": 1, "sports_centre": 3, "parking": 3}
LEVEL_H = 3.0
# Кто прячется в зданиях (civilians.json/spawn_groups/poi_types)
SPAWN_KIND = {"apartments": "residential", "residential": "residential", "house": "residential", "dormitory": "residential",
              "detached": "residential", "yes": "residential", "retail": "shop", "commercial": "shop", "kiosk": "shop",
              "school": "school", "kindergarten": "school", "university": "school", "college": "school",
              "hospital": "hospital", "clinic": "hospital"}
FACADE_ACCENT = {"PANEL_WHITE": "TILE_BLUE", "PANEL_BEIGE": "BRICK", "STALIN_YEL": "WHITE", "BRICK_L": "CONCRETE_L",
                 "CONCRETE_D": "CONCRETE_D", "CONCRETE_L": "CONCRETE", "WHITE": "CONCRETE_L"}


def wall_color(tags, levels, rnd):
    b = tags.get("building", "yes")
    if b in ("church", "cathedral", "chapel", "monastery") or tags.get("amenity") == "place_of_worship":
        return "WHITE"
    if b in ("garage", "garages", "shed", "industrial", "warehouse", "service", "guardhouse"):
        return "CONCRETE_D"
    if b in ("stadium", "sports_centre"):
        return "CONCRETE_L"
    col = tags.get("building:colour", "")
    if col in ("red", "brown", "maroon", "#8b4513") or tags.get("building:material") == "brick":
        return "BRICK_L"
    if col in ("yellow", "beige", "#ffff00"):
        return "STALIN_YEL"
    if levels >= 14:
        return "PANEL_BEIGE" if rnd.random() < 0.5 else "PANEL_WHITE"
    if levels >= 9:
        return "PANEL_WHITE"
    if levels >= 6:
        return "STALIN_YEL" if rnd.random() < 0.4 else rnd.choice(["PANEL_WHITE", "BRICK_L"])
    return "BRICK_L" if levels >= 4 else rnd.choice(["PANEL_BEIGE", "BRICK_L", "CONCRETE_L"])


def parse_float(s, default=None):
    try:
        return float(str(s).replace(",", ".").split(";")[0].split()[0])
    except Exception:
        return default


class Projector:
    def __init__(self, lat0, lon0):
        self.lat0, self.lon0 = lat0, lon0
        self.kx = 111320.0 * math.cos(math.radians(lat0))
        self.kz = 110540.0

    def __call__(self, lat, lon):
        return ((lon - self.lon0) * self.kx, -(lat - self.lat0) * self.kz)


# ------------------------------------------------------------------ чтение OSM
def load_osm(paths):
    nodes, ways, rels = {}, {}, {}
    for path in paths:
        data = json.loads(Path(path).read_text())
        for e in data.get("elements", []):
            if e["type"] == "node":
                if e["id"] not in nodes or "tags" in e:
                    nodes[e["id"]] = e
            elif e["type"] == "way":
                ways[e["id"]] = e
            elif e["type"] == "relation":
                rels[e["id"]] = e
    return nodes, ways, list(rels.values())


def way_coords(w, nodes, P):
    pts = []
    for nid in w.get("nodes", []):
        n = nodes.get(nid)
        if n and "lat" in n:
            pts.append(P(n["lat"], n["lon"]))
    return pts


def way_polygon(w, nodes, P):
    pts = way_coords(w, nodes, P)
    if len(pts) < 4 or pts[0] != pts[-1]:
        if len(pts) >= 3:
            pts = pts + [pts[0]]
        else:
            return None
    try:
        poly = Polygon(pts).buffer(0)
        return poly if poly.area > 1 else None
    except Exception:
        return None


def relation_polygons(r, ways, nodes, P):
    """Сборка multipolygon: склеиваем outer-ветки в кольца, вычитаем inner."""
    outers, inners = [], []
    for m in r.get("members", []):
        if m["type"] != "way" or m["ref"] not in ways:
            continue
        coords = way_coords(ways[m["ref"]], nodes, P)
        if len(coords) >= 2:
            (inners if m.get("role") == "inner" else outers).append(coords)

    def rings(segs):
        segs = [list(s) for s in segs]
        out = []
        while segs:
            ring = segs.pop(0)
            changed = True
            while changed and ring[0] != ring[-1]:
                changed = False
                for i, s in enumerate(segs):
                    if s[0] == ring[-1]:
                        ring += s[1:]; segs.pop(i); changed = True; break
                    if s[-1] == ring[-1]:
                        ring += s[::-1][1:]; segs.pop(i); changed = True; break
            if len(ring) >= 4:
                try:
                    p = Polygon(ring).buffer(0)
                    if p.area > 1:
                        out.append(p)
                except Exception:
                    pass
        return out

    o, i = rings(outers), rings(inners)
    if not o:
        return None, []
    g = unary_union(o)
    if i:
        g = g.difference(unary_union(i))
    return g, i


def polys_of(g):
    if g is None or g.is_empty:
        return []
    if isinstance(g, Polygon):
        return [g]
    if isinstance(g, MultiPolygon):
        return list(g.geoms)
    return [p for p in getattr(g, "geoms", []) if isinstance(p, Polygon)]


# ------------------------------------------------------------------ геометрия → меш
class MeshAcc:
    """Аккумулятор треугольников с палитровыми UV (плоский шейдинг)."""

    def __init__(self):
        self.V, self.UV = [], []

    def add_tris(self, tris, color):
        tris = np.asarray(tris, dtype=np.float64).reshape(-1, 3)
        if not len(tris):
            return
        self.V.append(tris)
        self.UV.append(np.tile(uv_for(color), (len(tris), 1)))

    def add_mesh(self, m: trimesh.Trimesh, color_fn):
        tri = m.vertices[m.faces]
        cols = [color_fn(nn) for nn in m.face_normals]
        for c in set(cols):
            sel = np.array([cc == c for cc in cols])
            self.add_tris(tri[sel], c)

    def extend(self, other: "MeshAcc"):
        self.V += other.V
        self.UV += other.UV

    def build(self):
        if not self.V:
            return None
        V = np.vstack(self.V); UV = np.vstack(self.UV)
        F = np.arange(len(V)).reshape(-1, 3)
        return trimesh.Trimesh(V, F, process=False, visual=trimesh.visual.TextureVisuals(uv=UV, material=_MATERIAL))

    def tri_count(self):
        return sum(len(v) for v in self.V) // 3


Y_UP = np.array([[1, 0, 0, 0], [0, 0, 1, 0], [0, 1, 0, 0], [0, 0, 0, 1]], dtype=float)  # (x, y2d, h) → (x, h, z)


def extrude_xz(poly: Polygon, h, y0=0.0):
    m = trimesh.creation.extrude_polygon(poly, h)
    m.apply_transform(Y_UP)       # отражение; trimesh сам разворачивает обход граней при det<0
    m.apply_translation((0, y0, 0))
    return m


def flat_xz(poly: Polygon, y):
    """Плоский полигон (только верх) на высоте y."""
    try:
        v2, f = trimesh.creation.triangulate_polygon(poly)
    except Exception:
        return None
    v = np.c_[v2[:, 0], np.full(len(v2), y), v2[:, 1]]
    return v[f][:, ::-1, :]  # нормаль вверх


def ring_walls(poly: Polygon, y0, y1, outward=True):
    """Вертикальные стенки по контуру полигона (набережная, бортик моста). Нормали — наружу из полигона."""
    tris = []
    for ring in [poly.exterior] + list(poly.interiors):
        c = list(ring.coords)
        ccw = ring.is_ccw
        for (ax, az), (bx, bz) in zip(c[:-1], c[1:]):
            a0, a1, b0, b1 = (ax, y0, az), (ax, y1, az), (bx, y0, bz), (bx, y1, bz)
            quad = [a0, b0, b1, a0, b1, a1]
            if ccw != outward:
                quad = [a0, b1, b0, a0, a1, b1]
            tris += quad
    return np.array(tris).reshape(-1, 3, 3) if tris else None


# ------------------------------------------------------------------ разбор OSM
class City:
    def __init__(self):
        self.buildings, self.roads, self.footways, self.bridges = [], [], [], []
        self.water, self.parks, self.trees, self.shops = [], [], [], []
        self.walls, self.entrances, self.stations = [], [], {}
        self.stadium = None


def collect(nodes, ways, rels, P, area, rnd) -> City:
    c = City()
    for w in ways.values():
        t = w.get("tags", {})
        if "building" in t or "building:part" in t:
            if t.get("building") in ("roof",) or t.get("layer", "0").startswith("-") or t.get("location") == "underground":
                continue
            p = way_polygon(w, nodes, P)
            if p is not None and p.intersects(area):
                c.buildings.append((p.intersection(area), t))
        elif "highway" in t:
            hw = t["highway"]
            if hw in ROAD_WIDTH and t.get("tunnel") not in ("yes", "building_passage") and not t.get("layer", "0").startswith("-"):
                co = way_coords(w, nodes, P)
                if len(co) >= 2:
                    wdt = parse_float(t.get("width"), ROAD_WIDTH[hw]) or ROAD_WIDTH[hw]
                    rec = (LineString(co), min(wdt, 30.0), hw)
                    (c.roads if hw in CAR_ROADS or hw == "pedestrian" else c.footways).append(rec)
                    if t.get("bridge") in ("yes", "viaduct"):
                        c.bridges.append(rec)
        elif t.get("natural") == "water" or t.get("waterway") == "riverbank" or t.get("landuse") == "reservoir":
            p = way_polygon(w, nodes, P)
            if p is not None:
                c.water.append(p)
        elif t.get("leisure") in ("park", "garden") or t.get("landuse") in ("grass", "forest", "meadow", "recreation_ground") \
                or t.get("natural") in ("wood", "scrub"):
            p = way_polygon(w, nodes, P)
            if p is not None:
                c.parks.append((p, t))
        if t.get("barrier") in ("wall", "city_wall"):
            co = way_coords(w, nodes, P)
            if len(co) >= 2:
                c.walls.append(LineString(co))
        if t.get("shop") or t.get("amenity") in ("pharmacy", "fuel"):
            p = way_polygon(w, nodes, P)
            if p is not None:
                c.shops.append((p.centroid.x, p.centroid.y, t))

    for r in rels:
        t = r.get("tags", {})
        if t.get("type") != "multipolygon":
            continue
        if t.get("natural") == "water" or t.get("waterway") == "riverbank":
            g, _ = relation_polygons(r, ways, nodes, P)
            c.water += polys_of(g)
        elif "building" in t:
            g, inners = relation_polygons(r, ways, nodes, P)
            if t.get("building") == "stadium" and "Лужники" in t.get("name", ""):
                c.stadium = (g, inners)
                continue
            for p in polys_of(g):
                if p.intersects(area):
                    c.buildings.append((p.intersection(area), t))
        elif t.get("leisure") in ("park", "garden") or t.get("landuse") in ("grass", "forest"):
            g, _ = relation_polygons(r, ways, nodes, P)
            c.parks += [(p, t) for p in polys_of(g)]

    for n in nodes.values():
        t = n.get("tags", {})
        if "lat" not in n or not t:
            continue
        x, z = P(n["lat"], n["lon"])
        if t.get("railway") == "station" and t.get("station") == "subway":
            c.stations[t.get("name", "")] = (x, z)
        if not area.contains(Point(x, z)):
            continue
        if t.get("natural") == "tree":
            c.trees.append({"x": round(x, 1), "z": round(z, 1), "kind": rnd.choice(["linden", "birch", "poplar"]), "wood": 40})
        if t.get("shop") or t.get("amenity") in ("pharmacy", "fuel"):
            c.shops.append((x, z, t))
        if t.get("railway") == "subway_entrance":
            c.entrances.append((x, z))
    return c


# ------------------------------------------------------------------ основной пайплайн
def raster(img_draw, geom, val, x0, z0, cell):
    for p in polys_of(geom):
        img_draw.polygon([((x - x0) / cell, (z - z0) / cell) for x, z in p.exterior.coords], fill=val)
        for hole in p.interiors:
            img_draw.polygon([((x - x0) / cell, (z - z0) / cell) for x, z in hole.coords], fill=128)


class Nav:
    """Обёртка над navgrid для пост-обработки (поиск ближайшей проходимой клетки)."""

    def __init__(self, img, x0, z0, cell):
        self.a = np.array(img); self.x0, self.z0, self.cell = x0, z0, cell
        self.h, self.w = self.a.shape

    def val(self, x, z):
        cx, cz = int((x - self.x0) / self.cell), int((z - self.z0) / self.cell)
        if 0 <= cx < self.w and 0 <= cz < self.h:
            return int(self.a[cz, cx])
        return 0

    def nearest_walkable(self, x, z, rmax=40.0, min_val=100):
        if self.val(x, z) >= min_val:
            return x, z
        step = self.cell
        r = step
        while r <= rmax:
            n = max(8, int(2 * math.pi * r / step))
            best = None
            for k in range(n):
                a = 2 * math.pi * k / n
                px, pz = x + math.cos(a) * r, z + math.sin(a) * r
                if self.val(px, pz) >= min_val:
                    best = (px, pz); break
            if best:
                return best
            r += step
        return None


def build_arena(c: City, P, cfg):
    if c.stadium is None:
        return None
    g, inners = c.stadium
    outer = max(polys_of(g), key=lambda p: p.area)
    outer = Polygon(outer.exterior)
    inner = max(inners, key=lambda p: p.area) if inners else None
    tris, blocked, info = arena_mesh(outer, inner)
    info["outer_poly"] = outer
    return tris, blocked, info


def build_fortress(c: City, poi_xz, nodes, ways, rels, P):
    """OSM почти не содержит стен Новодевичьего — собираем оболочку по храмам и уцелевшим кускам стен."""
    center = Point(*poi_xz)
    for r in rels:
        if "Смоленский собор" in r.get("tags", {}).get("name", ""):
            g, _ = relation_polygons(r, ways, nodes, P)
            if g is not None:
                center = g.centroid
    parts = [p.representative_point() for p, _ in c.buildings
             if p.representative_point().distance(center) < 125 and p.area < 4000]
    parts += [w for w in c.walls if w.distance(center) < 135 and w.length < 60]
    if len(parts) < 3:
        return None
    hull = unary_union(parts).convex_hull.buffer(22, join_style=2).simplify(4.0)
    if hull.geom_type != "Polygon" or hull.area < 5000:
        return None
    tris, blocked, info = fortress_mesh(hull)
    info["hull_poly"] = hull
    return tris, blocked, info


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--osm", required=True, nargs="+", help="один или несколько Overpass JSON")
    ap.add_argument("--map", required=True, help="data/map_*.json (center, bbox, pois)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--bbox", choices=["mvp", "full"], default="mvp")
    ap.add_argument("--chunk", type=float, default=128.0)
    ap.add_argument("--cell", type=float, default=2.0)
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args()

    rnd = random.Random(a.seed)
    cfg = json.loads(Path(a.map).read_text())
    P = Projector(cfg["center"]["lat"], cfg["center"]["lon"])
    bb = cfg["bbox_" + a.bbox]
    x0, z1 = P(bb["south"], bb["west"]); x1, z0 = P(bb["north"], bb["east"])
    area = box(x0, z0, x1, z1)
    out = Path(a.out)
    (out / "chunks").mkdir(parents=True, exist_ok=True)
    (out / "landmarks").mkdir(parents=True, exist_ok=True)
    for old in (out / "chunks").glob("*.glb"):
        old.unlink()

    nodes, ways, rels = load_osm(a.osm)
    c = collect(nodes, ways, rels, P, area, rnd)
    pois_cfg = {p["id"]: p for p in cfg.get("pois", [])}
    stats = defaultdict(int)

    # ---- ориентиры
    arena = build_arena(c, P, cfg)
    arena_poly = arena[2]["outer_poly"] if arena else None
    nov = pois_cfg.get("novodevichy")
    fort = build_fortress(c, P(nov["lat"], nov["lon"]), nodes, ways, rels, P) if nov else None
    fort_hull = fort[2]["hull_poly"] if fort else None
    if arena_poly is not None:  # OSM-части стадиона заменяем своей чашей
        c.buildings = [(p, t) for p, t in c.buildings if not p.representative_point().within(arena_poly.buffer(5))]
    if fort_hull is not None:  # контур монастыря из OSM (building=monastery) не экструдируем — внутри двор
        c.buildings = [(p, t) for p, t in c.buildings
                       if not (p.area > fort_hull.area * 0.5 and p.intersects(fort_hull))]

    water_u = unary_union(c.water).intersection(area) if c.water else None
    road_polys = unary_union([ls.buffer(wd / 2, cap_style=2, join_style=2) for ls, wd, _ in c.roads]).intersection(area) if c.roads else None
    foot_polys = unary_union([ls.buffer(wd / 2) for ls, wd, _ in c.footways]).intersection(area) if c.footways else None
    if foot_polys is not None and road_polys is not None:
        foot_polys = foot_polys.difference(road_polys)
    bridge_polys = unary_union([ls.buffer(max(wd, 3.0) / 2, cap_style=2) for ls, wd, _ in c.bridges]).intersection(area) if c.bridges else None
    park_u = unary_union([p for p, _ in c.parks]).intersection(area) if c.parks else None
    if park_u is not None and water_u is not None:
        park_u = park_u.difference(water_u)
    if arena_poly is not None:
        for name in ("road_polys", "foot_polys", "park_u"):
            g = locals()[name]
            if g is not None:
                locals()[name]  # noqa
        road_polys = road_polys.difference(arena_poly) if road_polys is not None else None
        foot_polys = foot_polys.difference(arena_poly) if foot_polys is not None else None
        park_u = park_u.difference(arena_poly) if park_u is not None else None

    # ---- navgrid
    cell = a.cell
    gw, gh = int(math.ceil((x1 - x0) / cell)), int(math.ceil((z1 - z0) / cell))
    img = Image.new("L", (gw, gh), 128)
    d = ImageDraw.Draw(img)
    raster(d, foot_polys, 200, x0, z0, cell)
    raster(d, road_polys, 255, x0, z0, cell)
    raster(d, water_u, 0, x0, z0, cell)
    raster(d, bridge_polys, 255, x0, z0, cell)  # мосты — поверх воды: это узкие места, а не преграды
    for poly, _ in c.buildings:
        for p in polys_of(poly):
            d.polygon([((x - x0) / cell, (z - z0) / cell) for x, z in p.exterior.coords], fill=0)
    if arena:
        raster(d, arena[2]["outer_poly"].difference(arena[1]).difference(unary_union([arena[1]])), 128, x0, z0, cell)
        raster(d, arena[1], 0, x0, z0, cell)
    if fort:
        raster(d, fort[1], 0, x0, z0, cell)
    img.save(out / "navgrid.png")
    nav = Nav(img, x0, z0, cell)

    # ---- ресурсы
    trees = [t for t in c.trees if nav.val(t["x"], t["z"]) == 128]
    if park_u is not None:
        dens = cfg["resource_nodes_from_osm"]["tree"]["park_density_per_100m2"]
        for p in polys_of(park_u):
            n = int(p.area / 100 * dens * 0.25)  # прореживаем ×0.25 ради производительности рендера и поиска
            minx, minz, maxx, maxz = p.bounds
            k = tries = 0
            while k < n and tries < n * 6:
                tries += 1
                x, z = rnd.uniform(minx, maxx), rnd.uniform(minz, maxz)
                if p.contains(Point(x, z)) and nav.val(x, z) == 128:
                    trees.append({"x": round(x, 1), "z": round(z, 1),
                                  "kind": rnd.choice(["linden", "linden", "birch", "pine", "poplar"]),
                                  "wood": cfg["resource_nodes_from_osm"]["tree"]["wood_per_node"]})
                    k += 1
    wcfg = cfg["resource_nodes_from_osm"]["wreck"]
    wrecks = []
    for ls, wd, hw in c.roads:
        if hw in WRECK_ROADS:
            L = ls.length; dd = rnd.uniform(0, 40)
            while dd < L:
                pt = ls.interpolate(dd)
                x, z = pt.x + rnd.uniform(-wd / 3, wd / 3), pt.y + rnd.uniform(-wd / 3, wd / 3)
                if area.contains(Point(x, z)) and nav.val(x, z) >= 200:
                    wrecks.append({"x": round(x, 1), "z": round(z, 1), "rot": round(rnd.uniform(0, 360)),
                                   "kind": rnd.choice(["sedan_red", "sedan_white", "sedan_burnt", "sedan_burnt", "truck", "trolleybus"]),
                                   "iron": wcfg["iron_per_node"]})
                dd += 100 / wcfg["per_100m_road"] * rnd.uniform(0.6, 1.4)
    loot = []
    for x, z, t in c.shops:
        s, am = t.get("shop", ""), t.get("amenity", "")
        kind = "grocery" if s in ("supermarket", "convenience", "greengrocer", "bakery", "butcher", "deli") else \
               "pharmacy" if am == "pharmacy" or s == "chemist" else \
               "car_service" if s in ("car_repair", "car_parts", "tyres") or am == "fuel" else \
               "hardware" if s in ("hardware", "doityourself", "trade") else None
        if kind:
            w = nav.nearest_walkable(x, z, 30)
            if w:
                loot.append({"x": round(w[0], 1), "z": round(w[1], 1), "type": kind, "name": t.get("name", "")})
    loot = _dedupe(loot, 25.0)

    # ---- укрытия мирных
    spawns = []
    for poly, t in c.buildings:
        for p in polys_of(poly):
            kind = SPAWN_KIND.get(t.get("building", "yes"))
            if t.get("amenity") in ("hospital", "clinic"):
                kind = "hospital"
            if not kind or p.area < 60:
                continue
            rp = p.representative_point()
            w = nav.nearest_walkable(rp.x, rp.y, 40)
            if w:
                spawns.append({"x": round(w[0], 1), "z": round(w[1], 1), "kind": kind})
            lv = parse_float(t.get("building:levels"), DEFAULT_LEVELS.get(t.get("building", "yes"), 5)) or 5
            if lv >= 9 and p.area > 300:
                spawns.append({"x": round(rp.x, 1), "z": round(rp.y, 1), "kind": "rooftop", "h": round(lv * LEVEL_H + 1)})
    for x, z in c.entrances:
        w = nav.nearest_walkable(x, z, 20)
        if w and area.contains(Point(*w)):
            spawns.append({"x": round(w[0], 1), "z": round(w[1], 1), "kind": "metro_exit"})
    if fort:
        hp = fort[2]["hull_poly"].buffer(-12)
        minx, minz, maxx, maxz = hp.bounds
        for _ in range(60):
            x, z = rnd.uniform(minx, maxx), rnd.uniform(minz, maxz)
            if hp.contains(Point(x, z)) and nav.val(x, z) >= 100:
                spawns.append({"x": round(x, 1), "z": round(z, 1), "kind": "fortress"})
    spawns = _dedupe(spawns, 6.0)

    # ---- меши чанков
    chunks = defaultdict(lambda: {"buildings": MeshAcc(), "ground": MeshAcc(), "water": MeshAcc()})

    def ck(x, z):
        return int(math.floor(x / a.chunk)), int(math.floor(z / a.chunk))

    for poly, t in c.buildings:
        for p in polys_of(poly):
            if _add_building(chunks[ck(p.centroid.x, p.centroid.y)]["buildings"], p, t, rnd):
                stats["buildings"] += 1
            else:
                stats["building_fail"] += 1

    def add_flat(geom, layer, y, color):
        for p in polys_of(geom):
            minx, minz, maxx, maxz = p.bounds
            for cx in range(int(math.floor(minx / a.chunk)), int(math.floor(maxx / a.chunk)) + 1):
                for cz in range(int(math.floor(minz / a.chunk)), int(math.floor(maxz / a.chunk)) + 1):
                    part = p.intersection(box(cx * a.chunk, cz * a.chunk, (cx + 1) * a.chunk, (cz + 1) * a.chunk))
                    for q in polys_of(part):
                        tri = flat_xz(q, y)
                        if tri is not None and len(tri):
                            chunks[(cx, cz)][layer].add_tris(tri, color)

    add_flat(water_u, "water", -0.7, "WATER")
    for p in polys_of(water_u):  # гранитная набережная: стенка от воды до земли
        tri = ring_walls(p, -0.7, 0.0, outward=False)
        if tri is not None:
            chunks[ck(p.centroid.x, p.centroid.y)]["ground"].add_tris(tri, "CONCRETE_D")
    add_flat(park_u, "ground", 0.02, "GRASS")
    add_flat(foot_polys, "ground", 0.04, "CONCRETE")
    add_flat(road_polys, "ground", 0.06, "ASPHALT")
    if bridge_polys is not None and water_u is not None:
        over = bridge_polys.intersection(water_u.buffer(2))
        add_flat(over, "ground", 0.12, "CONCRETE_L")
        for p in polys_of(over):
            tri = ring_walls(p, -0.7, 0.9)
            if tri is not None:
                chunks[ck(p.centroid.x, p.centroid.y)]["ground"].add_tris(tri, "CONCRETE")

    for (cx, cz), layers in chunks.items():
        sc = trimesh.Scene()
        for name, acc in layers.items():
            mm = acc.build()
            if mm is not None:
                sc.add_geometry(mm, node_name=name, geom_name=f"{name}_mesh")
                stats["tris"] += acc.tri_count()
        if sc.geometry:
            (out / "chunks" / f"chunk_{cx}_{cz}.glb").write_bytes(sc.export(file_type="glb", include_normals=True))
            stats["chunks"] += 1

    zones = {}
    for name, lm in (("arena", arena), ("fortress", fort)):
        if not lm:
            continue
        acc = MeshAcc()
        for col, tri in lm[0].items():
            acc.add_tris(tri, col)
        mm = acc.build()
        trimesh.Scene(mm).export(str(out / "landmarks" / f"{name}.glb"))
        stats["tris"] += acc.tri_count()
        zones[name] = {k: v for k, v in lm[2].items() if not k.endswith("_poly") or k == "field_poly"}

    # ---- подложка и миникарта
    g = MeshAcc()
    g.add_tris(flat_xz(area, -0.05), "GRASS_D")
    trimesh.Scene(g.build()).export(str(out / "ground.glb"))
    _minimap(out / "minimap.png", x0, z0, x1, z1, water_u, park_u, road_polys, foot_polys, bridge_polys,
             c.buildings, arena, fort)

    # ---- POI сценария → реальные объекты
    pois = _pois(cfg, P, area, c, nav, arena, fort, nodes)
    if arena:
        hq = cfg["safe_zone"]["hq_offset_m"]
        zones["arena"]["hq"] = [round(arena[2]["center"][0] + hq[0], 1), round(arena[2]["center"][1] + hq[2], 1)]

    (out / "resources.json").write_text(json.dumps({"trees": trees, "wrecks": wrecks, "loot": loot}, ensure_ascii=False))
    (out / "spawns.json").write_text(json.dumps(spawns, ensure_ascii=False))
    (out / "pois.json").write_text(json.dumps(pois, ensure_ascii=False, indent=1))
    (out / "zones.json").write_text(json.dumps(zones, ensure_ascii=False, indent=1))
    report = {"bounds_m": [round(x0, 1), round(z0, 1), round(x1, 1), round(z1, 1)],
              "size_m": [round(x1 - x0), round(z1 - z0)], "navgrid_px": [gw, gh], "cell_m": cell,
              "chunk_m": a.chunk, "buildings": stats["buildings"], "building_fail": stats["building_fail"],
              "chunks": stats["chunks"], "tris": stats["tris"], "roads": len(c.roads), "footways": len(c.footways),
              "bridges": len(c.bridges), "water_polys": len(c.water), "parks": len(c.parks), "trees": len(trees),
              "wrecks": len(wrecks), "loot": len(loot), "spawns": len(spawns),
              "arena": bool(arena), "fortress": bool(fort)}
    (out / "report.json").write_text(json.dumps(report, indent=1))
    print(json.dumps(report, indent=1))


def _dedupe(items, r):
    out = []
    grid = {}
    for it in items:
        k = (int(it["x"] // r), int(it["z"] // r), it.get("kind", it.get("type")))
        if k in grid:
            continue
        grid[k] = 1
        out.append(it)
    return out


def _add_building(acc: MeshAcc, p: Polygon, t, rnd) -> bool:
    p = p.simplify(0.6, preserve_topology=True)
    if p.area < 8:
        return False
    lv = parse_float(t.get("building:levels"), None)
    h = parse_float(t.get("height"), None)
    if h is None:
        lv = lv if lv is not None else DEFAULT_LEVELS.get(t.get("building", "yes"), 5)
        h = max(3.0, lv * LEVEL_H + 1.0)
    else:
        lv = lv or max(1, round(h / LEVEL_H))
    h = min(h, 120.0)
    minh = parse_float(t.get("min_height"), 0.0) or 0.0
    if h - minh < 1.0:
        return False
    col = wall_color(t, lv, rnd)
    try:
        body_h = h - minh - (0.9 if lv >= 4 else 0.0)
        m = extrude_xz(p, body_h, y0=minh)
        acc.add_mesh(m, lambda n, col=col: "ROOF_D" if n[1] > 0.7 else col)
        if lv >= 4:  # карниз/полоса верхнего этажа — читаемость силуэта сверху
            band = extrude_xz(p.buffer(0.25, join_style=2), 0.9, y0=minh + body_h)
            acc.add_mesh(band, lambda n, ac=FACADE_ACCENT.get(col, "CONCRETE_L"): "ROOF_D" if n[1] > 0.7 else ac)
    except Exception:
        return False
    if lv >= 9 and p.area > 200:  # машинное отделение лифта на крыше
        rp = p.representative_point()
        try:
            acc.add_mesh(extrude_xz(box(rp.x - 2.5, rp.y - 2, rp.x + 2.5, rp.y + 2), 3.0, y0=h),
                         lambda n: "CONCRETE_D" if n[1] < 0.7 else "ROOF_D")
        except Exception:
            pass
    return True


def _pois(cfg, P, area, c: City, nav: Nav, arena, fort, nodes):
    names = {"metro_sportivnaya": "Спортивная", "metro_frunzenskaya": "Фрунзенская", "metro_vorobyovy": "Воробьёвы горы"}
    substations = [p for p, t in c.buildings if t.get("power") == "substation"]
    masts = [P(n["lat"], n["lon"]) for n in nodes.values()
             if n.get("tags", {}).get("man_made") in ("mast", "tower") and n["tags"].get("tower:type") == "communication"]
    out = []
    for p in cfg.get("pois", []):
        x, z = P(p["lat"], p["lon"])
        src = "config"
        if p["id"] == "luzhniki_arena" and arena:
            x, z = arena[2]["center"]; src = "osm_stadium"
        elif p["id"] in names and names[p["id"]] in c.stations:
            x, z = c.stations[names[p["id"]]]; src = "osm_station"
        elif p["id"] == "novodevichy" and fort:
            x, z = fort[2]["center"]; src = "osm_walls"
        elif p["type"] == "substation" and substations:
            best = min(substations, key=lambda q: q.distance(Point(x, z)))
            if best.distance(Point(x, z)) < 400:
                x, z = best.centroid.x, best.centroid.y; src = "osm_substation"
        elif p["type"] == "radio_tower" and masts:
            best = min(masts, key=lambda q: math.hypot(q[0] - x, q[1] - z))
            if math.hypot(best[0] - x, best[1] - z) < 500:
                x, z = best; src = "osm_mast"
        inb = bool(area.contains(Point(x, z)))
        wx, wz = x, z
        if inb and p["type"] not in ("landmark", "forest", "road_main"):
            w = nav.nearest_walkable(x, z, 60)
            if w:
                wx, wz = w
        out.append({**{k: v for k, v in p.items() if k not in ("lat", "lon")}, "x": round(x, 1), "z": round(z, 1),
                    "wx": round(wx, 1), "wz": round(wz, 1), "in_bounds": inb, "source": src})
    return out


def _minimap(path, x0, z0, x1, z1, water, parks, roads, foot, bridges, buildings, arena, fort, scale=4.0):
    w, h = int((x1 - x0) / scale), int((z1 - z0) / scale)
    img = Image.new("RGB", (w, h), hex_rgb(PALETTE["GRASS_D"][1]))
    d = ImageDraw.Draw(img)

    def fill(geom, col):
        for p in polys_of(geom):
            d.polygon([((x - x0) / scale, (z - z0) / scale) for x, z in p.exterior.coords], fill=col)

    fill(parks, (96, 122, 66))
    fill(foot, (120, 122, 118))
    fill(roads, (150, 150, 146))
    fill(water, (55, 90, 117))
    fill(bridges, (170, 170, 164))
    for poly, _ in buildings:
        fill(poly, (58, 62, 70))
    if arena:
        fill(arena[1], (190, 190, 186))
    if fort:
        fill(fort[1], (158, 75, 54))
    img.save(path)


if __name__ == "__main__":
    main()
