--[[
	Owns each player's held eggs. Eggs charge from successful catches
	instead of real-time timers -- playing IS the incubation -- so the
	only way charge moves is CatchService calling chargeEggs after a
	landed catch. Hatching rolls a species from the egg type's published
	odds and hands the creature to CreatureService through a dependency;
	this service never touches inventories itself.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TidetownShared = ReplicatedStorage.TidetownShared
local CreatureCatalog = require(TidetownShared.CreatureCatalog)
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

export type EggRecord = {
	uid: string,
	eggKey: string,
	charge: number,
}

type EggType = {
	key: string,
	name: string,
	zone: string,
	shellCost: number,
	catchesToHatch: number,
	modelName: string,
	rarityWeights: { [string]: number },
}

type Dependencies = {
	grantCreature: (Player, string) -> string?,
	recordSpecies: (Player, string) -> boolean,
	reportBounty: (Player, string, number) -> (),
	pushToast: (Player, string, string?) -> (),
}

local EggService = {}

local eggsByPlayer: { [Player]: { EggRecord } } = {}
local dependencies: Dependencies? = nil
local syncStateRemote: RemoteEvent? = nil

local function eggTypeFor(eggKey: string): EggType?
	for _, eggType in ipairs(TidetownConfig.eggs.types) do
		if eggType.key == eggKey then
			return eggType
		end
	end

	return nil
end

local function requiredChargeFor(eggKey: string): number
	local eggType = eggTypeFor(eggKey)

	-- An unknown key means the config changed under a saved egg; zero
	-- makes it hatchable immediately instead of stranding it forever.
	return if eggType ~= nil then eggType.catchesToHatch else 0
end

local function copyEggList(eggs: { EggRecord }): { EggRecord }
	local copy = {}
	for _, egg in ipairs(eggs) do
		table.insert(copy, {
			uid = egg.uid,
			eggKey = egg.eggKey,
			charge = egg.charge,
		})
	end

	return copy
end

--[[
	Sends the player's egg strip to their client, with each egg's
	required charge merged in so the client never reads the config for
	progress math. Called after every mutation.
]]
function EggService.pushState(player: Player)
	local eggs = eggsByPlayer[player]
	if eggs == nil or syncStateRemote == nil then
		return
	end

	local payload = {}
	for _, egg in ipairs(eggs) do
		table.insert(payload, {
			uid = egg.uid,
			eggKey = egg.eggKey,
			charge = egg.charge,
			required = requiredChargeFor(egg.eggKey),
		})
	end

	syncStateRemote:FireClient(player, "eggs", { eggs = payload })
end

function EggService.initializePlayer(player: Player, eggs: { EggRecord })
	-- Copied so this service owns its slice outright instead of
	-- aliasing the loaded PlayerData table.
	eggsByPlayer[player] = copyEggList(eggs)
	EggService.pushState(player)
end

function EggService.snapshot(player: Player): { EggRecord }?
	local eggs = eggsByPlayer[player]
	if eggs == nil then
		return nil
	end

	-- Copied so the save snapshot cannot alias live state that a later
	-- charge or hatch could mutate mid-save.
	return copyEggList(eggs)
end

function EggService.removePlayer(player: Player)
	eggsByPlayer[player] = nil
end

--[[
	Adds one egg of the type, refusing over the held cap or on an
	unknown key. Egg uids count up from the highest existing number so
	a grant after a hatch can never reuse a uid the client still shows.
]]
function EggService.grantEgg(player: Player, eggKey: string): boolean
	local eggs = eggsByPlayer[player]
	if eggs == nil or #eggs >= TidetownConfig.eggs.maxHeld then
		return false
	end

	local eggType = eggTypeFor(eggKey)
	if eggType == nil then
		return false
	end

	local highestCounter = 0
	for _, egg in ipairs(eggs) do
		local counter = tonumber(string.match(egg.uid, "^e(%d+)$"))
		if counter ~= nil and counter > highestCounter then
			highestCounter = counter
		end
	end

	table.insert(eggs, {
		uid = "e" .. (highestCounter + 1),
		eggKey = eggKey,
		charge = 0,
	})

	EggService.pushState(player)

	if dependencies ~= nil then
		dependencies.pushToast(
			player,
			string.format("%s added to your egg bag!", eggType.name),
			"good"
		)
	end

	return true
end

--[[
	Adds one charge to the OLDEST egg that still needs some -- array
	order is grant order, so the first unfilled egg is the oldest.
	Returns the charged egg's progress for the catch result card, or
	nil when every egg is full (or the player holds none).
]]
function EggService.chargeEggs(player: Player): { [string]: any }?
	local eggs = eggsByPlayer[player]
	if eggs == nil then
		return nil
	end

	for _, egg in ipairs(eggs) do
		local required = requiredChargeFor(egg.eggKey)
		if egg.charge < required then
			egg.charge += 1
			EggService.pushState(player)

			return {
				eggUid = egg.uid,
				charge = egg.charge,
				required = required,
			}
		end
	end

	return nil
end

--[[
	Hatches a fully charged egg from the untrusted HatchEgg remote:
	rolls a species from the egg type's odds, grants the creature and
	the Tidepedia entry through dependencies, then consumes the egg.
	The egg is only removed after the grant succeeds, so a failed roll
	never eats it.
]]
function EggService.hatchEgg(player: Player, eggUid: any): (boolean, any)
	local eggs = eggsByPlayer[player]
	if eggs == nil or dependencies == nil then
		return false, "Not ready"
	end

	if typeof(eggUid) ~= "string" then
		return false, "No such egg"
	end

	local eggIndex: number? = nil
	for index, egg in ipairs(eggs) do
		if egg.uid == eggUid then
			eggIndex = index
			break
		end
	end

	if eggIndex == nil then
		return false, "No such egg"
	end

	local egg = eggs[eggIndex]
	local eggType = eggTypeFor(egg.eggKey)
	if eggType == nil then
		return false, "No such egg"
	end

	if egg.charge < eggType.catchesToHatch then
		return false, "Keep catching to charge it"
	end

	-- Deep-only species are fair game from eggs: the deep egg is
	-- itself gated behind Stormglass wealth, so the mount gate has
	-- already been paid in kind.
	local species = CreatureCatalog.rollSpecies(
		eggType.zone,
		eggType.rarityWeights,
		math.random(),
		math.random(),
		true
	)
	if species == nil then
		return false, "The egg is not ready"
	end

	local creatureUid = dependencies.grantCreature(player, species.key)
	if creatureUid == nil then
		return false, "The egg is not ready"
	end

	local isNew = dependencies.recordSpecies(player, species.key)

	table.remove(eggs, eggIndex)
	dependencies.reportBounty(player, "hatchEggs", 1)
	EggService.pushState(player)

	return true,
		{
			speciesKey = species.key,
			speciesName = species.name,
			rarity = species.rarity,
			isNew = isNew,
			creatureUid = creatureUid,
		}
end

--[[
	Wires dependencies and fetches the SyncState remote (yields, which
	is why init calls start from a spawned task).
]]
function EggService.start(dependencyTable: Dependencies)
	dependencies = dependencyTable
	syncStateRemote = TidetownRemotes.get("SyncState") :: RemoteEvent
end

return EggService
