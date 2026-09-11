-- Services
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Stats = game:GetService("Stats")

-- Variables
local Connections = {}

-- Main Functions

local function trackConnection(connection)
	table.insert(Connections, connection)
end

local function disconnectConnections()
	for _, connection in ipairs(Connections) do
		connection:Disconnect()
	end
	Connections = {}
end

-- Library
local repo = "https://raw.githubusercontent.com/pokeneed3/Project-Poke/main/LinoriaLib/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

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
				math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
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
