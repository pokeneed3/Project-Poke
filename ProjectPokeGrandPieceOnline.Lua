local Players = game:GetService("Players")
local player = Players.LocalPlayer

local Character = player.Character or player.CharacterAdded:Wait()

local Humanoid = Character:FindFirstChildOfClass("Humanoid")

local DEFAULT_SPEED = 16
local DEFAULT_JUMPPOWER = 50

local Current_SpeedValue = DEFAULT_SPEED
local Current_JumpPowerValue = DEFAULT_JUMPPOWER

local ToggleSpeedEnabled = false
local ToggleJumpPowerEnabled = false
local ToggleInfiniteJumpEnabled = false

local function SetSpeed()
	local hum = Humanoid or (Character and Character:FindFirstChildOfClass("Humanoid"))
	if not hum then
		return
	end
	hum.WalkSpeed = ToggleSpeedEnabled and Current_SpeedValue or DEFAULT_SPEED
end

local function SetJumpPower()
	local hum = Humanoid or (Character and Character:FindFirstChildOfClass("Humanoid"))
	if not hum then
		return
	end
	hum.JumpPower = ToggleJumpPowerEnabled and Current_JumpPowerValue or DEFAULT_JUMPPOWER
end

local repo = "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/"
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
	["UI Settings"] = Window:AddTab("UI Settings"),
}

local TabBox = Tabs.Main:AddLeftTabbox()
local Main = TabBox:AddTab("Main")
local Options = TabBox:AddTab("Options")

Main:AddToggle("SpeedToggle", {
	Text = "Speed",
	Default = false,
	Tooltip = "Makes your character faster",

	Callback = function(Value)
		ToggleSpeedEnabled = Value
		SetSpeed()
	end,
})

Options:AddSlider("SpeedSlider", {
	Text = "Speed",
	Default = 16,
	Min = 16,
	Max = 45,
	Rounding = 0,

	Callback = function(Value)
		Current_SpeedValue = Value
		SetSpeed()
	end,
})

-- Library functions
-- Sets the watermark visibility
Library:SetWatermarkVisibility(true)

-- Example of dynamically-updating watermark with common traits (fps and ping)
local FrameTimer = tick()
local FrameCounter = 0
local FPS = 60

local WatermarkConnection = game:GetService("RunService").RenderStepped:Connect(function()
	FrameCounter += 1

	if (tick() - FrameTimer) >= 1 then
		FPS = FrameCounter
		FrameTimer = tick()
		FrameCounter = 0
	end

	Library:SetWatermark(
		("LinoriaLib demo | %s fps | %s ms"):format(
			math.floor(FPS),
			math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue())
		)
	)
end)

Library.KeybindFrame.Visible = true -- todo: add a function for this

Library:OnUnload(function()
	WatermarkConnection:Disconnect()

	print("Unloaded!")
	Library.Unloaded = true
end)

-- UI Settings
local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu")

-- I set NoUI so it does not show up in the keybinds menu
MenuGroup:AddButton("Unload", function()
	Library:Unload()
end)
MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "End", NoUI = true, Text = "Menu keybind" })

Library.ToggleKeybind = Options.MenuKeybind -- Allows you to have a custom keybind for the menu

-- Addons:
-- SaveManager (Allows you to have a configuration system)
-- ThemeManager (Allows you to have a menu theme system)

-- Hand the library over to our managers
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

-- Ignore keys that are used by ThemeManager.
-- (we dont want configs to save themes, do we?)
SaveManager:IgnoreThemeSettings()

-- Adds our MenuKeybind to the ignore list
-- (do you want each config to have a different menu key? probably not.)
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })

-- use case for doing it this way:
-- a script hub could have themes in a global folder
-- and game configs in a separate folder per game
ThemeManager:SetFolder("MyScriptHub")
SaveManager:SetFolder("MyScriptHub/specific-game")

-- Builds our config menu on the right side of our tab
SaveManager:BuildConfigSection(Tabs["UI Settings"])

-- Builds our theme menu (with plenty of built in themes) on the left side
-- NOTE: you can also call ThemeManager:ApplyToGroupbox to add it to a specific groupbox
ThemeManager:ApplyToTab(Tabs["UI Settings"])

-- You can use the SaveManager:LoadAutoloadConfig() to load a config
-- which has been marked to be one that auto loads!
SaveManager:LoadAutoloadConfig()
