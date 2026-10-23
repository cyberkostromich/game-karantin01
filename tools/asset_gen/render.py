"""Софтверный рендер превью low-poly моделей: ортографическая изометрия, плоский шейдинг, z-buffer, мягкая тень."""
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


def _raster(px_tris, depth, colors, W, rgb, zbuf, mask=None):
    """px_tris: (N,3,2) экранные координаты; depth: (N,3) глубина (меньше = ближе)."""
    for t, z, c in zip(px_tris, depth, colors):
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
        else:
            rgb[y0:y1 + 1, x0:x1 + 1][upd] = c


def render(model, size=320, yaw=145, pitch=-32, bg=(0, 0, 0, 0), ss=3, shadow=True) -> Image.Image:
    tris, cols = model.world_triangles()
    if len(tris) == 0:
        return Image.new("RGBA", (size, size), bg)
    R = _rot(yaw, pitch)
    W = size * ss
    n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    nl = np.linalg.norm(n, axis=1, keepdims=True); nl[nl == 0] = 1; n = n / nl
    shade = np.clip(0.58 + 0.42 * np.clip(n @ LIGHT, 0, 1) + 0.08 * np.clip(n[:, 1], 0, 1), 0, 1.08)
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
    colors = []
    for (r, g, b), s in zip(cols, shade):
        colors.append((min(255, int(r * s)), min(255, int(g * s)), min(255, int(b * s)), 255))
    _raster(px(v), v[:, :, 2], colors, W, rgb, z)
    img = Image.alpha_composite(Image.fromarray(rgba, "RGBA"), Image.fromarray(rgb, "RGBA"))
    return img.resize((size, size), Image.LANCZOS)
