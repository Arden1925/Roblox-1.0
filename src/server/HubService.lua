--[[
	The Main Island: a cozy floating hub far above and behind the
	worlds, built at runtime like the rest of the map. It carries the
	landing pad, the shop stall, the travel portal, the group chest, a
	house, the prize wheel, the egg garden, the TDS town district, and
	an open sky terrace on the front quarter for viewing future islands.

	Also routes players home: tutorial graduates and returning players
	are pivoted to the pad and handed to the client's landing cutscene
	through the BeginHubLanding remote.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local GRASS_COLOR = Color3.fromRGB(126, 214, 87)
local DIRT_COLOR = Color3.fromRGB(126, 96, 68)
local ROCK_COLOR = Color3.fromRGB(120, 124, 134)
local WOOD_COLOR = Color3.fromRGB(160, 118, 70)
local PLANK_COLOR = Color3.fromRGB(196, 152, 98)
local WHITE_COLOR = Color3.fromRGB(245, 246, 250)
local GOLD_COLOR = Color3.fromRGB(253, 203, 110)
-- Portal-gun green, matching MapGenerator's world portals exactly.
local PORTAL_GREEN = Color3.fromRGB(97, 255, 66)
local ROOF_COLOR = Color3.fromRGB(214, 108, 76)
local SIGN_TEXT_COLOR = Color3.fromRGB(255, 255, 255)

local ISLAND_THICKNESS = 4
local TOWN_FOOTPRINT = 95
local EGG_HEIGHT = 4
local DECORATED_EGG_HEIGHT = 5.5

-- The client wires its landing listener during boot; this delay keeps
-- the cutscene event from firing before anyone is listening.
local WELCOME_DELAY_SECONDS = 1.2

local hub = GameConfig.hub
local CENTER = Vector3.new(hub.centerX, hub.surfaceY, hub.centerZ)
local HALF_SIZE = hub.islandSize / 2
-- The pad sits behind true center so the front quarter stays an open
-- terrace looking out at the sky.
local PAD_POSITION = CENTER + Vector3.new(0, 0, 20)
local TERRACE_EDGE_Z = CENTER.Z + HALF_SIZE

local cutsceneSeenByPlayer: { [Player]: boolean } = {}

local HubService = {}

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

local function addPrompt(part: BasePart, actionText: string, objectText: string)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
end

local function addBillboard(part: BasePart, text: string, color: Color3, offsetY: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 220, 0, 60)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 60
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.4
	label.TextSize = 18
	label.TextWrapped = true
	label.Parent = billboard
end

local function addOutline(part: BasePart, color: Color3)
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineColor = color
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = part
end

-- Decorative clones never trap the player: anchored and untouchable.
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

-- Set once in start(); every decoration below prefers a real model
-- from here and falls back to simple part-work when it is missing.
local packModelsFolder: Instance? = nil

type PropPath = { string | number }

local function naturePath(propName: string): PropPath
	return { "Low_Poly_Nature_Asset_Pack", "Low Poly Nature Asset Pack | Destiny Tech", propName }
end

local function cityPath(category: string, propName: string): PropPath
	return { "City_Asset_Pack_2026", "Models", category, propName }
end

local function findProp(path: PropPath): Instance?
	local current = packModelsFolder

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

-- A PointLight on a placed prop's highest part, so pack lampposts
-- actually light the paths at night the way the old part lamps did.
local function addTopLight(container: Model)
	local highest: BasePart? = nil
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if highest == nil or descendant.Position.Y > highest.Position.Y then
				highest = descendant
			end
		end
	end

	if highest ~= nil then
		local light = Instance.new("PointLight")
		light.Color = GOLD_COLOR
		light.Brightness = 1.4
		light.Range = 22
		light.Parent = highest
	end
end

--[[
	The one decoration entry point: clones the pack model at the path,
	scales it to the target height, and stands it bottom-down at the
	position. When the model is missing (Assets not synced, or a prop
	renamed), the optional fallback builds simple part-work at the same
	spot instead -- so the island composes identically either way, and
	upgrading any piece later means editing one path string, not
	geometry. Returns the placed model, or nil when the fallback ran.
]]
local function placeProp(
	parent: Instance,
	path: PropPath,
	position: Vector3,
	height: number,
	yaw: number?,
	fallback: ((Instance, Vector3, number) -> ())?
): Model?
	local template = findProp(path)
	if template == nil then
		if fallback ~= nil then
			fallback(parent, position, height)
		elseif packModelsFolder ~= nil then
			warn("HubService: missing prop " .. table.concat(path, "/"))
		end

		return nil
	end

	local container = Instance.new("Model")
	container.Name = template.Name

	local clone = template:Clone()
	clone.Parent = container
	makeInert(container)

	local extents = container:GetExtentsSize()
	if extents.Y < 0.05 then
		container:Destroy()
		return nil
	end

	container:PivotTo(container:GetPivot() * CFrame.Angles(0, math.rad(yaw or 0), 0))
	container:ScaleTo(height / extents.Y)

	local boxCFrame, boxSize = container:GetBoundingBox()
	local target = position + Vector3.new(0, boxSize.Y / 2, 0)
	container:PivotTo(container:GetPivot() + (target - boxCFrame.Position))
	container.Parent = parent

	return container
end

-- Fallbacks: deliberately simple, clearly placeholder shapes that keep
-- the composition intact until the matching pack model syncs in.
local function fallbackTree(parent: Instance, position: Vector3, height: number)
	createPart({
		Name = "FallbackTreeTrunk",
		Size = Vector3.new(2, height * 0.6, 2),
		Position = position + Vector3.new(0, height * 0.3, 0),
		Color = WOOD_COLOR,
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	createPart({
		Name = "FallbackTreeLeaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(height * 0.55, height * 0.5, height * 0.55),
		Position = position + Vector3.new(0, height * 0.75, 0),
		Color = Color3.fromRGB(88, 178, 78),
		Material = Enum.Material.Grass,
		CanCollide = false,
		Parent = parent,
	})
end

local function fallbackLamp(parent: Instance, position: Vector3, height: number)
	createPart({
		Name = "FallbackLampPole",
		Size = Vector3.new(0.7, height - 2, 0.7),
		Position = position + Vector3.new(0, (height - 2) / 2, 0),
		Color = Color3.fromRGB(62, 74, 96),
		Material = Enum.Material.Metal,
		CanCollide = false,
		Parent = parent,
	})
	local globe = createPart({
		Name = "FallbackLampGlobe",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2, 2, 2),
		Position = position + Vector3.new(0, height - 1, 0),
		Color = GOLD_COLOR,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = parent,
	})
	local light = Instance.new("PointLight")
	light.Color = GOLD_COLOR
	light.Brightness = 1.4
	light.Range = 22
	light.Parent = globe
end

local function fallbackBench(parent: Instance, position: Vector3, height: number)
	createPart({
		Name = "FallbackBenchSeat",
		Size = Vector3.new(8, 0.8, 2.4),
		Position = position + Vector3.new(0, height * 0.5, 0),
		Color = PLANK_COLOR,
		Material = Enum.Material.WoodPlanks,
		Parent = parent,
	})
	for _, legOffset in ipairs({ -3.2, 3.2 }) do
		createPart({
			Name = "FallbackBenchLeg",
			Size = Vector3.new(0.8, height * 0.5, 2.2),
			Position = position + Vector3.new(legOffset, height * 0.25, 0),
			Color = WOOD_COLOR,
			Material = Enum.Material.Wood,
			CanCollide = false,
			Parent = parent,
		})
	end
end

-- A cobbled walking path between two ground points: one rotated slab,
-- slightly proud of the grass so routes read from the air.
local function buildPath(parent: Instance, fromOffset: Vector3, toOffset: Vector3, width: number)
	local fromPosition = CENTER + fromOffset
	local toPosition = CENTER + toOffset
	local span = toPosition - fromPosition
	local length = span.Magnitude
	if length < 1 then
		return
	end

	local midpoint = fromPosition + span / 2 + Vector3.new(0, 0.12, 0)
	createPart({
		Name = "HubPath",
		Size = Vector3.new(width, 0.25, length),
		CFrame = CFrame.lookAt(midpoint, midpoint + span),
		Color = Color3.fromRGB(178, 168, 152),
		Material = Enum.Material.Cobblestone,
		CanCollide = false,
		Parent = parent,
	})
end

local function buildBase(parent: Instance)
	createPart({
		Name = "IslandGrass",
		Size = Vector3.new(hub.islandSize, ISLAND_THICKNESS, hub.islandSize),
		Position = CENTER - Vector3.new(0, ISLAND_THICKNESS / 2, 0),
		Color = GRASS_COLOR,
		Material = Enum.Material.Grass,
		Parent = parent,
	})

	-- The floating-island silhouette: dirt, then shrinking rock shelves.
	createPart({
		Name = "IslandDirt",
		Size = Vector3.new(hub.islandSize - 40, 26, hub.islandSize - 40),
		Position = CENTER - Vector3.new(0, ISLAND_THICKNESS + 13, 0),
		Color = DIRT_COLOR,
		Material = Enum.Material.Ground,
		Parent = parent,
	})

	for shelfIndex, shelf in ipairs({
		{ size = 180, height = 22, drop = 41 },
		{ size = 110, height = 18, drop = 61 },
		{ size = 50, height = 16, drop = 78 },
	}) do
		createPart({
			Name = "IslandRock" .. shelfIndex,
			Size = Vector3.new(shelf.size, shelf.height, shelf.size),
			Position = CENTER - Vector3.new(0, shelf.drop, 0),
			Color = ROCK_COLOR,
			Material = Enum.Material.Slate,
			Parent = parent,
		})
	end

	-- Picket fence on the three closed sides; the terrace side stays
	-- open so nothing blocks the view.
	for _, edge in ipairs({
		{
			center = CENTER + Vector3.new(0, 2.2, -HALF_SIZE + 1),
			size = Vector3.new(hub.islandSize, 0.6, 0.6),
		},
		{
			center = CENTER + Vector3.new(-HALF_SIZE + 1, 2.2, 0),
			size = Vector3.new(0.6, 0.6, hub.islandSize),
		},
		{
			center = CENTER + Vector3.new(HALF_SIZE - 1, 2.2, 0),
			size = Vector3.new(0.6, 0.6, hub.islandSize),
		},
	}) do
		createPart({
			Name = "FenceRail",
			Size = edge.size,
			Position = edge.center,
			Color = WHITE_COLOR,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = parent,
		})
		createPart({
			Name = "FenceRailLow",
			Size = edge.size,
			Position = edge.center - Vector3.new(0, 1.1, 0),
			Color = WHITE_COLOR,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = parent,
		})
	end

	for postOffset = -HALF_SIZE + 2, HALF_SIZE - 2, 12 do
		for _, postPosition in ipairs({
			CENTER + Vector3.new(postOffset, 1.5, -HALF_SIZE + 1),
			CENTER + Vector3.new(-HALF_SIZE + 1, 1.5, postOffset),
			CENTER + Vector3.new(HALF_SIZE - 1, 1.5, postOffset),
		}) do
			createPart({
				Name = "FencePost",
				Size = Vector3.new(0.8, 3, 0.8),
				Position = postPosition,
				Color = WHITE_COLOR,
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				Parent = parent,
			})
		end
	end

	-- The stone plaza ring around the landing pad: the island's heart,
	-- with cobbled paths running out to every district so the layout
	-- reads as a village green instead of a bare plain.
	createPart({
		Name = "PlazaRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 58, 58),
		CFrame = CFrame.new(PAD_POSITION + Vector3.new(0, 0.12, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(196, 188, 172),
		Material = Enum.Material.Cobblestone,
		CanCollide = false,
		Parent = parent,
	})

	local padOffset = PAD_POSITION - CENTER
	for _, pathSpec in ipairs({
		{ target = Vector3.new(0, 0, 80), width = 8 }, -- portal gate
		{ target = Vector3.new(-118, 0, 55), width = 6 }, -- prize wheel
		{ target = Vector3.new(-45, 0, 75), width = 6 }, -- shop stall
		{ target = Vector3.new(28, 0, 62), width = 5 }, -- group chest
		{ target = Vector3.new(62, 0, -95), width = 6 }, -- house
		{ target = Vector3.new(-85, 0, -40), width = 6 }, -- town
		{ target = Vector3.new(85, 0, -55), width = 6 }, -- egg garden
		{ target = Vector3.new(0, 0, 110), width = 10 }, -- terrace
	}) do
		buildPath(parent, padOffset, pathSpec.target, pathSpec.width)
	end

	-- Streetlamps from the city pack light the path junctions.
	for lampIndex, lampOffset in ipairs({
		Vector3.new(-25, 0, 45),
		Vector3.new(25, 0, 45),
		Vector3.new(-35, 0, -10),
		Vector3.new(35, 0, -10),
		Vector3.new(0, 0, -60),
		Vector3.new(-90, 0, 60),
	}) do
		local lampName = if lampIndex % 2 == 0 then "Round Street Lamp 1" else "Street Lamp 1"
		local lamp = placeProp(
			parent,
			cityPath("City Lamps", lampName),
			CENTER + lampOffset,
			10,
			lampIndex * 60,
			fallbackLamp
		)
		if lamp ~= nil then
			addTopLight(lamp)
		end
	end

	-- A tree line from the nature pack: varied species around the
	-- districts, denser toward the back edge.
	for _, treeSpec in ipairs({
		{ offset = Vector3.new(-45, 0, 62), prop = "Tree", height = 12 },
		{ offset = Vector3.new(52, 0, 66), prop = "Birch Tree", height = 12 },
		{ offset = Vector3.new(-115, 0, -20), prop = "Tall Pine Tree", height = 15 },
		{ offset = Vector3.new(115, 0, 10), prop = "Tall Tree", height = 14 },
		{ offset = Vector3.new(24, 0, -95), prop = "Double Tree", height = 13 },
		{ offset = Vector3.new(-120, 0, 95), prop = "Pine Tree", height = 12 },
		{ offset = Vector3.new(120, 0, 88), prop = "Tree 2", height = 11 },
		{ offset = Vector3.new(-40, 0, -125), prop = "Tall Pine Tree 2", height = 15 },
		{ offset = Vector3.new(118, 0, -95), prop = "Squared Tree", height = 11 },
	}) do
		placeProp(
			parent,
			naturePath(treeSpec.prop),
			CENTER + treeSpec.offset,
			treeSpec.height,
			(treeSpec.offset.X + treeSpec.offset.Z) * 7,
			fallbackTree
		)
	end

	-- The great tree: one oversized landmark between the districts, a
	-- meeting spot you can see from anywhere on the island.
	local greatTree = placeProp(
		parent,
		naturePath("Rooted Tree"),
		CENTER + Vector3.new(0, 0, -95),
		26,
		0,
		fallbackTree
	)
	if greatTree ~= nil then
		local trunk = greatTree:FindFirstChildWhichIsA("BasePart", true)
		if trunk ~= nil then
			addBillboard(trunk, "THE GREAT TREE", GRASS_COLOR, 20)
		end
	end

	-- Understory: bushes, flowers, and rocks scattered off the paths so
	-- the grass never reads as empty.
	for scatterIndex, scatterSpec in ipairs({
		{ offset = Vector3.new(-60, 0, 20), prop = "Bush", height = 3 },
		{ offset = Vector3.new(58, 0, 24), prop = "Bush 2", height = 3 },
		{ offset = Vector3.new(-18, 0, -40), prop = "Flower 2", height = 2 },
		{ offset = Vector3.new(20, 0, -36), prop = "Flower 5", height = 2 },
		{ offset = Vector3.new(-95, 0, 20), prop = "Big Rock", height = 4 },
		{ offset = Vector3.new(96, 0, 40), prop = "Rock 1", height = 3 },
		{ offset = Vector3.new(44, 0, -60), prop = "Tall Bush Flower", height = 3.5 },
		{ offset = Vector3.new(-52, 0, -78), prop = "Mushroom", height = 2.5 },
		{ offset = Vector3.new(12, 0, 96), prop = "Flower 8", height = 2 },
		{ offset = Vector3.new(-14, 0, 98), prop = "Flower 4", height = 2 },
		{ offset = Vector3.new(70, 0, 8), prop = "Round Plant", height = 2.5 },
		{ offset = Vector3.new(-70, 0, 8), prop = "Plant", height = 2.5 },
	}) do
		placeProp(
			parent,
			naturePath(scatterSpec.prop),
			CENTER + scatterSpec.offset,
			scatterSpec.height,
			scatterIndex * 47
		)
	end
end

local function buildLandingPad(parent: Instance)
	local pad = createPart({
		Name = "LandingPad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 18, 18),
		CFrame = CFrame.new(PAD_POSITION + Vector3.new(0, 0.5, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = WHITE_COLOR,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	addBillboard(pad, "MAIN ISLAND", GOLD_COLOR, 10)

	createPart({
		Name = "LandingPadRim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 20, 20),
		CFrame = CFrame.new(PAD_POSITION + Vector3.new(0, 0.2, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = GOLD_COLOR,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = parent,
	})

	for starIndex = 1, 8 do
		local angle = starIndex / 8 * math.pi * 2
		createPart({
			Name = "PadStud" .. starIndex,
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.2, 1.2, 1.2),
			Position = PAD_POSITION + Vector3.new(math.cos(angle) * 11, 1.2, math.sin(angle) * 11),
			Color = GOLD_COLOR,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = parent,
		})
	end
end

local function buildTerrace(parent: Instance)
	-- The open quarter: a deck along the whole front edge, pointed at
	-- the sky where the later islands and parkours will hang.
	createPart({
		Name = "TerraceDeck",
		Size = Vector3.new(hub.islandSize - 4, 0.6, 70),
		Position = Vector3.new(CENTER.X, hub.surfaceY + 0.3, TERRACE_EDGE_Z - 36),
		Color = PLANK_COLOR,
		Material = Enum.Material.WoodPlanks,
		Parent = parent,
	})

	createPart({
		Name = "TerraceRail",
		Size = Vector3.new(hub.islandSize - 4, 0.8, 0.8),
		Position = Vector3.new(CENTER.X, hub.surfaceY + 3.4, TERRACE_EDGE_Z - 2),
		Color = WOOD_COLOR,
		Material = Enum.Material.Wood,
		CanCollide = false,
		Parent = parent,
	})

	for postOffset = -HALF_SIZE + 4, HALF_SIZE - 4, 10 do
		createPart({
			Name = "TerracePost",
			Size = Vector3.new(0.9, 3.6, 0.9),
			Position = Vector3.new(CENTER.X + postOffset, hub.surfaceY + 1.8, TERRACE_EDGE_Z - 2),
			Color = WOOD_COLOR,
			Material = Enum.Material.Wood,
			CanCollide = false,
			Parent = parent,
		})
	end

	-- Real benches from the city pack face the view; a parasol cafe
	-- corner anchors the west end of the deck.
	for benchIndex, benchOffset in ipairs({ -60, -20, 20, 60 }) do
		local benchName = if benchIndex % 2 == 0 then "Wooden Bench 1" else "Bench 2"
		placeProp(
			parent,
			cityPath("Benches & Picnic", benchName),
			Vector3.new(CENTER.X + benchOffset, hub.surfaceY + 0.6, TERRACE_EDGE_Z - 10),
			3,
			180,
			fallbackBench
		)
	end

	placeProp(
		parent,
		cityPath("Restaurant Related", "Outside Parasol Table"),
		Vector3.new(CENTER.X - 80, hub.surfaceY + 0.6, TERRACE_EDGE_Z - 18),
		7,
		30
	)
	placeProp(
		parent,
		cityPath("Benches & Picnic", "Picnic Table"),
		Vector3.new(CENTER.X + 82, hub.surfaceY + 0.6, TERRACE_EDGE_Z - 18),
		3.5,
		-25
	)

	-- Telescopes sell the "look out there" idea even before the other
	-- islands exist.
	for _, scopeOffset in ipairs({ -40, 40 }) do
		local base = Vector3.new(CENTER.X + scopeOffset, hub.surfaceY, TERRACE_EDGE_Z - 6)
		createPart({
			Name = "TelescopeStand",
			Size = Vector3.new(0.8, 3.4, 0.8),
			Position = base + Vector3.new(0, 1.7, 0),
			Color = Color3.fromRGB(62, 74, 96),
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = parent,
		})
		createPart({
			Name = "TelescopeTube",
			Size = Vector3.new(0.9, 0.9, 3.2),
			CFrame = CFrame.new(base + Vector3.new(0, 3.8, 0)) * CFrame.Angles(math.rad(20), 0, 0),
			Color = GOLD_COLOR,
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = parent,
		})
	end

	local viewSign = createPart({
		Name = "ViewSign",
		Size = Vector3.new(10, 3, 0.5),
		Position = Vector3.new(CENTER.X, hub.surfaceY + 5, TERRACE_EDGE_Z - 20),
		Color = WOOD_COLOR,
		Material = Enum.Material.Wood,
		CanCollide = false,
		Parent = parent,
	})
	addBillboard(viewSign, "NEW ISLANDS & PARKOURS COMING SOON...", SIGN_TEXT_COLOR, 3)
	createPart({
		Name = "ViewSignPost",
		Size = Vector3.new(0.8, 5, 0.8),
		Position = Vector3.new(CENTER.X, hub.surfaceY + 2.5, TERRACE_EDGE_Z - 20),
		Color = WOOD_COLOR,
		Material = Enum.Material.Wood,
		CanCollide = false,
		Parent = parent,
	})
end

local function buildPortal(parent: Instance)
	local base = PAD_POSITION + Vector3.new(0, 0, 60)

	for _, pillarOffset in ipairs({ -8, 8 }) do
		createPart({
			Name = "PortalPillar",
			Size = Vector3.new(2, 15, 2),
			Position = base + Vector3.new(pillarOffset, 7.5, 0),
			Color = Color3.fromRGB(62, 74, 96),
			Material = Enum.Material.Slate,
			Parent = parent,
		})
	end

	createPart({
		Name = "PortalArch",
		Size = Vector3.new(20, 2, 2),
		Position = base + Vector3.new(0, 16, 0),
		Color = Color3.fromRGB(62, 74, 96),
		Material = Enum.Material.Slate,
		Parent = parent,
	})

	--[[
		One green disc, same orientation convention as the world
		portals: the cylinder's flat axis faces the walker. PortalFx
		spins its swirl rings around that axis, so the old unrotated
		block put three giant rings sideways THROUGH the arch -- the
		"extra portals" mess. Matching the convention gives a single
		coherent green portal.
	]]
	local swirl = createPart({
		Name = "Portal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 13, 13),
		CFrame = CFrame.new(base + Vector3.new(0, 7.5, 0)) * CFrame.Angles(0, math.rad(90), 0),
		Color = PORTAL_GREEN,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		CanCollide = false,
		Parent = parent,
	})
	swirl:SetAttribute("WorldIndex", 1)
	addPrompt(swirl, "Travel", "Portal")
	addBillboard(swirl, "PORTAL -- TRAVEL TO THE WORLDS!", PORTAL_GREEN, 9)
	addOutline(swirl, Color3.fromRGB(160, 255, 130))
	CollectionService:AddTag(swirl, "Portal")
end

local function buildShopStall(parent: Instance)
	local base = CENTER + Vector3.new(-45, 0, 75)

	local counter = createPart({
		Name = "ShopCounter",
		Size = Vector3.new(10, 3.4, 3),
		Position = base + Vector3.new(0, 1.7, 0),
		Color = WOOD_COLOR,
		Material = Enum.Material.Wood,
		Parent = parent,
	})

	for _, postOffset in ipairs({ -4.6, 4.6 }) do
		createPart({
			Name = "ShopPost",
			Size = Vector3.new(0.8, 8, 0.8),
			Position = base + Vector3.new(postOffset, 4, 0),
			Color = WHITE_COLOR,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = parent,
		})
	end

	-- Striped awning: alternating slabs beat a texture upload.
	for stripeIndex = 0, 4 do
		createPart({
			Name = "ShopAwning",
			Size = Vector3.new(2.2, 0.4, 5),
			CFrame = CFrame.new(base + Vector3.new(-4.4 + stripeIndex * 2.2, 8.4, -0.6))
				* CFrame.Angles(math.rad(-12), 0, 0),
			Color = if stripeIndex % 2 == 0 then Color3.fromRGB(235, 69, 44) else WHITE_COLOR,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = parent,
		})
	end

	counter:SetAttribute("WorldIndex", 1)
	addPrompt(counter, "Shop", "Island Shop")
	addBillboard(counter, "SHOP -- POTIONS & UPGRADES!", GOLD_COLOR, 7)
	addOutline(counter, GOLD_COLOR)
	CollectionService:AddTag(counter, "ShopStation")

	-- A little cafe spill-out beside the stall.
	placeProp(parent, cityPath("Restaurant Related", "Table"), base + Vector3.new(10, 0, 4), 3, 15)
	for chairIndex, chairOffset in ipairs({ Vector3.new(13, 0, 4), Vector3.new(7, 0, 7) }) do
		placeProp(
			parent,
			cityPath("Restaurant Related", "Restaurant Chair"),
			base + chairOffset,
			2.6,
			chairIndex * 140
		)
	end
	placeProp(parent, naturePath("Potted Plant"), base + Vector3.new(-7, 0, 3), 2.5, 0)
end

local function buildGroupChest(parent: Instance)
	local center = CENTER + Vector3.new(28, 0, 62)

	local body = createPart({
		Name = "GroupChest",
		Size = Vector3.new(5, 3, 3.4),
		Position = center + Vector3.new(0, 1.5, 0),
		Color = Color3.fromRGB(110, 80, 48),
		Material = Enum.Material.Wood,
		Parent = parent,
	})

	createPart({
		Name = "ChestLid",
		Size = Vector3.new(5.2, 1.4, 3.6),
		CFrame = CFrame.new(center + Vector3.new(0, 3.4, -0.4))
			* CFrame.Angles(math.rad(-18), 0, 0),
		Color = Color3.fromRGB(96, 68, 38),
		Material = Enum.Material.Wood,
		Parent = parent,
	})

	for _, bandX in ipairs({ -1.6, 1.6 }) do
		createPart({
			Name = "ChestBand",
			Size = Vector3.new(0.5, 3.2, 3.6),
			Position = center + Vector3.new(bandX, 1.5, 0),
			Color = GOLD_COLOR,
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = parent,
		})
	end

	addPrompt(body, "Claim Group Reward", "Group Chest")
	addBillboard(body, "GROUP REWARD -- JOIN & LIKE!", GOLD_COLOR, 6)
	addOutline(body, GOLD_COLOR)
	CollectionService:AddTag(body, "GroupChest")
end

local function buildHouse(parent: Instance)
	local base = CENTER + Vector3.new(62, 0, -110)
	local wallHeight = 9

	createPart({
		Name = "HouseFloor",
		Size = Vector3.new(26, 1, 22),
		Position = base + Vector3.new(0, 0.5, 0),
		Color = PLANK_COLOR,
		Material = Enum.Material.WoodPlanks,
		Parent = parent,
	})

	-- Back and side walls solid; the front wall leaves a doorway facing
	-- the plaza.
	createPart({
		Name = "HouseWallBack",
		Size = Vector3.new(26, wallHeight, 1),
		Position = base + Vector3.new(0, wallHeight / 2 + 1, -10.5),
		Color = WHITE_COLOR,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	for _, sideX in ipairs({ -12.5, 12.5 }) do
		createPart({
			Name = "HouseWallSide",
			Size = Vector3.new(1, wallHeight, 22),
			Position = base + Vector3.new(sideX, wallHeight / 2 + 1, 0),
			Color = WHITE_COLOR,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
	end
	for _, frontPiece in ipairs({
		{ x = -8.25, width = 9.5 },
		{ x = 8.25, width = 9.5 },
	}) do
		createPart({
			Name = "HouseWallFront",
			Size = Vector3.new(frontPiece.width, wallHeight, 1),
			Position = base + Vector3.new(frontPiece.x, wallHeight / 2 + 1, 10.5),
			Color = WHITE_COLOR,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
	end
	createPart({
		Name = "HouseDoorTop",
		Size = Vector3.new(7, 2.4, 1),
		Position = base + Vector3.new(0, wallHeight - 0.2, 10.5),
		Color = WHITE_COLOR,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})

	-- Two tilted slabs meet at the ridge for a cartoon roof.
	for _, roofSide in ipairs({ -1, 1 }) do
		createPart({
			Name = "HouseRoof",
			Size = Vector3.new(28, 0.8, 13.4),
			CFrame = CFrame.new(base + Vector3.new(0, wallHeight + 3.6, roofSide * 5.8))
				* CFrame.Angles(math.rad(roofSide * 28), 0, 0),
			Color = ROOF_COLOR,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
	end

	createPart({
		Name = "HouseChimney",
		Size = Vector3.new(2, 5, 2),
		Position = base + Vector3.new(8, wallHeight + 5, -5),
		Color = ROCK_COLOR,
		Material = Enum.Material.Brick,
		CanCollide = false,
		Parent = parent,
	})

	-- Cozy interior: rug, bench, table with a lamp.
	createPart({
		Name = "HouseRug",
		Size = Vector3.new(9, 0.2, 6),
		Position = base + Vector3.new(0, 1.1, 1),
		Color = Color3.fromRGB(232, 67, 147),
		Material = Enum.Material.Fabric,
		CanCollide = false,
		Parent = parent,
	})
	createPart({
		Name = "HouseBench",
		Size = Vector3.new(7, 1.6, 2.4),
		Position = base + Vector3.new(-6, 1.8, -6),
		Color = PLANK_COLOR,
		Material = Enum.Material.WoodPlanks,
		Parent = parent,
	})
	local table = createPart({
		Name = "HouseTable",
		Size = Vector3.new(4, 2.4, 4),
		Position = base + Vector3.new(6, 2.2, -5),
		Color = WOOD_COLOR,
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	local lamp = createPart({
		Name = "HouseLamp",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.4, 1.4, 1.4),
		Position = table.Position + Vector3.new(0, 2, 0),
		Color = GOLD_COLOR,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = parent,
	})
	local light = Instance.new("PointLight")
	light.Color = GOLD_COLOR
	light.Brightness = 1.2
	light.Range = 16
	light.Parent = lamp

	addBillboard(table, "COZY CORNER -- TAKE A BREAK!", SIGN_TEXT_COLOR, 6)

	-- A front garden so the house sits in the island instead of on it.
	placeProp(parent, naturePath("Flower 6"), base + Vector3.new(-9, 0, 13), 2, 0)
	placeProp(parent, naturePath("Flower 10"), base + Vector3.new(9, 0, 13), 2, 90)
	placeProp(parent, naturePath("Bush"), base + Vector3.new(-15, 0, 8), 3, 40)
	placeProp(parent, naturePath("Tall Bush Flower 2"), base + Vector3.new(16, 0, 6), 3.5, -30)
	placeProp(
		parent,
		naturePath("Birch Tree"),
		base + Vector3.new(-20, 0, -6),
		13,
		70,
		fallbackTree
	)
end

local function buildWheel(parent: Instance)
	-- West-front lawn: the old spot at (-70, -50) sat inside the town
	-- district's footprint, which only showed once the packs synced.
	local base = CENTER + Vector3.new(-118, 0, 55)
	local hubHeight = 11

	for _, postOffset in ipairs({ -2.4, 2.4 }) do
		createPart({
			Name = "WheelPost",
			Size = Vector3.new(1.4, hubHeight + 2, 1.4),
			Position = base + Vector3.new(0, (hubHeight + 2) / 2, postOffset),
			Color = WOOD_COLOR,
			Material = Enum.Material.Wood,
			Parent = parent,
		})
	end

	local disc = createPart({
		Name = "WheelDisc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 18, 18),
		CFrame = CFrame.new(base + Vector3.new(0, hubHeight, 0)),
		Color = WHITE_COLOR,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})

	-- One colored spoke per reward, so the in-world wheel mirrors the
	-- window's bubble order.
	for rewardIndex, reward in ipairs(GameConfig.wheel.rewards) do
		local angle = (rewardIndex - 1) / #GameConfig.wheel.rewards * math.pi * 2
		createPart({
			Name = "WheelSpoke" .. rewardIndex,
			Size = Vector3.new(0.4, 1.6, 7),
			CFrame = CFrame.new(base + Vector3.new(1.1, hubHeight, 0))
				* CFrame.Angles(angle, 0, 0)
				* CFrame.new(0, 0, -4.5),
			Color = Color3.fromRGB(reward.color[1], reward.color[2], reward.color[3]),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = parent,
		})
	end

	createPart({
		Name = "WheelPointer",
		Size = Vector3.new(1, 2.6, 1),
		CFrame = CFrame.new(base + Vector3.new(1.1, hubHeight + 10, 0))
			* CFrame.Angles(0, 0, math.rad(45)),
		Color = Color3.fromRGB(235, 69, 44),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = parent,
	})

	addPrompt(disc, "Spin", "Prize Wheel")
	addBillboard(disc, "DAILY PRIZE WHEEL -- FREE SPIN EVERY DAY!", GOLD_COLOR, 12)
	addOutline(disc, GOLD_COLOR)
	CollectionService:AddTag(disc, "SpinWheel")
end

local function buildSigns(parent: Instance)
	for _, signSpec in ipairs({
		{
			offset = Vector3.new(-14, 0, 34),
			text = "STAND ON GREEN PADS TO GROW -- BIG BODIES OPEN GATES!",
		},
		{
			offset = Vector3.new(14, 0, 34),
			text = "HATCH PETS & SPIN THE WHEEL -- BONUSES STACK FOREVER!",
		},
	}) do
		local base = CENTER + signSpec.offset
		createPart({
			Name = "InfoSignPost",
			Size = Vector3.new(0.8, 4.4, 0.8),
			Position = base + Vector3.new(0, 2.2, 0),
			Color = WOOD_COLOR,
			Material = Enum.Material.Wood,
			CanCollide = false,
			Parent = parent,
		})
		local board = createPart({
			Name = "InfoSignBoard",
			Size = Vector3.new(8, 2.6, 0.5),
			Position = base + Vector3.new(0, 5.2, 0),
			Color = PLANK_COLOR,
			Material = Enum.Material.WoodPlanks,
			CanCollide = false,
			Parent = parent,
		})
		addBillboard(board, signSpec.text, SIGN_TEXT_COLOR, 2.6)
	end
end

local function placeTown(parent: Instance, modelsFolder: Instance)
	local pack = modelsFolder:FindFirstChild("Tds_Town_Pack")
	local template = if pack ~= nil then pack:FindFirstChild("Scenery") else nil
	if template == nil or not template:IsA("Model") then
		warn("Hub town pack missing; skipping the town district")
		return
	end

	local town = template:Clone()
	makeInert(town)

	local extents = town:GetExtentsSize()
	local footprint = math.max(extents.X, extents.Z)
	if footprint < 1 then
		town:Destroy()
		return
	end

	town:ScaleTo(TOWN_FOOTPRINT / footprint)

	local boxCFrame, boxSize = town:GetBoundingBox()
	local target = CENTER + Vector3.new(-85, boxSize.Y / 2, -40)
	town:PivotTo(town:GetPivot() + (target - boxCFrame.Position))
	town.Name = "TownDistrict"
	town.Parent = parent
end

local function placeEggGarden(parent: Instance, modelsFolder: Instance)
	local pack = modelsFolder:FindFirstChild("Classic_Studs_Eggs_Pack")
	if pack == nil then
		warn("Hub eggs pack missing; skipping the egg garden")
		return
	end

	local garden = Instance.new("Folder")
	garden.Name = "EggGarden"
	garden.Parent = parent

	local gardenCenter = CENTER + Vector3.new(85, 0, -55)

	-- Arcs open toward the plaza: decorated showpieces inside, the
	-- plain collection curving around them.
	local ringSpecs = {
		{ folderName = "Decoration", radius = 20, height = DECORATED_EGG_HEIGHT },
		{ folderName = "Models", radius = 31, height = EGG_HEIGHT },
		{ folderName = "Models", radius = 41, height = EGG_HEIGHT, secondHalf = true },
	}

	for _, ringSpec in ipairs(ringSpecs) do
		local folder = pack:FindFirstChild(ringSpec.folderName)
		if folder == nil then
			continue
		end

		local children = folder:GetChildren()
		local firstIndex = 1
		local lastIndex = #children
		if ringSpec.folderName == "Models" then
			local half = math.ceil(#children / 2)
			if ringSpec.secondHalf then
				firstIndex = half + 1
			else
				lastIndex = half
			end
		end

		local count = lastIndex - firstIndex + 1
		if count < 1 then
			continue
		end

		for arcIndex = 0, count - 1 do
			local template = children[firstIndex + arcIndex]
			-- 300 degrees of arc, opening toward the landing pad.
			local angle = math.rad(120 + arcIndex / math.max(count - 1, 1) * 300)
			local position = gardenCenter
				+ Vector3.new(
					math.cos(angle) * ringSpec.radius,
					0,
					math.sin(angle) * ringSpec.radius
				)

			local container = Instance.new("Model")
			container.Name = template.Name
			local clone = template:Clone()
			clone.Parent = container
			makeInert(container)

			local extents = container:GetExtentsSize()
			if extents.Y < 0.05 then
				container:Destroy()
				continue
			end

			container:ScaleTo(ringSpec.height / extents.Y)

			local boxCFrame, boxSize = container:GetBoundingBox()
			local target = position + Vector3.new(0, boxSize.Y / 2, 0)
			container:PivotTo(container:GetPivot() + (target - boxCFrame.Position))
			container.Parent = garden
		end
	end

	local gardenSign = createPart({
		Name = "EggGardenSign",
		Size = Vector3.new(9, 2.8, 0.5),
		Position = gardenCenter + Vector3.new(0, 5, 24),
		Color = PLANK_COLOR,
		Material = Enum.Material.WoodPlanks,
		CanCollide = false,
		Parent = garden,
	})
	addBillboard(gardenSign, "THE EGG GARDEN -- EVERY EGG EVER!", GOLD_COLOR, 2.6)
end

-- Pivot a player's character onto the pad; the client cutscene lifts
-- them into the sky itself, so no one can fall out of the world here.
local function placeAtPad(player: Player): boolean
	local character = player.Character
	if character == nil then
		return false
	end

	character:PivotTo(CFrame.new(PAD_POSITION + Vector3.new(0, 4, 0)))

	return true
end

function HubService.landingPosition(): Vector3
	return PAD_POSITION + Vector3.new(0, 4, 0)
end

--[[
	Sends a player home. The first hub arrival each session plays the
	full winged landing cutscene; later arrivals just appear on the pad.
]]
function HubService.sendToHub(player: Player)
	if not placeAtPad(player) then
		return
	end

	if cutsceneSeenByPlayer[player] then
		return
	end
	cutsceneSeenByPlayer[player] = true

	local beginHubLanding = Remotes.get("BeginHubLanding") :: RemoteEvent
	beginHubLanding:FireClient(player, HubService.landingPosition())
end

--[[
	Join flow for players who already finished the tutorial: wait out
	the character spawn plus CheckpointService's deferred placement,
	then run the landing.
]]
function HubService.welcome(player: Player)
	task.spawn(function()
		local character = player.Character
		if character == nil then
			character = player.CharacterAdded:Wait()
		end

		task.wait(WELCOME_DELAY_SECONDS)
		if player.Parent ~= nil and character == player.Character then
			HubService.sendToHub(player)
		end
	end)
end

function HubService.removePlayer(player: Player)
	cutsceneSeenByPlayer[player] = nil
end

function HubService.start()
	if Workspace:FindFirstChild("HubIsland") ~= nil then
		return
	end

	-- Resolve the pack folder first: every build below places real
	-- models through placeProp when it exists, and falls back to
	-- placeholder part-work when it does not.
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local modelsFolder = if assetsFolder ~= nil then assetsFolder:FindFirstChild("Models") else nil
	packModelsFolder = modelsFolder
	if modelsFolder == nil then
		warn("ReplicatedStorage.Assets.Models missing; hub builds with placeholder props")
	end

	local hubFolder = Instance.new("Folder")
	hubFolder.Name = "HubIsland"

	buildBase(hubFolder)
	buildLandingPad(hubFolder)
	buildTerrace(hubFolder)
	buildPortal(hubFolder)
	buildShopStall(hubFolder)
	buildGroupChest(hubFolder)
	buildHouse(hubFolder)
	buildWheel(hubFolder)
	buildSigns(hubFolder)

	if modelsFolder ~= nil then
		placeTown(hubFolder, modelsFolder)
		placeEggGarden(hubFolder, modelsFolder)
	end

	hubFolder.Parent = Workspace
end

return HubService
