-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ============================================================
-- Configuration
-- ============================================================
local ESPConfig = {
	Enabled = true,

	-- How many times per second the ESP redraws, matching the
	-- Visuals module's ESPRefreshRate pattern.
	RefreshRate = 60,

	-- Global fallbacks (groups override these)
	BoxColor = Color3.fromRGB(255, 255, 255),
	TextColor = Color3.fromRGB(255, 255, 255),
	TextSize = 14,
	BoxStyle = "Square", -- "Square" | "Corners" | "Filled" | "3D"
	BoxThickness = 1,
	BoxTransparency = 1,

	-- Fixed screen size, snapshotted at creation. Never scales.
	FixedBoxSize = Vector2.new(60, 100),
	CornerLength = 0.25,

	MaxDistance = math.huge,
	TeamCheck = false,
	ShowBox = true,
	ShowName = true,
	ShowDistance = true,
	UseDisplayName = true,
	ShowBars = true,
	BarColor = nil,
	OcclusionCheck = false,
	Padding = 0,

	FixedBarWidth = 4,
	FixedBarLength = nil,

	FormatText = nil,
	Defaults = {},
	Groups = {},
}

-- ============================================================
-- State
-- ============================================================
local Groups = {} -- identifier -> Group instance
local GroupClassifiers = {} -- ordered list of {Name, Predicate}
local CustomBars = {} -- registered bar definitions
local Connections = {}
local lastESPUpdate = 0

-- ============================================================
-- Helpers
-- ============================================================

local function getSetting(group, key)
	local groupCfg = ESPConfig.Groups[group]
	if groupCfg and groupCfg[key] ~= nil then
		return groupCfg[key]
	end
	local defaultGroup = ESPConfig.Groups.Default
	if defaultGroup and defaultGroup[key] ~= nil then
		return defaultGroup[key]
	end
	if ESPConfig.Defaults[key] ~= nil then
		return ESPConfig.Defaults[key]
	end
	return ESPConfig[key]
end

local function safeDestroy(drawing)
	if not drawing then
		return
	end
	pcall(function()
		drawing.Visible = false
	end)
	local destroyFn = drawing.Destroy or drawing.Remove
	if destroyFn then
		pcall(destroyFn, drawing)
	end
end

local function resolveGroup(instance)
	for _, classifier in ipairs(GroupClassifiers) do
		local ok, matches = pcall(classifier.Predicate, instance)
		if ok and matches then
			return classifier.Name
		elseif not ok then
			warn("[ESP] Group classifier '" .. classifier.Name .. "' errored:", matches)
		end
	end
	if instance:IsA("Player") then
		return "Player"
	end
	return "Anything"
end

-- ============================================================
-- ESPObject (class) — one per tracked target
-- ============================================================

local ESPObject = {}
ESPObject.__index = ESPObject

local function makeBoxDrawings(style)
	local d = { Style = style }
	if style == "Corners" then
		d.TopLeftH = Drawing.new("Line")
		d.TopLeftV = Drawing.new("Line")
		d.TopRightH = Drawing.new("Line")
		d.TopRightV = Drawing.new("Line")
		d.BotLeftH = Drawing.new("Line")
		d.BotLeftV = Drawing.new("Line")
		d.BotRightH = Drawing.new("Line")
		d.BotRightV = Drawing.new("Line")
		d.All = { d.TopLeftH, d.TopLeftV, d.TopRightH, d.TopRightV, d.BotLeftH, d.BotLeftV, d.BotRightH, d.BotRightV }
		for _, line in ipairs(d.All) do
			line.Visible = false
			line.Thickness = 1
			line.Transparency = 1
			line.ZIndex = 2
		end
	elseif style == "3D" then
		d.Lines = {}
		for i = 1, 12 do
			local line = Drawing.new("Line")
			line.Visible = false
			line.Thickness = 1
			line.Transparency = 1
			line.ZIndex = 2
			d.Lines[i] = line
		end
	else
		d.Square = Drawing.new("Square")
		d.Square.Visible = false
		d.Square.Thickness = 1
		d.Square.Filled = (style == "Filled")
		d.Square.Transparency = (style == "Filled") and 0.5 or 1
		d.Square.ZIndex = 2
	end
	return d
end

