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

	-- Health Bar Settings
	ShowHealthBar = true,
	HealthBarSide = "Left", -- Options: "Left" or "Right"
	HealthBarWidth = 2, -- Bar thickness in pixels
	HealthBarOffset = 4, -- Distance away from bounding box in pixels
	HealthBarLerpColor = true, -- True: Red -> Yellow -> Green gradient; False: solid green
	HealthBarColor = Color3.fromRGB(0, 255, 0), -- Fallback if lerp is false

	-- Toggles
	ShowName = true,
	UseDisplayName = true,
	ShowDistance = true,
	ShowHealth = true, -- Header text percentage
	TeamCheck = false,
}

-- Storage table for player ESP objects
local ESPObjects = {}

-- Function to create Drawing primitives for a player
local function createESP(player)
	if player == LocalPlayer then
		return
	end

	local drawings = {
		Box = Drawing.new("Square"),
		Name = Drawing.new("Text"),
		HealthBarOutline = Drawing.new("Square"),
		HealthBar = Drawing.new("Square"),
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

	-- Configure Health Bar Outline (Dark border/background)
	drawings.HealthBarOutline.Visible = false
	drawings.HealthBarOutline.Color = Color3.fromRGB(0, 0, 0) -- Fixed: was RGB(255, 254, 254)
	drawings.HealthBarOutline.Thickness = 1
	drawings.HealthBarOutline.Filled = true
	drawings.HealthBarOutline.Transparency = 0.8
	drawings.HealthBarOutline.ZIndex = 2
	-- hello
	-- Configure Health Bar Fill
	drawings.HealthBar.Visible = false
	drawings.HealthBar.Color = Color3.fromRGB(0, 255, 0)
	drawings.HealthBar.Thickness = 1
	drawings.HealthBar.Filled = true
	drawings.HealthBar.Transparency = 1
	drawings.HealthBar.ZIndex = 3

	ESPObjects[player] = drawings
end

-- Cleanup function to destroy Drawing objects and avoid memory leaks
local function removeESP(player)
	if ESPObjects[player] then
		for _, drawing in pairs(ESPObjects[player]) do
			drawing.Visible = false
			drawing:Destroy()
		end
		ESPObjects[player] = nil
	end
end

-- Helper: Check if character is alive and valid
local function isValidCharacter(player)
	local char = player.Character
	if not char then
		return nil
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")

	if humanoid and root and humanoid.Health > 0 then
		return char, root, humanoid
	end
	return nil
end

-- Helper: Hide all primitives for a player
local function hideESP(drawings)
	drawings.Box.Visible = false
	drawings.Name.Visible = false
	drawings.HealthBarOutline.Visible = false
	drawings.HealthBar.Visible = false
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

	for player, drawings in pairs(ESPObjects) do
		local char, root, humanoid = isValidCharacter(player)
		local isTeammate = ESPConfig.TeamCheck and (LocalPlayer.Team ~= nil and player.Team == LocalPlayer.Team)

		if char and not isTeammate then
			local rootPos, onScreen = Camera:WorldToViewportPoint(root.Position)

			if onScreen then
				local headPos = Camera:WorldToViewportPoint(root.Position + Vector3.new(0, 2.5, 0))
				local legPos = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3.5, 0))

				-- Prevent inverted coordinates when near camera clip plane
				if headPos.Z > 0 and legPos.Z > 0 then
					local height = math.abs(headPos.Y - legPos.Y)
					local width = height / 1.6

					local boxX = rootPos.X - (width / 2)
					local boxY = math.min(headPos.Y, legPos.Y) -- Fixed vertical centering

					-- 1. Update Box
					drawings.Box.Size = Vector2.new(width, height)
					drawings.Box.Position = Vector2.new(boxX, boxY)
					drawings.Box.Color = ESPConfig.BoxColor
					drawings.Box.Visible = true

					-- 2. Update Health Bar
					local maxHealth = humanoid.MaxHealth > 0 and humanoid.MaxHealth or 100
					local healthRatio = math.clamp(humanoid.Health / maxHealth, 0, 1)

					if ESPConfig.ShowHealthBar then
						local barWidth = ESPConfig.HealthBarWidth
						local offset = ESPConfig.HealthBarOffset
						local barX

						if ESPConfig.HealthBarSide == "Right" then
							barX = boxX + width + offset
						else
							barX = boxX - offset - barWidth
						end

						-- Background Outline
						drawings.HealthBarOutline.Position = Vector2.new(barX - 1, boxY - 1)
						drawings.HealthBarOutline.Size = Vector2.new(barWidth + 2, height + 2)
						drawings.HealthBarOutline.Visible = true

						-- Filled Bar
						local barHeight = math.floor(height * healthRatio)
						drawings.HealthBar.Position = Vector2.new(barX, boxY + (height - barHeight))
						drawings.HealthBar.Size = Vector2.new(barWidth, barHeight)

						if ESPConfig.HealthBarLerpColor then
							drawings.HealthBar.Color = Color3.fromRGB(255, 0, 0)
								:Lerp(Color3.fromRGB(0, 255, 0), healthRatio)
						else
							drawings.HealthBar.Color = ESPConfig.HealthBarColor
						end
						drawings.HealthBar.Visible = (barHeight > 0)
					else
						drawings.HealthBarOutline.Visible = false
						drawings.HealthBar.Visible = false
					end

					-- 3. Build Dynamic Text
					local textParts = {}

					if ESPConfig.ShowName then
						local nameStr = ESPConfig.UseDisplayName and player.DisplayName or ("@" .. player.Name)
						table.insert(textParts, nameStr)
					end

					if ESPConfig.ShowHealth then
						local healthPct = math.floor(healthRatio * 100)
						table.insert(textParts, `[{healthPct}%]`)
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

-- Setup listeners & store connections for cleanup
local playerAddedConn = Players.PlayerAdded:Connect(createESP)
local playerRemovingConn = Players.PlayerRemoving:Connect(removeESP)

for _, player in ipairs(Players:GetPlayers()) do
	createESP(player)
end

-- Define the unload function
local function unload()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	if playerAddedConn then
		playerAddedConn:Disconnect()
		playerAddedConn = nil
	end
	if playerRemovingConn then
		playerRemovingConn:Disconnect()
		playerRemovingConn = nil
	end

	for player, _ in pairs(ESPObjects) do
		removeESP(player)
	end
end

-- Return the module table
return {
	Config = ESPConfig,
	Objects = ESPObjects,
	Unload = unload,
}
