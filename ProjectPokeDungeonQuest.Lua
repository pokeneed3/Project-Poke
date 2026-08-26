-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Player
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local PLAYER_NAMETAG = playerGui:WaitForChild("playerStatus"):WaitForChild("Frame"):WaitForChild("playerName")

local Character, Humanoid, HumanoidRootPart

local OriginalCollision = {}

local FarmLoopRunning = false
local Connections = {}

local ApplyNoclip
local RevertNoclip
local stopAutoFarm

local DEFAULT_SPEED = 16
local DEFAULT_JUMPPOWER = 25
local DEFAULT_FARMSPEED = 200
local DEFAULT_FARMYOFFSET = 11

local ToggleSpeedEnabled = false
local ToggleJumpPowerEnabled = false
local CurrentSpeedValue = DEFAULT_SPEED
local CurrentJumpPowerValue = DEFAULT_JUMPPOWER
local CurrentFarmSpeedValue = DEFAULT_FARMSPEED
local CurrentFarmYOffset = DEFAULT_FARMYOFFSET

local AutoFarmEnabled = false
local AbilityLoopRunning = false
local InfiniteJumpEnabled = false

-- Speed / Jump
local function applySpeed()
	local hum = Humanoid or (Character and Character:FindFirstChildOfClass("Humanoid"))
	if hum then
		hum.WalkSpeed = ToggleSpeedEnabled and CurrentSpeedValue or DEFAULT_SPEED
	end
end

local function applyJumpPower()
	local hum = Humanoid or (Character and Character:FindFirstChildOfClass("Humanoid"))
	if hum then
		hum.JumpPower = ToggleJumpPowerEnabled and CurrentJumpPowerValue or DEFAULT_JUMPPOWER
	end
end

-- Character handling

local function onCharacterAdded(char)
	Character = char
	Humanoid = char:WaitForChild("Humanoid")
	HumanoidRootPart = char:WaitForChild("HumanoidRootPart")
	applySpeed()
	applyJumpPower()

	if AutoFarmEnabled then
		Humanoid.PlatformStand = true
		ApplyNoclip()
	end
end

if player.Character then
	onCharacterAdded(player.Character)
end
Connections = player.CharacterAdded:Connect(onCharacterAdded)

Connections = player.CharacterRemoving:Connect(function()
	Character = nil
	Humanoid = nil
	HumanoidRootPart = nil
end)

local playerNameplate = Character and Character:WaitForChild("playerNameplate")
local playerNameplateText = playerNameplate and playerNameplate:WaitForChild("Frame"):WaitForChild("name")

-- Library
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

Library.ShowSearch = true

local Tabs = {
	Main = Window:AddTab("Main"),
	AutoFarm = Window:AddTab("AutoFarm"),
	["UI Settings"] = Window:AddTab("UI Settings"),
}

-- ====================== MAIN TAB ======================
local TabBox = Tabs.Main:AddLeftTabbox()
local Movement = TabBox:AddTab("Movement")
local MainSettings = TabBox:AddTab("Options")

local RightTabBox = Tabs.Main:AddRightTabbox()
local General1 = RightTabBox:AddTab("General")

General1:AddToggle("ToggleStreamerMode", {
	Text = "StreamerMode",
	Default = false,
	Tooltip = "Hides your name",
	Callback = function(Value)
		if Value then
			PLAYER_NAMETAG.Text = "Project Poke"
			playerNameplateText.Text = "Project Poke"
		else
			PLAYER_NAMETAG.Text = player.Name
			playerNameplateText.Text = player.Name
		end
	end,
})

Movement:AddToggle("ToggleSpeed", {
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
	Default = DEFAULT_SPEED,
	Min = 16,
	Max = 500,
	Rounding = 0,
	Callback = function(v)
		CurrentSpeedValue = v
		applySpeed()
	end,
})

Movement:AddToggle("ToggleJumpPower", {
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
	Default = DEFAULT_JUMPPOWER,
	Min = 25,
	Max = 500,
	Rounding = 0,
	Callback = function(v)
		CurrentJumpPowerValue = v
		applyJumpPower()
	end,
})

