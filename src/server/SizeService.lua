--[[
	The single authority on player size. Every change to Current Size or
	Max Size happens here, on the server, so exploited clients can only
	ever change what they see -- never what they are.

	State is published to clients through player attributes (CurrentSize,
	MaxSize, Rebirths, GrowthMultiplier), which replicate automatically and
	save us a stream of remote events.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Server = script.Parent
local ShopService = require(Server.ShopService)

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local SizeFormula = require(Shared.SizeFormula)

local GROW_PAD_TAG = "GrowPad"
local SHRINK_PAD_TAG = "ShrinkPad"

-- How far above a pad a character still counts as standing on it.
local PAD_DETECTION_HEIGHT = 8

-- Humanoid scale values that exist on R15 rigs.
local HUMANOID_SCALE_NAMES = {
	"BodyDepthScale",
	"BodyHeightScale",
	"BodyWidthScale",
	"HeadScale",
}

type PlayerState = {
	currentSize: number,
	maxSize: number,
	rebirths: number,
	appliedScale: number,
	publishedCurrent: number,
	publishedMax: number,
	publishedMultiplier: number,
}

local stateByPlayer: { [Player]: PlayerState } = {}

local SizeService = {}

local function passFlagsFor(player: Player): SizeFormula.PassFlags
	return {
		doubleGrowth = ShopService.playerOwnsPass(player, "DoubleGrowth"),
		vip = ShopService.playerOwnsPass(player, "Vip"),
		doubleRebirthBonus = ShopService.playerOwnsPass(player, "DoubleRebirthBonus"),
	}
end

local function publishState(player: Player, state: PlayerState)
	-- Attributes replicate to every client on change, so only write them
	-- when the visible (rounded) value actually moved.
	local roundedCurrent = math.floor(state.currentSize)
	local roundedMax = math.floor(state.maxSize)
	local multiplier = SizeFormula.growthMultiplier(state.rebirths, passFlagsFor(player))

	if roundedCurrent ~= state.publishedCurrent then
		state.publishedCurrent = roundedCurrent
		player:SetAttribute("CurrentSize", roundedCurrent)
	end

	if roundedMax ~= state.publishedMax then
		state.publishedMax = roundedMax
		player:SetAttribute("MaxSize", roundedMax)

		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats ~= nil then
			local sizeValue = leaderstats:FindFirstChild("Size")
			if sizeValue ~= nil then
				sizeValue.Value = roundedMax
			end
		end
	end

	if multiplier ~= state.publishedMultiplier then
		state.publishedMultiplier = multiplier
		player:SetAttribute("GrowthMultiplier", multiplier)
	end
end

local function applyCharacterScale(player: Player, state: PlayerState)
	local character = player.Character
	if character == nil then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end

	local scale = SizeFormula.scaleForSize(state.currentSize)

	-- Speed and jump are cheap to set and must react immediately to
	-- timed boosts like Cloud Boots, so they update every tick even when
	-- the scale itself has not moved.
	local jumpBonus = if ShopService.effectActive(player, "CloudBoots")
		then 1 + GameConfig.passEffects.cloudBootsJumpBonus
		else 1

	humanoid.UseJumpPower = true
	humanoid.WalkSpeed = SizeFormula.walkSpeedForScale(scale)
	humanoid.JumpPower = math.min(SizeFormula.jumpPowerForScale(scale) * jumpBonus, 180)

	if math.abs(scale - state.appliedScale) < 0.01 then
		return
	end

	-- A missing scale value means the rig is still assembling (or is R6);
	-- leaving appliedScale untouched makes the next tick retry.
	for _, scaleName in ipairs(HUMANOID_SCALE_NAMES) do
		local scaleValue = humanoid:FindFirstChild(scaleName)
		if scaleValue == nil then
			return
		end

		scaleValue.Value = scale
	end

	state.appliedScale = scale
end

--[[
	Finds every player currently standing on a pad with the given tag.
	Spatial queries each tick beat Touched events here: no missed
	TouchEnded, no debounce bookkeeping, and pads never hold state.
]]
local function findPlayersOnPads(tag: string): { [Player]: boolean }
	local playersOnPads = {}

	for _, pad in ipairs(CollectionService:GetTagged(tag)) do
		if pad:IsA("BasePart") and pad:IsDescendantOf(workspace) then
			local region = pad.Size + Vector3.new(0, PAD_DETECTION_HEIGHT, 0)
			local center = pad.CFrame * CFrame.new(0, PAD_DETECTION_HEIGHT / 2, 0)

			for _, part in ipairs(workspace:GetPartBoundsInBox(center, region)) do
				local character = part.Parent
				if character ~= nil then
					local player = Players:GetPlayerFromCharacter(character)
					if player ~= nil then
						playersOnPads[player] = true
					end
				end
			end
		end
	end

	return playersOnPads
end

local function stepPlayer(
	player: Player,
	state: PlayerState,
	deltaSeconds: number,
	onGrowPad: boolean,
	onShrinkPad: boolean
)
	if onGrowPad then
		state.maxSize += SizeFormula.growthPerTick(state.rebirths, passFlagsFor(player))
	elseif ShopService.playerOwnsPass(player, "AutoGrow") then
		local growth = SizeFormula.growthPerTick(state.rebirths, passFlagsFor(player))
		state.maxSize += growth * GameConfig.passEffects.autoGrowFraction
	end

	if onShrinkPad then
		state.currentSize = math.max(
			GameConfig.shrink.shrunkSize,
			state.currentSize - GameConfig.shrink.shrinkPerSecond * deltaSeconds
		)
	else
		state.currentSize = math.min(
			state.maxSize,
			state.currentSize + GameConfig.growth.regrowPerSecond * deltaSeconds
		)
	end

	applyCharacterScale(player, state)
	publishState(player, state)
end

--[[
	Registers a player with their loaded save data. Called once per player
	after DataService finishes loading them.
]]
function SizeService.initializePlayer(player: Player, data: { maxSize: number, rebirths: number })
	local state: PlayerState = {
		currentSize = data.maxSize,
		maxSize = data.maxSize,
		rebirths = data.rebirths,
		appliedScale = 0,
		publishedCurrent = -1,
		publishedMax = -1,
		publishedMultiplier = -1,
	}
	stateByPlayer[player] = state

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local sizeValue = Instance.new("IntValue")
	sizeValue.Name = "Size"
	sizeValue.Value = math.floor(data.maxSize)
	sizeValue.Parent = leaderstats

	local rebirthsValue = Instance.new("IntValue")
	rebirthsValue.Name = "Rebirths"
	rebirthsValue.Value = data.rebirths
	rebirthsValue.Parent = leaderstats

	leaderstats.Parent = player
	player:SetAttribute("Rebirths", data.rebirths)

	-- Respawned characters come back at default scale; force a re-apply.
	player.CharacterAdded:Connect(function()
		state.appliedScale = 0
	end)

	publishState(player, state)
end

function SizeService.snapshot(player: Player): { maxSize: number, rebirths: number }?
	local state = stateByPlayer[player]
	if state == nil then
		return nil
	end

	return {
		maxSize = state.maxSize,
		rebirths = state.rebirths,
	}
end

function SizeService.getState(player: Player): PlayerState?
	return stateByPlayer[player]
end

--[[
	Resets progress for a rebirth. The caller (RebirthService) validates
	eligibility; this just executes the trade.
]]
function SizeService.applyRebirth(player: Player)
	local state = stateByPlayer[player]
	if state == nil then
		return
	end

	state.rebirths += 1
	state.maxSize = 0
	state.currentSize = 0
	player:SetAttribute("Rebirths", state.rebirths)

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats ~= nil then
		local rebirthsValue = leaderstats:FindFirstChild("Rebirths")
		if rebirthsValue ~= nil then
			rebirthsValue.Value = state.rebirths
		end
	end

	applyCharacterScale(player, state)
	publishState(player, state)
end

-- Instant Shrink game pass: same effect as finishing a Shrink Pad.
function SizeService.forceShrink(player: Player)
	local state = stateByPlayer[player]
	if state == nil then
		return
	end

	state.currentSize = math.min(state.currentSize, GameConfig.shrink.shrunkSize)
	applyCharacterScale(player, state)
	publishState(player, state)
end

-- City items like Meadow Surge: paid size is granted to the body
-- immediately, not drip-fed through regrowth.
function SizeService.grantMaxSize(player: Player, amount: number)
	local state = stateByPlayer[player]
	if state == nil then
		return
	end

	state.maxSize += amount
	state.currentSize += amount
	applyCharacterScale(player, state)
	publishState(player, state)
end

function SizeService.removePlayer(player: Player)
	stateByPlayer[player] = nil
end

function SizeService.start()
	local accumulated = 0

	RunService.Heartbeat:Connect(function(deltaSeconds)
		accumulated += deltaSeconds
		if accumulated < GameConfig.growth.tickSeconds then
			return
		end

		local tickSeconds = accumulated
		accumulated = 0

		local onGrowPads = findPlayersOnPads(GROW_PAD_TAG)
		local onShrinkPads = findPlayersOnPads(SHRINK_PAD_TAG)

		for player, state in pairs(stateByPlayer) do
			stepPlayer(
				player,
				state,
				tickSeconds,
				onGrowPads[player] == true,
				onShrinkPads[player] == true
			)
		end
	end)
end

return SizeService