local function destroyBoxDrawings(box)
	if not box then
		return
	end
	if box.All then
		for _, line in ipairs(box.All) do
			safeDestroy(line)
		end
	elseif box.Lines then
		for _, line in ipairs(box.Lines) do
			safeDestroy(line)
		end
	elseif box.Square then
		safeDestroy(box.Square)
	end
end

local function hideBoxDrawings(box)
	if not box then
		return
	end
	if box.All then
		for _, line in ipairs(box.All) do
			line.Visible = false
		end
	elseif box.Lines then
		for _, line in ipairs(box.Lines) do
			line.Visible = false
		end
	elseif box.Square then
		box.Square.Visible = false
	end
end

---Create an ESP object for a target (Player or Model).
---@param instance Player | Model
---@param groupOverride string?
---@return ESPObject?
function ESPObject.new(instance, groupOverride)
	if instance == LocalPlayer then
		return nil
	end

	local target
	if instance:IsA("Player") then
		target = {
			Instance = instance,
			Group = groupOverride or resolveGroup(instance),
			GetModel = function()
				return instance.Character
			end,
			GetName = function()
				return ESPConfig.UseDisplayName and instance.DisplayName or instance.Name
			end,
			GetTeam = function()
				return instance.Team
			end,
			IsLocal = (instance == LocalPlayer),
		}
	elseif instance:IsA("Model") then
		target = {
			Instance = instance,
			Group = groupOverride or resolveGroup(instance),
			GetModel = function()
				return instance
			end,
			GetName = function()
				local override = instance:GetAttribute("ESPName")
				return override and tostring(override) or instance.Name
			end,
			GetTeam = function()
				return nil
			end,
			IsLocal = false,
		}
	else
		return nil
	end
	if target.IsLocal then
		return nil
	end

	-- Snapshot locked dimensions ONCE at creation. Never re-read.
	local fixed = getSetting(target.Group, "FixedBoxSize") or Vector2.new(60, 100)
	local pad = getSetting(target.Group, "Padding") or 0

	local self = setmetatable({}, ESPObject)
	self.Instance = instance
	self.Target = target
	self.NeedsRefresh = false

	self._LockedSize = Vector2.new(fixed.X + pad * 2, fixed.Y + pad * 2)
	self._LockedBarWidth = getSetting(target.Group, "FixedBarWidth") or 4
	self._LockedBarLength = getSetting(target.Group, "FixedBarLength")

	-- Box
	self.Box = makeBoxDrawings(getSetting(target.Group, "BoxStyle"))

	-- Name text
	self.Name = Drawing.new("Text")
	self.Name.Visible = false
	self.Name.Color = getSetting(target.Group, "TextColor")
	self.Name.Size = getSetting(target.Group, "TextSize")
	self.Name.Center = true
	self.Name.Outline = true
	self.Name.OutlineColor = Color3.fromRGB(0, 0, 0)
	self.Name.ZIndex = 4

	-- Bars
	self.Bars = {}
	for _, barDef in ipairs(CustomBars) do
		self:_createBar(barDef, target.Group)
	end

	return self
end

function ESPObject:_createBar(barDef, group)
	if barDef.Groups and not table.find(barDef.Groups, group) then
		return
	end

	local outline = Drawing.new("Square")
	outline.Visible = false
	outline.Color = Color3.fromRGB(0, 0, 0)
	outline.Thickness = 1
	outline.Filled = true
	outline.Transparency = 0.8
	outline.ZIndex = 2

	local fill = Drawing.new("Square")
	fill.Visible = false
	fill.Color = barDef.Color or Color3.fromRGB(0, 255, 0)
	fill.Thickness = 1
	fill.Filled = true
	fill.Transparency = 1
	fill.ZIndex = 3

	self.Bars[barDef.Name] = { Outline = outline, Fill = fill, Def = barDef }
end

---Refresh the target's group (reassign bars if group changed).
function ESPObject:refreshGroup()
	local newGroup = resolveGroup(self.Instance)
	if newGroup == self.Target.Group then
		return
	end
	self.Target.Group = newGroup

	for _, barDef in ipairs(CustomBars) do
		local applies = not barDef.Groups or table.find(barDef.Groups, newGroup) ~= nil
		local existing = self.Bars[barDef.Name]
		if applies and not existing then
			self:_createBar(barDef, newGroup)
		elseif not applies and existing then
			safeDestroy(existing.Outline)
			safeDestroy(existing.Fill)
			self.Bars[barDef.Name] = nil
		end
	end
