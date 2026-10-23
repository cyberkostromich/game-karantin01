"""
kenney.py — персонажи v4 на базе Kenney «Animated Characters» (CC0, tools/asset_gen/kenney/, License.txt).

Одна модель (1604 треугольника, скелет) ставится в позу и режется по костям в Blender (bl_kenney.py) на узлы
игры; скины — PNG Kenney, а чего у Kenney нет (военная форма «цифра», хаки, маскхалат, грязная форма
заражённого) — перекрашивается по маскам UV из исходных скинов. Снаряжение и оружие — палитровые детали
(characters.py: rbox/ell/cyl/skin через Blender), оружие ориентируется по рукам позы.
Результаты Blender кешируются в .cache/kenney.json.gz (в git) — без изменений спек Blender не нужен.
"""
from __future__ import annotations

import gzip
import hashlib
import json
import math
import random
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import trimesh
from PIL import Image, ImageDraw, ImageFilter

from characters import cyl, ell, rbox, skin
from lowpoly import Model, Part, _rot_matrix, hex_rgb, PALETTE

HERE = Path(__file__).resolve().parent
KDIR = HERE / "kenney"
FBX = KDIR / "characterMedium.fbx"
CACHE = HERE / ".cache" / "kenney.json.gz"
SKIN_OUT = HERE / ".cache" / "skins"   # сгенерированные скины (встраиваются в glb)

# --------------------------------------------------------------------------------------------- позы
# [кость, ось в кадре игры, градусы]. Kenney Right* — сторона −X (наши *_l), Left* — +X (наши *_r).
# Правша: спуск — правая рука анатомически = Right* (−X), цевьё держит Left* (+X).
DOWN = [["RightArm", [0, 0, 1], 76], ["LeftArm", [0, 0, 1], -76]]
POSES = {
    "down": DOWN + [["RightForeArm", [1, 0, 0], -12], ["LeftForeArm", [1, 0, 0], -12]],
    "rifle": DOWN + [["Neck", [1, 0, 0], 6]],
    "pistol": DOWN + [["LeftForeArm", [1, 0, 0], -20]],
    "carry": DOWN,
    "zombie": DOWN + [["RightArm", [1, 0, 0], -78], ["RightArm", [0, 1, 0], 8], ["LeftArm", [1, 0, 0], -70],
                      ["LeftArm", [0, 1, 0], -10], ["RightForeArm", [1, 0, 0], -10], ["LeftForeArm", [1, 0, 0], -22],
                      ["Spine", [1, 0, 0], 14], ["Neck", [1, 0, 0], 12], ["RightUpLeg", [1, 0, 0], -12],
                      ["LeftUpLeg", [1, 0, 0], 10], ["RightLeg", [1, 0, 0], 10]],
    "runner": DOWN + [["RightArm", [1, 0, 0], 30], ["LeftArm", [1, 0, 0], 22], ["RightForeArm", [1, 0, 0], -25],
                      ["LeftForeArm", [1, 0, 0], -25], ["Spine", [1, 0, 0], 26], ["Neck", [1, 0, 0], -22],
                      ["RightUpLeg", [1, 0, 0], -26], ["LeftUpLeg", [1, 0, 0], 22], ["LeftLeg", [1, 0, 0], 35]],
    "brute": DOWN + [["RightArm", [1, 0, 0], -25], ["RightArm", [0, 0, 1], -14], ["LeftArm", [1, 0, 0], -25],
                     ["LeftArm", [0, 0, 1], 14], ["RightForeArm", [1, 0, 0], -35], ["LeftForeArm", [1, 0, 0], -35],
                     ["Spine", [1, 0, 0], 20], ["Neck", [1, 0, 0], -6]],
    "scream": DOWN + [["RightArm", [0, 0, 1], -50], ["LeftArm", [0, 0, 1], 50], ["RightArm", [1, 0, 0], -20],
                      ["LeftArm", [1, 0, 0], -20], ["RightForeArm", [1, 0, 0], -25], ["LeftForeArm", [1, 0, 0], -25],
                      ["Spine", [1, 0, 0], -8], ["Neck", [1, 0, 0], -32]],
    "old": DOWN + [["RightForeArm", [1, 0, 0], -30], ["LeftForeArm", [1, 0, 0], -12], ["Spine", [1, 0, 0], 12],
                   ["Neck", [1, 0, 0], 8]],
}
# объём громилы/великана: сдвиг по нормали в долях роста по весу кости (bl_kenney.inflate)
# IK запястий (кадр игры, м; сторона Right — наша l, −X): [сторона, цель, полюс локтя]
IK = {
    "rifle": [["Right", [-0.11, 0.92, 0.2], [-0.5, 0.65, -0.25]], ["Left", [0.03, 0.97, 0.38], [0.45, 0.7, 0.05]]],
    "pistol": [["Right", [-0.1, 1.04, 0.44], [-0.45, 0.85, 0.0]]],
    "carry": [["Right", [-0.17, 0.86, 0.3], [-0.5, 0.7, 0.0]], ["Left", [0.17, 0.86, 0.3], [0.5, 0.7, 0.0]]],
}
BULKY = {"UpperChest": 0.05, "Chest": 0.045, "Spine": 0.03, "RightShoulder": 0.04, "LeftShoulder": 0.04,
         "RightArm": 0.035, "LeftArm": 0.035, "RightForeArm": 0.04, "LeftForeArm": 0.04, "RightHand": 0.03,
         "LeftHand": 0.03, "RightUpLeg": 0.02, "LeftUpLeg": 0.02}

