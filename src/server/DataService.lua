--[[
	Loads and saves player progress. Two rules protect player data:

	1. Every DataStore call is wrapped in pcall with retries, because
	   DataStores fail routinely under load.
	2. If a player's load never succeeded, this session refuses to save
	   them. Saving defaults over real data is how games destroy years of
	   progress; failing to save nothing is always the safer error.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)

export type PlayerData = {
	maxSize: number,
	rebirths: number,
	reachedWorld: number,
	coins: number,
	tutorialDone: boolean,
	pets: { string },
	petNames: { [string]: string },
	-- Legacy single-pet field, still read so old saves keep their pet;
	-- new saves write the equippedPets list.
	equippedPet: string,
	equippedPets: { string },
	extraPetSlot: boolean,
	upgrades: { [string]: number },
	checkpointsClaimed: { [string]: number },
	respawnWorld: number,
	respawnIndex: number,
	lastSeenAt: number,
	permanentGrowthBonus: number,
	groupChestClaimed: boolean,
	streakCount: number,
	streakLastDate: string,
	questDate: string,
	quests: { { [string]: any } },
	wheelLastSpinAt: number,
	wheelSpinCredits: number,
	redeemedCodes: { string },
}

local store = nil
local loadedOkByUserId: { [number]: boolean } = {}

local DataService = {}

local function copyDefaultData(): PlayerData
	return {
		maxSize = 0,
		rebirths = 0,
		reachedWorld = 1,
		coins = 0,
		tutorialDone = false,
		pets = {},
		petNames = {},
		equippedPet = "",
		equippedPets = {},
		extraPetSlot = false,
		upgrades = {},
		checkpointsClaimed = {},
		respawnWorld = 1,
		respawnIndex = 0,
		lastSeenAt = 0,
		permanentGrowthBonus = 0,
		groupChestClaimed = false,
		streakCount = 0,
		streakLastDate = "",
		questDate = "",
		quests = {},
		wheelLastSpinAt = 0,
		wheelSpinCredits = 0,
		redeemedCodes = {},
	}
end

--[[
	Copies recognized fields from a raw stored value onto fresh defaults,
	type-checking each one so a corrupt or outdated record can never
	poison a session.
]]
local function sanitize(result: any): PlayerData
	local data = copyDefaultData()
	if typeof(result) ~= "table" then
		return data
	end

	for _, numberField in ipairs({
		"maxSize",
		"rebirths",
		"reachedWorld",
		"coins",
		"respawnWorld",
		"respawnIndex",
		"lastSeenAt",
		"permanentGrowthBonus",
		"streakCount",
		"wheelLastSpinAt",
		"wheelSpinCredits",
	}) do
		if typeof(result[numberField]) == "number" then
			data[numberField] = result[numberField]
		end
	end

	for _, booleanField in ipairs({ "tutorialDone", "groupChestClaimed", "extraPetSlot" }) do
		if typeof(result[booleanField]) == "boolean" then
			data[booleanField] = result[booleanField]
		end
	end

	for _, stringField in ipairs({ "equippedPet", "streakLastDate", "questDate" }) do
		if typeof(result[stringField]) == "string" then
			data[stringField] = result[stringField]
		end
	end

	-- Quests are structured little tables; QuestService re-rolls on any
	-- mismatch, so passing well-formed entries through is enough.
	if typeof(result.quests) == "table" then
		for _, quest in ipairs(result.quests) do
			if typeof(quest) == "table" and typeof(quest.key) == "string" then
				table.insert(data.quests, quest)
			end
		end
	end

	if typeof(result.pets) == "table" then
		for _, petId in ipairs(result.pets) do
			if typeof(petId) == "string" then
				table.insert(data.pets, petId)
			end
		end
	end

	if typeof(result.redeemedCodes) == "table" then
		for _, code in ipairs(result.redeemedCodes) do
			if typeof(code) == "string" then
				table.insert(data.redeemedCodes, code)
			end
		end
	end

	if typeof(result.equippedPets) == "table" then
		for _, petId in ipairs(result.equippedPets) do
			if typeof(petId) == "string" then
				table.insert(data.equippedPets, petId)
			end
		end
	end

	-- Old saves carry a single equipped pet; fold it into the list so
	-- nobody loses their companion on the schema change.
	if #data.equippedPets == 0 and data.equippedPet ~= "" then
		table.insert(data.equippedPets, data.equippedPet)
	end

	-- Nicknames are keyed by the pet's inventory index as a string.
	if typeof(result.petNames) == "table" then
		for key, nickname in pairs(result.petNames) do
			if typeof(key) == "string" and typeof(nickname) == "string" then
				data.petNames[key] = nickname
			end
		end
	end

	for _, mapField in ipairs({ "upgrades", "checkpointsClaimed" }) do
		if typeof(result[mapField]) == "table" then
			for key, value in pairs(result[mapField]) do
				if typeof(key) == "string" and typeof(value) == "number" then
					data[mapField][key] = value
				end
			end
		end
	end

	return data
end

--[[
	Fetches a player's saved data, retrying with backoff. Yields; call
	from a spawned task. Always returns usable data -- defaults if every
	attempt failed -- but only marks the session save-safe on success.
]]
function DataService.loadAsync(player: Player): PlayerData
	if store == nil then
		return copyDefaultData()
	end

	for attempt = 1, GameConfig.data.loadAttempts do
		-- GetAsync throws on throttling and outages; those are the errors
		-- we retry. Anything else lands in the same retry path harmlessly.
		local success, result = pcall(function()
			return store:GetAsync(tostring(player.UserId))
		end)

		if success then
			loadedOkByUserId[player.UserId] = true

			return sanitize(result)
		end

		if attempt < GameConfig.data.loadAttempts then
			task.wait(GameConfig.data.retryBaseSeconds * 2 ^ (attempt - 1))
		else
			warn(string.format("Data load failed for %s: %s", player.Name, tostring(result)))
		end
	end

	return copyDefaultData()
end

--[[
	Saves a snapshot for a player. Yields; call from a spawned task.
	Silently refuses when the load never succeeded (see file comment).
]]
function DataService.saveAsync(player: Player, snapshot: PlayerData)
	if store == nil or loadedOkByUserId[player.UserId] ~= true then
		return
	end

	-- SetAsync throws on throttling and outages; one retry is enough here
	-- because autosave and the leave-save give us more chances later.
	local success, result = pcall(function()
		store:SetAsync(tostring(player.UserId), snapshot)
	end)

	if not success then
		warn(string.format("Data save failed for %s: %s", player.Name, tostring(result)))
	end
end

function DataService.forgetPlayer(player: Player)
	loadedOkByUserId[player.UserId] = nil
end

--[[
	Starts autosave and the shutdown save. getSnapshot is injected so this
	module stays ignorant of where runtime state lives.
]]
function DataService.start(getSnapshot: (Player) -> PlayerData?)
	-- GetDataStore throws in Studio when API access is disabled; the game
	-- then runs memory-only, which is fine for local testing.
	local success, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.data.storeName)
	end)

	if success then
		store = result
	else
		warn("DataStores unavailable; progress will not save this session")
	end

	task.spawn(function()
		while true do
			task.wait(GameConfig.data.autosaveSeconds)

			for _, player in ipairs(Players:GetPlayers()) do
				local snapshot = getSnapshot(player)
				if snapshot ~= nil then
					task.spawn(DataService.saveAsync, player, snapshot)
				end
			end
		end
	end)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			local snapshot = getSnapshot(player)
			if snapshot ~= nil then
				DataService.saveAsync(player, snapshot)
			end
		end
	end)
end

return DataService
