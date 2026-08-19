--[[
	Builds the whole Tidetown world under one Workspace folder: the
	stepped seabed the low tide exposes (deep reef shelf, glowing cave
	shallows, tidepool flats), the dry beach, the boardwalk with its
	pier and reef plots, the flooded-at-high-tide town, the two water
	slabs the tide clock moves, and the border walls. Geometry math
	comes from TidetownConfig.layout and TideLayout so the map can never
	drift from the zone logic that judges casts and surges.

	Everything is plain anchored part-work except the town, which
	prefers the bought TDS scenery pack and falls back to simple part
	houses so the map composes identically without the asset.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local TidetownShared = ReplicatedStorage.TidetownShared
local TideLayout = require(TidetownShared.TideLayout)
local TidetownConfig = require(TidetownShared.TidetownConfig)

local MAP_FOLDER_NAME = "Tidetown"

-- The playable box. The west and east edges sit past the outermost
-- zones so the deep shelf runs all the way to the border wall and no
-- swimmer ever finds a void.
local WEST_EDGE_X = -760
local EAST_EDGE_X = 430
local HALF_WIDTH_Z = 190
local FULL_WIDTH_Z = HALF_WIDTH_Z * 2

local SLAB_THICKNESS = 4
local STAIR_STEP_DEPTH = 1.6
local TIDE_POOL_COUNT = 12
local CRYSTAL_COUNT = 14

local MOUNT_STAND_POSITION = Vector3.new(-70, 8.5, 0)
local RESCUE_POSITION = Vector3.new(0, 3.5, 20)

local DEEP_FLOOR_COLOR = Color3.fromRGB(82, 92, 105)
local CAVE_FLOOR_COLOR = Color3.fromRGB(105, 98, 118)
local WET_SAND_COLOR = Color3.fromRGB(216, 195, 145)
local DRY_SAND_COLOR = Color3.fromRGB(238, 220, 165)
local WOOD_COLOR = Color3.fromRGB(133, 100, 70)
local RAIL_COLOR = Color3.fromRGB(150, 115, 82)
local GRASS_COLOR = Color3.fromRGB(120, 176, 92)
local WATER_COLOR = Color3.fromRGB(64, 180, 182)
local POOL_COLOR = Color3.fromRGB(128, 222, 234)
local BARRIER_COLOR = Color3.fromRGB(66, 165, 245)
local PERCH_COLOR = Color3.fromRGB(240, 128, 128)
local PAD_COLOR = Color3.fromRGB(190, 200, 210)
local TUBE_COLOR = Color3.fromRGB(255, 110, 100)
local ARCH_COLOR = Color3.fromRGB(120, 112, 134)

local CRYSTAL_COLORS = {
	Color3.fromRGB(102, 255, 255),
	Color3.fromRGB(186, 104, 200),
	Color3.fromRGB(129, 212, 250),
}

local HOUSE_COLORS = {
	Color3.fromRGB(236, 190, 180),
	Color3.fromRGB(178, 210, 224),
	Color3.fromRGB(226, 220, 180),
	Color3.fromRGB(196, 222, 190),
	Color3.fromRGB(222, 196, 224),
}

local MapBuilder = {}

local mapFolder: Instance? = nil

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

-- Zone bounds come from the shared layout so the geometry can never
-- disagree with the zone logic; a missing key is a programmer error.
local function zoneBounds(zoneKey: string): { minX: number, maxX: number, floorY: number }
	local info = TideLayout.zoneInfo(zoneKey)
	assert(info ~= nil, string.format("Unknown zone %q", zoneKey))

	return info
end

local function buildFloorSlab(
	parent: Instance,
	name: string,
	minX: number,
	maxX: number,
	topY: number,
	material: Enum.Material,
	color: Color3
): BasePart
	return createPart({
		Name = name,
		Size = Vector3.new(maxX - minX, SLAB_THICKNESS, FULL_WIDTH_Z),
		Position = Vector3.new((minX + maxX) / 2, topY - SLAB_THICKNESS / 2, 0),
		Material = material,
		Color = color,
		Parent = parent,
	})
end

local function buildStoneArch(parent: Instance, position: Vector3, yawDegrees: number)
	local archCFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(yawDegrees), 0)

	for _, side in ipairs({ -8, 8 }) do
		createPart({
			Name = "ArchPillar",
			Size = Vector3.new(4, 14, 4),
			CFrame = archCFrame * CFrame.new(side, 7, 0),
			Material = Enum.Material.Rock,
			Color = ARCH_COLOR,
			Parent = parent,
		})
	end

	createPart({
		Name = "ArchLintel",
		Size = Vector3.new(20, 4, 5),
		CFrame = archCFrame * CFrame.new(0, 16, 0),
		Material = Enum.Material.Rock,
		Color = ARCH_COLOR,
		Parent = parent,
	})
end

local function buildCrystals(parent: Instance, minX: number, maxX: number)
	for _ = 1, CRYSTAL_COUNT do
		local x = math.random(minX + 10, maxX - 10)
		local z = math.random(-HALF_WIDTH_Z + 10, HALF_WIDTH_Z - 10)
		local height = 2 + math.random() * 4

		createPart({
			Name = "Crystal",
			Size = Vector3.new(0.8 + math.random() * 0.8, height, 0.8 + math.random() * 0.8),
			CFrame = CFrame.new(x, height / 2 - 0.3, z) * CFrame.Angles(
				math.rad(math.random(-18, 18)),
				math.rad(math.random(0, 359)),
				math.rad(math.random(-18, 18))
			),
			Material = Enum.Material.Neon,
			Color = CRYSTAL_COLORS[math.random(1, #CRYSTAL_COLORS)],
			CanCollide = false,
			Parent = parent,
		})
	end
end

local function buildTidePool(parent: Instance, x: number, z: number)
	local diameter = 6 + math.random() * 4

	-- A cylinder lies along its local X axis, so rolling it 90 degrees
	-- about Z stands the disc flat on the sand.
	createPart({
		Name = "TidePool",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, diameter, diameter),
		CFrame = CFrame.new(x, 0.1, z) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Glass,
		Color = POOL_COLOR,
		Transparency = 0.35,
		CanCollide = false,
		Parent = parent,
	})

	-- The emitter lives on its own unrotated host so the sparkles rise
	-- straight up instead of along the rolled cylinder's axis.
	local sparkleHost = createPart({
		Name = "Sparkle",
		Size = Vector3.new(0.5, 0.5, 0.5),
		Position = Vector3.new(x, 0.6, z),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Parent = parent,
	})

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), POOL_COLOR)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.25)
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Rate = 3
	emitter.Speed = NumberRange.new(0.5, 1.2)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Parent = sparkleHost
