"""
bl_worker.py — запускается внутри Blender (без numpy): меширует «органические» и скруглённые детали моделей.

    blender -b --factory-startup -P bl_worker.py -- in.json out.json

Вход: список спецификаций деталей (кадр игры: Y вверх, +Z вперёд, метры). Выход: на каждую деталь
треугольники с нормалями по углам — гладкий шейдинг, который не дают выпуклые оболочки trimesh.

Типы:
  skin — цепочка/дерево точек с радиусами → Skin + Subdivision (руки, ноги, торс, шея), затем Decimate;
  ell  — эллипсоид (голова, кисть, сумки), опционально срезанный плоскостью (купол шлема);
  rbox — коробка со скруглёнными фасками (Bevel + harden normals): плитник, подсумки, оружие;
  cyl  — цилиндр/усечённый конус с фаской (ствол, обод, бревно).
"""
import json
import math
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector


def _reset():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)


def _obj(me):
    ob = bpy.data.objects.new("p", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def _xf(p):
    """Поворот (градусы, X→Y→Z, как lowpoly._rot_matrix) и перенос в кадре игры."""
    rot = p.get("rot") or (0, 0, 0)
    M = Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
    return Matrix.Translation(Vector(p.get("pos", (0, 0, 0)))) @ M


def _skin(p):
    # Skin считает радиусы в своей системе (Z вверх): точки переводим в кадр Blender, на выходе — обратно.
    vs = [(x, -z, y) for x, y, z in p["v"]]
    me = bpy.data.meshes.new("s")
    me.from_pydata(vs, p["e"], [])
    ob = _obj(me)
    sk = ob.modifiers.new("skin", "SKIN")
    sk.use_smooth_shade = True
    sk.branch_smoothing = p.get("branch", 0.0)
    data = me.skin_vertices[0].data
    for i, r in enumerate(p["r"]):
        data[i].radius = r
    data[0].use_root = True
    ob.modifiers.new("sub", "SUBSURF").levels = p.get("sub", 1)
    return ob, True


def _ell(p):
    me = bpy.data.meshes.new("e")
    bm = bmesh.new()
    u, v = p.get("seg", (12, 6))
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=1.0)
    if "cut" in p:  # срез по локальной Y (−1..1), остаётся верх
        g = bm.verts[:] + bm.edges[:] + bm.faces[:]
        res = bmesh.ops.bisect_plane(bm, geom=g, plane_co=(0, p["cut"], 0), plane_no=(0, 1, 0), clear_inner=True)
        edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    bmesh.ops.scale(bm, vec=p["r"], verts=bm.verts)
    bm.transform(_xf(p))
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(me)
    bm.free()
    return _obj(me), False


def _hard(me, p):
    ob = _obj(me)
    if p.get("bevel", 0) > 0:
        bv = ob.modifiers.new("bev", "BEVEL")
        bv.width = p["bevel"]
        bv.segments = p.get("bseg", 2)
        bv.limit_method = "ANGLE"
        bv.harden_normals = True
        me.use_auto_smooth = True
        me.auto_smooth_angle = math.radians(p.get("smooth", 40))
        for f in me.polygons:
            f.use_smooth = True
    elif p.get("smooth"):
        me.use_auto_smooth = True
        me.auto_smooth_angle = math.radians(p["smooth"])
        for f in me.polygons:
            f.use_smooth = True
    return ob, False


def _rbox(p):
    me = bpy.data.meshes.new("b")
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=p["size"], verts=bm.verts)
    bm.transform(_xf(p))
    bm.to_mesh(me)
    bm.free()
    return _hard(me, p)


def _cyl(p):
    me = bpy.data.meshes.new("c")
    bm = bmesh.new()
    r2 = p.get("r2", p["r"])
    bmesh.ops.create_cone(bm, cap_ends=True, segments=p.get("seg", 10), radius1=p["r"], radius2=r2, depth=p["h"])
    bm.transform(_xf(p))
    bm.to_mesh(me)
    bm.free()
    p.setdefault("smooth", 50)
    return _hard(me, p)


KINDS = {"skin": _skin, "ell": _ell, "rbox": _rbox, "cyl": _cyl}


def _eval(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    return bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)


def _decimate(me, target):
    me.calc_loop_triangles()
    n = len(me.loop_triangles)
    if not target or n <= target:
        return me
    ob = _obj(me)
    d = ob.modifiers.new("dec", "DECIMATE")
    d.ratio = target / n
    d.use_collapse_triangulate = True
    return _eval(ob)


def mesh_piece(p):
    ob, from_bl = KINDS[p["k"]](p)
    me = _eval(ob)
    if p["k"] in ("skin", "ell"):
        me = _decimate(me, p.get("tris"))
        for f in me.polygons:
            f.use_smooth = True
    me.calc_normals_split()
    me.calc_loop_triangles()
    V, N = [], []
    for t in me.loop_triangles:
        for vi, n in zip(t.vertices, t.split_normals):
            c = me.vertices[vi].co
            if from_bl:
                V += [c.x, c.z, -c.y]
                N += [n[0], n[2], -n[1]]
            else:
                V += [c.x, c.y, c.z]
                N += [n[0], n[1], n[2]]
    return {"v": [round(x, 5) for x in V], "n": [round(x, 4) for x in N]}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    specs = json.load(open(argv[0]))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    out = {}
    for key, p in specs.items():
        _reset()
        out[key] = mesh_piece(p)
    json.dump(out, open(argv[1], "w"))


main()
