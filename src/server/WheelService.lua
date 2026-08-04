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

-- The consolation when a reroll lands with no pet equipped.
local REROLL_FALLBACK_COINS = 500

local awardCoins: (Player, number) -> () = function() end
local grantMaxSize: (Player, number) -> () = function() end
local grantUltraPet: (Player) -> string? = function()
	return nil
end
local rerollMutation: (Player) -> string? = function()
	return nil
end

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

-- Returns an optional detail line for rewards whose outcome the label
-- alone cannot describe (which pet, which mutation).
local function applyReward(player: Player, reward: { [string]: any }): string?
	if reward.kind == "coins" then
		awardCoins(player, reward.amount)
	elseif reward.kind == "maxSize" then
		grantMaxSize(player, reward.amount)
	elseif reward.kind == "effect" then
		local expiresAt = Workspace:GetServerTimeNow() + reward.durationSeconds
		player:SetAttribute(reward.effectKey .. "Until", expiresAt)
	elseif reward.kind == "ultraPet" then
		local petName = grantUltraPet(player)

		return if petName ~= nil then "You won " .. petName .. "!" else nil
	elseif reward.kind == "mutationReroll" then
		local newName = rerollMutation(player)
		if newName == nil then
			-- No equipped pet to reroll; pay out coins instead of nothing.
			awardCoins(player, REROLL_FALLBACK_COINS)

			return string.format("No pet equipped -- %d coins instead!", REROLL_FALLBACK_COINS)
		end

		return "Your pet is now " .. newName .. "!"
	end

	return nil
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
	local detail = applyReward(player, reward)
	publish(player, record)

	return true, { rewardIndex = rewardIndex, label = reward.label, detail = detail }
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
	grantUltraPet: (Player) -> string?,
	rerollMutation: (Player) -> string?,
})
	awardCoins = dependencies.awardCoins
	grantMaxSize = dependencies.grantMaxSize
	grantUltraPet = dependencies.grantUltraPet
	rerollMutation = dependencies.rerollMutation
end

return WheelService
