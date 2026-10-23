"""Генерирует синтетический Overpass JSON вокруг центра карты — для проверки build_city.py без сети."""
import json, math, random, sys
lat0, lon0 = 55.7175, 37.5625
kx = 111320 * math.cos(math.radians(lat0)); kz = 110540
def ll(x, z): return lat0 - z / kz, lon0 + x / kx
els, nid, wid = [], [1], [1]
def node(x, z, tags=None):
    lat, lon = ll(x, z); i = nid[0]; nid[0] += 1
    e = {"type": "node", "id": i, "lat": lat, "lon": lon}
    if tags: e["tags"] = tags
    els.append(e); return i
def way(pts, tags, closed=True):
    ids = [node(x, z) for x, z in pts]
    if closed: ids.append(ids[0])
    i = wid[0]; wid[0] += 1
    els.append({"type": "way", "id": i, "nodes": ids, "tags": tags}); return i
r = random.Random(4)
for gx in range(-3, 4):
    for gz in range(-3, 2):
        x, z = gx * 90, gz * 90
        w, d = r.choice([(60, 12), (14, 14), (48, 12), (30, 16)])
        lv = r.choice([5, 9, 9, 12, 17])
        way([(x - w/2, z - d/2), (x + w/2, z - d/2), (x + w/2, z + d/2), (x - w/2, z + d/2)],
            {"building": "apartments", "building:levels": str(lv)})
for gx in range(-4, 5):
    way([(gx * 90 + 45, -320), (gx * 90 + 45, 200)], {"highway": "secondary" if gx % 2 else "residential"}, closed=False)
way([(-400, -45), (400, -45)], {"highway": "primary", "name": "Комсомольский проспект"}, closed=False)
way([(-400, 230), (400, 230), (400, 330), (-400, 330)], {"natural": "water", "name": "Москва-река"})
way([(100, 120), (300, 120), (300, 210), (100, 210)], {"leisure": "park"})
for i in range(10): node(r.uniform(-300, 0), r.uniform(150, 200), {"natural": "tree"})
node(10, -50, {"shop": "supermarket", "name": "Продукты"}); node(-120, -50, {"amenity": "pharmacy"}); node(200, -40, {"shop": "car_repair"})
json.dump({"elements": els}, open(sys.argv[1], "w"))
print(len(els), "elements")
