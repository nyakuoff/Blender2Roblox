--!nonstrict
-- Blender2Roblox: import Blender animations into Roblox Studio over a localhost link.
-- Install: copy this file into your Studio Plugins folder. Pair: blender_addon/blender2roblox.

local AnimationClipProvider = game:GetService("AnimationClipProvider")
local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")
local Studio = settings().Studio
local C = Enum.StudioStyleGuideColor

---------------------------------------------------------------------------
-- Bone matching (pure; tests/match_test.luau loads the block between markers)
---------------------------------------------------------------------------
-- BEGIN matchBones
local function stripSuffix(name: string): string
	return (string.gsub(name, "%.%d%d%d$", ""))
end

-- rig: {[bone] = {parentBone or "", robloxName or "", "M"|"B"}} for every bone in the armature.
-- byName: name -> nodes (parts and Bones); parentOf: node -> parent node; isBone: set of Bones.
-- Passes 1-2 also require the parent to match, so a bone from another rig in the same
-- armature (R15 "Head" vs R6 "Head.001") can't take a part; passes 3-4 match on name alone.
local function matchBones(rig, byName, parentOf, isBone)
	isBone = isBone or {}
	local keys = {}
	for key in rig do
		table.insert(keys, key)
	end
	table.sort(keys)
	local function robloxName(key)
		local entry = rig[key]
		return if entry and entry[2] ~= "" then entry[2] else key
	end
	local function parentMatches(key, part)
		local parentKey, parentPart = rig[key][1], parentOf[part]
		if parentKey == "" then -- a root bone: rig root part, or a root Bone inside its mesh part
			return parentPart == nil or (isBone[part] and not isBone[parentPart])
		end
		local wanted = robloxName(parentKey)
		return parentPart ~= nil and (parentPart.Name == wanted or parentPart.Name == stripSuffix(wanted))
	end
	local assigned, claimed = {}, {}
	for pass = 1, 4 do
		for _, key in keys do
			if assigned[key] then
				continue
			end
			-- ".001" suffixes come from Blender deduping Roblox part names (Motor6D bones);
			-- Bone names reach Studio verbatim, so they never get suffix-stripped.
			if pass % 2 == 0 and rig[key][3] == "B" then
				continue
			end
			local name = if pass % 2 == 0 then stripSuffix(robloxName(key)) else robloxName(key)
			for _, part in byName[name] or {} do
				if not claimed[part] and (pass > 2 or parentMatches(key, part)) then
					assigned[key], claimed[part] = part, true
					break
				end
			end
		end
	end
	return assigned, claimed
end
-- END matchBones

---------------------------------------------------------------------------
-- UI kit (Studio-themed, re-colored on theme change)
---------------------------------------------------------------------------
local themed = {} -- inst -> prop -> {color, modifier}
local function paint(inst, prop, color, modifier)
	themed[inst] = themed[inst] or {}
	themed[inst][prop] = { color, modifier }
	inst[prop] = Studio.Theme:GetColor(color, modifier)
end
Studio.ThemeChanged:Connect(function()
	for inst, props in themed do
		for prop, c in props do
			inst[prop] = Studio.Theme:GetColor(c[1], c[2])
		end
	end
end)

local function new(class, props, children)
	local inst = Instance.new(class)
	for k, v in props do
		inst[k] = v
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	return inst
end

local order = 0
local function nextOrder()
	order += 1
	return order
end

local function rounded(inst, radius)
	new("UICorner", { CornerRadius = UDim.new(0, radius or 4), Parent = inst })
	return inst
end

local widget = plugin:CreateDockWidgetPluginGuiAsync(
	"Blender2RobloxPanel", -- new id so the left-dock default applies even if the old panel was floated
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Left, true, false, 300, 600, 260, 320)
)
widget.Title = "Blender2Roblox"
widget.Name = "Blender2Roblox"
local toolbar = plugin:CreateToolbar("Blender2Roblox")
local toggleButton = toolbar:CreateButton("Blender2Roblox", "Show the Blender2Roblox panel", "rbxasset://textures/AnimationEditor/icon_checkmark.png")
toggleButton.ClickableWhenViewportHidden = true
toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

