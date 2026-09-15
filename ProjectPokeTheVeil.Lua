-- Services
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Stats = game:GetService("Stats")
local UserInputService = cloneref(game:GetService("UserInputService"))

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

-- 2. Load ESP and extract Config & Objects directly!
local ESP = assert(loadstring(game:HttpGet("https://raw.githubusercontent.com/pokeneed3/Project-Poke/main/Esp.Lua")))()
local ESPConfig = ESP.Config

-- Group overrides are optional. Values set here override ESPConfig globals.
local ESPGroups = ESPConfig.Groups or {}
ESPConfig.Groups = ESPGroups
ESPConfig.BarColor = ESPConfig.BarColor or Color3.fromRGB(0, 255, 0)
ESPGroups.Player = ESPGroups.Player or {}
ESPGroups.Monster = ESPGroups.Monster or {}
ESPGroups.NPC = ESPGroups.NPC or {}
ESPGroups.Drop = ESPGroups.Drop or {}
ESPGroups.Chest = ESPGroups.Chest or {}

ESPGroups.NPC.ShowHealth = false
ESPGroups.NPC.ShowBox = false
ESPGroups.Chest.ShowHealth = false
ESPGroups.Drop.ShowHealth = false
ESPGroups.Drop.ShowBox = false
ESPGroups.Chest.ShowBox = false

-- Linoria's global Options & Toggles tables

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

-- Functions

-- ============ 2. Track mobs ============
local watchedFolders = {}
local watchedInstanceName = {}

local function watchInstanceName(Instancename, groupName)
	if not Instancename then
		return
	end

	if watchedInstanceName[Instancename] then
		return
	end

	for _, m in ipairs(workspace:GetDescendants()) do
		if m.Name == Instancename then
			ESP.Track(m, groupName)
		end
	end

	watchedInstanceName[Instancename] = {
		added = workspace.DescendantAdded:Connect(function(m)
			if m.Name == Instancename then
				ESP.Track(m, groupName)
			end
		end),
		removed = workspace.DescendantRemoving:Connect(function(m)
			if m.Name == Instancename then
				ESP.Untrack(m)
			end
		end),
	}
end

local function unwatchInstanceName(Instancename)
	local rec = watchedInstanceName[Instancename]
	if not rec then
		return
	end
	rec.added:Disconnect()
	rec.removed:Disconnect()
	watchedInstanceName[Instancename] = nil

	if Instancename then
		for _, m in ipairs(workspace:GetDescendants()) do
			if m.Name == Instancename then
				ESP.Untrack(m)
			end
		end
	end
end

local function watchFolder(folder, groupName)
	if not folder then
		return
	end

	if watchedFolders[folder] then
		return
	end

	for _, m in ipairs(folder:GetChildren()) do
		ESP.Track(m, groupName)
	end

	watchedFolders[folder] = {
		added = folder.ChildAdded:Connect(function(m)
			ESP.Track(m, groupName)
		end),
		removed = folder.ChildRemoved:Connect(function(m)
			ESP.Untrack(m)
		end),
	}
end

local function unwatchFolder(folder)
	local rec = watchedFolders[folder]
	if not rec then
		return
	end
	rec.added:Disconnect()
	rec.removed:Disconnect()
	watchedFolders[folder] = nil

	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			ESP.Untrack(m)
		end
	end
end

-- watchFolder(Workspace:FindFirstChild("NPCs"))  -- add more folders as needed

-------------------------------- Main Tab --------------------------------
local TabBox = Tabs.Main:AddLeftTabbox()
local General = TabBox:AddTab("General")
local MainSettings = TabBox:AddTab("Settings")

local SpeedConnection
local Speed = 20

General:AddToggle("Speed", {
	Text = "Speed",
	Default = false,
	Callback = function(Value)
		if Value then
			task.spawn(function()
				SpeedConnection = RunService.Heartbeat:Connect(function()
					local player = game:GetService("Players").LocalPlayer
					local humanoid = player.Character:FindFirstChild("Humanoid")
					local root = player.Character:FindFirstChild("HumanoidRootPart")
					local dir = humanoid.MoveDirection
					if dir.Magnitude > 0 then
						local speed = humanoid.WalkSpeed + Speed
						local current = root.AssemblyLinearVelocity
						root.AssemblyLinearVelocity = Vector3.new(dir.X * speed, current.Y, dir.Z * speed)
					end
				end)
			end)
		else
			if SpeedConnection then
				SpeedConnection:Disconnect()
			end
		end
	end,
}):AddKeyPicker("Speed_Toggle", {
	Default = "F1",
	Mode = "Toggle",
	Text = "Toggle Speed",
	SyncToggleState = true,
	NoUI = false,
})

MainSettings:AddSlider("SpeedSlider", {
	Text = "Speed",
	Default = Speed,
	Min = 1,
	Max = 70,
	Rounding = 0,
	Compact = false,

	Callback = function(Value)
		Speed = Value
	end,
})

local NoclipParts = {}
local Noclipping = nil
local Clip

