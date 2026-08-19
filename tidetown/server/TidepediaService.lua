--[[
	The collection log: one permanent timestamp per species the player
	has ever caught. Entry count is the game's horizontal progression
	-- it feeds the capped luck buff, the Keeper Rank, and the zone
	gates -- so this service is the single authority other systems ask
	instead of counting entries themselves.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TidetownShared = ReplicatedStorage.TidetownShared
local CreatureCatalog = require(TidetownShared.CreatureCatalog)
local TideLayout = require(TidetownShared.TideLayout)
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

export type Dependencies = {
	pushToast: (Player, string, string?) -> (),
}

local entriesByPlayer: { [Player]: { [string]: number } } = {}
local dependencies: Dependencies? = nil
local syncStateRemote: RemoteEvent? = nil

local TidepediaService = {}

-- Cloned at every boundary crossing so no caller ever holds an alias
-- of the live entries table.
local function copyEntries(entries: { [string]: number }): { [string]: number }
	return table.clone(entries)
end

local function countOf(entries: { [string]: number }): number
	local count = 0
	for _ in pairs(entries) do
		count += 1
	end

	return count
end

-- Luck bends only the top of the rarity table and is hard-capped:
-- past the cap, new entries pay pride, not power.
local function luckFor(count: number): number
	local tidepedia = TidetownConfig.tidepedia

	return math.min(count * tidepedia.buffPerEntryPercent, tidepedia.aggregateCapPercent)
end

local function rankFor(count: number): number
	return math.floor(count / TidetownConfig.tidepedia.entriesPerKeeperRank)
end

--[[
	Mirrors the entry count onto the player attributes and the
	leaderstats board. CurrencyService builds the board; the lookup
	tolerates its absence so initialization order never throws here.
]]
local function updateBoard(player: Player, count: number)
	player:SetAttribute("TidepediaCount", count)
	player:SetAttribute("KeeperRank", rankFor(count))

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats ~= nil then
		local tidepediaValue = leaderstats:FindFirstChild("Tidepedia")
		if tidepediaValue ~= nil and tidepediaValue:IsA("IntValue") then
			tidepediaValue.Value = count
		end
	end
end

--[[
	Toasts the milestones a new entry crossed: a Keeper Rank up or a
	zone gate opening. Announced here because only this service knows
	both counts of the crossing.
]]
local function announceUnlocks(player: Player, previousCount: number, count: number)
	local currentDependencies = dependencies
	if currentDependencies == nil then
		return
	end

	local rank = rankFor(count)
	if rank > rankFor(previousCount) then
		currentDependencies.pushToast(player, string.format("Keeper Rank %d!", rank), "good")
	end

	for zoneKey, gate in pairs(TidetownConfig.tidepedia.zoneEntryGates) do
		if previousCount < gate and count >= gate then
			local zone = TideLayout.zoneInfo(zoneKey)
			local zoneName = if zone ~= nil then zone.name else zoneKey
			currentDependencies.pushToast(
				player,
				string.format("New waters unlocked: %s!", zoneName),
				"rare"
			)
		end
	end
end

--[[
	Sends the player's full Tidepedia view to their client. Called
	after every mutation so the client never has to ask.
]]
function TidepediaService.pushState(player: Player)
	local entries = entriesByPlayer[player]
	if entries == nil or syncStateRemote == nil then
		return
	end

	local count = countOf(entries)
	syncStateRemote:FireClient(player, "tidepedia", {
		entries = copyEntries(entries),
		luckPercent = luckFor(count),
		keeperRank = rankFor(count),
		count = count,
		gates = TidetownConfig.tidepedia.zoneEntryGates,
	})
end

function TidepediaService.initializePlayer(player: Player, entries: { [string]: number })
	-- Copied so this service owns its slice outright instead of
	-- aliasing the loaded PlayerData table.
	local copied = copyEntries(entries)
	entriesByPlayer[player] = copied

	updateBoard(player, countOf(copied))
	TidepediaService.pushState(player)
end

function TidepediaService.snapshot(player: Player): { [string]: number }?
	local entries = entriesByPlayer[player]
	if entries == nil then
		return nil
	end

	-- Copied so the save snapshot cannot alias live state that a later
	-- catch could mutate mid-save.
	return copyEntries(entries)
end

function TidepediaService.removePlayer(player: Player)
	entriesByPlayer[player] = nil
end

--[[
	Stamps a first catch of the species and returns whether it was new.
	Unknown keys must never mint entries -- the count gates zones, so a
	stray key would inflate real progression.
]]
function TidepediaService.record(player: Player, speciesKey: string): boolean
	local entries = entriesByPlayer[player]
	if entries == nil then
		return false
	end

	if CreatureCatalog.speciesFor(speciesKey) == nil then
		return false
	end

	if entries[speciesKey] ~= nil then
		return false
	end

	local previousCount = countOf(entries)
	entries[speciesKey] = os.time()
	local count = previousCount + 1

	updateBoard(player, count)
	announceUnlocks(player, previousCount, count)
	TidepediaService.pushState(player)

	return true
end

function TidepediaService.entryCount(player: Player): number
	local entries = entriesByPlayer[player]
	if entries == nil then
		return 0
	end

	return countOf(entries)
end

function TidepediaService.luckPercent(player: Player): number
	return luckFor(TidepediaService.entryCount(player))
end

function TidepediaService.keeperRank(player: Player): number
	return rankFor(TidepediaService.entryCount(player))
end

function TidepediaService.zoneUnlocked(player: Player, zoneKey: string): boolean
	local gate = TidetownConfig.tidepedia.zoneEntryGates[zoneKey]
	if gate == nil then
		return false
	end

	return TidepediaService.entryCount(player) >= gate
end

--[[
	Stores the wiring from init and fetches the SyncState remote once.
	TidetownRemotes.get yields, which is why init calls start from a
	spawned task.
]]
function TidepediaService.start(startDependencies: Dependencies)
	dependencies = startDependencies
	syncStateRemote = TidetownRemotes.get("SyncState") :: RemoteEvent
end

return TidepediaService
