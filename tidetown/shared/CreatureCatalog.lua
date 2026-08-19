--[[
	The species registry: every catchable creature in Tidetown, keyed by
	a stable id that saves and remotes pass around. Both the server
	(catch rolls, surge stats) and the client (Tidepedia, team cards)
	read from here, so the two can never disagree about what exists.

	Every species maps to a real model in the Sea Animals asset pack;
	rarity picks the power multiplier inside one narrow band, and the
	role decides HOW it fights, so collecting is about roles and looks,
	never raw power.
]]

local Shared = script.Parent
local TidetownConfig = require(Shared.TidetownConfig)

export type Species = {
	key: string,
	name: string,
	modelName: string,
	zone: string,
	rarity: string,
	role: string,
	-- Deep-only species need an OWNED mount (the loaner tube cannot
	-- reach them); everything else in the Deep Reef works from any
	-- mount.
	deepOnly: boolean,
	flavor: string,
}

local SPECIES_LIST: { Species } = {
	-- Tidepool Flats: the teaching zone, common-heavy.
	{
		key = "goldfish",
		name = "Goldfish",
		modelName = "Goldfish",
		zone = "Beach",
		rarity = "common",
		role = "Sprayer",
		deepOnly = false,
		flavor = "Spits seawater with surprising conviction.",
	},
	{
		key = "clownfish",
		name = "Clownfish",
		modelName = "Clownfish",
		zone = "Beach",
		rarity = "common",
		role = "Herder",
		deepOnly = false,
		flavor = "Ferals slow down to hear the joke.",
	},
	{
		key = "crab",
		name = "Crab",
		modelName = "Crab",
		zone = "Beach",
		rarity = "common",
		role = "Anchor",
		deepOnly = false,
		flavor = "Plants its claws and simply refuses.",
	},
	{
		key = "seahorse",
		name = "Seahorse",
		modelName = "Seahorse",
		zone = "Beach",
		rarity = "common",
		role = "Sparker",
		deepOnly = false,
		flavor = "Stores a static charge in its curled tail.",
	},
	{
		key = "lobster",
		name = "Lobster",
		modelName = "Lobster",
		zone = "Beach",
		rarity = "rare",
		role = "Anchor",
		deepOnly = false,
		flavor = "Armor plating polished by the surf.",
	},
	{
		key = "axolotl",
		name = "Axolotl",
		modelName = "Axolotl",
		zone = "Beach",
		rarity = "rare",
		role = "Sparker",
		deepOnly = false,
		flavor = "The smile hides a thunderclap.",
	},
	{
		key = "candyTurtle",
		name = "Candy Turtle",
		modelName = "Candy Turtle",
		zone = "Beach",
		rarity = "epic",
		role = "Anchor",
		deepOnly = false,
		flavor = "The shell is hard candy. Ferals learn this once.",
	},

	-- Old Tidetown: the flooded streets, catchable at high tide.
	{
		key = "catfish",
		name = "Catfish",
		modelName = "Catfish",
		zone = "Town",
		rarity = "common",
		role = "Herder",
		deepOnly = false,
		flavor = "Patrols Main Street like it pays rent.",
	},
	{
		key = "flounder",
		name = "Flounder",
		modelName = "Flounder",
		zone = "Town",
		rarity = "common",
		role = "Anchor",
		deepOnly = false,
		flavor = "Flat enough to block a doorway.",
	},
	{
		key = "tigerfish",
		name = "Tigerfish",
		modelName = "Tigerfish",
		zone = "Town",
		rarity = "rare",
		role = "Sprayer",
		deepOnly = false,
		flavor = "Stripes move faster than the fish.",
	},
	{
		key = "electricEel",
		name = "Electric Eel",
		modelName = "Electric Eel",
		zone = "Town",
		rarity = "rare",
		role = "Sparker",
		deepOnly = false,
		flavor = "The streetlights flicker when it yawns.",
	},
	{
		key = "steampunkTurtle",
		name = "Steampunk Turtle",
		modelName = "Steampunk Turtle",
		zone = "Town",
		rarity = "epic",
		role = "Anchor",
		deepOnly = false,
		flavor = "Rivets and brass; the tide winds its gears.",
	},
	{
		key = "cyberShark",
		name = "Cyber Shark",
		modelName = "Cyber Shark",
		zone = "Town",
		rarity = "epic",
		role = "Sprayer",
		deepOnly = false,
		flavor = "Targets acquired. All of them.",
	},
	{
		key = "steveTheStingray",
		name = "Steve The Stingray",
		modelName = "Steve The Stingray",
		zone = "Town",
		rarity = "legendary",
		role = "Herder",
		deepOnly = false,
		flavor = "Everyone in the harbor just calls him Steve.",
	},

	-- Glowcave Shallows: the low-tide caves.
	{
		key = "pufferfish",
		name = "Pufferfish",
		modelName = "Pufferfish",
		zone = "Cave",
		rarity = "common",
		role = "Sprayer",
		deepOnly = false,
		flavor = "Inflates to exactly doorframe size.",
	},
	{
		key = "meteorCrab",
		name = "Meteor Crab",
		modelName = "Meteor Crab",
		zone = "Cave",
		rarity = "rare",
		role = "Anchor",
		deepOnly = false,
		flavor = "Fell from somewhere. Refuses to elaborate.",
	},
	{
		key = "crystalShark",
		name = "Crystal Shark",
		modelName = "Crystal Shark",
		zone = "Cave",
		rarity = "rare",
		role = "Herder",
		deepOnly = false,
		flavor = "Ferals stop to admire their reflection.",
	},
	{
		key = "skeletalShark",
		name = "Skeletal Shark",
		modelName = "Skeletal Shark",
		zone = "Cave",
		rarity = "epic",
		role = "Sprayer",
		deepOnly = false,
		flavor = "No flesh, all business.",
	},
	{
		key = "meteorLobster",
		name = "Meteor Lobster",
		modelName = "Meteor Lobster",
		zone = "Cave",
		rarity = "epic",
		role = "Sparker",
		deepOnly = false,
		flavor = "Still cooling. Handle with oven mitts.",
	},
	{
		key = "infernalAxolotl",
		name = "Infernal Axolotl",
		modelName = "Infernal Axolotl",
		zone = "Cave",
		rarity = "legendary",
		role = "Sparker",
		deepOnly = false,
		flavor = "The cave glow? That is just him.",
	},
	{
		key = "voidTurtle",
		name = "Void Turtle",
		modelName = "Void Turtle",
		zone = "Cave",
		rarity = "legendary",
		role = "Anchor",
		deepOnly = false,
		flavor = "Light goes in. Ferals do not come out.",
	},

	-- Deep Reef: mounted casts only; the four deep-only species need an
	-- owned mount.
	{
		key = "narwhal",
		name = "Narwhal",
		modelName = "Narwhal",
		zone = "DeepReef",
		rarity = "rare",
		role = "Sprayer",
		deepOnly = false,
		flavor = "The point is excellent, thank you.",
	},
	{
		key = "alienJellyfish",
		name = "Alien Jellyfish",
		modelName = "Alien Jellyfish",
		zone = "DeepReef",
		rarity = "epic",
		role = "Herder",
		deepOnly = false,
		flavor = "Communicates exclusively in slow pulses.",
	},
	{
		key = "flowerWhale",
		name = "Flower Whale",
		modelName = "Flower Whale",
		zone = "DeepReef",
		rarity = "epic",
		role = "Anchor",
		deepOnly = false,
		flavor = "A reef bloomed on its back and stayed.",
	},
	{
		key = "nebulaWhale",
		name = "Nebula Whale",
		modelName = "Nebula Whale",
		zone = "DeepReef",
		rarity = "legendary",
		role = "Anchor",
		deepOnly = true,
		flavor = "Swallowed a night sky and kept it.",
	},
	{
		key = "galaxyAxolotl",
		name = "Galaxy Axolotl",
		modelName = "Galaxy Axolotl",
		zone = "DeepReef",
		rarity = "legendary",
		role = "Sparker",
		deepOnly = true,
		flavor = "Stars orbit the smile now.",
	},
	{
		key = "lunarPenguin",
		name = "Lunar Penguin",
		modelName = "Lunar Penguin",
		zone = "DeepReef",
		rarity = "legendary",
		role = "Herder",
		deepOnly = true,
		flavor = "Waddles on water when the moon approves.",
	},
}