General:AddToggle("Noclip", {
	Text = "Noclip",
	Default = false,
	Callback = function(Value)
		if Value then
			local player = game:GetService("Players").LocalPlayer
			local NoclipParts = {}
			local Noclipping = nil

			pcall(function()
				Noclipping:Disconnect()
			end)

			Clip = false
			NoclipParts = {}
			Noclipping = RunService.Stepped:Connect(function()
				if Clip == false and player.Character ~= nil then
					for _, child in pairs(player.Character:GetDescendants()) do
						if child:IsA("BasePart") and child.CanCollide == true then
							child.CanCollide = false
							NoclipParts[child] = true
						end
					end
				end
			end)
		else
			pcall(function()
				Noclipping:Disconnect()
			end)

			Clip = true
			for child, _ in pairs(NoclipParts) do
				if typeof(child) == "Instance" and child:IsA("BasePart") and child.Parent then
					child.CanCollide = true
				end
			end
			NoclipParts = {}
		end
	end,
}):AddKeyPicker("Noclip_Toggle", {
	Default = "F3",
	Mode = "Toggle",
	Text = "Toggle Noclip",
	SyncToggleState = true,
	NoUI = false,
})

local JumpConnection
local HoldingJump = false
local InfJumpPowerValue = 20

General:AddToggle("InfiniteJump_Toggle", {
	Text = "Infinite Jump",
	Default = false,
	Callback = function(Value)
		if Value then
			local LP = Players.LocalPlayer

			-- Track held state
			local inputBegan = UserInputService.InputBegan:Connect(function(input, gpe)
				if gpe then
					return
				end
				if input.KeyCode == Enum.KeyCode.Space then
					HoldingJump = true
				end
			end)

			local inputEnded = UserInputService.InputEnded:Connect(function(input)
				if input.KeyCode == Enum.KeyCode.Space then
					HoldingJump = false
				end
			end)

			-- Apply continuously
			JumpConnection = RunService.RenderStepped:Connect(function()
				if not HoldingJump then
					return
				end
				local character = LP.Character
				if not character then
					return
				end
				local root = character:FindFirstChild("HumanoidRootPart")
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if not (root and humanoid) or humanoid.Health <= 0 then
					return
				end

				local power = math.max(humanoid.JumpPower, 50) + InfJumpPowerValue
				local v = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity = Vector3.new(v.X, power, v.Z)
			end)

			-- Cleanup hooks
			JumpConnection = {
				Disconnect = function()
					inputBegan:Disconnect()
					inputEnded:Disconnect()
					HoldingJump = false
				end,
			}
		else
			if JumpConnection then
				JumpConnection:Disconnect()
				JumpConnection = nil
			end
			HoldingJump = false
		end
	end,
}):AddKeyPicker("InfiniteJump_KeyPicker", {
	Default = "F4",
	Mode = "Toggle",
	Text = "Toggle InfiniteJump",
	SyncToggleState = true,
	NoUI = false,
})

MainSettings:AddSlider("InfJumpSlider", {
	Text = "JumpPower",
	Default = InfJumpPowerValue,
	Min = InfJumpPowerValue,
	Max = 500,
	Rounding = 0,
	Compact = false,

	Callback = function(Value)
		InfJumpPowerValue = Value
	end,
})

-------------------------------- Visual Tab --------------------------------
local VisualTabBox = Tabs.Visual:AddLeftTabbox()
local VisualGeneral = VisualTabBox:AddTab("General")
local VisualSettings = VisualTabBox:AddTab("Settings")

local GroupSettings = VisualSettings

local function addGroupToggle(groupName, key, label)
	local config = ESPGroups[groupName]
	local optionName = "ESP_" .. groupName .. "_" .. key

	local defaultValue = config[key]
	if defaultValue == nil then
		defaultValue = false
	end
	config[key] = defaultValue

	-- Map which keys get a color picker, and to which config key
	local colorKey
	if key == "ShowBox" then
		colorKey = "BoxColor"
	elseif key == "ShowHealth" then
		colorKey = "BarColor"
	elseif key == "ShowName" then
		colorKey = "TextColor"
		-- key == "ShowDistance" → no colorKey, no picker
	end

	local toggle = GroupSettings:AddToggle(optionName, {
		Text = groupName .. " - " .. label,
		Default = defaultValue,
		Callback = function(value)
			config[key] = value
		end,
	})

	if colorKey then
		local defaultColor = config[colorKey] or ESPConfig[colorKey] or Color3.new(1, 1, 1)
		config[colorKey] = defaultColor

		toggle:AddColorPicker(optionName .. "_Color", {
			Default = defaultColor,
			Title = "Color",
			Callback = function(Value)
				config[colorKey] = Value
			end,
		})
	end
end

for _, groupName in ipairs({ "Player", "Monster", "NPC", "Drop", "Chest" }) do
	addGroupToggle(groupName, "ShowName", "Name")
	addGroupToggle(groupName, "ShowDistance", "Distance")
	if groupName == "NPC" or groupName == "Drop" or groupName == "Chest" then
		continue
	else
		addGroupToggle(groupName, "ShowHealth", "Health Bar")
		addGroupToggle(groupName, "ShowBox", "Box")
	end
