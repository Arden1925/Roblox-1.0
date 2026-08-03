--[[
	Daily quests, the login streak, and the group reward chest. Quests
	are three random templates rolled per player per UTC day; other
	services report progress through QuestService.increment. State is
	published as attributes (QuestsJson, StreakCount, StreakClaimable,
	GroupChestClaimed) for the quest window to render.

	Coin rewards go through an injected grantor so this module never
	requires EconomyService (which sits below several services that need
	to report quest progress).
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)

type Quest = {
	key: string,
	description: string,
	stat: string,
	target: number,
	rewardCoins: number,
	progress: number,
	claimed: boolean,
}

type QuestRecord = {
	questDate: string,
	quests: { Quest },
	streakCount: number,
	streakLastDate: string,
	groupChestClaimed: boolean,
}

local recordByPlayer: { [Player]: QuestRecord } = {}

local awardCoins: (Player, number) -> () = function() end

local QuestService = {}

local function todayString(): string
	return os.date("!%Y-%m-%d")
end

local function yesterdayString(): string
	return os.date("!%Y-%m-%d", os.time() - 24 * 60 * 60)
end

local function rollQuests(): { Quest }
	local templates = table.clone(GameConfig.questTemplates)
	local quests = {}

	for _ = 1, math.min(3, #templates) do
		local pickedIndex = math.random(#templates)
		local template = table.remove(templates, pickedIndex)

		table.insert(quests, {
			key = template.key,
			description = string.format(template.description, template.target),
			stat = template.stat,
			target = template.target,
			rewardCoins = template.rewardCoins,
			progress = 0,
			claimed = false,
		})
	end

	return quests
end

local function publish(player: Player, record: QuestRecord)
	player:SetAttribute("QuestsJson", HttpService:JSONEncode(record.quests))
	player:SetAttribute("StreakCount", record.streakCount)
	player:SetAttribute("StreakClaimable", record.streakLastDate ~= todayString())
	player:SetAttribute("GroupChestClaimed", record.groupChestClaimed)
end

function QuestService.increment(player: Player, stat: string)
	local record = recordByPlayer[player]
	if record == nil then
		return
	end

	local changed = false
	for _, quest in ipairs(record.quests) do
		if quest.stat == stat and not quest.claimed and quest.progress < quest.target then
			quest.progress += 1
			changed = true
		end
	end

	if changed then
		publish(player, record)
	end
end

-- Wired as ClaimQuest.OnServerInvoke.
function QuestService.claimQuest(player: Player, questIndex: any): (boolean, string)
	local record = recordByPlayer[player]
	if record == nil or typeof(questIndex) ~= "number" then
		return false, "Try again in a moment."
	end

	local quest = record.quests[questIndex]
	if quest == nil or quest.claimed then
		return false, "Nothing to claim there."
	end

	if quest.progress < quest.target then
		return false, "That quest is not finished yet!"
	end

	quest.claimed = true
	awardCoins(player, quest.rewardCoins)
	publish(player, record)

	return true, string.format("Quest complete: +%d coins!", quest.rewardCoins)
end

-- Wired as ClaimStreak.OnServerInvoke.
function QuestService.claimStreak(player: Player): (boolean, string)
	local record = recordByPlayer[player]
	if record == nil then
		return false, "Try again in a moment."
	end

	if record.streakLastDate == todayString() then
		return false, "Already claimed today -- come back tomorrow!"
	end

	-- Missing a day resets the streak to day one.
	if record.streakLastDate ~= yesterdayString() then
		record.streakCount = 0
	end

	record.streakCount += 1
	record.streakLastDate = todayString()

	local rewardIndex = (record.streakCount - 1) % #GameConfig.streakRewards + 1
	local reward = GameConfig.streakRewards[rewardIndex]
	awardCoins(player, reward.coins)
	publish(player, record)

	return true, string.format("Day %d streak: +%d coins!", record.streakCount, reward.coins)
end

-- Wired as ClaimGroupChest.OnServerInvoke.
function QuestService.claimGroupChest(player: Player): (boolean, string)
	local record = recordByPlayer[player]
	if record == nil then
		return false, "Try again in a moment."
	end

	if GameConfig.group.groupId == 0 then
		return false, "The group is coming soon -- the chest will open then!"
	end

	if record.groupChestClaimed then
		return false, "You already claimed the group reward. Thank you!"
	end

	-- IsInGroupAsync yields and throws on group-service outages; treat
	-- failure as not-in-group and let the player retry.
	local success, inGroup = pcall(function()
		return player:IsInGroupAsync(GameConfig.group.groupId)
	end)

	if not success or inGroup ~= true then
		return false, "Join the group (and like the game!), then claim your reward."
	end

	record.groupChestClaimed = true
	awardCoins(player, GameConfig.group.rewardCoins)
	publish(player, record)

	return true, string.format("Group reward: +%d coins!", GameConfig.group.rewardCoins)
end

function QuestService.initializePlayer(
	player: Player,
	questDate: string,
	savedQuests: { Quest },
	streakCount: number,
	streakLastDate: string,
	groupChestClaimed: boolean
)
	local record: QuestRecord = {
		questDate = questDate,
		quests = savedQuests,
		streakCount = streakCount,
		streakLastDate = streakLastDate,
		groupChestClaimed = groupChestClaimed,
	}

	-- A new day means a fresh quest roll; an old save keeps its board.
	if record.questDate ~= todayString() or #record.quests == 0 then
		record.questDate = todayString()
		record.quests = rollQuests()
	end

	recordByPlayer[player] = record
	publish(player, record)
end

function QuestService.snapshot(player: Player): (string?, { Quest }?, number?, string?, boolean?)
	local record = recordByPlayer[player]
	if record == nil then
		return nil, nil, nil, nil, nil
	end

	return record.questDate,
		record.quests,
		record.streakCount,
		record.streakLastDate,
		record.groupChestClaimed
end

function QuestService.removePlayer(player: Player)
	recordByPlayer[player] = nil
end

function QuestService.start(dependencies: { awardCoins: (Player, number) -> () })
	awardCoins = dependencies.awardCoins
end

return QuestService
