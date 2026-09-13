-- Services
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Stats = game:GetService("Stats")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

-- Variables
local Connections = {}

local SavedPositions = {
	["Base"] = nil,
}

local ToggleSpeedEnabled = false
local ToggleJumpPowerEnabled = false
local CurrentSpeedValue = 16
local CurrentJumpPowerValue = 50
local InfiniteJumpEnabled = false

-- Main Functions

local function trackConnection(connection)
	table.insert(Connections, connection)
end

local function disconnectConnections()
	for _, connection in ipairs(Connections) do
		if connection then
			connection:Disconnect()
		end
	end
	Connections = {}
end

local function updateCharacter(newCharacter)
	character = newCharacter
	character:WaitForChild("Humanoid")
	character:WaitForChild("HumanoidRootPart")
end

trackConnection(player.CharacterAdded:Connect(updateCharacter))

local function applySpeed()
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = ToggleSpeedEnabled and CurrentSpeedValue
	end
end

local function applyJumpPower()
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.JumpPower = ToggleJumpPowerEnabled and CurrentJumpPowerValue
	end
end

-- Library
local repo = "https://raw.githubusercontent.com/pokeneed3/Project-Poke/main/LinoriaLib/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
local Options = loadstring("return getgenv().Options")()

local Window = Library:CreateWindow({
	Title = "Project Poke",
	Center = true,
	AutoShow = true,
	TabPadding = 8,
	MenuFadeTime = 0,
})

local Tabs = {
	Main = Window:AddTab("Main"),
	AutoFarm = Window:AddTab("AutoFarm"),
	Visual = Window:AddTab("Visual"),
	["UI Settings"] = Window:AddTab("UI Settings"),
}

-------------------------------- Main Tab --------------------------------
local TabBox = Tabs.Main:AddLeftTabbox()
local General = TabBox:AddTab("General")
local MainSettings = TabBox:AddTab("Settings")

local RightTabBox = Tabs.Main:AddRightTabbox()

General:AddButton({
	Text = "Spawn Random Tool",
	Tooltip = "Gives you a random tool",
	Func = function()
		local Event = game:GetService("ReplicatedStorage").SpawnGalaxyBlock

		task.spawn(function()
			for _ = 1, 150 do
				Event:FireServer()
				task.wait()
			end
		end)
	end,
})

General:AddButton({
	Text = "Save Position",
	Tooltip = "Saves the current position",
	Func = function()
		if character and character.Parent then
			SavedPositions["Base"] = character:GetPivot()
			Library:Notify("Position Saved!", 5)
		end
	end,
})

local function teleportToSavedPosition()
	if character and character.Parent and SavedPositions["Base"] then
		character:PivotTo(SavedPositions["Base"])
	end
end

General:AddButton({
	Text = "Teleport to Saved Position",
	Tooltip = "Teleports to the saved position",
	Func = function()
		teleportToSavedPosition()
	end,
})

General:AddLabel("Keybind"):AddKeyPicker("TeleportKeyPicker", {
	Default = "C",
	Mode = "Toggle",
	Text = "Teleport to Saved Position",
	NoUI = true,
	Callback = function()
		teleportToSavedPosition()
	end,
})

General:AddToggle("ToggleSpeed", {
	Text = "Speed",
	Default = false,
	Tooltip = "Makes your character move faster",
	Callback = function(Value)
		ToggleSpeedEnabled = Value
		applySpeed()
	end,
}):AddKeyPicker("SpeedKeyPicker", {
	Default = "F1",
	SyncToggleState = true,
	Text = "Speed",
	Mode = "Toggle",
	Callback = function(Value)
		Toggles.ToggleSpeed:SetValue(Value)
		applySpeed()
	end,
})

MainSettings:AddSlider("SpeedSlider", {
	Text = "Speed",
	Default = 16,
	Min = 16,
	Max = 300,
	Rounding = 0,
	Callback = function(v)
		CurrentSpeedValue = v
		applySpeed()
	end,
})

General:AddToggle("ToggleJumpPower", {
	Text = "JumpPower",
	Default = false,
	Tooltip = "Makes your character jump higher",
	Callback = function(Value)
		ToggleJumpPowerEnabled = Value
		applyJumpPower()
	end,
}):AddKeyPicker("JumpPowerKeyPicker", {
	Default = "F2",
	SyncToggleState = true,
	Text = "JumpPower",
	Mode = "Toggle",
	Callback = function(Value)
		Toggles.ToggleJumpPower:SetValue(Value)
		applyJumpPower()
	end,
})

