-- Bone matching check, no Studio needed. Run from roblox_plugin/:
--   sed -n '/BEGIN matchBones/,/END matchBones/p' BlenderLink.server.lua | cat - tests/match_test.luau > /tmp/m.luau && luau /tmp/m.luau
-- Fixtures were generated from the user's test files with rbx_link.bake.
-- RIG is the real rig map of a combo armature ("User" in Off Ball Awk Isagi Ego Ball.blend):
-- an R15 body, an R6 body and a ball model under three roots in one armature.

local RIG = {
	["AccessoryMeshPart"] = { "HumanoidRootPart.002", "AccessoryMeshPart" },
	["AccessoryMeshPart1"] = { "HumanoidRootPart.002", "AccessoryMeshPart1" },
	["AccessoryMeshescrown3Accessory"] = { "HumanoidRootPart.002", "AccessoryMeshescrown3Accessory" },
	["AccessoryYellowEyesSeriousFace"] = { "HumanoidRootPart.002", "AccessoryYellowEyesSeriousFace" },
	["Head"] = { "UpperTorso", "" },
	["Head.001"] = { "Torso", "" },
	["HumanoidRootPart"] = { "", "" },
	["HumanoidRootPart.001"] = { "", "" },
	["HumanoidRootPart.002"] = { "", "HumanoidRootPart" },
	["Left Arm"] = { "Torso", "" },
	["Left Arm.001"] = { "LeftLowerArm", "" },
	["Left Leg"] = { "Torso", "" },
	["Left Leg.001"] = { "LeftLowerLeg", "" },
	["LeftFoot"] = { "LeftLowerLeg", "" },
	["LeftHand"] = { "LeftLowerArm", "" },
	["LeftLowerArm"] = { "LeftUpperArm", "" },
	["LeftLowerLeg"] = { "LeftUpperLeg", "" },
	["LeftUpperArm"] = { "UpperTorso", "" },
	["LeftUpperLeg"] = { "LowerTorso", "" },
	["LowerTorso"] = { "HumanoidRootPart", "" },
	["Meshes/LowPoly-Ball"] = { "HumanoidRootPart.002", "Meshes/LowPoly-Ball" },
	["Right Arm"] = { "Torso", "" },
	["Right Arm.001"] = { "RightLowerArm", "" },
	["Right Leg"] = { "Torso", "" },
	["Right Leg.001"] = { "RightLowerLeg", "" },
	["RightFoot"] = { "RightLowerLeg", "" },
	["RightHand"] = { "RightLowerArm", "" },
	["RightLowerArm"] = { "RightUpperArm", "" },
	["RightLowerLeg"] = { "RightUpperLeg", "" },
	["RightUpperArm"] = { "UpperTorso", "" },
	["RightUpperLeg"] = { "LowerTorso", "" },
	["Torso"] = { "HumanoidRootPart.001", "" },
	["UpperTorso"] = { "LowerTorso", "" },
}

