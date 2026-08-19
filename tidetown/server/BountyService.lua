--[[
	Owns the daily bounty board and the claim streak. Three bounties
	roll fresh per UTC day from the config templates; other services
	report progress by key, and claims pay out through the currency
	dependencies. Only key, target, progress, and claimed persist --
	text and rewards merge back from the template at sync time, so a
	config rebalance applies even to already-rolled bounties.

	The streak deliberately PAUSES on missed days instead of resetting:
	the count rises on the first claim of any day and never moves
	backward, so coming back after a break always continues the climb.
	Milestones auto-award the moment the count reaches them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TidetownShared = ReplicatedStorage.TidetownShared
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

export type BountyRecord = {
	key: string,
	target: number,
	progress: number,
	claimed: boolean,
}

type BountyTemplate = {
	key: string,
	text: string,
	target: number,
	shellReward: number,
	stormglassReward: number?,
}

type PlayerState = {
	date: string,
	bounties: { BountyRecord },
	streakCount: number,
	streakLastDate: string,
	claimedMilestones: { [string]: boolean },
}

type Dependencies = {
	awardShells: (Player, number) -> (),
	awardStormglass: (Player, number) -> (),
	pushToast: (Player, string, string?) -> (),
}

local BountyService = {}

local statesByPlayer: { [Player]: PlayerState } = {}
local dependencies: Dependencies? = nil
local syncStateRemote: RemoteEvent? = nil

-- The "!" prefix pins the stamp to UTC so every server region agrees
-- on the moment "today" flips.
local function todayUtc(): string
	return os.date("!%Y-%m-%d")
end

local function templateFor(key: string): BountyTemplate?
	for _, template in ipairs(TidetownConfig.bounties.templates) do
		if template.key == key then
			return template
		end
	end

	return nil
end

local function copyBountyList(bounties: { BountyRecord }): { BountyRecord }
	local copy = {}
	for _, bounty in ipairs(bounties) do
		table.insert(copy, {
			key = bounty.key,
			target = bounty.target,
			progress = bounty.progress,
			claimed = bounty.claimed,
		})
	end

	return copy
end

--[[
	Rolls the day's bounties: distinct templates picked by a partial
	Fisher-Yates shuffle, then sorted back into template order so the
	board always reads in the same familiar sequence.
]]
local function rollDailyBounties(): { BountyRecord }
	local templates = TidetownConfig.bounties.templates
	local indices = {}
	for index = 1, #templates do
		table.insert(indices, index)
	end

	local perDay = math.min(TidetownConfig.bounties.perDay, #templates)
	for pickIndex = 1, perDay do
		local swapIndex = math.random(pickIndex, #templates)
		indices[pickIndex], indices[swapIndex] = indices[swapIndex], indices[pickIndex]
	end

	local picked = {}
	for pickIndex = 1, perDay do
		table.insert(picked, indices[pickIndex])
	end
	table.sort(picked)

	local bounties = {}
	for _, templateIndex in ipairs(picked) do
		local template = templates[templateIndex]
		table.insert(bounties, {
			key = template.key,
			target = template.target,
			progress = 0,
			claimed = false,
		})
	end

	return bounties
end

--[[
	Awards every milestone the streak has reached but not yet paid.
	Ran after each streak advance so milestones can never be missed,
	even when a config edit adds one below an existing count.
]]
local function awardStreakMilestones(player: Player, state: PlayerState)
	local currentDependencies = dependencies
	if currentDependencies == nil then
		return
	end

	for _, milestone in ipairs(TidetownConfig.bounties.streakMilestones) do
		local milestoneKey = tostring(milestone.days)
		if
			milestone.days <= state.streakCount
			and state.claimedMilestones[milestoneKey] ~= true
		then
			state.claimedMilestones[milestoneKey] = true
			currentDependencies.awardShells(player, milestone.shellReward)
			currentDependencies.pushToast(
				player,
				string.format("%d-day streak! +%d Shells", milestone.days, milestone.shellReward),
				"rare"
			)
		end
	end
end

--[[
	Sends the player's full bounty board to their client, with text and
	rewards merged in from the template by key so the client never
	reads the config for display strings.
]]
function BountyService.pushState(player: Player)
	local state = statesByPlayer[player]
	if state == nil or syncStateRemote == nil then
		return
	end

	local list = {}
	for _, bounty in ipairs(state.bounties) do
		local template = templateFor(bounty.key)
		local stormglassReward = if template ~= nil and template.stormglassReward ~= nil
			then template.stormglassReward
			else 0
		table.insert(list, {
			key = bounty.key,
			text = if template ~= nil then template.text else bounty.key,
			target = bounty.target,
			progress = bounty.progress,
			claimed = bounty.claimed,
			shellReward = if template ~= nil then template.shellReward else 0,
			stormglassReward = stormglassReward,
		})
	end

	local milestones = {}
	for _, milestone in ipairs(TidetownConfig.bounties.streakMilestones) do
		table.insert(milestones, {
			days = milestone.days,
			shellReward = milestone.shellReward,
			claimed = state.claimedMilestones[tostring(milestone.days)] == true,
		})
	end

	syncStateRemote:FireClient(player, "bounties", {
		date = state.date,
		list = list,
		streakCount = state.streakCount,
		milestones = milestones,
	})
end

function BountyService.initializePlayer(
	player: Player,
	bountyDate: string,
	bounties: { BountyRecord },
	streakCount: number,
	streakLastDate: string,
	claimedMilestones: { [string]: boolean }
)
	local today = todayUtc()
	local todaysBounties: { BountyRecord }
	if bountyDate == today then
		-- Copied so this service owns its slice outright instead of
		-- aliasing the loaded PlayerData table.
		todaysBounties = copyBountyList(bounties)
	else
		-- A new UTC day rolls a fresh board. The streak survives the
		-- rollover untouched: missed days pause it, never reset it.
		todaysBounties = rollDailyBounties()
	end

	statesByPlayer[player] = {
		date = today,
		bounties = todaysBounties,
		streakCount = streakCount,
		streakLastDate = streakLastDate,
		claimedMilestones = table.clone(claimedMilestones),
	}

	BountyService.pushState(player)
end

function BountyService.snapshot(player: Player): (
	string?,
	{ BountyRecord }?,
	number?,
	string?,
	{ [string]: boolean }?
)
	local state = statesByPlayer[player]
	if state == nil then
		return nil, nil, nil, nil, nil
	end

	-- Copied so the save snapshot cannot alias live state that a later
	-- report could mutate mid-save.
	return state.date,
		copyBountyList(state.bounties),
		state.streakCount,
		state.streakLastDate,
		table.clone(state.claimedMilestones)
end

function BountyService.removePlayer(player: Player)
	statesByPlayer[player] = nil
end

--[[
	Adds progress to the matching unclaimed bounty. Called by other
	services after real gameplay events, never by remotes, so the
	amount is trusted beyond a basic sanity check. Sync is throttled to
	whole-number crossings and completion because high-frequency
	reporters (ride distance) would otherwise flood the client.
]]
function BountyService.report(player: Player, key: string, amount: number)
	local state = statesByPlayer[player]
	if state == nil then
		return
	end

	if typeof(key) ~= "string" then
		return
	end

	if typeof(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end

	for _, bounty in ipairs(state.bounties) do
		if bounty.key == key and not bounty.claimed and bounty.progress < bounty.target then
			local previousProgress = bounty.progress
			bounty.progress = math.min(bounty.progress + amount, bounty.target)

			local crossedWhole = math.floor(bounty.progress) > math.floor(previousProgress)
			if crossedWhole or bounty.progress >= bounty.target then
				BountyService.pushState(player)
			end
		end
	end
end

--[[
	Pays out a finished bounty from the untrusted ClaimBounty remote.
	The first claim of any UTC day also advances the streak; because
	the streak pauses rather than resets, the advance is simply "+1
	whenever the last claim day is not today", no gap math needed.
]]
function BountyService.claimBounty(player: Player, index: any): (boolean, any)
	local state = statesByPlayer[player]
	local currentDependencies = dependencies
	if state == nil or currentDependencies == nil then
		return false, "Not ready"
	end

	if typeof(index) ~= "number" or index % 1 ~= 0 then
		return false, "No such bounty"
	end

	local bounty = state.bounties[index]
	if bounty == nil then
		return false, "No such bounty"
	end

	if bounty.claimed then
		return false, "Already claimed"
	end

	if bounty.progress < bounty.target then
		return false, "Not finished yet"
	end

	bounty.claimed = true

	-- A missing template means the config changed under a saved
	-- bounty; the claim still clears it, just without pay.
	local template = templateFor(bounty.key)
	local shellReward = if template ~= nil then template.shellReward else 0
	local stormglassReward = if template ~= nil and template.stormglassReward ~= nil
		then template.stormglassReward
		else 0
	if shellReward > 0 then
		currentDependencies.awardShells(player, shellReward)
	end
	if stormglassReward > 0 then
		currentDependencies.awardStormglass(player, stormglassReward)
	end

	local today = todayUtc()
	if state.streakLastDate ~= today then
		state.streakCount += 1
		state.streakLastDate = today
		awardStreakMilestones(player, state)
	end

	BountyService.pushState(player)

	return true,
		{
			shellReward = shellReward,
			stormglassReward = stormglassReward,
			streakCount = state.streakCount,
		}
end

--[[
	Wires dependencies and fetches the SyncState remote (yields, which
	is why init calls start from a spawned task).
]]
function BountyService.start(dependencyTable: Dependencies)
	dependencies = dependencyTable
	syncStateRemote = TidetownRemotes.get("SyncState") :: RemoteEvent
end

return BountyService