end

function ESPObject:_isValid()
	local model = self.Target.GetModel()
	if not model then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart")
	if root and (not humanoid or humanoid.Health > 0) then
		return model, root, humanoid
	end
	return nil
end

function ESPObject:_projectBox(root, group)
	local sp = Camera:WorldToViewportPoint(root.Position)
	if sp.Z <= 0 then
		return nil
	end

	local w = self._LockedSize.X
	local h = self._LockedSize.Y
	return sp.X - w * 0.5, sp.Y - h * 0.5, sp.X + w * 0.5, sp.Y + h * 0.5
end

function ESPObject:_drawBox(group, x, y, w, h)
	local box = self.Box
	local color = getSetting(group, "BoxColor")
	local thickness = getSetting(group, "BoxThickness")
	local transparency = getSetting(group, "BoxTransparency")
	local wantedStyle = getSetting(group, "BoxStyle")

	if box.Style ~= wantedStyle then
		destroyBoxDrawings(box)
		self.Box = makeBoxDrawings(wantedStyle)
		box = self.Box
	end

	if wantedStyle == "Corners" then
		local cl = getSetting(group, "CornerLength")
		local hLen, vLen = w * cl, h * cl
		local function setLine(line, x1, y1, x2, y2)
			line.From = Vector2.new(x1, y1)
			line.To = Vector2.new(x2, y2)
			line.Color = color
			line.Thickness = thickness
			line.Transparency = transparency
			line.Visible = true
		end
		setLine(box.TopLeftH, x, y, x + hLen, y)
		setLine(box.TopLeftV, x, y, x, y + vLen)
		setLine(box.TopRightH, x + w, y, x + w - hLen, y)
		setLine(box.TopRightV, x + w, y, x + w, y + vLen)
		setLine(box.BotLeftH, x, y + h, x + hLen, y + h)
		setLine(box.BotLeftV, x, y + h, x, y + h - vLen)
		setLine(box.BotRightH, x + w, y + h, x + w - hLen, y + h)
		setLine(box.BotRightV, x + w, y + h, x + w, y + h - vLen)
	elseif wantedStyle == "3D" then
		local off = 4
		local lines = box.Lines
		local pts = {
			Vector2.new(x, y),
			Vector2.new(x + w, y),
			Vector2.new(x + w, y + h),
			Vector2.new(x, y + h),
		}
		local back = {}
		for i, p in ipairs(pts) do
			back[i] = Vector2.new(p.X + off, p.Y - off)
		end
		local edges = {
			{ pts[1], pts[2] },
			{ pts[2], pts[3] },
			{ pts[3], pts[4] },
			{ pts[4], pts[1] },
			{ back[1], back[2] },
			{ back[2], back[3] },
			{ back[3], back[4] },
			{ back[4], back[1] },
			{ pts[1], back[1] },
			{ pts[2], back[2] },
			{ pts[3], back[3] },
			{ pts[4], back[4] },
		}
		for i = 1, 12 do
			local line = lines[i]
			local e = edges[i]
			line.From = e[1]
			line.To = e[2]
			line.Color = color
			line.Thickness = thickness
			line.Transparency = transparency
			line.Visible = true
		end
	else
		box.Square.Size = Vector2.new(w, h)
		box.Square.Position = Vector2.new(x, y)
		box.Square.Color = color
		box.Square.Thickness = thickness
		box.Square.Transparency = (wantedStyle == "Filled") and 0.5 or transparency
		box.Square.Filled = (wantedStyle == "Filled")
		box.Square.Visible = true
	end
end

function ESPObject:_hide()
	hideBoxDrawings(self.Box)
	self.Name.Visible = false
	for _, barDrawings in pairs(self.Bars) do
		barDrawings.Outline.Visible = false
		barDrawings.Fill.Visible = false
	end
end

