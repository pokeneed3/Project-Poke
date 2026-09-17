-- Services
local Lighting = cloneref(game:GetService("Lighting"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local Stats = game:GetService("Stats")
local UserInputService = cloneref(game:GetService("UserInputService"))

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

local function watchFolderPredicate(folder, groupName, predicate)
	if not folder then
		return
	end
	if watchedFolders[folder] then
		return
	end

	local function tryTrack(m)
		if not predicate or predicate(m) then
			ESP.Track(m, groupName)
		end
	end

	for _, m in ipairs(folder:GetChildren()) do
		tryTrack(m)
	end

	watchedFolders[folder] = {
		added = folder.ChildAdded:Connect(tryTrack),
		removed = folder.ChildRemoved:Connect(function(m)
			ESP.Untrack(m)
		end),
	}
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
				SpeedConnection = RunService.Heartbeat:Connect(function()
					local player = Players.LocalPlayer
					local character = player.Character
					if not character then
						return
					end

					local humanoid = character:FindFirstChildOfClass("Humanoid")
					local root = character:FindFirstChild("HumanoidRootPart")
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

				local humanoid = character:FindFirstChildOfClass("Humanoid")
				local root = character:FindFirstChild("HumanoidRootPart")

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
	Rounding = 0,
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
				local root = character:FindFirstChild("HumanoidRootPart")
				local humanoid = character:FindFirstChildOfClass("Humanoid")
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
	Rounding = 0,
	Compact = false,

	Callback = function(Value)
		InfJumpPowerValue = Value
	end,
})

local NoFallDmgEnabled = false

General:AddToggle("NoFallDmg_Toggle", {
	Text = "No Fall Damage",
	Default = false,
	Callback = function(Value)
		if Value then
			local WorldClient = game.Players.LocalPlayer.PlayerGui:FindFirstChild("WorldClient")
			local env = getsenv(WorldClient)

			local fallName, originalFall
			for name, value in pairs(env) do
				if type(value) == "function" and name:lower():find("fall") then
					fallName, originalFall = name, value
					break
				end
			end

			if not originalFall then
				warn("Could not find fall function")
				return
			end

			print("Hooking:", fallName)

			NoFallDmgEnabled = true

			env[fallName] = function(...)
				if NoFallDmgEnabled then
					return
				end
				return originalFall(...)
			end
		else
			NoFallDmgEnabled = false
		end
	end,
})

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
	addGroupToggle(groupName, "ShowName", "Name")
	addGroupToggle(groupName, "ShowDistance", "Distance")
	if groupName == "NPC" or groupName == "Drop" or groupName == "Chest" then
		continue
	else
		addGroupToggle(groupName, "ShowBars", "Health Bar")
		addGroupToggle(groupName, "ShowBox", "Box")
	end
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
	Rounding = 0,
	Compact = false,

	Callback = function(Value)
		ESPGroups.Player.MaxDistance = Value
	end,
})

TempStorageVisualTabBoxMain:AddToggle("ESP_HealthPercent", {
	Text = "Health Percentage",
	Default = false,
	Callback = function(value)
		for _, groupConfig in pairs(ESPGroups) do
			groupConfig.ShowHealthPercentage = value
		end
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
		if Value then
			watchFolderPredicate(folder, "Mob", isMob)
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
	Rounding = 0,
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
		if Value then
			watchFolder(folder, "NPC")
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
	Rounding = 0,
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
		if Value then
			watchFolder(folder, "Drop")
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
	Rounding = 0,
	Compact = false,

	Callback = function(Value)
		ESPGroups.Drop.MaxDistance = Value
	end,
})

