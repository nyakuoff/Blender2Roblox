"""Headless check: blender -b FILE.blend --python blender_check.py

For every Roblox-rigged armature: bake, assert keys sit on whole frames, and
(with B2R_UPSTREAM set) diff poses against the original addon's serialize()
at the frames both export. Never saves the .blend.
"""

import importlib
import importlib.util
import os
import pathlib
import sys
import time

import bpy
import numpy as np

here = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("rbx_bake", here / "blender2roblox" / "bake.py")
bake = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bake)

# Optional: B2R_UPSTREAM=<dir containing the original roblox_animations package> to diff against it.
upstream = None
if os.environ.get("B2R_UPSTREAM"):
    sys.path.insert(0, os.environ["B2R_UPSTREAM"])
    upstream = importlib.import_module("roblox_animations.animation.serialization")


def quat_to_mat(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


scene = bpy.context.scene
fps = scene.render.fps / scene.render.fps_base
failed = False
for ao in [o for o in bpy.data.objects if o.type == "ARMATURE"]:
    if not (any(all(p in b for p in bake.MOTOR_PROPS) for b in ao.data.bones) or bake.is_skinned(ao)):
        continue
    t0 = time.perf_counter()
    dense = bake.bake(ao, exact=True)
    t_dense = time.perf_counter() - t0
    t0 = time.perf_counter()
    out = bake.bake(ao)
    t_red = time.perf_counter() - t0
    hidden_before = {o.name for o in bpy.data.objects if o.hide_viewport}
    same = bake.bake(ao, isolate=False) == out  # skipping unrelated objects must not change the pose
    restored = {o.name for o in bpy.data.objects if o.hide_viewport} == hidden_before

    frames = np.concatenate([np.asarray(b["t"]) for b in out["bones"].values()]) * fps
    off_grid = int(np.sum(np.abs(frames - np.round(frames)) > 1e-3))
    n_dense = sum(len(b["t"]) for b in dense["bones"].values())
    n_red = sum(len(b["t"]) for b in out["bones"].values())
    line = (f"{ao.name}: {len(out['bones'])} bones, {n_red}/{n_dense} keys kept, "
            f"bake {t_red:.2f}s (exact {t_dense:.2f}s), off-grid keys {off_grid}, "
            f"isolated == full scene: {same}, visibility restored: {restored}")
    failed |= not (same and restored)

    if upstream:
        t0 = time.perf_counter()
        up = upstream.serialize(ao)
        t_up = time.perf_counter() - t0
        up_sub, max_diff = 0, 0.0
        for kf in up["kfs"]:
            f = kf["t"] * fps
            if abs(f - round(f)) > 1e-3:
                up_sub += 1
                continue
            for bone, pose in kf["kf"].items():
                mine = dense["bones"].get(bone)
                if not mine:
                    continue
                # exact bake drops only repeats, so the last key at or before t is the pose at t
                # (+1e-4: payload times are rounded to 5 decimals)
                i = int(np.searchsorted(np.asarray(mine["t"]), kf["t"] + 1e-4, side="right")) - 1
                p = np.asarray(mine["p"]).reshape(-1, 7)[i]
                m = np.eye(4)
                m[:3, :3], m[:3, 3] = quat_to_mat(p[3:]), p[:3]
                c = np.asarray(pose[0])
                u = np.eye(4)
                u[:3, 3], u[:3, :3] = c[:3], c[3:].reshape(3, 3)
                u[:3, :3] /= np.linalg.norm(u[:3, :3], axis=0)
                max_diff = max(max_diff, float(np.abs(m - u).max()))
        line += f" | upstream {t_up:.2f}s, {len(up['kfs'])} keyframes, {up_sub} between frames, max pose diff {max_diff:.2e}"
        failed |= max_diff > 1e-3

    failed |= off_grid > 0
    print("CHECK", line, flush=True)


# --- Link round trip: rebuild a rig from stored Roblox data, POST it, GET animations over HTTP.
# At rest only the root may export a pose (a constant offset, same as the original
# addon; Roblox ignores it since the root part has no joint).
import json
import threading
import urllib.request

sys.path.insert(0, str(here))
import blender2roblox  # noqa: E402

registered_here = not hasattr(bpy.types.Scene, "blender2roblox_port")  # the extension may be installed already
if registered_here:
    blender2roblox.register()
arms = [o for o in bpy.data.objects if o.type == "ARMATURE" and o.name in blender2roblox.server.list_armatures()]
src = max(arms, key=lambda o: sum(all(p in b for p in bake.MOTOR_PROPS) for b in o.data.bones))
skinned = next((o for o in arms if bake.is_skinned(o)), None)


def node(b):
    rows = lambda key: bake._mat(b[key]).ravel().tolist()  # noqa: E731
    cf = lambda m: m[3:4] + m[7:8] + m[11:12] + m[0:3] + m[4:7] + m[8:11]  # noqa: E731 (rows -> CFrame order)
    n = {"jname": b.get("rbx_source_name", b.name), "transform": cf(rows("transform")), "size": [1, 2, 1],
         "children": [node(c) for c in b.children if all(p in c for p in bake.MOTOR_PROPS)]}
    if b.parent:
        n["jointtransform0"], n["jointtransform1"] = cf(rows("transform0")), cf(rows("transform1"))
    return n


root = max((b for b in src.data.bones if not b.parent and all(p in b for p in bake.MOTOR_PROPS)),
           key=lambda b: len(b.children_recursive))
rig_json = {"rigName": "RoundTrip", "rig": node(root)}
# A real mesh (tetrahedron with UVs) on the root part, plus a welded accessory using it.
tetra = {"id": "rbxassetid://1", "v": [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1], "f": [0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3],
         "u": [0, 0, 1, 0, 0, 1], "fu": [0, 1, 2] * 4}
rig_json["rig"].update(mesh="rbxassetid://1", meshScale=[2, 2, 2], meshOffset=[0, 1, 0])
rig_json["rig"]["aux"] = [{"jname": "RTHat", "transform": rig_json["rig"]["transform"], "mesh": "rbxassetid://1"}]
port = 31399
blender2roblox.server.start(port)
results = {}


def client():
    base = f"http://127.0.0.1:{port}"
    try:
        mreq = urllib.request.Request(f"{base}/mesh", json.dumps(tetra).encode(), {"Content-Type": "application/json"})
        results["mesh"] = json.load(urllib.request.urlopen(mreq))
        req = urllib.request.Request(f"{base}/rig", json.dumps(rig_json).encode(), {"Content-Type": "application/json"})
        results["rig"] = json.load(urllib.request.urlopen(req))
        results["arms"] = json.load(urllib.request.urlopen(f"{base}/armatures"))
        q = urllib.parse.quote(results["rig"])
        results["rest"] = json.load(urllib.request.urlopen(f"{base}/animation?name={q}"))
        results["src"] = json.load(urllib.request.urlopen(f"{base}/animation?name={urllib.parse.quote(src.name)}"))
        if skinned:  # Studio reports Bones twice as long -> translations must double
            rest2 = {k: 2 * v for k, v in bake.bone_rest_distances(skinned).items()}
            body = json.dumps({"name": skinned.name, "boneRest": rest2}).encode()
            results["skin1"] = json.load(urllib.request.urlopen(f"{base}/animation?name={urllib.parse.quote(skinned.name)}"))
            results["skin2"] = json.load(urllib.request.urlopen(
                urllib.request.Request(f"{base}/animation", body, {"Content-Type": "application/json"})))
    except Exception as e:
        results["error"] = repr(e)


th = threading.Thread(target=client)
th.start()
while th.is_alive():  # timers don't tick inside a --python script; pump the job queue by hand
    blender2roblox.server._run_jobs()
    th.join(0.01)
blender2roblox.server.stop()

ok = ("error" not in results and results["rig"] in results["arms"] and set(results["rest"]["bones"]) <= {root.get("rbx_source_name", root.name)}
      and results["src"]["bones"].keys() == bake.bake(src)["bones"].keys())
if skinned and "skin1" in results:
    scaled = []
    for name, b1 in results["skin1"]["bones"].items():
        b2 = results["skin2"]["bones"].get(name)
        if b2 and b1["t"] == b2["t"]:
            p1, p2 = np.reshape(b1["p"], (-1, 7)), np.reshape(b2["p"], (-1, 7))
            scaled.append(np.allclose(p1[:, :3] * 2, p2[:, :3], atol=2e-5) and np.allclose(p1[:, 3:], p2[:, 3:], atol=2e-5))
    ok &= bool(scaled) and all(scaled)
    print("CHECK Bone scale calibration:", skinned.name, f"{sum(scaled)}/{len(scaled)} bones doubled", flush=True)
new = bpy.data.objects.get(results.get("rig", ""))
hat = bpy.data.objects.get("RTHat")
root_obj = next((o for o in bpy.data.objects if o.parent == new and o.parent_bone == root.name), None)
ok &= (results.get("mesh") == 4 and hat is not None and len(hat.data.polygons) == 4 and len(hat.data.uv_layers) == 1
       and root_obj is not None and len(root_obj.data.vertices) == 4
       and abs(max(v.co.length for v in root_obj.data.vertices) - 3) < 1e-4)  # (0,1,0)*2 + (0,1,0)
if new:
    for b in new.data.bones:
        o = src.data.bones.get(b.name) or next((x for x in src.data.bones if x.get("rbx_source_name") == b.name), None)
        if o is not None:
            for key in ("transform", "transform0", "transform1"):
                ok &= bool(np.allclose(bake._mat(b[key]), bake._mat(o[key]), atol=1e-5))
print("CHECK link round trip:", "ok" if ok else f"FAILED {results.get('error', '')}",
      f"({len(new.data.bones) if new else 0} bones rebuilt from {src.name})")
failed |= not ok
if registered_here:
    blender2roblox.unregister()
print("CHECK", "FAILED" if failed else "ok")
