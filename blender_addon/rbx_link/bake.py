"""Bake an armature action into a compact Roblox pose payload.

Every frame is sampled once (dense, so nothing can be skipped or clamped),
the Motor6D math runs batched in numpy, then each bone's keys are thinned with
an error-bounded Ramer-Douglas-Peucker pass. Only bake() touches bpy, so the
numpy helpers can be tested outside Blender.
"""

import math
import re

import numpy as np

MOTOR_PROPS = ("transform", "transform1", "nicetransform")
FCURVE_PATH = re.compile(
    r'pose\.bones\["(.+)"\]\.(location|rotation_quaternion|rotation_euler|rotation_axis_angle|scale)$'
)


def mat_to_quat(r):
    """(..., 3, 3) rotation matrices -> (..., 4) unit quaternions as x, y, z, w."""
    m00, m01, m02 = r[..., 0, 0], r[..., 0, 1], r[..., 0, 2]
    m10, m11, m12 = r[..., 1, 0], r[..., 1, 1], r[..., 1, 2]
    m20, m21, m22 = r[..., 2, 0], r[..., 2, 1], r[..., 2, 2]
    a, b, c = m21 - m12, m02 - m20, m10 - m01
    d, e, g = m01 + m10, m02 + m20, m12 + m21
    # Row k is 4 * q[k] * q; take the row with the largest q[k] for stability.
    cand = np.stack([
        np.stack([1 + m00 - m11 - m22, d, e, a], -1),
        np.stack([d, 1 - m00 + m11 - m22, g, b], -1),
        np.stack([e, g, 1 - m00 - m11 + m22, c], -1),
        np.stack([a, b, c, 1 + m00 + m11 + m22], -1),
    ], -2)
    best = np.take_along_axis(cand, cand.diagonal(0, -2, -1).argmax(-1)[..., None, None], -2)[..., 0, :]
    return best / np.linalg.norm(best, axis=-1, keepdims=True)


def slerp(q0, q1, u):
    """Slerp two quaternions at fractions u of shape (n, 1)."""
    d = float(q0 @ q1)
    if d < 0:
        q1, d = -q1, -d
    if d > 0.9995:
        out = q0 + u * (q1 - q0)
        return out / np.linalg.norm(out, axis=-1, keepdims=True)
    th = math.acos(d)
    return (np.sin((1 - u) * th) * q0 + np.sin(u * th) * q1) / math.sin(th)


def reduce_keys(t, pos, quat, stepped, pos_tol, rot_tol):
    """Indices of samples to keep so every dropped sample is within tolerance.

    A key whose `stepped` flag is set holds its value until the next key
    (Roblox Constant easing); otherwise it lerps/slerps to the next key.
    """
    n = len(t)
    keep = {0, n - 1}
    stack = [(0, n - 1)]
    while stack:
        a, b = stack.pop()
        if b - a < 2:
            continue
        j = np.arange(a + 1, b)
        if stepped[a]:
            pp, qq = pos[a], quat[a]
        else:
            u = ((t[j] - t[a]) / (t[b] - t[a]))[:, None]
            pp = pos[a] + u * (pos[b] - pos[a])
            qq = slerp(quat[a], quat[b], u)
        perr = np.linalg.norm(pos[j] - pp, axis=1) / pos_tol
        dots = np.clip(np.abs(np.sum(quat[j] * qq, axis=1)), 0.0, 1.0)
        err = np.maximum(perr, 2 * np.arccos(dots) / rot_tol)
        k = int(err.argmax())
        if err[k] > 1:
            m = a + 1 + k
            keep.add(m)
            stack += [(a, m), (m, b)]
    return sorted(keep)


def _mat(prop):
    value = prop.to_list() if hasattr(prop, "to_list") else list(prop)
    return np.array(value, dtype=np.float64).reshape(4, 4)


def _stepped_flags(ao, pbones, idx, frames):
    """(F, K) bool: the bone's key at or before each frame is CONSTANT on every channel."""
    flags = np.zeros((len(frames), len(idx)), dtype=bool)
    ad = ao.animation_data
    if not ad or not ad.action or any(not tr.mute and len(tr.strips) for tr in ad.nla_tracks):
        return flags
    try:
        from bpy_extras.anim_utils import action_get_channelbag_for_slot
        bag = action_get_channelbag_for_slot(ad.action, ad.action_slot)
        fcurves = bag.fcurves if bag else []
    except ImportError:  # Blender < 4.4
        fcurves = ad.action.fcurves
    driven = {m.group(1) for d in ad.drivers if (m := FCURVE_PATH.match(d.data_path))}
    by_bone = {}
    for fc in fcurves:
        m = FCURVE_PATH.match(fc.data_path)
        if m:
            by_bone.setdefault(m.group(1), []).append(fc)
    f = np.asarray(frames, dtype=np.float64)
    for k, i in enumerate(idx):
        pb = pbones[i]
        curves = by_bone.get(pb.name)
        # Constraint/driver output does not follow the curves; keep it Linear.
        if not curves or pb.name in driven or any(not c.mute for c in pb.constraints):
            continue
        bone_flag = np.ones(len(frames), dtype=bool)
        for fc in curves:
            if fc.mute or len(fc.modifiers) or fc.extrapolation != "CONSTANT" or not len(fc.keyframe_points):
                bone_flag[:] = False
                break
            xs = np.array([kp.co.x for kp in fc.keyframe_points])
            const = np.array([kp.interpolation == "CONSTANT" for kp in fc.keyframe_points])
            j = np.searchsorted(xs, f + 1e-6, side="right") - 1
            bone_flag &= np.where(j < 0, True, const[np.clip(j, 0, None)])
        flags[:, k] = bone_flag
    return flags