end

local function buildSeabed(parent: Instance)
	local seabed = Instance.new("Folder")
	seabed.Name = "Seabed"
	seabed.Parent = parent

	local deep = zoneBounds("DeepReef")
	buildFloorSlab(
		seabed,
		"DeepReefFloor",
		WEST_EDGE_X,
		deep.maxX,
		deep.floorY,
		Enum.Material.Slate,
		DEEP_FLOOR_COLOR
	)

	local cave = zoneBounds("Cave")
	buildFloorSlab(
		seabed,
		"CaveFloor",
		cave.minX,
		cave.maxX,
		cave.floorY,
		Enum.Material.Rock,
		CAVE_FLOOR_COLOR
	)

	buildStoneArch(seabed, Vector3.new(-430, cave.floorY, -60), 15)
	buildStoneArch(seabed, Vector3.new(-380, cave.floorY, 70), -25)
	buildStoneArch(seabed, Vector3.new(-320, cave.floorY, -110), 40)
	buildStoneArch(seabed, Vector3.new(-270, cave.floorY, 40), 0)
	buildCrystals(seabed, cave.minX, cave.maxX)

	local beach = zoneBounds("Beach")
	buildFloorSlab(
		seabed,
		"BeachFlats",
		beach.minX,
		beach.maxX,
		beach.floorY,
		Enum.Material.Sand,
		WET_SAND_COLOR
	)

	for _ = 1, TIDE_POOL_COUNT do
		buildTidePool(seabed, math.random(beach.minX + 20, beach.maxX - 20), math.random(-170, 170))
	end
end

local function buildBeach(parent: Instance)
	local sand = TidetownConfig.layout.beachSand

	local beach = Instance.new("Folder")
	beach.Name = "Beach"
	beach.Parent = parent

	buildFloorSlab(
		beach,
		"DrySand",
		sand.minX,
		sand.maxX,
		sand.topY,
		Enum.Material.Sand,
		DRY_SAND_COLOR
	)
end

