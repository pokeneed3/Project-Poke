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

	-- Global fallbacks
	BoxColor = Color3.fromRGB(255, 255, 255),
	TextColor = Color3.fromRGB(255, 255, 255),
	TextSize = 14,
	BoxStyle = "Square", -- "Square" | "Corners" | "Filled" | "3D"
	BoxThickness = 1,
	BoxTransparency = 1,
	CornerLength = 0.25,
	MaxDistance = math.huge,
	TeamCheck = false,
	ShowBox = false,
	ShowName = true,
	ShowDistance = true,
	ShowHealthPercentage = true,
	UseDisplayName = true,
	ShowBars = true,
	BarColor = nil,
	OcclusionCheck = false,
	Padding = 0,
	MinDistance = 6,

	FormatText = nil,
	Defaults = {},
	Groups = {},
}

local ESPObjects = {}
local CustomBars = {}
local GroupClassifiers = {}
local Connections = {}

-- Reusable global RaycastParams to prevent GC allocations
local SharedRaycastParams = RaycastParams.new()
SharedRaycastParams.FilterType = Enum.RaycastFilterType.Exclude

-- Static reusable vector offsets for top/bottom character projection
local OFFSET_TOP = Vector3.new(0, 3, 0)
local OFFSET_BOTTOM = Vector3.new(0, -3.5, 0)

-- Helper: Fast group setting resolver
local function getSetting(group, key)
	local groups = ESPConfig.Groups
	local groupCfg = groups[group]
	if groupCfg and groupCfg[key] ~= nil then
		return groupCfg[key]
	end

	local defaultGroup = groups.Default
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
		end
	end

	if instance:IsA("Player") then
		return "Player"
	end
	return "Anything"
end

-- ============================================================
-- Group Registration
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
-- Bars Construction
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

local function RefreshGroup(instance)
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
-- Target Construction
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
				return override and tostring(override) or instance.Name
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
-- Drawing Creation & Destruction
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
	if instance == LocalPlayer or ESPObjects[instance] then
		return
	end

	local target = makeTarget(instance, groupOverride)
	if not target or target.IsLocal then
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

-- Fast validation check
local function isValidCharacter(target)
	local model = target.GetModel()
	if not model or not model.Parent then
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart")

	if not root then
		return nil
	end
	if humanoid and humanoid.Health <= 0 then
		return nil
	end

	return model, root, humanoid
end

-- ============================================================
-- Zero-Allocation Box Drawing
-- ============================================================

local function drawBox(drawings, group, x, y, w, h)
	local box = drawings.Box
	local color = getSetting(group, "BoxColor")
	local thickness = getSetting(group, "BoxThickness")
	local transparency = getSetting(group, "BoxTransparency")
	local wantedStyle = getSetting(group, "BoxStyle")

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

		-- Direct assignment (Zero Table Allocations)
		local x2, y2 = x + w, y + h
		local bx, by = x + off, y - off
		local bx2, by2 = x2 + off, y2 - off

		local l = lines
		l[1].From, l[1].To = Vector2.new(x, y), Vector2.new(x2, y)
		l[2].From, l[2].To = Vector2.new(x2, y), Vector2.new(x2, y2)
		l[3].From, l[3].To = Vector2.new(x2, y2), Vector2.new(x, y2)
		l[4].From, l[4].To = Vector2.new(x, y2), Vector2.new(x, y)

		l[5].From, l[5].To = Vector2.new(bx, by), Vector2.new(bx2, by)
		l[6].From, l[6].To = Vector2.new(bx2, by), Vector2.new(bx2, by2)
		l[7].From, l[7].To = Vector2.new(bx2, by2), Vector2.new(bx, by2)
		l[8].From, l[8].To = Vector2.new(bx, by2), Vector2.new(bx, by)

		l[9].From, l[9].To = Vector2.new(x, y), Vector2.new(bx, by)
		l[10].From, l[10].To = Vector2.new(x2, y), Vector2.new(bx2, by)
		l[11].From, l[11].To = Vector2.new(x2, y2), Vector2.new(bx2, by2)
		l[12].From, l[12].To = Vector2.new(x, y2), Vector2.new(bx, by2)

		for i = 1, 12 do
			l[i].Color = color
			l[i].Thickness = thickness
			l[i].Transparency = transparency
			l[i].Visible = true
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
-- Per-Frame Update Logic
-- ============================================================

local function hideESP(drawings)
	hideBoxDrawings(drawings.Box)
	drawings.Name.Visible = false
	for _, barDrawings in pairs(drawings.Bars) do
		barDrawings.Outline.Visible = false
		barDrawings.Fill.Visible = false
	end
end

