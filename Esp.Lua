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
	-- FIX: Transparency semantics: 0 = opaque, 1 = invisible.
	-- Original default of 1 made the box invisible by default.
	BoxTransparency = 0,
	CornerLength = 0.25, -- fraction of box side, for "Corners"
	MaxDistance = math.huge, -- studs; hide beyond this
	TeamCheck = false,
	ShowBox = true,
	ShowName = true,
	ShowDistance = true,
	UseDisplayName = true,
	ShowBars = true,
	BarColor = nil, -- nil = use per-bar Color / LerpColor
	OcclusionCheck = false, -- raycast from camera to root
	Padding = 0, -- extra pixels around box

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
-- RefreshGroup (FIX: moved above Register/Unregister so the
-- local is in scope when those functions capture it)
-- ============================================================

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
			-- FIX: createBarForPlayer is defined below; forward-declare it.
			if createBarForPlayer then
				createBarForPlayer(drawings, barDef, newGroup)
			end
		elseif not applies and existing then
			safeDestroy(existing.Outline)
			safeDestroy(existing.Fill)
			drawings.Bars[barDef.Name] = nil
		end
	end
end

-- ============================================================
-- Group registration
-- ============================================================

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
				-- Refresh existing targets so the new predicate takes effect
				for instance in pairs(ESPObjects) do
					ESPObjects[instance].Target.NeedsRefresh = true
				end
				return
			end
		end
	end

	if atFront then
		table.insert(GroupClassifiers, 1, { Name = name, Predicate = predicate })
	else
		table.insert(GroupClassifiers, { Name = name, Predicate = predicate })
	end

	-- Refresh existing targets
	for instance in pairs(ESPObjects) do
		ESPObjects[instance].Target.NeedsRefresh = true
	end
end

local function UnregisterGroup(name)
	for i, c in ipairs(GroupClassifiers) do
		if c.Name == name then
			table.remove(GroupClassifiers, i)
			for instance in pairs(ESPObjects) do
				ESPObjects[instance].Target.NeedsRefresh = true
			end
			return true
		end
	end
	return false
end

-- ============================================================
-- Bars
-- ============================================================

-- FIX: forward declaration so RefreshGroup (defined above) can call this.
createBarForPlayer = function(playerDrawings, barDef, group)
	if barDef.Groups and not table.find(barDef.Groups, group) then
		return
	end

	local outline = Drawing.new("Square")
	outline.Visible = false
	outline.Color = Color3.fromRGB(0, 0, 0)
	outline.Thickness = 1
	outline.Filled = true
	-- FIX: outline transparency also follows 0=opaque semantics.
	outline.Transparency = 0.2
	outline.ZIndex = 2

	local fill = Drawing.new("Square")
	fill.Visible = false
	fill.Color = barDef.Color or Color3.fromRGB(0, 255, 0)
	fill.Thickness = 1
	fill.Filled = true
	fill.Transparency = 0
	fill.ZIndex = 3

	playerDrawings.Bars[barDef.Name] = {
		Outline = outline,
		Fill = fill,
		Def = barDef,
	}
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
				-- Optional: allow attribute override on the model
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
			line.Transparency = 0
			line.ZIndex = 2
		end
	elseif style == "3D" then
		-- 12 lines of a wireframe box
		d.Lines = {}
		for i = 1, 12 do
			local line = Drawing.new("Line")
			line.Visible = false
			line.Thickness = 1
			line.Transparency = 0
			line.ZIndex = 2
			d.Lines[i] = line
		end
	else
		-- Square or Filled both use a single Square
		d.Square = Drawing.new("Square")
		d.Square.Visible = false
		d.Square.Thickness = 1
		d.Square.Filled = (style == "Filled")
		-- FIX: default transparency, actual value is set per-frame from config.
		d.Square.Transparency = (style == "Filled") and 0.5 or 0
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

local function isValidCharacter(target)
	local model = target.GetModel()
	if not model then
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart")

	if root and (not humanoid or humanoid.Health > 0) then
		return model, root, humanoid
	end
	return nil
end

-- Get world-space CFrame + size for the model's bounding box.
-- Returns: cf, size (Vector3s) or nil if it can't be computed.
local function getWorldBoundingBox(model)
	local ok, cf, size = pcall(function()
		return model:GetBoundingBox()
	end)

	if ok and cf and size then
		return cf, size
	end

	-- Fallback: use PrimaryPart / extents
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not primary then
		return nil
	end
	local ok2, size2 = pcall(function()
		return model:GetExtentsSize()
	end)
	if not ok2 then
		return nil
	end
	return primary.CFrame, size2
end

