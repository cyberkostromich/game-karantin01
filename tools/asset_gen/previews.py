"""Рендерит превью каждой модели (previews/models/*.png) и контакт-листы по категориям (previews/sheet_*.png)."""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

import models
from render import render

ROOT = Path(__file__).resolve().parents[2]
PV = ROOT / "previews"
F_B = str(ROOT / "assets" / "fonts" / "Inter-SemiBold.ttf")
F_R = str(ROOT / "assets" / "fonts" / "Inter-Regular.ttf")

BG = (238, 236, 230, 255)
INK = (34, 38, 44)
MUTED = (120, 124, 130)
ACCENT = (255, 106, 31)

TITLES = {
    "units": "Военные юниты", "civilians": "Мирные", "zombies": "Заражённые", "vehicles": "Техника",
    "buildings": "Постройки игрока", "city": "Город и POI", "props": "Пропсы и ресурсные узлы", "pickups": "Лут",
}


def sheet(cat, items, cols=6, cell=260):
    rows = (len(items) + cols - 1) // cols
    W, H = cols * cell + 48, rows * (cell + 44) + 110
    img = Image.new("RGBA", (W, H), BG)
    d = ImageDraw.Draw(img)
    d.text((24, 22), TITLES.get(cat, cat).upper(), font=ImageFont.truetype(F_B, 34), fill=INK)
    d.text((24, 66), f"КАРАНТИН: МОСКВА · модели v0.2 · {len(items)} шт · 1 ед = 1 м",
           font=ImageFont.truetype(F_R, 18), fill=MUTED)
    d.rectangle((24, 96, 84, 100), fill=ACCENT)
    f_name = ImageFont.truetype(F_B, 15); f_meta = ImageFont.truetype(F_R, 13)
    for i, (fn, m, th) in enumerate(items):
        cx, cy = 24 + (i % cols) * cell, 112 + (i // cols) * (cell + 44)
        d.rounded_rectangle((cx + 4, cy, cx + cell - 4, cy + cell + 36), 14, fill=(250, 249, 246, 255))
        t = th.resize((cell - 24, cell - 24), Image.LANCZOS)
        img.alpha_composite(t, (cx + 12, cy + 6))
        st = m.stats()
        d.text((cx + 16, cy + cell - 14), fn.replace(".glb", ""), font=f_name, fill=INK)
        d.text((cx + 16, cy + cell + 6), f"{st['tris']} tris · {st['size_m'][0]}×{st['size_m'][1]}×{st['size_m'][2]} м",
               font=f_meta, fill=MUTED)
    return img


def main():
    models.build_all()
    (PV / "models").mkdir(parents=True, exist_ok=True)
    by_cat: dict[str, list] = {}
    for cat, fn, m in models.REG:
        th = render(m, size=360)
        th.save(PV / "models" / fn.replace(".glb", ".png"))
        by_cat.setdefault(cat, []).append((fn, m, th))
    for cat, items in by_cat.items():
        sheet(cat, items).convert("RGB").save(PV / f"sheet_{cat}.png", optimize=True)
        print("sheet", cat, len(items))


if __name__ == "__main__":
    main()
