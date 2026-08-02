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
local GateService = require(Server.GateService)
local MapGenerator = require(Server.MapGenerator)
local ObstacleService = require(Server.ObstacleService)
local PetService = require(Server.PetService)
local RebirthService = require(Server.RebirthService)
local ShopService = require(Server.ShopService)
local SizeService = require(Server.SizeService)
local WorldService = require(Server.WorldService)

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)

Remotes.createAll()

-- Progress is split across services; saving needs it reassembled into
-- one record.
local function snapshotPlayer(player: Player): DataService.PlayerData?
	local sizeSnapshot = SizeService.snapshot(player)
	local reachedWorld = WorldService.reachedWorld(player)
	local coins, upgrades = EconomyService.snapshot(player)
	local pets, equippedPet = PetService.snapshot(player)
	local checkpointsClaimed, respawnWorld, respawnIndex = CheckpointService.snapshot(player)

	if sizeSnapshot == nil or reachedWorld == nil or coins == nil or pets == nil then
		return nil
	end

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
	}
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
	player:SetAttribute("TutorialDone", data.tutorialDone)
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

	if snapshot ~= nil then
		task.spawn(function()
			DataService.saveAsync(player, snapshot)
			DataService.forgetPlayer(player)
		end)
	else
		DataService.forgetPlayer(player)
	end
end)

local attemptRebirth = Remotes.get("AttemptRebirth") :: RemoteFunction
attemptRebirth.OnServerInvoke = RebirthService.attemptRebirth

local requestTeleport = Remotes.get("RequestTeleport") :: RemoteFunction
requestTeleport.OnServerInvoke = WorldService.attemptTeleport

local hatchEgg = Remotes.get("HatchEgg") :: RemoteFunction
hatchEgg.OnServerInvoke = PetService.hatchEgg

local equipPet = Remotes.get("EquipPet") :: RemoteFunction
equipPet.OnServerInvoke = PetService.equipPet

local buyPotion = Remotes.get("BuyPotion") :: RemoteFunction
buyPotion.OnServerInvoke = EconomyService.buyPotion

local buyUpgrade = Remotes.get("BuyUpgrade") :: RemoteFunction
buyUpgrade.OnServerInvoke = EconomyService.buyUpgrade

local useMysteryMachine = Remotes.get("UseMysteryMachine") :: RemoteFunction
useMysteryMachine.OnServerInvoke = EconomyService.useMysteryMachine

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
})
SizeService.start()
GateService.start()
WorldService.start()
ObstacleService.start()
EconomyService.start()
CheckpointService.start()
MapGenerator.generate()
