-- Player
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local PLAYER_NAMETAG = player.PlayerGui.playerStatus.Frame.playerName

local Character, Humanoid, HumanoidRootPart

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

-- Define these early so onCharacterAdded can use them
local function applySpeed()
	local hum = Humanoid or (Character and Character:FindFirstChildOfClass("Humanoid"))
	if not hum then
		return
	end
	hum.WalkSpeed = ToggleSpeedEnabled and CurrentSpeedValue or DEFAULT_SPEED
end

local function applyJumpPower()
	local hum = Humanoid or (Character and Character:FindFirstChildOfClass("Humanoid"))
	if not hum then
		return
	end
	hum.JumpPower = ToggleJumpPowerEnabled and CurrentJumpPowerValue or DEFAULT_JUMPPOWER
end

-- Character handling
local function onCharacterAdded(char)
	Character = char
	Humanoid = char:WaitForChild("Humanoid")
	HumanoidRootPart = char:WaitForChild("HumanoidRootPart")

	applySpeed()
	applyJumpPower()
end

-- Connect once
if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

player.CharacterRemoving:Connect(function()
	Character = nil
	Humanoid = nil
	HumanoidRootPart = nil
end)

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
local Movement = TabBox:AddTab("Movement")
local MainSettings = TabBox:AddTab("Options")

local RightTabBox = Tabs.Main:AddRightTabbox()
local General1 = RightTabBox:AddTab("General")
local MainSettings1 = RightTabBox:AddTab("Options")

local ToggleStreamerMode = false

General1:AddToggle("ToggleStreamerMode", {
	Text = "StreamerMode",
	Default = false,
	Tooltip = "Hides your name",

	Callback = function(Value)
		ToggleStreamerMode = Value
	end,
})

Toggles.ToggleStreamerMode:OnChanged(function()
	if not Toggles.ToggleStreamerMode.Value then
		PLAYER_NAMETAG.Text = player.Name
	else
		PLAYER_NAMETAG.Text = "Project Poke"
	end
end)

--[[
player.PlayerGui.playerStatus.Frame.playerName
]]

function applySpeed()
	local hum = Humanoid or (Character and Character:FindFirstChildOfClass("Humanoid"))
	if not hum then
		return
	end
	hum.WalkSpeed = ToggleSpeedEnabled and CurrentSpeedValue or DEFAULT_SPEED
end

function applyJumpPower()
	local hum = Humanoid or (Character and Character:FindFirstChildOfClass("Humanoid"))
	if not hum then
		return
	end
	hum.JumpPower = ToggleJumpPowerEnabled and CurrentJumpPowerValue or DEFAULT_JUMPPOWER
end

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

	NoUI = false,

	Callback = function(Value)
		Toggles.ToggleSpeed:SetValue(Value)
		applySpeed()
	end,
})