def _ortho(m):
    """Drop scale from (..., 4, 4) transforms, keeping rotation and translation."""
    out = m.copy()
    out[..., :3, :3] = m[..., :3, :3] / np.linalg.norm(m[..., :3, :3], axis=-2, keepdims=True)
    return out


def bone_rest_distances(ao):
    """Rest distance of each bone from its parent bone, in Roblox units (for scale calibration)."""
    import bpy  # noqa: F401
    from bpy_extras.io_utils import axis_conversion

    world = np.array(axis_conversion(from_forward="Z", from_up="Y", to_forward="-Y", to_up="Z")
                     .to_4x4().inverted()) @ np.array(ao.matrix_world)
    out = {}
    for b in ao.data.bones:
        if b.parent:
            rest = _ortho(world @ np.array(b.matrix_local))
            prest = _ortho(world @ np.array(b.parent.matrix_local))
            out[b.get("rbx_source_name", b.name)] = float(np.linalg.norm((np.linalg.inv(prest) @ rest)[:3, 3]))
    return out


def is_skinned(ao):
    import bpy
    return any(m.type == "ARMATURE" and m.object == ao
               for o in bpy.data.objects if o.type == "MESH" for m in o.modifiers)


def bake(ao, exact=False, pos_tol=1e-3, rot_tol=math.radians(0.1), progress=None, bone_rest=None):
    """Sample the scene frame range of armature `ao` and return the payload dict.

    Motor6D bones (Roblox-rigged: transform/transform1/nicetransform) become Motor6D
    poses; every other bone becomes a Roblox Bone pose (skinned meshes). progress(done,
    total) is called while frames are sampled. bone_rest = {bone: rest distance from
    parent in Studio} calibrates Bone translation when the mesh was imported at a
    different scale.
    """
    import bpy
    from bpy_extras.io_utils import axis_conversion

    scene = bpy.context.scene
    back = np.array(axis_conversion(
        from_forward="Z", from_up="Y", to_forward="-Y", to_up="Z"
    ).to_4x4().inverted())

    pbones = list(ao.pose.bones)
    nb = len(pbones)
    motor = np.array([all(p in pb.bone for p in MOTOR_PROPS) for pb in pbones], dtype=bool)
    if not nb:
        raise ValueError(f"'{ao.name}' has no bones")
    index = {pb.name: i for i, pb in enumerate(pbones)}
    # Export names: Motor6D bones keep their (unique) bone name; Bones use the
    # recorded Roblox name if any.
    names = [pb.name if motor[i] else pb.bone.get("rbx_source_name", pb.name) for i, pb in enumerate(pbones)]
    if len(set(names)) < nb:  # a recorded Roblox name collides: fall back to unique bone names
        names = [pb.name for pb in pbones]

    # Parent = direct parent (or the original parent of a world-space bone).
    # Motor6D bones only count Motor6D parents; anything else makes them a root,
    # matching the original addon. Bones use any parent bone.
    par = np.full(nb, -1)
    for i, pb in enumerate(pbones):
        pname = pb.bone.get("worldspace_original_parent") if pb.bone.get("worldspace_bone") else None
        j = index.get(pname or (pb.parent.name if pb.parent else None), -1)
        par[i] = j if j >= 0 and (motor[j] or not motor[i]) else -1

    eye = np.eye(4)
    extr_inv = np.stack([np.linalg.inv(_mat(pb.bone["nicetransform"])) if motor[i] else eye
                         for i, pb in enumerate(pbones)])

    frames = list(range(scene.frame_start, scene.frame_end + 1, max(scene.frame_step, 1)))
    fps = scene.render.fps / (scene.render.fps_base or 1.0)
    buf = np.empty((len(frames), nb * 16), dtype=np.float64)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    restore = (scene.frame_current, scene.frame_subframe)
    try:
        for n, frame in enumerate(frames):
            scene.frame_set(frame)
            ao.evaluated_get(depsgraph).pose.bones.foreach_get("matrix", buf[n])
            if progress and n % 10 == 0:
                progress(n, len(frames))
    finally:
        scene.frame_set(restore[0], subframe=restore[1])
    # foreach_get flattens matrices column-major; transpose back to row-major.
    mats = buf.reshape(len(frames), nb, 4, 4).transpose(0, 1, 3, 2)

    def local_delta(cur, rest, sel):
        """rest_local^-1 @ cur_local for bones `sel`, local to their parent (or root)."""
        p = par[sel]
        hp = p >= 0
        lc, lr = cur[:, sel].copy(), rest[sel].copy()
        lc[:, hp] = np.linalg.inv(cur[:, p[hp]]) @ cur[:, sel][:, hp]
        lr[hp] = np.linalg.inv(rest[p[hp]]) @ rest[sel][hp]
        return np.linalg.inv(lr) @ lc

    pos = np.zeros((len(frames), nb, 3))
    rot = np.tile(eye[:3, :3], (len(frames), nb, 1, 1))

    # Motor6D path: same math as the original addon (armature space).
    m_sel = np.flatnonzero(motor)
    if len(m_sel):
        orig_base = np.tile(eye, (nb, 1, 1))
        orig_base[m_sel] = back @ np.stack([_mat(pbones[i].bone["transform"]) @ _mat(pbones[i].bone["transform1"])
                                            for i in m_sel])
        d = local_delta(back @ mats @ extr_inv, orig_base, m_sel)
        pos[:, m_sel], rot[:, m_sel] = d[..., :3, 3], d[..., :3, :3]

    # Bone path (original addon's deform serializer): world space, scale dropped,
    # local to the parent bone (a Motor6D parent uses its joint frame).
    d_sel = np.flatnonzero(~motor)
    if len(d_sel):
        world = back @ np.array(ao.matrix_world)
        rest_ml = np.stack([np.array(pb.bone.matrix_local) for pb in pbones])
        d = local_delta(_ortho(world @ mats @ extr_inv), _ortho(world @ rest_ml @ extr_inv), d_sel)
        t, r = d[..., :3, 3], d[..., :3, :3] / np.linalg.norm(d[..., :3, :3], axis=-2, keepdims=True)
        flip = np.diag([-1.0, 1.0, -1.0])  # Roblox Bone axes: 180 degrees about Y from Blender's
        skinned = is_skinned(ao)
        chain = set()
        for pb in pbones:
            if pb.bone.use_deform:
                chain.update([pb.name] + [a.name for a in pb.parent_recursive])
        in_chain = np.array([skinned and pbones[i].name in chain for i in d_sel])
        scale = 1.0
        if bone_rest and skinned:
            # Median ratio of Studio to Blender bone lengths, like the original addon.
            mine = bone_rest_distances(ao)
            ratios = sorted(float(bone_rest[n]) / mine[n] for n in mine
                            if n in bone_rest and mine[n] > 1e-6 and float(bone_rest[n]) > 1e-6)
            if ratios:
                mid = len(ratios) // 2
                scale = ratios[mid] if len(ratios) % 2 else (ratios[mid - 1] + ratios[mid]) / 2
        t = t @ flip  # position swizzle (-x, y, -z) for every Bone
        t[:, in_chain] *= scale
        r[:, in_chain] = flip @ r[:, in_chain] @ flip  # skinned chain: rotation flips too
        pos[:, d_sel], rot[:, d_sel] = t, r

    quat = mat_to_quat(rot / np.linalg.norm(rot, axis=-2, keepdims=True))
    stepped = _stepped_flags(ao, pbones, list(range(nb)), frames)
    times = (np.asarray(frames, dtype=np.float64) - scene.frame_start) / fps
    bones = {}
    for k, name in enumerate(names):
        p, q, s = pos[:, k], quat[:, k], stepped[:, k]
        if np.abs(p).max() < 1e-6 and np.abs(q[:, 3]).min() > 1 - 1e-10:
            continue  # rest pose for the whole clip
        keep = list(range(len(frames))) if exact else reduce_keys(times, p, q, s, pos_tol, rot_tol)
        bones[name] = {
            "t": times[keep].round(5).tolist(),
            "p": np.concatenate([p[keep], q[keep]], 1).round(5).ravel().tolist(),
            "e": "".join("C" if s[i] else "L" for i in keep),
        }

    # Whole tree, animated or not, so Studio can match bones to parts/Bones by name
    # and parent: {bone: [parent bone or "", Roblox name if recorded or "", "M"|"B"]}.
    rig = {names[k]: [names[par[k]] if par[k] >= 0 else "",
                      pbones[k].bone.get("rbx_source_name", "") if motor[k] else names[k],
                      "M" if motor[k] else "B"]
           for k in range(nb)}
    return {"fps": fps, "len": round(float(times[-1]), 5), "rig": rig, "bones": bones}