end

-- Master ESP Toggle with Box Colorpicker attached
VisualGeneral:AddToggle("ESP_Enabled", {
	Text = "Enable ESP",
	Default = ESPConfig.Enabled,
	Tooltip = "Toggle all player ESP visuals",
	Callback = function(Value)
		ESPConfig.Enabled = Value
	end,
})

-- Name Toggle with Text Colorpicker attached
VisualGeneral:AddToggle("ESP_ShowName", {
	Text = "Show Name",
	Default = ESPConfig.ShowName or true,
	Callback = function(Value)
		ESPConfig.ShowName = Value
	end,
})

-- Display Name Toggle
VisualGeneral:AddToggle("ESP_DisplayName", {
	Text = "Use Display Name",
	Default = ESPConfig.UseDisplayName or true,
	Callback = function(Value)
		ESPConfig.UseDisplayName = Value
	end,
})

-- Health % Toggle
VisualGeneral:AddToggle("ESP_ShowHealth", {
	Text = "Show Health %",
	Default = ESPConfig.ShowHealth or true,
	Callback = function(Value)
		ESPConfig.ShowHealth = Value
	end,
})

-- Distance Toggle
VisualGeneral:AddToggle("ESP_ShowDistance", {
	Text = "Show Distance",
	Default = ESPConfig.ShowDistance,
	Callback = function(Value)
		ESPConfig.ShowDistance = Value
	end,
})

VisualGeneral:AddToggle("Mob_ESP", {
	Text = "Mob Esp",
	Default = false,
	Callback = function(Value)
		local folder = workspace:FindFirstChild("Monsters")
		if Value then
			watchFolder(folder, "Monster")
		else
			unwatchFolder(folder)
		end
	end,
})

VisualGeneral:AddToggle("NPC_ESP", {
	Text = "Npc Esp",
	Default = false,
	Callback = function(Value)
		local folder = workspace:FindFirstChild("NPCs")
		if Value then
			watchFolder(folder, "NPC")
		else
			unwatchFolder(folder)
		end
	end,
})

VisualGeneral:AddToggle("Drop_Esp", {
	Text = "Drop Esp",
	Default = false,
	Callback = function(Value)
		local folder = workspace:FindFirstChild("Drops")
		if Value then
			watchFolder(folder, "Drop")
		else
			unwatchFolder(folder)
		end
	end,
})

VisualGeneral:AddToggle("Chest_ESP", {
	Text = "Chest Esp",
	Default = false,
	Callback = function(Value)
		if Value then
			watchInstanceName("Chest", "Chest")
		else
			unwatchInstanceName("Chest")
		end
	end,
})

local Original_Density = 0.7
local RemoveFogConnection

VisualGeneral:AddToggle("Remove_Fog", {
	Text = "No Fog",
	Default = false,

	Callback = function(Value)
		if Value then
			RemoveFogConnection = RunService.RenderStepped:Connect(function()
				game.Lighting.Atmosphere.Density = 0
			end)
		else
			if RemoveFogConnection then
				RemoveFogConnection:Disconnect()
			end

			game.Lighting.Atmosphere.Density = Original_Density
		end
	end,
})

--[[
ESP:NewBar({
	Name = "Health",
	Side = "Left",
	Width = 2,
	LerpColor = true,
	GetValue = function(char, player)
		local hum = char:FindFirstChildOfClass("Humanoid")
		return hum and hum.Health or 0, hum and hum.MaxHealth or 100
	end,
})
]]

-- ============ 1. Track players ============
local function trackPlayer(player)
	if player ~= Players.LocalPlayer then
		ESP.Track(player, "Player")
	end
end

for _, p in ipairs(Players:GetPlayers()) do
	trackPlayer(p)
end

Players.PlayerAdded:Connect(function(player)
	trackPlayer()

	local groupId = 36025827

	local roleName = player:GetRoleInGroup(groupId)

	if roleName == "Owner" or roleName == "Admin" or roleName == "money tester" or roleName == "Tester" then
		Library:Notify(`Mod in game {roleName}`)
	end
end)
Players.PlayerRemoving:Connect(function(player)
	ESP.Untrack(player)
end)

-- ============ 4. Register bars ============
ESP.NewBar({
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

-- ============ 5. Cleanup ============
-- Example: hook into a UI button, or call ESP:Unload() manually.
-- game:GetService("UserInputService").InputBegan:Connect(function(input)
--     if input.KeyCode == Enum.KeyCode.Delete then
--         ESP:Unload()
--     end
-- end)

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

-- Unload handler: clean up connections and Drawing objects
Library:OnUnload(function()
	Library.Unloaded = true
	disconnectConnections()
	if ESP and ESP.Unload then
		ESP.Unload()
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
-- Library:Notify("hello")
Library.ToggleKeybind = Options.MenuKeybind
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
ThemeManager:SetFolder("Project Poke")
SaveManager:SetFolder("Project Poke/TheVeil")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()
