--[[
	Server entry point. All cross-service wiring lives here -- services
	never subscribe to player lifecycle events themselves -- so the order
	of operations on join and leave is visible in one place and save-on-
	leave always runs before state cleanup.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script
local DataService = require(Server.DataService)
local GateService = require(Server.GateService)
local MapGenerator = require(Server.MapGenerator)
local ObstacleService = require(Server.ObstacleService)
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
	if sizeSnapshot == nil or reachedWorld == nil then
		return nil
	end

	return {
		maxSize = sizeSnapshot.maxSize,
		rebirths = sizeSnapshot.rebirths,
		reachedWorld = reachedWorld,
	}
end

local function onPlayerAdded(player: Player)
	task.spawn(ShopService.prefetchAsync, player)

	local data = DataService.loadAsync(player)
	SizeService.initializePlayer(player, data)
	WorldService.initializePlayer(player, data.reachedWorld)
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

local requestInstantShrink = Remotes.get("RequestInstantShrink") :: RemoteEvent
requestInstantShrink.OnServerEvent:Connect(function(player)
	-- Ownership is checked server-side; the client button is a request.
	if ShopService.playerOwnsPass(player, "InstantShrink") then
		SizeService.forceShrink(player)
	end
end)

DataService.start(snapshotPlayer)
ShopService.start({
	grantMaxSize = SizeService.grantMaxSize,
})
SizeService.start()
GateService.start()
WorldService.start()
ObstacleService.start()
MapGenerator.generate()
