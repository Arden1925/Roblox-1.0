--[[
	Builds the full pet list from GameConfig and answers questions about
	it: what a pet id means, what an egg can hatch, and what everything
	is worth. Both the server (hatching, equipping) and the client
	(inventory, egg previews) read from here, so the two can never
	disagree about what exists.

	Pet id formats: "w<world>:<Name>" for coin-egg pets, "r<world>:<Name>"
	for Robux-egg pets, "limited:<Name>" for the limited pet.
]]

local Shared = script.Parent
local GameConfig = require(Shared.GameConfig)

export type PetInfo = {
	id: string,
	name: string,
	tierName: string,
	tierColor: Color3,
	bonus: number,
	worldIndex: number?,
}

local PetCatalog = {}

local infoById: { [string]: PetInfo } = {}

-- Coin-egg pets: two on the egg's lowest tier, two on its middle, one
-- on top; tiers slide up one per world so later eggs are strictly
-- better.
local EGG_SLOT_TIER_OFFSETS = { 0, 0, 1, 1, 2 }

local function tierAt(index: number): { name: string, color: { number }, bonus: number }
	local clamped = math.clamp(index, 1, #GameConfig.petTiers)

	return GameConfig.petTiers[clamped]
end

local function register(info: PetInfo)
	infoById[info.id] = info
end

for worldIndex, world in ipairs(GameConfig.worlds) do
	for slot, petName in ipairs(world.eggPets) do
		local tier = tierAt(worldIndex + EGG_SLOT_TIER_OFFSETS[slot])
		register({
			id = string.format("w%d:%s", worldIndex, petName),
			name = petName,
			tierName = tier.name,
			tierColor = Color3.fromRGB(tier.color[1], tier.color[2], tier.color[3]),
			bonus = tier.bonus,
			worldIndex = worldIndex,
		})
	end

	for _, petSpec in ipairs(world.robuxEgg.pets) do
		local tier = tierAt(petSpec.tier)
		register({
			id = string.format("r%d:%s", worldIndex, petSpec.name),
			name = petSpec.name,
			tierName = tier.name,
			tierColor = Color3.fromRGB(tier.color[1], tier.color[2], tier.color[3]),
			bonus = petSpec.bonus,
			worldIndex = worldIndex,
		})
	end
end

register({
	id = "limited:" .. GameConfig.limitedPet.name,
	name = GameConfig.limitedPet.name,
	tierName = "Ultra",
	tierColor = Color3.fromRGB(255, 234, 167),
	bonus = GameConfig.limitedPet.bonus,
	worldIndex = nil,
})

local SHINY_SUFFIX = "*shiny"

function PetCatalog.shinyId(petId: string): string
	return petId .. SHINY_SUFFIX
end

function PetCatalog.isShiny(petId: string): boolean
	return string.sub(petId, -#SHINY_SUFFIX) == SHINY_SUFFIX
end

function PetCatalog.baseId(petId: string): string
	if PetCatalog.isShiny(petId) then
		return string.sub(petId, 1, -#SHINY_SUFFIX - 1)
	end

	return petId
end

--[[
	Shiny variants are derived, not registered: any pet id with the shiny
	suffix resolves to its base pet with a boosted bonus and a shiny
	name, so the catalog never has to list them.
]]
function PetCatalog.infoFor(petId: string): PetInfo?
	if PetCatalog.isShiny(petId) then
		local baseInfo = infoById[string.sub(petId, 1, -#SHINY_SUFFIX - 1)]
		if baseInfo == nil then
			return nil
		end

		return {
			id = petId,
			name = "Shiny " .. baseInfo.name,
			tierName = baseInfo.tierName,
			tierColor = baseInfo.tierColor:Lerp(Color3.fromRGB(255, 255, 255), 0.3),
			bonus = baseInfo.bonus * GameConfig.shiny.bonusMultiplier,
			worldIndex = baseInfo.worldIndex,
		}
	end

	return infoById[petId]
end

--[[
	The five pets a world's coin egg can hatch, with hatch weights,
	weakest first -- the exact list the hatch roll and the egg preview
	both use.
]]
function PetCatalog.coinEggPool(worldIndex: number): { { id: string, weight: number } }
	local world = GameConfig.worlds[worldIndex]
	local pool = {}

	for slot, petName in ipairs(world.eggPets) do
		local tierOffset = EGG_SLOT_TIER_OFFSETS[slot]
		-- Two pets share each of the lower tiers, so each gets half that
		-- tier's weight; the top slot keeps its full weight.
		local tierWeight = GameConfig.eggTierWeights[tierOffset + 1]
		local weight = if slot == 5 then tierWeight else tierWeight / 2

		table.insert(pool, {
			id = string.format("w%d:%s", worldIndex, petName),
			weight = weight,
		})
	end

	return pool
end

function PetCatalog.robuxEggPool(worldIndex: number): { string }
	local world = GameConfig.worlds[worldIndex]
	local pool = {}

	for _, petSpec in ipairs(world.robuxEgg.pets) do
		table.insert(pool, string.format("r%d:%s", worldIndex, petSpec.name))
	end

	return pool
end

function PetCatalog.limitedPetId(): string
	return "limited:" .. GameConfig.limitedPet.name
end

return PetCatalog
