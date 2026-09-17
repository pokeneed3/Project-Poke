print("hello")
-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ============================================================
-- Configuration
-- ============================================================
local ESPConfig = {
	Enabled = true,

	-- Global fallbacks (groups override these)
	BoxColor = Color3.fromRGB(255, 255, 255),
	TextColor = Color3.fromRGB(255, 255, 255),
	TextSize = 14,
	BoxStyle = "Square", -- "Square" | "Corners" | "Filled" | "3D"
	BoxThickness = 1,
	BoxTransparency = 1,
	CornerLength = 0.25, -- fraction of box side, for "Corners"
	MaxDistance = math.huge, -- studs; hide beyond this
	TeamCheck = false,
	ShowBox = true,
	ShowName = true,
	ShowDistance = true,
	ShowHealthPercentage = true,
	UseDisplayName = true,
	ShowBars = true,
	BarColor = nil, -- nil = use per-bar Color / LerpColor
	OcclusionCheck = false, -- raycast from camera to root
	Padding = 0, -- extra pixels around box

	-- FIX: min distance (studs) below which ESP is hidden to avoid
	-- unreliable projections when the camera is inside/near the target.
	MinDistance = 6,

	-- Optional global text formatter.
	-- Signature: function(target, char, distance, group) -> string
	FormatText = nil,

	-- Fallback group config applied when a group has no explicit key.
	Defaults = {},

	-- Per-group overrides, e.g.
	-- Groups = {
	--   Player = { BoxColor = Color3.fromRGB(255,0,0) },
	--   NPC    = { BoxColor = Color3.fromRGB(0,255,0), MaxDistance = 500 },
	-- }
	Groups = {},
}

local ESPObjects = {}
local CustomBars = {}
local GroupClassifiers = {}
local Connections = {}
local ModelPartCache = setmetatable({}, { __mode = "k" })

-- ============================================================
-- Helpers
-- ============================================================

-- Resolve a setting for a group with fallback chain:
--   Groups[group][key] -> Groups.Default[key] -> Defaults[key] -> ESPConfig[key]
local function getSetting(group, key)
	local groupCfg = ESPConfig.Groups[group]
	if groupCfg and groupCfg[key] ~= nil then
		return groupCfg[key]
	end

	local defaultGroup = ESPConfig.Groups.Default
	if defaultGroup and defaultGroup[key] ~= nil then
		return defaultGroup[key]
	end

	if ESPConfig.Defaults[key] ~= nil then
		return ESPConfig.Defaults[key]
	end

	return ESPConfig[key]
end

local function safeDestroy(drawing)
	if not drawing then
		return
	end
	pcall(function()
		drawing.Visible = false
	end)
	local destroyFn = drawing.Destroy or drawing.Remove
	if destroyFn then
		pcall(destroyFn, drawing)
	end
end

local function resolveGroup(instance)
	for _, classifier in ipairs(GroupClassifiers) do
		local ok, matches = pcall(classifier.Predicate, instance)
		if ok and matches then
			return classifier.Name
		elseif not ok then
			warn("[ESP] Group classifier '" .. classifier.Name .. "' errored:", matches)
		end
	end

	if instance:IsA("Player") then
		return "Player"
	end
	return "Anything"
end

-- ============================================================
-- Group registration
-- ============================================================

local function RefreshAllTargets()
	for _, drawings in pairs(ESPObjects) do
		drawings.Target.NeedsRefresh = true
	end
end

local function RegisterGroup(name, predicate, atFront)
	assert(type(name) == "string", "Group name must be a string")
	assert(type(predicate) == "function", "predicate must be function(instance) -> boolean")

	for i, c in ipairs(GroupClassifiers) do
		if c.Name == name then
			if atFront then
				table.remove(GroupClassifiers, i)
				break
			else
				c.Predicate = predicate
				RefreshAllTargets()
				return
			end
		end
	end

	if atFront then
		table.insert(GroupClassifiers, 1, { Name = name, Predicate = predicate })
	else
		table.insert(GroupClassifiers, { Name = name, Predicate = predicate })
	end

	RefreshAllTargets()