Movement:AddToggle("ToggleInfiniteJump", {
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

-- Heartbeat for speed/jump
Connections = RunService.Heartbeat:Connect(function()
	if not Humanoid or Library.Unloaded then
		return
	end
	if ToggleSpeedEnabled then
		Humanoid.WalkSpeed = CurrentSpeedValue
	end
	if ToggleJumpPowerEnabled then
		Humanoid.JumpPower = CurrentJumpPowerValue
		Humanoid.JumpHeight = CurrentJumpPowerValue / 2.5
	end
end)

Connections = UserInputService.JumpRequest:Connect(function()
	if Library.Unloaded then
		return
	end

	if InfiniteJumpEnabled and Humanoid then
		Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)

-- ====================== AUTOFARM TAB ======================

function ApplyNoclip()
	if not Character then
		return
	end

	for _, part in ipairs(Character:GetDescendants()) do
		if part:IsA("BasePart") then
			if OriginalCollision[part] == nil then
				OriginalCollision[part] = part.CanCollide
			end
			part.CanCollide = false
		end
	end
end

function RevertNoclip()
	for part, originalValue in pairs(OriginalCollision) do
		if part and part.Parent then
			part.CanCollide = originalValue
		end
		OriginalCollision[part] = nil
	end
end

local function StandCharacter()
	if not Humanoid or Humanoid.Health <= 0 then
		return
	end

	Humanoid.PlatformStand = false
	Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
end

local function GetWeapon()
	if not Character then
		return nil
	end
	for _, v in ipairs(Character:GetDescendants()) do
		if v:IsA("BoolValue") and v.Name == "Weapon" then
			return v.Parent
		end
	end
	return nil
end

local function GetAbilities()
	local tools = {}
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") then
				table.insert(tools, item)
			end
		end
	end
	if Character then
		for _, item in ipairs(Character:GetChildren()) do
			if item:IsA("Tool") then
				table.insert(tools, item)
			end
		end
	end
	return tools
end

function stopAutoFarm()
	AutoFarmEnabled = false
	AbilityLoopRunning = false

	if Humanoid then
		Humanoid.PlatformStand = false
	end
	if HumanoidRootPart and HumanoidRootPart:FindFirstChild("AntiFall") then
		HumanoidRootPart.AntiFall:Destroy()
	end

	FarmLoopRunning = false
	RevertNoclip()
	StandCharacter()
end

-- ====================== AUTOFARM LOGIC ======================

local function getNearestMob()
	local closest, closestDist = nil, math.huge
	if not HumanoidRootPart then
		return nil
	end

	for _, v in ipairs(workspace:GetDescendants()) do
		if v:IsA("Humanoid") and v.Health > 0 and v.Parent ~= Character then
			local hrp = v.Parent:FindFirstChild("HumanoidRootPart")
				or v.Parent:FindFirstChild("Torso")
				or v.Parent:FindFirstChild("UpperTorso")
			if hrp then
				local dist = (hrp.Position - HumanoidRootPart.Position).Magnitude
				if dist < closestDist then
					closestDist = dist
					closest = hrp
				end
			end
		end
	end
	return closest
end

local function moveTo(targetCFrame, speed)
	if not HumanoidRootPart then
		return
	end

	while AutoFarmEnabled do
		local current = HumanoidRootPart.CFrame
		local distance = (current.Position - targetCFrame.Position).Magnitude

		if distance < 4 then
			HumanoidRootPart.CFrame = targetCFrame
			break
		end

		local dt = task.wait()
		local alpha = math.clamp((speed * dt) / distance, 0, 1)
		HumanoidRootPart.CFrame = current:Lerp(targetCFrame, alpha)
	end
end

local TabBox1 = Tabs.AutoFarm:AddLeftTabbox()
local FarmTab = TabBox1:AddTab("Dungeon")
local FarmOptions = TabBox1:AddTab("Options")

FarmTab:AddToggle("DungeonAutoFarmToggle", {
	Text = "Dungeon AutoFarm",
	Default = false,
	Tooltip = "Auto farm + Auto ability",

	Callback = function(Value)
		AutoFarmEnabled = Value

		if not Value then
			stopAutoFarm()
			return
		end

		if not HumanoidRootPart or not Humanoid then
			Toggles.DungeonAutoFarmToggle:SetValue(false)
			return
		end

		-- Anti fall
		if HumanoidRootPart:FindFirstChild("AntiFall") then
			HumanoidRootPart.AntiFall:Destroy()
		end

		ApplyNoclip()
		Humanoid.PlatformStand = true

		local bv = Instance.new("BodyVelocity")
		bv.Name = "AntiFall"
		bv.Velocity = Vector3.zero
		bv.MaxForce = Vector3.new(0, math.huge, 0)
		bv.Parent = HumanoidRootPart

		-- Ability loop (fires abilityEvent inside each tool)
		if not AbilityLoopRunning then
			AbilityLoopRunning = true
			task.spawn(function()
				while AutoFarmEnabled and AbilityLoopRunning do
					local Abilities = GetAbilities()

					for _, tool in ipairs(Abilities) do
						local abilityEvent = tool:FindFirstChild("abilityEvent")
						if abilityEvent and abilityEvent:IsA("RemoteEvent") then
							abilityEvent:FireServer()
						end
					end

					task.wait(1.5)
				end
				AbilityLoopRunning = false
			end)
		end

		if FarmLoopRunning then
			return
		end

		FarmLoopRunning = true

		-- Main farm loop
		task.spawn(function()
			while AutoFarmEnabled do
				local target = getNearestMob()
				if target and target.Parent and HumanoidRootPart then
					local goal = target.CFrame * CFrame.new(0, CurrentFarmYOffset, 0)
					moveTo(goal, CurrentFarmSpeedValue)

					if AutoFarmEnabled and HumanoidRootPart then
						HumanoidRootPart.CFrame =
							CFrame.lookAt(HumanoidRootPart.Position, HumanoidRootPart.Position - Vector3.new(0, 5, 0))

						local weapon = GetWeapon()
						if weapon and weapon:FindFirstChild("swing") then
							weapon.swing:FireServer()
						end
					end
				end
				task.wait(0.1)
			end
			FarmLoopRunning = false
		end)
	end,
})

FarmOptions:AddSlider("FarmSpeedSlider", {
	Text = "Farm Speed",
	Default = DEFAULT_FARMSPEED,
	Min = 100,
	Max = 1000,
	Rounding = 0,
	Callback = function(v)
		CurrentFarmSpeedValue = v
	end,
})

FarmOptions:AddSlider("FarmYOffsetSlider", {
	Text = "Farm Y Offset",
	Default = DEFAULT_FARMYOFFSET,
	Min = 1,
	Max = 100,
	Rounding = 0,
	Callback = function(v)
		CurrentFarmYOffset = v
	end,
})

-- ====================== UI SETTINGS ======================
Library:SetWatermarkVisibility(true)

local FrameTimer = tick()
local FrameCounter = 0
local FPS = 60

local WatermarkConnection = RunService.RenderStepped:Connect(function()
	FrameCounter += 1
	if (tick() - FrameTimer) >= 1 then
		FPS = FrameCounter
		FrameTimer = tick()
		FrameCounter = 0
	end
	Library:SetWatermark(
		("Poke Hub | %s fps | %s ms"):format(
			math.floor(FPS),
			math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue())
		)
	)
end)

Library.KeybindFrame.Visible = true

Library:OnUnload(function()
	WatermarkConnection:Disconnect()
	PLAYER_NAMETAG.Text = player.Name
	playerNameplateText.Text = player.Name

	if Humanoid then
		Humanoid.JumpPower = DEFAULT_JUMPPOWER
		Humanoid.WalkSpeed = DEFAULT_SPEED
	end

	task.spawn(function()
		for _, connection in Connections do
			if connection then
				connection:Disconnect()
			end
		end
	end)

	stopAutoFarm()
	Library.Unloaded = true
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
	Default = "End",
	NoUI = false,
	Text = "Menu keybind",
})

Library.ToggleKeybind = Options.MenuKeybind
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
ThemeManager:SetFolder("Project Poke")
SaveManager:SetFolder("Project Poke/specific-game")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()