local root = new("ScrollingFrame", {
	Size = UDim2.fromScale(1, 1),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
	BorderSizePixel = 0,
	Parent = widget,
}, {
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }),
	new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
})
paint(root, "BackgroundColor3", C.MainBackground)
paint(root, "ScrollBarImageColor3", C.ScrollBar)

local function text(parent, str, props)
	local l = new("TextLabel", {
		Text = str,
		BackgroundTransparency = 1,
		Font = Enum.Font.SourceSans,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromScale(1, 0),
		LayoutOrder = nextOrder(),
		Parent = parent,
	})
	for k, v in props or {} do
		l[k] = v
	end
	paint(l, "TextColor3", C.MainText)
	return l
end

local function section(title)
	local frame = new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = nextOrder(),
		Parent = root,
	}, { new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local head = text(frame, string.upper(title), { Font = Enum.Font.SourceSansBold, TextSize = 12 })
	paint(head, "TextColor3", C.DimmedText)
	return frame
end

local function button(parent, label, onClick, primary)
	local b = rounded(new("TextButton", {
		Text = label,
		Font = Enum.Font.SourceSansSemibold,
		TextSize = 14,
		Size = UDim2.new(1, 0, 0, 28),
		AutoButtonColor = true,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(),
		Parent = parent,
	}))
	paint(b, "BackgroundColor3", if primary then C.DialogMainButton else C.Button)
	paint(b, "TextColor3", if primary then C.DialogMainButtonText else C.ButtonText)
	b.Activated:Connect(onClick)
	return b
end

-- Horizontal row of equal-width buttons.
local function buttonRow(parent, specs)
	local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = nextOrder(), Parent = parent }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local out = {}
	local gap = 6 * (#specs - 1) / #specs
	for i, spec in specs do
		local b = button(row, spec[1], spec[2], spec[3])
		b.Size = UDim2.new(1 / #specs, -gap, 1, 0)
		out[i] = b
	end
	return table.unpack(out)
end

local function bar(parent, height)
	local track = rounded(new("Frame", { Size = UDim2.new(1, 0, 0, height), BorderSizePixel = 0, LayoutOrder = nextOrder(), Parent = parent }), height // 2)
	paint(track, "BackgroundColor3", C.InputFieldBackground)
	local fill = rounded(new("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, Parent = track }), height // 2)
	paint(fill, "BackgroundColor3", C.DialogMainButton)
	return track, fill
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
-- Connection
local connSection = section("Blender connection")
local connRow = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = nextOrder(), Parent = connSection }, {
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }),
})
local portBox = rounded(new("TextBox", {
	Text = tostring(plugin:GetSetting("port") or 31337),
	PlaceholderText = "Port",
	Font = Enum.Font.SourceSans,
	TextSize = 14,
	ClearTextOnFocus = false,
	Size = UDim2.new(0, 64, 1, 0),
	BorderSizePixel = 0,
	LayoutOrder = 1,
	Parent = connRow,
}))
paint(portBox, "BackgroundColor3", C.InputFieldBackground)
paint(portBox, "TextColor3", C.MainText)
local refreshButton = button(connRow, "Refresh", function() end)
refreshButton.Size = UDim2.new(1, -70, 1, 0)
refreshButton.LayoutOrder = 2
local connStatus = text(connSection, "Not connected. Start the link in Blender (N panel > Blender2Roblox).")
paint(connStatus, "TextColor3", C.DimmedText)

-- Target rig(s)
local targetSection = section("Target rig")
local targetLabel = text(targetSection, "")

-- Armatures
local armSection = section("Blender armatures")
local armList = new("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	LayoutOrder = nextOrder(),
	Parent = armSection,
}, { new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })

-- Progress
local progSection = section("Progress")
local _, progFill = bar(progSection, 8)
local progLabel = text(progSection, "Idle")
paint(progLabel, "TextColor3", C.DimmedText)

-- Preview
local previewSection = section("Preview")
local timeline, timeFill = bar(previewSection, 14)
local playhead = new("Frame", { Size = UDim2.new(0, 2, 1, 4), Position = UDim2.fromOffset(0, -2), BorderSizePixel = 0, Parent = timeline })
paint(playhead, "BackgroundColor3", C.MainText)
local timeLabel = text(previewSection, "0.00 / 0.00 s", { TextXAlignment = Enum.TextXAlignment.Center })
local playButton, loopButton -- assigned below once handlers exist

