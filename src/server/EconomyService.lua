--[[
	Coins and everything they buy: pickups on the map, checkpoint and
	world-reach rewards, station potions, permanent upgrades, and the
	Mystery Machine. Coin balances and upgrade levels are published as
	player attributes (Coins, Upgrade<Key>) so HUDs and SizeService read
	them without depending on this module.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Server = script.Parent
local SizeService = require(Server.SizeService)

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)

local COIN_TAG = "Coin"

local coinsByPlayer: { [Player]: number } = {}
local upgradesByPlayer: { [Player]: { [string]: number } } = {}

local EconomyService = {}

local function potionByKey(potionKey: string): { [string]: any }?
	for _, potion in ipairs(GameConfig.potions) do
		if potion.key == potionKey then
			return potion
		end
	end

	return nil
end

local function upgradeByKey(upgradeKey: string): { [string]: any }?
	for _, upgrade in ipairs(GameConfig.upgrades) do
		if upgrade.key == upgradeKey then
			return upgrade
		end
	end

	return nil
end

local function publishCoins(player: Player)
	player:SetAttribute("Coins", math.floor(coinsByPlayer[player] or 0))
end

function EconomyService.upgradeLevel(player: Player, upgradeKey: string): number
	local upgrades = upgradesByPlayer[player]
	if upgrades == nil then
		return 0
	end

	return upgrades[upgradeKey] or 0
end

function EconomyService.upgradeCost(player: Player, upgradeKey: string): number?
	local upgrade = upgradeByKey(upgradeKey)
	if upgrade == nil then
		return nil
	end

	local level = EconomyService.upgradeLevel(player, upgradeKey)
	if level >= upgrade.maxLevel then
		return nil
	end

	return math.floor(upgrade.baseCost * upgrade.costGrowth ^ level)
end

--[[
	All coin income funnels through here so Coin Magnet applies
	everywhere without every caller remembering it.
]]
function EconomyService.awardCoins(player: Player, baseAmount: number)
	if coinsByPlayer[player] == nil then
		return
	end

	local upgrade = upgradeByKey("CoinUpgrade")
	local bonusPerLevel = if upgrade ~= nil then upgrade.bonusPerLevel else 0
	local magnet = 1 + EconomyService.upgradeLevel(player, "CoinUpgrade") * bonusPerLevel

	coinsByPlayer[player] += baseAmount * magnet
	publishCoins(player)
end

function EconomyService.awardWorldReach(player: Player, worldIndex: number)
	EconomyService.awardCoins(player, GameConfig.economy.worldReachCoinBase * worldIndex)
end

function EconomyService.awardCheckpoint(player: Player, worldIndex: number)
	EconomyService.awardCoins(player, GameConfig.economy.checkpointCoinBase * worldIndex)
end

local function trySpend(player: Player, cost: number): boolean
	local balance = coinsByPlayer[player]
	if balance == nil or balance < cost then
		return false
	end

	coinsByPlayer[player] = balance - cost
	publishCoins(player)

	return true
end

-- PetService validates the balance itself before hatching; this just
-- executes the deduction.
function EconomyService.spendForEgg(player: Player, cost: number): boolean
	return trySpend(player, cost)
end

-- Wired as BuyPotion.OnServerInvoke.
function EconomyService.buyPotion(player: Player, potionKey: any): (boolean, string)
	local potion = if typeof(potionKey) == "string" then potionByKey(potionKey) else nil
	if potion == nil then
		return false, "That potion does not exist."
	end

	local worldIndex = player:GetAttribute("CurrentWorld")
	if typeof(worldIndex) ~= "number" then
		worldIndex = 1
	end

	local cost = potion.baseCost * worldIndex
	if not trySpend(player, cost) then
		return false, string.format("You need %d coins for that.", cost)
	end

	if potion.effect == "instantSize" then
		SizeService.grantMaxSize(player, potion.amount * worldIndex)
	else
		local expiresAt = Workspace:GetServerTimeNow() + potion.durationSeconds
		player:SetAttribute(potion.effectKey .. "Until", expiresAt)
	end

	return true, string.format("%s used!", potion.name)
end

-- Wired as BuyUpgrade.OnServerInvoke.
function EconomyService.buyUpgrade(player: Player, upgradeKey: any): (boolean, string)
	local upgrade = if typeof(upgradeKey) == "string" then upgradeByKey(upgradeKey) else nil
	if upgrade == nil then
		return false, "That upgrade does not exist."
	end

	local cost = EconomyService.upgradeCost(player, upgradeKey)
	if cost == nil then
		return false, "Already at max level!"
	end

	if not trySpend(player, cost) then
		return false, string.format("You need %d coins for that.", cost)
	end

	local upgrades = upgradesByPlayer[player]
	upgrades[upgradeKey] = (upgrades[upgradeKey] or 0) + 1
	player:SetAttribute("Upgrade" .. upgradeKey, upgrades[upgradeKey])

	return true, string.format("%s is now level %d!", upgrade.name, upgrades[upgradeKey])
end

-- Wired as UseMysteryMachine.OnServerInvoke.
function EconomyService.useMysteryMachine(player: Player): (boolean, string)
	local worldIndex = player:GetAttribute("CurrentWorld")
	if typeof(worldIndex) ~= "number" then
		return false, "Try again in a moment."
	end

	local cost = GameConfig.economy.mysteryMachineBaseCost * worldIndex
	if not trySpend(player, cost) then
		return false, string.format("The machine wants %d coins.", cost)
	end

	local roll = math.random(3)
	if roll == 1 then
		local expiresAt = Workspace:GetServerTimeNow() + 600
		player:SetAttribute("MysteryGrowthUntil", expiresAt)

		return true, "JACKPOT: x3 growth for 10 minutes!"
	elseif roll == 2 then
		SizeService.grantMaxSize(player, 150 * worldIndex)

		return true, string.format("The machine spits out +%d Max Size!", 150 * worldIndex)
	end

	local expiresAt = Workspace:GetServerTimeNow() + 600
	player:SetAttribute("SpeedPotionUntil", expiresAt)

	return true, "Zoom! Bonus speed for 10 minutes!"
end

local function watchCoin(coin: BasePart)
	coin.Touched:Connect(function(hit)
		if coin.Transparency > 0 then
			return
		end

		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player == nil then
			return
		end

		local worldIndex = coin:GetAttribute("WorldIndex")
		if typeof(worldIndex) ~= "number" then
			worldIndex = 1
		end

		-- Hide rather than destroy so the coin can respawn for the next
		-- runner without regenerating the map.
		coin.Transparency = 1
		coin.CanTouch = false
		EconomyService.awardCoins(player, GameConfig.economy.coinPickupBase * worldIndex)

		task.delay(GameConfig.economy.coinRespawnSeconds, function()
			coin.Transparency = 0
			coin.CanTouch = true
		end)
	end)
end

function EconomyService.initializePlayer(
	player: Player,
	coins: number,
	upgrades: { [string]: number }
)
	coinsByPlayer[player] = coins
	upgradesByPlayer[player] = upgrades
	publishCoins(player)

	for _, upgrade in ipairs(GameConfig.upgrades) do
		player:SetAttribute("Upgrade" .. upgrade.key, upgrades[upgrade.key] or 0)
	end
end

function EconomyService.snapshot(player: Player): (number?, { [string]: number }?)
	return coinsByPlayer[player], upgradesByPlayer[player]
end

function EconomyService.removePlayer(player: Player)
	coinsByPlayer[player] = nil
	upgradesByPlayer[player] = nil
end

function EconomyService.start()
	for _, coin in ipairs(CollectionService:GetTagged(COIN_TAG)) do
		if coin:IsA("BasePart") then
			watchCoin(coin)
		end
	end

	CollectionService:GetInstanceAddedSignal(COIN_TAG):Connect(function(coin)
		if coin:IsA("BasePart") then
			watchCoin(coin)
		end
	end)
end

return EconomyService
