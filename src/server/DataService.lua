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

local DEFAULT_DATA = {
	maxSize = 0,
	rebirths = 0,
}

local store = nil
local loadedOkByUserId: { [number]: boolean } = {}

local DataService = {}

local function copyDefaultData(): { maxSize: number, rebirths: number }
	return {
		maxSize = DEFAULT_DATA.maxSize,
		rebirths = DEFAULT_DATA.rebirths,
	}
end

--[[
	Fetches a player's saved data, retrying with backoff. Yields; call from
	a spawned task. Always returns usable data -- defaults if every attempt
	failed -- but only marks the session save-safe on success.
]]
function DataService.loadAsync(player: Player): { maxSize: number, rebirths: number }
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

			local data = copyDefaultData()
			if typeof(result) == "table" then
				if typeof(result.maxSize) == "number" then
					data.maxSize = result.maxSize
				end
				if typeof(result.rebirths) == "number" then
					data.rebirths = result.rebirths
				end
			end

			return data
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
function DataService.saveAsync(player: Player, snapshot: { maxSize: number, rebirths: number })
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
function DataService.start(getSnapshot: (Player) -> { maxSize: number, rebirths: number }?)
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
