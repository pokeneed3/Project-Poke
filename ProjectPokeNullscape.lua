local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local clientModules = nil
local GiftClient = nil

local function requireChild(parent, childName)
	local child = parent and parent:FindFirstChild(childName)
	if not child then
		return nil
	end

	local ok, module = pcall(require, child)
	return ok and module or nil
end

local ReplicationClient = nil
local GiftClientHandler = nil

local function loadGiftClients()
	clientModules = ReplicatedFirst:FindFirstChild("ClientModules")
	GiftClient = clientModules and clientModules:FindFirstChild("GiftClient")
	ReplicationClient = requireChild(GiftClient, "ReplicationClient")
	GiftClientHandler = requireChild(GiftClient, "GiftClientHandler")
end

loadGiftClients()
local MovementGiftMagnet = game.ReplicatedStorage:FindFirstChild("Events")
	and game.ReplicatedStorage.Events.MovementGiftMagnet

local PICKUP_RADIUS = 32
local SYNC_WAIT = 0.1
local ROUND_TIMEOUT = 0.5
local ALTAR_TP_WAIT = 0.4
local ALTAR_FIRE_WAIT = 0.3
local FIRE_RETRY_COUNT = 3
local FIRE_RETRY_INTERVAL = 0.15
local RESET_Y = 100
local HEARTBEAT_COLLECT_INTERVAL = 0.1
local MAGNET_UPDATE_INTERVAL = 0.15

local ROOM_DEBOUNCE_TIME = 1.0
local ROOM_WAIT_TIMEOUT = 10.0
local ROOM_MIN_COUNT = 1

local MAGNET_PARAMS = {
	ActualMultiplier = 999,
	GlobalDivide = 0.001,
	Multiplier = 999,
	Add = 999,
	SpiritAdd = 999,
	Squish = 0.001,
	Disable = false,
}
local MAGNET_RESET = {
	ActualMultiplier = 1,
	GlobalDivide = 1,
	Multiplier = 1,
	Add = 0,
	SpiritAdd = 0,
	Squish = 1,
	Disable = true,
}

local EXCLUDED_ALTARS = {
	Purification = true,
	Protection = true,
	Chaos = true,
}

local ALTAR_PRIORITY = {
	Purgatory = 1,
	Echo = 2,
	Chance = 3,
	Passage = 3,
}

local player = Players.LocalPlayer
local enabled = false
local mainTask = nil
local heartbeatConn = nil
local roomsLoaded = false
local roomLoadConn = nil
local lastRoomAddedTime = 0
local lastHeartbeatCollectTime = 0
local lastMagnetUpdateTime = 0

local fireProximityPrompt = rawget(_G, "fireproximityprompt")
local setProximityPromptDuration = rawget(_G, "setproximitypromptduration")

if type(fireProximityPrompt) ~= "function" then
	fireProximityPrompt = nil
end
if type(setProximityPromptDuration) ~= "function" then
	setProximityPromptDuration = nil
end

local function getGifts()
	local gifts = GiftClientHandler and GiftClientHandler.Gifts
	return type(gifts) == "table" and gifts or nil
end

local function updateMagnet(params, force)
	if not MovementGiftMagnet or not MovementGiftMagnet.Parent then
		local events = game.ReplicatedStorage:FindFirstChild("Events")
		MovementGiftMagnet = events and events:FindFirstChild("MovementGiftMagnet")
	end

	if not MovementGiftMagnet or not MovementGiftMagnet.Parent then
		return
	end

	if not force and os.clock() - lastMagnetUpdateTime < MAGNET_UPDATE_INTERVAL then
		return
	end

	lastMagnetUpdateTime = os.clock()
	pcall(function()
		MovementGiftMagnet:Fire(params)
	end)
end

local function getRoot()
	local char = player.Character
	if not char then
		return nil
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root or not root.Parent then
		return nil
	end
	return root
end

local function getGiftPosition(gift)
	if not gift then
		return nil
	end
	if typeof(gift.Position) == "Vector3" then
		return gift.Position
	end
	if gift.Model and typeof(gift.Model) == "Instance" and gift.Model:IsA("Model") then
		local pp = gift.Model.PrimaryPart
		if pp and pp.Parent then
			return pp.Position
		end
		local part = gift.Model:FindFirstChildWhichIsA("BasePart")
		if part then
			return part.Position
		end
	end
	if typeof(gift.Instance) == "Instance" and gift.Instance:IsA("BasePart") then
		return gift.Instance.Position
	end
	if typeof(gift.Part) == "Instance" and gift.Part:IsA("BasePart") then
		return gift.Part.Position
	end
	return nil
end