---Main draw method. Called by the group each refresh tick.
function ESPObject:draw()
	local target = self.Target
	local group = target.Group

	if self.NeedsRefresh then
		self.NeedsRefresh = false
		self:refreshGroup()
		group = target.Group
	end

	local char, root = self:_isValid()
	if not char then
		self:_hide()
		return
	end

	local distance = (Camera.CFrame.Position - root.Position).Magnitude
	local maxDist = getSetting(group, "MaxDistance")
	if maxDist and distance > maxDist then
		self:_hide()
		return
	end

	local isTeammate = getSetting(group, "TeamCheck")
		and LocalPlayer.Team ~= nil
		and target.GetTeam() == LocalPlayer.Team
	if isTeammate then
		self:_hide()
		return
	end

	if getSetting(group, "OcclusionCheck") then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char, LocalPlayer.Character }
		local result = Workspace:Raycast(Camera.CFrame.Position, root.Position - Camera.CFrame.Position, params)
		if result then
			self:_hide()
			return
		end
	end

	local minX, minY, maxX, maxY = self:_projectBox(root, group)
	if not minX then
		self:_hide()
		return
	end

	local boxX, boxY = minX, minY
	local width = maxX - minX
	local height = maxY - minY

	if getSetting(group, "ShowBox") then
		self:_drawBox(group, boxX, boxY, width, height)
	else
		hideBoxDrawings(self.Box)
	end

	-- Bars
	if getSetting(group, "ShowBars") then
		local fixedBarWidth = self._LockedBarWidth
		local fixedBarLength = self._LockedBarLength
		local leftOffset, rightOffset, bottomOffset = 4, 4, 4
		local barSpacing = 2

		for _, barDef in ipairs(CustomBars) do
			local barDrawings = self.Bars[barDef.Name]
			if barDrawings then
				local curVal, maxVal = barDef.GetValue(char, self.Instance)
				maxVal = (maxVal and maxVal > 0) and maxVal or 100
				local ratio = math.clamp((curVal or 0) / maxVal, 0, 1)
				local barWidth = barDef.Width or fixedBarWidth
				local lengthLimit = (barDef.Side == "Bottom") and (fixedBarLength or self._LockedSize.X)
					or (fixedBarLength or self._LockedSize.Y)

				if barDef.Side == "Right" then
					local barX = boxX + width + rightOffset
					rightOffset = rightOffset + barWidth + barSpacing + 2
					barDrawings.Outline.Position = Vector2.new(barX - 1, boxY - 1)
					barDrawings.Outline.Size = Vector2.new(barWidth + 2, lengthLimit + 2)
					local fillLength = math.floor(lengthLimit * ratio)
					barDrawings.Fill.Position = Vector2.new(barX, boxY + (lengthLimit - fillLength))
					barDrawings.Fill.Size = Vector2.new(barWidth, fillLength)
				elseif barDef.Side == "Bottom" then
					local barY = boxY + height + bottomOffset
					bottomOffset = bottomOffset + barWidth + barSpacing + 2
					barDrawings.Outline.Position = Vector2.new(boxX - 1, barY - 1)
					barDrawings.Outline.Size = Vector2.new(lengthLimit + 2, barWidth + 2)
					local fillLength = math.floor(lengthLimit * ratio)
					barDrawings.Fill.Position = Vector2.new(boxX, barY)
					barDrawings.Fill.Size = Vector2.new(fillLength, barWidth)
				else
					leftOffset = leftOffset + barWidth
					local barX = boxX - leftOffset
					leftOffset = leftOffset + barSpacing + 2
					barDrawings.Outline.Position = Vector2.new(barX - 1, boxY - 1)
					barDrawings.Outline.Size = Vector2.new(barWidth + 2, lengthLimit + 2)
					local fillLength = math.floor(lengthLimit * ratio)
					barDrawings.Fill.Position = Vector2.new(barX, boxY + (lengthLimit - fillLength))
					barDrawings.Fill.Size = Vector2.new(barWidth, fillLength)
				end

				local groupBarColor = getSetting(group, "BarColor")
				if groupBarColor then
					barDrawings.Fill.Color = groupBarColor
				elseif barDef.LerpColor then
					barDrawings.Fill.Color = Color3.fromRGB(255, 0, 0):Lerp(Color3.fromRGB(0, 255, 0), ratio)
				else
					barDrawings.Fill.Color = barDef.Color or Color3.fromRGB(0, 255, 0)
				end

				barDrawings.Outline.Visible = true
				barDrawings.Fill.Visible = (ratio > 0)
			end
		end
	else
		for _, barDrawings in pairs(self.Bars) do
			barDrawings.Outline.Visible = false
			barDrawings.Fill.Visible = false
		end
	end

	-- Text
	local showName = getSetting(group, "ShowName")
	local showDist = getSetting(group, "ShowDistance")

	if showName or showDist then
		local finalText
		if ESPConfig.FormatText then
			local ok, result = pcall(ESPConfig.FormatText, target, char, distance, group)
			if ok and result then
				finalText = result
			end
		end
		if not finalText then
			local parts = {}
			if showName then
				table.insert(parts, target.GetName())
			end
			if showDist then
				table.insert(parts, "[" .. math.floor(distance) .. "m]")
			end
			finalText = table.concat(parts, " ")
		end
		if #finalText > 0 then
			local textSize = getSetting(group, "TextSize")
			self.Name.Text = finalText
			self.Name.Color = getSetting(group, "TextColor")
			self.Name.Size = textSize
			self.Name.Position = Vector2.new((minX + maxX) / 2, boxY - textSize - 4)
			self.Name.Visible = true
		else
			self.Name.Visible = false
		end
	else
		self.Name.Visible = false
	end