--[[
	One railing run along a deck edge, split around the listed gaps
	({ zFrom, zTo } pairs) so stairs and the pier mouth stay walkable.
]]
local function buildRailingRuns(
	parent: Instance,
	edgeX: number,
	deckY: number,
	gaps: { { number } }
)
	table.sort(gaps, function(a, b)
		return a[1] < b[1]
	end)

	local cursor = -HALF_WIDTH_Z
	local index = 1
	while cursor < HALF_WIDTH_Z do
		local gap = gaps[index]
		local runEnd = if gap ~= nil then gap[1] else HALF_WIDTH_Z

		if runEnd > cursor then
			local length = runEnd - cursor
			createPart({
				Name = "Railing",
				Size = Vector3.new(0.5, 3, length),
				Position = Vector3.new(edgeX, deckY + 1.5, cursor + length / 2),
				Material = Enum.Material.WoodPlanks,
				Color = RAIL_COLOR,
				Parent = parent,
			})
		end

		if gap == nil then
			break
		end

		cursor = gap[2]
		index += 1
	end
end

-- A straight flight of one-stud steps from the deck edge down to the
-- ground, walking away from the deck in the given X direction.
local function buildStairs(
	parent: Instance,
	edgeX: number,
	direction: number,
	topY: number,
	bottomY: number,
	zCenter: number,
	width: number
)
	for step = 1, topY - bottomY do
		createPart({
			Name = "Stair",
			Size = Vector3.new(STAIR_STEP_DEPTH, 1, width),
			Position = Vector3.new(
				edgeX + direction * (step - 0.5) * STAIR_STEP_DEPTH,
				topY - step - 0.5,
				zCenter
			),
			Material = Enum.Material.WoodPlanks,
			Color = WOOD_COLOR,
			Parent = parent,
		})
	end
end

local function buildBoardwalk(parent: Instance)
	local layout = TidetownConfig.layout
	local deck = layout.boardwalk
	local sandTopY = layout.beachSand.topY

	local boardwalk = Instance.new("Folder")
	boardwalk.Name = "Boardwalk"
	boardwalk.Parent = parent

	createPart({
		Name = "Deck",
		Size = Vector3.new(deck.maxX - deck.minX, 1, FULL_WIDTH_Z),
		Position = Vector3.new((deck.minX + deck.maxX) / 2, deck.deckY - 0.5, 0),
		Material = Enum.Material.WoodPlanks,
		Color = WOOD_COLOR,
		Parent = boardwalk,
	})

	-- The landward face gets a skirt so the deck reads as a solid
	-- structure from the town instead of a floating slab.
	createPart({
		Name = "DeckSkirt",
		Size = Vector3.new(1, deck.deckY - 1 - layout.townGroundY, FULL_WIDTH_Z),
		Position = Vector3.new(deck.maxX - 0.5, (deck.deckY - 1 + layout.townGroundY) / 2, 0),
		Material = Enum.Material.WoodPlanks,
		Color = WOOD_COLOR,
		Parent = boardwalk,
	})

	local seawardGaps: { { number } } = { { -5, 5 } }
	for plotIndex = 1, layout.reefPlotCount do
		local plotZ = TideLayout.plotPosition(plotIndex).Z
		table.insert(seawardGaps, { plotZ - 4, plotZ + 4 })
		buildStairs(boardwalk, deck.minX, -1, deck.deckY, sandTopY, plotZ, 6)
	end

	buildRailingRuns(boardwalk, deck.minX + 0.25, deck.deckY, seawardGaps)
	buildRailingRuns(boardwalk, deck.maxX - 0.25, deck.deckY, { { -5, 5 } })

	-- One wide flight into the town: high tide floods the streets to
	-- the waist, so players need a way back up that is not a jump.
	buildStairs(boardwalk, deck.maxX, 1, deck.deckY, layout.townGroundY, 0, 8)

	for postZ = -160, 160, 40 do
		if postZ ~= 0 then
			createPart({
				Name = "DeckPost",
				Size = Vector3.new(1.5, deck.deckY - 1 - sandTopY, 1.5),
				Position = Vector3.new(deck.minX + 1, (deck.deckY - 1 + sandTopY) / 2, postZ),
				Material = Enum.Material.Wood,
				Color = WOOD_COLOR,
				Parent = boardwalk,
			})
		end
	end
end