end

local function UnregisterGroup(name)
	for i, c in ipairs(GroupClassifiers) do
		if c.Name == name then
			table.remove(GroupClassifiers, i)
			RefreshAllTargets()
			return true
		end
	end
	return false
end

-- ============================================================
-- Bars
-- ============================================================

local function createBarForPlayer(playerDrawings, barDef, group)
	if barDef.Groups and not table.find(barDef.Groups, group) then
		return
	end

	local outline = Drawing.new("Square")
	outline.Visible = false
	outline.Color = Color3.fromRGB(0, 0, 0)
	outline.Thickness = 1
	outline.Filled = true
	outline.Transparency = 0.8
	outline.ZIndex = 2

	local fill = Drawing.new("Square")
	fill.Visible = false
	fill.Color = barDef.Color or Color3.fromRGB(0, 255, 0)
	fill.Thickness = 1
	fill.Filled = true
	fill.Transparency = 1
	fill.ZIndex = 3

	playerDrawings.Bars[barDef.Name] = {
		Outline = outline,
		Fill = fill,
		Def = barDef,
	}
end

local RefreshGroup = function(instance)
	local drawings = ESPObjects[instance]
	if not drawings then
		return
	end

	local newGroup = resolveGroup(instance)
	if newGroup == drawings.Target.Group then
		return
	end
	drawings.Target.Group = newGroup

	for _, barDef in ipairs(CustomBars) do
		local applies = not barDef.Groups or table.find(barDef.Groups, newGroup) ~= nil
		local existing = drawings.Bars[barDef.Name]

		if applies and not existing then
			createBarForPlayer(drawings, barDef, newGroup)
		elseif not applies and existing then
			safeDestroy(existing.Outline)
			safeDestroy(existing.Fill)
			drawings.Bars[barDef.Name] = nil
		end
	end
end

-- ============================================================
-- Target construction
-- ============================================================

local function makeTarget(instance, groupOverride)
	if not instance then
		return nil
	end

	if instance:IsA("Player") then
		return {
			Instance = instance,
			Group = groupOverride or resolveGroup(instance),
			GetModel = function()
				return instance.Character
			end,
			GetName = function()
				return ESPConfig.UseDisplayName and instance.DisplayName or instance.Name
			end,
			GetTeam = function()
				return instance.Team
			end,
			IsLocal = (instance == LocalPlayer),
		}
	elseif instance:IsA("Model") then
		return {
			Instance = instance,
			Group = groupOverride or resolveGroup(instance),
			GetModel = function()
				return instance
			end,
			GetName = function()
				local override = instance:GetAttribute("ESPName")
				if override then
					return tostring(override)
				end
				return instance.Name
			end,
			GetTeam = function()
				return nil
			end,
			IsLocal = false,
		}
	end
	return nil
end

-- ============================================================
-- Drawing creation
-- ============================================================

local function makeBoxDrawings(style)
	local d = { Style = style }
	if style == "Corners" then
		d.TopLeftH = Drawing.new("Line")
		d.TopLeftV = Drawing.new("Line")
		d.TopRightH = Drawing.new("Line")
		d.TopRightV = Drawing.new("Line")
		d.BotLeftH = Drawing.new("Line")
		d.BotLeftV = Drawing.new("Line")
		d.BotRightH = Drawing.new("Line")
		d.BotRightV = Drawing.new("Line")
		d.All = {
			d.TopLeftH,
			d.TopLeftV,
			d.TopRightH,
			d.TopRightV,
			d.BotLeftH,
			d.BotLeftV,
			d.BotRightH,
			d.BotRightV,
		}
		for _, line in ipairs(d.All) do
			line.Visible = false
			line.Thickness = 1
			line.Transparency = 1
			line.ZIndex = 2
		end
	elseif style == "3D" then
		d.Lines = {}
		for i = 1, 12 do
			local line = Drawing.new("Line")
			line.Visible = false
			line.Thickness = 1
			line.Transparency = 1
			line.ZIndex = 2
			d.Lines[i] = line
		end
	else
		d.Square = Drawing.new("Square")
		d.Square.Visible = false
		d.Square.Thickness = 1
		d.Square.Filled = (style == "Filled")
		d.Square.Transparency = (style == "Filled") and 0.5 or 1
		d.Square.ZIndex = 2
	end
	return d
