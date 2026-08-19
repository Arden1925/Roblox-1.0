--[[
	Pure timing and loot math for the cast minigame, shared so the
	client's ring visuals and the server's judgment can never disagree
	about where the windows sit. The server remains the only judge: the
	client uses these numbers to DRAW the ring, the server to score the
	tap on its own clock.
]]

local Shared = script.Parent
local TidetownConfig = require(Shared.TidetownConfig)

export type CastWindow = {
	ringSeconds: number,
	perfectAt: number,
}

local CatchRules = {}

--[[
	Rolls the randomized ring for one cast from two uniform [0, 1)
	samples. Randomizing both the ring speed and where the perfect
	moment sits means no fixed rhythm ever farms perfect casts.
]]
function CatchRules.rollWindow(speedSample: number, centerSample: number): CastWindow
	local catch = TidetownConfig.catch
	local ringSeconds = catch.ringSecondsMinimum
		+ (catch.ringSecondsMaximum - catch.ringSecondsMinimum) * speedSample
	local perfectAt = catch.perfectAtMinimum
		+ (catch.perfectAtMaximum - catch.perfectAtMinimum) * centerSample

	return {
		ringSeconds = ringSeconds,
		perfectAt = perfectAt,
	}
end

--[[
	Scores a tap by the fraction of the ring that had elapsed when it
	landed. The grace fraction widens both windows to absorb network
	latency; Perfect keeps a tighter share of it than Good.
]]
function CatchRules.qualityFor(window: CastWindow, elapsedFraction: number): string
	local catch = TidetownConfig.catch
	local offset = math.abs(elapsedFraction - window.perfectAt)

	if offset <= catch.perfectWindowFraction / 2 + catch.latencyGraceFraction / 2 then
		return "perfect"
	end

	if offset <= catch.goodWindowFraction / 2 + catch.latencyGraceFraction then
		return "good"
	end

	return "miss"
end

--[[
	The rarity weight table a cast rolls on: the quality picks the base
	table, then the player's Tidepedia luck inflates the epic and
	legendary weights. Luck bends the top of the table only, so buffs
	never make commons disappear.
]]
function CatchRules.rarityWeightsFor(quality: string, luckPercent: number): { [string]: number }
	local catch = TidetownConfig.catch
	local base = if quality == "perfect"
		then catch.rarityWeightsPerfect
		else catch.rarityWeightsGood
	local luckMultiplier = 1 + luckPercent / 100

	return {
		common = base.common,
		rare = base.rare,
		epic = base.epic * luckMultiplier,
		legendary = base.legendary * luckMultiplier,
	}
end

--[[
	Applies soft pity: after enough casts without a rare (or an epic),
	the weight table floors at that rarity so the next catch cannot
	roll below it. Pity counts come from the caller's persisted state.
]]
function CatchRules.applyPity(
	weights: { [string]: number },
	castsSinceRare: number,
	castsSinceEpic: number
): { [string]: number }
	local catch = TidetownConfig.catch
	local floored = {
		common = weights.common,
		rare = weights.rare,
		epic = weights.epic,
		legendary = weights.legendary,
	}

	if castsSinceRare >= catch.pityRareCasts then
		floored.common = 0
	end

	if castsSinceEpic >= catch.pityEpicCasts then
		floored.common = 0
		floored.rare = 0
	end

	return floored
end

--[[
	Shell payout for one catch: rarity base, zone multiplier, and the
	perfect bonus. Misses pay the small consolation instead so a whiffed
	ring never reads as a punishment.
]]
function CatchRules.shellsFor(quality: string, rarity: string, zoneKey: string): number
	local catch = TidetownConfig.catch

	if quality == "miss" then
		return catch.missConsolationShells
	end

	local base = catch.shellsByRarity[rarity] or 0
	local zoneMultiplier = catch.zoneShellMultipliers[zoneKey] or 1
	local perfectMultiplier = if quality == "perfect" then catch.perfectShellMultiplier else 1

	return math.floor(base * zoneMultiplier * perfectMultiplier + 0.5)
end

return CatchRules