-- Output
local outSection = section("Rig & publish")
local logLabel -- assigned below

---------------------------------------------------------------------------
-- Status helpers
---------------------------------------------------------------------------
local function setProgress(frac, msg)
	progFill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
	progLabel.Text = msg
end

local function log(msg, level) -- level: nil | "warn" | "error"
	logLabel.Text = msg
	paint(logLabel, "TextColor3", if level == "error" then C.ErrorText elseif level == "warn" then C.WarningText else C.MainText)
end

---------------------------------------------------------------------------
-- Link
---------------------------------------------------------------------------
local lastDecodeTime = 0 -- seconds spent in JSONDecode by the last request (import timing)

local function request(method, path, body)
	local res = HttpService:RequestAsync({
		Url = `http://127.0.0.1:{tonumber(portBox.Text) or 31337}{path}`,
		Method = method,
		Headers = { ["Content-Type"] = "application/json" },
		Body = if body ~= nil then HttpService:JSONEncode(body) else nil,
	})
	local tDecode = os.clock()
	local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
	lastDecodeTime = os.clock() - tDecode
	if not res.Success then
		error(if ok and type(data) == "table" and data.error then data.error else `HTTP {res.StatusCode}`, 0)
	end
	return data
end

---------------------------------------------------------------------------
-- Rig helpers
---------------------------------------------------------------------------
local function selectedRigs()
	local rigs, seen = {}, {}
	for _, inst in Selection:Get() do
		local model = if inst:IsA("Model") then inst else inst:FindFirstAncestorWhichIsA("Model")
		while model and not (model:FindFirstChildWhichIsA("Humanoid") or model:FindFirstChildWhichIsA("AnimationController")) do
			model = model:FindFirstAncestorWhichIsA("Model")
		end
		if model and not seen[model] then
			seen[model] = true
			table.insert(rigs, model)
		end
	end
	return rigs
end