end

local function destroyBoxDrawings(box)
	if not box then
		return
	end
	if box.All then
		for _, line in ipairs(box.All) do
			safeDestroy(line)
		end
	elseif box.Lines then
		for _, line in ipairs(box.Lines) do
			safeDestroy(line)
		end
	elseif box.Square then
		safeDestroy(box.Square)
	end
end

local function hideBoxDrawings(box)
	if not box then
		return
	end
	if box.All then
		for _, line in ipairs(box.All) do
			line.Visible = false
		end
	elseif box.Lines then
		for _, line in ipairs(box.Lines) do
			line.Visible = false
		end
	elseif box.Square then
		box.Square.Visible = false
	end
end

local function createESP(instance, groupOverride)
	if instance == LocalPlayer then
		return
	end
	if ESPObjects[instance] then
		return
	end

	local target = makeTarget(instance, groupOverride)
	if not target then
		return
	end
	if target.IsLocal then
		return
	end

	local style = getSetting(target.Group, "BoxStyle")
	local drawings = {
		Box = makeBoxDrawings(style),
		Name = Drawing.new("Text"),
		Bars = {},
		Target = target,
	}

	drawings.Name.Visible = false
	drawings.Name.Color = getSetting(target.Group, "TextColor")
	drawings.Name.Size = getSetting(target.Group, "TextSize")
	drawings.Name.Center = true
	drawings.Name.Outline = true
	drawings.Name.OutlineColor = Color3.fromRGB(0, 0, 0)
	drawings.Name.ZIndex = 4

	for _, barDef in ipairs(CustomBars) do
		createBarForPlayer(drawings, barDef, target.Group)
	end

	ESPObjects[instance] = drawings
end

local function removeESP(instance)
	local drawings = ESPObjects[instance]
	if not drawings then
		return
	end

	destroyBoxDrawings(drawings.Box)
	safeDestroy(drawings.Name)

	for _, barDrawings in pairs(drawings.Bars) do
		safeDestroy(barDrawings.Outline)
		safeDestroy(barDrawings.Fill)
	end

	ESPObjects[instance] = nil
end

-- ============================================================
-- Validity + bounding box
-- ============================================================

-- FIX: stricter validity check.
--   - Player targets require a Humanoid AND a HumanoidRootPart so we
--     don't render on half-streamed / respawning characters.
--   - Model targets still allow the loose BasePart fallback.
-- Returns: model, root, humanoid
local function isValidCharacter(target)
	local model = target.GetModel()
	if not model or not model.Parent then
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart

	if humanoid then
		-- Humanoid rigs are only valid once the root exists and is alive.
		if not root then
			return nil
		end
		if humanoid.Health <= 0 then
			return nil
		end
	else
		-- Non-Humanoid model: allow a loose BasePart fallback.
		if not root then
			root = model:FindFirstChildWhichIsA("BasePart")
		end
		if not root then
			return nil
		end
	end

	return model, root, humanoid
end

-- FIX: compute the bounding box only from the character's own BaseParts,
-- ignoring tools, accessories with offset welds, effects, etc. This is
-- what caused the "giant / offset box on some people" bug.
local function getModelParts(model)
	local cachedParts = ModelPartCache[model]
	if cachedParts then
		return cachedParts
	end

	local parts = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local inTool = false
			local inAccessory = false
			local parent = descendant.Parent
			while parent and parent ~= model do
				if parent:IsA("Tool") then
					inTool = true
					break
				elseif parent:IsA("Accessory") then
					inAccessory = true
					break
				end
				parent = parent.Parent
			end

			if not inTool and not inAccessory then
				table.insert(parts, descendant)
			end
		end
	end

	ModelPartCache[model] = parts
	return parts
end

