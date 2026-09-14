-- Services
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Stats = game:GetService("Stats")

-- Variables
local Connections = {}

local function trackConnection(connection)
	table.insert(Connections, connection)
end

local function disconnectConnections()
	for _, connection in ipairs(Connections) do
		connection:Disconnect()
	end
	Connections = {}
end

-- 1. Load LinoriaLib
local repo = "https://raw.githubusercontent.com/pokeneed3/Project-Poke/main/LinoriaLib/"
local Library = assert(loadstring(game:HttpGet(repo .. "Library.lua")))()
local ThemeManager = assert(loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua")))()
local SaveManager = assert(loadstring(game:HttpGet(repo .. "addons/SaveManager.lua")))()

-- 2. Load ESP Module
local ESP = assert(loadstring(game:HttpGet("https://raw.githubusercontent.com/pokeneed3/Project-Poke/main/Esp.Lua")))()
local ESPConfig = ESP.Config

------------------------------------------------------------------------
-- 3. Group Setup & Auto-Resolver
------------------------------------------------------------------------
-- Configure default initial settings for Player and Mob groups
ESP.SetGroupConfig("Players", {
	Enabled = true,
	ShowBox = true,
	ShowName = true,
	ShowDistance = true,
	BoxColor = Color3.fromRGB(0, 255, 150),
	TextColor = Color3.fromRGB(255, 255, 255),
})

ESP.SetGroupConfig("Mobs", {
	Enabled = true,
	ShowBox = false, -- Box off for mobs by default
	ShowName = true,
	ShowDistance = true,
	BoxColor = Color3.fromRGB(255, 170, 0),
	TextColor = Color3.fromRGB(255, 170, 0),
})

-- Automatically sort tracked targets into "Players" or "Mobs"
ESP.SetGroupResolver(function(instance)
	if instance:IsA("Player") then
		return "Players"
	elseif instance:IsA("Model") and instance:FindFirstChildOfClass("Humanoid") then
		return "Mobs"
	end
	return "Default"
end)

------------------------------------------------------------------------
-- 4. UI Window & Tabs Setup
------------------------------------------------------------------------
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

-------------------------------- Visual Tab --------------------------------
local PlayersGroupbox = Tabs.Visual:AddLeftGroupbox("Player ESP")
local MobsGroupbox = Tabs.Visual:AddRightGroupbox("Mob ESP")

-- ==================== Player ESP Settings ====================
PlayersGroupbox:AddToggle("Player_Enabled", {
	Text = "Enable Player ESP",
	Default = true,
	Callback = function(Value)
		ESP.SetGroupConfig("Players", { Enabled = Value })
	end,
})

PlayersGroupbox:AddToggle("Player_ShowBox", {
	Text = "Show Box",
	Default = true,
	Callback = function(Value)
		ESP.SetGroupConfig("Players", { ShowBox = Value })
	end,
}):AddColorPicker("Player_BoxColor", {
	Default = Color3.fromRGB(0, 255, 150),
	Title = "Box Color",
	Callback = function(Value)
		ESP.SetGroupConfig("Players", { BoxColor = Value })
	end,
})

PlayersGroupbox:AddToggle("Player_ShowName", {
	Text = "Show Name",
	Default = true,
	Callback = function(Value)
		ESP.SetGroupConfig("Players", { ShowName = Value })
	end,
}):AddColorPicker("Player_TextColor", {
	Default = Color3.fromRGB(255, 255, 255),
	Title = "Text Color",
	Callback = function(Value)
		ESP.SetGroupConfig("Players", { TextColor = Value })
	end,
})

PlayersGroupbox:AddToggle("Player_ShowDistance", {
	Text = "Show Distance",
	Default = true,
	Callback = function(Value)
		ESP.SetGroupConfig("Players", { ShowDistance = Value })
	end,
})

PlayersGroupbox:AddToggle("ESP_TeamCheck", {
	Text = "Team Check",
	Default = ESPConfig.TeamCheck or false,
	Callback = function(Value)
		ESPConfig.TeamCheck = Value
	end,
})

-- ==================== Mob ESP Settings ====================
MobsGroupbox:AddToggle("Mob_Enabled", {
	Text = "Enable Mob ESP",
	Default = true,
	Callback = function(Value)
		ESP.SetGroupConfig("Mobs", { Enabled = Value })
	end,
})

MobsGroupbox:AddToggle("Mob_ShowBox", {
	Text = "Show Box",
	Default = false, -- Specifically toggle box off for mobs
	Callback = function(Value)
		ESP.SetGroupConfig("Mobs", { ShowBox = Value })
	end,
}):AddColorPicker("Mob_BoxColor", {
	Default = Color3.fromRGB(255, 170, 0),
	Title = "Box Color",
	Callback = function(Value)
		ESP.SetGroupConfig("Mobs", { BoxColor = Value })
	end,
})

MobsGroupbox:AddToggle("Mob_ShowName", {
	Text = "Show Name",
	Default = true,
	Callback = function(Value)
		ESP.SetGroupConfig("Mobs", { ShowName = Value })
	end,
}):AddColorPicker("Mob_TextColor", {
	Default = Color3.fromRGB(255, 170, 0),
	Title = "Text Color",
	Callback = function(Value)
		ESP.SetGroupConfig("Mobs", { TextColor = Value })
	end,
})

MobsGroupbox:AddToggle("Mob_ShowDistance", {
	Text = "Show Distance",
	Default = true,
	Callback = function(Value)
		ESP.SetGroupConfig("Mobs", { ShowDistance = Value })
	end,
})

------------------------------------------------------------------------
-- 5. Entity Tracking Connections
------------------------------------------------------------------------
-- Track Players
local function trackPlayer(player)
	if player ~= Players.LocalPlayer then
		ESP:Track(player)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	trackPlayer(player)
end
Players.PlayerAdded:Connect(trackPlayer)
Players.PlayerRemoving:Connect(function(player)
	ESP:Untrack(player)
end)

-- Track Mobs Folder
local function watchFolder(folder)
	if not folder then
		return
	end
	for _, m in ipairs(folder:GetChildren()) do
		ESP:Track(m)
	end
	folder.ChildAdded:Connect(function(m)
		ESP:Track(m)
	end)
	folder.ChildRemoved:Connect(function(m)
		ESP:Untrack(m)
	end)
end

watchFolder(workspace:FindFirstChild("Monsters"))

------------------------------------------------------------------------
-- 6. Register Custom Health Bar
------------------------------------------------------------------------
ESP:NewBar({
	Name = "Health",
	Side = "Left",
	Width = 3,
	LerpColor = true,
	GetValue = function(char, instance)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			return hum.Health, hum.MaxHealth
		end
		return instance:GetAttribute("Health") or 0, instance:GetAttribute("MaxHealth") or 100
	end,
})

-------------------------------- UI Settings Tab & Watermark --------------------------------
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

-- Unload handler
Library:OnUnload(function()
	Library.Unloaded = true
	disconnectConnections()
	if ESP and ESP.Unload then
		ESP:Unload()
	end
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
	NoUI = true,
	Text = "Menu keybind",
})

Library.ToggleKeybind = Options.MenuKeybind
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
ThemeManager:SetFolder("Project Poke")
SaveManager:SetFolder("Project Poke/Universal")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()
