--[[
	Server entry point. All cross-service wiring lives here -- services
	never subscribe to player lifecycle events themselves -- so the order
	of operations on join and leave is visible in one place and save-on-
	leave always runs before state cleanup.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script
local CheckpointService = require(Server.CheckpointService)
local DataService = require(Server.DataService)
local EconomyService = require(Server.EconomyService)
local EventService = require(Server.EventService)
local GateService = require(Server.GateService)
local MapGenerator = require(Server.MapGenerator)
local MechanismService = require(Server.MechanismService)
local ObstacleService = require(Server.ObstacleService)
local PetService = require(Server.PetService)
local QuestService = require(Server.QuestService)
local RebirthService = require(Server.RebirthService)
local ShopService = require(Server.ShopService)
local SizeService = require(Server.SizeService)
local WorldService = require(Server.WorldService)

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)
local SizeFormula = require(Shared.SizeFormula)

Remotes.createAll()

-- Progress is split across services; saving needs it reassembled into
-- one record.
local function snapshotPlayer(player: Player): DataService.PlayerData?
	local sizeSnapshot = SizeService.snapshot(player)
	local reachedWorld = WorldService.reachedWorld(player)
	local coins, upgrades = EconomyService.snapshot(player)
	local pets, equippedPet = PetService.snapshot(player)
	local checkpointsClaimed, respawnWorld, respawnIndex = CheckpointService.snapshot(player)
	local questDate, quests, streakCount, streakLastDate, groupChestClaimed =
		QuestService.snapshot(player)

	if sizeSnapshot == nil or reachedWorld == nil or coins == nil or pets == nil then
		return nil
	end

	local permanentGrowthBonus = player:GetAttribute("PermanentGrowthBonus")

	return {
		maxSize = sizeSnapshot.maxSize,
		rebirths = sizeSnapshot.rebirths,
		reachedWorld = reachedWorld,
		coins = coins,
		tutorialDone = player:GetAttribute("TutorialDone") == true,
		pets = pets,
		equippedPet = equippedPet or "",
		upgrades = upgrades or {},
		checkpointsClaimed = checkpointsClaimed or {},
		respawnWorld = respawnWorld or 1,
		respawnIndex = respawnIndex or 0,
		lastSeenAt = os.time(),
		permanentGrowthBonus = if typeof(permanentGrowthBonus) == "number"
			then permanentGrowthBonus
			else 0,
		groupChestClaimed = groupChestClaimed == true,
		streakCount = streakCount or 0,
		streakLastDate = streakLastDate or "",
		questDate = questDate or "",
		quests = quests or {},
	}
end

--[[
	Away-time growth: a gentle drip per minute offline, scaled by rebirth
	multiplier and capped. The OfflineGain attribute cues the client's
	welcome-back popup.
]]
local function grantOfflineGrowth(player: Player, data: DataService.PlayerData)
	if data.lastSeenAt <= 0 then
		return
	end

	local awaySeconds = math.min(os.time() - data.lastSeenAt, GameConfig.offline.maxHours * 3600)
	if awaySeconds < 60 then
		return
	end

	local multiplier = SizeFormula.growthMultiplier(data.rebirths, {})
	local gain = math.floor(awaySeconds / 60 * GameConfig.offline.sizePerMinute * multiplier)
	if gain > 0 then
		SizeService.grantMaxSize(player, gain)
		player:SetAttribute("OfflineGain", gain)
	end
end

local function onPlayerAdded(player: Player)
	task.spawn(ShopService.prefetchAsync, player)

	local data = DataService.loadAsync(player)
	SizeService.initializePlayer(player, data)
	WorldService.initializePlayer(player, data.reachedWorld)
	EconomyService.initializePlayer(player, data.coins, data.upgrades)
	PetService.initializePlayer(player, data.pets, data.equippedPet)
	CheckpointService.initializePlayer(
		player,
		data.checkpointsClaimed,
		data.respawnWorld,
		data.respawnIndex
	)
	QuestService.initializePlayer(
		player,
		data.questDate,
		data.quests,
		data.streakCount,
		data.streakLastDate,
		data.groupChestClaimed
	)
	player:SetAttribute("TutorialDone", data.tutorialDone)
	grantOfflineGrowth(player, data)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(onPlayerAdded, player)
end)

-- Players who joined while the server was still booting.
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	local snapshot = snapshotPlayer(player)
	SizeService.removePlayer(player)
	WorldService.removePlayer(player)
	EconomyService.removePlayer(player)
	PetService.removePlayer(player)
	CheckpointService.removePlayer(player)
	QuestService.removePlayer(player)

	if snapshot ~= nil then
		task.spawn(function()
			DataService.saveAsync(player, snapshot)
			DataService.forgetPlayer(player)
		end)
	else
		DataService.forgetPlayer(player)
	end
end)

local remoteHandlers: { [string]: (Player, ...any) -> (boolean, string) } = {
	AttemptRebirth = RebirthService.attemptRebirth,
	RequestTeleport = WorldService.attemptTeleport,
	HatchEgg = PetService.hatchEgg,
	EquipPet = PetService.equipPet,
	BuyPotion = EconomyService.buyPotion,
	BuyUpgrade = EconomyService.buyUpgrade,
	UseMysteryMachine = EconomyService.useMysteryMachine,
	ClaimQuest = QuestService.claimQuest,
	ClaimStreak = QuestService.claimStreak,
	ClaimGroupChest = QuestService.claimGroupChest,
}

for remoteName, handler in pairs(remoteHandlers) do
	local remote = Remotes.get(remoteName) :: RemoteFunction
	remote.OnServerInvoke = handler
end

local requestInstantShrink = Remotes.get("RequestInstantShrink") :: RemoteEvent
requestInstantShrink.OnServerEvent:Connect(function(player)
	-- Ownership is checked server-side; the client button is a request.
	if ShopService.playerOwnsPass(player, "InstantShrink") then
		SizeService.forceShrink(player)
	end
end)

local setDesiredSize = Remotes.get("SetDesiredSize") :: RemoteEvent
setDesiredSize.OnServerEvent:Connect(SizeService.setDesiredSize)

local setDesiredSpeed = Remotes.get("SetDesiredSpeed") :: RemoteEvent
setDesiredSpeed.OnServerEvent:Connect(SizeService.setDesiredSpeed)

local markTutorialDone = Remotes.get("MarkTutorialDone") :: RemoteEvent
markTutorialDone.OnServerEvent:Connect(function(player)
	player:SetAttribute("TutorialDone", true)
end)

DataService.start(snapshotPlayer)
ShopService.start({
	grantMaxSize = SizeService.grantMaxSize,
	grantRobuxEggPet = PetService.grantRobuxEggPet,
	grantLimitedPet = PetService.grantLimitedPet,
	awardCoins = EconomyService.awardCoins,
	addPermanentGrowth = SizeService.addPermanentGrowth,
})
QuestService.start({
	awardCoins = EconomyService.awardCoins,
})
SizeService.start()
GateService.start()
WorldService.start()
ObstacleService.start()
EconomyService.start()
CheckpointService.start()
EventService.start()
MechanismService.start()
MapGenerator.generate()