MainSettings:AddSlider("JumpPowerSlider", {
	Text = "JumpPower",
	Default = 50,
	Min = 50,
	Max = 300,
	Rounding = 0,
	Callback = function(v)
		CurrentJumpPowerValue = v
		applyJumpPower()
	end,
})

General:AddToggle("ToggleInfiniteJump", {
	Text = "Infinite Jump",
	Default = false,
	Tooltip = 'Combine with "JumpPower" to jump higher',
	Callback = function(v)
		InfiniteJumpEnabled = v
	end,
}):AddKeyPicker("InfiniteJumpKeyPicker", {
	Default = "F3",
	SyncToggleState = true,
	Text = "Infinite Jump",
	Mode = "Toggle",
	Callback = function(Value)
		Toggles.ToggleInfiniteJump:SetValue(Value)
	end,
})

RunService.Heartbeat:Connect(function()
	local Humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not Humanoid or Library.Unloaded then
		return
	end

	if ToggleSpeedEnabled then
		Humanoid.WalkSpeed = CurrentSpeedValue
	else
		Humanoid.WalkSpeed = 16
	end

	if ToggleJumpPowerEnabled then
		Humanoid.JumpPower = CurrentJumpPowerValue
		Humanoid.JumpHeight = CurrentJumpPowerValue / 2.5
	else
		Humanoid.JumpPower = 50
	end
end)

trackConnection(UserInputService.JumpRequest:Connect(function()
	local Humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if Library.Unloaded then
		return
	end

	if InfiniteJumpEnabled and Humanoid then
		Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end))

General:AddButton({
	Text = "Rejoin Server",
	Tooltip = "Rejoins the server",
	DoubleClick = true,
	Func = function()
		game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
	end,
})

General:AddButton({
	Text = "Server Hop",
	Tooltip = "Hops to a different server in the same place",
	DoubleClick = true,
	Func = function()
		local success, message = pcall(function()
			local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(
				game.PlaceId
			)
			local response = HttpService:JSONDecode(game:HttpGet(url))
			local availableServers = {}

			for _, server in ipairs(response.data or {}) do
				if server.id ~= game.JobId and server.playing < server.maxPlayers then
					table.insert(availableServers, server)
				end
			end

			if #availableServers == 0 then
				error("No available servers found")
			end

			local server = availableServers[math.random(1, #availableServers)]
			game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, server.id, player)
		end)

		if not success then
			Library:Notify("Server hop failed: " .. tostring(message), 5)
		end
	end,
})

-------------------------------- Visual Tab --------------------------------
local VisualTabBox = Tabs.Visual:AddLeftTabbox()
local VisualGeneral = VisualTabBox:AddTab("General")
local VisualSettings = VisualTabBox:AddTab("Settings")

-------------------------------- AutoFarm Tab --------------------------------
local AutoFarmTabBox = Tabs.AutoFarm:AddLeftTabbox()

-------------------------------- UI Settings Tab --------------------------------
Library:SetWatermarkVisibility(true)

local FrameTimer = tick()
local FrameCounter = 0
local FPS = 60

trackConnection(RunService.RenderStepped:Connect(function()
	FrameCounter += 1
	local now = tick()
	if now - FrameTimer >= 1 then
		FPS = FrameCounter
		FrameTimer = now
		FrameCounter = 0
		Library:SetWatermark(
			("Poke Hub | %s fps | %s ms"):format(
				math.floor(FPS),
				math.floor(
					(
						Stats.Network.ServerStatsItem["Data Ping"]
						and Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
					) or 0
				)
			)
		)
	end
end))

Library.KeybindFrame.Visible = true

Library:OnUnload(function()
	Library.Unloaded = true
	disconnectConnections()
end)

local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu")
MenuGroup:AddButton({
	Text = "Unload",
	Tooltip = "Unload the UI",
	DoubleClick = true,
	Func = function()
		Library:Unload()
	end,
})

MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
	Default = "RightAlt",
	NoUI = false,
	Text = "Menu keybind",
})

--Library:Notify('Project Poke Loaded Press "End" to open the menu', 5)

Library.ToggleKeybind = Options.MenuKeybind
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
ThemeManager:SetFolder("Project Poke")
SaveManager:SetFolder("Project Poke/Dungeon Quest Reborn")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()
