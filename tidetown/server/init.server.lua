--[[
	Tidetown server entry point. All cross-service wiring lives here --
	services never subscribe to player lifecycle events themselves and
	never require each other -- so the order of operations on join and
	leave is visible in one place and save-on-leave always runs before
	state cleanup.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script
local BountyService = require(Server.BountyService)
local CatchService = require(Server.CatchService)
local CreatureService = require(Server.CreatureService)
local CurrencyService = require(Server.CurrencyService)
local EggService = require(Server.EggService)
local MapBuilder = require(Server.MapBuilder)
local MountService = require(Server.MountService)
local ReefService = require(Server.ReefService)
local SettingsService = require(Server.SettingsService)
local ShopService = require(Server.ShopService)
local SurgeService = require(Server.SurgeService)
local TideClockService = require(Server.TideClockService)
local TidepediaService = require(Server.TidepediaService)
local TidetownData = require(Server.TidetownData)

local TidetownShared = ReplicatedStorage.TidetownShared
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

TidetownRemotes.createAll()

local toastRemote = TidetownRemotes.get("Toast") :: RemoteEvent
local surgeEventRemote = TidetownRemotes.get("SurgeEvent") :: RemoteEvent

local function pushToast(player: Player, message: string, style: string?)
	toastRemote:FireClient(player, message, style)
end

local function fireSurgeEvent(player: Player, kind: string, payload: any)
	surgeEventRemote:FireClient(player, kind, payload)
end

-- Buried eggs found while casting map the zone to its egg type; a zone
-- without an egg (never the case today) simply finds nothing.
local function grantFoundEgg(player: Player, zoneKey: string): boolean
	for _, eggType in ipairs(TidetownConfig.eggs.types) do
		if eggType.zone == zoneKey then
			return EggService.grantEgg(player, eggType.key)
		end
	end

	return false
end

local function isInDefenseTeam(player: Player, creatureUid: string): boolean
	for _, member in ipairs(CreatureService.defenseTeamStats(player)) do
		if member.uid == creatureUid then
			return true
		end
	end

	return false
end

-- Progress is split across services; saving needs it reassembled into
-- one record.
local function snapshotPlayer(player: Player): TidetownData.PlayerData?
	local shells, stormglass = CurrencyService.snapshot(player)
	local creatures, companionUid, defenseTeam, nextUid = CreatureService.snapshot(player)
	local eggs = EggService.snapshot(player)
	local slotsUnlocked, placed, pool, lastAccrualAt = ReefService.snapshot(player)
	local tidepedia = TidepediaService.snapshot(player)
	local castsSinceRare, castsSinceEpic = CatchService.snapshot(player)
	local bountyDate, bounties, streakCount, streakLastDate, claimedMilestones =
		BountyService.snapshot(player)
	local mountsOwned = MountService.snapshot(player)
	local upgrades, decorationsOwned, trailsOwned, equippedTrail = ShopService.snapshot(player)
	local settings = SettingsService.snapshot(player)

	if shells == nil or creatures == nil or tidepedia == nil then
		return nil
	end

	return {
		shells = shells,
		stormglass = stormglass or 0,
		creatures = creatures,
		companionUid = companionUid or "",
		defenseTeam = defenseTeam or {},
		nextUid = nextUid or 1,
		reefSlotsUnlocked = slotsUnlocked or TidetownConfig.reef.startingSlots,
		reefPlaced = placed or {},
		reefPool = pool or 0,
		reefLastAccrualAt = lastAccrualAt or os.time(),
		eggs = eggs or {},
		tidepedia = tidepedia,
		castsSinceRare = castsSinceRare or 0,
		castsSinceEpic = castsSinceEpic or 0,
		bountyDate = bountyDate or "",
		bounties = bounties or {},
		streakCount = streakCount or 0,
		streakLastDate = streakLastDate or "",
		claimedStreakMilestones = claimedMilestones or {},
		mountsOwned = mountsOwned or {},
		upgrades = upgrades or {},
		decorationsOwned = decorationsOwned or {},
		trailsOwned = trailsOwned or {},
		equippedTrail = equippedTrail or "",
		settings = settings or {
			musicVolume = TidetownConfig.settings.defaults.musicVolume,
			sfxVolume = TidetownConfig.settings.defaults.sfxVolume,
			reducedMotion = TidetownConfig.settings.defaults.reducedMotion,
		},
		tutorialDone = player:GetAttribute("TutorialDone") == true,
		lastSeenAt = os.time(),
	}
end

local function onPlayerAdded(player: Player)
	local data = TidetownData.loadAsync(player)

	CurrencyService.initializePlayer(player, data.shells, data.stormglass)
	TidepediaService.initializePlayer(player, data.tidepedia)
	CreatureService.initializePlayer(
		player,
		data.creatures,
		data.companionUid,
		data.defenseTeam,
		data.nextUid
	)
	EggService.initializePlayer(player, data.eggs)
	ReefService.initializePlayer(
		player,
		data.reefSlotsUnlocked,
		data.reefPlaced,
		data.reefPool,
		data.reefLastAccrualAt
	)
	CatchService.initializePlayer(player, data.castsSinceRare, data.castsSinceEpic)
	BountyService.initializePlayer(
		player,
		data.bountyDate,
		data.bounties,
		data.streakCount,
		data.streakLastDate,
		data.claimedStreakMilestones
	)
	MountService.initializePlayer(player, data.mountsOwned)
	ShopService.initializePlayer(
		player,
		data.upgrades,
		data.decorationsOwned,
		data.trailsOwned,
		data.equippedTrail
	)
	SettingsService.initializePlayer(player, data.settings)
	player:SetAttribute("TutorialDone", data.tutorialDone)
	TideClockService.syncPlayer(player)

	-- The loading screen watches this flag; everything the client needs
	-- has been pushed by the initializers above.
	player:SetAttribute("TidetownReady", true)
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

	SurgeService.removePlayer(player)
	MountService.removePlayer(player)
	CatchService.removePlayer(player)
	EggService.removePlayer(player)
	ReefService.removePlayer(player)
	CreatureService.removePlayer(player)
	BountyService.removePlayer(player)
	ShopService.removePlayer(player)
	SettingsService.removePlayer(player)
	TidepediaService.removePlayer(player)
	CurrencyService.removePlayer(player)

	if snapshot ~= nil then
		task.spawn(function()
			TidetownData.saveAsync(player, snapshot)
			TidetownData.forgetPlayer(player)
		end)
	else
		TidetownData.forgetPlayer(player)
	end
end)

local remoteHandlers: { [string]: (Player, ...any) -> (boolean, any) } = {
	BeginCast = CatchService.beginCast,
	ResolveCast = CatchService.resolveCast,
	HatchEgg = EggService.hatchEgg,
	EquipCompanion = CreatureService.equipCompanion,
	SetDefenseTeam = CreatureService.setDefenseTeam,
	RenameCreature = CreatureService.renameCreature,
	PlaceReefCreature = ReefService.placeCreature,
	ClearReefSlot = ReefService.clearSlot,
	CollectReef = ReefService.collect,
	BuyShopItem = ShopService.buyItem,
	ClaimBounty = BountyService.claimBounty,
	RequestMount = MountService.requestMount,
	Dismount = MountService.dismount,
}

for remoteName, handler in pairs(remoteHandlers) do
	local remote = TidetownRemotes.get(remoteName) :: RemoteFunction
	remote.OnServerInvoke = handler
end

local deflectTap = TidetownRemotes.get("DeflectTap") :: RemoteEvent
deflectTap.OnServerEvent:Connect(function(player)
	SurgeService.handleDeflect(player)
end)

local markTutorialDone = TidetownRemotes.get("MarkTutorialDone") :: RemoteEvent
markTutorialDone.OnServerEvent:Connect(function(player)
	player:SetAttribute("TutorialDone", true)
end)

local setSetting = TidetownRemotes.get("SetSetting") :: RemoteEvent
setSetting.OnServerEvent:Connect(function(player, key, value)
	SettingsService.set(player, key, value)
end)

-- The map must exist before the clock stamps attributes on its folder,
-- and both before any service that looks the geometry up.
MapBuilder.build()
TideClockService.start()

TidetownData.start(snapshotPlayer)
TidepediaService.start({
	pushToast = pushToast,
})
CatchService.start({
	getPhase = TideClockService.currentPhase,
	awardShells = CurrencyService.awardShells,
	recordSpecies = TidepediaService.record,
	chargeEggs = EggService.chargeEggs,
	grantFoundEgg = grantFoundEgg,
	luckPercent = TidepediaService.luckPercent,
	zoneUnlocked = TidepediaService.zoneUnlocked,
	isMounted = MountService.isMounted,
	reportBounty = BountyService.report,
})
CreatureService.start({
	isReefPlaced = ReefService.isPlaced,
	grantEgg = EggService.grantEgg,
	pushToast = pushToast,
})
EggService.start({
	grantCreature = CreatureService.grantCreature,
	recordSpecies = TidepediaService.record,
	reportBounty = BountyService.report,
	pushToast = pushToast,
})
ReefService.start({
	creatureByUid = CreatureService.creatureByUid,
	isInDefenseTeam = isInDefenseTeam,
	awardShells = CurrencyService.awardShells,
	reportBounty = BountyService.report,
	pushToast = pushToast,
	plotPad = MapBuilder.plotPad,
	plotBarrier = MapBuilder.plotBarrier,
})
SurgeService.start({
	onPhaseChanged = TideClockService.onPhaseChanged,
	getPhase = TideClockService.currentPhase,
	defenseTeamStats = CreatureService.defenseTeamStats,
	plotIndexFor = ReefService.plotIndexFor,
	plotBarrier = MapBuilder.plotBarrier,
	upgradeLevel = ShopService.upgradeLevel,
	keeperRank = TidepediaService.keeperRank,
	awardShells = CurrencyService.awardShells,
	awardStormglass = CurrencyService.awardStormglass,
	reportBounty = BountyService.report,
	pushToast = pushToast,
	fireSurgeEvent = fireSurgeEvent,
})
MountService.start({
	getPhase = TideClockService.currentPhase,
	waterLevelNow = TideClockService.waterLevelNow,
	onPhaseChanged = TideClockService.onPhaseChanged,
	reportBounty = BountyService.report,
	pushToast = pushToast,
})
ShopService.start({
	spendShells = CurrencyService.spendShells,
	spendStormglass = CurrencyService.spendStormglass,
	awardShells = CurrencyService.awardShells,
	grantEgg = EggService.grantEgg,
	grantMount = MountService.grantMount,
	mountsOwnedList = function(player: Player): { string }
		return MountService.snapshot(player) or {}
	end,
	unlockNextSlot = ReefService.unlockNextSlot,
	nextSlotCost = ReefService.nextSlotCost,
	pushToast = pushToast,
})
BountyService.start({
	awardShells = CurrencyService.awardShells,
	awardStormglass = CurrencyService.awardStormglass,
	pushToast = pushToast,
})
