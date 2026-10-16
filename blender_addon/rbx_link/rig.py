"""Build a Blender armature from the Roblox plugin's rig JSON.

Bone custom props (transform, transform0, transform1, nicetransform,
rbx_source_name) match the original addon, so rigs made by either addon bake
the same way. Each part gets its real mesh when Studio sent one (POST /mesh),
otherwise a box sized from its Roblox Size.
"""

import bpy
import numpy as np
from bpy_extras.io_utils import axis_conversion
from mathutils import Matrix, Vector

MESHES = {}  # mesh id -> {"v": [x,y,z..], "f": [i,j,k..], "u": [u,v..], "fu": [uv index per corner]}
_BOX_FACES = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]


def cf_to_mat(cf):
    mat = Matrix.Translation((cf[0], cf[1], cf[2]))
    mat[0][0:3] = cf[3:6]
    mat[1][0:3] = cf[6:9]
    mat[2][0:3] = cf[9:12]
    return mat


def _prop(mat):
    return [list(row) for row in mat]


def _add_bone(amt, t2b, node, parent, mode, out):
    """Port of the original load_rigbone core (RAW / LOCAL_AXIS_EXTEND)."""
    bone = amt.edit_bones.new(node["jname"])
    bone["rbx_source_name"] = node["jname"]
    mat = cf_to_mat(node["transform"])
    bone["transform"] = _prop(mat)
    bone_dir = (t2b @ mat).to_3x3().to_4x4() @ Vector((0, 0, 1))

    if "jointtransform0" not in node:  # rig root
        bone.head = (t2b @ mat).to_translation()
        bone.tail = (t2b @ mat) @ Vector((0, 0.01, 0))
        bone["transform0"] = _prop(Matrix())
        bone["transform1"] = _prop(Matrix())
        o_trans = t2b @ mat
    else:
        mat1 = cf_to_mat(node["jointtransform1"])
        bone["transform0"] = _prop(cf_to_mat(node["jointtransform0"]))
        bone["transform1"] = _prop(mat1)
        bone["is_transformable"] = True
        bone.parent = parent
        o_trans = t2b @ (mat @ mat1)
        bone.head = o_trans.to_translation()
        real_tail = o_trans @ Vector((0, 0.25, 0))
        bone.tail = real_tail
        bone.align_roll(bone_dir)
        children = node.get("children") or []
        if mode == "LOCAL_AXIS_EXTEND":
            pre_mat = bone.matrix
            if len(children) == 1 and "jointtransform1" in children[0]:
                c = children[0]
                target = (t2b @ (cf_to_mat(c["transform"]) @ cf_to_mat(c["jointtransform1"]))).to_translation()
                local = pre_mat.inverted() @ target
                axis = max(range(3), key=lambda i: abs(local[i]))
                bone.tail = bone.head + pre_mat.to_3x3().col[axis].normalized() * local[axis]
            else:
                bone.tail = bone.head + (bone.head - (t2b @ mat).to_translation()) * -2
            if (bone.tail - bone.head).length < 0.01:
                bone.tail = real_tail
    bone.align_roll(bone_dir)
    bone["nicetransform"] = _prop(o_trans.inverted() @ bone.matrix)
    out.append((bone.name, node))
    for child in node.get("children") or []:
        _add_bone(amt, t2b, child, bone, mode, out)


def build_rig(data, mode="RAW"):
    """data = {"rigName": str, "rig": {jname, transform, jointtransform0/1, size, children}}"""
    t2b = axis_conversion(from_forward="Z", from_up="Y", to_forward="-Y", to_up="Z").to_4x4()
    name = data.get("rigName", "Rig")
    amt = bpy.data.armatures.new(f"__{name}_RigArm")
    amt.show_names = True
    ao = bpy.data.objects.new(f"__{name}_Armature", amt)
    ao.show_in_front = True
    bpy.context.scene.collection.objects.link(ao)
    # mode_set edits every selected armature, so select only the new one.
    for o in bpy.context.view_layer.objects.selected:
        o.select_set(False)
    ao.select_set(True)
    bpy.context.view_layer.objects.active = ao
    with bpy.context.temp_override(active_object=ao, object=ao):
        bpy.ops.object.mode_set(mode="EDIT")
        made = []
        _add_bone(amt, t2b, data["rig"], None, mode, made)
        bpy.ops.object.mode_set(mode="OBJECT")

    # One object per part (and per welded accessory part), parented to its bone
    # at the part's Roblox CFrame.
    for bone_name, node in made:
        for part in [node] + (node.get("aux") or []):
            obj = bpy.data.objects.new(part["jname"], _part_mesh(part))
            bpy.context.scene.collection.objects.link(obj)
            obj.parent, obj.parent_type, obj.parent_bone = ao, "BONE", bone_name
            obj.matrix_world = ao.matrix_world @ t2b @ cf_to_mat(part["transform"])
    return ao


def _part_mesh(part):
    """Mesh in the part's local Roblox space: Studio's geometry if sent, else a box."""
    me = bpy.data.meshes.new(part["jname"])
    geo = MESHES.get(part.get("mesh"))
    if geo is None:
        sx, sy, sz = part.get("size") or (1, 1, 1)
        me.from_pydata([(x * sx / 2, y * sy / 2, z * sz / 2)
                        for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)], [], _BOX_FACES)
        return me
    # v_part = v_mesh * meshScale + meshOffset (Studio computes these per part)
    v = np.asarray(geo["v"], float).reshape(-1, 3) * part.get("meshScale", (1, 1, 1)) + part.get("meshOffset", (0, 0, 0))
    me.from_pydata(v.tolist(), [], np.asarray(geo["f"], int).reshape(-1, 3).tolist())
    if geo.get("u") and geo.get("fu"):
        uv = np.asarray(geo["u"], float).reshape(-1, 2)[np.asarray(geo["fu"], int)]
        uv[:, 1] = 1 - uv[:, 1]  # Roblox UV origin is top-left, Blender's bottom-left
        me.uv_layers.new(name="UVMap").data.foreach_set("uv", uv.ravel())
    me.validate()
    return me
