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

export type PetMutation = {
	key: string,
	name: string,
	color: Color3,
	scale: number,
	bonusMultiplier: number,
}

export type PetInfo = {
	id: string,
	name: string,
	baseName: string,
	tierName: string,
	tierColor: Color3,
	bonus: number,
	worldIndex: number?,
	mutation: PetMutation?,
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
			baseName = petName,
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
			baseName = petSpec.name,
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
	baseName = GameConfig.limitedPet.name,
	tierName = "Ultra",
	tierColor = Color3.fromRGB(255, 234, 167),
	bonus = GameConfig.limitedPet.bonus,
	worldIndex = nil,
})

-- Mutated ids append "*<key>" to the base id (e.g. "w1:Crab*golden"),
-- so mutated variants are derived, never registered. The old "*shiny"
-- saves keep working because shiny is one of the mutation keys.
local mutationByKey: { [string]: PetMutation } = {}

for _, spec in ipairs(GameConfig.mutations) do
	mutationByKey[spec.key] = {
		key = spec.key,
		name = spec.name,
		color = Color3.fromRGB(spec.color[1], spec.color[2], spec.color[3]),
		scale = spec.scale,
		bonusMultiplier = spec.bonusMultiplier,
	}
end

function PetCatalog.mutatedId(petId: string, mutationKey: string): string
	return petId .. "*" .. mutationKey
end

function PetCatalog.baseId(petId: string): string
	local base = string.match(petId, "^(.+)%*")

	return if base ~= nil then base else petId
end

function PetCatalog.mutationFor(petId: string): PetMutation?
	local key = string.match(petId, "%*(.+)$")

	return if key ~= nil then mutationByKey[key] else nil
end

--[[
	Rolls a mutation from one uniform [0, 1) sample by walking the list
	rarest first with cumulative chances, so overlapping ranges always
	resolve in favor of the rarer mutation. Returns nil for no mutation.
]]
function PetCatalog.rollMutation(sample: number): string?
	local cumulative = 0

	for _, spec in ipairs(GameConfig.mutations) do
		cumulative += spec.chance
		if sample < cumulative then
			return spec.key
		end
	end

	return nil
end

function PetCatalog.infoFor(petId: string): PetInfo?
	local mutation = PetCatalog.mutationFor(petId)
	if mutation ~= nil then
		local baseInfo = infoById[PetCatalog.baseId(petId)]
		if baseInfo == nil then
			return nil
		end

		return {
			id = petId,
			name = mutation.name .. " " .. baseInfo.name,
			baseName = baseInfo.name,
			tierName = baseInfo.tierName,
			tierColor = baseInfo.tierColor:Lerp(mutation.color, 0.35),
			bonus = baseInfo.bonus * mutation.bonusMultiplier,
			worldIndex = baseInfo.worldIndex,
			mutation = mutation,
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
