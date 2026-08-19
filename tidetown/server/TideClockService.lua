--[[
	The authoritative server-wide tide clock. One loop walks the
	Low -> Rising -> High -> Falling cycle forever with durations from
	TidetownConfig.tide; everything else in the game asks this service
	what the tide is doing instead of keeping its own clock, so no two
	systems can ever disagree about the phase.

	On every transition the service stamps attributes on the
	Workspace.Tidetown folder (late joiners and tools can read them),
	snaps the two water parts to the new target level (clients tween
	the visual from wherever replication put them), broadcasts the
	TideChanged remote, and runs registered phase callbacks in their
	own tasks so a slow listener can never stall the clock.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local TidetownShared = ReplicatedStorage.TidetownShared
local TidePhase = require(TidetownShared.TidePhase)
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

local MAP_FOLDER_NAME = "Tidetown"
local WATER_PART_NAMES = { "Water", "FloodWater" }
local PHASE_ORDER = { TidePhase.Low, TidePhase.Rising, TidePhase.High, TidePhase.Falling }

local TideClockService = {}

local mapFolder: Instance? = nil
local tideChangedRemote: RemoteEvent? = nil
local phaseCallbacks: { (string) -> () } = {}

local phaseIndex = 1
local phaseDurationSeconds = TidetownConfig.tide.lowSeconds
local phaseStartedClock = 0
local phaseEndsAtUnix = 0
local cycle = 1
local started = false

local function durationFor(phase: string): number
	local tide = TidetownConfig.tide

	return if phase == TidePhase.Low
		then tide.lowSeconds
		elseif phase == TidePhase.Rising then tide.risingSeconds
		elseif phase == TidePhase.High then tide.highSeconds
		else tide.fallingSeconds
end

-- The water level each phase is heading toward: transitions aim at the
-- level their destination phase holds steady.
local function targetWaterFor(phase: string): number
	local tide = TidetownConfig.tide

	return if phase == TidePhase.Low or phase == TidePhase.Falling
		then tide.lowWaterY
		else tide.highWaterY
end

local function currentPayload(): { [string]: any }
	local phase = PHASE_ORDER[phaseIndex]

	return {
		phase = phase,
		endsAt = phaseEndsAtUnix,
		waterY = targetWaterFor(phase),
		seconds = phaseDurationSeconds,
	}
end

--[[
	Snaps both water parts so their top face sits at the level. The
	server holds the authoritative position; clients animate toward it
	locally, so an instant snap here never looks like a jump cut.
]]
local function repositionWater(level: number)
	if mapFolder == nil then
		return
	end

	for _, partName in ipairs(WATER_PART_NAMES) do
		local part = mapFolder:FindFirstChild(partName)
		if part ~= nil and part:IsA("BasePart") then
			local position = part.Position
			part.CFrame = CFrame.new(position.X, level - part.Size.Y / 2, position.Z)
		end
	end
end

local function applyPhase(newIndex: number)
	phaseIndex = newIndex

	local phase = PHASE_ORDER[phaseIndex]
	phaseDurationSeconds = durationFor(phase)
	phaseStartedClock = os.clock()
	phaseEndsAtUnix = os.time() + phaseDurationSeconds

	local waterTarget = targetWaterFor(phase)

	if mapFolder ~= nil then
		mapFolder:SetAttribute("Phase", phase)
		mapFolder:SetAttribute("PhaseEndsAt", phaseEndsAtUnix)
		mapFolder:SetAttribute("WaterY", waterTarget)
		mapFolder:SetAttribute("Cycle", cycle)
	end

	repositionWater(waterTarget)

	if tideChangedRemote ~= nil then
		tideChangedRemote:FireAllClients(currentPayload())
	end

	-- Spawned so one slow or throwing callback cannot delay the clock
	-- or the other listeners.
	for _, callback in ipairs(phaseCallbacks) do
		task.spawn(callback, phase)
	end
end

function TideClockService.currentPhase(): string
	return PHASE_ORDER[phaseIndex]
end

function TideClockService.phaseEndsAt(): number
	return phaseEndsAtUnix
end

function TideClockService.cycleNumber(): number
	return cycle
end

--[[
	The water level right now: steady during Low and High, linearly
	interpolated while the tide moves. Mounts float on this number, so
	it must be continuous rather than jumping with the parts.
]]
function TideClockService.waterLevelNow(): number
	local tide = TidetownConfig.tide
	local phase = PHASE_ORDER[phaseIndex]

	if phase == TidePhase.Low then
		return tide.lowWaterY
	end

	if phase == TidePhase.High then
		return tide.highWaterY
	end

	local fraction = math.clamp((os.clock() - phaseStartedClock) / phaseDurationSeconds, 0, 1)

	if phase == TidePhase.Rising then
		return tide.lowWaterY + (tide.highWaterY - tide.lowWaterY) * fraction
	end

	return tide.highWaterY + (tide.lowWaterY - tide.highWaterY) * fraction
end

--[[
	Registers a callback for every phase transition. Callbacks run via
	task.spawn and receive the new phase name. There is no way to
	unregister because services live for the whole server lifetime.
]]
function TideClockService.onPhaseChanged(callback: (phase: string) -> ())
	assert(typeof(callback) == "function", "onPhaseChanged expects a function")

	table.insert(phaseCallbacks, callback)
end

--[[
	Catches a late joiner up with the same payload the last broadcast
	carried, so their HUD and water are right without waiting for the
	next transition. Init calls this on PlayerAdded.
]]
function TideClockService.syncPlayer(player: Player)
	if tideChangedRemote == nil then
		return
	end

	tideChangedRemote:FireClient(player, currentPayload())
end

--[[
	Resolves the map folder and remote (both yield -- init calls start
	from a spawned task after MapBuilder.build()), stamps the initial
	Low phase, then runs the cycle loop in its own task forever.
]]
function TideClockService.start()
	if started then
		return
	end
	started = true

	mapFolder = Workspace:WaitForChild(MAP_FOLDER_NAME)

	local remote = TidetownRemotes.get("TideChanged")
	if remote:IsA("RemoteEvent") then
		tideChangedRemote = remote
	end

	applyPhase(1)

	task.spawn(function()
		while true do
			task.wait(phaseDurationSeconds)

			local nextIndex = phaseIndex % #PHASE_ORDER + 1
			if nextIndex == 1 then
				cycle += 1
			end

			applyPhase(nextIndex)
		end
	end)
end

return TideClockService