local function buildPier(parent: Instance)
	local layout = TidetownConfig.layout
	local deckY = layout.boardwalk.deckY
	local pierMinX = -80
	local pierMaxX = layout.boardwalk.minX

	local pier = Instance.new("Folder")
	pier.Name = "Pier"
	pier.Parent = parent

	createPart({
		Name = "PierDeck",
		Size = Vector3.new(pierMaxX - pierMinX, 1, 10),
		Position = Vector3.new((pierMinX + pierMaxX) / 2, deckY - 0.5, 0),
		Material = Enum.Material.WoodPlanks,
		Color = WOOD_COLOR,
		Parent = pier,
	})

	-- Rails on both long sides; the seaward end stays open so riders
	-- can leap straight into the flood.
	for _, side in ipairs({ -4.75, 4.75 }) do
		createPart({
			Name = "PierRail",
			Size = Vector3.new(pierMaxX - pierMinX, 2.5, 0.5),
			Position = Vector3.new((pierMinX + pierMaxX) / 2, deckY + 1.25, side),
			Material = Enum.Material.WoodPlanks,
			Color = RAIL_COLOR,
			Parent = pier,
		})
	end

	for postX = pierMinX + 5, pierMaxX - 5, 20 do
		local floorY = if postX >= layout.beachSand.minX then layout.beachSand.topY else 0
		for _, side in ipairs({ -4, 4 }) do
			createPart({
				Name = "PierPost",
				Size = Vector3.new(1.5, deckY - 1 - floorY, 1.5),
				Position = Vector3.new(postX, (deckY - 1 + floorY) / 2, side),
				Material = Enum.Material.Wood,
				Color = WOOD_COLOR,
				Parent = pier,
			})
		end
	end

	-- The stand is a direct child of the map folder because
	-- MountService looks it up as Workspace.Tidetown.MountStand.
	local stand = createPart({
		Name = "MountStand",
		Size = Vector3.new(2, 3, 2),
		Position = MOUNT_STAND_POSITION,
		Material = Enum.Material.Wood,
		Color = RAIL_COLOR,
		Parent = parent,
	})

	createPart({
		Name = "TubeDecoration",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 3.5, 3.5),
		Position = MOUNT_STAND_POSITION + Vector3.new(0, 1.7, 0),
		Color = TUBE_COLOR,
		CanCollide = false,
		Parent = pier,
	})

	-- Enabled at all times on purpose: MountService rejects rides
	-- outside high tide with a friendly toast, which teaches the rule
	-- better than a prompt that silently disappears.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Grab the inner tube"
	prompt.ObjectText = "Pier Inner Tube"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = stand
end

