--[[
	Pure math for everything size-related. Keeping these as side-effect-free
	functions makes the growth curve safe to tweak and easy to unit test:
	every rule about what a size *means* lives here, while SizeService owns
	when sizes change.
]]

local Shared = script.Parent
local GameConfig = require(Shared.GameConfig)

export type PassFlags = {
	doubleGrowth: boolean?,
	vip: boolean?,
	doubleRebirthBonus: boolean?,
}

local SizeFormula = {}

--[[
	Maps a size to a character scale with a saturating curve: fast visible
	growth early on, flattening toward the maximum so giant players never
	break physics or cameras.
]]
function SizeFormula.scaleForSize(size: number): number
	local range = GameConfig.scale.maximum - GameConfig.scale.minimum
	local saturation = size / (size + GameConfig.scale.halfwaySize)

	return GameConfig.scale.minimum + range * saturation
end

--[[
	Speed comes from the player's slider setting; size adds only a gentle
	nudge on top. Keeping the size term small is a design rule -- speed
	must stay a comfort setting, never the way you win.
]]
function SizeFormula.walkSpeed(speedSetting: number, scale: number, potionBonus: number): number
	local sizeBonus = 4 * (math.sqrt(scale) - 1)

	return math.clamp(speedSetting + sizeBonus + potionBonus, 8, GameConfig.speed.hardCap)
end

--[[
	Square-root curve so big characters jump meaningfully higher (walls!)
	without breaking physics.
]]
function SizeFormula.jumpPowerForScale(scale: number): number
	return math.clamp(50 * math.sqrt(scale), 40, 120)
end

function SizeFormula.growthMultiplier(rebirths: number, flags: PassFlags): number
	local perRebirth = GameConfig.rebirth.multiplierPerRebirth
	if flags.doubleRebirthBonus then
		perRebirth *= 2
	end

	local multiplier = 1 + rebirths * perRebirth
	if flags.doubleGrowth then
		multiplier *= 2
	end
	if flags.vip then
		multiplier *= 1 + GameConfig.passEffects.vipGrowthBonus
	end

	return multiplier
end

function SizeFormula.growthPerTick(rebirths: number, flags: PassFlags): number
	return GameConfig.growth.sizePerTick * SizeFormula.growthMultiplier(rebirths, flags)
end

function SizeFormula.requiredSizeForRebirth(rebirths: number): number
	return GameConfig.rebirth.baseRequiredSize * (rebirths + 1)
end

function SizeFormula.canPassGate(currentSize: number, requiredSize: number): boolean
	return currentSize >= requiredSize
end

--[[
	allowanceMultiplier stretches how big you may be and still fit: 1 for
	most players, above 1 with Super Squeeze or a Slick Coating.
]]
function SizeFormula.canFitCrack(
	currentSize: number,
	maxAllowedSize: number,
	allowanceMultiplier: number?
): boolean
	local allowance = if allowanceMultiplier ~= nil then allowanceMultiplier else 1

	return currentSize <= maxAllowedSize * allowance
end

return SizeFormula
