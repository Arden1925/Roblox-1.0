--[[
	Loads and saves Tidetown player progress. Two rules protect player
	data:

	1. Every DataStore call is wrapped in pcall with retries, because
	   DataStores fail routinely under load.
	2. If a player's load never succeeded, this session refuses to save
	   them. Saving defaults over real data is how games destroy years of
	   progress; failing to save nothing is always the safer error.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TidetownShared = ReplicatedStorage.TidetownShared
local TidetownConfig = require(TidetownShared.TidetownConfig)

export type PlayerData = {
	shells: number,
	stormglass: number,
	creatures: { { uid: string, species: string, nickname: string, caughtAt: number } },
	companionUid: string,
	defenseTeam: { string },
	nextUid: number,
	reefSlotsUnlocked: number,
	reefPlaced: { [string]: string },
	reefPool: number,
	reefLastAccrualAt: number,
	eggs: { { uid: string, eggKey: string, charge: number } },
	tidepedia: { [string]: number },
	castsSinceRare: number,
	castsSinceEpic: number,
	bountyDate: string,
	bounties: { { key: string, target: number, progress: number, claimed: boolean } },
	streakCount: number,
	streakLastDate: string,
	claimedStreakMilestones: { [string]: boolean },
	mountsOwned: { string },
	upgrades: { [string]: number },
	decorationsOwned: { string },
	trailsOwned: { string },
	equippedTrail: string,
	settings: { musicVolume: number, sfxVolume: number, reducedMotion: boolean },
	tutorialDone: boolean,
	lastSeenAt: number,
}

local store = nil
-- Keyed by UserId but storing the Player INSTANCE whose load
-- succeeded: a rejoin produces a fresh instance, so a leave-save or
-- forgetPlayer that finishes after a fast rejoin can neither clear
-- nor inherit the new session's save eligibility.
local loadedPlayerByUserId: { [number]: Player } = {}

local TidetownData = {}

local pendingSaves = 0

local function copyDefaultData(): PlayerData
	return {
		shells = 0,
		stormglass = 0,
		creatures = {},
		companionUid = "",
		defenseTeam = {},
		nextUid = 1,
		reefSlotsUnlocked = TidetownConfig.reef.startingSlots,
		reefPlaced = {},
		reefPool = 0,
		reefLastAccrualAt = 0,
		eggs = {},
		tidepedia = {},
		castsSinceRare = 0,
		castsSinceEpic = 0,
		bountyDate = "",
		bounties = {},
		streakCount = 0,
		streakLastDate = "",
		claimedStreakMilestones = {},
		mountsOwned = {},
		upgrades = {},
		decorationsOwned = {},
		trailsOwned = {},
		equippedTrail = "",
		settings = {
			musicVolume = TidetownConfig.settings.defaults.musicVolume,
			sfxVolume = TidetownConfig.settings.defaults.sfxVolume,
			reducedMotion = TidetownConfig.settings.defaults.reducedMotion,
		},
		tutorialDone = false,
		lastSeenAt = 0,
	}
end

--[[
	Copies recognized fields from a raw stored value onto fresh defaults,
	type-checking each one -- nested records field by field -- so a
	corrupt or outdated record can never poison a session.
]]
local function sanitize(result: any): PlayerData
	local data = copyDefaultData()
	if typeof(result) ~= "table" then
		return data
	end

	for _, numberField in ipairs({
		"shells",
		"stormglass",
		"nextUid",
		"reefSlotsUnlocked",
		"reefPool",
		"reefLastAccrualAt",
		"castsSinceRare",
		"castsSinceEpic",
		"streakCount",
		"lastSeenAt",
	}) do
		if typeof(result[numberField]) == "number" then
			data[numberField] = result[numberField]
		end
	end

	for _, stringField in ipairs({
		"companionUid",
		"bountyDate",
		"streakLastDate",
		"equippedTrail",
	}) do
		if typeof(result[stringField]) == "string" then
			data[stringField] = result[stringField]
		end
	end

	if typeof(result.tutorialDone) == "boolean" then
		data.tutorialDone = result.tutorialDone
	end

	-- A corrupt slot count would either lock a paid slot away or hand
	-- out free ones, so it is pinned to the legal range on top of the
	-- type check.
	data.reefSlotsUnlocked = math.clamp(
		data.reefSlotsUnlocked,
		TidetownConfig.reef.startingSlots,
		TidetownConfig.reef.maxSlots
	)

	-- Creature records are rebuilt field by field so one corrupt entry
	-- cannot smuggle bad types into a session.
	if typeof(result.creatures) == "table" then
		for _, creature in ipairs(result.creatures) do
			if
				typeof(creature) == "table"
				and typeof(creature.uid) == "string"
				and typeof(creature.species) == "string"
			then
				table.insert(data.creatures, {
					uid = creature.uid,
					species = creature.species,
					nickname = if typeof(creature.nickname) == "string"
						then creature.nickname
						else "",
					caughtAt = if typeof(creature.caughtAt) == "number"
						then creature.caughtAt
						else 0,
				})
			end
		end
	end

	-- nextUid must stay ahead of every kept creature uid, or a corrupt
	-- record would make the next hatch mint a duplicate uid that
	-- permanently shadows an existing creature.
	local highestUidNumber = 0
	for _, creature in ipairs(data.creatures) do
		local uidNumber = tonumber(string.match(creature.uid, "^c(%d+)$"))
		if uidNumber ~= nil and uidNumber > highestUidNumber then
			highestUidNumber = uidNumber
		end
	end
	data.nextUid = math.max(math.floor(data.nextUid), highestUidNumber + 1)

	-- The defense team stores creature uids; CreatureService ignores
	-- any uid that no longer exists, so string-checking plus the size
	-- cap is enough here.
	if typeof(result.defenseTeam) == "table" then
		for _, uid in ipairs(result.defenseTeam) do
			if
				typeof(uid) == "string"
				and #data.defenseTeam < TidetownConfig.creatures.defenseTeamSize
			then
				table.insert(data.defenseTeam, uid)
			end
		end
	end

	if typeof(result.eggs) == "table" then
		for _, egg in ipairs(result.eggs) do
			if
				typeof(egg) == "table"
				and typeof(egg.uid) == "string"
				and typeof(egg.eggKey) == "string"
			then
				table.insert(data.eggs, {
					uid = egg.uid,
					eggKey = egg.eggKey,
					charge = if typeof(egg.charge) == "number" then egg.charge else 0,
				})
			end
		end
	end

	-- BountyService re-rolls the whole set on a date mismatch, so a
	-- well-formed record is all a stored bounty has to prove.
	if typeof(result.bounties) == "table" then
		for _, bounty in ipairs(result.bounties) do
			if
				typeof(bounty) == "table"
				and typeof(bounty.key) == "string"
				and typeof(bounty.target) == "number"
			then
				table.insert(data.bounties, {
					key = bounty.key,
					target = bounty.target,
					progress = if typeof(bounty.progress) == "number" then bounty.progress else 0,
					claimed = bounty.claimed == true,
				})
			end
		end
	end

	for _, stringListField in ipairs({ "mountsOwned", "decorationsOwned", "trailsOwned" }) do
		if typeof(result[stringListField]) == "table" then
			for _, entry in ipairs(result[stringListField]) do
				if typeof(entry) == "string" then
					table.insert(data[stringListField], entry)
				end
			end
		end
	end

	-- Reef placements are keyed by the slot index as a string, mapping
	-- to the placed creature's uid.
	if typeof(result.reefPlaced) == "table" then
		for slotIndex, uid in pairs(result.reefPlaced) do
			if typeof(slotIndex) == "string" and typeof(uid) == "string" then
				data.reefPlaced[slotIndex] = uid
			end
		end
	end

	-- Tidepedia entries map a species key to the unix time of the first
	-- catch.
	if typeof(result.tidepedia) == "table" then
		for speciesKey, firstCaughtAt in pairs(result.tidepedia) do
			if typeof(speciesKey) == "string" and typeof(firstCaughtAt) == "number" then
				data.tidepedia[speciesKey] = firstCaughtAt
			end
		end
	end

	-- Claimed streak milestones are keyed by the milestone's day count
	-- as a string.
	if typeof(result.claimedStreakMilestones) == "table" then
		for days, claimed in pairs(result.claimedStreakMilestones) do
			if typeof(days) == "string" and typeof(claimed) == "boolean" then
				data.claimedStreakMilestones[days] = claimed
			end
		end
	end

	if typeof(result.upgrades) == "table" then
		for upgradeKey, level in pairs(result.upgrades) do
			if typeof(upgradeKey) == "string" and typeof(level) == "number" then
				data.upgrades[upgradeKey] = level
			end
		end
	end

	-- Settings feed straight into client sound volumes, so the numbers
	-- are clamped on top of the type check.
	if typeof(result.settings) == "table" then
		for _, volumeField in ipairs({ "musicVolume", "sfxVolume" }) do
			if typeof(result.settings[volumeField]) == "number" then
				data.settings[volumeField] = math.clamp(result.settings[volumeField], 0, 1)
			end
		end

		if typeof(result.settings.reducedMotion) == "boolean" then
			data.settings.reducedMotion = result.settings.reducedMotion
		end
	end

	return data
end

--[[
	Fetches a player's saved data, retrying with backoff. Yields; call
	from a spawned task. Always returns usable data -- defaults if every
	attempt failed -- but only marks the session save-safe on success.
]]
function TidetownData.loadAsync(player: Player): PlayerData
	if store == nil then
		return copyDefaultData()
	end

	for attempt = 1, TidetownConfig.data.loadAttempts do
		-- GetAsync throws on throttling and outages; those are the errors
		-- we retry. Anything else lands in the same retry path harmlessly.
		local success, result = pcall(function()
			return store:GetAsync(tostring(player.UserId))
		end)

		if success then
			loadedPlayerByUserId[player.UserId] = player

			return sanitize(result)
		end

		if attempt < TidetownConfig.data.loadAttempts then
			task.wait(TidetownConfig.data.retryBaseSeconds * 2 ^ (attempt - 1))
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
function TidetownData.saveAsync(player: Player, snapshot: PlayerData)
	if store == nil or loadedPlayerByUserId[player.UserId] ~= player then
		return
	end

	-- SetAsync throws on throttling and outages; one retry is enough here
	-- because autosave and the leave-save give us more chances later.
	-- BindToClose drains this counter so the server never dies with a
	-- leave-save still in flight.
	pendingSaves += 1

	local success, result = pcall(function()
		store:SetAsync(tostring(player.UserId), snapshot)
	end)

	pendingSaves -= 1

	if not success then
		warn(string.format("Data save failed for %s: %s", player.Name, tostring(result)))
	end
end

function TidetownData.forgetPlayer(player: Player)
	-- Only forget the session that is actually this instance; a stale
	-- deferred forget from a previous session must not evict a rejoined
	-- player's fresh eligibility.
	if loadedPlayerByUserId[player.UserId] == player then
		loadedPlayerByUserId[player.UserId] = nil
	end
end

--[[
	Starts autosave and the shutdown save. getSnapshot is injected so this
	module stays ignorant of where runtime state lives.
]]
function TidetownData.start(getSnapshot: (Player) -> PlayerData?)
	-- GetDataStore throws in Studio when API access is disabled; the game
	-- then runs memory-only, which is fine for local testing.
	local success, result = pcall(function()
		return DataStoreService:GetDataStore(TidetownConfig.data.storeName)
	end)

	if success then
		store = result
	else
		warn("DataStores unavailable; progress will not save this session")
	end

	task.spawn(function()
		while true do
			task.wait(TidetownConfig.data.autosaveSeconds)

			for _, player in ipairs(Players:GetPlayers()) do
				local snapshot = getSnapshot(player)
				if snapshot ~= nil then
					task.spawn(TidetownData.saveAsync, player, snapshot)
				end
			end
		end
	end)

	game:BindToClose(function()
		-- Saves run in parallel to fit the shutdown budget; task.spawn
		-- runs each one synchronously up to its first yield, so every
		-- save increments pendingSaves before the drain loop below.
		for _, player in ipairs(Players:GetPlayers()) do
			local snapshot = getSnapshot(player)
			if snapshot ~= nil then
				task.spawn(TidetownData.saveAsync, player, snapshot)
			end
		end

		while pendingSaves > 0 do
			task.wait(0.1)
		end
	end)
end

return TidetownData
