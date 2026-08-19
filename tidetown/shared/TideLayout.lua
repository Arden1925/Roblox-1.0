--[[
	Answers "where am I and what does the tide allow here" from the zone
	bounds in TidetownConfig. All world-geometry math lives here so the
	server (cast validation, surge lanes) and the client (zone labels)
	can never disagree about where a zone begins.
]]

local Shared = script.Parent
local TidePhase = require(Shared.TidePhase)
local TidetownConfig = require(Shared.TidetownConfig)

-- Which tide phases allow casting in each zone. The town only has
-- water (and therefore creatures) at high tide; the caves flood shut
-- at high tide; the deep reef additionally needs a mount to reach.
local CASTABLE_PHASES_BY_ZONE: { [string]: { [string]: boolean } } = {
	Beach = { [TidePhase.Low] = true, [TidePhase.High] = true },
	Town = { [TidePhase.High] = true },
	Cave = { [TidePhase.Low] = true },
	DeepReef = { [TidePhase.High] = true },
}

local TideLayout = {}

function TideLayout.zoneAt(position: Vector3): string?
	for _, zone in ipairs(TidetownConfig.layout.zones) do
		if position.X >= zone.minX and position.X < zone.maxX then
			return zone.key
		end
	end

	return nil
end

function TideLayout.zoneInfo(zoneKey: string): {
	key: string,
	name: string,
	minX: number,
	maxX: number,
	floorY: number,
}?
	for _, zone in ipairs(TidetownConfig.layout.zones) do
		if zone.key == zoneKey then
			return zone
		end
	end

	return nil
end

function TideLayout.castableAt(zoneKey: string, phase: string): boolean
	local phases = CASTABLE_PHASES_BY_ZONE[zoneKey]

	return phases ~= nil and phases[phase] == true
end

--[[
	The center of a reef plot pad. Plots line up along Z on the sand
	shelf just seaward of the boardwalk, centered on the shoreline.
]]
function TideLayout.plotPosition(plotIndex: number): Vector3
	local layout = TidetownConfig.layout
	local count = layout.reefPlotCount
	local centeredIndex = plotIndex - (count + 1) / 2

	return Vector3.new(
		layout.reefPlotX,
		layout.beachSand.topY,
		centeredIndex * layout.reefPlotSpacing
	)
end

function TideLayout.spawnPosition(): Vector3
	local spawn = TidetownConfig.layout.spawnPosition

	return Vector3.new(spawn.x, spawn.y, spawn.z)
end

return TideLayout
