--[[
	Checkpoints: touch one and it becomes your respawn point, pays coins
	the first time, and persists across sessions. Respawning places you
	at your latest checkpoint instead of the world-1 spawn, which is what
	makes the longer obby sections fair.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent
local EconomyService = require(Server.EconomyService)

local Shared = ReplicatedStorage.Shared
local WorldLayout = require(Shared.WorldLayout)

local CHECKPOINT_TAG = "Checkpoint"

type CheckpointRecord = {
	-- Highest checkpoint index paid out per world, so rewards are
	-- once-ever even across rejoins.
	claimed: { [string]: number },
	respawnWorld: number,
	respawnIndex: number,
}

local recordByPlayer: { [Player]: CheckpointRecord } = {}

local CheckpointService = {}

local function checkpointPosition(worldIndex: number, checkpointIndex: number): Vector3?
	for _, checkpoint in ipairs(CollectionService:GetTagged(CHECKPOINT_TAG)) do
		if
			checkpoint:IsA("BasePart")
			and checkpoint:GetAttribute("WorldIndex") == worldIndex
			and checkpoint:GetAttribute("CheckpointIndex") == checkpointIndex
		then
			return checkpoint.Position + Vector3.new(0, 4, 0)
		end
	end

	return nil
end

local function onCheckpointTouched(checkpoint: BasePart, hit: BasePart)
	local player = Players:GetPlayerFromCharacter(hit.Parent)
	if player == nil then
		return
	end

	local record = recordByPlayer[player]
	local worldIndex = checkpoint:GetAttribute("WorldIndex")
	local checkpointIndex = checkpoint:GetAttribute("CheckpointIndex")
	if record == nil or typeof(worldIndex) ~= "number" or typeof(checkpointIndex) ~= "number" then
		return
	end

	local isForward = worldIndex > record.respawnWorld
		or (worldIndex == record.respawnWorld and checkpointIndex > record.respawnIndex)
	if isForward then
		record.respawnWorld = worldIndex
		record.respawnIndex = checkpointIndex
		player:SetAttribute("CheckpointIndex", checkpointIndex)
	end

	-- JSON object keys must be strings, so world indexes are stored
	-- stringified.
	local worldKey = tostring(worldIndex)
	local claimed = record.claimed[worldKey] or 0
	if checkpointIndex > claimed then
		record.claimed[worldKey] = checkpointIndex
		EconomyService.awardCheckpoint(player, worldIndex)
	end
end

function CheckpointService.initializePlayer(
	player: Player,
	claimed: { [string]: number },
	respawnWorld: number,
	respawnIndex: number
)
	recordByPlayer[player] = {
		claimed = claimed,
		respawnWorld = math.clamp(respawnWorld, 1, WorldLayout.worldCount()),
		respawnIndex = respawnIndex,
	}

	player.CharacterAdded:Connect(function(character)
		local record = recordByPlayer[player]
		if record == nil then
			return
		end

		-- Deferred so the engine finishes placing the character at the
		-- default spawn before we move it.
		task.defer(function()
			local position = checkpointPosition(record.respawnWorld, record.respawnIndex)
			if position == nil and record.respawnWorld > 1 then
				position = WorldLayout.spawnPositionForWorld(record.respawnWorld)
			end

			if position ~= nil and character.Parent ~= nil then
				character:PivotTo(CFrame.new(position))
			end
		end)
	end)
end

function CheckpointService.snapshot(player: Player): ({ [string]: number }?, number?, number?)
	local record = recordByPlayer[player]
	if record == nil then
		return nil, nil, nil
	end

	return record.claimed, record.respawnWorld, record.respawnIndex
end

function CheckpointService.removePlayer(player: Player)
	recordByPlayer[player] = nil
end

function CheckpointService.start()
	local function watch(checkpoint: Instance)
		if checkpoint:IsA("BasePart") then
			checkpoint.Touched:Connect(function(hit)
				onCheckpointTouched(checkpoint, hit)
			end)
		end
	end

	for _, checkpoint in ipairs(CollectionService:GetTagged(CHECKPOINT_TAG)) do
		watch(checkpoint)
	end

	CollectionService:GetInstanceAddedSignal(CHECKPOINT_TAG):Connect(watch)
end

return CheckpointService
