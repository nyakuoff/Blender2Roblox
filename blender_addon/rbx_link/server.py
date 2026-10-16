"""Localhost HTTP link for the Roblox Studio plugin.

Requests arrive on a worker thread; bpy is not thread-safe, so each request
queues a job that a bpy.app.timers callback runs on Blender's main thread.
"""

import json
import queue
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

import bpy

from .bake import MOTOR_PROPS, bake, is_skinned
from .rig import MESHES, build_rig

_jobs = queue.Queue()
_server = None
_progress = {"done": 0, "total": 0}  # read by GET /progress without the main thread


def _run_jobs():
    while not _jobs.empty():
        fn, box, done = _jobs.get()
        try:
            box["ok"] = fn()
        except Exception as e:  # reported back to Studio as a 500
            box["err"] = f"{type(e).__name__}: {e}"
        done.set()
    return 0.05


def _on_main(fn, timeout=300):
    box, done = {}, threading.Event()
    _jobs.put((fn, box, done))
    if not done.wait(timeout):
        raise TimeoutError("Blender did not respond (busy or a modal dialog is open)")
    if "err" in box:
        raise RuntimeError(box["err"])
    return box["ok"]


def list_armatures():
    """Roblox-rigged armatures (Motor6D bones) and armatures that skin a mesh (Roblox Bones)."""
    return [o.name for o in bpy.data.objects if o.type == "ARMATURE" and (
        any(all(p in b for p in MOTOR_PROPS) for b in o.data.bones) or is_skinned(o))]


def export_animation(name, bone_rest=None):
    ao = bpy.data.objects.get(name)
    if ao is None or ao.type != "ARMATURE":
        raise ValueError(f"No armature named '{name}'")
    if ao.mode == "EDIT":
        raise ValueError(f"'{name}' is in Edit Mode; switch to Pose or Object Mode")

    def report(done, total):
        _progress["done"], _progress["total"] = done, total

    try:
        return bake(ao, exact=bpy.context.scene.rbx_link_exact, progress=report, bone_rest=bone_rest)
    finally:
        _progress["done"] = _progress["total"]


class _Handler(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        body = json.dumps(obj, separators=(",", ":")).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _handle(self, fn):
        try:
            self._send(200, _on_main(fn))
        except Exception as e:
            self._send(500, {"error": str(e)})

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/progress":
            self._send(200, _progress)
        elif url.path == "/armatures":
            self._handle(list_armatures)
        elif url.path == "/animation":
            name = parse_qs(url.query).get("name", [""])[0]
            self._handle(lambda: export_animation(name))
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        path = urlparse(self.path).path
        try:
            data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
            if path == "/mesh" and not (isinstance(data, dict) and isinstance(data.get("id"), str)
                                        and isinstance(data.get("v"), list) and isinstance(data.get("f"), list)):
                raise ValueError("expected {id, v, f, u?, fu?}")
            if path == "/rig" and not (isinstance(data, dict) and isinstance(data.get("rig"), dict)):
                raise ValueError("expected {rigName, rig}")
            if path == "/animation" and not (isinstance(data, dict) and isinstance(data.get("name"), str)
                                             and isinstance(data.get("boneRest", {}), dict)):
                raise ValueError("expected {name, boneRest?}")
        except ValueError as e:
            return self._send(400, {"error": f"bad JSON: {e}"})
        if path == "/mesh":  # plain data, no bpy: store it for the next /rig
            MESHES[data["id"]] = data
            self._send(200, len(data["f"]) // 3)
        elif path == "/rig":
            self._handle(lambda: build_rig(data, bpy.context.scene.rbx_link_rig_mode).name)
        elif path == "/animation":  # POST form carries Studio's Bone rest lengths for scale calibration
            self._handle(lambda: export_animation(data["name"], data.get("boneRest")))
        else:
            self._send(404, {"error": "not found"})

    def log_message(self, *args):
        pass


def start(port):
    global _server
    stop()
    _server = ThreadingHTTPServer(("127.0.0.1", port), _Handler)  # localhost only
    threading.Thread(target=_server.serve_forever, daemon=True).start()
    if not bpy.app.timers.is_registered(_run_jobs):
        bpy.app.timers.register(_run_jobs, persistent=True)


def stop():
    global _server
    if _server:
        _server.shutdown()
        _server.server_close()
        _server = None
    if bpy.app.timers.is_registered(_run_jobs):
        bpy.app.timers.unregister(_run_jobs)


def running():
    return _server is not None