MainSettings:AddSlider("SpeedSlider", {
	Text = "Speed",
	Default = DEFAULT_SPEED,
	Tooltip = "Change your WalkSpeed value",
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

	NoUI = false,

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

game:GetService("RunService").Heartbeat:Connect(function()
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

local InfiniteJumpEnabled = false

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

	NoUI = false,

	Callback = function(Value)
		Toggles.ToggleInfiniteJump:SetValue(Value)
	end,
})

game:GetService("UserInputService").JumpRequest:Connect(function()
	if Library.Unloaded then
		return
	end
	if InfiniteJumpEnabled and Humanoid then
		Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)

local function ApplyNoclip()
	for _, part in ipairs(Character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
		end
	end
end

local function RevertNoclip()
	for _, part in ipairs(Character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = true
		end
	end
end

local function GetWeapon()
	if not Character or not HumanoidRootPart then
		return nil
	end

	for _, v in Character:GetDescendants() do
		if v:IsA("BoolValue") and v.Name == "Weapon" then
			return v.Parent
		end
	end

	return nil -- nothing found
end

local function GetQAbility()
	local backpack = player:WaitForChild("Backpack")
	local tools = {}

	for _, item in ipairs(backpack:GetChildren()) do
		if item:IsA("Tool") then
			table.insert(tools, item)
		end
	end

	return tools[1]
end

local function GetEAbility()
	local backpack = player:WaitForChild("Backpack")
	local tools = {}

	for _, item in ipairs(backpack:GetChildren()) do
		if item:IsA("Tool") then
			table.insert(tools, item)
		end
	end

	return tools[2]
end

--[[

local Event = game:GetService("ReplicatedStorage").remotes.abilityUsed
	Event:FireServer("e", game:GetService("Players").LocalPlayer.Backpack.Whirlwind)

	local Event1 = game:GetService("Players").LocalPlayer.Backpack.Whirlwind.spellEvent
	Event1:FireServer()

]]

local TabBox1 = Tabs.AutoFarm:AddLeftTabbox()
local FarmTab = TabBox1:AddTab("Dungeon")
local MainSettings1 = TabBox1:AddTab("Options")

local AutoFarmEnabled = false
local AntiFall = nil

local function stopAutoFarm()
	AutoFarmEnabled = false

	if Humanoid then
		Humanoid.PlatformStand = false
	end

	if HumanoidRootPart and HumanoidRootPart:FindFirstChild("AntiFall") then
		HumanoidRootPart.AntiFall:Destroy()
	end
end

local function getNearestMob()
	local closest, closestDist = nil, math.huge
	local myHRP = HumanoidRootPart
	if not myHRP then
		return nil
	end

	for _, v in ipairs(workspace:GetDescendants()) do
		if v:IsA("Humanoid") and v.Health > 0 and v.Parent ~= Character then
			local hrp = v.Parent:FindFirstChild("HumanoidRootPart")
				or v.Parent:FindFirstChild("Torso")
				or v.Parent:FindFirstChild("UpperTorso")

			if hrp then
				local dist = (hrp.Position - myHRP.Position).Magnitude
				if dist < closestDist and dist < math.huge then -- max range
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

		if distance < 4 then -- close enough
			HumanoidRootPart.CFrame = targetCFrame
			break
		end

		-- Calculate how far to move this frame
		local alpha = math.clamp((speed * task.wait()) / distance, 0, 1)
		HumanoidRootPart.CFrame = current:Lerp(targetCFrame, alpha)
	end
end

FarmTab:AddToggle("DungeonAutoFarm", {
	Text = "Dungeon AutoFarm",
	Default = false,
	Tooltip = "Starts / stops the dungeon farm",

	Callback = function(Value)
		AutoFarmEnabled = Value

		if not Value then
			stopAutoFarm()
			RevertNoclip()
			return
		end

		if not HumanoidRootPart or not Humanoid then
			Toggles.DungeonAutoFarm:SetValue(false)
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

		-- Ability loop (runs only once)
		task.spawn(function()
			while AutoFarmEnabled do
				local eTool = GetEAbility()
				if eTool then
					local remote = game:GetService("ReplicatedStorage").remotes.abilityUsed
					remote:FireServer("e", eTool)

					local spellEvent = eTool:FindFirstChild("spellEvent")
					if spellEvent then
						spellEvent:FireServer()
					end
				end
				task.wait(2)
			end
		end)

		-- Main farm loop
		task.spawn(function()
			while AutoFarmEnabled do
				local target = getNearestMob()
				if target then
					local goal = target.CFrame * CFrame.new(0, CurrentFarmYOffset, 0)
					moveTo(goal, CurrentFarmSpeedValue) -- studs per second

					-- Look down + attack only if still enabled
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
		end)
	end,
})

MainSettings1:AddSlider("FarmSpeedSlider", {
	Text = "Farm Speed",
	Default = DEFAULT_FARMSPEED,
	Min = 100,
	Max = 1000,
	Rounding = 0,

	Callback = function(v)
		CurrentFarmSpeedValue = v
	end,
})

MainSettings1:AddSlider("FarmYOffsetSlider", {
	Text = "Farm Y Offset",
	Default = DEFAULT_FARMYOFFSET,
	Min = 1,
	Max = 100,
	Rounding = 0,

	Callback = function(v)
		CurrentFarmYOffset = v
	end,
})

local RightTabBox = Tabs.AutoFarm:AddRightTabbox()

------------------------------------------------------------------------------------------------------------------------------
Library:SetWatermarkVisibility(true)

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

	if Humanoid then
		Humanoid.JumpPower = DEFAULT_JUMPPOWER
		Humanoid.WalkSpeed = DEFAULT_SPEED
	end

	Library.Unloaded = true
end)

local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu")
MenuGroup:AddButton("Unload", function()
	Library:Unload()
end)

MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "End", NoUI = false, Text = "Menu keybind" })

Library.ToggleKeybind = Options.MenuKeybind
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
--SaveManager:SetIgnoreIndexes({ 'MenuKeybind' })
ThemeManager:SetFolder("Project Poke")
SaveManager:SetFolder("Project Poke/specific-game")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig()