-- COAT is the real rig map of a skinned coat armature ("Coat" in Cid Atomic.blend):
-- plain Blender bones that become Roblox Bones inside the coat MeshPart.
local COAT = {
	["Bone.001.L"] = { "Bone.L", "Bone.001.L", "B" },
	["Bone.001.R"] = { "Bone.R", "Bone.001.R", "B" },
	["Bone.002.L"] = { "Bone.001.L", "Bone.002.L", "B" },
	["Bone.002.R"] = { "Bone.001.R", "Bone.002.R", "B" },
	["Bone.003"] = { "Main", "Bone.003", "B" },
	["Bone.004"] = { "Bone.003", "Bone.004", "B" },
	["Bone.005"] = { "Bone.004", "Bone.005", "B" },
	["Bone.006.L"] = { "Main", "Bone.006.L", "B" },
	["Bone.006.R"] = { "Main", "Bone.006.R", "B" },
	["Bone.007.L"] = { "Bone.006.L", "Bone.007.L", "B" },
	["Bone.007.R"] = { "Bone.006.R", "Bone.007.R", "B" },
	["Bone.008.L"] = { "Bone.007.L", "Bone.008.L", "B" },
	["Bone.008.R"] = { "Bone.007.R", "Bone.008.R", "B" },
	["Bone.L"] = { "Main", "Bone.L", "B" },
	["Bone.R"] = { "Main", "Bone.R", "B" },
	["Main"] = { "", "Main", "B" },
	["Main.002.L"] = { "Main", "Main.002.L", "B" },
	["Main.002.L.001"] = { "Main", "Main.002.L.001", "B" },
	["Main.002.R"] = { "Main", "Main.002.R", "B" },
	["Main.002.R.001"] = { "Main", "Main.002.R.001", "B" },
	["Main.003.L"] = { "Main", "Main.003.L", "B" },
	["Main.003.L.001"] = { "Main", "Main.003.L.001", "B" },
	["Main.003.R"] = { "Main", "Main.003.R", "B" },
	["Main.003.R.001"] = { "Main", "Main.003.R.001", "B" },
	["Main.004.L"] = { "Main", "Main.004.L", "B" },
	["Main.004.L.001"] = { "Main", "Main.004.L.001", "B" },
	["Main.004.R"] = { "Main", "Main.004.R", "B" },
	["Main.004.R.001"] = { "Main", "Main.004.R.001", "B" },
	["Main.005"] = { "Main", "Main.005", "B" },
	["Main.005.L"] = { "Main", "Main.005.L", "B" },
	["Main.005.R"] = { "Main", "Main.005.R", "B" },
	["Main.006.L"] = { "Main", "Main.006.L", "B" },
	["Main.006.R"] = { "Main", "Main.006.R", "B" },
	["Main.007.L"] = { "Main", "Main.007.L", "B" },
	["Main.007.R"] = { "Main", "Main.007.R", "B" },
	["Main.009.L"] = { "Main", "Main.009.L", "B" },
	["Main.009.R"] = { "Main", "Main.009.R", "B" },
	["Main.010.L"] = { "Main", "Main.010.L", "B" },
	["Main.010.R"] = { "Main", "Main.010.R", "B" },
	["Main.011"] = { "Main", "Main.011", "B" },
	["Main.012.L"] = { "Main", "Main.012.L", "B" },
	["Main.012.R"] = { "Main", "Main.012.R", "B" },
	["Main.013.L"] = { "Main.002.L", "Main.013.L", "B" },
	["Main.013.L.001"] = { "Main", "Main.013.L.001", "B" },
	["Main.013.R"] = { "Main.002.R", "Main.013.R", "B" },
	["Main.013.R.001"] = { "Main", "Main.013.R.001", "B" },
	["Main.014.L"] = { "Main.013.L", "Main.014.L", "B" },
	["Main.014.R"] = { "Main.013.R", "Main.014.R", "B" },
	["Main.015.L"] = { "Main", "Main.015.L", "B" },
	["Main.015.L.001"] = { "Main.015.L", "Main.015.L.001", "B" },
	["Main.015.R"] = { "Main", "Main.015.R", "B" },
	["Main.015.R.001"] = { "Main.015.R", "Main.015.R.001", "B" },
	["Main.016.L"] = { "Main.015.L.001", "Main.016.L", "B" },
	["Main.016.R"] = { "Main.015.R.001", "Main.016.R", "B" },
	["Main.017.L"] = { "Main.016.L", "Main.017.L", "B" },
	["Main.017.R"] = { "Main.016.R", "Main.017.R", "B" },
	["Main.018.L"] = { "Main", "Main.018.L", "B" },
	["Main.018.R"] = { "Main", "Main.018.R", "B" },
	["Main.019.L"] = { "Main.016.L", "Main.019.L", "B" },
	["Main.019.R"] = { "Main.016.R", "Main.019.R", "B" },
	["Main.020.L"] = { "Main.019.L", "Main.020.L", "B" },
	["Main.020.R"] = { "Main.019.R", "Main.020.R", "B" },
	["Main.021.L"] = { "Main.020.L", "Main.021.L", "B" },
	["Main.021.R"] = { "Main.020.R", "Main.021.R", "B" },
	["Main.022.L"] = { "Main.021.L", "Main.022.L", "B" },
	["Main.022.R"] = { "Main.021.R", "Main.022.R", "B" },
	["Main.023.L"] = { "Main.018.L", "Main.023.L", "B" },
	["Main.023.R"] = { "Main.018.R", "Main.023.R", "B" },
	["Main.024.L"] = { "Main.023.L", "Main.024.L", "B" },
	["Main.024.R"] = { "Main.023.R", "Main.024.R", "B" },
	["Main.025"] = { "Main", "Main.025", "B" },
	["Main.026"] = { "Main.025", "Main.026", "B" },
	["Main.027"] = { "Main.026", "Main.027", "B" },
	["Main.028"] = { "Main.027", "Main.028", "B" },
	["Main.029.L"] = { "Main", "Main.029.L", "B" },
	["Main.029.R"] = { "Main", "Main.029.R", "B" },
	["Main.030.L"] = { "Main", "Main.030.L", "B" },
	["Main.030.R"] = { "Main", "Main.030.R", "B" },
	["Main.031.L"] = { "Main", "Main.031.L", "B" },
	["Main.031.R"] = { "Main", "Main.031.R", "B" },
	["Main.032.L"] = { "Main", "Main.032.L", "B" },
	["Main.032.R"] = { "Main", "Main.032.R", "B" },
	["Main.033.L"] = { "Main", "Main.033.L", "B" },
	["Main.033.R"] = { "Main", "Main.033.R", "B" },
	["Main.034.L"] = { "Main", "Main.034.L", "B" },
	["Main.034.R"] = { "Main", "Main.034.R", "B" },
	["Main.035.L"] = { "Main", "Main.035.L", "B" },
	["Main.035.R"] = { "Main", "Main.035.R", "B" },
}

