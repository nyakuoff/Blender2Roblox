import bpy

from . import server


class RBXLINK_OT_toggle(bpy.types.Operator):
    bl_idname = "rbx_link.toggle"
    bl_label = "Start/Stop Link"
    bl_description = "Start or stop the localhost server the Roblox plugin connects to"

    def execute(self, context):
        if server.running():
            server.stop()
        else:
            try:
                server.start(context.scene.rbx_link_port)
            except OSError as e:
                self.report({"ERROR"}, f"Port {context.scene.rbx_link_port}: {e}")
                return {"CANCELLED"}
        return {"FINISHED"}


class RBXLINK_PT_panel(bpy.types.Panel):
    bl_label = "Roblox Link"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "Roblox"

    def draw(self, context):
        col = self.layout.column()
        col.prop(context.scene, "rbx_link_port")
        on = server.running()
        col.operator("rbx_link.toggle", text="Stop Link" if on else "Start Link",
                     icon="CANCEL" if on else "PLAY", depress=on)
        col.label(text=f"Listening on 127.0.0.1:{context.scene.rbx_link_port}" if on else "Not running")
        col.separator()
        col.prop(context.scene, "rbx_link_exact")
        col.prop(context.scene, "rbx_link_rig_mode")


def register():
    bpy.types.Scene.rbx_link_port = bpy.props.IntProperty(name="Port", default=31337, min=1024, max=65535)
    bpy.types.Scene.rbx_link_exact = bpy.props.BoolProperty(
        name="Exact (every frame)", description="Export a key on every frame instead of only the ones needed")
    bpy.types.Scene.rbx_link_rig_mode = bpy.props.EnumProperty(
        name="New rig bones",
        items=[("RAW", "Nodes only", "Bones point along the joint (original default)"),
               ("LOCAL_AXIS_EXTEND", "Local axis aligned", "Bones reach toward their child joint")])
    bpy.utils.register_class(RBXLINK_OT_toggle)
    bpy.utils.register_class(RBXLINK_PT_panel)


def unregister():
    server.stop()
    bpy.utils.unregister_class(RBXLINK_PT_panel)
    bpy.utils.unregister_class(RBXLINK_OT_toggle)
    del bpy.types.Scene.rbx_link_port, bpy.types.Scene.rbx_link_exact, bpy.types.Scene.rbx_link_rig_mode
