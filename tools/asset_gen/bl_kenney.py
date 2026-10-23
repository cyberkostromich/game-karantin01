"""
bl_kenney.py — запускается внутри Blender: модель Kenney «Animated Characters» (CC0, один меш + скелет)
ставится в позу, деформируется скелетом и режется по костям на жёсткие части — узлы игры
(body, head, arm_*/forearm_*, leg_*/shin_*). Так процедурная анимация (HumanAnim, zombie.gdshader) и
MultiMesh орды работают без скиннинга.

    blender -b --factory-startup -P bl_kenney.py -- model.fbx specs.json out.json

spec: {"pose": [[кость, [ось x,y,z в кадре игры], градусы], ...], "scale": {кость: k}, "height": м,
       "decimate": доля или 0}
Кадр игры: Y вверх, +Z вперёд (у Blender: Z вверх, −Y вперёд). Кости Kenney Left* — это +X, то есть
наши *_r (у генератора «l» — сторона −X).
"""
import json
import math
import sys

import bpy
from mathutils import Matrix, Vector

NODE_OF = {
    "Hips": "body", "Spine": "body", "Chest": "body", "UpperChest": "body", "LeftShoulder": "body",
    "RightShoulder": "body", "Neck": "head", "Head": "head",
    "RightArm": "arm_l", "RightForeArm": "forearm_l", "LeftArm": "arm_r", "LeftForeArm": "forearm_r",
    "RightUpLeg": "leg_l", "RightLeg": "shin_l", "LeftUpLeg": "leg_r", "LeftLeg": "shin_r",
}
PIVOT_BONE = {"head": "Neck", "arm_l": "RightArm", "forearm_l": "RightForeArm", "arm_r": "LeftArm",
              "forearm_r": "LeftForeArm", "leg_l": "RightUpLeg", "shin_l": "RightLeg", "leg_r": "LeftUpLeg",
              "shin_r": "LeftLeg"}
PARENT = {"head": "body", "arm_l": "body", "arm_r": "body", "forearm_l": "arm_l", "forearm_r": "arm_r",
          "shin_l": "leg_l", "shin_r": "leg_r"}
ANCHORS = ["Head", "Head_end", "Neck", "UpperChest", "Chest", "Spine", "Hips", "RightHand", "LeftHand",
           "RightHandIndex3_end", "LeftHandIndex3_end", "RightForeArm", "LeftForeArm", "RightArm", "LeftArm",
           "RightLeg", "LeftLeg", "RightFoot", "LeftFoot", "RightToes_end", "LeftToes_end"]


def node_of(bone):
    """Кисти/пальцы — к предплечью, стопы — к голени."""
    if bone in NODE_OF:
        return NODE_OF[bone]
    side = "l" if bone.startswith("Right") else "r"
    if "Hand" in bone:
        return f"forearm_{side}"
    if "Foot" in bone or "Toe" in bone:
        return f"shin_{side}"
    return "body"


def to_bl(v):  # кадр игры → Blender
    return Vector((v[0], -v[2], v[1]))


def to_game(v):
    return [v.x, v.z, -v.y]


def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=path)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    mesh = next(o for o in bpy.data.objects if o.type == "MESH")
    return arm, mesh


_REST = {}


def reset(arm, mesh):
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    if not _REST:
        _REST["co"] = [v.co.copy() for v in mesh.data.vertices]
    for v, co in zip(mesh.data.vertices, _REST["co"]):
        v.co = co
    mesh.data.update()
    bpy.context.view_layer.update()


def inflate(arm, mesh, spec):
    """Объём по костям (громила, великан): вершины сдвигаются по нормали пропорционально весу кости;
    head_k — масштаб головы вокруг её центра. Делается в позе покоя до деформации скелетом."""
    amt = spec.get("inflate", {})
    hk = spec.get("head_k", 1.0)
    if not amt and hk == 1.0:
        return
    h = mesh.dimensions.z
    names = {g.index: g.name for g in mesh.vertex_groups}
    hb = arm.data.bones["Head"]
    hc = arm.matrix_world @ ((hb.head_local + hb.tail_local) / 2)
    hc = mesh.matrix_world.inverted() @ hc
    for v in mesh.data.vertices:
        d = 0.0
        hw = 0.0
        for g in v.groups:
            d += g.weight * amt.get(names[g.group], 0.0)
            if names[g.group] in ("Head", "Neck"):
                hw += g.weight
        v.co = v.co + v.normal * d * h
        if hk != 1.0 and hw > 0.0:
            v.co = hc + (v.co - hc) * (1.0 + (hk - 1.0) * min(1.0, hw))
    mesh.data.update()


def pose(arm, spec):
    for name, k in spec.get("scale", {}).items():
        arm.pose.bones[name].scale = (k, k, k)
    bpy.context.view_layer.update()
    to_arm = arm.matrix_world.to_3x3().inverted()
    for name, axis, deg in spec.get("pose", []):
        pb = arm.pose.bones[name]
        head = pb.head.copy()
        R = Matrix.Rotation(math.radians(deg), 4, (to_arm @ to_bl(axis)).normalized())
        pb.matrix = Matrix.Translation(head) @ R @ Matrix.Translation(-head) @ pb.matrix
        bpy.context.view_layer.update()


