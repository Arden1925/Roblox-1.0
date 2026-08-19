--[[
	Owns each player's boardwalk reef plot: the assigned pad, the
	creatures placed in its tank slots, and the capped Shell pool the
	tank earns. Placement, collection, and slot unlocks all funnel
	through here, so the pool a collect pays out is always the pool the
	accrual loops actually filled.

	Accrual runs on two clocks: a live loop ticks the active rate while
	the player is online, and initializePlayer settles the offline gap
	at a deliberately reduced fraction, capped in hours -- absence pays
	something, presence always pays more. Tank models are anchored and
	steered by ONE Heartbeat for the whole service: each creature
	orbits its pad slowly, which reads as swimming with zero physics.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TidetownShared = ReplicatedStorage.TidetownShared
local CreatureCatalog = require(TidetownShared.CreatureCatalog)
local CreatureModels = require(TidetownShared.CreatureModels)
local TideLayout = require(TidetownShared.TideLayout)
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

local TANK_HEIGHT_STUDS = 1.6
local RING_RADIUS_STUDS = 2.2
local RING_HEIGHT_STUDS = 1.8
local SPIN_RADIANS_PER_SECOND = 0.4
local BOB_STUDS = 0.25
local BOB_RADIANS_PER_SECOND = 1.6
local ACCRUAL_INTERVAL_SECONDS = 6
local DEFAULT_SIGN_TEXT = "Open Reef"

type CreatureRecord = {
	uid: string,
	species: string,
	nickname: string,
	caughtAt: number,
}

type Dependencies = {
	creatureByUid: (Player, string) -> CreatureRecord?,
	isInDefenseTeam: (Player, string) -> boolean,
	awardShells: (Player, number) -> (),
	reportBounty: (Player, string, number) -> (),
	pushToast: (Player, string, string?) -> (),
	plotPad: (number) -> BasePart?,
	plotBarrier: (number) -> BasePart?,
}

type TankRecord = {
	model: Model,
	center: Vector3,
	baseAngle: number,
}

type PlayerState = {
	slotsUnlocked: number,
	placed: { [string]: string },
	pool: number,
	plotIndex: number,
}

local ReefService = {}

local statesByPlayer: { [Player]: PlayerState } = {}
local tanksByPlayer: { [Player]: { [string]: TankRecord } } = {}
local dependencies: Dependencies? = nil
local syncStateRemote: RemoteEvent? = nil
local spinClock = 0

--[[
	Picks the lowest pad no online player holds. When every pad is
	claimed the newcomer shares pad one -- servers hold fewer players
	than pads in practice, so v1 keeps assignment this simple.
]]
local function assignPlotIndex(): number
	local used: { [number]: boolean } = {}
	for _, state in pairs(statesByPlayer) do
		used[state.plotIndex] = true
	end

	for plotIndex = 1, TidetownConfig.layout.reefPlotCount do
		if used[plotIndex] ~= true then
			return plotIndex
		end
	end

	return 1
end

local function padTopFor(plotIndex: number): Vector3
	local currentDependencies = dependencies
	local pad = if currentDependencies ~= nil then currentDependencies.plotPad(plotIndex) else nil
	if pad ~= nil then
		return pad.Position + Vector3.new(0, pad.Size.Y / 2, 0)
	end

	-- The shared layout knows the pad-top center even when the map
	-- part is missing (Studio tests without MapBuilder).
	return TideLayout.plotPosition(plotIndex)
end

local function signLabelFor(plotIndex: number): TextLabel?
	local currentDependencies = dependencies
	if currentDependencies == nil then
		return nil
	end

	local pad = currentDependencies.plotPad(plotIndex)
	local plotFolder = if pad ~= nil then pad.Parent else nil
	local sign = if plotFolder ~= nil then plotFolder:FindFirstChild("Sign") else nil
	local surfaceGui = if sign ~= nil then sign:FindFirstChildOfClass("SurfaceGui") else nil

	return if surfaceGui ~= nil then surfaceGui:FindFirstChildOfClass("TextLabel") else nil
end

local function setSignText(plotIndex: number, text: string)
	local label = signLabelFor(plotIndex)
	if label ~= nil then
		label.Text = text
	end
end

--[[
	Sums the per-minute Shell rate of every placed creature by rarity.
	Uids that no longer resolve to an owned creature simply earn
	nothing rather than erroring a whole plot.
]]
local function ratePerMinuteFor(player: Player, state: PlayerState): number
	local currentDependencies = dependencies
	if currentDependencies == nil then
		return 0
	end

	local rate = 0
	for _, uid in pairs(state.placed) do
		local record = currentDependencies.creatureByUid(player, uid)
		local species = if record ~= nil then CreatureCatalog.speciesFor(record.species) else nil
		if species ~= nil then
			local perMinute = TidetownConfig.reef.shellsPerMinuteByRarity[species.rarity]
			if perMinute ~= nil then
				rate += perMinute
			end
		end
	end

	return rate
end

local function nextSlotCostFor(state: PlayerState): number?
	if state.slotsUnlocked >= TidetownConfig.reef.maxSlots then
		return nil
	end

	local costIndex = state.slotsUnlocked - TidetownConfig.reef.startingSlots + 1

	return TidetownConfig.reef.slotUpgradeCosts[costIndex]
end

local function destroyTank(player: Player, slotKey: string)
	local tanks = tanksByPlayer[player]
	if tanks == nil then
		return
	end

	local tank = tanks[slotKey]
	if tank == nil then
		return
	end

	tank.model:Destroy()
	tanks[slotKey] = nil
end

local function clearTanks(player: Player)
	local tanks = tanksByPlayer[player]
	if tanks == nil then
		return
	end

	for _, tank in pairs(tanks) do
		tank.model:Destroy()
	end

	tanksByPlayer[player] = nil
end

--[[
	Builds the anchored tank model for one placed creature and parks it
	on its slot's spot in the ring above the pad; the service Heartbeat
	takes over its motion from there. Tolerates a uid that no longer
	resolves -- the slot just shows nothing.
]]
local function spawnTank(player: Player, state: PlayerState, slotKey: string, uid: string)
	local currentDependencies = dependencies
	local tanks = tanksByPlayer[player]
	if currentDependencies == nil or tanks == nil then
		return
	end

	local slotNumber = tonumber(slotKey)
	if slotNumber == nil then
		return
	end

	local record = currentDependencies.creatureByUid(player, uid)
	if record == nil then
		return
	end

	destroyTank(player, slotKey)

	local model = CreatureModels.build(record.species, TANK_HEIGHT_STUDS)
	model.Name = string.format("Tank_%d_%s", player.UserId, slotKey)

	local baseAngle = (slotNumber - 1) / TidetownConfig.reef.maxSlots * math.pi * 2
	local center = padTopFor(state.plotIndex) + Vector3.new(0, RING_HEIGHT_STUDS, 0)
	local startOffset = Vector3.new(
		math.cos(baseAngle) * RING_RADIUS_STUDS,
		0,
		math.sin(baseAngle) * RING_RADIUS_STUDS
	)
	model:PivotTo(CFrame.new(center + startOffset))

	local pad = currentDependencies.plotPad(state.plotIndex)
	local plotFolder = if pad ~= nil then pad.Parent else nil
	model.Parent = if plotFolder ~= nil then plotFolder else Workspace

	tanks[slotKey] = {
		model = model,
		center = center,
		baseAngle = baseAngle,
	}
end

-- The one Heartbeat for every tank on every plot: a slow orbit around
-- the pad center plus a sine bob, facing the direction of travel.
local function stepTanks(deltaSeconds: number)
	spinClock += deltaSeconds

	for _, tanks in pairs(tanksByPlayer) do
		for _, tank in pairs(tanks) do
			local angle = tank.baseAngle + spinClock * SPIN_RADIANS_PER_SECOND
			local bob = math.sin(spinClock * BOB_RADIANS_PER_SECOND + tank.baseAngle) * BOB_STUDS
			local position = tank.center
				+ Vector3.new(
					math.cos(angle) * RING_RADIUS_STUDS,
					bob,
					math.sin(angle) * RING_RADIUS_STUDS
				)
			local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
			tank.model:PivotTo(CFrame.lookAt(position, position + tangent))
		end
	end
end

--[[
	Settles the Shells the reef earned while the player was away, at
	the reduced offline fraction and capped in hours so a long absence
	pays a bounded, predictable amount.
]]
local function runOfflineAccrual(player: Player, state: PlayerState, lastAccrualAt: number)
	if lastAccrualAt <= 0 then
		return
	end

	local reef = TidetownConfig.reef
	local cappedSeconds = math.clamp(os.time() - lastAccrualAt, 0, reef.offlineCapHours * 3600)
	local earned = (cappedSeconds / 60) * ratePerMinuteFor(player, state) * reef.offlineRateFraction
	if earned <= 0 then
		return
	end

	state.pool = math.min(state.pool + earned, reef.poolCap)

	local currentDependencies = dependencies
	if earned >= 1 and currentDependencies ~= nil then
		currentDependencies.pushToast(
			player,
			string.format("Your reef earned %d Shells while you were away!", math.floor(earned)),
			"good"
		)
	end
end

--[[
	Sends the player's full reef view to their client. Called after
	every mutation; the pool is floored because fractions are an
	accrual bookkeeping detail, never a promise to the player.
]]
function ReefService.pushState(player: Player)
	local state = statesByPlayer[player]
	if state == nil or syncStateRemote == nil then
		return
	end

	syncStateRemote:FireClient(player, "reef", {
		slotsUnlocked = state.slotsUnlocked,
		placed = table.clone(state.placed),
		pool = math.floor(state.pool),
		nextSlotCost = nextSlotCostFor(state),
		plotIndex = state.plotIndex,
	})
end

function ReefService.initializePlayer(
	player: Player,
	slotsUnlocked: number,
	placed: { [string]: string },
	pool: number,
	lastAccrualAt: number
)
	-- A stale rejoin race could leave old tanks behind; clearing first
	-- makes initialization safe to run twice.
	clearTanks(player)

	local reef = TidetownConfig.reef
	local state: PlayerState = {
		slotsUnlocked = math.clamp(slotsUnlocked, reef.startingSlots, reef.maxSlots),
		placed = {},
		pool = math.clamp(pool, 0, reef.poolCap),
		plotIndex = assignPlotIndex(),
	}

	-- Copied entry-wise (instead of aliasing the loaded PlayerData)
	-- and filtered so a corrupted save cannot strand ghost tanks in
	-- slots that no longer parse or exceed the unlocked range.
	for slotKey, uid in pairs(placed) do
		local slotNumber = tonumber(slotKey)
		if slotNumber ~= nil and slotNumber >= 1 and slotNumber <= state.slotsUnlocked then
			state.placed[slotKey] = uid
		end
	end

	statesByPlayer[player] = state
	tanksByPlayer[player] = {}

	setSignText(state.plotIndex, string.format("%s's Reef", player.DisplayName))
	for slotKey, uid in pairs(state.placed) do
		spawnTank(player, state, slotKey, uid)
	end

	runOfflineAccrual(player, state, lastAccrualAt)
	ReefService.pushState(player)
end

function ReefService.snapshot(player: Player): (number?, { [string]: string }?, number?, number?)
	local state = statesByPlayer[player]
	if state == nil then
		return nil, nil, nil, nil
	end

	-- The accrual stamp is "now" because the pool being saved already
	-- contains everything earned up to this moment; the copy keeps the
	-- snapshot from aliasing live state a later place could mutate.
	return state.slotsUnlocked, table.clone(state.placed), state.pool, os.time()
end

function ReefService.removePlayer(player: Player)
	local state = statesByPlayer[player]
	clearTanks(player)
	statesByPlayer[player] = nil

	if state == nil then
		return
	end

	-- Only reclaim the sign when no remaining player shares the pad
	-- (possible once assignment doubles up).
	for _, otherState in pairs(statesByPlayer) do
		if otherState.plotIndex == state.plotIndex then
			return
		end
	end

	setSignText(state.plotIndex, DEFAULT_SIGN_TEXT)
end

function ReefService.placeCreature(player: Player, slotIndex: any, uid: any): (boolean, any)
	local state = statesByPlayer[player]
	local currentDependencies = dependencies
	if state == nil or currentDependencies == nil then
		return false, "Not ready"
	end

	if typeof(slotIndex) ~= "number" or slotIndex % 1 ~= 0 then
		return false, "No such slot"
	end

	if slotIndex < 1 or slotIndex > state.slotsUnlocked then
		return false, "That slot is locked"
	end

	if typeof(uid) ~= "string" then
		return false, "No such creature"
	end

	if currentDependencies.creatureByUid(player, uid) == nil then
		return false, "You do not own that creature"
	end

	if ReefService.isPlaced(player, uid) then
		return false, "That creature is already in a tank"
	end

	if currentDependencies.isInDefenseTeam(player, uid) then
		return false, "That creature is on your defense team"
	end

	local slotKey = tostring(slotIndex)
	if state.placed[slotKey] ~= nil then
		return false, "That slot is taken"
	end

	state.placed[slotKey] = uid
	spawnTank(player, state, slotKey, uid)
	ReefService.pushState(player)

	return true, { slot = slotIndex, uid = uid }
end

function ReefService.clearSlot(player: Player, slotIndex: any): (boolean, any)
	local state = statesByPlayer[player]
	if state == nil then
		return false, "Not ready"
	end

	if typeof(slotIndex) ~= "number" or slotIndex % 1 ~= 0 then
		return false, "No such slot"
	end

	local slotKey = tostring(slotIndex)
	if state.placed[slotKey] == nil then
		return false, "That slot is empty"
	end

	state.placed[slotKey] = nil
	destroyTank(player, slotKey)
	ReefService.pushState(player)

	return true, { slot = slotIndex }
end

function ReefService.collect(player: Player): (boolean, any)
	local state = statesByPlayer[player]
	local currentDependencies = dependencies
	if state == nil or currentDependencies == nil then
		return false, "Not ready"
	end

	local amount = math.floor(state.pool)
	if amount < 1 then
		return false, "Nothing to collect yet"
	end

	-- Only the floored whole leaves the pool; the fractional remainder
	-- keeps accruing toward the next Shell instead of vanishing.
	state.pool -= amount
	currentDependencies.awardShells(player, amount)
	currentDependencies.reportBounty(player, "collectReef", amount)
	ReefService.pushState(player)

	return true, amount
end

--[[
	Grants the next tank slot. ShopService calls this AFTER it has
	already spent the Shells, so there is no cost check here -- pricing
	lives with the purchase, capacity lives with the reef.
]]
function ReefService.unlockNextSlot(player: Player): (boolean, string)
	local state = statesByPlayer[player]
	if state == nil then
		return false, "Not ready"
	end

	if state.slotsUnlocked >= TidetownConfig.reef.maxSlots then
		return false, "Reef fully expanded"
	end

	state.slotsUnlocked += 1
	ReefService.pushState(player)

	return true, "Reef slot unlocked"
end

function ReefService.nextSlotCost(player: Player): number?
	local state = statesByPlayer[player]
	if state == nil then
		return nil
	end

	return nextSlotCostFor(state)
end

function ReefService.isPlaced(player: Player, uid: string): boolean
	local state = statesByPlayer[player]
	if state == nil then
		return false
	end

	for _, placedUid in pairs(state.placed) do
		if placedUid == uid then
			return true
		end
	end

	return false
end

function ReefService.plotIndexFor(player: Player): number?
	local state = statesByPlayer[player]
	if state == nil then
		return nil
	end

	return state.plotIndex
end

-- The live accrual tick: the full active rate, applied a few seconds
-- at a time so a fresh placement starts paying almost immediately.
local function stepLiveAccrual()
	local poolCap = TidetownConfig.reef.poolCap

	for player, state in pairs(statesByPlayer) do
		if state.pool < poolCap then
			local rate = ratePerMinuteFor(player, state)
			if rate > 0 then
				local flooredBefore = math.floor(state.pool)
				local earned = rate * ACCRUAL_INTERVAL_SECONDS / 60
				state.pool = math.min(state.pool + earned, poolCap)

				-- Sync only when the visible whole-Shell count moves,
				-- so slow tanks do not spam the client.
				if math.floor(state.pool) > flooredBefore then
					ReefService.pushState(player)
				end
			end
		end
	end
end

--[[
	Wires dependencies, fetches the SyncState remote (yields, which is
	why init calls start from a spawned task), then starts the tank
	Heartbeat and the live accrual loop.
]]
function ReefService.start(dependencyTable: Dependencies)
	dependencies = dependencyTable
	syncStateRemote = TidetownRemotes.get("SyncState") :: RemoteEvent

	RunService.Heartbeat:Connect(stepTanks)

	task.spawn(function()
		while true do
			task.wait(ACCRUAL_INTERVAL_SECONDS)
			stepLiveAccrual()
		end
	end)
end

return ReefService
