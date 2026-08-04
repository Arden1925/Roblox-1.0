--[[
	The hub's prize wheel: one free spin per cooldown, extra spins sold
	as a developer product. The roll and the reward both happen here --
	the client only animates the pointer to the slice this service
	picked, so spoofed spins cannot exist. Cooldown and purchased spin
	credits ride the normal save pipeline.

	Publishes WheelNextSpinAt (os.time epoch) and WheelSpinCredits as
	player attributes for the wheel window's countdown.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)

type WheelRecord = {
	lastSpinAt: number,
	credits: number,
}

local recordByPlayer: { [Player]: WheelRecord } = {}

local awardCoins: (Player, number) -> () = function() end
local grantMaxSize: (Player, number) -> () = function() end

local WheelService = {}

local function publish(player: Player, record: WheelRecord)
	player:SetAttribute("WheelNextSpinAt", record.lastSpinAt + GameConfig.wheel.cooldownSeconds)
	player:SetAttribute("WheelSpinCredits", record.credits)
end

-- Weighted roll over the reward list; weights are relative, not
-- percentages, so the list can be retuned freely.
local function rollRewardIndex(): number
	local totalWeight = 0
	for _, reward in ipairs(GameConfig.wheel.rewards) do
		totalWeight += reward.weight
	end

	local roll = math.random() * totalWeight
	for rewardIndex, reward in ipairs(GameConfig.wheel.rewards) do
		roll -= reward.weight
		if roll <= 0 then
			return rewardIndex
		end
	end

	return #GameConfig.wheel.rewards
end

local function applyReward(player: Player, reward: { [string]: any })
	if reward.kind == "coins" then
		awardCoins(player, reward.amount)
	elseif reward.kind == "maxSize" then
		grantMaxSize(player, reward.amount)
	elseif reward.kind == "effect" then
		local expiresAt = Workspace:GetServerTimeNow() + reward.durationSeconds
		player:SetAttribute(reward.effectKey .. "Until", expiresAt)
	end
end

-- Wired as SpinWheel.OnServerInvoke.
function WheelService.spin(player: Player): (boolean, any)
	local record = recordByPlayer[player]
	if record == nil then
		return false, "Try again in a moment."
	end

	local now = os.time()
	if record.credits > 0 then
		record.credits -= 1
	elseif now - record.lastSpinAt >= GameConfig.wheel.cooldownSeconds then
		record.lastSpinAt = now
	else
		local waitSeconds = record.lastSpinAt + GameConfig.wheel.cooldownSeconds - now
		return false,
			string.format(
				"Next free spin in %dh %02dm.",
				waitSeconds // 3600,
				waitSeconds % 3600 // 60
			)
	end

	local rewardIndex = rollRewardIndex()
	local reward = GameConfig.wheel.rewards[rewardIndex]
	applyReward(player, reward)
	publish(player, record)

	return true, { rewardIndex = rewardIndex, label = reward.label }
end

-- Called when the extra-spin developer product is granted.
function WheelService.grantSpinCredit(player: Player)
	local record = recordByPlayer[player]
	if record == nil then
		return
	end

	record.credits += 1
	publish(player, record)
end

function WheelService.initializePlayer(player: Player, lastSpinAt: number, credits: number)
	local record = {
		lastSpinAt = lastSpinAt,
		credits = credits,
	}
	recordByPlayer[player] = record
	publish(player, record)
end

function WheelService.snapshot(player: Player): (number?, number?)
	local record = recordByPlayer[player]
	if record == nil then
		return nil, nil
	end

	return record.lastSpinAt, record.credits
end

function WheelService.removePlayer(player: Player)
	recordByPlayer[player] = nil
end

function WheelService.start(dependencies: {
	awardCoins: (Player, number) -> (),
	grantMaxSize: (Player, number) -> (),
})
	awardCoins = dependencies.awardCoins
	grantMaxSize = dependencies.grantMaxSize
end

return WheelService
