--[[
	Builds the playable starter map: a chain of square worlds separated by
	ever-taller climbable walls, ringed by borders no one can escape. It
	runs only when the workspace has no tagged pads, so a hand-built map
	always wins and this file can eventually be deleted without ceremony.

	All gameplay meaning comes from the same tags and attributes a
	hand-built map would use (see GAME_DESIGN.md), and all geometry math
	comes from WorldLayout so the progress tracker always agrees with what
	got built.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local WorldLayout = require(Shared.WorldLayout)

local BORDER_HEIGHT = 90
local BORDER_THICKNESS = 4
local WALL_THICKNESS = 4

local GROW_PAD_COLOR = Color3.fromRGB(76, 209, 55)
local SHRINK_PAD_COLOR = Color3.fromRGB(0, 168, 255)
local CRACK_COLOR = Color3.fromRGB(255, 168, 1)
local HAZARD_COLOR = Color3.fromRGB(255, 71, 87)
local BOUNCE_COLOR = Color3.fromRGB(255, 121, 198)
local WALL_COLOR = Color3.fromRGB(87, 96, 111)
local BORDER_COLOR = Color3.fromRGB(47, 54, 64)
local STEP_COLOR = Color3.fromRGB(223, 228, 234)
local PORTAL_COLOR = Color3.fromRGB(156, 136, 255)

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
		Position = position + Vector3.new(0, WorldLayout.baseY, 0),
		Color = color,
		Material = Enum.Material.Neon,
		Parent = parent,
	})

	CollectionService:AddTag(pad, tag)
end

local function createPortal(parent: Instance, worldIndex: number)
	local minZ = WorldLayout.boundsForWorld(worldIndex)
	local portal = createPart({
		Name = "Portal",
		Size = Vector3.new(1.5, 12, 8),
		Position = Vector3.new(-46, WorldLayout.baseY + 6, minZ + 20),
		Color = PORTAL_COLOR,
		Material = Enum.Material.ForceField,
		Parent = parent,
	})

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open Portal"
	prompt.ObjectText = "World Portal"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = portal

	CollectionService:AddTag(portal, "Portal")
end