end

---Tear down all drawings for this object.
function ESPObject:detach()
	destroyBoxDrawings(self.Box)
	safeDestroy(self.Name)
	for _, barDrawings in pairs(self.Bars) do
		safeDestroy(barDrawings.Outline)
		safeDestroy(barDrawings.Fill)
	end
	self.Bars = {}
end

-- ============================================================
-- Group (class) — holds ESPObjects by identifier
-- ============================================================

local Group = {}
Group.__index = Group

function Group.new(identifier)
	return setmetatable({
		Identifier = identifier,
		Objects = {},
	}, Group)
end

function Group:insert(instance, object)
	self.Objects[instance] = object
end

function Group:remove(instance)
	local object = self.Objects[instance]
	if not object then
		return nil
	end
	self.Objects[instance] = nil
	return object
end

function Group:update()
	for _, object in pairs(self.Objects) do
		local ok, err = pcall(function()
			object:draw()
		end)
		if not ok then
			object:_hide()
			warn("[ESP] draw failed for", object.Instance, "-", err)
		end
	end
end

function Group:detach()
	for _, object in pairs(self.Objects) do
		object:detach()
	end
	self.Objects = {}
end

-- ============================================================
-- Object management
-- ============================================================

---Track a Player or Model instance as an ESP target.
local function Track(instance, groupOverride)
	if not instance then
		return
	end
	if instance == LocalPlayer then
		return
	end

	local identifier = groupOverride or resolveGroup(instance)
	local group = Groups[identifier] or Group.new(identifier)
	Groups[identifier] = group

	if group.Objects[instance] then
		return
	end

	local object = ESPObject.new(instance, groupOverride)
	if not object then
		return
	end

	group:insert(instance, object)
end

---Untrack an instance and remove all its drawings.
local function Untrack(instance)
	for _, group in pairs(Groups) do
		local object = group:remove(instance)
		if object then
			object:detach()
			return
		end
	end
end

---Refresh group assignment of an instance (marks for re-eval next tick).
local function RefreshGroup(instance)
	for _, group in pairs(Groups) do
		local object = group.Objects[instance]
		if object then
			object.NeedsRefresh = true
			return
		end
	end
end

-- ============================================================
-- Group registration
-- ============================================================

local function RegisterGroup(name, predicate, atFront)
	assert(type(name) == "string", "Group name must be a string")
	assert(type(predicate) == "function", "predicate must be function(instance) -> boolean")

	for i, c in ipairs(GroupClassifiers) do
		if c.Name == name then
			if atFront then
				table.remove(GroupClassifiers, i)
				break
			else
				c.Predicate = predicate
				for _, group in pairs(Groups) do
					for _, object in pairs(group.Objects) do
						object.NeedsRefresh = true
					end
				end
				return
			end
		end
	end

	if atFront then
		table.insert(GroupClassifiers, 1, { Name = name, Predicate = predicate })
	else
		table.insert(GroupClassifiers, { Name = name, Predicate = predicate })
	end

	for _, group in pairs(Groups) do
		for _, object in pairs(group.Objects) do
			object.NeedsRefresh = true
		end
	end