class Space:
    """Перевод кадра игры (метры, ступни на 0, таз в 0) в пространство арматуры и обратно."""

    def __init__(self, arm, mesh, height):
        zs = [(mesh.matrix_world @ c).z for c in _REST["co"]]
        self.k = height / (max(zs) - min(zs))           # по росту в позе покоя, а не после позы
        hips = arm.matrix_world @ arm.pose.bones["Hips"].head
        self.off = Vector((hips.x, hips.y, min(zs)))
        self.inv = arm.matrix_world.inverted()

    def to_arm(self, g):
        return self.inv @ (to_bl([c / self.k for c in g]) + self.off)

    def game(self, world_co):
        return [round(c * self.k, 5) for c in to_game(world_co - self.off)]


def _aim(arm, pb, target):
    """Повернуть кость (в пространстве арматуры) так, чтобы её хвост смотрел на target."""
    cur = (pb.tail - pb.head).normalized()
    want = (target - pb.head).normalized()
    R = cur.rotation_difference(want).to_matrix().to_4x4()
    pb.matrix = Matrix.Translation(pb.head) @ R @ Matrix.Translation(-pb.head) @ pb.matrix
    bpy.context.view_layer.update()


def ik(arm, sp, side, target, pole):
    """Двухзвенная IK руки: запястье в target (кадр игры), локоть — в сторону pole."""
    up, lo = arm.pose.bones[side + "Arm"], arm.pose.bones[side + "ForeArm"]
    S = up.head.copy()
    T = sp.to_arm(target)
    P = sp.to_arm(pole)
    l1, l2 = up.length, lo.length
    d = min((T - S).length, (l1 + l2) * 0.999)
    T = S + (T - S).normalized() * d
    a = (l1 * l1 + d * d - l2 * l2) / (2 * d)
    h = math.sqrt(max(0.0, l1 * l1 - a * a))
    ax = (T - S).normalized()
    side_v = (P - S) - ax * (P - S).dot(ax)
    E = S + ax * a + side_v.normalized() * h
    _aim(arm, up, E)
    _aim(arm, lo, T)


def bake(arm, mesh, spec):
    """Деформированный скелетом меш (с весами) в мировых координатах + опциональный Decimate."""
    if spec.get("decimate"):
        d = mesh.modifiers.new("dec", "DECIMATE")
        d.ratio = spec["decimate"]
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(mesh.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    me.transform(mesh.matrix_world)
    if spec.get("decimate"):
        mesh.modifiers.remove(mesh.modifiers["dec"])
    return me


def export(arm, mesh, spec):
    reset(arm, mesh)
    inflate(arm, mesh, spec)
    pose(arm, spec)
    sp = Space(arm, mesh, spec["height"])
    for side, target, pole in spec.get("ik", []):
        ik(arm, sp, side, target, pole)
    me = bake(arm, mesh, spec)
    me.calc_normals_split()
    me.calc_loop_triangles()
    gname = {g.index: g.name for g in mesh.vertex_groups}
    k = sp.k
    P = sp.game

    vnode, vbone = [], []
    for v in me.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        vbone.append(gname[best.group] if best else "Hips")
        vnode.append(node_of(vbone[-1]))
    uv = me.uv_layers.active.data
    nodes = {}
    for t in me.loop_triangles:
        votes = [vnode[i] for i in t.vertices]
        nd = max(set(votes), key=votes.count)
        d = nodes.setdefault(nd, {"v": [], "n": [], "uv": [], "b": []})
        bones = [vbone[i] for i in t.vertices]
        d["b"].append(max(set(bones), key=bones.count))
        for li, vi, n in zip(t.loops, t.vertices, t.split_normals):
            d["v"] += P(me.vertices[vi].co)
            d["n"] += [round(x, 4) for x in to_game(Vector(n))]
            d["uv"] += [round(uv[li].uv[0], 5), round(uv[li].uv[1], 5)]
    for nd, d in nodes.items():
        pb = PIVOT_BONE.get(nd)
        if pb:
            d["pivot"] = P(arm.matrix_world @ arm.pose.bones[pb].head)
        else:  # таз: между тазобедренными суставами
            a = arm.matrix_world @ arm.pose.bones["RightUpLeg"].head
            b = arm.matrix_world @ arm.pose.bones["LeftUpLeg"].head
            d["pivot"] = P((a + b) / 2)
        d["parent"] = PARENT.get(nd)
    anchors = {}
    for b in ANCHORS:
        pb = arm.pose.bones[b]
        anchors[b] = P(arm.matrix_world @ pb.head)
        anchors[b + ":tail"] = P(arm.matrix_world @ pb.tail)
    return {"nodes": nodes, "anchors": anchors, "scale": k}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    model, specs, out = argv[0], json.load(open(argv[1])), argv[2]
    arm, mesh = load(model)
    res = {key: export(arm, mesh, spec) for key, spec in specs.items()}
    json.dump(res, open(out, "w"))


main()