local function computeModelBounds(model)
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	local any = false

	for _, part in ipairs(getModelParts(model)) do
		if part.Parent then
			any = true
			local cf = part.CFrame
			local size = part.Size
			local half = size * 0.5
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz = -1, 1, 2 do
						local corner = cf * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
						minV = Vector3.new(
							math.min(minV.X, corner.X),
							math.min(minV.Y, corner.Y),
							math.min(minV.Z, corner.Z)
						)
						maxV = Vector3.new(
							math.max(maxV.X, corner.X),
							math.max(maxV.Y, corner.Y),
							math.max(maxV.Z, corner.Z)
						)
					end
				end
			end
		end
	end

	if not any then
		return nil
	end

	local center = (minV + maxV) * 0.5
	local size = maxV - minV
	return center, size
end

-- FIX: returns a CFrame + size, computed from our own AABB (not
-- GetBoundingBox, which includes tools/accessories). Falls back to
-- GetBoundingBox only if the manual pass finds nothing.
local function getWorldBoundingBox(model)
	local center, size = computeModelBounds(model)
	if center and size and size.Magnitude >= 1 then
		-- Build a CFrame aligned to world axes at the AABB center.
		return CFrame.new(center), size
	end

	-- Fallback: model may have no BaseParts we recognize (rare).
	local ok, cf, size2 = pcall(function()
		return model:GetBoundingBox()
	end)
	if ok and cf and size2 and size2.Magnitude >= 1 then
		return cf, size2
	end

	return nil
end

-- ============================================================
-- Box drawing
-- ============================================================

local function drawBox(drawings, group, x, y, w, h)
	local box = drawings.Box
	local color = getSetting(group, "BoxColor")
	local thickness = getSetting(group, "BoxThickness")
	local transparency = getSetting(group, "BoxTransparency")
	local wantedStyle = getSetting(group, "BoxStyle")

	-- Rebuild drawings if the style changed at runtime
	if box.Style ~= wantedStyle then
		destroyBoxDrawings(box)
		drawings.Box = makeBoxDrawings(wantedStyle)
		box = drawings.Box
	end

	if wantedStyle == "Corners" then
		local cl = getSetting(group, "CornerLength")
		local hLen = w * cl
		local vLen = h * cl

		local function setLine(line, x1, y1, x2, y2)
			line.From = Vector2.new(x1, y1)
			line.To = Vector2.new(x2, y2)
			line.Color = color
			line.Thickness = thickness
			line.Transparency = transparency
			line.Visible = true
		end

		setLine(box.TopLeftH, x, y, x + hLen, y)
		setLine(box.TopLeftV, x, y, x, y + vLen)
		setLine(box.TopRightH, x + w, y, x + w - hLen, y)
		setLine(box.TopRightV, x + w, y, x + w, y + vLen)
		setLine(box.BotLeftH, x, y + h, x + hLen, y + h)
		setLine(box.BotLeftV, x, y + h, x, y + h - vLen)
		setLine(box.BotRightH, x + w, y + h, x + w - hLen, y + h)
		setLine(box.BotRightV, x + w, y + h, x + w, y + h - vLen)
	elseif wantedStyle == "3D" then
		local off = 4
		local lines = box.Lines
		local pts = {
			Vector2.new(x, y),
			Vector2.new(x + w, y),
			Vector2.new(x + w, y + h),
			Vector2.new(x, y + h),
		}
		local back = {}
		for i, p in ipairs(pts) do
			back[i] = Vector2.new(p.X + off, p.Y - off)
		end
		local edges = {
			{ pts[1], pts[2] },
			{ pts[2], pts[3] },
			{ pts[3], pts[4] },
			{ pts[4], pts[1] },
			{ back[1], back[2] },
			{ back[2], back[3] },
			{ back[3], back[4] },
			{ back[4], back[1] },
			{ pts[1], back[1] },
			{ pts[2], back[2] },
			{ pts[3], back[3] },
			{ pts[4], back[4] },
		}
		for i = 1, 12 do
			local line = lines[i]
			local e = edges[i]
			line.From = e[1]
			line.To = e[2]
			line.Color = color
			line.Thickness = thickness
			line.Transparency = transparency
			line.Visible = true
		end
	else
		box.Square.Size = Vector2.new(w, h)
		box.Square.Position = Vector2.new(x, y)
		box.Square.Color = color
		box.Square.Thickness = thickness
		box.Square.Transparency = (wantedStyle == "Filled") and 0.5 or transparency
		box.Square.Filled = (wantedStyle == "Filled")
		box.Square.Visible = true
	end
