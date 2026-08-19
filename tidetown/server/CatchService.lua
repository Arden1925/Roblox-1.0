--[[
	Runs the two-tap cast minigame with the server as the only judge:
	the ring is rolled here, the second tap is timed by the server's
	own clock, and every gate -- zone, tide phase, Tidepedia unlock,
	mount, and cooldown -- is re-checked here no matter what the client
	claims. A resolved catch feeds the Tidepedia and pays Shells; the
	creatures a player KEEPS come from eggs, which is why a catch never
	adds to the inventory.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TidetownShared = ReplicatedStorage.TidetownShared
local CatchRules = require(TidetownShared.CatchRules)
local CreatureCatalog = require(TidetownShared.CreatureCatalog)
local TideLayout = require(TidetownShared.TideLayout)
local TidetownConfig = require(TidetownShared.TidetownConfig)

local DEEP_REEF_ZONE_KEY = "DeepReef"
-- Pity resets on the named rarity OR BETTER, so rarities compare as
-- ranks instead of string-matching one exact tier.
local RARITY_RANKS: { [string]: number } = { common = 1, rare = 2, epic = 3, legendary = 4 }
local RARE_RANK = 2
local EPIC_RANK = 3

export type Dependencies = {
	getPhase: () -> string,
	awardShells: (Player, number) -> (),
	recordSpecies: (Player, string) -> boolean,
	chargeEggs: (Player) -> any,
	grantFoundEgg: (Player, string) -> boolean,
	luckPercent: (Player) -> number,
	zoneUnlocked: (Player, string) -> boolean,
	isMounted: (Player) -> (boolean, boolean),
	reportBounty: (Player, string, number) -> (),
}

type ActiveCast = {
	castId: string,
	window: CatchRules.CastWindow,
	issuedAt: number,
	zone: string,
	deepAllowed: boolean,
}

type CastState = {
	castsSinceRare: number,
	castsSinceEpic: number,
	lastCastClock: number,
	activeCast: ActiveCast?,
}

local stateByPlayer: { [Player]: CastState } = {}
local dependencies: Dependencies? = nil

local CatchService = {}

-- Pity counters come from saved data; NaN or a negative would wedge
-- the pity math, so they are floored to a whole non-negative count.
local function flooredCount(value: number): number
	if typeof(value) ~= "number" or value ~= value then
		return 0
	end

	return math.max(math.floor(value), 0)
end

function CatchService.initializePlayer(
	player: Player,
	castsSinceRare: number,
	castsSinceEpic: number
)
	stateByPlayer[player] = {
		castsSinceRare = flooredCount(castsSinceRare),
		castsSinceEpic = flooredCount(castsSinceEpic),
		lastCastClock = 0,
		activeCast = nil,
	}
end

function CatchService.snapshot(player: Player): (number?, number?)
	local state = stateByPlayer[player]
	if state == nil then
		return nil, nil
	end

	return state.castsSinceRare, state.castsSinceEpic
end

function CatchService.removePlayer(player: Player)
	stateByPlayer[player] = nil
end

--[[
	Validates one cast attempt and, when every gate passes, rolls the
	randomized ring the client must draw. Randomizing both the ring
	speed and the perfect point means no memorized rhythm ever farms
	perfect taps.
]]
function CatchService.beginCast(player: Player): (boolean, any)
	local state = stateByPlayer[player]
	local currentDependencies = dependencies
	if state == nil or currentDependencies == nil then
		return false, "Not ready"
	end

	local character = player.Character
	if character == nil then
		return false, "Not ready"
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return false, "Not ready"
	end

	local zone = TideLayout.zoneAt(root.Position)
	if zone == nil then
		return false, "Nothing bites here"
	end

	if not TideLayout.castableAt(zone, currentDependencies.getPhase()) then
		return false, "The tide is wrong for this spot"
	end

	if not currentDependencies.zoneUnlocked(player, zone) then
		return false, "Log more species to fish here"
	end

	-- The loaner tube physically reaches the Deep Reef, but only an
	-- owned mount unlocks the deep-only species; deepAllowed carries
	-- that distinction into the resolve.
	local deepAllowed = false
	if zone == DEEP_REEF_ZONE_KEY then
		local mounted, deepAccess = currentDependencies.isMounted(player)
		if not mounted then
			return false, "You need a mount out here"
		end

		deepAllowed = deepAccess
	end

	local now = os.clock()
	if now - state.lastCastClock < TidetownConfig.catch.castCooldownSeconds then
		return false, "The line needs a moment"
	end

	state.lastCastClock = now

	local window = CatchRules.rollWindow(math.random(), math.random())
	local castId = HttpService:GenerateGUID(false)

	-- A fresh BeginCast replaces any cast still in flight, so an
	-- abandoned ring can never be resolved late for a free roll.
	state.activeCast = {
		castId = castId,
		window = window,
		issuedAt = os.clock(),
		zone = zone,
		deepAllowed = deepAllowed,
	}

	return true,
		{
			castId = castId,
			ringSeconds = window.ringSeconds,
			perfectAt = window.perfectAt,
			zone = zone,
		}
end

--[[
	Judges the second tap on the server's clock. Misses pay a small
	consolation and leave the pity counters alone -- pity tracks bad
	luck, and a whiffed tap is not bad luck. Good and perfect taps
	roll a species, pay Shells, feed the Tidepedia, eggs, and
	bounties, and advance or reset pity.
]]
function CatchService.resolveCast(player: Player, castId: any): (boolean, any)
	local state = stateByPlayer[player]
	local currentDependencies = dependencies
	if state == nil or currentDependencies == nil then
		return false, "Not ready"
	end

	local cast = state.activeCast
	if typeof(castId) ~= "string" or cast == nil or cast.castId ~= castId then
		return false, "No cast in flight"
	end

	-- Consumed before judging so a duplicated ResolveCast can never
	-- score the same ring twice.
	state.activeCast = nil

	local elapsedFraction = (os.clock() - cast.issuedAt) / cast.window.ringSeconds
	local quality = CatchRules.qualityFor(cast.window, elapsedFraction)

	if quality == "miss" then
		local consolation = TidetownConfig.catch.missConsolationShells
		currentDependencies.awardShells(player, consolation)

		return true, {
			quality = "miss",
			shells = consolation,
		}
	end

	local weights = CatchRules.applyPity(
		CatchRules.rarityWeightsFor(quality, currentDependencies.luckPercent(player)),
		state.castsSinceRare,
		state.castsSinceEpic
	)
	local species = CreatureCatalog.rollSpecies(
		cast.zone,
		weights,
		math.random(),
		math.random(),
		cast.deepAllowed
	)
	if species == nil then
		return false, "The catch slipped away"
	end

	local shells = CatchRules.shellsFor(quality, species.rarity, cast.zone)
	currentDependencies.awardShells(player, shells)

	local isNew = currentDependencies.recordSpecies(player, species.key)

	local rank = RARITY_RANKS[species.rarity] or 1
	if rank >= RARE_RANK then
		state.castsSinceRare = 0
	else
		state.castsSinceRare += 1
	end

	if rank >= EPIC_RANK then
		state.castsSinceEpic = 0
	else
		state.castsSinceEpic += 1
	end

	local chargeInfo = currentDependencies.chargeEggs(player)

	-- A successful catch sometimes uncovers a buried egg for the
	-- zone; a full egg bag just loses the find, so the result is
	-- deliberately ignored.
	if math.random() < TidetownConfig.catch.eggFindChance then
		currentDependencies.grantFoundEgg(player, cast.zone)
	end

	currentDependencies.reportBounty(player, "catchAny", 1)
	if quality == "perfect" then
		currentDependencies.reportBounty(player, "perfectCasts", 1)
	end

	return true,
		{
			quality = quality,
			speciesKey = species.key,
			speciesName = species.name,
			rarity = species.rarity,
			isNew = isNew,
			shells = shells,
			chargeInfo = chargeInfo,
		}
end

function CatchService.start(startDependencies: Dependencies)
	dependencies = startDependencies
end

return CatchService
