--[[
	The interactive machinery: weight plates that hold bridges extended,
	boulders that shatter for big characters, updrafts that lift small
	ones, and crusher bars on slow readable cycles. Everything is
	tag-driven like the rest of the map:

	WeightPlate (RequiredSize, BridgeName) -- combined Current Size of
	everyone standing on it must reach RequiredSize.
	MechBridge (named BridgeName, ExtendX/Y/Z) -- slides by that offset
	while its plate is held.
	CrushBoulder (CrushSize) -- shatters into flying debris on touch by
	a big-enough player, regrows later.
	Updraft (MaxLiftSize) -- pushes light bodies up its column.
	Crusher (CycleSeconds, DropHeight) -- rises and slams on a sine
	cycle; getting caught shrinks Current Size (never Max).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Server = script.Parent
local QuestService = require(Server.QuestService)
local SizeService = require(Server.SizeService)

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)

local UPDATE_INTERVAL_SECONDS = 0.1
local PLATE_DETECTION_HEIGHT = 6
local UPDRAFT_HEIGHT = 34
local CRUSH_DEBOUNCE_SECONDS = 1

local bridgeBaseCFrames: { [BasePart]: CFrame } = {}
local bridgeExtended: { [BasePart]: boolean } = {}
local shatteredBoulders: { [BasePart]: boolean } = {}
local playersInUpdraft: { [Player]: boolean } = {}
local crusherBaseCFrames: { [BasePart]: CFrame } = {}
local crushDebounce: { [Player]: number } = {}

local MechanismService = {}

local function playersOnPart(part: BasePart, extraHeight: number): { [Player]: boolean }
	local found = {}
	local region = part.Size + Vector3.new(0, extraHeight, 0)
	local center = part.CFrame * CFrame.new(0, extraHeight / 2, 0)

	for _, hit in ipairs(workspace:GetPartBoundsInBox(center, region)) do
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player ~= nil then
			found[player] = true
		end
	end

	return found
end

local function bridgeForPlate(plate: BasePart): BasePart?
	local bridgeName = plate:GetAttribute("BridgeName")
	if typeof(bridgeName) ~= "string" then
		return nil
	end

	for _, bridge in ipairs(CollectionService:GetTagged("MechBridge")) do
		if bridge:IsA("BasePart") and bridge.Name == bridgeName then
			return bridge
		end
	end

	return nil
end

local function updatePlate(plate: BasePart)
	local requiredSize = plate:GetAttribute("RequiredSize")
	local bridge = bridgeForPlate(plate)
	if typeof(requiredSize) ~= "number" or bridge == nil then
		return
	end

	if bridgeBaseCFrames[bridge] == nil then
		bridgeBaseCFrames[bridge] = bridge.CFrame
	end

	-- Combined weight: two mediums can hold what one giant can.
	local totalSize = 0
	for player in pairs(playersOnPart(plate, PLATE_DETECTION_HEIGHT)) do
		local currentSize = player:GetAttribute("CurrentSize")
		if typeof(currentSize) == "number" then
			totalSize += currentSize
		end
	end

	local shouldExtend = totalSize >= requiredSize
	if bridgeExtended[bridge] == shouldExtend then
		return
	end
	bridgeExtended[bridge] = shouldExtend

	plate.Color = if shouldExtend then Color3.fromRGB(76, 209, 55) else Color3.fromRGB(180, 90, 70)

	local function attributeOrZero(name: string): number
		local value = bridge:GetAttribute(name)

		return if typeof(value) == "number" then value else 0
	end

	local offset = Vector3.new(
		attributeOrZero("ExtendX"),
		attributeOrZero("ExtendY"),
		attributeOrZero("ExtendZ")
	)

	local duration = if shouldExtend
		then GameConfig.mechanisms.bridgeExtendSeconds
		else GameConfig.mechanisms.bridgeRetractSeconds
	local target = if shouldExtend
		then bridgeBaseCFrames[bridge] * CFrame.new(offset)
		else bridgeBaseCFrames[bridge]

	TweenService:Create(bridge, TweenInfo.new(duration, Enum.EasingStyle.Quad), {
		CFrame = target,
	}):Play()
end

local function shatterBoulder(boulder: BasePart)
	shatteredBoulders[boulder] = true

	-- Debris: chunks of the boulder flying apart, cleaned up after they
	-- have made their point.
	for _ = 1, 6 do
		local chunk = Instance.new("Part")
		chunk.Size =
			Vector3.new(1 + math.random() * 1.5, 1 + math.random() * 1.5, 1 + math.random() * 1.5)
		chunk.CFrame = boulder.CFrame
			* CFrame.new(
				(math.random() - 0.5) * 4,
				(math.random() - 0.5) * 4,
				(math.random() - 0.5) * 4
			)
		chunk.Color = boulder.Color
		chunk.Material = boulder.Material
		chunk.CanCollide = false
		chunk.AssemblyLinearVelocity = Vector3.new(
			(math.random() - 0.5) * 40,
			20 + math.random() * 20,
			(math.random() - 0.5) * 40
		)
		chunk.Parent = workspace

		task.delay(3, function()
			chunk:Destroy()
		end)
	end

	boulder.Transparency = 1
	boulder.CanCollide = false
	boulder.CanTouch = false

	task.delay(GameConfig.mechanisms.boulderRespawnSeconds, function()
		if boulder.Parent ~= nil then
			boulder.Transparency = 0
			boulder.CanCollide = true
			boulder.CanTouch = true
			shatteredBoulders[boulder] = nil
		end
	end)
end

local function watchBoulder(boulder: BasePart)
	boulder.Touched:Connect(function(hit)
		if shatteredBoulders[boulder] then
			return
		end

		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player == nil then
			return
		end

		local crushSize = boulder:GetAttribute("CrushSize")
		local currentSize = player:GetAttribute("CurrentSize")
		if
			typeof(crushSize) == "number"
			and typeof(currentSize) == "number"
			and currentSize >= crushSize
		then
			shatterBoulder(boulder)
		end
	end)
end

local function updateUpdraft(updraft: BasePart)
	local maxLift = updraft:GetAttribute("MaxLiftSize")
	if typeof(maxLift) ~= "number" then
		return
	end

	for player in pairs(playersOnPart(updraft, UPDRAFT_HEIGHT)) do
		local currentSize = player:GetAttribute("CurrentSize")
		local character = player.Character
		if typeof(currentSize) ~= "number" or character == nil or currentSize > maxLift then
			continue
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart ~= nil then
			local velocity = rootPart.AssemblyLinearVelocity
			rootPart.AssemblyLinearVelocity =
				Vector3.new(velocity.X, GameConfig.mechanisms.updraftVelocity, velocity.Z)

			-- Count the launch quest once per visit, not per tick.
			if not playersInUpdraft[player] then
				playersInUpdraft[player] = true
				QuestService.increment(player, "launches")

				task.delay(2, function()
					playersInUpdraft[player] = nil
				end)
			end
		end
	end
end

local function updateCrusher(crusher: BasePart, now: number)
	local cycleSeconds = crusher:GetAttribute("CycleSeconds")
	local dropHeight = crusher:GetAttribute("DropHeight")
	if typeof(cycleSeconds) ~= "number" or typeof(dropHeight) ~= "number" then
		return
	end

	if crusherBaseCFrames[crusher] == nil then
		crusherBaseCFrames[crusher] = crusher.CFrame
	end

	-- Sine motion: readable and predictable, which keeps the skill
	-- gentle. Squaring the descent phase adds a little "slam".
	local phase = (math.sin(now * math.pi * 2 / cycleSeconds) + 1) / 2
	crusher.CFrame = crusherBaseCFrames[crusher] * CFrame.new(0, -dropHeight * phase * phase, 0)

	if phase > 0.6 then
		for player in pairs(playersOnPart(crusher, 2)) do
			local debounceUntil = crushDebounce[player]
			if debounceUntil == nil or now > debounceUntil then
				crushDebounce[player] = now + CRUSH_DEBOUNCE_SECONDS
				SizeService.forceShrink(player)
			end
		end
	end
end

function MechanismService.start()
	for _, boulder in ipairs(CollectionService:GetTagged("CrushBoulder")) do
		if boulder:IsA("BasePart") then
			watchBoulder(boulder)
		end
	end

	CollectionService:GetInstanceAddedSignal("CrushBoulder"):Connect(function(boulder)
		if boulder:IsA("BasePart") then
			watchBoulder(boulder)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		playersInUpdraft[player] = nil
		crushDebounce[player] = nil
	end)

	local sinceUpdate = 0
	local elapsed = 0

	RunService.Heartbeat:Connect(function(deltaSeconds)
		elapsed += deltaSeconds
		sinceUpdate += deltaSeconds
		if sinceUpdate < UPDATE_INTERVAL_SECONDS then
			return
		end
		sinceUpdate = 0

		for _, plate in ipairs(CollectionService:GetTagged("WeightPlate")) do
			if plate:IsA("BasePart") and plate:IsDescendantOf(workspace) then
				updatePlate(plate)
			end
		end

		for _, updraft in ipairs(CollectionService:GetTagged("Updraft")) do
			if updraft:IsA("BasePart") and updraft:IsDescendantOf(workspace) then
				updateUpdraft(updraft)
			end
		end

		for _, crusher in ipairs(CollectionService:GetTagged("Crusher")) do
			if crusher:IsA("BasePart") and crusher:IsDescendantOf(workspace) then
				updateCrusher(crusher, elapsed)
			end
		end
	end)
end

return MechanismService