--[[
	The climbable boundary wall after a world, with floating steps on the
	approach side. Bigger characters jump higher, so the step spacing (a
	fraction of wall height) is what turns "grow" into "may pass".
	Alternating step offsets add the light skill element: miss a hop and
	you start the climb again.
]]
local function createBoundaryWall(parent: Instance, worldIndex: number)
	local world = GameConfig.worlds[worldIndex]
	local _, maxZ = WorldLayout.boundsForWorld(worldIndex)
	local wallHeight = world.exitWallHeight
	local stepCount = world.exitStepCount

	createPart({
		Name = "BoundaryWall",
		Size = Vector3.new(WorldLayout.width, wallHeight, WALL_THICKNESS),
		Position = Vector3.new(0, WorldLayout.baseY + wallHeight / 2, maxZ),
		Color = WALL_COLOR,
		Material = Enum.Material.Slate,
		Parent = parent,
	})

	for stepIndex = 1, stepCount do
		local stepHeight = wallHeight * stepIndex / (stepCount + 1)
		local stepX = if stepIndex % 2 == 0 then 14 else -14

		createPart({
			Name = "WallStep",
			Size = Vector3.new(14, 1.5, 8),
			Position = Vector3.new(
				stepX,
				WorldLayout.baseY + stepHeight,
				maxZ - (stepCount - stepIndex + 1) * 11
			),
			Color = STEP_COLOR,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
	end
end

local function createBorders(parent: Instance)
	local totalLength = WorldLayout.length * WorldLayout.worldCount()
	local firstZ = WorldLayout.startZ
	local lastZ = firstZ + totalLength
	local centerZ = (firstZ + lastZ) / 2
	local halfWidth = WorldLayout.width / 2

	local borders = {
		{
			size = Vector3.new(BORDER_THICKNESS, BORDER_HEIGHT, totalLength),
			position = Vector3.new(-halfWidth, BORDER_HEIGHT / 2, centerZ),
		},
		{
			size = Vector3.new(BORDER_THICKNESS, BORDER_HEIGHT, totalLength),
			position = Vector3.new(halfWidth, BORDER_HEIGHT / 2, centerZ),
		},
		{
			size = Vector3.new(WorldLayout.width, BORDER_HEIGHT, BORDER_THICKNESS),
			position = Vector3.new(0, BORDER_HEIGHT / 2, firstZ),
		},
		{
			size = Vector3.new(WorldLayout.width, BORDER_HEIGHT, BORDER_THICKNESS),
			position = Vector3.new(0, BORDER_HEIGHT / 2, lastZ),
		},
	}

	for _, border in ipairs(borders) do
		createPart({
			Name = "Border",
			Size = border.size,
			Position = border.position + Vector3.new(0, WorldLayout.baseY, 0),
			Color = BORDER_COLOR,
			Material = Enum.Material.Slate,
			Transparency = 0.35,
			Parent = parent,
		})
	end
end

local function createCrackWall(parent: Instance, positionZ: number, maxAllowedSize: number)
	local openingWidth = 5
	local openingHeight = 5
	local wallHeight = 16
	local sideWidth = (WorldLayout.width - openingWidth) / 2

	for _, sideX in ipairs({ -(openingWidth + sideWidth) / 2, (openingWidth + sideWidth) / 2 }) do
		createPart({
			Name = "CrackWall",
			Size = Vector3.new(sideWidth, wallHeight, WALL_THICKNESS),
			Position = Vector3.new(sideX, WorldLayout.baseY + wallHeight / 2, positionZ),
			Color = WALL_COLOR,
			Material = Enum.Material.Slate,
			Parent = parent,
		})
	end

	createPart({
		Name = "CrackWallTop",
		Size = Vector3.new(openingWidth, wallHeight - openingHeight, WALL_THICKNESS),
		Position = Vector3.new(
			0,
			WorldLayout.baseY + openingHeight + (wallHeight - openingHeight) / 2,
			positionZ
		),
		Color = WALL_COLOR,
		Material = Enum.Material.Slate,
		Parent = parent,
	})

	local crack = createPart({
		Name = "SqueezeCrack",
		Size = Vector3.new(openingWidth, openingHeight, WALL_THICKNESS),
		Position = Vector3.new(0, WorldLayout.baseY + openingHeight / 2, positionZ),
		Color = CRACK_COLOR,
		Material = Enum.Material.ForceField,
		Parent = parent,
	})

	crack:SetAttribute("MaxAllowedSize", maxAllowedSize)
	CollectionService:AddTag(crack, "SqueezeCrack")
end

local function buildSproutMeadows(parent: Instance, minZ: number)
	for _, padX in ipairs({ -16, 0, 16 }) do
		createPad(parent, "GrowPad", Vector3.new(padX, 0.5, minZ + 45), GROW_PAD_COLOR)
	end

	createPad(parent, "GrowPad", Vector3.new(0, 0.5, minZ + 70), GROW_PAD_COLOR)
end

local function buildVentCity(parent: Instance, minZ: number)
	createPad(parent, "ShrinkPad", Vector3.new(0, 0.5, minZ + 30), SHRINK_PAD_COLOR)
	createCrackWall(parent, minZ + 45, 15)

	-- The vent: a ceiling low enough that regrown players get stuck, so
	-- the corridor itself enforces "stay small" with no scripting.
	createPart({
		Name = "VentCeiling",
		Size = Vector3.new(WorldLayout.width, 1, 30),
		Position = Vector3.new(0, WorldLayout.baseY + 6.5, minZ + 60),
		Color = WALL_COLOR,
		Material = Enum.Material.DiamondPlate,
		Parent = parent,
	})

	createPad(parent, "ShrinkPad", Vector3.new(0, 0.5, minZ + 60), SHRINK_PAD_COLOR)

	for _, padX in ipairs({ -16, 16 }) do
		createPad(parent, "GrowPad", Vector3.new(padX, 0.5, minZ + 90), GROW_PAD_COLOR)
	end
end

local function buildEmberFoundry(parent: Instance, minZ: number)
	-- Hazard patches between the entry and the pads: route through them
	-- while small, or around them while paying attention.
	for _, patch in ipairs({ { -14, 40 }, { 10, 52 }, { -6, 64 }, { 18, 72 } }) do
		local hazard = createPart({
			Name = "Hazard",
			Size = Vector3.new(12, 0.4, 12),
			Position = Vector3.new(patch[1], WorldLayout.baseY + 0.3, minZ + patch[2]),
			Color = HAZARD_COLOR,
			Material = Enum.Material.Neon,
			Parent = parent,
		})

		CollectionService:AddTag(hazard, "Hazard")
	end

	for _, padX in ipairs({ -20, 20 }) do
		createPad(parent, "GrowPad", Vector3.new(padX, 0.5, minZ + 85), GROW_PAD_COLOR)
	end

	-- A fading-platform bridge up to a bonus island with a faster payoff:
	-- pure optional skill content.
	for bridgeIndex = 1, 3 do
		local platform = createPart({
			Name = "FadingPlatform",
			Size = Vector3.new(8, 1, 8),
			Position = Vector3.new(
				-34 + bridgeIndex * 9,
				WorldLayout.baseY + 4 + bridgeIndex * 3,
				minZ + 100
			),
			Color = STEP_COLOR,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})

		CollectionService:AddTag(platform, "FadingPlatform")
	end

	createPart({
		Name = "BonusIsland",
		Size = Vector3.new(18, 2, 14),
		Position = Vector3.new(6, WorldLayout.baseY + 15, minZ + 100),
		Color = Color3.fromRGB(255, 159, 67),
		Material = Enum.Material.Slate,
		Parent = parent,
	})

	createPad(parent, "GrowPad", Vector3.new(6, 16.5, minZ + 100), GROW_PAD_COLOR)
end

local function buildCloudCapital(parent: Instance, minZ: number)
	local bounce = createPart({
		Name = "BouncePad",
		Size = Vector3.new(10, 1, 10),
		Position = Vector3.new(0, WorldLayout.baseY + 0.7, minZ + 35),
		Color = BOUNCE_COLOR,
		Material = Enum.Material.Neon,
		Parent = parent,
	})
	CollectionService:AddTag(bounce, "BouncePad")

	-- A fading staircase from the bounce apex to the sky garden.
	for stepIndex = 1, 3 do
		local platform = createPart({
			Name = "FadingPlatform",
			Size = Vector3.new(9, 1, 9),
			Position = Vector3.new(
				stepIndex * 10 - 20,
				WorldLayout.baseY + 12 + stepIndex * 4,
				minZ + 52 + stepIndex * 6
			),
			Color = STEP_COLOR,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})

		CollectionService:AddTag(platform, "FadingPlatform")
	end

	createPart({
		Name = "SkyGarden",
		Size = Vector3.new(30, 2, 24),
		Position = Vector3.new(10, WorldLayout.baseY + 27, minZ + 85),
		Color = Color3.fromRGB(190, 210, 255),
		Material = Enum.Material.Slate,
		Parent = parent,
	})

	for _, padX in ipairs({ 2, 18 }) do
		createPad(parent, "GrowPad", Vector3.new(padX, 28.5, minZ + 85), GROW_PAD_COLOR)
	end

	createPart({
		Name = "RebirthPodium",
		Size = Vector3.new(14, 3, 14),
		Position = Vector3.new(0, WorldLayout.baseY + 1.5, minZ + 105),
		Color = Color3.fromRGB(253, 203, 110),
		Material = Enum.Material.Marble,
		Parent = parent,
	})
end

local WORLD_BUILDERS = {
	buildSproutMeadows,
	buildVentCity,
	buildEmberFoundry,
	buildCloudCapital,
}

--[[
	Sunny late-afternoon sky with real clouds and light haze. Everything
	here is a built-in engine object, so no uploaded assets are needed.
]]
local function setupEnvironment()
	Lighting.ClockTime = 14.3
	Lighting.Brightness = 2.4

	if Lighting:FindFirstChildOfClass("Atmosphere") == nil then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.3
		atmosphere.Offset = 0.25
		atmosphere.Color = Color3.fromRGB(199, 199, 214)
		atmosphere.Decay = Color3.fromRGB(255, 188, 111)
		atmosphere.Glare = 0.3
		atmosphere.Haze = 1.7
		atmosphere.Parent = Lighting
	end

	if Lighting:FindFirstChildOfClass("BloomEffect") == nil then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.4
		bloom.Size = 24
		bloom.Threshold = 1.1
		bloom.Parent = Lighting
	end

	if Lighting:FindFirstChildOfClass("SunRaysEffect") == nil then
		local sunRays = Instance.new("SunRaysEffect")
		sunRays.Intensity = 0.08
		sunRays.Spread = 0.6
		sunRays.Parent = Lighting
	end

	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain ~= nil and terrain:FindFirstChildOfClass("Clouds") == nil then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.6
		clouds.Density = 0.3
		clouds.Parent = terrain
	end
end

-- Leftover template spawns (like the Baseplate's) would drop players
-- outside the borders, so switch them off rather than delete anything.
local function disableForeignSpawns()
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("SpawnLocation") then
			descendant.Enabled = false
		end
	end
end

function MapGenerator.generate()
	if #CollectionService:GetTagged("GrowPad") > 0 then
		return
	end

	setupEnvironment()
	disableForeignSpawns()

	local map = Instance.new("Folder")
	map.Name = "GeneratedMap"

	for worldIndex, world in ipairs(GameConfig.worlds) do
		local minZ, maxZ = WorldLayout.boundsForWorld(worldIndex)
		local floorColor = world.floorColor

		createPart({
			Name = "Floor",
			Size = Vector3.new(WorldLayout.width, 1, WorldLayout.length),
			Position = Vector3.new(0, WorldLayout.baseY - 0.5, (minZ + maxZ) / 2),
			Color = Color3.fromRGB(floorColor[1], floorColor[2], floorColor[3]),
			Material = Enum.Material.SmoothPlastic,
			Parent = map,
		})

		createPortal(map, worldIndex)
		WORLD_BUILDERS[worldIndex](map, minZ)

		if world.exitWallHeight ~= nil then
			createBoundaryWall(map, worldIndex)
		end
	end

	createBorders(map)

	local spawnPosition = WorldLayout.spawnPositionForWorld(1)
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Size = Vector3.new(12, 1, 12)
	spawnLocation.Position = Vector3.new(spawnPosition.X, WorldLayout.baseY + 0.5, spawnPosition.Z)
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Color = Color3.fromRGB(245, 246, 250)
	spawnLocation.Parent = map

	map.Parent = workspace
end

return MapGenerator
