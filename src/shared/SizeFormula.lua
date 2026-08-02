--[[
	Pure math for everything size-related. Keeping these as side-effect-free
	functions makes the growth curve safe to tweak and easy to unit test:
	every rule about what a size *means* lives here, while SizeService owns
	when sizes change.
]]

local Shared = script.Parent
local GameConfig = require(Shared.GameConfig)

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

-- Square-root curves so big characters feel weighty but never useless and
-- tiny characters stay nimble without being uncontrollable.
function SizeFormula.walkSpeedForScale(scale: number): number
	return math.clamp(16 * math.sqrt(scale), 8, 28)
end

function SizeFormula.jumpPowerForScale(scale: number): number
	return math.clamp(50 * math.sqrt(scale), 40, 120)
end

function SizeFormula.growthMultiplier(rebirths: number, ownsDoubleGrowth: boolean): number
	local rebirthBonus = 1 + rebirths * GameConfig.rebirth.multiplierPerRebirth
	local passMultiplier = if ownsDoubleGrowth then 2 else 1

	return rebirthBonus * passMultiplier
end

function SizeFormula.growthPerTick(rebirths: number, ownsDoubleGrowth: boolean): number
	return GameConfig.growth.sizePerTick * SizeFormula.growthMultiplier(rebirths, ownsDoubleGrowth)
end

function SizeFormula.requiredSizeForRebirth(rebirths: number): number
	return GameConfig.rebirth.baseRequiredSize * (rebirths + 1)
end

function SizeFormula.canPassGate(currentSize: number, requiredSize: number): boolean
	return currentSize >= requiredSize
end

function SizeFormula.canFitCrack(currentSize: number, maxAllowedSize: number): boolean
	return currentSize <= maxAllowedSize
end

return SizeFormula
