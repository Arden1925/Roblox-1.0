--[[
	Tracks which world each player is in and the furthest world they have
	ever reached, and validates portal teleports against that record.
	Reaching a world means physically crossing its boundary wall once;
	after that, portals can take you back and forth freely.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local WorldLayout = require(Shared.WorldLayout)

local UPDATE_INTERVAL_SECONDS = 0.5

local reachedByPlayer: { [Player]: number } = {}

local WorldService = {}

local function updatePlayerWorld(player: Player)
	local character = player.Character
	if character == nil then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil then
		return
	end

	local worldIndex = WorldLayout.worldIndexForPosition(rootPart.Position)
	if player:GetAttribute("CurrentWorld") ~= worldIndex then
		player:SetAttribute("CurrentWorld", worldIndex)
	end

	local reached = reachedByPlayer[player]
	if reached ~= nil and worldIndex > reached then
		reachedByPlayer[player] = worldIndex
		player:SetAttribute("ReachedWorld", worldIndex)
	end
end

function WorldService.initializePlayer(player: Player, reachedWorld: number)
	local reached = math.clamp(reachedWorld, 1, WorldLayout.worldCount())
	reachedByPlayer[player] = reached
	player:SetAttribute("ReachedWorld", reached)
	player:SetAttribute("CurrentWorld", 1)
end

function WorldService.reachedWorld(player: Player): number?
	return reachedByPlayer[player]
end

function WorldService.removePlayer(player: Player)
	reachedByPlayer[player] = nil
end

--[[
	Wired as RequestTeleport.OnServerInvoke. Returns success plus a
	message the client shows verbatim.
]]
function WorldService.attemptTeleport(player: Player, worldIndex: any): (boolean, string)
	if typeof(worldIndex) ~= "number" or GameConfig.worlds[worldIndex] == nil then
		return false, "That world does not exist."
	end

	local reached = reachedByPlayer[player]
	if reached == nil then
		return false, "Your data is still loading -- try again in a moment."
	end

	if worldIndex > reached then
		return false, "You haven't met the requirements -- reach this world on foot first!"
	end

	local character = player.Character
	if character == nil then
		return false, "You need a character to teleport."
	end

	character:PivotTo(CFrame.new(WorldLayout.spawnPositionForWorld(worldIndex)))

	return true, string.format("Teleported to %s!", GameConfig.worlds[worldIndex].name)
end

function WorldService.start()
	local sinceUpdate = 0

	RunService.Heartbeat:Connect(function(deltaSeconds)
		sinceUpdate += deltaSeconds
		if sinceUpdate < UPDATE_INTERVAL_SECONDS then
			return
		end
		sinceUpdate = 0

		for _, player in ipairs(Players:GetPlayers()) do
			updatePlayerWorld(player)
		end
	end)
end

return WorldService