# --------------------------------------------------------------------------------------------- Blender


def _key(spec):
    return hashlib.sha1((json.dumps(spec, sort_keys=True) + FBX.name).encode()).hexdigest()[:16]


def rig(specs: dict) -> dict:
    """{имя: spec} → {имя: результат bl_kenney} с кешем по хешу спеки."""
    cache = json.loads(gzip.decompress(CACHE.read_bytes())) if CACHE.exists() else {}
    keys = {n: _key(s) for n, s in specs.items()}
    missing = {keys[n]: s for n, s in specs.items() if keys[n] not in cache}
    if missing:
        exe = shutil.which("blender")
        if not exe:
            raise SystemExit(f"нужен Blender (apt install blender python3-numpy): {len(missing)} поз нет в кеше")
        print(f"blender: {len(missing)} поз Kenney")
        with tempfile.TemporaryDirectory() as td:
            src, dst = Path(td) / "in.json", Path(td) / "out.json"
            src.write_text(json.dumps(missing))
            subprocess.run([exe, "-b", "--factory-startup", "--python-exit-code", "1", "-P", str(HERE / "bl_kenney.py"), "--", str(FBX), str(src),
                            str(dst)], check=True, stdout=subprocess.DEVNULL)
            cache.update(json.loads(dst.read_text()))
    used = set(keys.values())
    CACHE.parent.mkdir(exist_ok=True)
    CACHE.write_bytes(gzip.compress(json.dumps({k: v for k, v in sorted(cache.items()) if k in used},
                                               separators=(",", ":")).encode(), mtime=0))
    return {n: cache[keys[n]] for n in specs}


# --------------------------------------------------------------------------------------------- скины

TORSO = {"Hips", "Spine", "Chest", "UpperChest", "LeftShoulder", "RightShoulder"}
REGIONS = {
    "torso": lambda b, u: b in TORSO and u < 0.6,
    "sleeve": lambda b, u: b in ("LeftArm", "RightArm"),
    "forearm": lambda b, u: b in ("LeftForeArm", "RightForeArm"),
    "legs": lambda b, u: b in ("LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg") or (b == "Hips" and u >= 0.6),
    "feet": lambda b, u: "Foot" in b or "Toe" in b,
}
_MASKS: dict = {}


