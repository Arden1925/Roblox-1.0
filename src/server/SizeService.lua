--[[
	The single authority on player size. Every change to Current Size or
	Max Size happens here, on the server, so exploited clients can only
	ever change what they see -- never what they are.

	State is published to clients through player attributes (CurrentSize,
	MaxSize, Rebirths, GrowthMultiplier, SpeedSetting), which replicate
	automatically. Bonuses owned by other systems arrive the same way:
	PetGrowthBonus (PetService), Upgrade<Key> (EconomyService), and
	<Effect>Until timestamps (ShopService/EconomyService), which keeps
	this module free of dependencies on any of them.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Server = script.Parent
local ShopService = require(Server.ShopService)

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local SizeFormula = require(Shared.SizeFormula)

local GROW_PAD_TAG = "GrowPad"
local SHRINK_PAD_TAG = "ShrinkPad"
local AFK_POD_TAG = "AfkPod"

-- How far above a pad a character still counts as standing on it.
local PAD_DETECTION_HEIGHT = 8

-- Humanoid scale values that exist on R15 rigs.
local HUMANOID_SCALE_NAMES = {
	"BodyDepthScale",
	"BodyHeightScale",
	"BodyWidthScale",
	"HeadScale",
}

local function upgradeConfigByKey(upgradeKey: string): { [string]: any }?
	for _, upgrade in ipairs(GameConfig.upgrades) do
		if upgrade.key == upgradeKey then
			return upgrade
		end
	end

	return nil
end

local GROWTH_UPGRADE = upgradeConfigByKey("GrowthUpgrade")
local JUMP_UPGRADE = upgradeConfigByKey("JumpUpgrade")

type PlayerState = {
	currentSize: number,
	maxSize: number,
	rebirths: number,
	speedSetting: number,
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

local function attributeNumber(player: Player, name: string): number
	local value = player:GetAttribute(name)

	return if typeof(value) == "number" then value else 0
end

--[[
	The one place all growth bonuses combine: passes and rebirths, then
	the Growth Training upgrade, the equipped pet, and any timed boosts.
]]
local function totalGrowthMultiplier(player: Player, state: PlayerState): number
	local multiplier = SizeFormula.growthMultiplier(state.rebirths, passFlagsFor(player))

	if GROWTH_UPGRADE ~= nil then
		local level = attributeNumber(player, "UpgradeGrowthUpgrade")
		multiplier *= 1 + level * GROWTH_UPGRADE.bonusPerLevel
	end

	multiplier *= 1 + attributeNumber(player, "PetGrowthBonus")
	multiplier *= 1 + attributeNumber(player, "PermanentGrowthBonus")

	if ShopService.effectActive(player, "GrowthPotion") then
		multiplier *= 1.5
	end
	if ShopService.effectActive(player, "MysteryGrowth") then
		multiplier *= 3
	end

	return multiplier
end

local function publishState(player: Player, state: PlayerState)
	-- Attributes replicate to every client on change, so only write them
	-- when the visible (rounded) value actually moved.
	local roundedCurrent = math.floor(state.currentSize)
	local roundedMax = math.floor(state.maxSize)
	local multiplier = math.floor(totalGrowthMultiplier(player, state) * 100) / 100

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

-- Whether the character currently stands on the Main Island. Altitude
-- is the one test every entry route shares -- portal, landing cutscene,
-- teleport -- and no world geometry reaches within 200 studs of it.
local function isInHub(player: Player): boolean
	local character = player.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart == nil then
		return false
	end

	return rootPart.Position.Y > GameConfig.hub.surfaceY - 200
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

	-- The hub is a social space: everyone walks it at base size, and
	-- their true size comes back the moment they leave. Only the
	-- rendered scale changes; stored size, growth, and the HUD keep
	-- reporting the real numbers throughout. The InHub attribute lets
	-- PetService shrink followers to match.
	local inHub = isInHub(player)
	if player:GetAttribute("InHub") ~= inHub then
		player:SetAttribute("InHub", inHub)
	end
	if inHub then
		scale = 1
	end

	-- Speed and jump are cheap to set and must react immediately to the
	-- slider and timed boosts, so they update every tick even when the
	-- scale itself has not moved.
	local speedPotionBonus = if ShopService.effectActive(player, "SpeedPotion")
		then GameConfig.speed.potionBonus
		else 0

	local jumpBonus = if ShopService.effectActive(player, "CloudBoots")
		then 1 + GameConfig.passEffects.cloudBootsJumpBonus
		else 1
	if ShopService.effectActive(player, "JumpPotion") then
		jumpBonus *= 1.25
	end
	if JUMP_UPGRADE ~= nil then
		local level = attributeNumber(player, "UpgradeJumpUpgrade")
		jumpBonus *= 1 + level * JUMP_UPGRADE.bonusPerLevel
	end

	humanoid.UseJumpPower = true
	humanoid.WalkSpeed = SizeFormula.walkSpeed(state.speedSetting, scale, speedPotionBonus)
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
local function findPlayersOnPads(tag: string): { [Player]: BasePart }
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
						playersOnPads[player] = pad
					end
				end
			end
		end
	end

	return playersOnPads
end

--[[
	How much pad growth this player earns this tick: full on a grow pad
	(times the Golden Pad event multiplier when lit), a fraction inside
	an AFK pod, zero elsewhere.
]]
local function padMultiplierFor(player: Player, growPad: BasePart?, afkPod: BasePart?): number
	if growPad ~= nil then
		local goldenUntil = growPad:GetAttribute("GoldenUntil")
		local golden = typeof(goldenUntil) == "number"
			and goldenUntil > Workspace:GetServerTimeNow()

		return if golden then GameConfig.events.goldenPadMultiplier else 1
	end

	if afkPod ~= nil then
		return GameConfig.afkPod.growthFraction
	end

	return 0
end

local function stepPlayer(
	player: Player,
	state: PlayerState,
	deltaSeconds: number,
	padMultiplier: number,
	onShrinkPad: boolean
)
	local growth = GameConfig.growth.sizePerTick * totalGrowthMultiplier(player, state)

	if padMultiplier > 0 then
		state.maxSize += growth * padMultiplier
	elseif ShopService.playerOwnsPass(player, "AutoGrow") then
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
function SizeService.initializePlayer(
	player: Player,
	data: {
		maxSize: number,
		rebirths: number,
		permanentGrowthBonus: number?,
	}
)
	local state: PlayerState = {
		currentSize = data.maxSize,
		maxSize = data.maxSize,
		rebirths = data.rebirths,
		speedSetting = GameConfig.speed.default,
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
	player:SetAttribute("SpeedSetting", state.speedSetting)
	player:SetAttribute("PermanentGrowthBonus", data.permanentGrowthBonus or 0)

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

-- The Mega Pack's forever bonus. Published as an attribute (which the
-- growth formula reads) and persisted through the snapshot.
function SizeService.addPermanentGrowth(player: Player, amount: number)
	local current = player:GetAttribute("PermanentGrowthBonus")
	local base = if typeof(current) == "number" then current else 0
	player:SetAttribute("PermanentGrowthBonus", base + amount)
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

-- The Size Master pass slider. Clamped to the honest range: no smaller
-- than a Shrink Pad allows, no bigger than earned Max Size.
function SizeService.setDesiredSize(player: Player, value: any)
	local state = stateByPlayer[player]
	if state == nil or typeof(value) ~= "number" or value ~= value then
		return
	end

	if not ShopService.playerOwnsPass(player, "SizeMaster") then
		return
	end

	state.currentSize = math.clamp(value, GameConfig.shrink.shrunkSize, state.maxSize)
	applyCharacterScale(player, state)
	publishState(player, state)
end

function SizeService.setDesiredSpeed(player: Player, value: any)
	local state = stateByPlayer[player]
	if state == nil or typeof(value) ~= "number" or value ~= value then
		return
	end

	state.speedSetting = math.clamp(value, GameConfig.speed.minimum, GameConfig.speed.maximum)
	player:SetAttribute("SpeedSetting", state.speedSetting)
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
		local inAfkPods = findPlayersOnPads(AFK_POD_TAG)

		for player, state in pairs(stateByPlayer) do
			stepPlayer(
				player,
				state,
				tickSeconds,
				padMultiplierFor(player, onGrowPads[player], inAfkPods[player]),
				onShrinkPads[player] ~= nil
			)
		end
	end)
end

return SizeService
