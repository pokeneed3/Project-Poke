-- Services
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Stats = game:GetService("Stats")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

-- Variables
local Connections = {}

local SavedPositions = {
	["Base"] = nil,
}

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
			for _ = 1, 100 do
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
	Callback = function()
		teleportToSavedPosition()
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
