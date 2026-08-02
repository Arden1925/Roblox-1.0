--[[
	Pure geometry for the chain of square worlds: where each world sits,
	where its spawn point is, and which world a position belongs to. Both
	the map builder and the world-progress tracker read from here, so the
	two can never disagree about boundaries.
]]

local Shared = script.Parent
local GameConfig = require(Shared.GameConfig)

local WorldLayout = {}

WorldLayout.width = 120
WorldLayout.length = 120
WorldLayout.startZ = -60

-- The whole map floats slightly above zero so its floors never share a
-- plane with a leftover Baseplate, which causes visible flickering
-- (z-fighting) where two surfaces overlap exactly.
WorldLayout.baseY = 0.2

function WorldLayout.worldCount(): number
	return #GameConfig.worlds
end

function WorldLayout.boundsForWorld(index: number): (number, number)
	local minZ = WorldLayout.startZ + (index - 1) * WorldLayout.length

	return minZ, minZ + WorldLayout.length
end

function WorldLayout.centerForWorld(index: number): Vector3
	local minZ, maxZ = WorldLayout.boundsForWorld(index)

	return Vector3.new(0, WorldLayout.baseY, (minZ + maxZ) / 2)
end

function WorldLayout.spawnPositionForWorld(index: number): Vector3
	local minZ = WorldLayout.boundsForWorld(index)

	return Vector3.new(0, WorldLayout.baseY + 5, minZ + 18)
end

function WorldLayout.worldIndexForPosition(position: Vector3): number
	local rawIndex = math.floor((position.Z - WorldLayout.startZ) / WorldLayout.length) + 1

	return math.clamp(rawIndex, 1, WorldLayout.worldCount())
end

return WorldLayout
