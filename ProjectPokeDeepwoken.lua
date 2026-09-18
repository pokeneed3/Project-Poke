-- Services
local Lighting = cloneref(game:GetService("Lighting"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local Stats = game:GetService("Stats")
local UserInputService = cloneref(game:GetService("UserInputService"))

local player = game:GetService("Players").LocalPlayer

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Camera = workspace.CurrentCamera
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
ESPConfig.ShowHealthPercentage = ESPConfig.ShowHealthPercentage
ESPConfig.BarColor = ESPConfig.BarColor or Color3.fromRGB(0, 255, 0)
ESPConfig.MaxDistance = ESPConfig.MaxDistance or 10000
ESPGroups.Player = ESPGroups.Player or {}
ESPGroups.Mob = ESPGroups.Mob or {}
ESPGroups.NPC = ESPGroups.NPC or {}
ESPGroups.Drop = ESPGroups.Drop or {}
ESPGroups.Chest = ESPGroups.Chest or {}

ESPGroups.Player.ShowName = true
ESPGroups.Player.ShowHealthPercentage = true
ESPGroups.Player.ShowDistance = true
ESPGroups.Player.ShowBars = true

ESPGroups.NPC.ShowName = true
ESPGroups.NPC.ShowDistance = true

ESPGroups.Mob.ShowHealthPercentage = true
ESPGroups.Mob.ShowName = true
ESPGroups.Mob.ShowDistance = true
ESPGroups.Chest.ShowName = true
ESPGroups.Chest.ShowDistance = true

ESPGroups.Mob.ShowName = true
ESPGroups.Mob.ShowDistance = true
ESPGroups.Mob.ShowBox = false
ESPGroups.Mob.ShowBars = false

ESPGroups.NPC.ShowHealthPercentage = false
ESPGroups.Chest.ShowHealthPercentage = false
ESPGroups.Drop.ShowHealthPercentage = false
ESPGroups.NPC.ShowBars = false
ESPGroups.NPC.ShowBox = false
ESPGroups.Chest.ShowBars = false
ESPGroups.Drop.ShowBars = false
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

-- Toggle Helper Functions

local TrackedToggles = {}
local SetToggle

local function TrackToggle(ToggleName: string)
	if type(ToggleName) ~= "string" then
		return
	end

	if not TrackedToggles[ToggleName] then
		TrackedToggles[ToggleName] = true
	end
end

local function UnTrackToggle(ToggleName: string)
	if type(ToggleName) == "string" then
		TrackedToggles[ToggleName] = nil
	end
end

local function DisableAllTrackedToggles()
	for ToggleName in pairs(TrackedToggles) do
		SetToggle(ToggleName, false)
	end
end

SetToggle = function(ToggleName: string, v: boolean)
	if type(ToggleName) ~= "string" then
		return
	end

	local Toggle = Toggles[ToggleName]
	if Toggle then
		Toggle:SetValue(v)
	end
end

local function trackPlayer(player)
	if player ~= Players.LocalPlayer then
		ESP.Track(player, "Player")
	end
end

-- Storage for active watchers
local watchedFolders = {}
local watchedInstanceName = {}

-- Helper function to apply custom attribute to ESP text
local function applyMobAttribute(instance, attributeName)
	if not instance or not instance:IsA("Model") then
		return
	end

	-- Function to update the ESPName attribute
	local function updateName()
		local attrValue = instance:GetAttribute(attributeName)
		if attrValue then
			instance:SetAttribute("ESPName", tostring(attrValue))
		else
			-- Fallback if attribute is nil (e.g., MobName (Level 5))
			local nameAttr = instance:GetAttribute("MobName") or instance:GetAttribute("DisplayName")
			local levelAttr = instance:GetAttribute("Level")

			if nameAttr and levelAttr then
				instance:SetAttribute("ESPName", string.format("%s [Lvl %s]", tostring(nameAttr), tostring(levelAttr)))
			elseif nameAttr then
				instance:SetAttribute("ESPName", tostring(nameAttr))
			end
		end
	end

	-- Apply immediately
	updateName()

	-- Listen for attribute updates (in case mob stats/name load asynchronously)
	local attributeConnection = instance.AttributeChanged:Connect(function(changedAttr)
		if changedAttr == attributeName or changedAttr == "MobName" or changedAttr == "Level" then
			updateName()
		end
	end)

	return attributeConnection
end

-- Refactored watchFolderPredicate with Attribute support
local function watchFolderPredicate(folder, groupName, predicate, targetAttributeName)
	if not folder or watchedFolders[folder] then
		return
	end

	local attrConnections = {}

	local function tryTrack(m)
		if not predicate or predicate(m) then
			-- Extract and assign attribute before tracking
			if targetAttributeName then
				local conn = applyMobAttribute(m, targetAttributeName)
				if conn then
					attrConnections[m] = conn
				end
			end
			ESP.Track(m, groupName)
		end
	end

	-- Track existing children
	for _, m in ipairs(folder:GetChildren()) do
		tryTrack(m)
	end

	-- Track future added children & cleanup on removal
	watchedFolders[folder] = {
		added = folder.ChildAdded:Connect(tryTrack),
		removed = folder.ChildRemoved:Connect(function(m)
			if attrConnections[m] then
				attrConnections[m]:Disconnect()
				attrConnections[m] = nil
			end
			ESP.Untrack(m)
		end),
		attrConns = attrConnections,
	}
end

local function unwatchFolder(folder)
	local rec = watchedFolders[folder]
	if not rec then
		return
	end

	rec.added:Disconnect()
	rec.removed:Disconnect()

	if rec.attrConns then
		for _, conn in pairs(rec.attrConns) do
			conn:Disconnect()
		end
	end

	watchedFolders[folder] = nil

	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			ESP.Untrack(m)
		end
	end
end

-- watchFolder(Workspace:FindFirstChild("NPCs"))  -- add more folders as needed

-- Tracking Toggles that need to be cleaned up
TrackToggle("Speed")
TrackToggle("Noclip")
TrackToggle("InfiniteJump_Toggle")
TrackToggle("NoFallDmg_Toggle")
TrackToggle("Remove_Fog")
TrackToggle("Chat_History")
TrackToggle("Remove_Shadows")
TrackToggle("MaxZoom_Toggle")
TrackToggle("LeaderboardSpectate_Toggle")

-------------------------------- Main Tab --------------------------------
local TabBox = Tabs.Main:AddLeftTabbox()
local General = TabBox:AddTab("General")
local MainSettings = TabBox:AddTab("Settings")

local SpeedConnection
local Speed = 100

General:AddToggle("Speed", {
	Text = "Speed",
	Default = false,
	Callback = function(Value)
		if Value then
			task.spawn(function()
				SpeedConnection = RunService.RenderStepped:Connect(function()
					local player = Players.LocalPlayer
					local character = player.Character
					if not character then
						return
					end

					local humanoid = character:WaitForChild("Humanoid")
					local root = character:WaitForChild("HumanoidRootPart")
					if not humanoid or not root or humanoid.Health <= 0 then
						return
					end

					local dir = humanoid.MoveDirection
					local speed = humanoid.WalkSpeed + Speed
					local current = root.AssemblyLinearVelocity
					if dir.Magnitude > 0 then
						root.AssemblyLinearVelocity = Vector3.new(dir.X * speed, current.Y, dir.Z * speed)
					else
						root.AssemblyLinearVelocity = Vector3.new(0, current.Y, 0)
					end
				end)
			end)
		else
			if SpeedConnection then
				local player = Players.LocalPlayer
				local character = player.Character

				if not character then
					return
				end

				local humanoid = character:WaitForChild("Humanoid")
				local root = character:WaitForChild("HumanoidRootPart")

				if not humanoid or not root or humanoid.Health <= 0 then
					return
				end

				local current = root.AssemblyLinearVelocity

				root.AssemblyLinearVelocity = Vector3.new(0, current.Y, 0)

				SpeedConnection:Disconnect()
				SpeedConnection = nil
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
	Min = 10,
	Max = 250,
	Rounding = 1,
	Compact = false,

	Callback = function(Value)
		Speed = Value
	end,
})

--
local NoclipCFrameBlock = false

local mt = getrawmetatable(game)
local oldNewIndex = mt.__newindex
setreadonly(mt, false)

mt.__newindex = newcclosure(function(self, key, value)
	if
		NoclipCFrameBlock
		and key == "CFrame"
		and self.Name == "HumanoidRootPart"
		and self:IsDescendantOf(Players.LocalPlayer.Character)
	then
		return
	end
	return oldNewIndex(self, key, value)
end)

setreadonly(mt, true)

local NoclipParts = {} -- set of parts we've disabled
local Noclipping = nil -- Stepped connection
local CharConnections = {} -- connections tied to the current character
local Clip = true

local player = game:GetService("Players").LocalPlayer

-- Disable collision on a single part and remember it
local function stripPart(part)
	if part:IsA("BasePart") and part.CanCollide then
		part.CanCollide = false
		NoclipParts[part] = true
	end
end

-- Handle all current + future parts of a character
local function hookCharacter(character)
	-- Clean up old connections
	for _, c in ipairs(CharConnections) do
		c:Disconnect()
	end
	table.clear(CharConnections)

	-- Initial pass (once, not per-frame)
	for _, d in ipairs(character:GetDescendants()) do
		stripPart(d)
	end

	-- Handle parts added later (accessories, tools, etc.)
	table.insert(
		CharConnections,
		character.DescendantAdded:Connect(function(d)
			if not Clip then
				stripPart(d)
			end
		end)
	)
end

-- Re-hook on respawn
table.insert(
	CharConnections,
	player.CharacterAdded:Connect(function(char)
		if not Clip then
			hookCharacter(char)
		end
	end)
)

General:AddToggle("Noclip", {
	Text = "Noclip",
	Default = false,
	Callback = function(Value)
		if Value then
			local player = game:GetService("Players").LocalPlayer

			NoclipCFrameBlock = true

			pcall(function()
				Noclipping:Disconnect()
			end)

			Clip = false
			NoclipParts = {}
			Noclipping = RunService.Stepped:Connect(function()
				if Clip == false and player.Character ~= nil then
					for _, child in pairs(player.Character:GetChildren()) do
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
local InfJumpPowerValue = 100

General:AddToggle("InfiniteJump_Toggle", {
	Text = "Infinite Jump",
	Default = false,
	Callback = function(Value)
		if Value then
			local LP = Players.LocalPlayer

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

			local renderStepped = RunService.RenderStepped:Connect(function()
				if not HoldingJump then
					return
				end
				local character = LP.Character
				if not character then
					return
				end
				local root = character:WaitForChild("HumanoidRootPart")
				local humanoid = character:WaitForChild("Humanoid")
				if not (root and humanoid) or humanoid.Health <= 0 then
					return
				end

				local power = math.max(humanoid.JumpPower, 50) + InfJumpPowerValue
				local v = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity = Vector3.new(v.X, power, v.Z)
			end)

			JumpConnection = {
				Disconnect = function()
					inputBegan:Disconnect()
					inputEnded:Disconnect()
					renderStepped:Disconnect()
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
	Text = "Jump Power",
	Default = InfJumpPowerValue,
	Min = 10,
	Max = 500,
	Rounding = 1,
	Compact = false,

	Callback = function(Value)
		InfJumpPowerValue = Value
	end,
})

local NoFallDmgEnabled = false
local FallDamageSearchActive = false

local function hookFallDmgFunction()
	if FallDamageSearchActive then
		return
	end

	FallDamageSearchActive = true
	NoFallDmgEnabled = true

	task.spawn(function()
		while FallDamageSearchActive and NoFallDmgEnabled do
			local WorldClient = Players.LocalPlayer.PlayerGui:FindFirstChild("WorldClient")
			local originalFall
			local fallName

			if WorldClient then
				local env = getsenv(WorldClient)
				for name, value in pairs(env) do
					if type(value) == "function" and name:lower():find("fall") then
						fallName, originalFall = name, value
						break
					end
				end
			end

			if originalFall then
				local env = getsenv(WorldClient)
				env[fallName] = function(...)
					if NoFallDmgEnabled then
						return
					end
					return originalFall(...)
				end

				FallDamageSearchActive = false
				return
			end

			task.wait(1)
		end

		FallDamageSearchActive = false
	end)
end

General:AddToggle("NoFallDmg_Toggle", {
	Text = "No Fall Damage",
	Default = false,
	Callback = function(Value)
		if Value then
			hookFallDmgFunction()
		else
			NoFallDmgEnabled = false
			FallDamageSearchActive = false
		end
	end,
})

local lifeFieldStates = {}

General:AddToggle("RemoveCastleLightField_Toggle", {
	Text = "Remove Castle Light Field",
	Default = false,
	Callback = function(Value)
		if Value then
			for _, lifeField in workspace:GetChildren() do
				if lifeField.Name == "LifeField" and lifeField:IsA("BasePart") then
					lifeFieldStates[lifeField] = {
						CanCollide = lifeField.CanCollide,
						CanTouch = lifeField.CanTouch,
					}
					lifeField.CanCollide = false
					lifeField.CanTouch = false
				end
			end
		else
			for lifeField, state in pairs(lifeFieldStates) do
				if lifeField.Parent then
					lifeField.CanCollide = state.CanCollide
					lifeField.CanTouch = state.CanTouch
				end
			end
		end
	end,
})

local AntiAfkConnection
General:AddToggle("AntiAFK_Toggle", {
	Text = "Anti-AFK",
	Default = false,
	Tooltip = "Prevents the 20-minute idle disconnect",
	Callback = function(Value)
		if Value then
			local VirtualUser = cloneref(game:GetService("VirtualUser"))

			AntiAfkConnection = Players.LocalPlayer.Idled:Connect(function()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.new())
			end)
		else
			if AntiAfkConnection then
				AntiAfkConnection:Disconnect()
				AntiAfkConnection = nil
			end
		end
	end,
})

TrackToggle("AntiAFK_Toggle")

local OverlayGui = game:GetService("Players").LocalPlayer.PlayerGui:WaitForChild("OverlayGui", 2)

local RemoveInsanityActive = false
General:AddToggle("RemoveInsanityScreen_Toggle", {
	Text = "Remove Insanity Screen",
	Default = false,
	Tooltip = "Removes the blue screen you get when insane",
	Callback = function(Value)
		if Value then
			if not OverlayGui then
				Library:Notify("OverlayGui was not found")
				return
			end

			local TerrorImg = OverlayGui:FindFirstChild("Terror")
			local TerrorTendril = OverlayGui:FindFirstChild("TerrorTendril")
			local TerrorTendril2 = OverlayGui:FindFirstChild("TerrorTendril2")
			if not TerrorImg or not TerrorTendril or not TerrorTendril2 then
				Library:Notify("Insanity UI elements were not found")
				return
			end
			RemoveInsanityActive = true

			task.spawn(function()
				while RemoveInsanityActive do
					TerrorImg.Visible = false
					TerrorTendril.Visible = false
					TerrorTendril2.Visible = false
					task.wait()
				end
			end)
		else
			RemoveInsanityActive = false
		end
	end,
})

TrackToggle("RemoveInsanityScreen_Toggle")

-------------------------------- Visual Tab --------------------------------
local VisualTabBox = Tabs.Visual:AddLeftTabbox()
local RightVisualTabBox = Tabs.Visual:AddRightTabbox()

local TempStorageVisualTabBox = Tabs.Visual:AddRightTabbox()
local TempStorageVisualTabBoxMain = TempStorageVisualTabBox:AddTab("Main")
local TempStorageVisualTabBoxSettings = TempStorageVisualTabBox:AddTab("Settings")

local PlayerVisual = RightVisualTabBox:AddTab("Player")
local PlayerPlayerVisualSettings = RightVisualTabBox:AddTab("Settings")

local VisualMods = VisualTabBox:AddTab("Mods")
local PlayerVisualSettings = VisualTabBox:AddTab("Settings")

local function addGroupBooleanDropDown(groupName, key, label)
	local config = ESPGroups[groupName]
	local optionName = "ESP_" .. groupName .. "_" .. key

	local defaultValue = config[key]
	if defaultValue == nil then
		defaultValue = ESPConfig[key]
	end

	local defaultOption = defaultValue and "On" or "Off"

	TempStorageVisualTabBoxSettings:AddDropdown(optionName, {
		Values = { "On", "Off" },
		Default = defaultOption,
		Multi = false,
		Text = groupName .. " - " .. label,

		Callback = function(value)
			config[key] = value == "On"
		end,
	})
end

local function addGroupToggle(groupName, key, label)
	local config = ESPGroups[groupName]
	local optionName = "ESP_" .. groupName .. "_" .. key

	local defaultValue = config[key]
	if defaultValue == nil then
		defaultValue = ESPConfig[key]
	end
	config[key] = defaultValue

	local colorKey
	if key == "ShowBox" then
		colorKey = "BoxColor"
	elseif key == "ShowBars" then
		colorKey = "BarColor"
	elseif key == "ShowName" then
		colorKey = "TextColor"
	end

	local toggle = TempStorageVisualTabBoxSettings:AddToggle(optionName, {
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

for _, groupName in ipairs({ "Player", "Mob", "NPC", "Drop", "Chest" }) do
	local config = ESPGroups[groupName]
	addGroupToggle(groupName, "ShowBox", "Box")
	addGroupToggle(groupName, "ShowBars", "Health Bars")
	addGroupToggle(groupName, "ShowName", "Name")

	local textOptions = {
		"Name",
		"Distance",
		"HealthPercentage",
	}

	TempStorageVisualTabBoxSettings:AddDropdown("ESP_" .. groupName .. "_Text", {
		Values = textOptions,
		Default = (function()
			local selected = {}

			if config.ShowName then
				table.insert(selected, "Name")
			end
			if config.ShowDistance then
				table.insert(selected, "Distance")
			end
			if config.ShowHealthPercentage then
				table.insert(selected, "HealthPercentage")
			end

			return selected
		end)(),
		Multi = true,
		Text = groupName .. " - Text Display",

		Callback = function(values)
			config.ShowName = values.Name == true
			config.ShowDistance = values.Distance == true
			config.ShowHealthPercentage = values.HealthPercentage == true
		end,
	})
end

-- Master ESP Toggle with Box Colorpicker attached
TempStorageVisualTabBoxMain:AddToggle("ESP_Enabled", {
	Text = "Enable ESP",
	Default = ESPConfig.Enabled,
	Tooltip = "Toggle all player ESP visuals",
	Callback = function(Value)
		ESPConfig.Enabled = Value
	end,
})

local playerESPEnabled = true
local playerConnectionList = {}

local function enablePlayerESP()
	if playerESPEnabled then
		return
	end

	playerESPEnabled = true

	for _, p in ipairs(Players:GetPlayers()) do
		trackPlayer(p)
	end

	table.insert(
		playerConnectionList,
		Players.PlayerAdded:Connect(function(player)
			if playerESPEnabled and player ~= Players.LocalPlayer then
				ESP.Track(player, "Player")
			end
		end)
	)
end

local function disablePlayerESP()
	if not playerESPEnabled then
		return
	end

	playerESPEnabled = false

	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= Players.LocalPlayer then
			ESP.Untrack(p)
		end
	end

	for _, conn in ipairs(playerConnectionList) do
		conn:Disconnect()
	end
	table.clear(playerConnectionList)
end

TempStorageVisualTabBoxMain:AddToggle("Player_ESP", {
	Text = "Player Esp",
	Default = true,
	Callback = function(Value)
		if Value then
			enablePlayerESP()
		else
			disablePlayerESP()
		end
	end,
})

TempStorageVisualTabBoxMain:AddSlider("PlayerMaxDistance_Slider", {
	Text = "Max Distance",
	Default = 5000,
	Min = 100,
	Max = 50000,
	Rounding = 1,
	Compact = false,

	Callback = function(Value)
		ESPGroups.Player.MaxDistance = Value
	end,
})

-- Display Name Toggle
TempStorageVisualTabBoxMain:AddToggle("ESP_DisplayName", {
	Text = "Use Display Name",
	Default = ESPConfig.UseDisplayName or true,
	Callback = function(Value)
		ESPConfig.UseDisplayName = Value
	end,
})

-- Distance Toggle
TempStorageVisualTabBoxMain:AddToggle("ESP_ShowDistance", {
	Text = "Show Distance",
	Default = ESPConfig.ShowDistance,
	Callback = function(Value)
		ESPConfig.ShowDistance = Value
	end,
})

local function isMob(m)
	return m:IsA("Model") and Players:GetPlayerFromCharacter(m) == nil
end

TempStorageVisualTabBoxMain:AddToggle("Mob_ESP", {
	Text = "Mob Esp",
	Default = false,
	Callback = function(Value)
		local folder = workspace:FindFirstChild("Live")
		if not folder then
			Library:Notify("Live folder was not found")
			return
		end
		if Value then
			watchFolderPredicate(folder, "Mob", isMob, "MOB_rich_name")
		else
			unwatchFolder(folder)
		end
	end,
})

TempStorageVisualTabBoxMain:AddSlider("MobMaxDistance_Slider", {
	Text = "Max Distance",
	Default = 5000,
	Min = 100,
	Max = 50000,
	Rounding = 1,
	Compact = false,

	Callback = function(Value)
		ESPGroups.Mob.MaxDistance = Value
	end,
})

TempStorageVisualTabBoxMain:AddToggle("NPC_ESP", {
	Text = "Npc Esp",
	Default = false,
	Callback = function(Value)
		local folder = workspace:FindFirstChild("NPCs")
		if not folder then
			Library:Notify("NPCs folder was not found")
			return
		end
		if Value then
			watchFolderPredicate(folder, "NPC")
		else
			unwatchFolder(folder)
		end
	end,
})

TempStorageVisualTabBoxMain:AddSlider("NPCMaxDistance_Slider", {
	Text = "Max Distance",
	Default = 5000,
	Min = 100,
	Max = 50000,
	Rounding = 1,
	Compact = false,

	Callback = function(Value)
		ESPGroups.NPC.MaxDistance = Value
	end,
})

TempStorageVisualTabBoxMain:AddToggle("Drop_Esp", {
	Text = "Drop Esp",
	Default = false,
	Callback = function(Value)
		local folder = workspace:FindFirstChild("Drops")
		if not folder then
			Library:Notify("Drops folder was not found")
			return
		end
		if Value then
			watchFolderPredicate(folder, "Drop")
		else
			unwatchFolder(folder)
		end
	end,
})

TempStorageVisualTabBoxMain:AddSlider("DropMaxDistance_Slider", {
	Text = "Max Distance",
	Default = 5000,
	Min = 100,
	Max = 50000,
	Rounding = 1,
	Compact = false,

	Callback = function(Value)
		ESPGroups.Drop.MaxDistance = Value
	end,
})

--[[
TempStorageVisualTabBoxMain:AddToggle("Chest_ESP", {
	Text = "Chest Esp",
	Default = false,
	Callback = function(Value)
		if Value then
			watchFolderPredicate("Chest", "Chest")
		else
			unwatchInstanceName("Chest")
		end
	end,
})
]]

TempStorageVisualTabBoxMain:AddSlider("ChestMaxDistance_Slider", {
	Text = "Max Distance",
	Default = 5000,
	Min = 100,
	Max = 50000,
	Rounding = 1,
	Compact = false,

	Callback = function(Value)
		ESPGroups.Chest.MaxDistance = Value
	end,
})

local chatwindow = game:GetService("TextChatService").ChatWindowConfiguration

VisualMods:AddToggle("Chat_History", {
	Text = "Show Chat Window",
	Default = false,
	Callback = function(Value)
		if Value then
			chatwindow.Enabled = true
		else
			chatwindow.Enabled = false
		end
	end,
})

local RemoveFogConnection

local Original_FogStart = Lighting.FogStart
local Original_FogEnd = Lighting.FogEnd

local Atmosphere = Lighting:FindFirstChild("Atmosphere")
local Original_Density = Atmosphere and Atmosphere.Density or 0
VisualMods:AddToggle("Remove_Fog", {
	Text = "No Fog",
	Default = false,

	Callback = function(Value)
		if Value then
			RemoveFogConnection = RunService.RenderStepped:Connect(function()
				if Atmosphere then
					Atmosphere.Density = 0
				end

				Lighting.FogEnd = math.huge
				Lighting.FogStart = math.huge
			end)
		else
			if RemoveFogConnection then
				RemoveFogConnection:Disconnect()
			end
			Lighting.FogEnd = Original_FogStart
			Lighting.FogStart = Original_FogEnd
			if Atmosphere then
				Atmosphere.Density = Original_Density
			end
		end
	end,
})

VisualMods:AddToggle("Remove_Shadows", {
	Text = "No Shadows",
	Default = false,

	Callback = function(Value)
		if Value then
			Lighting.GlobalShadows = false
		else
			Lighting.GlobalShadows = true
		end
	end,
})

local MaxZoomDefault = player.CameraMaxZoomDistance
local CurrentMaxZoom = MaxZoomDefault

local MaxZoomToggleActive = false

VisualMods:AddToggle("MaxZoom_Toggle", {
	Text = "Max Zoom",
	Default = false,

	Callback = function(Value)
		if Value then
			MaxZoomToggleActive = true
			player.CameraMaxZoomDistance = CurrentMaxZoom
		else
			MaxZoomToggleActive = false
			player.CameraMaxZoomDistance = MaxZoomDefault
		end
	end,
})

VisualMods:AddSlider("MaxZoom_Slider", {
	Text = "Max Zoom",
	Default = MaxZoomDefault,
	Min = 10,
	Max = 400, --YOU GET BANNED IF YOU GO TOO HIGH
	Rounding = 1,
	Compact = false,

	Callback = function(Value)
		if MaxZoomToggleActive then
			CurrentMaxZoom = Value
			player.CameraMaxZoomDistance = CurrentMaxZoom
		end
	end,
})

local PlayerGui = player:WaitForChild("PlayerGui", 2)
local LeaderboardGui = PlayerGui and PlayerGui:WaitForChild("LeaderboardGui", 2)
local LeaderboardMainFrame = LeaderboardGui and LeaderboardGui:WaitForChild("MainFrame", 2)
local ScrollingFrame = LeaderboardMainFrame and LeaderboardMainFrame:WaitForChild("ScrollingFrame", 2)

if not ScrollingFrame then
	Library:Notify("Leaderboard UI was not found; leaderboard spectate disabled")
end

local leaderboardspectateLoops = {}
local currentSpectateLoop
local currentSpectateName
local ListenForHealthChangeConnection
local PlayerLabels = {}

local function extractUsername(text)
	local username = text:match("^(.-)%s*%(") or text
	return username
end

local function findLeaderboardLabel(playerName)
	if not ScrollingFrame then
		return nil
	end

	for _, descendant in ipairs(ScrollingFrame:GetDescendants()) do
		if descendant.Name == "Player" and descendant:IsA("TextLabel") then
			if extractUsername(descendant.Text) == playerName then
				return descendant
			end
		end
	end

	return nil
end

local function setSpectateLabelColor(playerName, color)
	local leaderboardLabel = findLeaderboardLabel(playerName)
	if leaderboardLabel then
		leaderboardLabel.TextColor3 = color
	end

	local targetPlayer = Players:FindFirstChild(playerName)
	local proximityLabel = targetPlayer and PlayerLabels[targetPlayer]
	if proximityLabel then
		proximityLabel.TextColor3 = color
	end

	return leaderboardLabel
end

local function spectatePlayer(targetPlayerOrName)
	local targetPlayer
	if typeof(targetPlayerOrName) == "Instance" and targetPlayerOrName:IsA("Player") then
		targetPlayer = targetPlayerOrName
	elseif type(targetPlayerOrName) == "string" then
		targetPlayer = Players:FindFirstChild(extractUsername(targetPlayerOrName))
	end

	if not targetPlayer then
		Library:Notify("Player was not found")
		return
	end

	local spectateName = targetPlayer.Name

	if spectateName == currentSpectateName then
		if currentSpectateLoop then
			currentSpectateLoop:Disconnect()
			currentSpectateLoop = nil
		end
		setSpectateLabelColor(spectateName, Color3.fromRGB(255, 255, 255))
		currentSpectateName = nil
		return
	end

	if currentSpectateName then
		setSpectateLabelColor(currentSpectateName, Color3.fromRGB(255, 255, 255))
	end

	if currentSpectateLoop then
		currentSpectateLoop:Disconnect()
		currentSpectateLoop = nil
	end

	if ListenForHealthChangeConnection then
		ListenForHealthChangeConnection:Disconnect()
		ListenForHealthChangeConnection = nil
	end

	if targetPlayer == player then
		Library:Notify(`You cannot spectate yourself`)
		return
	end

	local character = targetPlayer.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	if not humanoid and character then
		humanoid = character:WaitForChild("Humanoid", 5)
	end

	if not character or not humanoid then
		Library:Notify(`{character} doesnt have a valid Character or Humanoid`)
		return
	end

	setSpectateLabelColor(spectateName, Color3.fromRGB(111, 0, 255))
	currentSpectateName = spectateName

	local localHumanoid = player.Character and player.Character:FindFirstChild("Humanoid")
	if localHumanoid then
		local previousHealth = localHumanoid.Health

		ListenForHealthChangeConnection = localHumanoid.HealthChanged:Connect(function(newHealth)
			if newHealth < previousHealth and currentSpectateLoop then
				setSpectateLabelColor(spectateName, Color3.fromRGB(255, 255, 255))

				currentSpectateLoop:Disconnect()
				currentSpectateLoop = nil
			end
			previousHealth = newHealth
		end)
	end

	currentSpectateLoop = RunService.Heartbeat:Connect(function()
		local targetCharacter = targetPlayer.Character
		local targetHumanoid = targetCharacter and targetCharacter:FindFirstChild("Humanoid")

		if not targetCharacter or not targetHumanoid then
			setSpectateLabelColor(spectateName, Color3.fromRGB(255, 255, 255))

			currentSpectateLoop:Disconnect()
			currentSpectateLoop = nil

			Library:Notify(`{targetCharacter} doesnt have a valid Character or Humanoid`)
			return
		end

		workspace.CurrentCamera.CameraSubject = targetHumanoid
	end)
end

local function setupClick(label)
	local connection = label.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			spectatePlayer(extractUsername(label.Text))
		end
	end)

	table.insert(leaderboardspectateLoops, connection)
end

local function disconnectAllLeaderboardSpectateLoops()
	for _, connection in ipairs(leaderboardspectateLoops) do
		connection:Disconnect()
	end
	table.clear(leaderboardspectateLoops)

	if currentSpectateLoop then
		currentSpectateLoop:Disconnect()
		currentSpectateLoop = nil
	end

	if currentSpectateName then
		setSpectateLabelColor(currentSpectateName, Color3.fromRGB(255, 255, 255))
	end

	currentSpectateName = nil
end

VisualMods:AddToggle("LeaderboardSpectate_Toggle", {
	Text = "Leaderboard Spectate",
	Default = false,

	Callback = function(Value)
		if Value then
			if not ScrollingFrame then
				Library:Notify("Leaderboard UI is unavailable")
				return
			end

			local TextLabelConnection = ScrollingFrame.DescendantAdded:Connect(function(desc)
				if desc.Name == "Player" and desc:IsA("TextLabel") then
					setupClick(desc)
				end
			end)
			table.insert(leaderboardspectateLoops, TextLabelConnection)

			for _, desc in ipairs(ScrollingFrame:GetDescendants()) do
				if desc.Name == "Player" and desc:IsA("TextLabel") then
					setupClick(desc)
				end
			end
		else
			disconnectAllLeaderboardSpectateLoops()
		end
	end,
})

local LeaderboardPlayerTextLabel = LeaderboardMainFrame
	and LeaderboardMainFrame:FindFirstChild("ScrollingFrame")
	and LeaderboardMainFrame.ScrollingFrame:FindFirstChild("PlayerFrame")
	and LeaderboardMainFrame.ScrollingFrame.PlayerFrame:FindFirstChild("PlayerFrame")
	and LeaderboardMainFrame.ScrollingFrame.PlayerFrame.PlayerFrame:FindFirstChild("Player") :: TextLabel

local LeaderPlayerFrameButton = LeaderboardMainFrame
	and LeaderboardMainFrame:FindFirstChild("ScrollingFrame")
	and LeaderboardMainFrame.ScrollingFrame:FindFirstChild("PlayerFrame") :: TextButton

local StreamerModeConnections = {}

VisualMods:AddToggle("StreamerMode_Toggle", {
	Text = "Streamer Mode",
	Default = false,
	Tooltip = "Hides your account information like your username and userid",

	Callback = function(Value)
		if not LeaderPlayerFrameButton then
			Library:Notify("Leaderboard UI is unavailable")
			return
		end

		if Value then
			LeaderPlayerFrameButton.Visible = false
		else
			LeaderPlayerFrameButton.Visible = true
		end
	end,
})
TrackToggle("StreamerMode_Toggle")

local RemoveBlurConnection

VisualMods:AddToggle("RemoveBlur_Toggle", {
	Text = "No Blur",
	Default = false,

	Callback = function(Value)
		if Value then
			RemoveBlurConnection = RunService.RenderStepped:Connect(function()
				game:GetService("Lighting"):WaitForChild("GenericBlur").Size = 0
			end)
		else
			if RemoveBlurConnection then
				RemoveBlurConnection:Disconnect()
			end
		end
	end,
})

local PlayerProximityWindowVisible = true
local ProximityMaxDistance = 1000 -- Max detection distance in studs

-- 1. Create the UI Window Frame
local PlayerProximityOuter = Library:Create("Frame", {
	AnchorPoint = Vector2.new(0, 0),
	BorderColor3 = Color3.new(0, 0, 0),
	Position = UDim2.new(0, 10, 0.5, 0),
	Size = UDim2.fromOffset(220, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Visible = PlayerProximityWindowVisible,
	ZIndex = 100,
	Parent = Library.ScreenGui,
})

local PlayerProximityInner = Library:Create("Frame", {
	BackgroundColor3 = Library.MainColor,
	BorderColor3 = Library.OutlineColor,
	BorderMode = Enum.BorderMode.Inset,
	Size = UDim2.fromScale(1, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	ZIndex = 101,
	Parent = PlayerProximityOuter,
})

Library:AddToRegistry(PlayerProximityInner, {
	BackgroundColor3 = "MainColor",
	BorderColor3 = "OutlineColor",
}, true)

local ColorFrame = Library:Create("Frame", {
	BackgroundColor3 = Library.AccentColor,
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 2),
	ZIndex = 102,
	Parent = PlayerProximityInner,
})

Library:AddToRegistry(ColorFrame, {
	BackgroundColor3 = "AccentColor",
}, true)

local ProximityTitleLabel = Library:CreateLabel({
	Size = UDim2.new(1, 0, 0, 20),
	Position = UDim2.fromOffset(5, 2),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Nearby Players (0)",
	ZIndex = 104,
	Parent = PlayerProximityInner,
})

local PlayerProximityTextLabelContainer = Library:Create("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Position = UDim2.fromOffset(0, 22),
	ZIndex = 104,
	Parent = PlayerProximityInner,
})

Library:Create("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 2),
	Parent = PlayerProximityTextLabelContainer,
})

Library:Create("UIPadding", {
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
	PaddingTop = UDim.new(0, 4),
	PaddingBottom = UDim.new(0, 6),
	Parent = PlayerProximityTextLabelContainer,
})

Library:MakeDraggable(PlayerProximityOuter)

local function ClearPlayerLabels()
	for plr, label in pairs(PlayerLabels) do
		if label then
			label:Destroy()
		end
	end
	table.clear(PlayerLabels)
end

local function UpdateProximityList()
	if not PlayerProximityWindowVisible then
		return
	end

	local localChar = player.Character
	local localRoot = localChar and localChar:FindFirstChild("HumanoidRootPart")

	local activePlayers = {}
	local count = 0

	if localRoot then
		for _, plr in ipairs(Players:GetPlayers()) do
			-- Exclude LocalPlayer
			if plr ~= player then
				local char = plr.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				local hum = char and char:FindFirstChildOfClass("Humanoid")

				if root and hum and hum.Health > 0 then
					local distance = math.floor((localRoot.Position - root.Position).Magnitude)
					if distance <= ProximityMaxDistance then
						count += 1
						activePlayers[plr] = distance
					end
				end
			end
		end
	end

	ProximityTitleLabel.Text = string.format("Nearby Players (%d)", count)

	-- Create or Update TextLabels for active nearby players
	for plr, dist in pairs(activePlayers) do
		local label = PlayerLabels[plr]
		local displayText = `{plr:GetAttribute("CharacterName")} - {dist} studs`

		if not label then
			label = Library:CreateLabel({
				Active = true,
				Text = displayText,
				TextColor3 = plr.Name == currentSpectateName and Color3.fromRGB(111, 0, 255) or Library.FontColor,
				Size = UDim2.new(1, 0, 0, 18),
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 105, -- Render above background frame (101)
				Parent = PlayerProximityTextLabelContainer,
			})

			label.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					spectatePlayer(plr)
				end
			end)

			PlayerLabels[plr] = label
		else
			label.Text = displayText
			label.TextColor3 = plr.Name == currentSpectateName and Color3.fromRGB(111, 0, 255) or Library.FontColor
		end
	end

	-- Destroy labels for players who left, died, or moved out of range
	for plr, label in pairs(PlayerLabels) do
		if not activePlayers[plr] then
			if label then
				label:Destroy()
			end
			PlayerLabels[plr] = nil
		end
	end
end

-- 3. Register UI Toggle
VisualMods:AddToggle("PlayerProximity_Toggle", {
	Text = "Player Proximity",
	Default = true,
	Callback = function(Value)
		PlayerProximityWindowVisible = Value
		if PlayerProximityOuter then
			PlayerProximityOuter.Visible = Value
		end
		if not Value then
			ClearPlayerLabels()
		end
	end,
})

-- 4. Throttled update loop (10 checks per second)
task.spawn(function()
	while true do
		if Library.Unloaded then
			ClearPlayerLabels()
			break
		end
		if PlayerProximityWindowVisible then
			pcall(UpdateProximityList)
		end
		task.wait(0.02)
	end
end)

VisualMods:AddSlider("PlayerProximityDistanceThreshold_Slider", {
	Text = "Distance Threshold",
	Default = ProximityMaxDistance,
	Min = 10,
	Max = 50000,
	Rounding = 1,
	Compact = false,

	Callback = function(Value)
		ProximityMaxDistance = Value
	end,
})

-- ============ 1. Track players ============

for _, p in ipairs(Players:GetPlayers()) do
	trackPlayer(p)
end

local GroupId = 5212858

local ModRoles = {
	Owner = true,
	Developer = true,
	["Junior Moderator"] = true,
	["Game Tester"] = true,
	Moderator = true,
	["Senior Moderator"] = true,
	["Moderation Lead"] = true,
	Contractors = true,
}

local function checkForModerator(player)
	local success, roleName = pcall(function()
		return player:GetRoleInGroup(GroupId)
	end)

	if success and ModRoles[roleName] then
		Library:Notify(("Mod in game: %s"):format(roleName), 5)
	end
end

Players.PlayerAdded:Connect(function(player)
	trackPlayer(player)

	checkForModerator(player)
end)

checkForModerator(player)

local CharacterAddedConnection = player.CharacterAdded:Connect(function()
	if NoFallDmgEnabled then
		hookFallDmgFunction()
	end
end)

-- ============ 4. Register bars ============
ESP.NewBar({
	Name = "Health",
	Side = "Left",
	Width = 10,
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

Library:OnUnload(function()
	Library.Unloaded = true
	disconnectConnections()
	DisableAllTrackedToggles()

	disconnectAllLeaderboardSpectateLoops()
	if CharacterAddedConnection then
		CharacterAddedConnection:Disconnect()
	end

	setreadonly(mt, false)
	mt.__newindex = oldNewIndex
	setreadonly(mt, true)

	if ESP and ESP.Unload then
		pcall(function()
			ESP.Unload()
		end)
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
--SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
ThemeManager:SetFolder("Project Poke")
SaveManager:SetFolder("Project Poke/Deepwoken")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()

--[[
Teleports you to depths roof for some reason

local PathfindConnections = {}
local originalCFrame

General:AddToggle("PathfindBreaker_Toggle", {
	Text = "Pathfind Breaker (Mob Blind)",
	Default = false,
	Tooltip = "Breaks NPC pathfinding by spoofing your server position",
	Callback = function(Value)
		if Value then
			-- 1. Heartbeat fires right before physics replicate to the server.
			-- We move the character to the sky so the server (and mobs) see you up there.
			table.insert(PathfindConnections, RunService.Heartbeat:Connect(function()
				local character = Players.LocalPlayer.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root then
					originalCFrame = root.CFrame
					
					-- Teleport high up to break pathfinding/MoveTo
					root.CFrame = originalCFrame + Vector3.new(0, 5000, 0)
					
					-- Optional: Spiking velocity also breaks AI prediction
					root.AssemblyLinearVelocity = Vector3.new(0, 0, 0) 
				end
			end))

			-- 2. RenderStepped fires right before your screen renders the frame.
			-- We bring you back down immediately so your screen doesn't glitch.
			table.insert(PathfindConnections, RunService.RenderStepped:Connect(function()
				local character = Players.LocalPlayer.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				
				-- Restore the CFrame so the client experiences normal gameplay
				if root and originalCFrame then
					root.CFrame = originalCFrame
					originalCFrame = nil
				end
			end))
		else
			-- Clean up the loops when toggled off
			for _, conn in ipairs(PathfindConnections) do
				conn:Disconnect()
			end
			table.clear(PathfindConnections)
			
			-- Catch the player if they toggled off in the middle of a frame
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and originalCFrame then
				root.CFrame = originalCFrame
				originalCFrame = nil
			end
		end
	end,
})

-- Register for safe unloading!
TrackToggle("PathfindBreaker_Toggle")
]]