local CreatureCatalog = {}

local speciesByKey: { [string]: Species } = {}
local speciesByZone: { [string]: { Species } } = {}

for _, species in ipairs(SPECIES_LIST) do
	speciesByKey[species.key] = species

	local zoneList = speciesByZone[species.zone]
	if zoneList == nil then
		zoneList = {}
		speciesByZone[species.zone] = zoneList
	end

	table.insert(zoneList, species)
end

function CreatureCatalog.speciesFor(key: string): Species?
	return speciesByKey[key]
end

function CreatureCatalog.allSpecies(): { Species }
	return SPECIES_LIST
end

function CreatureCatalog.speciesInZone(zoneKey: string): { Species }
	return speciesByZone[zoneKey] or {}
end

function CreatureCatalog.totalCount(): number
	return #SPECIES_LIST
end

function CreatureCatalog.rarityColor(rarity: string): Color3
	local rgb = TidetownConfig.creatures.rarityColors[rarity]
	if rgb == nil then
		return Color3.fromRGB(255, 255, 255)
	end

	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

--[[
	The narrow power band: a species' stat is its role's base stat times
	its rarity multiplier times any link bonus. Returns the multiplier
	so callers scale whichever role stat they need.
]]
function CreatureCatalog.rarityMultiplier(rarity: string): number
	return TidetownConfig.creatures.rarityMultipliers[rarity] or 1