local function updateTarget(instance, drawings)
	local target = drawings.Target
	local group = target.Group

	if target.NeedsRefresh then
		target.NeedsRefresh = false
		RefreshGroup(instance)
		group = drawings.Target.Group
	end

	local char, root, humanoid = isValidCharacter(target)
	if not char then
		hideESP(drawings)
		return
	end

	local rootPos = root.Position
	local camPos = Camera.CFrame.Position
	local distance = (camPos - rootPos).Magnitude

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
	if getSetting(group, "TeamCheck") and LocalPlayer.Team ~= nil and target.GetTeam() == LocalPlayer.Team then
		hideESP(drawings)
		return
	end

	-- Occlusion Check (using static params)
	if getSetting(group, "OcclusionCheck") then
		SharedRaycastParams.FilterDescendantsInstances = { char, LocalPlayer.Character }
		local result = Workspace:Raycast(camPos, rootPos - camPos, SharedRaycastParams)
		if result then
			hideESP(drawings)
			return
		end
	end

	-- Fast 2D Projection: Project top and bottom of character
	local screenPoint, onScreen = Camera:WorldToViewportPoint(rootPos)
	if not onScreen or screenPoint.Z <= 0 then
		hideESP(drawings)
		return
	end

	local top2D = Camera:WorldToViewportPoint(rootPos + OFFSET_TOP)
	local bottom2D = Camera:WorldToViewportPoint(rootPos + OFFSET_BOTTOM)

	local height = math.abs(bottom2D.Y - top2D.Y)
	local width = height * 0.6

	local boxX = screenPoint.X - width * 0.5
	local boxY = screenPoint.Y - height * 0.5

	-- Render Box
	if getSetting(group, "ShowBox") then
		drawBox(drawings, group, boxX, boxY, width, height)
	else
		hideBoxDrawings(drawings.Box)
	end

	-- Render Bars
	if getSetting(group, "ShowBars") then
		local scale = math.clamp(height / 90, 0.2, 1.5)
		local leftOffset = math.max(1, math.floor(4 * scale))
		local rightOffset = math.max(1, math.floor(4 * scale))
		local bottomOffset = math.max(1, math.floor(4 * scale))
		local barSpacing = math.max(1, math.floor(2 * scale))

		for _, barDef in ipairs(CustomBars) do
			local barDrawings = drawings.Bars[barDef.Name]
			if barDrawings then
				local ok, curVal, maxVal = pcall(barDef.GetValue, char, instance)
				if not ok then
					curVal, maxVal = 0, 100
				end
				maxVal = (maxVal and maxVal > 0) and maxVal or 100
				local ratio = math.clamp((curVal or 0) / maxVal, 0, 1)

				local barWidth = math.max(1, math.floor((barDef.Width or 2) * scale))

				if barDef.Side == "Right" then
					local barX = boxX + width + rightOffset
					rightOffset += barWidth + barSpacing + 2
					barDrawings.Outline.Position = Vector2.new(barX - 1, boxY - 1)
					barDrawings.Outline.Size = Vector2.new(barWidth + 2, height + 2)
					local barHeight = math.clamp(math.floor(height * ratio), 0, height)
					barDrawings.Fill.Position = Vector2.new(barX, boxY + (height - barHeight))
					barDrawings.Fill.Size = Vector2.new(barWidth, barHeight)
				elseif barDef.Side == "Bottom" then
					local barY = boxY + height + bottomOffset
					bottomOffset += barWidth + barSpacing + 2
					barDrawings.Outline.Position = Vector2.new(boxX - 1, barY - 1)
					barDrawings.Outline.Size = Vector2.new(width + 2, barWidth + 2)
					local fillWidth = math.clamp(math.floor(width * ratio), 0, width)
					barDrawings.Fill.Position = Vector2.new(boxX, barY)
					barDrawings.Fill.Size = Vector2.new(fillWidth, barWidth)
				else
					leftOffset += barWidth
					local barX = boxX - leftOffset
					leftOffset += barSpacing + 2
					barDrawings.Outline.Position = Vector2.new(barX - 1, boxY - 1)
					barDrawings.Outline.Size = Vector2.new(barWidth + 2, height + 2)
					local barHeight = math.clamp(math.floor(height * ratio), 0, height)
					barDrawings.Fill.Position = Vector2.new(barX, boxY + (height - barHeight))
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

	-- Render Text (Optimized string generation)
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
			local textStr = ""
			if showName then
				textStr = target.GetName()
			end
			if showDist then
				textStr = (textStr ~= "" and (textStr .. " ") or "") .. "[" .. math.floor(distance) .. "m]"
			end
			if showHealth and humanoid and humanoid.MaxHealth > 0 then
				local hp = math.floor((humanoid.Health / humanoid.MaxHealth) * 100)
				textStr = (textStr ~= "" and (textStr .. " ") or "") .. "[" .. hp .. "%]"
			end
			finalText = textStr
		end

		if #finalText > 0 then
			local textSize = getSetting(group, "TextSize")
			drawings.Name.Text = finalText
			drawings.Name.Color = getSetting(group, "TextColor")
			drawings.Name.Size = textSize
			drawings.Name.Position = Vector2.new(screenPoint.X, boxY - textSize - 4)
			drawings.Name.Visible = true
		else
			drawings.Name.Visible = false
		end
	else
		drawings.Name.Visible = false
	end
end

-- ============================================================
-- Render Loop (30 FPS Cap)
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
		updateTarget(instance, drawings)
	end
end)

-- Camera update listener
table.insert(
	Connections,
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		Camera = Workspace.CurrentCamera
	end)
)

-- ============================================================
-- Bar API & Unload
-- ============================================================
local function NewBar(args)
	assert(type(args) == "table", "NewBar expects a table of arguments")
	assert(args.Name, "Bar must have a unique 'Name'")
	assert(type(args.GetValue) == "function", "Bar must provide a 'GetValue(char, instance)' function")

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