local function getPromptWorldPosition(prompt)
	if prompt:IsA("ProximityPrompt") then
		local parent = prompt.Parent
		if parent and parent:IsA("BasePart") then
			return parent.Position
		end
		local current = prompt
		while current and current.Parent do
			current = current.Parent
			if current:IsA("BasePart") then
				return current.Position
			end
		end
		if parent and parent:IsA("Model") then
			if parent.PrimaryPart then
				return parent.PrimaryPart.Position
			end
			local part = parent:FindFirstChildWhichIsA("BasePart")
			if part then
				return part.Position
			end
		end
	end
	return nil
end

local function findAltarPrompt(altarModel)
	local promptFolder = altarModel:FindFirstChild("Prompt")
	if promptFolder then
		local innerPrompt = promptFolder:FindFirstChild("Prompt")
		if innerPrompt and innerPrompt:IsA("ProximityPrompt") then
			return innerPrompt
		end
		for _, child in ipairs(promptFolder:GetChildren()) do
			if child:IsA("ProximityPrompt") then
				return child
			end
		end
	end
	for _, desc in ipairs(altarModel:GetDescendants()) do
		if desc:IsA("ProximityPrompt") then
			return desc
		end
	end
	return nil
end

local function findAltarRealName(altarModel)
	local rn = altarModel:FindFirstChild("RealName")
	if rn and rn:IsA("ValueBase") then
		return rn.Value
	end
	for _, desc in ipairs(altarModel:GetDescendants()) do
		if desc.Name == "RealName" and desc:IsA("ValueBase") then
			return desc.Value
		end
	end
	return nil
end

local function findAltarAncestor(instance)
	local current = instance.Parent
	while current do
		if string.find(current.Name, "Altar") or current:FindFirstChild("RealName") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function startRoomLoadListener()
	roomsLoaded = false
	lastRoomAddedTime = os.clock()

	if roomLoadConn then
		pcall(function()
			roomLoadConn:Disconnect()
		end)
		roomLoadConn = nil
	end

	local currentRooms = workspace:FindFirstChild("CurrentRooms")
	if not currentRooms then
		local elapsed = 0
		while enabled and elapsed < 10 do
			currentRooms = workspace:FindFirstChild("CurrentRooms")
			if currentRooms then
				break
			end
			task.wait(0.2)
			elapsed += 0.2
		end
		if not currentRooms then
			return false
		end
	end

	roomLoadConn = currentRooms.ChildAdded:Connect(function(child)
		lastRoomAddedTime = os.clock()
	end)

	local existingCount = #currentRooms:GetChildren()
	if existingCount > 0 then
		lastRoomAddedTime = os.clock()
	end

	local startTime = os.clock()
	while enabled do
		local elapsed = os.clock() - startTime
		if elapsed > ROOM_WAIT_TIMEOUT then
			break
		end

		local timeSinceLastRoom = os.clock() - lastRoomAddedTime
		local currentCount = #currentRooms:GetChildren()

		if timeSinceLastRoom >= ROOM_DEBOUNCE_TIME then
			if currentCount >= ROOM_MIN_COUNT then
				roomsLoaded = true
				break
			end
		end

		task.wait(0.1)
	end

	if roomLoadConn then
		pcall(function()
			roomLoadConn:Disconnect()
		end)
		roomLoadConn = nil
	end

	return roomsLoaded
end