def masks(res, W=1024):
    """Маски областей UV (рубашка, рукава, штаны, обувь) по костям треугольников — одна раскладка на все скины."""
    if _MASKS:
        return _MASKS
    for name, pred in REGIONS.items():
        im = Image.new("L", (W, W), 0)
        dr = ImageDraw.Draw(im)
        for nd in res["nodes"].values():
            uv = nd["uv"]
            for t, b in enumerate(nd["b"]):
                u0 = uv[t * 6]
                if pred(b, u0):
                    dr.polygon([(uv[t * 6 + k * 2] * W, (1 - uv[t * 6 + k * 2 + 1]) * W) for k in range(3)], fill=255)
        _MASKS[name] = im.filter(ImageFilter.MaxFilter(7))
    return _MASKS


def camo(cols, cell=10, seed=1, W=1024):
    """«Цифра» (ЕМР): пиксельные пятна из нескольких цветов поверх базового."""
    rnd = np.random.default_rng(seed)
    n = W // cell
    base = np.zeros((n, n, 3), np.uint8)
    base[:] = hex_rgb(PALETTE[cols[0]][1])
    for k, c in enumerate(cols[1:]):
        noise = rnd.random((n // 4 + 1, n // 4 + 1))
        big = np.kron(noise, np.ones((4, 4)))[:n, :n] + rnd.random((n, n)) * 0.35
        base[big > 0.78 - k * 0.04] = hex_rgb(PALETTE[c][1])
    return Image.fromarray(base).resize((W, W), Image.NEAREST)


def solid(color, W=1024):
    return Image.new("RGB", (W, W), hex_rgb(PALETTE[color][1]) if color in PALETTE else color)


def make_skin(name, base, res, paint: dict, dirt=0.0):
    """paint: {область: изображение-заливка}; dirt — пятна грязи/крови (заражённые)."""
    img = Image.open(KDIR / "skins" / f"{base}.png").convert("RGB")
    mk = masks(res)
    for region, fill in paint.items():
        img.paste(fill, (0, 0), mk[region])
    if dirt:
        rnd = random.Random(name)
        dr = ImageDraw.Draw(img)
        for _ in range(int(60 * dirt)):
            x, y, r = rnd.randint(0, 1023), rnd.randint(480, 1023), rnd.randint(6, 26)
            c = rnd.choice([(74, 60, 48), (95, 40, 36), (60, 66, 50)])
            dr.ellipse((x - r, y - r * 0.8, x + r, y + r * 0.8), fill=c)
    SKIN_OUT.mkdir(parents=True, exist_ok=True)
    p = SKIN_OUT / f"{name}.png"
    img.save(p)
    return p


# --------------------------------------------------------------------------------------------- модель


class Rig:
    """Результат позы: точки скелета и габариты частей в кадре игры."""

    def __init__(self, res):
        self.res = res
        self.a = {k: np.asarray(v, float) for k, v in res["anchors"].items()}
        self.box = {}
        for nd, d in res["nodes"].items():
            v = np.asarray(d["v"], float).reshape(-1, 3)
            self.box[nd] = (v.min(0), v.max(0))

    def hand(self, side):  # Right* — наша сторона l (−X)
        b = "RightHand" if side == "l" else "LeftHand"
        return self.a[b] * 0.55 + self.a[b + "Index3_end"] * 0.45

    def head(self):
        lo, hi = self.box["head"]
        return (lo + hi) / 2, hi - lo

    def torso_at(self, y):
        """Полуширина, перед, зад торса на высоте y (по вершинам узла body)."""
        v = np.asarray(self.res["nodes"]["body"]["v"], float).reshape(-1, 3)
        sl = v[np.abs(v[:, 1] - y) < 0.06]
        if len(sl) == 0:
            sl = v
        return float(np.abs(sl[:, 0]).max()), float(sl[:, 2].max()), float(sl[:, 2].min())


def build(name, res, skin_png, lod=1.0) -> tuple[Model, Rig]:
    m = Model(name, meta={"lod": lod})
    r = Rig(res)
    order = ["body", "head", "arm_l", "arm_r", "forearm_l", "forearm_r", "leg_l", "leg_r", "shin_l", "shin_r"]
    for nd in order:
        d = res["nodes"].get(nd)
        if d is None:
            continue
        node = m.node(nd, parent=d["parent"], pivot=d["pivot"])
        v = np.asarray(d["v"], float).reshape(-1, 3)
        part = Part(trimesh.Trimesh(v, np.arange(len(v)).reshape(-1, 3), process=False), "WHITE",
                    normals=np.asarray(d["n"], float).reshape(-1, 3, 3),
                    uv=np.asarray(d["uv"], float).reshape(-1, 3, 2), tex=skin_png)
        node.parts.append(part)
    m.meta.update(rig=r)
    return m, r


# --------------------------------------------------------------------------------------------- снаряжение


class Frame:
    """Локальная система оружия: начало в кисти, +Z — к точке aim (боковой снос гасится: ствол смотрит
    вперёд, а не поперёк тела, даже если кисти в позе разведены)."""

    def __init__(self, origin, aim, lateral=0.15):
        d = np.asarray(aim, float) - np.asarray(origin, float)
        d[0] *= lateral
        d /= np.linalg.norm(d)
        self.yaw = math.degrees(math.atan2(d[0], d[2]))
        self.pitch = -math.degrees(math.asin(np.clip(d[1], -1, 1)))
        self.R = _rot_matrix((self.pitch, self.yaw, 0))
        self.o = np.asarray(origin, float)

    def p(self, local):
        return self.o + self.R[:3, :3] @ np.asarray(local, float)

    def rot(self, extra=None):
        M = self.R @ _rot_matrix(extra) if extra else self.R
        return [math.degrees(a) for a in trimesh.transformations.euler_from_matrix(M, "sxyz")]


def _box(w, f, size, local, color, extra=None, bevel=None):
    rbox(w, size, f.p(local), color, rot=f.rot(extra), bevel=bevel)


def _tube(w, f, r, h, local, color, r2=None):
    cyl(w, r, h, f.p(local), color, rot=f.rot(), seg=8, r2=r2)


def ak(m, r, short=False):
    grip = r.hand("l")
    w = m.node("weapon", parent="body", pivot=tuple(grip))
    f = Frame(grip, r.hand("r"), lateral=0.5)
    L = 0.4 if short else 0.55
    _box(w, f, (0.05, 0.09, 0.34), (0, 0.06, 0.12), "GUNMETAL", bevel=0.01)          # ствольная коробка
    _box(w, f, (0.055, 0.07, 0.2), (0, 0.05, 0.38), "GUNMETAL" if short else "WOOD", bevel=0.012)  # цевьё
    _tube(w, f, 0.014, L, (0, 0.07, 0.48 + L / 2), "GUNMETAL")                         # ствол
    _box(w, f, (0.04, 0.12, 0.06), (0, -0.04, 0.2), "GUNMETAL", extra=(20, 0, 0), bevel=0.008)  # магазин
    _box(w, f, (0.035, 0.1, 0.04), (0, -0.01, 0.0), "GUNMETAL", extra=(-15, 0, 0), bevel=0.008)  # рукоять
    if short:
        _box(w, f, (0.02, 0.04, 0.22), (0, 0.06, -0.13), "GUNMETAL")
    else:
        _box(w, f, (0.045, 0.1, 0.24), (0, 0.03, -0.14), "WOOD", extra=(6, 0, 0), bevel=0.014)  # приклад


def svd(m, r):
    grip = r.hand("l")
    w = m.node("weapon", parent="body", pivot=tuple(grip))
    f = Frame(grip, r.hand("r"), lateral=0.5)
    _box(w, f, (0.05, 0.08, 0.42), (0, 0.06, 0.14), "GUNMETAL", bevel=0.01)
    _box(w, f, (0.055, 0.07, 0.3), (0, 0.05, 0.48), "WOOD", bevel=0.012)
    _tube(w, f, 0.013, 0.6, (0, 0.06, 0.93), "GUNMETAL")
    _box(w, f, (0.04, 0.12, 0.06), (0, -0.04, 0.22), "GUNMETAL", bevel=0.008)
    _box(w, f, (0.045, 0.12, 0.28), (0, 0.02, -0.16), "WOOD", extra=(6, 0, 0), bevel=0.014)
    _tube(w, f, 0.03, 0.28, (0, 0.14, 0.16), "BLACK")                                  # ПСО-1


def pistol(m, r):
    h = r.hand("l")
    elbow = r.a["RightForeArm"]
    w = m.node("weapon", parent="forearm_l", pivot=tuple(h))
    f = Frame(h, h + (h - elbow), lateral=1.0)  # стволом вдоль предплечья
    _box(w, f, (0.04, 0.05, 0.18), (0, 0.04, 0.07), "GUNMETAL", bevel=0.008)
    _box(w, f, (0.035, 0.09, 0.045), (0, 0.0, 0.0), "GUNMETAL", extra=(-15, 0, 0), bevel=0.008)


def shell(m, r, color, brow=0.05, tilt=0.35, thick=0.022, lower=None):
    """Головной убор по форме головы: треугольники головы выше линии лба (сзади ниже на tilt) сдвигаются
    по нормалям на thick — ничего не просвечивает и не торчит, в отличие от эллипсоида поверх."""
    d = r.res["nodes"]["head"]
    v = np.asarray(d["v"], float).reshape(-1, 3, 3)
    n = np.asarray(d["n"], float).reshape(-1, 3, 3)
    c, s = r.head()
    cen = v.mean(axis=1)
    y0 = c[1] + brow * s[1]
    keep = cen[:, 1] > y0 - tilt * np.clip(-(cen[:, 2] - c[2]) / (s[2] / 2), 0, 1) * s[1] * 0.5
    if lower is not None:  # платок: ниже по бокам, лицо открыто
        keep |= (cen[:, 1] > c[1] + lower * s[1]) & (cen[:, 2] < c[2] + s[2] * 0.25)
    vv = v[keep] + n[keep] * thick
    part = Part(trimesh.Trimesh(vv.reshape(-1, 3), np.arange(len(vv) * 3).reshape(-1, 3), process=False), color,
                normals=n[keep])
    m.node("head").parts.append(part)
    return c, s


def helmet(m, r, color="HELMET", gear=True, team=True):
    """team — обод цвета игрока (палитра TEAM): сверху это главный опознавательный знак, как цвет команды
    на наплечниках в RTS; у заражённых в касках обод обычный."""
    c, s = shell(m, r, color, brow=0.06, thick=0.045)
    ell(m.node("head"), c + [0, s[1] * 0.07, -0.005], [s[0] * 0.64, 0.036, s[2] * 0.66], "TEAM" if team else color, tris=56)
    if gear:
        rbox(m.node("head"), (0.08, 0.05, 0.035), c + [0, s[1] * 0.3, s[2] * 0.5 + 0.03], "GUNMETAL")  # крепление ПНВ


def glow_eyes(m, r, k=1.0):
    """Светящиеся глаза заражённых (палитра INFECT_GLOW — emission ночью): враг читается в темноте."""
    d = r.res["nodes"]["head"]
    v = np.asarray(d["v"], float).reshape(-1, 3)
    c, s = r.head()
    lo, hi = r.box["head"]
    ey = lo[1] + (hi[1] - lo[1]) * 0.52
    for sx in (-1, 1):
        ex = sx * s[0] * 0.2
        near = v[(np.abs(v[:, 1] - ey) < s[1] * 0.08) & (np.abs(v[:, 0] - ex) < s[0] * 0.1)]
        ez = (near[:, 2].max() if len(near) else c[2] + s[2] * 0.5) - 0.004
        ell(m.node("head"), (ex, ey, ez), (0.035 * k, 0.025 * k, 0.012), "INFECT_GLOW", tris=12)


def vest(m, r, color="OLIVE_D", pouches="OLIVE_L"):
    n = m.node("body")
    y0, y1 = r.a["Spine"][1], r.a["UpperChest"][1] + 0.03
    hw, zf, zb = r.torso_at((y0 + y1) / 2)
    cy = (y0 + y1) / 2
    rbox(n, (hw * 2.1, y1 - y0, (zf - zb) * 1.18), (0, cy, (zf + zb) / 2), color, bevel=0.03)
    if pouches:
        for x in (-0.7, 0.0, 0.7):
            rbox(n, (hw * 0.5, (y1 - y0) * 0.38, 0.06), (x * hw, y0 + (y1 - y0) * 0.3, zf * 1.18 + 0.02), pouches, bevel=0.012)


def backpack(m, r, color="OLIVE_D", k=1.0, roll=None):
    n = m.node("body")
    y = (r.a["Chest"][1] + r.a["UpperChest"][1]) / 2
    hw, zf, zb = r.torso_at(y)
    size = (hw * 1.5 * k, 0.32 * k, 0.16 * k)
    rbox(n, size, (0, y, zb * 1.12 - size[2] / 2), color, bevel=0.04)
    if roll:
        cyl(n, 0.06, size[0] + 0.06, (0, y + size[1] / 2 + 0.04, zb * 1.12 - size[2] / 2), roll, rot=(0, 90, 0), seg=10)


def armband(m, r, color="TEAM", side="l"):
    a, b = (r.a["RightArm"], r.a["RightForeArm"]) if side == "l" else (r.a["LeftArm"], r.a["LeftForeArm"])
    lo, hi = r.box[f"arm_{side}"]
    rad = float(min(hi[0] - lo[0], hi[2] - lo[2])) * 0.55
    skin(m.node(f"arm_{side}"), [a + (b - a) * 0.4, a + (b - a) * 0.62], [rad, rad], color, tris=24)


def cap(m, r, color, brim=True, brow=0.12, lower=None):
    c, s = shell(m, r, color, brow=brow, thick=0.02, lower=lower)
    if brim:
        ell(m.node("head"), c + [0, s[1] * (brow + 0.02), s[2] * 0.5], [s[0] * 0.36, 0.015, s[2] * 0.22], color, tris=24)
    return c, s


# --------------------------------------------------------------------------------------------- состав

def _specs():
    S = {}
    for n, pose in (("unit_assault", "rifle"), ("unit_sniper", "rifle"), ("unit_medic", "pistol"), ("unit_scout", "rifle"),
                    ("civ_adult_a", "down"), ("civ_adult_b", "down"), ("civ_adult_c", "down"), ("civ_adult_d", "old"),
                    ("civ_adult_e", "down"), ("civ_worker_carry", "carry")):
        S[n] = {"pose": POSES[pose], "height": 1.8 if n.startswith("unit") else 1.75, "ik": IK.get(pose, [])}
    S["civ_child"] = {"pose": POSES["down"], "height": 1.15}
    for n, pose in (("zmb_walker", "zombie"), ("zmb_walker_armored", "zombie"), ("zmb_runner", "runner"),
                    ("zmb_screamer", "scream"), ("zmb_spitter", "zombie")):
        S[n] = {"pose": POSES[pose], "height": 1.75, "decimate": 0.55}
    S["zmb_brute"] = {"pose": POSES["brute"], "height": 2.15, "inflate": BULKY, "head_k": 0.72, "decimate": 0.7}
    S["zmb_giant"] = {"pose": POSES["brute"], "height": 3.3, "inflate": BULKY, "head_k": 0.62, "decimate": 0.7}
    return S


def _uniform(res, name, base, top, pants, sleeves=True, boots="BLACK", dirt=0.0):
    paint = {"torso": top, "legs": pants, "feet": solid(boots)}
    if sleeves:
        paint.update(sleeve=top, forearm=top)
    return make_skin(name, base, res, paint, dirt)


EMR = ["OLIVE", "OLIVE_L", "OLIVE_D", "CAMO_BROWN"]


def units(R, reg):
    m, r = build("unit_assault", R["unit_assault"], _uniform(R["unit_assault"], "soldier", "survivorMaleB",
                                                              camo(EMR, seed=1), camo(EMR, seed=2)))
    helmet(m, r); vest(m, r); armband(m, r); backpack(m, r, k=0.9); ak(m, r)
    reg("units", m, unit="assault")
    m, r = build("unit_sniper", R["unit_sniper"], _uniform(R["unit_sniper"], "sniper", "survivorMaleB",
                                                            camo(["CAMO_BROWN", "KHAKI", "OLIVE_D", "OLIVE"], seed=3),
                                                            camo(["OLIVE_D", "CAMO_BROWN", "OLIVE"], seed=4)))
    c, s = cap(m, r, "KHAKI", brim=False, brow=0.1)
    ell(m.node("head"), c + [0, s[1] * 0.1, -0.01], [s[0] * 0.78, 0.02, s[2] * 0.78], "KHAKI", tris=40)  # поля панамы
    armband(m, r); svd(m, r)
    reg("units", m, unit="sniper")
    m, r = build("unit_medic", R["unit_medic"], _uniform(R["unit_medic"], "medic", "survivorMaleB",
                                                          camo(EMR, seed=5), camo(EMR, seed=6)))
    helmet(m, r, gear=False); vest(m, r, pouches="MEDIC_WHITE"); armband(m, r, "MEDIC_WHITE"); armband(m, r, "TEAM", "r")
    backpack(m, r, "MEDIC_WHITE", k=1.1)
    y = (r.a["Chest"][1] + r.a["UpperChest"][1]) / 2
    zb = r.torso_at(y)[2] * 1.12 - 0.18
    rbox(m.node("body"), (0.06, 0.2, 0.02), (0, y, zb - 0.005), "RED_CROSS")
    rbox(m.node("body"), (0.2, 0.06, 0.02), (0, y, zb - 0.006), "RED_CROSS")
    pistol(m, r)
    reg("units", m, unit="medic")
    m, r = build("unit_scout", R["unit_scout"], _uniform(R["unit_scout"], "scout", "survivorMaleB", solid("KHAKI"),
                                                          camo(["CAMO_BROWN", "OLIVE_D", "KHAKI"], seed=7)))
    cap(m, r, "OLIVE_D"); armband(m, r); backpack(m, r, "CAMO_BROWN", k=1.15, roll="OLIVE"); ak(m, r, short=True)
    y = r.a["UpperChest"][1]
    cyl(m.node("body"), 0.008, 0.7, (0.1, y + 0.45, r.torso_at(y)[2] - 0.15), "GUNMETAL", rot=(-90, 0, 0), seg=5)  # антенна
    reg("units", m, unit="scout")


def civilians(R, reg):
    for n, base, paint in (("civ_adult_a", "survivorMaleB", {}), ("civ_adult_b", "survivorFemaleA", {}),
                           ("civ_adult_c", "skaterMaleA", {}),
                           ("civ_adult_d", "survivorFemaleA", {"torso": solid("CIV_GREEN"), "sleeve": solid("CIV_GREEN")}),
                           ("civ_adult_e", "criminalMaleA", {}), ("civ_child", "skaterFemaleA", {})):
        m, r = build(n, R[n], make_skin(n, base, R[n], paint))
        if n == "civ_adult_d":
            cap(m, r, "CIV_PURPLE", brim=False, brow=0.18, lower=-0.25)       # платок
        reg("civilians", m, unit={"civ_child": "child"}.get(n, "civilian"))
    n = "civ_worker_carry"
    m, r = build(n, R[n], make_skin(n, "survivorMaleB", R[n], {"torso": solid("CIV_ORANGE")}))
    c, s = cap(m, r, "HAZARD_YELLOW", brim=False, brow=0.1)
    ell(m.node("head"), c + [0, s[1] * 0.1, 0.02], [s[0] * 0.6, 0.015, s[2] * 0.66], "HAZARD_YELLOW", tris=24)  # козырёк каски
    hl, hr = r.hand("l"), r.hand("r")
    mid = (hl + hr) / 2
    w = m.node("weapon", parent="body", pivot=tuple(mid))
    cyl(w, 0.1, 1.3, mid + [0, 0.05, 0.02], "BARK", rot=(0, 90, 0), seg=9, bevel=0.02)
    cyl(w, 0.08, 1.305, mid + [0, 0.05, 0.02], "WOOD_L", rot=(0, 90, 0), seg=9)
    reg("civilians", m, unit="civilian_worker")


def zombies(R, reg):
    ZL = 0.55
    base_reg = reg

    def reg(cat, m, **kw):   # всем заражённым — светящиеся глаза
        glow_eyes(m, m.meta["rig"], 1.6 if kw.get("unit") in ("brute", "giant") else 1.0)
        return base_reg(cat, m, **kw)
    m, r = build("zmb_walker", R["zmb_walker"], make_skin("zmb_walker", "zombieA", R["zmb_walker"], {}), ZL)
    reg("zombies", m, unit="walker")
    n = "zmb_walker_armored"
    m, r = build(n, R[n], _uniform(R[n], n, "zombieA", camo(EMR, seed=8), camo(EMR, seed=9), dirt=1.0), ZL)
    helmet(m, r, "OLIVE_D", gear=False, team=False); vest(m, r, pouches=None)
    reg("zombies", m, unit="walker_armored")
    m, r = build("zmb_runner", R["zmb_runner"], make_skin("zmb_runner", "zombieC", R["zmb_runner"], {}), ZL)
    reg("zombies", m, unit="runner")
    n = "zmb_screamer"
    m, r = build(n, R[n], make_skin(n, "zombieC", R[n], {"torso": solid("ZMB_CLOTH")}, dirt=0.6), ZL)
    reg("zombies", m, unit="screamer")
    n = "zmb_spitter"
    m, r = build(n, R[n], make_skin(n, "zombieA", R[n], {"torso": solid("ZMB_CLOTH_D")}, dirt=0.6), ZL)
    y = r.a["UpperChest"][1]
    hw, zf, zb = r.torso_at(y)
    ell(m.node("body"), (0, y - 0.02, zf + 0.06), (0.14, 0.12, 0.12), "SPIT_SAC", tris=40)        # зоб
    ell(m.node("body"), (0.04, y - 0.05, zb - 0.16), (0.24, 0.24, 0.2), "SPIT_SAC", tris=48)      # мешок на спине
    ell(m.node("body"), (-0.12, y - 0.25, zb - 0.1), (0.1, 0.1, 0.1), "INFECT_GLOW", tris=20)
    reg("zombies", m, unit="spitter")
    for n, base, k in (("zmb_brute", "zombieC", 1.0), ("zmb_giant", "zombieA", 1.55)):
        m, r = build(n, R[n], make_skin(n, base, R[n], {"torso": solid("BRUTE_SKIN")}, dirt=0.8), 1.0)
        y = r.a["UpperChest"][1]
        zb = r.torso_at(y)[2]
        rnd = random.Random(n)
        for i in range(4 if k == 1.0 else 7):
            x = rnd.uniform(-0.35, 0.35) * k
            cyl(m.node("body"), 0.025 * k, 0.4 * k, (x, y - rnd.uniform(0.0, 0.3) * k, zb - 0.05 * k),
                rnd.choice(["RUST", "CONCRETE_L"]), rot=(-120 + rnd.uniform(-20, 20), 0, rnd.uniform(-25, 25)), seg=5,
                r2=0.006 * k)                                                                         # арматура из спины
        if k > 1.0:
            for side, a in (("l", "RightArm"), ("r", "LeftArm")):
                rbox(m.node(f"arm_{side}"), (0.42, 0.3, 0.42), r.a[a] + [0, 0.05, 0], "CONCRETE_D",
                     rot=(8, 15, 10 if side == "r" else -10), bevel=0.05)                              # бетонный наплечник
        reg("zombies", m, unit=n.split("_")[1])


def build_all(reg):
    R = rig(_specs())
    units(R, reg)
    civilians(R, reg)
    zombies(R, reg)
