"""Софтверный рендер превью low-poly моделей: ортографическая изометрия, шейдинг по нормалям вершин, z-buffer, мягкая тень."""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageFilter


def _rot(yaw_deg, pitch_deg):
    y, p = math.radians(yaw_deg), math.radians(pitch_deg)
    Ry = np.array([[math.cos(y), 0, math.sin(y)], [0, 1, 0], [-math.sin(y), 0, math.cos(y)]])
    Rx = np.array([[1, 0, 0], [0, math.cos(p), -math.sin(p)], [0, math.sin(p), math.cos(p)]])
    return Rx @ Ry


LIGHT = np.array([-0.45, 1.0, 0.65]); LIGHT = LIGHT / np.linalg.norm(LIGHT)


def _raster(px_tris, depth, colors, W, rgb, zbuf, mask=None, shades=None):
    """px_tris: (N,3,2) экранные координаты; depth: (N,3) глубина (меньше = ближе); shades: (N,3) свет по углам."""
    for i, (t, z, c) in enumerate(zip(px_tris, depth, colors)):
        x0, y0 = np.floor(t.min(0)).astype(int); x1, y1 = np.ceil(t.max(0)).astype(int)
        x0, y0 = max(x0, 0), max(y0, 0); x1, y1 = min(x1, W - 1), min(y1, W - 1)
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        (ax, ay), (bx, by), (cx, cy) = t
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-9:
            continue
        w0 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / den
        w1 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / den
        w2 = 1 - w0 - w1
        inside = (w0 >= -1e-4) & (w1 >= -1e-4) & (w2 >= -1e-4)
        if not inside.any():
            continue
        zz = w0 * z[0] + w1 * z[1] + w2 * z[2]
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        upd = inside & (zz < sub)
        sub[upd] = zz[upd]
        if mask is not None:
            mask[y0:y1 + 1, x0:x1 + 1][upd] = 255
        elif shades is not None:  # гладкий шейдинг: свет интерполируется по барицентрам
            sh = (w0 * shades[i][0] + w1 * shades[i][1] + w2 * shades[i][2])[upd]
            col = np.clip(np.outer(sh, c[:3]), 0, 255).astype(np.uint8)
            rgb[y0:y1 + 1, x0:x1 + 1][upd] = np.c_[col, np.full(len(col), 255, np.uint8)]
        else:
            rgb[y0:y1 + 1, x0:x1 + 1][upd] = c


def render(model, size=320, yaw=145, pitch=-32, bg=(0, 0, 0, 0), ss=3, shadow=True) -> Image.Image:
    tris, cols, vn = model.world_triangles(with_normals=True)
    if len(tris) == 0:
        return Image.new("RGBA", (size, size), bg)
    R = _rot(yaw, pitch)
    W = size * ss
    vn = vn / np.maximum(np.linalg.norm(vn, axis=2, keepdims=True), 1e-9)
    shades = np.clip(0.58 + 0.42 * np.clip(vn @ LIGHT, 0, 1) + 0.08 * np.clip(vn[..., 1], 0, 1), 0, 1.08)
    v = tris @ R.T
    gtris = tris - LIGHT[None, None, :] * (tris[:, :, 1:2] / LIGHT[1])
    gv = gtris @ R.T
    pts = np.vstack([v.reshape(-1, 3), gv.reshape(-1, 3)]) if shadow else v.reshape(-1, 3)
    mn, mx = pts[:, :2].min(0), pts[:, :2].max(0)
    span = max(mx[0] - mn[0], mx[1] - mn[1]) * 1.1 + 1e-6
    c0 = (mn + mx) / 2
    scale = W / span

    def px(a):
        out = np.empty(a.shape[:-1] + (2,))
        out[..., 0] = (a[..., 0] - c0[0]) * scale + W / 2
        out[..., 1] = -(a[..., 1] - c0[1]) * scale + W / 2
        return out

    rgba = np.zeros((W, W, 4), dtype=np.uint8); rgba[:] = bg
    if shadow:
        sh = np.zeros((W, W), dtype=np.uint8)
        _raster(px(gv), np.zeros(gv.shape[:2]), [0] * len(gv), W, None, np.full((W, W), np.inf), mask=sh)
        shi = Image.fromarray(sh).filter(ImageFilter.GaussianBlur(W / 110))
        a = (np.asarray(shi, dtype=np.float32) * 0.36).astype(np.uint8)
        rgba[..., :3] = (20, 24, 30); rgba[..., 3] = a
    rgb = np.zeros((W, W, 4), dtype=np.uint8)
    z = np.full((W, W), np.inf)
    colors = [(r, g, b, 255) for r, g, b in cols]
    _raster(px(v), v[:, :, 2], colors, W, rgb, z, shades=shades)
    img = Image.alpha_composite(Image.fromarray(rgba, "RGBA"), Image.fromarray(rgb, "RGBA"))
    return img.resize((size, size), Image.LANCZOS)
