# Blender2Roblox

Send animations from Blender to Roblox Studio: fast, frame-exact, lightweight.

It works with armatures rigged by the original [Blender Animations Plugin](https://github.com/Cautioned/Blender-Animations-Plugin), and with skinned meshes (Roblox Bones).

## Install

1. **Blender (4.2+):** download `blender2roblox-*.zip` from Releases (or build it, below), then go to *Edit → Preferences → Get Extensions → ⌄ → Install from Disk*.
2. **Roblox Studio:** ...

Build the Blender zip yourself:
```bash
mkdir -p dist && blender --command extension build --source-dir "$PWD/blender_addon/blender2roblox" --output-dir "$PWD/dist"
```

## Quick start

1. In Blender, press **N** → **Blender2Roblox** tab → **Start Link**.
2. In Studio, select your rig in the Explorer → **Refresh** → click the armature to import it.

## Blender panel

| Setting | What it does |
|---|---|
| **Port** | Port the link listens on (default 31337). Must match the port in Studio. |
| **Start / Stop Link** | Starts or stops the local connection to Studio. It only listens on your own machine. |
| **Exact (every frame)** | **Off (Default):** Keeps only the keys needed to stay within 0.001 studs / 0.1° of Blender, so files are smaller and look the same.<br>**On:** One key on every frame. |
| **New rig bones** | How bones are shaped when Studio sends a rig. *Nodes only* points along each joint (original default); *Local axis aligned* points bones toward their child joint, which is nicer for posing. |

## Studio panel

| Section | What it does |
|---|---|
| **Blender connection** | Port box and **Refresh**. Refresh lists the armatures in the open .blend. |
| **Target rig** | The rig(s) selected in the Explorer. Select several to import onto each one at once (e.g. a character and its prop). |
| **Blender armatures** | Click one to import it onto the target rig(s). |
| **Progress** | Follows the Blender bake (frame by frame), then the keyframe build. |
| **Preview** | Timeline (drag to scrub), **Play / Pause**, **Stop** (always stops and resets the rig, even mid-loop), **Loop** (applies right away). |
| **Rig & publish** | **Publish to Roblox** uploads the selected rig's animation. **Send rig to Blender** builds an armature from the selected rig, with its real meshes, UVs and welded accessories. |

Imported animations are saved in `ServerStorage/Blender2Roblox/`.

**Status messages after an import:**
- *No Blender bone for: …* lists Studio joints that got no animation. Check the bone names.
- *N bones belong to other rigs in this armature* is normal when one armature holds several rigs (e.g. R15 + R6); those bones are ignored.

## How it works

- **Every frame, never between frames.** Blender samples each scene frame (`frame_start..frame_end`, using `frame_step`) once.
- **Stepped animation stays stepped.** Bones whose curves are all *Constant* export with Roblox *Constant* easing.
- **Bones are matched by name and parent,** so an armature with several rigs (R15 + R6 + props) puts each bone on the right part.
- **Skinned meshes** (an Armature modifier on a coat, for example…) export as Roblox **Bone** poses. Import onto the model containing that MeshPart. Bone names must match; if the mesh was imported at a different size, Studio sends its bone lengths and translations are rescaled to match.
- **Send rig** reads meshes with Roblox's EditableMesh. That only works for meshes you or Roblox own; any others come through as boxes.

## Credits & license

This is a from-scratch rewrite, not a fork. It ports these pieces from [Cautioned/Blender-Animations-Plugin](https://github.com/Cautioned/Blender-Animations-Plugin), which is by Cautioned and based on Den_S's original exporter:
- the Motor6D and Bone pose math;
- the rig-building core;
- the bone-length scale calibration.

This project therefore inherits the **GPL-3.0** license. (see `LICENSE`).