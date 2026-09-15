-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- Configuration
local ESPConfig = {
	Enabled = true,
	BoxColor = Color3.fromRGB(255, 255, 255),
	TextColor = Color3.fromRGB(255, 255, 255),
	TextSize = 14,

	ShowBox = true,
	ShowName = true,
	UseDisplayName = true,
	ShowDistance = true,
	ShowBars = true,
	ShowHealth = true,
	TeamCheck = false,
	BarColor = Color3.fromRGB(0, 255, 0),

	Groups = {},
}

local ESPObjects = {}
local CustomBars = {}
local GroupClassifiers = {}

local function getSetting(group, key)
	local groupCfg = ESPConfig.Groups[group]
	if groupCfg and groupCfg[key] ~= nil then
		return groupCfg[key]
	end
	return ESPConfig[key]
end

local function safeDestroy(drawing)
	if drawing then
		drawing.Visible = false
		local destroyFn = drawing.Destroy or drawing.Remove
		if destroyFn then
			destroyFn(drawing)
		end
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

local function RegisterGroup(selfOrName, nameOrPredicate, predicateOrAtFront, atFront)
	local name, predicate
	if type(selfOrName) == "table" then
		name, predicate = nameOrPredicate, predicateOrAtFront
	else
		name, predicate, atFront = selfOrName, nameOrPredicate, predicateOrAtFront
	end

	assert(type(name) == "string", "Group name must be a string")
	assert(type(predicate) == "function", "predicate must be function(instance) -> boolean")

	for i, c in ipairs(GroupClassifiers) do
		if c.Name == name then
			if atFront then
				table.remove(GroupClassifiers, i)
				break
			else
				c.Predicate = predicate
				return
			end
		end
	end

	if atFront then
		table.insert(GroupClassifiers, 1, { Name = name, Predicate = predicate })
	else
		table.insert(GroupClassifiers, { Name = name, Predicate = predicate })
	end
end

local function UnregisterGroup(selfOrName, name)
	if type(selfOrName) ~= "table" then
		name = selfOrName
	end

	for i, c in ipairs(GroupClassifiers) do
		if c.Name == name then
			table.remove(GroupClassifiers, i)
			return true
		end
	end
	return false
end

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
	}
end

local RefreshGroup
RefreshGroup = function(_, instance)
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

local function makeTarget(instance, groupOverride)
	if instance:IsA("Player") then
		return {
			Instance = instance,
			Group = groupOverride or resolveGroup(instance),
			GetModel = function()
				return instance.Character
			end,
			GetName = function()
				return ESPConfig.UseDisplayName and instance.DisplayName or ("@" .. instance.Name)
			end,
			GetTeam = function()
				return instance.Team
			end,
		}
	elseif instance:IsA("Model") then
		return {
			Instance = instance,
			Group = groupOverride or resolveGroup(instance),
			GetModel = function()
				return instance
			end,
			GetName = function()
				return instance.Name
			end,
			GetTeam = function()
				return nil
			end,
		}
	end
	return nil
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

	local drawings = {
		Box = Drawing.new("Square"),
		Name = Drawing.new("Text"),
		Bars = {},
		Target = target,
	}

	drawings.Box.Visible = false
	drawings.Box.Color = getSetting(target.Group, "BoxColor")
	drawings.Box.Thickness = 1
	drawings.Box.Filled = false
	drawings.Box.Transparency = 1
	drawings.Box.ZIndex = 2

	drawings.Name.Visible = false
	drawings.Name.Color = getSetting(target.Group, "TextColor")
	drawings.Name.Size = ESPConfig.TextSize
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

	safeDestroy(drawings.Box)
	safeDestroy(drawings.Name)

	for _, barDrawings in pairs(drawings.Bars) do
		safeDestroy(barDrawings.Outline)
		safeDestroy(barDrawings.Fill)
	end

	ESPObjects[instance] = nil
end

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

local function hideESP(drawings)
	drawings.Box.Visible = false
	drawings.Name.Visible = false
	for _, barDrawings in pairs(drawings.Bars) do
		barDrawings.Outline.Visible = false
		barDrawings.Fill.Visible = false
	end
end

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	Camera = Workspace.CurrentCamera
end)

local function updateTarget(instance, drawings)
	local target = drawings.Target
	local group = target.Group
	local char, root = isValidCharacter(target)

	local isTeammate = ESPConfig.TeamCheck and LocalPlayer.Team ~= nil and target.GetTeam() == LocalPlayer.Team

	if not char or isTeammate then
		hideESP(drawings)
		return
	end

	local rootPos, onScreen = Camera:WorldToViewportPoint(root.Position)
	if not onScreen then
		hideESP(drawings)
		return
	end

	local headPos = Camera:WorldToViewportPoint(root.Position + Vector3.new(0, 2.5, 0))
	local legPos = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3.5, 0))

	if not (headPos.Z > 0 and legPos.Z > 0) then
		hideESP(drawings)
		return
	end

	local height = math.abs(headPos.Y - legPos.Y)
	local width = height / 1.6

	local boxX = rootPos.X - (width / 2)
	local boxY = math.min(headPos.Y, legPos.Y)

	if getSetting(group, "ShowBox") then
		drawings.Box.Size = Vector2.new(width, height)
		drawings.Box.Position = Vector2.new(boxX, boxY)
		drawings.Box.Color = getSetting(group, "BoxColor")
		drawings.Box.Visible = true
	else
		drawings.Box.Visible = false
	end

	if getSetting(group, "ShowBars") and getSetting(group, "ShowHealth") ~= false then
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
				elseif barDef.Side == "Left" then
					leftOffset = leftOffset + barWidth
					local barX = boxX - leftOffset
					leftOffset = leftOffset + barSpacing + 2

					barDrawings.Outline.Position = Vector2.new(barX - 1, boxY - 1)
					barDrawings.Outline.Size = Vector2.new(barWidth + 2, height + 2)

					local barHeight = math.floor(height * ratio)
					barDrawings.Fill.Position = Vector2.new(barX, boxY + (height - barHeight))
					barDrawings.Fill.Size = Vector2.new(barWidth, barHeight)
				end

				local groupBarColor = getSetting(group, "BarColor")
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

	if getSetting(group, "ShowName") or getSetting(group, "ShowDistance") then
		local textParts = {}

		if getSetting(group, "ShowName") then
			table.insert(textParts, target.GetName())
		end

		if getSetting(group, "ShowDistance") then
			local distance = math.floor((Camera.CFrame.Position - root.Position).Magnitude)
			table.insert(textParts, `[{distance}m]`)
		end

		local finalText = table.concat(textParts, " ")

		if #finalText > 0 then
			drawings.Name.Text = finalText
			drawings.Name.Color = getSetting(group, "TextColor")
			drawings.Name.Size = ESPConfig.TextSize
			drawings.Name.Position = Vector2.new(rootPos.X, boxY - drawings.Name.Size - 4)
			drawings.Name.Visible = true
		else
			drawings.Name.Visible = false
		end
	else
		drawings.Name.Visible = false
	end
end

local renderConnection
renderConnection = RunService.RenderStepped:Connect(function()
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

local function unload()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	for instance, _ in pairs(ESPObjects) do
		removeESP(instance)
	end

	table.clear(CustomBars)
	table.clear(GroupClassifiers)
end

local function NewBar(selfOrArgs, args)
	if args == nil then
		args = selfOrArgs
	end

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

	return {
		Remove = function()
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
		end,
	}
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
