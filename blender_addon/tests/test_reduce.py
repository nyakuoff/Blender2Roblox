"""Self-check for the numpy helpers in bake.py. Runs without Blender: python3 test_reduce.py"""

import importlib.util
import math
import pathlib

import numpy as np

spec = importlib.util.spec_from_file_location(
    "bake", pathlib.Path(__file__).resolve().parents[1] / "blender2roblox" / "bake.py"
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


def reference_reduce(t, pos, quat, stepped, pos_tol, rot_tol):
    """The original one-segment-at-a-time reducer; reduce_all must keep exactly these keys."""
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
            qq = bake.slerp(quat[a], quat[b], u)
        perr = np.linalg.norm(pos[j] - pp, axis=1) / pos_tol
        dots = np.clip(np.abs(np.sum(quat[j] * qq, axis=1)), 0.0, 1.0)
        err = np.maximum(perr, 2 * np.arccos(dots) / rot_tol)
        k = int(err.argmax())
        if err[k] > 1:
            m = a + 1 + k
            keep.add(m)
            stack += [(a, m), (m, b)]
    return sorted(keep)


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
    # Batched reducer keeps exactly the reference keys on random curves (holds, steps, noise).
    rng = np.random.default_rng(7)
    for trial in range(60):
        n = int(rng.integers(3, 400))
        tt = np.arange(n) / 60.0
        steps = rng.random(n) < 0.05
        pos = np.cumsum(rng.normal(0, 0.01, (n, 3)) * (rng.random((n, 1)) < 0.7), axis=0)
        ang = np.cumsum(rng.normal(0, 0.01, n) + np.where(steps, 0.3, 0))
        quat = np.stack([axis_angle_quat((1, 2, 3), a) for a in ang])
        stepped = rng.random(n) < (0.5 if trial % 2 else 0.0)
        want = reference_reduce(tt, pos, quat, stepped, pos_tol, rot_tol)
        got = bake.reduce_keys(tt, pos, quat, stepped, pos_tol, rot_tol)
        assert got == want, (trial, len(got), len(want))
    # Exact mode: lossless_keep drops only samples equal to both ends of their gap, so
    # replaying the kept keys (Linear or Constant) reproduces every sample bit-for-bit.
    for trial in range(30):
        n = int(rng.integers(3, 300))
        tt = np.arange(n) / 60.0
        runs = np.repeat(rng.normal(0, 1, (n, 7)), rng.integers(1, 20, n), axis=0)[:n].round(5)
        mask = bake.lossless_keep(runs[:, None, :])[:, 0]
        keep = np.flatnonzero(mask).tolist()
        assert keep[0] == 0 and keep[-1] == n - 1
        for a, b in zip(keep, keep[1:]):
            seg = runs[a:b + 1]
            if b - a > 1:
                assert np.array_equal(seg[1:-1], np.repeat(seg[:1], b - a - 1, axis=0)) and np.array_equal(seg[0], seg[-1])
    print("test_reduce: ok")


if __name__ == "__main__":
    main()