-- Motor6D tree: parentOf[child] = Part0, childJoints[part] = motors with Part0 == part.
local function jointTree(model)
	local parentOf, childJoints = {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 and not parentOf[d.Part1] then
			parentOf[d.Part1] = d.Part0
			childJoints[d.Part0] = childJoints[d.Part0] or {}
			table.insert(childJoints[d.Part0], d)
		end
	end
	return parentOf, childJoints
end

local function rootPart(model)
	return model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
end

-- Pose tree for animation: Motor6D parts, Bones (skinned meshes), and welded parts
-- (no channel of their own, but Bones inside them need a path to the root).
-- animatable = nodes a pose can drive: Motor6D children and Bones.
local function poseTree(model)
	local parentOf, animatable, isBone = {}, {}, {}
	local welds = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 and not parentOf[d.Part1] then
			parentOf[d.Part1] = d.Part0
			animatable[d.Part1] = true
		elseif ((d:IsA("JointInstance") and not d:IsA("Motor6D")) or d:IsA("WeldConstraint")) and d.Part0 and d.Part1 then
			table.insert(welds, d)
		end
	end
	local rootP = rootPart(model)
	local function inTree(part)
		return part == rootP or parentOf[part] ~= nil
	end
	local changed = true
	while changed do
		changed = false
		for _, w in welds do
			local a, b = w.Part0, w.Part1
			if inTree(b) and not inTree(a) then
				a, b = b, a
			end
			if inTree(a) and not inTree(b) then
				parentOf[b] = a
				changed = true
			end
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") and d.Parent and (d.Parent:IsA("Bone") or d.Parent:IsA("BasePart")) then
			parentOf[d] = d.Parent
			animatable[d] = true
			isBone[d] = true
		end
	end
	return parentOf, animatable, isBone
end

-- Studio's Bone rest lengths (distance from parent Bone), so Blender can match the mesh's import scale.
local function boneRest(models)
	local rest = {}
	for _, model in models do
		for _, d in model:GetDescendants() do
			if d:IsA("Bone") and d.Parent and d.Parent:IsA("Bone") then
				rest[d.Name] = d.CFrame.Position.Magnitude
			end
		end
	end
	return if next(rest) then rest else nil -- JSONEncode turns {} into [], so send nothing
end

local function updateTarget()
	local rigs = selectedRigs()
	if #rigs == 0 then
		targetLabel.Text = "Select a rig model in the Explorer (several to import onto each)."
		paint(targetLabel, "TextColor3", C.DimmedText)
	else
		local names = {}
		for _, m in rigs do
			table.insert(names, m.Name)
		end
		targetLabel.Text = table.concat(names, ", ")
		paint(targetLabel, "TextColor3", C.MainText)
	end
end
Selection.SelectionChanged:Connect(updateTarget)
updateTarget()

---------------------------------------------------------------------------
-- Payload -> KeyframeSequence (single pass)
---------------------------------------------------------------------------
local function buildSequence(model, data, loop, onProgress)
	local parentOf, animatable, isBone = poseTree(model)
	local byName = {}
	local seen = {}
	for child, parent in parentOf do
		for _, part in { child, parent } do
			if not seen[part] then
				seen[part] = true
				byName[part.Name] = byName[part.Name] or {}
				table.insert(byName[part.Name], part)
			end
		end
	end
	local assigned, claimed = matchBones(data.rig, byName, parentOf, isBone)

	local kfs = Instance.new("KeyframeSequence")
	kfs.Loop = loop
	kfs.Priority = Enum.AnimationPriority.Action
	local keyframes, poses = {}, {}

	local function poseFor(kf, part)
		local cache = poses[kf]
		local p = cache[part]
		if p then
			return p
		end
		p = Instance.new("Pose")
		p.Name = part.Name
		p.Weight = 0 -- structural until keyed; each channel interpolates across its own keys
		local parent = parentOf[part]
		p.Parent = if parent then poseFor(kf, parent) else kf
		cache[part] = p
		return p
	end

	local total, done, budget = 0, 0, os.clock()
	for _ in data.bones do
		total += 1
	end
	for key, bone in data.bones do
		done += 1
		local part = assigned[key]
		if not (part and animatable[part]) then -- unmatched, a root, or a welded part: nothing to drive
			continue
		end
		local p, e = bone.p, bone.e
		for i, t in bone.t do
			local kf = keyframes[t]
			if not kf then
				kf = Instance.new("Keyframe")
				kf.Time = t
				kf.Parent = kfs
				keyframes[t] = kf
				poses[kf] = {}
			end
			local pose = poseFor(kf, part)
			local o = (i - 1) * 7
			pose.CFrame = CFrame.new(p[o + 1], p[o + 2], p[o + 3], p[o + 4], p[o + 5], p[o + 6], p[o + 7])
			pose.EasingStyle = if string.byte(e, i) == 67 then Enum.PoseEasingStyle.Constant else Enum.PoseEasingStyle.Linear -- 67 = "C"
			pose.EasingDirection = Enum.PoseEasingDirection.Out
			pose.Weight = 1
			if os.clock() - budget > 0.05 then -- yield on time, not item count
				onProgress(done / total)
				task.wait()
				budget = os.clock()
			end
		end
	end

	-- Report: Studio joints/Bones Blender has no bone for (a real problem) vs Motor6D bones
	-- that belong to other rigs in the same armature (normal for R15/R6 combo rigs).
	-- Unmatched Blender-only bones (IK/control bones) are expected and not counted.
	local unmatchedJoints, otherBones = {}, 0
	for node in animatable do
		if not claimed[node] then
			table.insert(unmatchedJoints, node.Name)
		end
	end
	for key, entry in data.rig do
		if not assigned[key] and entry[1] ~= "" and entry[3] ~= "B" then
			otherBones += 1
		end
	end
	table.sort(unmatchedJoints)
	return kfs, unmatchedJoints, otherBones
end

---------------------------------------------------------------------------
-- Preview: every control works at any moment and always wins.
---------------------------------------------------------------------------
local previews = {} -- { model, kfs, animator, track }
local playing = false
local loopEnabled = plugin:GetSetting("loop") ~= false
local dragging = false

local function editMode()
	return not RunService:IsRunning()
end

local function animatorFor(model)
	local holder = model:FindFirstChildWhichIsA("Humanoid") or model:FindFirstChildWhichIsA("AnimationController")
	if not holder then
		return nil
	end
	local animator = holder:FindFirstChildWhichIsA("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = holder
	end
	return animator
end

local function flush(animator)
	if editMode() and animator and animator.Parent then
		pcall(animator.StepAnimations, animator, 0)
	end
end

local function refreshTransport()
	playButton.Text = if playing then "Pause" else "Play"
	loopButton.Text = if loopEnabled then "Loop: On" else "Loop: Off"
end

-- Stop everything on the previewed rigs, including tracks we didn't start, and reset joints.
local function hardStop()
	for _, p in previews do
		if p.track then
			p.track:Stop(0)
			p.track:Destroy()
			p.track = nil
		end
		if p.animator and p.animator.Parent then
			for _, t in p.animator:GetPlayingAnimationTracks() do
				t:Stop(0)
			end
			flush(p.animator)
		end
		if p.model.Parent then
			for _, d in p.model:GetDescendants() do
				if d:IsA("Motor6D") or d:IsA("Bone") then
					d.Transform = CFrame.identity
				end
			end
		end
	end
	playing = false
	refreshTransport()
	timeFill.Size = UDim2.fromScale(0, 1)
	playhead.Position = UDim2.fromOffset(-1, -2)
end

local function ensureTracks()
	for _, p in previews do
		if not p.track and p.model.Parent then
			p.animator = animatorFor(p.model)
			if p.animator then
				for _, t in p.animator:GetPlayingAnimationTracks() do
					t:Stop(0)
				end
				local anim = Instance.new("Animation")
				anim.AnimationId = AnimationClipProvider:RegisterAnimationClip(p.kfs)
				p.track = p.animator:LoadAnimation(anim)
				p.track.Looped = loopEnabled
				p.track:Play(0)
				p.track:AdjustSpeed(0)
			end
		end
	end
end

local function play()
	if #previews == 0 then
		log("Import an animation first.", "warn")
		return
	end
	ensureTracks()
	for _, p in previews do
		local t = p.track
		if t then
			if not t.IsPlaying then -- finished (non-looped) or stopped: restart from the top
				t:Play(0)
				t.TimePosition = 0
			end
			t:AdjustSpeed(1)
		end
	end
	playing = true
	refreshTransport()
end

local function pause()
	for _, p in previews do
		if p.track then
			p.track:AdjustSpeed(0)
		end
	end
	playing = false
	refreshTransport()
end

local function seek(frac)
	if #previews == 0 then
		return
	end
	ensureTracks()
	for _, p in previews do
		local t = p.track
		if t then
			if not t.IsPlaying then
				t:Play(0)
			end
			t:AdjustSpeed(0)
			t.TimePosition = math.clamp(frac * t.Length, 0, math.max(t.Length - 1e-3, 0))
			flush(p.animator)
		end
	end
	playing = false
	refreshTransport()
end

local _stopButton
playButton, _stopButton, loopButton = buttonRow(previewSection, {
	{ "Play", function()
		if playing then
			pause()
		else
			play()
		end
	end, true },
	{ "Stop", hardStop },
	{ "Loop", function()
		loopEnabled = not loopEnabled
		plugin:SetSetting("loop", loopEnabled)
		for _, p in previews do
			p.kfs.Loop = loopEnabled
			if p.track then
				p.track.Looped = loopEnabled
			end
		end
		refreshTransport()
	end },
})
refreshTransport()

local function seekFromInput(input)
	local x = (input.Position.X - timeline.AbsolutePosition.X) / math.max(timeline.AbsoluteSize.X, 1)
	seek(math.clamp(x, 0, 1))
end
timeline.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		seekFromInput(input)
	end
end)
timeline.InputChanged:Connect(function(input)
	if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		seekFromInput(input)
	end
end)
timeline.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = false
	end
end)