end

-- ============================================================
-- Per-frame update
-- ============================================================

local function hideESP(drawings)
	hideBoxDrawings(drawings.Box)
	drawings.Name.Visible = false
	for _, barDrawings in pairs(drawings.Bars) do
		barDrawings.Outline.Visible = false
		barDrawings.Fill.Visible = false
	end
end

local FIXED_BOX_WIDTH = 60
local FIXED_BOX_HEIGHT = 90

local function updateTarget(instance, drawings)
	local target = drawings.Target
	local group = target.Group

	if target.NeedsRefresh then
		target.NeedsRefresh = false
		RefreshGroup(instance)
		group = drawings.Target.Group
	end

	local char, root = isValidCharacter(target)
	if not char then
		hideESP(drawings)
		return
	end

	local cf, size = getWorldBoundingBox(char)
	if not cf then
		hideESP(drawings)
		return
	end

	local boxCenter = cf.Position
	local distance = (Camera.CFrame.Position - boxCenter).Magnitude

	-- Distance gating
	local maxDist = getSetting(group, "MaxDistance")
	if maxDist and distance > maxDist then
		hideESP(drawings)
		return
	end
	local minDist = getSetting(group, "MinDistance") or 6
	if distance < minDist then
		hideESP(drawings)
		return
	end

	-- Team check
	local isTeammate = getSetting(group, "TeamCheck")
		and LocalPlayer.Team ~= nil
		and target.GetTeam() == LocalPlayer.Team
	if isTeammate then
		hideESP(drawings)
		return
	end

	-- Occlusion
	if getSetting(group, "OcclusionCheck") then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local filter = { char }
		if LocalPlayer.Character then
			table.insert(filter, LocalPlayer.Character)
		end
		params.FilterDescendantsInstances = filter
		local result = Workspace:Raycast(Camera.CFrame.Position, boxCenter - Camera.CFrame.Position, params)
		if result then
			hideESP(drawings)
			return
		end
	end

	-- SINGLE projected anchor point. No corner projection. No size math.
	local screenPoint, onScreen = Camera:WorldToViewportPoint(boxCenter)
	if not onScreen or screenPoint.Z <= 0 then
		hideESP(drawings)
		return
	end

	-- Hard-locked size. Nothing below this line can change width/height.
	local width = FIXED_BOX_WIDTH
	local height = FIXED_BOX_HEIGHT
	local boxCenterX = screenPoint.X
	local boxCenterY = screenPoint.Y
	local boxX = boxCenterX - width * 0.5
	local boxY = boxCenterY - height * 0.5

	-- Box
	if getSetting(group, "ShowBox") then
		drawBox(drawings, group, boxX, boxY, width, height)
	else
		hideBoxDrawings(drawings.Box)
	end

	-- Bars
	if getSetting(group, "ShowBars") then
		local leftOffset = 4
		local rightOffset = 4
		local bottomOffset = 4
		local barSpacing = 2

		local barBoxHeight = height
		local barBoxWidth = width

		for _, barDef in ipairs(CustomBars) do
			local barDrawings = drawings.Bars[barDef.Name]
			if barDrawings then
				local ok, curVal, maxVal = pcall(barDef.GetValue, char, instance)
				if not ok then
					curVal, maxVal = 0, 100
				end
				maxVal = (maxVal and maxVal > 0) and maxVal or 100
				local ratio = math.clamp((curVal or 0) / maxVal, 0, 1)
				local barWidth = barDef.Width or 2

				if barDef.Side == "Right" then
					local barX = boxX + width + rightOffset
					rightOffset = rightOffset + barWidth + barSpacing + 2
					barDrawings.Outline.Position = Vector2.new(barX - 1, boxY - 1)
					barDrawings.Outline.Size = Vector2.new(barWidth + 2, barBoxHeight + 2)
					local barHeight = math.clamp(math.floor(barBoxHeight * ratio), 0, barBoxHeight)
					barDrawings.Fill.Position = Vector2.new(barX, boxY + (barBoxHeight - barHeight))
					barDrawings.Fill.Size = Vector2.new(barWidth, barHeight)
				elseif barDef.Side == "Bottom" then
					local barY = boxY + height + bottomOffset
					bottomOffset = bottomOffset + barWidth + barSpacing + 2
					barDrawings.Outline.Position = Vector2.new(boxX - 1, barY - 1)
					barDrawings.Outline.Size = Vector2.new(barBoxWidth + 2, barWidth + 2)
					local fillWidth = math.clamp(math.floor(barBoxWidth * ratio), 0, barBoxWidth)
					barDrawings.Fill.Position = Vector2.new(boxX, barY)
					barDrawings.Fill.Size = Vector2.new(fillWidth, barWidth)
				else
					leftOffset = leftOffset + barWidth
					local barX = boxX - leftOffset
					leftOffset = leftOffset + barSpacing + 2
					barDrawings.Outline.Position = Vector2.new(barX - 1, boxY - 1)
					barDrawings.Outline.Size = Vector2.new(barWidth + 2, barBoxHeight + 2)
					local barHeight = math.clamp(math.floor(barBoxHeight * ratio), 0, barBoxHeight)
					barDrawings.Fill.Position = Vector2.new(barX, boxY + (barBoxHeight - barHeight))
					barDrawings.Fill.Size = Vector2.new(barWidth, barHeight)
				end

				local groupBarColor = ESPConfig.Groups[group] and ESPConfig.Groups[group].BarColor
				if groupBarColor then
					barDrawings.Fill.Color = groupBarColor
				elseif barDef.LerpColor then
					barDrawings.Fill.Color = Color3.fromRGB(255, 0, 0):Lerp(Color3.fromRGB(0, 255, 0), ratio)
				else
					barDrawings.Fill.Color = barDef.Color or Color3.fromRGB(0, 255, 0)
				end

				barDrawings.Outline.Visible = true
				barDrawings.Fill.Visible = (ratio > 0)
			end
		end
	else
		for _, barDrawings in pairs(drawings.Bars) do
			barDrawings.Outline.Visible = false
			barDrawings.Fill.Visible = false
		end
	end

	-- Text
	local showName = getSetting(group, "ShowName")
	local showDist = getSetting(group, "ShowDistance")
	local showHealth = getSetting(group, "ShowHealthPercentage")

	if showName or showDist or showHealth then
		local finalText
		if ESPConfig.FormatText then
			local ok, result = pcall(ESPConfig.FormatText, target, char, distance, group)
			if ok and result then
				finalText = result
			end
		end
		if not finalText then
			local parts = {}
			if showName then
				table.insert(parts, target.GetName())
			end
			if showDist then
				table.insert(parts, "[" .. math.floor(distance) .. "m]")
			end
			if showHealth then
				local humanoid = char:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.MaxHealth > 0 then
					local healthPercent = math.floor((humanoid.Health / humanoid.MaxHealth) * 100)
					table.insert(parts, "[" .. healthPercent .. "%]")
				end
			end
			finalText = table.concat(parts, " ")
		end

		if #finalText > 0 then
			local textSize = getSetting(group, "TextSize")
			drawings.Name.Text = finalText
			drawings.Name.Color = getSetting(group, "TextColor")
			drawings.Name.Size = textSize
			drawings.Name.Position = Vector2.new(boxCenterX, boxY - textSize - 4)
			drawings.Name.Visible = true
		else
			drawings.Name.Visible = false
		end
	else
		drawings.Name.Visible = false
	end