TempStorageVisualTabBoxMain:AddToggle("Chest_ESP", {
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

TempStorageVisualTabBoxMain:AddSlider("ChestMaxDistance_Slider", {
	Text = "Max Distance",
	Default = 5000,
	Min = 100,
	Max = 50000,
	Rounding = 0,
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

local Original_Density = 0.7
local RemoveFogConnection

VisualMods:AddToggle("Remove_Fog", {
	Text = "No Fog",
	Default = false,

	Callback = function(Value)
		if Value then
			RemoveFogConnection = RunService.RenderStepped:Connect(function()
				Lighting.Atmosphere.Density = 0
			end)
		else
			if RemoveFogConnection then
				RemoveFogConnection:Disconnect()
			end

			Lighting.Atmosphere.Density = Original_Density
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
	Rounding = 0,
	Compact = false,

	Callback = function(Value)
		if MaxZoomToggleActive then
			CurrentMaxZoom = Value
			player.CameraMaxZoomDistance = CurrentMaxZoom
		end
	end,
})

local ScrollingFrame = player.PlayerGui.LeaderboardGui.MainFrame.ScrollingFrame

local leaderboardspectateLoops = {}
local currentSpectateLoop
local currentSpectateLabel
local currentSpectateName
local ListenForHealthChangeConnection

local function extractUsername(text)
	local username = text:match("^(.-)%s*%(") or text
	return username
end

local function findCharacterByLabelText(text)
	local username = extractUsername(text)
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Name == username then
			return plr.Character
		end
	end
	return nil
end

local function setupClick(label)
	local connection = label.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local spectateName = label.Text

			if spectateName == currentSpectateName then
				if currentSpectateLoop then
					currentSpectateLoop:Disconnect()
					currentSpectateLoop = nil
				end
				if currentSpectateLabel then
					currentSpectateLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
					currentSpectateLabel = nil
				end
				currentSpectateName = nil
				return
			end

			if currentSpectateLabel then
				currentSpectateLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			end

			if currentSpectateLoop then
				currentSpectateLoop:Disconnect()
				currentSpectateLoop = nil
			end

			if ListenForHealthChangeConnection then
				ListenForHealthChangeConnection:Disconnect()
				ListenForHealthChangeConnection = nil
			end

			if spectateName == player.Character.Name then
				if currentSpectateLabel then
					currentSpectateLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
				end

				if currentSpectateLoop then
					currentSpectateLoop:Disconnect()
					currentSpectateLoop = nil
				end
				return
			end

			if
				not findCharacterByLabelText(spectateName)
				or not findCharacterByLabelText(spectateName):FindFirstChild("Humanoid")
			then
				Library:Notify(`{findCharacterByLabelText(spectateName)} doesnt have a valid Character or Humanoid`)

				if currentSpectateLabel then
					currentSpectateLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
				end

				return
			end

			label.TextColor3 = Color3.fromRGB(111, 0, 255)
			currentSpectateLabel = label
			currentSpectateName = spectateName

			local humanoid = player.Character:FindFirstChild("Humanoid")

			if humanoid then
				local previousHealth = humanoid.Health

				ListenForHealthChangeConnection = humanoid.HealthChanged:Connect(function(newHealth)
					if newHealth < previousHealth then
						if currentSpectateLoop then
							if currentSpectateLabel then
								currentSpectateLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
							end

							currentSpectateLoop:Disconnect()
							currentSpectateLoop = nil
						end
					end
					previousHealth = newHealth
				end)
			end

			currentSpectateLoop = RunService.Heartbeat:Connect(function()
				local character = findCharacterByLabelText(spectateName)
				local humanoid = character and character:FindFirstChild("Humanoid")

				if not character or not humanoid then
					if currentSpectateLabel then
						currentSpectateLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
					end

					currentSpectateLoop:Disconnect()
					currentSpectateLoop = nil

					Library:Notify(`{findCharacterByLabelText(spectateName)} doesnt have a valid Character or Humanoid`)

					return
				end

				if humanoid then
					workspace.CurrentCamera.CameraSubject = humanoid
				end
			end)
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

	if currentSpectateLabel then
		currentSpectateLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		currentSpectateLabel = nil
	end

	currentSpectateName = nil
end

VisualMods:AddToggle("LeaderboardSpectate_Toggle", {
	Text = "Leaderboard Spectate",
	Default = false,

	Callback = function(Value)
		if Value then
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

Library:OnUnload(function()
	Library.Unloaded = true
	disconnectConnections()
	DisableAllTrackedToggles()
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
