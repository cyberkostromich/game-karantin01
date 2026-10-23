"""
lowpoly.py — мини-библиотека для процедурных low-poly плейсхолдеров.

Все модели:
  * 1 ед. = 1 м, Y вверх, смотрят в +Z (конвенция glTF), pivot — центр основания;
  * один материал `palette` (assets/textures/palette.png, 256×256, 16×16 ячеек);
  * плоский шейдинг (вершины не шарятся между гранями), у деталей из Blender (Node.piece) — гладкие нормали;
  * анимируемые части — отдельные узлы с пивотом в точке вращения.

Использование:
    m = Model("unit_assault")
    body = m.node("body")
    body.box((0.5, 0.6, 0.3), (0, 1.15, 0), "OLIVE")
    arm = m.node("arm_r", parent="body", pivot=(0.35, 1.42, 0))
    arm.box(...)
    m.save("assets/models/units/unit_assault.glb")
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
import trimesh
from PIL import Image

# --------------------------------------------------------------------------------------
# Палитра: имя → (индекс ячейки, hex). Индекс i → ячейка (i % 16, i // 16).
# --------------------------------------------------------------------------------------
PALETTE: dict[str, tuple[int, str]] = {}


def _row(start: int, names_hex: list[tuple[str, str]]):
    for k, (n, h) in enumerate(names_hex):
        PALETTE[n] = (start + k, h)


_row(0, [("BLACK", "#1B1E23"), ("CHARCOAL", "#2E333B"), ("ASPHALT", "#3D424A"), ("CONCRETE_D", "#6B6F75"),
         ("CONCRETE", "#9A9C9E"), ("CONCRETE_L", "#C4C3BE"), ("PANEL_WHITE", "#E4E1D8"), ("PANEL_BEIGE", "#D8C7A3"),
         ("BRICK", "#9E4B36"), ("BRICK_L", "#B8694C"), ("STALIN_YEL", "#D9B97A"), ("ROOF_D", "#4A4F57"),
         ("TILE_BLUE", "#5B88A8"), ("TILE_TEAL", "#3E8A87"), ("GLASS", "#8FB3C7"), ("WHITE", "#F5F3EE")])
_row(16, [("OLIVE_D", "#3F4A2A"), ("OLIVE", "#5B6B3A"), ("OLIVE_L", "#7D8C55"), ("KHAKI", "#A69B6A"),
          ("CAMO_BROWN", "#6B5539"), ("STEEL_D", "#3A4148"), ("STEEL", "#5E6770"), ("GUNMETAL", "#2A2D31"),
          ("SKIN_A", "#E0B48F"), ("SKIN_B", "#B98463"), ("SKIN_C", "#7D5238"), ("HAIR_D", "#2B211B"),
          ("HAIR_L", "#8A6A45"), ("HELMET", "#4E5A35"), ("MEDIC_RED", "#C8383A"), ("MEDIC_WHITE", "#F0EEE8")])
_row(32, [("CIV_RED", "#B5473F"), ("CIV_BLUE", "#3F6FA8"), ("CIV_YELLOW", "#E0B43A"), ("CIV_GREEN", "#4F8A5B"),
          ("CIV_PURPLE", "#7A5B9A"), ("CIV_DENIM", "#4A5D7E"), ("CIV_GREY", "#7E8288"), ("CIV_PINK", "#D98AA0"),
          ("CIV_ORANGE", "#E07B39"), ("SHOE", "#2A2622")])
_row(48, [("ZMB_SKIN", "#8E9E6E"), ("ZMB_SKIN_D", "#64714E"), ("ZMB_CLOTH", "#5C5648"), ("ZMB_CLOTH_D", "#3E3A31"),
          ("BLOOD", "#7A1F1F"), ("BLOOD_L", "#A33A2E"), ("INFECT_GLOW", "#9BE564"), ("BRUTE_SKIN", "#7A7F5A"),
          ("SPIT_SAC", "#B6D94A"), ("SCREAM_MOUTH", "#4A1414"), ("NEST_FLESH", "#6E3B3B"), ("NEST_DARK", "#3A2222")])
_row(64, [("GRASS", "#6E8B4E"), ("GRASS_D", "#4E6A38"), ("LEAF", "#5E8C3E"), ("LEAF_AUTUMN", "#C98A2E"),
          ("LEAF_RED", "#A8452E"), ("BARK", "#5A4632"), ("WOOD", "#A77B4F"), ("WOOD_L", "#C9A273"),
          ("DIRT", "#7B6A55"), ("WATER", "#4F7A99"), ("WATER_D", "#375A75"), ("SAND", "#CDBA8E"),
          ("SANDBAG", "#B5A27A"), ("BIRCH", "#E9E6DC"), ("PINE", "#2F5236")])
_row(80, [("TEAM", "#2F80ED"), ("SIGNAL_ORANGE", "#FF6A1F"), ("HAZARD_YELLOW", "#F2C230"), ("LIGHT_WARM", "#FFE3A3"),
          ("LIGHT_EMIT", "#FFF4D6"), ("RED_CROSS", "#D23B3B"), ("GREEN_LIGHT", "#59D17A"), ("SOLAR_BLUE", "#26466B"),
          ("TARP_GREEN", "#556B3F"), ("TARP_BLUE", "#3C5D86"), ("RUST", "#8C4A2B"), ("CAR_RED", "#A23A33"),
          ("CAR_BLUE", "#35577F"), ("CAR_WHITE", "#D9D9D4"), ("TIRE", "#1F1F1F"), ("SMOKE", "#8A8A8A")])

CELL_PX = 16
TEX_PX = 256


def hex_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def build_palette_image() -> Image.Image:
    img = Image.new("RGBA", (TEX_PX, TEX_PX), (255, 0, 255, 255))  # пустые ячейки — маджента (видно ошибку)
    px = img.load()
    for name, (idx, h) in PALETTE.items():
        cx, cy = idx % 16, idx // 16
        r, g, b = hex_rgb(h)
        for y in range(cy * CELL_PX, (cy + 1) * CELL_PX):
            for x in range(cx * CELL_PX, (cx + 1) * CELL_PX):
                px[x, y] = (r, g, b, 255)
    return img


def uv_for(color: str) -> tuple[float, float]:
    idx = PALETTE[color][0]
    cx, cy = idx % 16, idx // 16
    u = (cx + 0.5) / 16.0
    v = 1.0 - (cy + 0.5) / 16.0  # glTF v идёт снизу вверх в trimesh → переворачиваем
    return u, v


_PALETTE_IMG = build_palette_image()
_MATERIAL = trimesh.visual.material.PBRMaterial(
    name="palette", baseColorTexture=_PALETTE_IMG, metallicFactor=0.0, roughnessFactor=0.9,
)

# --------------------------------------------------------------------------------------
# Геометрия
# --------------------------------------------------------------------------------------

def _rot_matrix(rot_deg) -> np.ndarray:
    """rot_deg = (rx, ry, rz) в градусах, порядок X→Y→Z."""
    if rot_deg is None:
        return np.eye(4)
    rx, ry, rz = [math.radians(a) for a in rot_deg]
    M = trimesh.transformations.euler_matrix(rx, ry, rz, "sxyz")
    return M


def _xf(mesh: trimesh.Trimesh, pos, rot=None, scale=None) -> trimesh.Trimesh:
    m = mesh.copy()
    if scale is not None:
        m.apply_scale(scale)
    if rot is not None:
        m.apply_transform(_rot_matrix(rot))
    m.apply_translation(pos)
    return m


class Part:
    __slots__ = ("mesh", "color", "normals")

    def __init__(self, mesh, color, normals=None):
        self.mesh, self.color = mesh, color
        self.normals = normals  # (F,3,3) нормали по углам — гладкий шейдинг; None — плоский


class Node:
    def __init__(self, model: "Model", name: str, parent: str | None, pivot):
        self.model, self.name, self.parent = model, name, parent
        self.pivot = np.array(pivot, dtype=float)  # мировая позиция пивота (для дочерних — тоже мировая)
        self.parts: list[Part] = []
        self.rest_rot = None  # поворот узла в позе покоя (градусы) вокруг пивота

    # --- примитивы (координаты мировые, в метрах) ---
    def add(self, mesh, color):
        self.parts.append(Part(mesh, color))
        return self

    def piece(self, spec, color):
        """Деталь, которую меширует Blender (blmesh/bl_worker): скругления и гладкие нормали."""
        import blmesh
        part = Part(None, color)
        self.parts.append(part)
        blmesh.request(spec, part)
        return self

    def box(self, size, pos, color, rot=None):
        return self.add(_xf(trimesh.creation.box(extents=size), pos, rot), color)

    def cyl(self, r, h, pos, color, sections=8, rot=None, r2=None):
        if r2 is None:
            m = trimesh.creation.cylinder(radius=r, height=h, sections=sections)
        else:
            m = _frustum(r, r2, h, sections)  # усечённый конус, r — низ, r2 — верх (по оси Z)
        return self.add(_xf(m, pos, rot), color)

    def cone(self, r, h, pos, color, sections=8, rot=None):
        m = trimesh.creation.cone(radius=r, height=h, sections=sections)
        m.apply_translation((0, 0, -h / 2))
        return self.add(_xf(m, pos, rot), color)

    def ball(self, r, pos, color, subdiv=1, scale=None):
        m = trimesh.creation.icosphere(subdivisions=subdiv, radius=r)
        return self.add(_xf(m, pos, None, scale), color)

    def prism(self, pts2d, height, pos, color, rot=None):
        """Экструзия 2D-полигона (XY) по высоте вдоль Z, затем rot/pos."""
        from shapely.geometry import Polygon
        m = trimesh.creation.extrude_polygon(Polygon(pts2d), height)
        return self.add(_xf(m, pos, rot), color)

    def wedge(self, size, pos, color, rot=None, slope="front"):
        """Клин: прямоугольник снизу, верх скошен к +Z (front) — для лобовых листов брони, крыш."""
        w, h, d = size
        pts = [(-d / 2, 0), (d / 2, 0), (d / 2, h * 0.15), (-d / 2, h)] if slope == "front" else \
              [(-d / 2, 0), (d / 2, 0), (d / 2, h), (-d / 2, h * 0.15)]
        # профиль в плоскости (z, y), экструзия по x
        from shapely.geometry import Polygon
        m = trimesh.creation.extrude_polygon(Polygon(pts), w)
        # сейчас: x_local=z, y_local=y, z_local=x → переставляем оси
        M = np.array([[0, 0, 1, -w / 2], [0, 1, 0, 0], [1, 0, 0, 0], [0, 0, 0, 1]], dtype=float)
        m.apply_transform(M)
        return self.add(_xf(m, pos, rot), color)

    def roof(self, size, pos, color, rot=None):
        """Двускатная крыша: основание w×d, конёк вдоль Z, высота h."""
        w, h, d = size
        from shapely.geometry import Polygon
        m = trimesh.creation.extrude_polygon(Polygon([(-w / 2, 0), (w / 2, 0), (0, h)]), d)
        m.apply_translation((0, 0, -d / 2))
        return self.add(_xf(m, pos, rot), color)


def _frustum(r1, r2, h, sections):
    ang = np.linspace(0, 2 * np.pi, sections, endpoint=False)
    bot = np.c_[r1 * np.cos(ang), r1 * np.sin(ang), np.full(sections, -h / 2)]
    top = np.c_[r2 * np.cos(ang), r2 * np.sin(ang), np.full(sections, h / 2)]
    v = np.vstack([bot, top, [[0, 0, -h / 2], [0, 0, h / 2]]])
    f = []
    for i in range(sections):
        j = (i + 1) % sections
        f += [[i, j, sections + j], [i, sections + j, sections + i]]
        f += [[2 * sections, j, i], [2 * sections + 1, sections + i, sections + j]]
    m = trimesh.Trimesh(v, f, process=True)
    m.fix_normals()
    return m


# trimesh-цилиндры ориентированы по Z. Удобные повороты:
UP = (-90, 0, 0)       # ось цилиндра → Y (вертикально)
ALONG_X = (0, 90, 0)   # ось → X
ALONG_Z = None          # ось → Z (по умолчанию)


class Model:
    def __init__(self, name: str, meta: dict | None = None):
        self.name = name
        self.nodes: dict[str, Node] = {}
        self.order: list[str] = []
        self.meta = meta or {}

    def node(self, name: str, parent: str | None = None, pivot=(0, 0, 0)) -> Node:
        if name in self.nodes:
            return self.nodes[name]
        n = Node(self, name, parent, pivot)
        self.nodes[name] = n
        self.order.append(name)
        return n

    # ---------------- сборка ----------------
    def _node_mesh(self, node: Node) -> trimesh.Trimesh | None:
        if not node.parts:
            return None
        V, F, UV, N = [], [], [], []
        off = 0
        for p in node.parts:
            m = p.mesh
            tri = m.vertices[m.faces]                      # (n,3,3) — расшариваем вершины → плоский шейдинг
            v = tri.reshape(-1, 3) - node.pivot            # локально относительно пивота
            if p.normals is not None:
                nr = p.normals.reshape(-1, 3)
            else:
                fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
                fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
                nr = np.repeat(fn, 3, axis=0)
            f = np.arange(len(v)).reshape(-1, 3) + off
            uv = np.tile(uv_for(p.color), (len(v), 1))
            V.append(v); F.append(f); UV.append(uv); N.append(nr)
            off += len(v)
        V, F, UV, N = np.vstack(V), np.vstack(F), np.vstack(UV), np.vstack(N)
        mesh = trimesh.Trimesh(V, F, vertex_normals=N, process=False,
                               visual=trimesh.visual.TextureVisuals(uv=UV, material=_MATERIAL))
        return mesh

    def scene(self) -> trimesh.Scene:
        sc = trimesh.Scene()
        root = self.name
        sc.graph.update(frame_to=root, frame_from=sc.graph.base_frame, matrix=np.eye(4))
        for name in self.order:
            node = self.nodes[name]
            parent = node.parent or root
            parent_pivot = self.nodes[node.parent].pivot if node.parent else np.zeros(3)
            T = np.eye(4)
            T[:3, 3] = node.pivot - parent_pivot
            if node.rest_rot is not None:
                T = T @ _rot_matrix(node.rest_rot)
            mesh = self._node_mesh(node)
            if mesh is not None:
                sc.add_geometry(mesh, geom_name=f"{name}_mesh", node_name=name,
                                parent_node_name=parent, transform=T)
            else:
                sc.graph.update(frame_to=name, frame_from=parent, matrix=T)
        return sc

    def save(self, path: str | Path):
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        data = self.scene().export(file_type="glb", include_normals=True)
        path.write_bytes(data)
        return path

    # для превью: мировые треугольники + цвета
    def world_triangles(self, with_normals=False):
        sc = self.scene()
        tris, cols, norms = [], [], []
        for node_name in sc.graph.nodes_geometry:
            T, geom_name = sc.graph[node_name]
            g = sc.geometry[geom_name]
            v = trimesh.transformations.transform_points(g.vertices, T)
            vn = g.vertex_normals @ T[:3, :3].T
            uv = g.visual.uv
            for face in g.faces:
                tris.append(v[face])
                norms.append(vn[face])
                u, vv = uv[face[0]]
                cx = int(u * 16); cy = int((1 - vv) * 16)
                idx = cy * 16 + cx
                cols.append(_IDX2RGB.get(idx, (255, 0, 255)))
        if with_normals:
            return np.array(tris), cols, np.array(norms)
        return np.array(tris), cols

    def stats(self):
        sc = self.scene()
        tri = sum(len(g.faces) for g in sc.geometry.values())
        b = sc.bounds
        return {"tris": int(tri), "size_m": [round(float(x), 2) for x in (b[1] - b[0])]}


_IDX2RGB = {idx: hex_rgb(h) for _, (idx, h) in PALETTE.items()}


def save_palette(path: str | Path):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    _PALETTE_IMG.save(path)