local function findAndActivateAltars()
	if not startRoomLoadListener() then
		return 0
	end

	local currentRooms = workspace:FindFirstChild("CurrentRooms")
	if not currentRooms then
		return 0
	end

	local altars = {}
	local seenPrompts = {}

	for _, room in ipairs(currentRooms:GetChildren()) do
		if not room or not room.Parent then
			continue
		end

		local foundAltar = false
		for _, desc in ipairs(room:GetDescendants()) do
			if desc:IsA("ProximityPrompt") then
				continue
			end

			local nameMatch = string.find(desc.Name, "Altar") ~= nil
			local hasRealName = desc:FindFirstChild("RealName") ~= nil

			if nameMatch or hasRealName then
				local prompt = findAltarPrompt(desc)
				if prompt and not seenPrompts[prompt] then
					seenPrompts[prompt] = true
					foundAltar = true

					local realName = findAltarRealName(desc)
					if not realName then
						realName = desc.Name
					end
					if EXCLUDED_ALTARS[realName] then
						continue
					end

					local pos = getPromptWorldPosition(prompt)
					if not pos then
						if desc:IsA("Model") and desc.PrimaryPart then
							pos = desc.PrimaryPart.Position
						elseif desc:IsA("BasePart") then
							pos = desc.Position
						else
							local ok, p = pcall(function()
								return desc:GetPivot().Position
							end)
							if ok then
								pos = p
							end
						end
					end
					if not pos then
						continue
					end

					table.insert(altars, {
						priority = ALTAR_PRIORITY[realName] or 99,
						prompt = prompt,
						name = realName,
						room = room.Name,
						position = pos,
					})
				end
			end
		end

		if not foundAltar then
			for _, desc in ipairs(room:GetDescendants()) do
				if desc:IsA("ProximityPrompt") and not seenPrompts[desc] then
					local altarAncestor = findAltarAncestor(desc)
					if altarAncestor then
						seenPrompts[desc] = true
						foundAltar = true

						local realName = findAltarRealName(altarAncestor)
						if not realName then
							realName = altarAncestor.Name
						end
						if EXCLUDED_ALTARS[realName] then
							continue
						end

						local pos = getPromptWorldPosition(desc)
						if not pos then
							if altarAncestor:IsA("Model") and altarAncestor.PrimaryPart then
								pos = altarAncestor.PrimaryPart.Position
							elseif altarAncestor:IsA("BasePart") then
								pos = altarAncestor.Position
							else
								local ok, p = pcall(function()
									return altarAncestor:GetPivot().Position
								end)
								if ok then
									pos = p
								end
							end
						end
						if not pos then
							continue
						end

						table.insert(altars, {
							priority = ALTAR_PRIORITY[realName] or 99,
							prompt = desc,
							name = realName,
							room = room.Name,
							position = pos,
						})
					end
				end
			end
		end
	end

	table.sort(altars, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		return tostring(a.room) < tostring(b.room)
	end)

	if #altars == 0 then
		return 0
	end

	local activated = 0
	for i, altar in ipairs(altars) do
		if not enabled then
			break
		end

		local root = getRoot()
		if not root then
			break
		end

		pcall(function()
			altar.prompt.Enabled = true
			altar.prompt.MaxActivationDistance = 9999
			altar.prompt.RequiresLineOfSight = false
			altar.prompt.HoldDuration = 0
		end)
		if setProximityPromptDuration then
			pcall(function()
				setProximityPromptDuration(altar.prompt, 0)
			end)
		end

		root.CFrame = CFrame.new(altar.position)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero

		task.wait(ALTAR_TP_WAIT)

		pcall(function()
			altar.prompt.Enabled = true
			altar.prompt.MaxActivationDistance = 9999
			altar.prompt.RequiresLineOfSight = false
			altar.prompt.HoldDuration = 0
		end)
		if setProximityPromptDuration then
			pcall(function()
				setProximityPromptDuration(altar.prompt, 0)
			end)
		end

		local fireSuccess = false
		for attempt = 1, FIRE_RETRY_COUNT do
			if not enabled then
				break
			end

			local ok1 = false
			if fireProximityPrompt then
				ok1 = pcall(function()
					fireProximityPrompt(altar.prompt)
				end)
			end

			local ok2 = pcall(function()
				altar.prompt:InputHoldBegin()
				task.wait(0.05)
				altar.prompt:InputHoldEnd()
			end)

			if ok1 or ok2 then
				fireSuccess = true
			end

			if fireSuccess then
				break
			end
			task.wait(FIRE_RETRY_INTERVAL)

			root = getRoot()
			if root then
				root.CFrame = CFrame.new(altar.position)
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end

		if fireSuccess then
			activated += 1
		end

		task.wait(ALTAR_FIRE_WAIT)
	end

	return activated
end

local function collectGiftsPhase()
	local lastTeleportTime = os.clock()
	local totalCollected = 0

	while enabled do
		local gifts = getGifts()
		if not gifts then
			task.wait(0.1)
			continue
		end

		updateMagnet(MAGNET_PARAMS)

		local root = getRoot()
		if not root then
			task.wait(0.3)
			continue
		end

		local bestId, bestPos, bestDist = nil, nil, math.huge

		for id, gift in pairs(gifts) do
			if not gift or gift.Collected or gift.Tripmine then
				continue
			end
			local pos = getGiftPosition(gift)
			if pos then
				local dist = (pos - root.Position).Magnitude
				if dist <= PICKUP_RADIUS then
					pcall(function()
						ReplicationClient.SendCollect(id)
					end)
				elseif dist < bestDist then
					bestId, bestPos, bestDist = id, pos, dist
				end
			end
		end

		if bestId and bestPos then
			root = getRoot()
			if not root then
				task.wait(0.1)
				continue
			end

			local gift = gifts[bestId]
			if gift and not gift.Collected and not gift.Tripmine then
				local freshPos = getGiftPosition(gift)
				if freshPos then
					bestPos = freshPos
				end
			end

			root.CFrame = CFrame.new(bestPos)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero

			task.wait(SYNC_WAIT)

			gift = gifts[bestId]
			if gift and not gift.Collected and not gift.Tripmine then
				local postPos = getGiftPosition(gift)
				if postPos then
					local newDist = (postPos - root.Position).Magnitude
					if newDist > PICKUP_RADIUS then
						root.CFrame = CFrame.new(postPos)
						root.AssemblyLinearVelocity = Vector3.zero
						root.AssemblyAngularVelocity = Vector3.zero
						task.wait(SYNC_WAIT)
					end
				end
				pcall(function()
					ReplicationClient.SendCollect(bestId)
				end)
			end

			totalCollected += 1
			lastTeleportTime = os.clock()
		else
			if os.clock() - lastTeleportTime > ROUND_TIMEOUT then
				break
			end
		end

		task.wait(0.01)
	end

	return totalCollected