-- Project the 8 corners of an oriented box into screen space.
-- Returns: minX, minY, maxX, maxY, or nil if all corners are behind camera.
local function projectBox(cf, size)
	local half = size * 0.5
	local corners = {
		cf * Vector3.new(-half.X, -half.Y, -half.Z),
		cf * Vector3.new(half.X, -half.Y, -half.Z),
		cf * Vector3.new(-half.X, half.Y, -half.Z),
		cf * Vector3.new(half.X, half.Y, -half.Z),
		cf * Vector3.new(-half.X, -half.Y, half.Z),
		cf * Vector3.new(half.X, -half.Y, half.Z),
		cf * Vector3.new(-half.X, half.Y, half.Z),
		cf * Vector3.new(half.X, half.Y, half.Z),
	}

	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge
	local anyFront = false

	for _, worldPos in ipairs(corners) do
		local sp = Camera:WorldToViewportPoint(worldPos)
		if sp.Z > 0 then
			anyFront = true
			if sp.X < minX then
				minX = sp.X
			end
			if sp.Y < minY then
				minY = sp.Y
			end
			if sp.X > maxX then
				maxX = sp.X
			end
			if sp.Y > maxY then
				maxY = sp.Y
			end
		end
	end

	if not anyFront then
		return nil
	end
	return minX, minY, maxX, maxY
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
		-- FIX: The original "3D" style was a fixed 2D offset (always the
		-- same regardless of camera angle). This version projects the
		-- model's actual 8 corners and connects them, giving a real
		-- 3D wireframe. The corners are passed in via `drawings.Box.ProjectedCorners`
		-- (set below in updateTarget) to avoid recomputing here.
		local corners = box.ProjectedCorners
		local lines = box.Lines

		if corners then
			-- Corner order matches projectBox's ordering:
			-- 1..4 = back face (z = -half), 5..8 = front face (z = +half)
			-- (1,2,3,4) form back quad, (5,6,7,8) form front quad.
			local edges = {
				{ 1, 2 },
				{ 2, 4 },
				{ 4, 3 },
				{ 3, 1 }, -- back
				{ 5, 6 },
				{ 6, 8 },
				{ 8, 7 },
				{ 7, 5 }, -- front
				{ 1, 5 },
				{ 2, 6 },
				{ 3, 7 },
				{ 4, 8 }, -- connectors
			}
			for i = 1, 12 do
				local line = lines[i]
				local e = edges[i]
				local a = corners[e[1]]
				local b = corners[e[2]]
				if a and b then
					line.From = a
					line.To = b
					line.Color = color
					line.Thickness = thickness
					line.Transparency = transparency
					line.Visible = true
				else
					line.Visible = false
				end
			end
		else
			-- Fallback: draw a flat 2D box if corners weren't provided
			local off = 4
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
		end
	else
		-- Square or Filled
		box.Square.Size = Vector2.new(w, h)
		box.Square.Position = Vector2.new(x, y)
		box.Square.Color = color
		box.Square.Thickness = thickness
		-- FIX: Filled style now respects the configured transparency.
		-- If you want a hardcoded softer fill, set BoxTransparency per group.
		box.Square.Transparency = transparency
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