-- Mock Studio rig: nodes are {Name = ...}; tree = {child, parent, isBone?} (parent nil = root).
local function studioRig(tree)
	local byName, parentOf, parts, isBone = {}, {}, {}, {}
	local function part(name)
		if not parts[name] then
			parts[name] = { Name = name }
			byName[name] = byName[name] or {}
			table.insert(byName[name], parts[name])
		end
		return parts[name]
	end
	for _, pair in tree do
		local child = part(pair[1])
		if pair[2] then
			parentOf[child] = part(pair[2])
		end
		isBone[child] = pair[3] == true
	end
	return byName, parentOf, isBone
end

local function boneFor(assigned, partName)
	for key, part in assigned do
		if part.Name == partName then
			return key
		end
	end
	return nil
end

local function expect(assigned, partName, bone)
	local got = boneFor(assigned, partName)
	assert(got == bone, `{partName}: expected bone {bone}, got {got}`)
end

-- R6 rig in Studio: Head must come from the R6 "Head.001" bone, not the R15 "Head".
local r6, r6Parents = studioRig({
	{ "HumanoidRootPart" }, { "Torso", "HumanoidRootPart" }, { "Head", "Torso" },
	{ "Left Arm", "Torso" }, { "Right Arm", "Torso" }, { "Left Leg", "Torso" }, { "Right Leg", "Torso" },
})
local assigned = matchBones(RIG, r6, r6Parents)
expect(assigned, "Torso", "Torso")
expect(assigned, "Head", "Head.001")
expect(assigned, "Left Arm", "Left Arm")
expect(assigned, "Right Leg", "Right Leg")

-- R15 rig in Studio: Head comes from the R15 "Head" bone.
local r15, r15Parents = studioRig({
	{ "HumanoidRootPart" }, { "LowerTorso", "HumanoidRootPart" }, { "UpperTorso", "LowerTorso" },
	{ "Head", "UpperTorso" }, { "LeftUpperArm", "UpperTorso" }, { "LeftLowerArm", "LeftUpperArm" },
	{ "LeftHand", "LeftLowerArm" }, { "RightUpperLeg", "LowerTorso" }, { "RightLowerLeg", "RightUpperLeg" },
	{ "RightFoot", "RightLowerLeg" },
})
assigned = matchBones(RIG, r15, r15Parents)
expect(assigned, "Head", "Head")
expect(assigned, "UpperTorso", "UpperTorso")
expect(assigned, "LeftHand", "LeftHand")
expect(assigned, "RightFoot", "RightFoot")

-- Ball model in Studio: its own HumanoidRootPart root with the ball under it.
local ball, ballParents = studioRig({ { "HumanoidRootPart" }, { "Meshes/LowPoly-Ball", "HumanoidRootPart" } })
assigned = matchBones(RIG, ball, ballParents)
expect(assigned, "Meshes/LowPoly-Ball", "Meshes/LowPoly-Ball")

-- Skinned coat in Studio: a MeshPart holding Bones. The root Bone's parent is the
-- part (not a Bone), and a stray Studio Bone "Bone" must not be taken by "Bone.004".
local coat, coatParents, coatBones = studioRig({
	{ "SHADOW TORSO" }, { "Main", "SHADOW TORSO", true }, { "Bone.R", "Main", true },
	{ "Bone.001.R", "Bone.R", true }, { "Bone.003", "Main", true }, { "Bone", "Main", true },
})
assigned = matchBones(COAT, coat, coatParents, coatBones)
expect(assigned, "Main", "Main")
expect(assigned, "Bone.R", "Bone.R")
expect(assigned, "Bone.001.R", "Bone.001.R")
expect(assigned, "Bone.003", "Bone.003")
expect(assigned, "Bone", nil)

print("match_test: ok")