end

local function UnregisterGroup(name)
	for i, c in ipairs(GroupClassifiers) do
		if c.Name == name then
			table.remove(GroupClassifiers, i)
			for _, group in pairs(Groups) do
				for _, object in pairs(group.Objects) do
					object.NeedsRefresh = true
				end
			end
			return true
		end
	end
	return false
end

-- ============================================================
-- Bar API
-- ============================================================

local function NewBar(args)
	assert(type(args) == "table", "NewBar expects a table of arguments")
	assert(args.Name, "Bar must have a unique 'Name'")
	assert(type(args.GetValue) == "function", "Bar must provide a 'GetValue(char, instance)' function")
	assert(args.Groups == nil or type(args.Groups) == "table", "Bar 'Groups' must be an array")

	for _, def in ipairs(CustomBars) do
		assert(def.Name ~= args.Name, "A bar named '" .. args.Name .. "' already exists")
	end

	local barDef = {
		Name = args.Name,
		Side = args.Side or "Left",
		Width = args.Width,
		MinWidth = args.MinWidth or 1,
		MaxWidth = args.MaxWidth or 999,
		Color = args.Color or Color3.fromRGB(0, 255, 0),
		LerpColor = args.LerpColor or false,
		GetValue = args.GetValue,
		Groups = args.Groups,
	}
	table.insert(CustomBars, barDef)

	for _, group in pairs(Groups) do
		for _, object in pairs(group.Objects) do
			if not object.Bars[barDef.Name] then
				object:_createBar(barDef, object.Target.Group)
			end
		end
	end

	local handle = {}

	function handle.Remove()
		for i, def in ipairs(CustomBars) do
			if def.Name == barDef.Name then
				table.remove(CustomBars, i)
				break
			end
		end
		for _, group in pairs(Groups) do
			for _, object in pairs(group.Objects) do
				local b = object.Bars[barDef.Name]
				if b then
					safeDestroy(b.Outline)
					safeDestroy(b.Fill)
					object.Bars[barDef.Name] = nil
				end
			end
		end
		handle.Removed = true
	end

	function handle.SetColor(color)
		barDef.Color = color
		barDef.LerpColor = false
	end
	function handle.SetSide(side)
		barDef.Side = side
	end
	function handle.SetWidth(width)
		barDef.Width = width
	end
	function handle.SetWidthClamp(minW, maxW)
		barDef.MinWidth = minW or barDef.MinWidth
		barDef.MaxWidth = maxW or barDef.MaxWidth
	end
	function handle.SetGroups(groups)
		barDef.Groups = groups
	end

	return handle
end

-- ============================================================
-- Render loop (throttled by RefreshRate)
-- ============================================================

local renderConnection = RunService.RenderStepped:Connect(function()
	local interval = 1 / math.max(1, ESPConfig.RefreshRate or 60)
	if os.clock() - lastESPUpdate < interval then
		return
	end
	lastESPUpdate = os.clock()

	if not ESPConfig.Enabled then
		for _, group in pairs(Groups) do
			for _, object in pairs(group.Objects) do
				object:_hide()
			end
		end
		return
	end

	for _, group in pairs(Groups) do
		group:update()
	end
end)

-- ============================================================
-- Camera change
-- ============================================================

table.insert(
	Connections,
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		Camera = Workspace.CurrentCamera
	end)
)

-- ============================================================
-- Unload
-- ============================================================

local function Unload()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	for _, conn in ipairs(Connections) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	table.clear(Connections)

	for identifier, group in pairs(Groups) do
		group:detach()
		Groups[identifier] = nil
	end

	table.clear(CustomBars)
	table.clear(GroupClassifiers)
end

-- ============================================================
-- Public API (unchanged shape)
-- ============================================================

return {
	Config = ESPConfig,
	Groups = Groups,
	NewBar = NewBar,
	Track = Track,
	Untrack = Untrack,
	Unload = Unload,
	RegisterGroup = RegisterGroup,
	UnregisterGroup = UnregisterGroup,
	RefreshGroup = RefreshGroup,
}