end

local function startHeartbeatCollector()
	if heartbeatConn then
		pcall(function()
			heartbeatConn:Disconnect()
		end)
		heartbeatConn = nil
	end

	heartbeatConn = RunService.Heartbeat:Connect(function()
		if not enabled then
			return
		end
		if os.clock() - lastHeartbeatCollectTime < HEARTBEAT_COLLECT_INTERVAL then
			return
		end
		lastHeartbeatCollectTime = os.clock()

		local root = getRoot()
		local gifts = getGifts()
		if not root or not gifts then
			return
		end

		for id, gift in pairs(gifts) do
			if not gift or gift.Collected or gift.Tripmine then
				continue
			end
			local position = getGiftPosition(gift)
			if position and (position - root.Position).Magnitude <= PICKUP_RADIUS then
				pcall(function()
					ReplicationClient.SendCollect(id)
				end)
			end
		end
	end)
end

local function stopHeartbeatCollector()
	if heartbeatConn then
		pcall(function()
			heartbeatConn:Disconnect()
		end)
		heartbeatConn = nil
	end
end

local beaconTask

local function StartChooseBeacon()
	if beaconTask and coroutine.status(beaconTask) ~= "dead" then
		return
	end
	beaconTask = nil

	beaconTask = task.spawn(function()
		while enabled do
			local root = getRoot()
			if root then
				root.CFrame = CFrame.new(-1.018191933631897, 53.6798095703125, -9.743292808532715)
			end

			local GameStart = workspace:FindFirstChild("GameStart")
			if GameStart then
				local GameStartPrompt = GameStart:FindFirstChildWhichIsA("ProximityPrompt")
				GameStartPrompt.HoldDuration = 0
				fireproximityprompt(GameStartPrompt)
			end

			local SelectFolder = workspace:FindFirstChild("Select")
			if not SelectFolder then
				break
			end

			local Beacon = SelectFolder:FindFirstChild("3")
				or SelectFolder:FindFirstChild("2")
				or SelectFolder:FindFirstChild("1")

			if not Beacon then
				break
			end

			local Prompt = Beacon:FindFirstChildWhichIsA("ProximityPrompt")
			if not Prompt then
				break
			end

			Prompt.HoldDuration = 0

			local success, err = false, "fireproximityprompt is unavailable"
			success, err = pcall(function()
				fireproximityprompt(Prompt)
			end)

			if not success then
				warn(err)
			end

			if not enabled then
				break
			end
			task.wait(0.5)
		end

		beaconTask = nil
	end)
end

local function startMainLoop()
	mainTask = task.spawn(function()
		while enabled do
			StartChooseBeacon()
			findAndActivateAltars()
			if not enabled then
				break
			end
			task.wait(0.1)

			collectGiftsPhase()

			if not enabled then
				break
			end

			local root = getRoot()
			if root then
				root.CFrame = CFrame.new(0, RESET_Y, 0)
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
			task.wait(0.2)
		end
	end)
end

local function enable()
	if enabled then
		return
	end
	if not ReplicationClient or not GiftClientHandler then
		loadGiftClients()
	end
	if not ReplicationClient or not ReplicationClient.SendCollect or not GiftClientHandler then
		return
	end
	enabled = true
	_G.PICKUP_BONUS = 32
	lastHeartbeatCollectTime = 0

	startHeartbeatCollector()
	updateMagnet(MAGNET_PARAMS, true)

	startMainLoop()
end

local function disable()
	if not enabled then
		return
	end
	enabled = false

	if mainTask then
		pcall(task.cancel, mainTask)
		mainTask = nil
	end

	if beaconTask then
		pcall(task.cancel, beaconTask)
		beaconTask = nil
	end

	stopHeartbeatCollector()

	if roomLoadConn then
		pcall(function()
			roomLoadConn:Disconnect()
		end)
		roomLoadConn = nil
	end

	updateMagnet(MAGNET_RESET, true)
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then
		return
	end
	if input.KeyCode == Enum.KeyCode.F3 then
		if enabled then
			disable()
		else
			enable()
		end
	end
end)
