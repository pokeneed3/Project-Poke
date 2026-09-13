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

	-- Toggles
	ShowName = true,
	UseDisplayName = true,
	ShowDistance = true,
	ShowHealth = true,
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
	drawings.Name.ZIndex = 3

	ESPObjects[player] = drawings
end

-- Cleanup function to destroy Drawing objects and avoid memory leaks
local function removeESP(player)
	if ESPObjects[player] then
		for _, drawing in pairs(ESPObjects[player]) do
			drawing.Visible = false
			drawing:Remove()
		end
		ESPObjects[player] = nil
	end
end

-- Helper: Check if character is alive and valid
local function isValidCharacter(player)
	local char = player.Character
	if not char then
		return false
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")

	if humanoid and root and humanoid.Health > 0 then
		return char, root, humanoid
	end
	return false
end

-- Main Render Loop
local renderConnection
renderConnection = RunService.RenderStepped:Connect(function()
	if not ESPConfig.Enabled then
		for _, drawings in pairs(ESPObjects) do
			drawings.Box.Visible = false
			drawings.Name.Visible = false
		end
		return
	end

	for player, drawings in pairs(ESPObjects) do
		local char, root, humanoid = isValidCharacter(player)
		local isTeammate = ESPConfig.TeamCheck and (player.Team ~= nil and player.Team == LocalPlayer.Team)

		if char and not isTeammate then
			local rootPos, onScreen = Camera:WorldToViewportPoint(root.Position)

			if onScreen then
				local headPos = Camera:WorldToViewportPoint(root.Position + Vector3.new(0, 2.5, 0))
				local legPos = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3.5, 0))

				local height = math.abs(headPos.Y - legPos.Y)
				local width = height / 1.6

				-- 1. Update Box
				drawings.Box.Size = Vector2.new(width, height)
				drawings.Box.Position = Vector2.new(rootPos.X - (width / 2), rootPos.Y - (height / 2))
				drawings.Box.Color = ESPConfig.BoxColor
				drawings.Box.Visible = true

				-- 2. Build Dynamic Text
				local textParts = {}

				if ESPConfig.ShowName then
					local nameStr = ESPConfig.UseDisplayName and player.DisplayName or ("@" .. player.Name)
					table.insert(textParts, nameStr)
				end

				if ESPConfig.ShowHealth then
					local maxHealth = humanoid.MaxHealth > 0 and humanoid.MaxHealth or 100
					local healthPct = math.clamp(math.floor((humanoid.Health / maxHealth) * 100), 0, 100)
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
					drawings.Name.Position = Vector2.new(rootPos.X, (rootPos.Y - (height / 2)) - drawings.Name.Size - 4)
					drawings.Name.Visible = true
				else
					drawings.Name.Visible = false
				end
			else
				drawings.Box.Visible = false
				drawings.Name.Visible = false
			end
		else
			drawings.Box.Visible = false
			drawings.Name.Visible = false
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
	-- 1. Stop the render loop
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	-- 2. Disconnect player events
	if playerAddedConn then
		playerAddedConn:Disconnect()
		playerAddedConn = nil
	end
	if playerRemovingConn then
		playerRemovingConn:Disconnect()
		playerRemovingConn = nil
	end

	-- 3. Destroy all active drawing primitives
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
