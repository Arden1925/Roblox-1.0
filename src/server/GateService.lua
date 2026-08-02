--[[
	Opens and closes Size Gates and Squeeze Cracks. Both are ordinary
	anchored parts: a gate opens (turns ghostly and walkable) when a
	qualifying player is near, and re-solidifies shortly after they leave.

	Player sizes are read from the attributes SizeService publishes, so
	this module needs no direct dependency on the size system.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local SizeFormula = require(Shared.SizeFormula)

local SIZE_GATE_TAG = "SizeGate"
local SQUEEZE_CRACK_TAG = "SqueezeCrack"

local UPDATE_INTERVAL_SECONDS = 0.1
local OPEN_TRANSPARENCY = 0.75

type BarrierState = {
	closedTransparency: number,
	openUntil: number,
}

local barrierStates: { [BasePart]: BarrierState } = {}

local GateService = {}

local function playerQualifies(barrier: BasePart, player: Player): boolean
	local currentSize = player:GetAttribute("CurrentSize")
	if typeof(currentSize) ~= "number" then
		return false
	end

	if CollectionService:HasTag(barrier, SIZE_GATE_TAG) then
		local requiredSize = barrier:GetAttribute("RequiredSize")
		return typeof(requiredSize) == "number"
			and SizeFormula.canPassGate(currentSize, requiredSize)
	end

	local maxAllowedSize = barrier:GetAttribute("MaxAllowedSize")
	return typeof(maxAllowedSize) == "number"
		and SizeFormula.canFitCrack(currentSize, maxAllowedSize)
end

local function anyQualifyingPlayerNear(barrier: BasePart): boolean
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character ~= nil then
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			if
				rootPart ~= nil
				and (rootPart.Position - barrier.Position).Magnitude <= GameConfig.gates.openRange
				and playerQualifies(barrier, player)
			then
				return true
			end
		end
	end

	return false
end

local function updateBarrier(barrier: BasePart, now: number)
	local state = barrierStates[barrier]
	if state == nil then
		state = {
			closedTransparency = barrier.Transparency,
			openUntil = 0,
		}
		barrierStates[barrier] = state
	end

	if anyQualifyingPlayerNear(barrier) then
		state.openUntil = now + GameConfig.gates.closeDelaySeconds
	end

	local shouldBeOpen = now < state.openUntil
	barrier.CanCollide = not shouldBeOpen
	barrier.Transparency = if shouldBeOpen then OPEN_TRANSPARENCY else state.closedTransparency
end

function GateService.start()
	local sinceUpdate = 0

	RunService.Heartbeat:Connect(function(deltaSeconds)
		sinceUpdate += deltaSeconds
		if sinceUpdate < UPDATE_INTERVAL_SECONDS then
			return
		end
		sinceUpdate = 0

		local now = os.clock()
		for _, tag in ipairs({ SIZE_GATE_TAG, SQUEEZE_CRACK_TAG }) do
			for _, barrier in ipairs(CollectionService:GetTagged(tag)) do
				if barrier:IsA("BasePart") and barrier:IsDescendantOf(workspace) then
					updateBarrier(barrier, now)
				end
			end
		end
	end)

	CollectionService:GetInstanceRemovedSignal(SIZE_GATE_TAG):Connect(function(barrier)
		barrierStates[barrier] = nil
	end)

	CollectionService:GetInstanceRemovedSignal(SQUEEZE_CRACK_TAG):Connect(function(barrier)
		barrierStates[barrier] = nil
	end)
end

return GateService