end

-- ============================================================
-- Render loop
-- ============================================================
local updateInterval = 1 / 30
local elapsed = 0

local renderConnection = RunService.RenderStepped:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < updateInterval then
		return
	end
	elapsed = 0

	if not ESPConfig.Enabled then
		for _, drawings in pairs(ESPObjects) do
			hideESP(drawings)
		end
		return
	end

	for instance, drawings in pairs(ESPObjects) do
		local ok, err = pcall(updateTarget, instance, drawings)
		if not ok then
			hideESP(drawings)
			warn("[ESP] update failed for", instance, "-", err)
		end
	end
end)

-- ============================================================
-- Camera change connection
-- ============================================================

table.insert(
	Connections,
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		Camera = Workspace.CurrentCamera
	end)
)

-- ============================================================
-- Bar API
-- ============================================================

local function NewBar(args)
	assert(type(args) == "table", "NewBar expects a table of arguments")
	assert(args.Name, "Bar must have a unique 'Name'")
	assert(type(args.GetValue) == "function", "Bar must provide a 'GetValue(char, instance)' function")
	assert(args.Groups == nil or type(args.Groups) == "table", "Bar 'Groups' must be an array of group names")

	for _, def in ipairs(CustomBars) do
		assert(def.Name ~= args.Name, "A bar named '" .. args.Name .. "' already exists")
	end

	local barDef = {
		Name = args.Name,
		Side = args.Side or "Left",
		Width = args.Width or 2,
		Color = args.Color or Color3.fromRGB(0, 255, 0),
		LerpColor = args.LerpColor or false,
		GetValue = args.GetValue,
		Groups = args.Groups,
	}

	table.insert(CustomBars, barDef)

	for _, drawings in pairs(ESPObjects) do
		if not drawings.Bars[barDef.Name] then
			createBarForPlayer(drawings, barDef, drawings.Target.Group)
		end
	end

	local handle = {}

	function handle.Remove()
		for i, def in ipairs(CustomBars) do
			if def.Name == barDef.Name then
				table.remove(CustomBars, i)
				break
			end
		end
		for _, drawings in pairs(ESPObjects) do
			if drawings.Bars[barDef.Name] then
				safeDestroy(drawings.Bars[barDef.Name].Outline)
				safeDestroy(drawings.Bars[barDef.Name].Fill)
				drawings.Bars[barDef.Name] = nil
			end
		end
		handle.Removed = true
	end

	function handle.SetColor(color)
		barDef.Color = color
		barDef.LerpColor = false
	end

	function handle.SetSide(side)
		barDef.Side = side
	end

	function handle.SetWidth(width)
		barDef.Width = width
	end

	-- FIX: when groups change at runtime, add/remove the bar on existing
	-- targets immediately instead of waiting for the next RefreshGroup.
	function handle.SetGroups(groups)
		barDef.Groups = groups
		for _, drawings in pairs(ESPObjects) do
			local applies = not groups or table.find(groups, drawings.Target.Group) ~= nil
			local existing = drawings.Bars[barDef.Name]
			if applies and not existing then
				createBarForPlayer(drawings, barDef, drawings.Target.Group)
			elseif not applies and existing then
				safeDestroy(existing.Outline)
				safeDestroy(existing.Fill)
				drawings.Bars[barDef.Name] = nil
			end
		end
	end

	return handle
end

-- ============================================================
-- Unload
-- ============================================================

local function unload()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	for _, conn in ipairs(Connections) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	table.clear(Connections)

	local toRemove = {}
	for instance in pairs(ESPObjects) do
		table.insert(toRemove, instance)
	end
	for _, instance in ipairs(toRemove) do
		removeESP(instance)
	end

	table.clear(CustomBars)
	table.clear(GroupClassifiers)
end

-- ============================================================
-- Public API
-- ============================================================

return {
	Config = ESPConfig,
	Objects = ESPObjects,
	NewBar = NewBar,
	Track = createESP,
	Untrack = removeESP,
	Unload = unload,
	RegisterGroup = RegisterGroup,
	UnregisterGroup = UnregisterGroup,
	RefreshGroup = RefreshGroup,
}