RunService.Heartbeat:Connect(function(dt)
	local first = previews[1] and previews[1].track
	if not first then
		return
	end
	if editMode() then -- Studio doesn't step animators outside play mode
		for _, p in previews do
			if p.track and p.animator and p.animator.Parent then
				p.animator:StepAnimations(dt)
			end
		end
	end
	if playing and not first.IsPlaying then -- non-looped clip reached the end
		playing = false
		refreshTransport()
	end
	local length = first.Length
	local frac = if length > 0 then first.TimePosition / length else 0
	timeFill.Size = UDim2.fromScale(frac, 1)
	playhead.Position = UDim2.new(frac, -1, 0, -2)
	timeLabel.Text = string.format("%.2f / %.2f s", first.TimePosition, length)
end)

---------------------------------------------------------------------------
-- Import
---------------------------------------------------------------------------
local busy = false

local function importArmature(name)
	local rigs = selectedRigs()
	if #rigs == 0 then
		log("Select the rig model(s) in the Explorer first.", "error")
		return
	end
	if busy then
		log("Still working on the previous request.", "warn")
		return
	end
	busy = true
	hardStop()
	local t0 = os.clock()
	setProgress(0, `Baking '{name}' in Blender…`)

	local polling = true
	task.spawn(function()
		while polling do
			local ok, p = pcall(request, "GET", "/progress")
			if polling and ok and type(p) == "table" and (p.total or 0) > 0 then
				setProgress(0.7 * p.done / p.total, `Baking in Blender: frame {p.done} / {p.total}`)
			end
			task.wait(0.15)
		end
	end)
	local ok, data = pcall(request, "POST", "/animation", { name = name, boneRest = boneRest(rigs) })
	polling = false
	if not ok then
		busy = false
		setProgress(0, "Failed")
		log(`Import failed: {data}`, "error")
		return
	end
	local tDecode = lastDecodeTime
	local tFetch = os.clock() - t0 - tDecode -- Blender bake + localhost transfer
	local tBuild0 = os.clock()

	local folder = ServerStorage:FindFirstChild("Blender2Roblox") or new("Folder", { Name = "Blender2Roblox", Parent = ServerStorage })
	previews = {}
	local lines, level = {}, nil
	local ok2, err = pcall(function()
		for i, model in rigs do
			local kfs, unmatched, otherBones = buildSequence(model, data, loopEnabled, function(frac)
				setProgress(0.7 + 0.3 * (i - 1 + frac) / #rigs, `Building keyframes for {model.Name}…`)
			end)
			kfs.Name = if #rigs > 1 then `{name} ({model.Name})` else name
			local old = folder:FindFirstChild(kfs.Name)
			if old then
				old:Destroy()
			end
			kfs.Parent = folder
			table.insert(previews, { model = model, kfs = kfs })
			local line = `{model.Name}: {#kfs:GetKeyframes()} keyframes`
			if #unmatched > 0 then
				line ..= `\n  No Blender bone for: {table.concat(unmatched, ", ")}`
				level = "warn"
			end
			if otherBones > 0 then
				line ..= `\n  {otherBones} bones belong to other rigs in this armature (ignored)`
			end
			table.insert(lines, line)
		end
	end)
	busy = false
	if not ok2 then
		setProgress(0, "Failed")
		log(`Import failed: {err}`, "error")
		return
	end
	setProgress(1, string.format(
		"Done in %.2fs: Blender + transfer %.2fs · decode %.2fs · build %.2fs · %.2fs clip",
		os.clock() - t0, tFetch, tDecode, os.clock() - tBuild0, data.len
	))
	log(table.concat(lines, "\n"), level)
	play()
end

local function refresh()
	for _, c in armList:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local ok, names = pcall(request, "GET", "/armatures")
	if not ok then
		connStatus.Text = `Not connected on port {portBox.Text}. Start the link in Blender (N panel > Blender2Roblox).`
		paint(connStatus, "TextColor3", C.ErrorText)
		return
	end
	connStatus.Text = `Connected · {#names} armature(s)`
	paint(connStatus, "TextColor3", C.DimmedText)
	for _, armName in names do
		local row = rounded(new("TextButton", {
			Text = "",
			AutoButtonColor = true,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = nextOrder(),
			Parent = armList,
		}))
		paint(row, "BackgroundColor3", C.Item)
		local nameLabel = new("TextLabel", {
			Text = armName,
			BackgroundTransparency = 1,
			Font = Enum.Font.SourceSans,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.new(1, -70, 1, 0),
			Parent = row,
		})
		paint(nameLabel, "TextColor3", C.MainText)
		local importTag = new("TextLabel", {
			Text = "Import",
			BackgroundTransparency = 1,
			Font = Enum.Font.SourceSansSemibold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.new(1, -64, 0, 0),
			Size = UDim2.new(0, 56, 1, 0),
			Parent = row,
		})
		paint(importTag, "TextColor3", C.LinkText)
		row.Activated:Connect(function()
			importArmature(armName)
		end)
	end
	if #names == 0 then
		text(armList, "No Roblox-rigged armatures in this .blend.")
	end
end
refreshButton.Activated:Connect(refresh)
portBox.FocusLost:Connect(function()
	plugin:SetSetting("port", tonumber(portBox.Text) or 31337)
	refresh()
end)

---------------------------------------------------------------------------
-- Send rig (with real mesh geometry) to Blender
---------------------------------------------------------------------------
local function r4(x)
	return math.round(x * 1e4) / 1e4
end

local meshCache = {} -- mesh id -> {geo, lo, hi} | false (unreadable)

-- Real geometry via EditableMesh. Works for meshes you (or Roblox) own; others stay boxes.
local function readMesh(id, content)
	if meshCache[id] ~= nil then
		return meshCache[id]
	end
	local ok, em = pcall(AssetService.CreateEditableMeshAsync, AssetService, content)
	if not ok then
		meshCache[id] = false
		return false
	end
	local v, f, u, fu, vIndex, uvIndex = {}, {}, {}, {}, {}, {}
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	local budget = os.clock()
	for _, vid in em:GetVertices() do
		local pos = em:GetPosition(vid)
		vIndex[vid] = #v // 3
		table.insert(v, r4(pos.X))
		table.insert(v, r4(pos.Y))
		table.insert(v, r4(pos.Z))
		lo = Vector3.new(math.min(lo.X, pos.X), math.min(lo.Y, pos.Y), math.min(lo.Z, pos.Z))
		hi = Vector3.new(math.max(hi.X, pos.X), math.max(hi.Y, pos.Y), math.max(hi.Z, pos.Z))
	end
	for _, fid in em:GetFaces() do
		local fv, fuv = em:GetFaceVertices(fid), em:GetFaceUVs(fid)
		for i = 1, 3 do
			table.insert(f, vIndex[fv[i]])
			local uvId = fuv[i]
			local idx = uvId and uvIndex[uvId]
			if uvId and not idx then
				local uv = em:GetUV(uvId) or Vector2.zero
				idx = #u // 2
				uvIndex[uvId] = idx
				table.insert(u, r4(uv.X))
				table.insert(u, r4(uv.Y))
			end
			table.insert(fu, idx or 0)
		end
		if os.clock() - budget > 0.05 then
			task.wait()
			budget = os.clock()
		end
	end
	em:Destroy()
	local entry = { geo = { id = id, v = v, f = f, u = if #u > 0 then u else nil, fu = if #u > 0 then fu else nil }, lo = lo, hi = hi }
	meshCache[id] = entry
	return entry
end

-- Mesh source of a part: MeshPart, or a part with a FileMesh SpecialMesh.
local function meshSource(part)
	if part:IsA("MeshPart") and part.MeshId ~= "" then
		return part.MeshId, part.MeshContent, nil
	end
	local sm = part:FindFirstChildWhichIsA("SpecialMesh")
	if sm and sm.MeshType == Enum.MeshType.FileMesh and sm.MeshId ~= "" then
		return sm.MeshId, sm.MeshContent, sm
	end
	return nil
end

-- Fill mesh/meshScale/meshOffset so Blender maps mesh space to part space.
local function addMesh(node, part, failed)
	local id, content, specialMesh = meshSource(part)
	if not id then
		return
	end
	local m = readMesh(id, content)
	if not m then
		failed[id] = true
		return
	end
	node.mesh = id
	if specialMesh then -- FileMesh: raw mesh units, scaled and offset
		node.meshScale = { specialMesh.Scale.X, specialMesh.Scale.Y, specialMesh.Scale.Z }
		node.meshOffset = { specialMesh.Offset.X, specialMesh.Offset.Y, specialMesh.Offset.Z }
	else -- MeshPart: mesh bounds are fitted to Size, centered
		local ext, center = m.hi - m.lo, (m.hi + m.lo) / 2
		local s = Vector3.new(
			if ext.X > 1e-6 then part.Size.X / ext.X else 1,
			if ext.Y > 1e-6 then part.Size.Y / ext.Y else 1,
			if ext.Z > 1e-6 then part.Size.Z / ext.Z else 1
		)
		node.meshScale = { s.X, s.Y, s.Z }
		node.meshOffset = { -center.X * s.X, -center.Y * s.Y, -center.Z * s.Z }
	end
end

local function sendRig()
	local model = selectedRigs()[1]
	if not model then
		log("Select the rig model in the Explorer first.", "error")
		return
	end
	if busy then
		log("Still working on the previous request.", "warn")
		return
	end
	local rootP = rootPart(model)
	if not rootP then
		log(`{model.Name} has no PrimaryPart or HumanoidRootPart.`, "error")
		return
	end
	busy = true
	local ok, res = pcall(function()
		local parentOf, childJoints = jointTree(model)
		local inTree = { [rootP] = true }
		for part in parentOf do
			inTree[part] = true
		end
		-- Welded parts (accessory handles, props) ride along on the part they're welded to.
		local aux, added = {}, {}
		for _, d in model:GetDescendants() do
			if (d:IsA("JointInstance") and not d:IsA("Motor6D")) or d:IsA("WeldConstraint") then
				local a, b = d.Part0, d.Part1
				if a and b and inTree[b] and not inTree[a] then
					a, b = b, a
				end
				if a and b and inTree[a] and not inTree[b] and not added[b] then
					added[b] = true
					aux[a] = aux[a] or {}
					table.insert(aux[a], b)
				end
			end
		end

		local allParts = {}
		for part in inTree do
			table.insert(allParts, part)
		end
		for part in added do
			table.insert(allParts, part)
		end
		local ids, idList = {}, {}
		for _, part in allParts do
			local id, content = meshSource(part)
			if id and not ids[id] then
				ids[id] = content
				table.insert(idList, id)
			end
		end

		local failed = {}
		for i, id in idList do
			setProgress(0.8 * (i - 1) / math.max(#idList, 1), `Reading mesh {i} / {#idList}`)
			local m = readMesh(id, ids[id])
			if m then
				local sent = pcall(request, "POST", "/mesh", m.geo)
				if not sent then
					failed[id] = true
				end
			else
				failed[id] = true
			end
		end

		local function encode(part, motor)
			local node = {
				jname = part.Name,
				transform = { part.CFrame:GetComponents() },
				size = { part.Size.X, part.Size.Y, part.Size.Z },
				children = {},
				aux = {},
			}
			if not failed[(meshSource(part))] then
				addMesh(node, part, failed)
			end
			if motor then
				node.jointtransform0 = { motor.C0:GetComponents() }
				node.jointtransform1 = { motor.C1:GetComponents() }
			end
			for _, m in childJoints[part] or {} do
				table.insert(node.children, encode(m.Part1, m))
			end
			for _, a in aux[part] or {} do
				local an = { jname = a.Name, transform = { a.CFrame:GetComponents() }, size = { a.Size.X, a.Size.Y, a.Size.Z } }
				if not failed[(meshSource(a))] then
					addMesh(an, a, failed)
				end
				table.insert(node.aux, an)
			end
			return node
		end
		setProgress(0.85, "Building armature in Blender…")
		local armature = request("POST", "/rig", { rigName = model.Name, rig = encode(rootP, nil) })
		local nFailed = 0
		for _ in failed do
			nFailed += 1
		end
		return { armature = armature, meshes = #idList - nFailed, failed = nFailed }
	end)
	busy = false
	if not ok then
		setProgress(0, "Failed")
		log(`Send failed: {res}`, "error")
		return
	end
	setProgress(1, `Created '{res.armature}' in Blender`)
	local msg = `Sent {model.Name}: {res.meshes} mesh(es) with real geometry.`
	if res.failed > 0 then
		msg ..= `\n{res.failed} mesh(es) couldn't be read (EditableMesh only loads meshes you or Roblox own); they show as boxes.`
	end
	log(msg, if res.failed > 0 then "warn" else nil)
end

local function publish()
	if #previews == 0 then
		log("Import an animation first.", "warn")
		return
	end
	-- Publish the preview of the selected rig, else the first one.
	local pick = previews[1]
	local sel = selectedRigs()[1]
	for _, p in previews do
		if p.model == sel then
			pick = p
		end
	end
	Selection:Set({ pick.kfs })
	plugin:SaveSelectedToRoblox()
end

buttonRow(outSection, { { "Publish to Roblox", publish, true }, { "Send rig to Blender", sendRig } })
logLabel = text(outSection, "")
paint(logLabel, "TextColor3", C.MainText)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	if widget.Enabled then
		refresh()
	end
end)
if widget.Enabled then
	task.defer(refresh)
end
plugin.Unloading:Connect(hardStop)
