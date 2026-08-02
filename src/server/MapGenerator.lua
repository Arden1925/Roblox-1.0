--[[
	Builds a playable three-zone starter map so the game works before any
	map has been made by hand in Studio. It runs only when the workspace
	has no tagged pads, so a hand-built map always wins and this file can
	eventually be deleted without ceremony.

	Zone 1 teaches growing, zone 2 (The Vents) forces shrinking, and zone 3
	(The Giant's Hall) demands real size. All gameplay meaning comes from
	the same tags and attributes a hand-built map would use.
]]

local CollectionService = game:GetService("CollectionService")

local FLOOR_WIDTH = 80
local WALL_HEIGHT = 26
local WALL_THICKNESS = 3

local GROW_PAD_COLOR = Color3.fromRGB(76, 209, 55)
local SHRINK_PAD_COLOR = Color3.fromRGB(0, 168, 255)
local GATE_COLOR = Color3.fromRGB(232, 65, 24)
local CRACK_COLOR = Color3.fromRGB(255, 168, 1)
local WALL_COLOR = Color3.fromRGB(87, 96, 111)

local MapGenerator = {}

local function createPart(properties: { [string]: any }): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	for key, value in pairs(properties) do
		if key ~= "Parent" then
			part[key] = value
		end
	end

	part.Parent = properties.Parent

	return part
end

local function createPad(parent: Instance, tag: string, position: Vector3, color: Color3)
	local pad = createPart({
		Name = tag,
		Size = Vector3.new(8, 1, 8),
		Position = position,
		Color = color,
		Material = Enum.Material.Neon,
		Parent = parent,
	})

	CollectionService:AddTag(pad, tag)
end

--[[
	Builds a wall across the floor with a centered opening, and fills the
	opening with a tagged barrier part. openingWidth and openingHeight
	control who can physically fit once the barrier goes ghostly.
]]
local function createWallWithBarrier(
	parent: Instance,
	positionZ: number,
	openingWidth: number,
	openingHeight: number,
	barrierTag: string,
	barrierAttribute: string,
	barrierValue: number,
	barrierColor: Color3
)
	local sideWidth = (FLOOR_WIDTH - openingWidth) / 2

	for _, sideX in ipairs({ -(openingWidth + sideWidth) / 2, (openingWidth + sideWidth) / 2 }) do
		createPart({
			Name = "Wall",
			Size = Vector3.new(sideWidth, WALL_HEIGHT, WALL_THICKNESS),
			Position = Vector3.new(sideX, WALL_HEIGHT / 2, positionZ),
			Color = WALL_COLOR,
			Material = Enum.Material.Slate,
			Parent = parent,
		})
	end

	createPart({
		Name = "WallTop",
		Size = Vector3.new(openingWidth, WALL_HEIGHT - openingHeight, WALL_THICKNESS),
		Position = Vector3.new(0, openingHeight + (WALL_HEIGHT - openingHeight) / 2, positionZ),
		Color = WALL_COLOR,
		Material = Enum.Material.Slate,
		Parent = parent,
	})

	local barrier = createPart({
		Name = barrierTag,
		Size = Vector3.new(openingWidth, openingHeight, WALL_THICKNESS),
		Position = Vector3.new(0, openingHeight / 2, positionZ),
		Color = barrierColor,
		Material = Enum.Material.ForceField,
		Parent = parent,
	})

	barrier:SetAttribute(barrierAttribute, barrierValue)
	CollectionService:AddTag(barrier, barrierTag)
end

local function createFloor(parent: Instance, fromZ: number, toZ: number, color: Color3)
	createPart({
		Name = "Floor",
		Size = Vector3.new(FLOOR_WIDTH, 1, toZ - fromZ),
		Position = Vector3.new(0, -0.5, (fromZ + toZ) / 2),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
end

local function createVentCorridor(parent: Instance, fromZ: number, toZ: number)
	-- A ceiling low enough that regrown players get stuck: the corridor
	-- itself enforces "stay small", no scripting needed.
	createPart({
		Name = "VentCeiling",
		Size = Vector3.new(FLOOR_WIDTH, 1, toZ - fromZ),
		Position = Vector3.new(0, 6.5, (fromZ + toZ) / 2),
		Color = WALL_COLOR,
		Material = Enum.Material.DiamondPlate,
		Parent = parent,
	})

	-- A mid-corridor shrink pad tops smallness back up, since Current
	-- Size regrows on its own the whole way through.
	createPad(parent, "ShrinkPad", Vector3.new(0, 0.5, (fromZ + toZ) / 2), SHRINK_PAD_COLOR)
end

function MapGenerator.generate()
	if #CollectionService:GetTagged("GrowPad") > 0 then
		return
	end

	local map = Instance.new("Folder")
	map.Name = "GeneratedMap"

	createFloor(map, -50, 30, Color3.fromRGB(220, 221, 225))

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Size = Vector3.new(12, 1, 12)
	spawnLocation.Position = Vector3.new(0, 0.5, -40)
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Color = Color3.fromRGB(245, 246, 250)
	spawnLocation.Parent = map

	for _, padX in ipairs({ -16, 0, 16 }) do
		createPad(map, "GrowPad", Vector3.new(padX, 0.5, 5), GROW_PAD_COLOR)
	end

	createWallWithBarrier(map, 30, 14, 14, "SizeGate", "RequiredSize", 40, GATE_COLOR)

	createFloor(map, 30, 100, Color3.fromRGB(200, 214, 229))
	createPad(map, "ShrinkPad", Vector3.new(0, 0.5, 40), SHRINK_PAD_COLOR)
	createWallWithBarrier(map, 50, 5, 5, "SqueezeCrack", "MaxAllowedSize", 15, CRACK_COLOR)
	createVentCorridor(map, 50, 85)
	createPad(map, "GrowPad", Vector3.new(-16, 0.5, 92), GROW_PAD_COLOR)
	createPad(map, "GrowPad", Vector3.new(16, 0.5, 92), GROW_PAD_COLOR)

	createWallWithBarrier(map, 100, 20, 22, "SizeGate", "RequiredSize", 150, GATE_COLOR)

	createFloor(map, 100, 170, Color3.fromRGB(255, 234, 167))
	for _, padX in ipairs({ -20, 0, 20 }) do
		createPad(map, "GrowPad", Vector3.new(padX, 0.5, 120), GROW_PAD_COLOR)
	end

	-- A landmark for the end of v1 content: rebirth happens through the
	-- UI, so this is a destination, not a mechanic.
	createPart({
		Name = "RebirthPodium",
		Size = Vector3.new(14, 3, 14),
		Position = Vector3.new(0, 1.5, 150),
		Color = Color3.fromRGB(253, 203, 110),
		Material = Enum.Material.Marble,
		Parent = map,
	})

	map.Parent = workspace
end

return MapGenerator
