--[[
	Dresses the generated map with real models from the asset packs in
	ReplicatedStorage.Assets.Models: trees and rocks in the meadow, street
	furniture in the city, cave formations in the foundry, beach props in
	the sky world, and a few oversized animals as landmarks. Everything
	placed here is pure decoration -- anchored, non-colliding, untagged --
	so gameplay is byte-for-byte the same with or without the packs.

	Placements are hand-picked against MapGenerator's coordinates so props
	never overlap pads, gates, ledges, bridges, or hazard fields.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local WorldLayout = require(Shared.WorldLayout)

type PropPath = { string | number }

type Placement = {
	world: number,
	path: PropPath,
	x: number,
	z: number,
	height: number,
	yaw: number?,
	lift: number?,
}

-- Path helpers, one per pack, so the placement table stays one line per
-- prop. A numeric segment picks a child by index for packs whose props
-- have unhelpful names (the cave pack is all "Model"/"MeshPart").
local function naturePath(propName: string): PropPath
	return { "Low_Poly_Nature_Asset_Pack", "Low Poly Nature Asset Pack | Destiny Tech", propName }
end

local function bundlePath(folderName: string, index: number): PropPath
	return { "Nature_Pack_Bundle", folderName, index }
end

local CITY_PACK = "City_Asset_Pack_2026"

local function cityPath(category: string, propName: string): PropPath
	return { CITY_PACK, "Models", category, propName }
end

local function cavePath(index: number): PropPath
	return { "Low_Poly_Cave_Asset_Pack", "Low Poly Cave Asset Pack | Destiny Tech", index }
end

local function beachPath(propName: string): PropPath
	return { "Beach_Summer_Asset_Pack_2025", "Models", propName }
end

local function foodPath(propName: string): PropPath
	return {
		"Ultimate_Low_Poly_Food_and_Candy_Pack",
		"Ultimate Low Poly Food and Candy Pack",
		propName,
	}
end

local function seaPath(propName: string): PropPath
	return { "Sea_Animals_Pack", "Models", propName }
end

-- x is absolute, z is relative to the world's minZ, height is the target
-- bounding-box height in studs (props are scaled to it), lift raises the
-- prop's bottom above the floor for floaters and rooftop props.
local PLACEMENTS: { Placement } = {
	-- World 1, Sprout Meadows: a real forest edge along both sides, a
	-- picnic of giant food by the spawn benches, and a beach turtle
	-- sunning itself near the pods.
	{ world = 1, path = naturePath("Birch Tree"), x = -50, z = 55, height = 14 },
	{ world = 1, path = naturePath("Tall Pine Tree"), x = -48, z = 95, height = 16 },
	{ world = 1, path = naturePath("Tree"), x = 46, z = 45, height = 13 },
	{ world = 1, path = naturePath("Tall Pine Tree 2"), x = 50, z = 120, height = 15 },
	{ world = 1, path = naturePath("Big Rock"), x = -46, z = 70, height = 5 },
	{ world = 1, path = naturePath("Rock 1"), x = 44, z = 85, height = 4 },
	{ world = 1, path = naturePath("Mushroom"), x = 28, z = 40, height = 3 },
	{ world = 1, path = naturePath("Big Mushroom"), x = -34, z = 146, height = 5 },
	{ world = 1, path = naturePath("Flower 2"), x = 30, z = 55, height = 2 },
	{ world = 1, path = naturePath("Flower 5"), x = -26, z = 100, height = 2 },
	{ world = 1, path = naturePath("Tree Stump"), x = 36, z = 130, height = 3 },
	{ world = 1, path = bundlePath("Bamboo Packs", 1), x = 20, z = 103, height = 8 },
	{ world = 1, path = foodPath("food_7"), x = -20, z = 14, height = 3 },
	{ world = 1, path = foodPath("food_21"), x = -24, z = 20, height = 3.5 },
	{ world = 1, path = foodPath("food_33"), x = -18, z = 24, height = 3 },
	{ world = 1, path = seaPath("Turtle"), x = 26, z = 10, height = 4, yaw = 40 },

	-- Replacements for MapGenerator's old part-built lollipop trees and
	-- neon flowers, at the exact spots the stand-ins occupied.
	{ world = 1, path = naturePath("Tree 2"), x = -36, z = 60, height = 12 },
	{ world = 1, path = naturePath("Double Tree"), x = 34, z = 100, height = 13 },
	{ world = 1, path = naturePath("Rooted Tree"), x = -30, z = 170, height = 12 },
	{ world = 1, path = naturePath("Squared Tree"), x = 38, z = 150, height = 11 },
	{ world = 1, path = naturePath("Flower 1"), x = -20, z = 35, height = 2 },
	{ world = 1, path = naturePath("Flower 3"), x = 24, z = 70, height = 2 },
	{ world = 1, path = naturePath("Flower 7"), x = -8, z = 130, height = 2 },
	{ world = 1, path = naturePath("Flower 9"), x = 12, z = 165, height = 2 },

	-- World 2, Vent City: lamp pairs flanking the main lane plus street
	-- furniture in the side margins, clear of the pipes, the crusher, the
	-- vent ceiling, and the plate-bridge yard.
	{ world = 2, path = cityPath("City Lamps", "Street Lamp 1"), x = -26, z = 45, height = 9 },
	{ world = 2, path = cityPath("City Lamps", "Street Lamp 1"), x = 26, z = 45, height = 9 },
	{ world = 2, path = cityPath("City Lamps", "Street Lamp 2"), x = -26, z = 95, height = 9 },
	{ world = 2, path = cityPath("City Lamps", "Street Lamp 2"), x = 26, z = 95, height = 9 },
	{
		world = 2,
		path = cityPath("Benches & Picnic", "Wooden Bench 1"),
		x = -30,
		z = 62,
		height = 3,
		yaw = 90,
	},
	{
		world = 2,
		path = { CITY_PACK, "Models", "MailBoxes", "Normal", 1 },
		x = 30,
		z = 58,
		height = 4,
	},
	{ world = 2, path = cityPath("Trash", "Trash Can 1"), x = -28, z = 88, height = 3.5 },
	{ world = 2, path = { CITY_PACK, "Models", "Signs", "Normal", 1 }, x = 28, z = 84, height = 7 },
	{ world = 2, path = cityPath("Vehicles", "Taxi Car"), x = -40, z = 100, height = 6, yaw = 20 },
	{
		world = 2,
		path = cityPath("Roadworks Stuff", "Warning Arrow Sign"),
		x = 24,
		z = 105,
		height = 3,
	},
	{
		world = 2,
		path = cityPath("Direction Signs", "Tall Direction Sign"),
		x = 24,
		z = 38,
		height = 6,
	},
	{
		world = 2,
		path = { CITY_PACK, "Models", "Red Lights", "Normal", 1 },
		x = -24,
		z = 190,
		height = 8,
	},

	-- World 3, Ember Foundry: cave formations lining the walls, loose
	-- stones near the routes, and a shark cruising high over the hazard
	-- field like it owns the place.
	{ world = 3, path = cavePath(1), x = -46, z = 40, height = 8 },
	{ world = 3, path = cavePath(3), x = 46, z = 40, height = 10 },
	{ world = 3, path = cavePath(5), x = -44, z = 120, height = 12 },
	{ world = 3, path = cavePath(7), x = 44, z = 120, height = 9 },
	{ world = 3, path = cavePath(9), x = -28, z = 60, height = 6 },
	{ world = 3, path = cavePath(11), x = 28, z = 135, height = 7 },
	{ world = 3, path = cavePath(13), x = -38, z = 92, height = 8 },
	{ world = 3, path = bundlePath("Stones Pack", 1), x = 24, z = 45, height = 3 },
	{ world = 3, path = bundlePath("Stones Pack", 4), x = -30, z = 168, height = 3.5 },
	{ world = 3, path = bundlePath("Stones Pack", 7), x = 30, z = 178, height = 4 },
	{ world = 3, path = seaPath("Shark"), x = -30, z = 130, height = 8, yaw = 120, lift = 30 },

	-- Replacements for the old freestanding basalt pillars.
	{ world = 3, path = cavePath(2), x = -40, z = 70, height = 17 },
	{ world = 3, path = cavePath(4), x = 40, z = 150, height = 16 },

	-- World 4, Cloud Capital: a beach resort in the sky, palms and
	-- loungers below, one chair on the sky garden itself, and a whale
	-- drifting between the clouds.
	{ world = 4, path = beachPath("Palm Tree"), x = -46, z = 40, height = 14 },
	{ world = 4, path = beachPath("Curved Palm Tree"), x = 46, z = 55, height = 13 },
	{ world = 4, path = beachPath("Palm Tree"), x = 48, z = 130, height = 14 },
	{ world = 4, path = beachPath("Sunshade"), x = -40, z = 90, height = 8 },
	{ world = 4, path = beachPath("Beach Chair"), x = -36, z = 96, height = 3, yaw = -30 },
	{ world = 4, path = beachPath("Sand Castle"), x = -30, z = 130, height = 5 },
	{ world = 4, path = beachPath("Beach Ball 1"), x = 34, z = 70, height = 3 },
	{ world = 4, path = beachPath("Surf Board"), x = 28, z = 40, height = 5, yaw = 15 },
	{ world = 4, path = beachPath("Starfish"), x = 24, z = 100, height = 2 },
	{ world = 4, path = beachPath("Unicorn Buoy"), x = -24, z = 105, height = 4 },
	{
		world = 4,
		path = beachPath("Beach Chair"),
		x = 22,
		z = 192,
		height = 3,
		yaw = 200,
		lift = 27.9,
	},
	{ world = 4, path = seaPath("Whale"), x = -38, z = 120, height = 14, yaw = 70, lift = 38 },
}

local SceneryService = {}

local function findProp(modelsFolder: Instance, path: PropPath): Instance?
	local current: Instance? = modelsFolder

	for _, segment in ipairs(path) do
		if current == nil then
			return nil
		end

		current = if typeof(segment) == "number"
			then current:GetChildren()[segment]
			else current:FindFirstChild(segment)
	end

	return current
end

-- Anchors and de-physicalizes every part so a prop can never block a
-- lane, eat a raycast, or fire Touched -- decoration stays decoration.
local function makeInert(container: Model)
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
end

local function placeProp(sceneryFolder: Folder, modelsFolder: Instance, placement: Placement)
	local template = findProp(modelsFolder, placement.path)
	if template == nil then
		warn("SceneryService: missing prop " .. table.concat(placement.path, "/"))
		return
	end

	-- Wrapping the clone lets one code path handle Models, Folders, and
	-- lone MeshParts alike: the container is what gets scaled and moved.
	local container = Instance.new("Model")
	container.Name = template.Name

	local clone = template:Clone()
	clone.Parent = container
	makeInert(container)

	local extents = container:GetExtentsSize()
	if extents.Y < 0.05 then
		container:Destroy()
		return
	end

	local yaw = if placement.yaw ~= nil then placement.yaw else 0
	container:PivotTo(container:GetPivot() * CFrame.Angles(0, math.rad(yaw), 0))
	container:ScaleTo(placement.height / extents.Y)

	local boxCFrame, boxSize = container:GetBoundingBox()
	local minZ = WorldLayout.boundsForWorld(placement.world)
	local lift = if placement.lift ~= nil then placement.lift else 0
	local bottomY = WorldLayout.baseY + lift

	local offset = Vector3.new(
		placement.x - boxCFrame.Position.X,
		bottomY + boxSize.Y / 2 - boxCFrame.Position.Y,
		minZ + placement.z - boxCFrame.Position.Z
	)

	container:PivotTo(container:GetPivot() + offset)
	container.Parent = sceneryFolder
end

function SceneryService.start()
	-- Emptied plots stay empty: decorating them would sneak the "stuff"
	-- right back into the rectangles.
	if GameConfig.worldsEmptied == true then
		return
	end

	local generatedMap = workspace:FindFirstChild("GeneratedMap")
	if generatedMap == nil then
		-- A hand-built map arranges its own scenery; placements below
		-- only make sense on MapGenerator's geometry.
		return
	end

	if generatedMap:FindFirstChild("Scenery") ~= nil then
		return
	end

	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local modelsFolder = if assetsFolder ~= nil then assetsFolder:FindFirstChild("Models") else nil
	if modelsFolder == nil then
		warn("SceneryService: ReplicatedStorage.Assets.Models is missing; map stays undecorated")
		return
	end

	local sceneryFolder = Instance.new("Folder")
	sceneryFolder.Name = "Scenery"

	for _, placement in ipairs(PLACEMENTS) do
		placeProp(sceneryFolder, modelsFolder, placement)
	end

	sceneryFolder.Parent = generatedMap
end

return SceneryService
