# Blender2Roblox

A fast, frame-exact Blender → Roblox animation link: a lean rewrite of the animation core of
[Cautioned/Blender-Animations-Plugin](https://github.com/Cautioned/Blender-Animations-Plugin)
(GPL-3.0, so this is GPL-3.0 too). It works with armatures rigged by that addon.

## Install

1. **Blender (4.2+):** build the extension zip, then *Edit → Preferences → Get Extensions → Install from Disk*:
   ```bash
   mkdir -p dist && blender --command extension build --source-dir "$PWD/blender_addon/rbx_link" --output-dir "$PWD/dist"
   ```
   (Absolute paths are needed because Flatpak Blender runs in its own working directory.)
2. **Roblox Studio:** *Plugins tab → Plugins Folder*, then copy `roblox_plugin/BlenderLink.server.lua` into it and restart Studio.

## Use

1. Blender: open the N panel, go to **Roblox**, and click **Start Link** (port 31337).
2. Studio: the **Blender Link** panel docks on the left. Select your rig model in the Explorer (select several to import onto each one), then click **Refresh**.
3. Click an armature to import it. The progress bar follows the Blender bake and the keyframe build. Results are saved under `ServerStorage/BlenderLink/`.
4. Preview with **Play/Pause**, **Stop** and **Loop**, or drag the timeline to scrub. Every control works at any time, including mid-loop.
5. **Publish to Roblox** uploads the selected rig's animation.
6. **Send rig to Blender** builds an armature with the rig's real meshes (MeshParts and FileMesh SpecialMeshes, with UVs) and its welded accessories. A mesh you don't own (and Roblox doesn't either) can't be read and arrives as a box.

### Skinned meshes (Roblox Bones)

Armatures that skin a mesh (an Armature modifier, e.g. a coat, hair or cape) are listed too. Their bones export as Roblox **Bone** poses, nested under the MeshPart that holds the Bones. Import onto the model that contains that MeshPart.
- Bone names must match between Blender and Studio. FBX import keeps them.
- If Studio imported the mesh at a different scale, the plugin sends Studio's bone lengths and Blender rescales translations to match.

### Armatures with several rigs

One armature can hold several Roblox rigs (an R15 body, an R6 body, a prop) under separate root bones. Bones are matched to parts by name **and** parent, so each Studio rig only takes its own bones. The status lists Studio joints with no bone (worth checking) separately from bones that belong to the armature's other rigs (normal).

## How it exports

- One sample per scene frame (`frame_start..frame_end`, `frame_step`), never between frames.
- Keys are then thinned, but only where the result stays within 0.001 studs and 0.1°. Tick **Exact** to keep every frame.
- Bones whose channels are all CONSTANT export with Roblox Constant easing, so stepped animation stays stepped.

## Checks

```bash
python3 blender_addon/tests/test_reduce.py
```
```bash
blender -b your_file.blend --python "$PWD/blender_addon/tests/blender_check.py"
```
```bash
cd roblox_plugin && sed -n '/BEGIN matchBones/,/END matchBones/p' BlenderLink.server.lua | cat - tests/match_test.luau > /tmp/m.luau && luau /tmp/m.luau
```

To also diff against the original addon, set `B2R_UPSTREAM` to a folder containing its `roblox_animations` package.

## Credits & license

This is a from-scratch rewrite, not a fork. It ports these pieces from
[Cautioned/Blender-Animations-Plugin](https://github.com/Cautioned/Blender-Animations-Plugin)
(by Cautioned, based on Den_S's original Blender rig exporter / animation importer):
- the Motor6D and Bone pose math;
- the rig-building core (`load_rigbone`);
- the bone-length scale calibration.

Those are GPL-3.0, so this project is GPL-3.0 too (see `LICENSE`). Per that license, don't re-upload it as a paid plugin.