local function buildFallbackHouses(parent: Instance)
	local groundY = TidetownConfig.layout.townGroundY

	for row, rowZ in ipairs({ -45, 45 }) do
		for column = 0, 4 do
			local x = 140 + column * 60
			local color = HOUSE_COLORS[(row + column) % #HOUSE_COLORS + 1]

			createPart({
				Name = "FallbackHouse",
				Size = Vector3.new(26, 13, 24),
				Position = Vector3.new(x, groundY + 6.5, rowZ),
				Material = Enum.Material.SmoothPlastic,
				Color = color,
				Parent = parent,
			})

			createPart({
				Name = "FallbackRoof",
				Size = Vector3.new(28, 1.5, 26),
				Position = Vector3.new(x, groundY + 13.75, rowZ),
				Material = Enum.Material.Wood,
				Color = WOOD_COLOR,
				Parent = parent,
			})
		end
	end

	warn("MapBuilder: TDS town pack missing; part houses mark the town")
end

local function buildTown(parent: Instance)
	local layout = TidetownConfig.layout
	local town = zoneBounds("Town")

	local townFolder = Instance.new("Folder")
	townFolder.Name = "Town"
	townFolder.Parent = parent

	buildFloorSlab(
		townFolder,
		"TownGround",
		town.minX,
		EAST_EDGE_X,
		layout.townGroundY,
		Enum.Material.Grass,
		GRASS_COLOR
	)

	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local modelsFolder = if assetsFolder ~= nil then assetsFolder:FindFirstChild("Models") else nil
	local pack = if modelsFolder ~= nil then modelsFolder:FindFirstChild("Tds_Town_Pack") else nil
	local template = if pack ~= nil then pack:FindFirstChild("Scenery") else nil

	if template == nil or not template:IsA("Model") then
		buildFallbackHouses(townFolder)
		return
	end

	local sceneryTown = template:Clone()
	for _, descendant in ipairs(sceneryTown:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	local boxCFrame, boxSize = sceneryTown:GetBoundingBox()

	-- Shrink-to-fit keeps a future, larger pack inside the town zone
	-- instead of spilling onto the boardwalk or through the borders.
	local fitScale = math.min(1, 320 / boxSize.X, 360 / boxSize.Z)
	if fitScale < 1 then
		sceneryTown:ScaleTo(fitScale)
		boxCFrame, boxSize = sceneryTown:GetBoundingBox()
	end

	-- Sunk one stud (the HubService pattern) so every foundation beds
	-- into the grass instead of hovering on the bounding box.
	local target = Vector3.new(250, layout.townGroundY + boxSize.Y / 2 - 1, 0)
	sceneryTown:PivotTo(sceneryTown:GetPivot() + (target - boxCFrame.Position))
	sceneryTown.Name = "TdsTown"
	sceneryTown.Parent = townFolder
end

local function buildPlot(parent: Instance, plotIndex: number)
	local position = TideLayout.plotPosition(plotIndex)

	local plotFolder = Instance.new("Folder")
	plotFolder.Name = "Plot" .. tostring(plotIndex)
	plotFolder.Parent = parent

	createPart({
		Name = "Pad",
		Size = Vector3.new(6, 1, 6),
		Position = Vector3.new(position.X, position.Y - 0.5, position.Z),
		Material = Enum.Material.Slate,
		Color = PAD_COLOR,
		Parent = plotFolder,
	})

	createPart({
		Name = "Barrier",
		Size = Vector3.new(1, 4, 14),
		Position = Vector3.new(position.X - 3, position.Y + 2, position.Z),
		Color = BARRIER_COLOR,
		Transparency = 0.35,
		CanCollide = false,
		Parent = plotFolder,
	})

	local perchOffsets = {
		Vector3.new(-2.2, 0.5, -2.2),
		Vector3.new(-2.2, 0.5, 2.2),
		Vector3.new(2.2, 0.5, 0),
	}
	for perchIndex, offset in ipairs(perchOffsets) do
		createPart({
			Name = "Perch" .. tostring(perchIndex),
			Size = Vector3.new(1, 1, 1),
			Position = position + offset,
			Material = Enum.Material.SmoothPlastic,
			Color = PERCH_COLOR,
			CanCollide = false,
			Parent = plotFolder,
		})
	end

	-- The sign pokes above the deck on a stub post so both boardwalk
	-- strollers and sea approaches can read whose reef this is. Yaw 90
	-- points the Front face (and its gui) seaward.
	createPart({
		Name = "SignPost",
		Size = Vector3.new(0.5, 1, 0.5),
		Position = Vector3.new(position.X - 3, position.Y + 4.5, position.Z),
		Material = Enum.Material.Wood,
		Color = WOOD_COLOR,
		Parent = plotFolder,
	})

	local sign = createPart({
		Name = "Sign",
		Size = Vector3.new(6, 2, 0.5),
		CFrame = CFrame.new(position.X - 3, position.Y + 6, position.Z)
			* CFrame.Angles(0, math.rad(90), 0),
		Material = Enum.Material.Wood,
		Color = RAIL_COLOR,
		Parent = plotFolder,
	})

	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Face = Enum.NormalId.Front
	surfaceGui.PixelsPerStud = 24
	surfaceGui.LightInfluence = 0
	surfaceGui.Parent = sign

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.5
	label.Text = "Open Reef"
	label.Parent = surfaceGui
end

local function buildWater(parent: Instance)
	local lowWaterY = TidetownConfig.tide.lowWaterY

	-- Two slabs instead of one so the flood over the shore and town can
	-- be a separate part: TideClockService snaps both to each phase
	-- target and the client tweens the visual.
	createPart({
		Name = "Water",
		Size = Vector3.new(730, 1, FULL_WIDTH_Z),
		Position = Vector3.new(-395, lowWaterY - 0.5, 0),
		Material = Enum.Material.Glass,
		Color = WATER_COLOR,
		Transparency = 0.35,
		CanCollide = false,
		CanQuery = false,
		Parent = parent,
	})

	createPart({
		Name = "FloodWater",
		Size = Vector3.new(460, 1, FULL_WIDTH_Z),
		Position = Vector3.new(200, lowWaterY - 0.5, 0),
		Material = Enum.Material.Glass,
		Color = WATER_COLOR,
		Transparency = 0.35,
		CanCollide = false,
		CanQuery = false,
		Parent = parent,
	})
end

local function buildBorders(parent: Instance)
	local borders = Instance.new("Folder")
	borders.Name = "Borders"
	borders.Parent = parent

	local walls = {
		{ position = Vector3.new(WEST_EDGE_X - 2, 40, 0), size = Vector3.new(4, 140, 396) },
		{ position = Vector3.new(EAST_EDGE_X + 2, 40, 0), size = Vector3.new(4, 140, 396) },
		{
			position = Vector3.new((WEST_EDGE_X + EAST_EDGE_X) / 2, 40, HALF_WIDTH_Z + 2),
			size = Vector3.new(EAST_EDGE_X - WEST_EDGE_X + 8, 140, 4),
		},
		{
			position = Vector3.new((WEST_EDGE_X + EAST_EDGE_X) / 2, 40, -HALF_WIDTH_Z - 2),
			size = Vector3.new(EAST_EDGE_X - WEST_EDGE_X + 8, 140, 4),
		},
	}

	for _, wall in ipairs(walls) do
		createPart({
			Name = "Border",
			Size = wall.size,
			Position = wall.position,
			Transparency = 1,
			Parent = borders,
		})
	end
end

local function buildSpawnAndRescue(parent: Instance)
	local spawnPosition = TideLayout.spawnPosition()

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "SpawnLocation"
	spawnLocation.Size = Vector3.new(8, 1, 8)
	spawnLocation.Position = Vector3.new(spawnPosition.X, spawnPosition.Y - 0.5, spawnPosition.Z)
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.Material = Enum.Material.WoodPlanks
	spawnLocation.Color = RAIL_COLOR
	spawnLocation.TopSurface = Enum.SurfaceType.Smooth
	spawnLocation.Parent = parent

	-- Decorative only: CreatureService builds the real rescue prompt at
	-- MapBuilder.rescuePosition(). The mound just draws the eye there.
	createPart({
		Name = "RescueSpot",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 5, 5),
		CFrame = CFrame.new(RESCUE_POSITION.X, RESCUE_POSITION.Y - 0.3, RESCUE_POSITION.Z)
			* CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Sand,
		Color = DRY_SAND_COLOR,
		CanCollide = false,
		Parent = parent,
	})
end

local function tidetownFolder(): Instance?
	if mapFolder ~= nil and mapFolder.Parent ~= nil then
		return mapFolder
	end

	mapFolder = Workspace:FindFirstChild(MAP_FOLDER_NAME)

	return mapFolder
end

--[[
	Builds the whole map once. A pre-existing Tidetown folder (a
	hand-built map, or a double call) wins: nothing is added to it, and
	the accessors below simply read from whatever is there.
]]
function MapBuilder.build()
	if Workspace:FindFirstChild(MAP_FOLDER_NAME) ~= nil then
		mapFolder = Workspace:FindFirstChild(MAP_FOLDER_NAME)
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = MAP_FOLDER_NAME
	mapFolder = folder

	buildSeabed(folder)
	buildBeach(folder)
	buildBoardwalk(folder)
	buildPier(folder)
	buildTown(folder)

	for plotIndex = 1, TidetownConfig.layout.reefPlotCount do
		buildPlot(folder, plotIndex)
	end

	buildWater(folder)
	buildBorders(folder)
	buildSpawnAndRescue(folder)

	folder.Parent = Workspace
end

function MapBuilder.plotPad(plotIndex: number): BasePart?
	local folder = tidetownFolder()
	if folder == nil then
		return nil
	end

	local plotFolder = folder:FindFirstChild("Plot" .. tostring(plotIndex))
	local pad = if plotFolder ~= nil then plotFolder:FindFirstChild("Pad") else nil
	if pad ~= nil and pad:IsA("BasePart") then
		return pad
	end

	return nil
end

function MapBuilder.plotBarrier(plotIndex: number): BasePart?
	local folder = tidetownFolder()
	if folder == nil then
		return nil
	end

	local plotFolder = folder:FindFirstChild("Plot" .. tostring(plotIndex))
	local barrier = if plotFolder ~= nil then plotFolder:FindFirstChild("Barrier") else nil
	if barrier ~= nil and barrier:IsA("BasePart") then
		return barrier
	end

	return nil
end

function MapBuilder.mountStandPosition(): Vector3
	local folder = tidetownFolder()
	local stand = if folder ~= nil then folder:FindFirstChild("MountStand") else nil
	if stand ~= nil and stand:IsA("BasePart") then
		return stand.Position
	end

	return MOUNT_STAND_POSITION
end

function MapBuilder.rescuePosition(): Vector3
	return RESCUE_POSITION
end

return MapBuilder
