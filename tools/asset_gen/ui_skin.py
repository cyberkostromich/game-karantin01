"""
ui_skin.py — текстуры интерфейса (арт-библия §9, D-12): «полевой планшет штаба» вместо плоских
полупрозрачных плашек. Крашеная сталь с фасками и заклёпками, утопленные слоты, кнопки-пластины,
малярный скотч для подписей, сигнальная «зебра». Всё — 9-slice PNG в assets/ui/ (поля — в UI_MARGINS
UiTheme.gd), процедурно и детерминированно (сид), без внешних картинок.

    python3 ui_skin.py
"""
from __future__ import annotations

import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "ui"


def _rgba(h, a=255):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


def chamfer_mask(w, h, c):
    """Маска прямоугольника со срезанными углами (вместо скруглений — «железный» силуэт)."""
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).polygon([(c, 0), (w - 1 - c, 0), (w - 1, c), (w - 1, h - 1 - c), (w - 1 - c, h - 1),
                               (c, h - 1), (0, h - 1 - c), (0, c)], fill=255)
    return m


def grain(w, h, base, amp, seed, streak=0.0):
    """Крашеный металл: зерно + вертикальные «шлифовочные» штрихи + лёгкий перепад сверху вниз."""
    rnd = np.random.default_rng(seed)
    a = np.zeros((h, w, 3), np.float32)
    a[:] = np.asarray(_rgba(base)[:3], np.float32)
    a += rnd.normal(0, amp, (h, w, 1))
    if streak:
        a += rnd.normal(0, streak, (1, w, 1)) * np.linspace(0.6, 1.0, h)[:, None, None]
    a *= np.linspace(1.05, 0.93, h)[:, None, None]
    return np.clip(a, 0, 255)


def plate(w, h, c, base, seed, hi="#5a6052", lo="#000000", amp=4.0, streak=2.0, rivets=False, wear=0.0,
          inset=False):
    rgb = grain(w, h, base, amp, seed, streak)
    img = Image.fromarray(rgb.astype(np.uint8)).convert("RGBA")
    ov = Image.new("RGBA", (w, h), (0, 0, 0, 0))   # штрихи рисуются слоем поверх (с смешиванием альфы)
    d = ImageDraw.Draw(ov)
    pts = [(c, 0), (w - 1 - c, 0), (w - 1, c), (w - 1, h - 1 - c), (w - 1 - c, h - 1), (c, h - 1), (0, h - 1 - c), (0, c)]
    top, bot = (_rgba(lo, 150), _rgba(hi, 110)) if inset else (_rgba(hi, 150), _rgba(lo, 120))
    # фаска: светлая грань сверху/слева, тёмная снизу/справа (утопленный — наоборот)
    d.line([(1, c + 1), (c + 1, 1), (w - 2 - c, 1)], fill=top, width=1)
    d.line([(w - 2, c + 1), (w - 2, h - 2 - c), (w - 2 - c, h - 2), (c + 1, h - 2)], fill=bot, width=1)
    if inset:  # внутренняя тень утопленного слота
        for k in range(4):
            d.line([(c + 1, 2 + k), (w - 2 - c, 2 + k)], fill=(0, 0, 0, 70 - k * 16))
    d.line(pts + [pts[0]], fill=_rgba("#0b0c0d", 255), width=1)
    rnd = random.Random(seed)
    for _ in range(int(wear * (w + h))):  # потёртости краски у кромок
        side = rnd.random()
        x = rnd.randint(2, w - 3) if side < 0.5 else rnd.choice([2, 3, w - 4, w - 3])
        y = rnd.choice([2, 3, h - 4, h - 3]) if side < 0.5 else rnd.randint(2, h - 3)
        d.point((x, y), fill=_rgba("#8a8d80", rnd.randint(60, 140)))
    if rivets:
        for x, y in ((c + 4, 4), (w - c - 5, 4), (c + 4, h - 5), (w - c - 5, h - 5)):
            d.ellipse((x - 2, y - 2, x + 2, y + 2), fill=_rgba("#1a1c1d"))
            d.point((x - 1, y - 1), fill=_rgba("#8f948a"))
    img = Image.alpha_composite(img, ov)
    img.putalpha(Image.composite(img.getchannel("A"), Image.new("L", (w, h), 0), chamfer_mask(w, h, c)))
    return img


def tape(w=72, h=22, seed=3):
    """Малярный скотч: подложка подписей разделов (подписано маркером «по-полевому»)."""
    rgb = grain(w, h, "#c9bc94", 5.0, seed, 0)
    img = Image.fromarray(rgb.astype(np.uint8)).convert("RGBA")
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    rnd = random.Random(seed)
    left = [(rnd.randint(0, 3), y) for y in range(0, h, 3)] + [(rnd.randint(0, 3), h - 1)]
    right = [(w - 1 - rnd.randint(0, 3), y) for y in range(h - 1, -1, -3)] + [(w - 1 - rnd.randint(0, 3), 0)]
    d.polygon(left + right, fill=232)
    img.putalpha(m)
    return img