local function updateTarget(instance, drawings)
	local target = drawings.Target
	local group = target.Group

	-- Group refresh if requested
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

	-- Distance check
	local distance = (Camera.CFrame.Position - root.Position).Magnitude
	local maxDist = getSetting(group, "MaxDistance")
	if maxDist and distance > maxDist then
		hideESP(drawings)
		return
	end

	-- FIX: TeamCheck guard. Previously, if both the local player and the
	-- target had no team (nil == nil), they were treated as teammates and
	-- hidden. Now we require the target to actually have a team.
	local teamCheckEnabled = getSetting(group, "TeamCheck")
	local isTeammate = false
	if teamCheckEnabled and LocalPlayer.Team ~= nil then
		local targetTeam = target.GetTeam()
		isTeammate = (targetTeam ~= nil) and (targetTeam == LocalPlayer.Team)
	end
	if isTeammate then
		hideESP(drawings)
		return
	end

	-- Occlusion check (optional)
	if getSetting(group, "OcclusionCheck") then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char, LocalPlayer.Character }
		local result = Workspace:Raycast(Camera.CFrame.Position, root.Position - Camera.CFrame.Position, params)
		if result then
			hideESP(drawings)
			return
		end
	end

	-- Bounding box projection
	local cf, size = getWorldBoundingBox(char)
	if not cf then
		hideESP(drawings)
		return
	end

	local minX, minY, maxX, maxY = projectBox(cf, size)
	if not minX then
		hideESP(drawings)
		return
	end

	local pad = getSetting(group, "Padding") or 0
	minX = minX - pad
	minY = minY - pad
	maxX = maxX + pad
	maxY = maxY + pad

	local boxX, boxY = minX, minY
	local width = math.max(maxX - minX, 1)
	local height = math.max(maxY - minY, 1)

	-- FIX: For the real "3D" style, compute projected corners once and
	-- stash them on the drawings so drawBox can use them.
	if getSetting(group, "BoxStyle") == "3D" then
		local half = size * 0.5
		local worldCorners = {
			cf * Vector3.new(-half.X, -half.Y, -half.Z),
			cf * Vector3.new(half.X, -half.Y, -half.Z),
			cf * Vector3.new(-half.X, half.Y, -half.Z),
			cf * Vector3.new(half.X, half.Y, -half.Z),
			cf * Vector3.new(-half.X, -half.Y, half.Z),
			cf * Vector3.new(half.X, -half.Y, half.Z),
			cf * Vector3.new(-half.X, half.Y, half.Z),
			cf * Vector3.new(half.X, half.Y, half.Z),
		}
		local projected = {}
		for i, wp in ipairs(worldCorners) do
			local sp = Camera:WorldToViewportPoint(wp)
			if sp.Z > 0 then
				projected[i] = Vector2.new(sp.X, sp.Y)
			end
		end
		drawings.Box.ProjectedCorners = projected
	end

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

		for _, barDef in ipairs(CustomBars) do
			local barDrawings = drawings.Bars[barDef.Name]
			if barDrawings then
				local curVal, maxVal = barDef.GetValue(char, instance)
				maxVal = (maxVal and maxVal > 0) and maxVal or 100
				local ratio = math.clamp((curVal or 0) / maxVal, 0, 1)
				local barWidth = barDef.Width or 2

				if barDef.Side == "Right" then
					local barX = boxX + width + rightOffset
					rightOffset = rightOffset + barWidth + barSpacing + 2

					barDrawings.Outline.Position = Vector2.new(barX - 1, boxY - 1)
					barDrawings.Outline.Size = Vector2.new(barWidth + 2, height + 2)

					local barHeight = math.floor(height * ratio)
					barDrawings.Fill.Position = Vector2.new(barX, boxY + (height - barHeight))
					barDrawings.Fill.Size = Vector2.new(barWidth, barHeight)
				elseif barDef.Side == "Bottom" then
					local barY = boxY + height + bottomOffset
					bottomOffset = bottomOffset + barWidth + barSpacing + 2

					barDrawings.Outline.Position = Vector2.new(boxX - 1, barY - 1)
					barDrawings.Outline.Size = Vector2.new(width + 2, barWidth + 2)

					local fillWidth = math.floor(width * ratio)
					barDrawings.Fill.Position = Vector2.new(boxX, barY)
					barDrawings.Fill.Size = Vector2.new(fillWidth, barWidth)
				else -- "Left"
					leftOffset = leftOffset + barWidth
					local barX = boxX - leftOffset
					leftOffset = leftOffset + barSpacing + 2

					barDrawings.Outline.Position = Vector2.new(barX - 1, boxY - 1)
					barDrawings.Outline.Size = Vector2.new(barWidth + 2, height + 2)

					local barHeight = math.floor(height * ratio)
					barDrawings.Fill.Position = Vector2.new(barX, boxY + (height - barHeight))
					barDrawings.Fill.Size = Vector2.new(barWidth, barHeight)
				end

				-- Color: per-group BarColor > per-bar Color/Lerp > default
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

	-- Text label
	local showName = getSetting(group, "ShowName")
	local showDist = getSetting(group, "ShowDistance")

	if showName or showDist then
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
			finalText = table.concat(parts, " ")
		end

		if #finalText > 0 then
			local textSize = getSetting(group, "TextSize")
			drawings.Name.Text = finalText
			drawings.Name.Color = getSetting(group, "TextColor")
			drawings.Name.Size = textSize
			drawings.Name.Position = Vector2.new((minX + maxX) / 2, boxY - textSize - 4)
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

local renderConnection = RunService.RenderStepped:Connect(function()
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
-- Camera change connection (tracked for cleanup)
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
		if handle.Removed then
			return
		end
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

	-- Collect keys first to avoid mutating the table during iteration
	local toRemove = {}
	for instance in pairs(ESPObjects) do
		table.insert(toRemove, instance)
	end
	for _, instance in ipairs(toRemove) do
		removeESP(instance)
	end

	table.clear(CustomBars)
	table.clear(GroupClassifiers)

	-- FIX: Reset config groups so a re-init starts clean.
	-- (Comment this out if you want config to persist across unload/reload.)
	ESPConfig.Groups = {}
	ESPConfig.Defaults = {}
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