end

--[[
	Rolls one species for a zone from rarity weights and one uniform
	[0, 1) sample per stage: first the rarity bucket, then a uniform
	pick inside it. Zones missing a rarity fall through to the next
	lower bucket so a weight table never strands the roll.
]]
function CreatureCatalog.rollSpecies(
	zoneKey: string,
	rarityWeights: { [string]: number },
	raritySample: number,
	speciesSample: number,
	allowDeepOnly: boolean
): Species?
	local pool = speciesByZone[zoneKey]
	if pool == nil then
		return nil
	end

	local RARITY_ORDER = { "legendary", "epic", "rare", "common" }

	local totalWeight = 0
	for _, rarity in ipairs(RARITY_ORDER) do
		totalWeight += rarityWeights[rarity] or 0
	end

	if totalWeight <= 0 then
		return nil
	end

	local chosenRarity = "common"
	local cumulative = 0
	for _, rarity in ipairs(RARITY_ORDER) do
		cumulative += (rarityWeights[rarity] or 0) / totalWeight
		if raritySample < cumulative then
			chosenRarity = rarity
			break
		end
	end

	-- Walk down from the chosen rarity, then back up, until a bucket in
	-- this zone has eligible species: zones missing a rarity outright
	-- (the Deep Reef has no commons) must never strand the roll.
	local startIndex = 1
	for index, rarity in ipairs(RARITY_ORDER) do
		if rarity == chosenRarity then
			startIndex = index
			break
		end
	end

	local function bucketAt(index: number): { Species }
		local bucket = {}
		for _, species in ipairs(pool) do
			local deepAllowed = allowDeepOnly or not species.deepOnly
			if species.rarity == RARITY_ORDER[index] and deepAllowed then
				table.insert(bucket, species)
			end
		end

		return bucket
	end

	local walkOrder = {}
	for index = startIndex, #RARITY_ORDER do
		table.insert(walkOrder, index)
	end
	for index = startIndex - 1, 1, -1 do
		table.insert(walkOrder, index)
	end

	for _, index in ipairs(walkOrder) do
		local bucket = bucketAt(index)
		if #bucket > 0 then
			local pick = math.clamp(math.floor(speciesSample * #bucket) + 1, 1, #bucket)

			return bucket[pick]
		end
	end

	return nil
end

return CreatureCatalog
