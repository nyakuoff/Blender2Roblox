"""Self-check for the numpy helpers in bake.py. Runs without Blender: python3 test_reduce.py"""

import importlib.util
import math
import pathlib

import numpy as np

spec = importlib.util.spec_from_file_location(
    "bake", pathlib.Path(__file__).resolve().parents[1] / "rbx_link" / "bake.py"
)
bake = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bake)


def axis_angle_quat(axis, angle):
    axis = np.asarray(axis, float) / np.linalg.norm(axis)
    return np.concatenate([axis * math.sin(angle / 2), [math.cos(angle / 2)]])


def quat_to_mat(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def reconstruct(t, pos, quat, stepped, keep):
    """Play back the kept keys the way Roblox does: Constant holds, Linear lerps/slerps."""
    out_p, out_q = np.empty_like(pos), np.empty_like(quat)
    for a, b in zip(keep, keep[1:]):
        j = np.arange(a, b + 1)
        if stepped[a]:
            out_p[a:b], out_q[a:b] = pos[a], quat[a]
            out_p[b], out_q[b] = pos[b], quat[b]
        else:
            u = ((t[j] - t[a]) / (t[b] - t[a]))[:, None]
            out_p[j] = pos[a] + u * (pos[b] - pos[a])
            out_q[j] = bake.slerp(quat[a], quat[b], u)
    return out_p, out_q


def check_within(t, pos, quat, stepped, keep, pos_tol, rot_tol):
    rp, rq = reconstruct(t, pos, quat, stepped, keep)
    perr = np.linalg.norm(rp - pos, axis=1).max()
    rerr = (2 * np.arccos(np.clip(np.abs(np.sum(rq * quat, 1)), 0, 1))).max()
    assert perr <= pos_tol + 1e-9, perr
    assert rerr <= rot_tol + 1e-9, rerr


def main():
    pos_tol, rot_tol = 1e-3, math.radians(0.1)

    # mat_to_quat round-trips through all four Shepperd branches (incl. 180 degree turns).
    for axis, ang in [((1, 0, 0), 3.1), ((0, 1, 0), 3.0), ((0, 0, 1), 2.9), ((1, 2, 3), 0.4), ((0, 0, 1), math.pi)]:
        q = axis_angle_quat(axis, ang)
        got = bake.mat_to_quat(quat_to_mat(q))
        assert abs(abs(got @ q) - 1) < 1e-9, (axis, ang, got, q)

    t = np.arange(240) / 60.0  # 4 s at 60 fps
    n = len(t)

    # Smooth sine motion: reduced, endpoints kept, every frame within tolerance.
    pos = np.stack([np.sin(t * 3), np.zeros(n), np.cos(t * 2) * 0.5], 1)
    quat = np.stack([axis_angle_quat((0, 1, 0), math.sin(x * 2)) for x in t])
    stepped = np.zeros(n, bool)
    keep = bake.reduce_keys(t, pos, quat, stepped, pos_tol, rot_tol)
    assert keep[0] == 0 and keep[-1] == n - 1
    assert len(keep) < n
    check_within(t, pos, quat, stepped, keep, pos_tol, rot_tol)

    # Stepped animation: holds of 12 frames, Constant easing reproduces it exactly.
    hold = (np.arange(n) // 12).astype(float)
    pos = np.stack([hold, np.zeros(n), np.zeros(n)], 1)
    quat = np.stack([axis_angle_quat((1, 0, 0), h * 0.3) for h in hold])
    stepped = np.ones(n, bool)
    keep = bake.reduce_keys(t, pos, quat, stepped, pos_tol, rot_tol)
    assert len(keep) == n // 12 + 1, len(keep)  # one key per hold + final frame
    check_within(t, pos, quat, stepped, keep, pos_tol, rot_tol)

    # A mid-clip return to the rest pose must survive (the original plugin dropped these).
    pos = np.zeros((n, 3))
    pos[100:140, 1] = np.sin(np.linspace(0, math.pi, 40))
    quat = np.tile([0, 0, 0, 1.0], (n, 1))
    stepped = np.zeros(n, bool)
    keep = bake.reduce_keys(t, pos, quat, stepped, pos_tol, rot_tol)
    check_within(t, pos, quat, stepped, keep, pos_tol, rot_tol)
    assert any(k <= 100 for k in keep[1:]) and any(k >= 139 for k in keep[:-1])

    # Every kept key is a sample index, so key times are always whole frames.
    assert all(isinstance(k, int) and 0 <= k < n for k in keep)
    print("test_reduce: ok")


if __name__ == "__main__":
    main()