def hazard(n=32):
    img = Image.new("RGBA", (n, n))
    px = img.load()
    for y in range(n):
        for x in range(n):
            px[x, y] = _rgba("#e3a92b") if ((x + y) // (n // 4)) % 2 == 0 else _rgba("#16171a")
    return img


def glow_line(w=64, h=6, color="#ff6a1f"):
    """Подсветка-полоса для активной/наведённой кнопки (вместо свечения рамки)."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle((0, h - 2, w, h), fill=_rgba(color))
    return img.filter(ImageFilter.GaussianBlur(0.6))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    plate(96, 96, 9, "#262a25", 1, rivets=True, wear=0.5).save(OUT / "panel.png")
    plate(96, 96, 9, "#1d201d", 2, rivets=False, wear=0.2, amp=3).save(OUT / "panel_dark.png")
    plate(48, 48, 5, "#111315", 3, hi="#3b4038", inset=True, amp=2, streak=0).save(OUT / "inset.png")
    plate(56, 56, 6, "#363b31", 4, wear=0.25).save(OUT / "btn.png")
    plate(56, 56, 6, "#454b3e", 5, hi="#7a816e", wear=0.25).save(OUT / "btn_hover.png")
    plate(56, 56, 6, "#22261f", 6, inset=True, wear=0.1).save(OUT / "btn_pressed.png")
    plate(56, 56, 6, "#25282a", 7, hi="#3a3d3c", amp=2, streak=0).save(OUT / "btn_disabled.png")
    act = plate(56, 56, 6, "#3d4334", 8, hi="#ff8a4a", wear=0.2)
    ImageDraw.Draw(act).line([(7, 53), (48, 53)], fill=_rgba("#ff6a1f"), width=2)   # активная — оранжевая кромка
    act.save(OUT / "btn_active.png")
    plate(40, 16, 3, "#0f1112", 9, hi="#2e322d", inset=True, amp=1.5, streak=0).save(OUT / "bar_bg.png")
    tape().save(OUT / "tape.png")
    hazard().save(OUT / "hazard.png")
    glow_line().save(OUT / "glow_line.png")
    print("ui skin ->", OUT)


if __name__ == "__main__":
    main()


def menu_bg(W=1920, H=1080):
    """Фон меню — штабная карта Лужников (наш OSM-рендер миникарты): тонировка «синька», сетка квадратов
    с подписями, пометки «карандашом» — периметр карантина вокруг арены, стрелки направлений орды."""
    import json
    from PIL import ImageFont
    city = ROOT / "assets" / "city" / "luzhniki"
    rep = json.loads((city / "report.json").read_text())
    x0, z0, x1, z1 = rep["bounds_m"]
    src = Image.open(city / "minimap.png").convert("L")
    k = max(W / src.width, H / src.height) * 1.25
    big = src.resize((int(src.width * k), int(src.height * k)), Image.LANCZOS).filter(ImageFilter.GaussianBlur(1.6))
    arena = next(p for p in json.loads((city / "pois.json").read_text()) if p["type"] == "safe_zone")
    ax = (arena["x"] - x0) / (x1 - x0) * big.width
    az = (arena["z"] - z0) / (z1 - z0) * big.height
    ox, oy = int(ax - W * 0.66), int(az - H * 0.52)              # арена — правее центра, слева место под меню
    crop = Image.new("L", (W, H), int(np.asarray(big).mean()))   # за краем карты — тон бумаги
    crop.paste(big, (-ox, -oy))
    g = np.asarray(crop, np.float32) / 255.0
    g = (g - g.mean()) * 1.25 + 0.5
    ink, paper = np.array([18, 26, 30], np.float32), np.array([92, 118, 118], np.float32)
    rgb = ink + (paper - ink) * np.clip(g, 0, 1)[..., None]
    rnd = np.random.default_rng(11)
    rgb += rnd.normal(0, 4.0, (H, W, 1))
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).convert("RGBA")
    ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    fnt = ImageFont.truetype(str(ROOT / "assets" / "fonts" / "PTM55FT.ttf"), 20)
    step = 160
    for i, x in enumerate(range(0, W, step)):
        d.line([(x, 0), (x, H)], fill=(200, 215, 210, 26), width=1)
        d.text((x + 6, 6), "АБВГДЕЖИКЛМН"[i % 12], font=fnt, fill=(200, 215, 210, 120))
    for j, y in enumerate(range(0, H, step)):
        d.line([(0, y), (W, y)], fill=(200, 215, 210, 26), width=1)
        d.text((W - 26, y + 6), str(j + 1), font=fnt, fill=(200, 215, 210, 120))
    cx, cy = ax - ox, az - oy
    red = (214, 64, 44, 215)
    rr = 150
    rnd2 = random.Random(5)
    pts = []
    for t in range(0, 380, 6):       # «от руки»: неровный круг с захлёстом
        a = np.radians(t)
        r = rr * (1 + 0.05 * np.sin(a * 3 + 1) + rnd2.uniform(-0.01, 0.01))
        pts.append((cx + r * np.cos(a) * 1.25, cy + r * np.sin(a)))
    d.line(pts, fill=red, width=5, joint="curve")
    for ang in (200, 250, 300, 20):  # стрелки направлений орды к периметру
        a = np.radians(ang)
        p0 = (cx + np.cos(a) * 520, cy + np.sin(a) * 400)
        p1 = (cx + np.cos(a) * 260, cy + np.sin(a) * 200)
        d.line([p0, p1], fill=red, width=4)
        n = np.array(p1) - np.array(p0)
        n /= np.linalg.norm(n)
        q = np.array([-n[1], n[0]])
        tip = np.array(p1)
        d.polygon([tuple(tip + n * 18), tuple(tip - n * 6 + q * 12), tuple(tip - n * 6 - q * 12)], fill=red)
    img = Image.alpha_composite(img, ov)
    # затемнение слева под меню и виньетка
    xs = np.linspace(0, 1, W)[None, :, None]
    ys = np.linspace(-1, 1, H)[:, None, None]
    shade = (0.12 + 0.88 * np.clip((xs - 0.3) / 0.28, 0, 1) ** 1.5) * (1 - 0.35 * ys ** 2)
    a = np.asarray(img, np.float32)
    a[..., :3] *= shade
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).convert("RGB").save(OUT / "menu_bg.jpg", quality=90)


if __name__ == "__main__" and True:
    menu_bg()
