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
local HubService = require(Server.HubService)
local MapGenerator = require(Server.MapGenerator)
local MechanismService = require(Server.MechanismService)
local ObstacleService = require(Server.ObstacleService)
local PetService = require(Server.PetService)
local QuestService = require(Server.QuestService)
local RebirthService = require(Server.RebirthService)
local SceneryService = require(Server.SceneryService)
local ShopService = require(Server.ShopService)
local SizeService = require(Server.SizeService)
local WheelService = require(Server.WheelService)
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
	local pets, equippedPets, petNames, extraPetSlot = PetService.snapshot(player)
	local checkpointsClaimed, respawnWorld, respawnIndex = CheckpointService.snapshot(player)
	local questDate, quests, streakCount, streakLastDate, groupChestClaimed =
		QuestService.snapshot(player)
	local wheelLastSpinAt, wheelSpinCredits = WheelService.snapshot(player)

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
		petNames = petNames or {},
		equippedPet = if equippedPets ~= nil and equippedPets[1] ~= nil
			then equippedPets[1]
			else "",
		equippedPets = equippedPets or {},
		extraPetSlot = extraPetSlot,
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
		wheelLastSpinAt = wheelLastSpinAt or 0,
		wheelSpinCredits = wheelSpinCredits or 0,
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
	PetService.initializePlayer(
		player,
		data.pets,
		data.petNames,
		data.equippedPets,
		data.extraPetSlot
	)
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
	WheelService.initializePlayer(player, data.wheelLastSpinAt, data.wheelSpinCredits)
	player:SetAttribute("TutorialDone", data.tutorialDone)
	grantOfflineGrowth(player, data)

	-- Tutorial graduates go straight home to the Main Island; brand-new
	-- players stay at the world spawn until the tutorial is done.
	if data.tutorialDone then
		HubService.welcome(player)
	end
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
	WheelService.removePlayer(player)
	HubService.removePlayer(player)

	if snapshot ~= nil then
		task.spawn(function()
			DataService.saveAsync(player, snapshot)
			DataService.forgetPlayer(player)
		end)
	else
		DataService.forgetPlayer(player)
	end
end)

-- HatchEgg returns a result table; everything else returns a message.
local remoteHandlers: { [string]: (Player, ...any) -> (boolean, any) } = {
	AttemptRebirth = RebirthService.attemptRebirth,
	RequestTeleport = WorldService.attemptTeleport,
	HatchEgg = PetService.hatchEgg,
	EquipPet = PetService.equipPet,
	BuyPetSlot = PetService.buyPetSlot,
	RenamePet = PetService.renamePet,
	BuyPotion = EconomyService.buyPotion,
	BuyUpgrade = EconomyService.buyUpgrade,
	UseMysteryMachine = EconomyService.useMysteryMachine,
	ClaimQuest = QuestService.claimQuest,
	ClaimStreak = QuestService.claimStreak,
	ClaimGroupChest = QuestService.claimGroupChest,
	SpinWheel = WheelService.spin,
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
	local firstTime = player:GetAttribute("TutorialDone") ~= true
	player:SetAttribute("TutorialDone", true)

	-- Finishing the tutorial is the moment the game hands you the Main
	-- Island, winged landing and all.
	if firstTime then
		HubService.sendToHub(player)
	end
end)

local resetCharacter = Remotes.get("ResetCharacter") :: RemoteEvent
resetCharacter.OnServerEvent:Connect(function(player)
	-- The settings window's reset button; a fresh character respawns at
	-- the player's checkpoint like any other death.
	player:LoadCharacter()
end)

DataService.start(snapshotPlayer)
ShopService.start({
	grantMaxSize = SizeService.grantMaxSize,
	grantRobuxEggPet = PetService.grantRobuxEggPet,
	grantLimitedPet = PetService.grantLimitedPet,
	awardCoins = EconomyService.awardCoins,
	addPermanentGrowth = SizeService.addPermanentGrowth,
	grantWheelSpin = WheelService.grantSpinCredit,
})
QuestService.start({
	awardCoins = EconomyService.awardCoins,
})
WheelService.start({
	awardCoins = EconomyService.awardCoins,
	grantMaxSize = SizeService.grantMaxSize,
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
SceneryService.start()
-- After the map: MapGenerator disables every foreign SpawnLocation
-- while it builds, and the hub must never be caught by that sweep.
HubService.start()
