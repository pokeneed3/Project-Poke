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
local Library = assert(loadstring(game:HttpGet(repo .. "Library.lua")))()
local ThemeManager = assert(loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua")))()
local SaveManager = assert(loadstring(game:HttpGet(repo .. "addons/SaveManager.lua")))()
local ESP = assert(loadstring(game:HttpGet("https://raw.githubusercontent.com/pokeneed3/Project-Poke/main/Esp.lua")))()
local ESPConfig = assert(loadstring("return getgenv().ESPConfig"))()
local ESPObjects = assert(loadstring("return getgenv().ESPObjects"))()
local Options = assert(loadstring("return getgenv().Options"))()
local Toggles = assert(loadstring("return getgenv().Toggles"))()

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

-- Toggle: Master ESP
VisualGeneral:CreateToggle({
	Name = "Enable ESP",
	CurrentValue = ESPConfig.Enabled,
	Callback = function(value)
		ESPConfig.Enabled = value
	end,
})

-- Toggle: Display Name vs Username
VisualGeneral:CreateToggle({
	Name = "Use Display Name",
	CurrentValue = ESPConfig.UseDisplayName,
	Callback = function(value)
		ESPConfig.UseDisplayName = value
	end,
})

-- Toggle: Show Health Percentage
VisualGeneral:CreateToggle({
	Name = "Show Health %",
	CurrentValue = ESPConfig.ShowHealth,
	Callback = function(value)
		ESPConfig.ShowHealth = value
	end,
})

-- Toggle: Show Distance
VisualGeneral:CreateToggle({
	Name = "Show Distance",
	CurrentValue = ESPConfig.ShowDistance,
	Callback = function(value)
		ESPConfig.ShowDistance = value
	end,
})

-- Color Picker: Box / Text Color
VisualGeneral:CreateColorPicker({
	Name = "Text Color",
	Color = ESPConfig.TextColor,
	Callback = function(newColor)
		ESPConfig.TextColor = newColor
		-- Update existing drawings immediately
		for _, drawings in pairs(ESPObjects) do
			drawings.Name.Color = newColor
		end
	end,
})

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
				tostring(math.floor(FPS)),
				tostring(math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()))
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
