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

	-- Toggles (text)
	ShowName = true,
	UseDisplayName = true,
	ShowDistance = true,
	TeamCheck = false,
}

local ESPObjects = {} -- [Instance] = drawings
local CustomBars = {} -- Stores bar blueprints registered via ESP:NewBar
local MobConns = {} -- Connections for the mob folder

-- Helper: Destroy a drawing safely
local function safeDestroy(drawing)
	if drawing then
		drawing.Visible = false
		local destroyFn = drawing.Destroy or drawing.Remove
		if destroyFn then
			destroyFn(drawing)
		end
	end
end

-- Helper: Instantiates a single bar's drawing primitives for one target
local function createBarForPlayer(playerDrawings, barDef)
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

-- Adapter: turn any Instance into a uniform "target" object
local function makeTarget(instance)
	if instance:IsA("Player") then
		return {
			Instance = instance,
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

local function createESP(instance)
	if instance == LocalPlayer then
		return
	end
	if ESPObjects[instance] then
		return
	end -- already tracked

	local target = makeTarget(instance)
	if not target then
		return
	end

	local drawings = {
		Box = Drawing.new("Square"),
		Name = Drawing.new("Text"),
		Bars = {}, -- Holds all dynamic bars for this target
		Target = target, -- The adapter, used by the render loop
	}

	-- Configure Box
	drawings.Box.Visible = false
	drawings.Box.Color = ESPConfig.BoxColor
	drawings.Box.Thickness = 1
	drawings.Box.Filled = false
	drawings.Box.Transparency = 1
	drawings.Box.ZIndex = 2

	-- Configure Name / Info Text
	drawings.Name.Visible = false
	drawings.Name.Color = ESPConfig.TextColor
	drawings.Name.Size = ESPConfig.TextSize
	drawings.Name.Center = true
	drawings.Name.Outline = true
	drawings.Name.OutlineColor = Color3.fromRGB(0, 0, 0)
	drawings.Name.ZIndex = 4

	-- Build primitives for any bars registered before this target existed
	for _, barDef in ipairs(CustomBars) do
		createBarForPlayer(drawings, barDef)
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

-- Helper: Check if character is alive and valid (works for players AND mobs)
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

-- Helper: Hide all primitives for a target
local function hideESP(drawings)
	drawings.Box.Visible = false
	drawings.Name.Visible = false
	for _, barDrawings in pairs(drawings.Bars) do
		barDrawings.Outline.Visible = false
		barDrawings.Fill.Visible = false
	end
end

-- Main Render Loop
local renderConnection
renderConnection = RunService.RenderStepped:Connect(function()
	if not ESPConfig.Enabled then
		for _, drawings in pairs(ESPObjects) do
			hideESP(drawings)
		end
		return
	end

	for instance, drawings in pairs(ESPObjects) do
		local target = drawings.Target
		local char, root, humanoid = isValidCharacter(target)

		local isTeammate = ESPConfig.TeamCheck and LocalPlayer.Team ~= nil and target.GetTeam() == LocalPlayer.Team

		if char and not isTeammate then
			local rootPos, onScreen = Camera:WorldToViewportPoint(root.Position)

			if onScreen then
				local headPos = Camera:WorldToViewportPoint(root.Position + Vector3.new(0, 2.5, 0))
				local legPos = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3.5, 0))

				if headPos.Z > 0 and legPos.Z > 0 then
					local height = math.abs(headPos.Y - legPos.Y)
					local width = height / 1.6

					local boxX = rootPos.X - (width / 2)
					local boxY = math.min(headPos.Y, legPos.Y)

					-- 1. Update Box
					drawings.Box.Size = Vector2.new(width, height)
					drawings.Box.Position = Vector2.new(boxX, boxY)
					drawings.Box.Color = ESPConfig.BoxColor
					drawings.Box.Visible = true

					-- 2. Update Dynamic Bars (Automatic side-stacking)
					local leftOffset = 4
					local rightOffset = 4
					local bottomOffset = 4
					local barSpacing = 2

					for _, barDef in ipairs(CustomBars) do
						local barDrawings = drawings.Bars[barDef.Name]
						if barDrawings then
							-- Pass raw instance so bar authors can branch on Player vs Model
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

							if barDef.LerpColor then
								barDrawings.Fill.Color = Color3.fromRGB(255, 0, 0)
									:Lerp(Color3.fromRGB(0, 255, 0), ratio)
							else
								barDrawings.Fill.Color = barDef.Color or Color3.fromRGB(0, 255, 0)
							end

							barDrawings.Outline.Visible = true
							barDrawings.Fill.Visible = (ratio > 0)
						end
					end

					-- 3. Build Dynamic Text
					local textParts = {}

					if ESPConfig.ShowName then
						table.insert(textParts, target.GetName())
					end

					if ESPConfig.ShowDistance then
						local distance = math.floor((Camera.CFrame.Position - root.Position).Magnitude)
						table.insert(textParts, `[{distance}m]`)
					end

					local finalText = table.concat(textParts, " ")

					if #finalText > 0 then
						drawings.Name.Text = finalText
						drawings.Name.Color = ESPConfig.TextColor
						drawings.Name.Size = ESPConfig.TextSize
						drawings.Name.Position = Vector2.new(rootPos.X, boxY - drawings.Name.Size - 4)
						drawings.Name.Visible = true
					else
						drawings.Name.Visible = false
					end
				else
					hideESP(drawings)
				end
			else
				hideESP(drawings)
			end
		else
			hideESP(drawings)
		end
	end
end)

-- Define the unload function
local function unload()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	for instance, _ in pairs(ESPObjects) do
		removeESP(instance)
	end
end

-- Function to register a new bar
local function NewBar(_, args)
	assert(type(args) == "table", "NewBar expects a table of arguments")
	assert(args.Name, "Bar must have a unique 'Name'")
	assert(type(args.GetValue) == "function", "Bar must provide a 'GetValue(char, instance)' function")

	local barDef = {
		Name = args.Name,
		Side = args.Side or "Left", -- "Left", "Right", or "Bottom"
		Width = args.Width or 2,
		Color = args.Color or Color3.fromRGB(0, 255, 0),
		LerpColor = args.LerpColor or false,
		GetValue = args.GetValue,
	}

	table.insert(CustomBars, barDef)

	-- Immediately create drawing objects for targets already tracked
	for _, drawings in pairs(ESPObjects) do
		if not drawings.Bars[barDef.Name] then
			createBarForPlayer(drawings, barDef)
		end
	end

	-- Return handle to allow removing this bar later
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

-- Return the module table
-- Public API
return {
	Config = ESPConfig,
	Objects = ESPObjects,
	NewBar = NewBar,
	Track = createESP,
	Untrack = removeESP,
	Unload = unload,
}
