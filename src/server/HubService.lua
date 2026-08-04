--[[
	The Main Island, rebuilt as the World Tree Isle: a large organic
	floating island sculpted from smooth terrain, three walkable tiers
	high. The bought TDS town sits ON the island's mid tier with its
	real wall gaps as gates; a colossal World Tree crowns the high
	tier; a river steps down from its spring pond into a lagoon that
	drains through the sky-well, a waterfall falling straight through
	the island into open sky. A sandy cove fronts the low tier, a
	crystal grotto hides in the rock beneath it, and rope bridges
	reach three satellite isles: the portal ring, the carnival wheel,
	and the balloon dock. A sky whale patrols a slow orbit around it
	all.

	Every decoration goes through placeProp: real pack models when
	ReplicatedStorage.Assets.Models is present, deliberately simple
	placeholder part-work when it is not, so the island composes
	identically either way and any prop upgrades by editing one path.

	The previous separate TDS island (buildTdsIsland) is preserved
	verbatim below and gated behind GameConfig.tdsIsland.enabled, so
	that design can come back by flipping one flag.

	Also routes players home: tutorial graduates and returning players
	are pivoted to the pad and handed to the client's landing cutscene
	through the BeginHubLanding remote.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local ROPE_COLOR = Color3.fromRGB(133, 100, 60)
local WATERFALL_COLOR = Color3.fromRGB(120, 196, 226)
local CRYSTAL_COLOR = Color3.fromRGB(180, 140, 232)
local SIGN_TEXT_COLOR = Color3.fromRGB(255, 255, 255)
-- Portal-gun green, matching MapGenerator's world portals exactly.
local PORTAL_GREEN = Color3.fromRGB(97, 255, 66)

-- The terrain grass is tinted between the game's bright cartoon green
-- and the TDS town's darker authored greens, so the town's own ground
-- blends into the island instead of sitting on it like a sticker.
local TERRAIN_GRASS = Color3.fromRGB(96, 168, 62)
local TERRAIN_WATER = Color3.fromRGB(70, 160, 200)

local ISLAND_THICKNESS = 4

-- Tier heights above hub.surfaceY. The town tier and high tier are
-- terrain plateaus; the deck rides the World Tree's trunk.
local TIER_MID = 12
local TIER_HIGH = 26
local TIER_DECK = 48

-- The client wires its landing listener during boot; this delay keeps
-- the cutscene event from firing before anyone is listening.
local WELCOME_DELAY_SECONDS = 1.2

local hub = GameConfig.hub
local CENTER = Vector3.new(hub.centerX, hub.surfaceY, hub.centerZ)

-- The spawn plaza sits on the low tier's west side; the landing pad is
-- its centerpiece and the cutscene target.
local PAD_POSITION = CENTER + Vector3.new(-90, 0, 95)

-- Anchor points the layout hangs off. Front of the island is +Z.
local TREE_BASE = CENTER + Vector3.new(-140, TIER_HIGH, -135)
local TOWN_CENTER = CENTER + Vector3.new(55, TIER_MID, -70)
local LAGOON_CENTER = CENTER + Vector3.new(30, 0, 70)
local LAGOON_RADIUS = 48
local HATCHERY_CENTER = CENTER + Vector3.new(150, 0, 120)
local GROTTO_CENTER = CENTER + Vector3.new(-60, -16, 150)
local PORTAL_ISLE = CENTER + Vector3.new(-60, -8, 330)
local CARNIVAL_ISLE = CENTER + Vector3.new(-300, 4, 60)
local BALLOON_ISLE = CENTER + Vector3.new(285, 16, -150)

local cutsceneSeenByPlayer: { [Player]: boolean } = {}

-- Deterministic scatter: the island looks identical on every server.
local rng = Random.new(7)

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
	billboard.MaxDistance = 80
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

-- A small glowing particle source: fireflies at the tree, dust motes
-- in the grotto, sparkle under the hatchery dome.
local function addGlowMotes(parent: Instance, position: Vector3, color: Color3, spread: number)
	local emitterHost = createPart({
		Name = "GlowMotes",
		Size = Vector3.new(spread, spread, spread),
		Position = position,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Parent = parent,
	})

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0.2)
	emitter.Lifetime = NumberRange.new(2.5, 4)
	emitter.Rate = 3
	emitter.Speed = NumberRange.new(0.4, 1)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = emitterHost
end

-- Set once in start(); every decoration below prefers a real model
-- from here and falls back to simple part-work when it is missing.
local packModelsFolder: Instance? = nil

type PropPath = { string | number }

local function naturePath(propName: string): PropPath
	return { "Low_Poly_Nature_Asset_Pack", "Low Poly Nature Asset Pack | Destiny Tech", propName }
end

local function bundlePath(folderName: string, index: number): PropPath
	return { "Nature_Pack_Bundle", folderName, index }
end

local function cityPath(category: string, propName: string): PropPath
	return { "City_Asset_Pack_2026", "Models", category, propName }
end

local function beachPath(propName: string): PropPath
	return { "Beach_Summer_Asset_Pack_2025", "Models", propName }
end

local function seaPath(propName: string): PropPath
	return { "Sea_Animals_Pack", "Models", propName }
end

local function eggPath(propName: string): PropPath
	return { "Classic_Studs_Eggs_Pack", "Models", propName }
end

local function foodPath(propName: string): PropPath
	return {
		"Ultimate_Low_Poly_Food_and_Candy_Pack",
		"Ultimate Low Poly Food and Candy Pack",
		propName,
	}
end

local function cavePath(index: number): PropPath
	return { "Low_Poly_Cave_Asset_Pack", "Low Poly Cave Asset Pack | Destiny Tech", index }
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
-- actually light the paths at night the way part lamps would.
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

-- Terrain shorthands. The island body is sculpted from smooth voxels:
-- organic slopes for free, real water, carveable rock.
local terrain = Workspace.Terrain

local function fillDisc(position: Vector3, height: number, radius: number, material: Enum.Material)
	terrain:FillCylinder(CFrame.new(position), height, radius, material)
end

local function fillBox(position: Vector3, size: Vector3, material: Enum.Material)
	terrain:FillBlock(CFrame.new(position), size, material)
end

--[[
	Sculpts the whole island body: the low-tier blob, the rectangular
	town plateau, the high-tier hill, the tapering rock underside, the
	sand cove, the lagoon with the sky-well carved through it, the
	spring pond, the mid pool, the grotto pocket with its entry stair,
	and the three satellite isles plus drifting rocks.
]]
local function sculptIsland()
	terrain:SetMaterialColor(Enum.Material.Grass, TERRAIN_GRASS)
	-- Water color has its own property; SetMaterialColor rejects Water.
	terrain.WaterColor = TERRAIN_WATER

	-- Low tier: three overlapping discs make the organic blob.
	for _, blob in ipairs({
		{ offset = Vector3.new(0, 0, 40), radius = 235 },
		{ offset = Vector3.new(-120, 0, 140), radius = 140 },
		{ offset = Vector3.new(130, 0, 120), radius = 130 },
	}) do
		local base = CENTER + blob.offset
		fillDisc(base + Vector3.new(0, -9, 0), 18, blob.radius, Enum.Material.Rock)
		fillDisc(base + Vector3.new(0, -1.5, 0), 5, blob.radius, Enum.Material.Grass)
	end

	-- Town plateau: rectangular so the walled town seats fully, with
	-- ball corners so it still reads organic from the air.
	local plateauCenter = CENTER + Vector3.new(55, 0, -70)
	fillBox(
		plateauCenter + Vector3.new(0, TIER_MID / 2 - 4, 0),
		Vector3.new(230, TIER_MID + 8, 240),
		Enum.Material.Rock
	)
	fillBox(
		plateauCenter + Vector3.new(0, TIER_MID - 1.5, 0),
		Vector3.new(230, 5, 240),
		Enum.Material.Grass
	)
	for _, corner in ipairs({
		Vector3.new(-115, 0, -120),
		Vector3.new(115, 0, -120),
		Vector3.new(-115, 0, 120),
		Vector3.new(115, 0, 120),
	}) do
		terrain:FillBall(
			plateauCenter + corner + Vector3.new(0, TIER_MID - 14, 0),
			26,
			Enum.Material.Rock
		)
	end

	-- High tier hill, two lobes behind and west of the town.
	for _, lobe in ipairs({
		{ offset = Vector3.new(-145, 0, -130), radius = 95 },
		{ offset = Vector3.new(-100, 0, -195), radius = 60 },
	}) do
		local base = CENTER + lobe.offset
		fillDisc(
			base + Vector3.new(0, TIER_HIGH / 2 - 5, 0),
			TIER_HIGH + 10,
			lobe.radius,
			Enum.Material.Rock
		)
		fillDisc(base + Vector3.new(0, TIER_HIGH - 1.5, 0), 5, lobe.radius, Enum.Material.Grass)
	end

	-- Rock underside: shrinking discs taper the island to a keel.
	fillDisc(CENTER + Vector3.new(0, -20, 30), 24, 200, Enum.Material.Rock)
	fillDisc(CENTER + Vector3.new(20, -45, 0), 26, 140, Enum.Material.Rock)
	fillDisc(CENTER + Vector3.new(-30, -72, 10), 28, 85, Enum.Material.Rock)
	fillDisc(CENTER + Vector3.new(30, -98, -10), 24, 45, Enum.Material.Rock)

	-- Sand cove along the front edge.
	fillBox(CENTER + Vector3.new(-10, -1, 185), Vector3.new(200, 6, 90), Enum.Material.Sand)

	-- Lagoon: carve the basin, fill the water, then carve the sky-well
	-- straight through the island. The water ring holds; the hole
	-- falls into open sky.
	fillDisc(LAGOON_CENTER + Vector3.new(0, -2, 0), 8, LAGOON_RADIUS + 2, Enum.Material.Air)
	fillDisc(LAGOON_CENTER + Vector3.new(0, -2.5, 0), 5, LAGOON_RADIUS, Enum.Material.Water)
	fillDisc(LAGOON_CENTER + Vector3.new(0, -40, 0), 84, 11, Enum.Material.Air)

	-- Spring pond at the World Tree, and the mid pool on the plateau.
	local pond = TREE_BASE + Vector3.new(30, 0, 35)
	fillDisc(pond + Vector3.new(0, -1.5, 0), 5, 12, Enum.Material.Air)
	fillDisc(pond + Vector3.new(0, -1.8, 0), 3.6, 11, Enum.Material.Water)

	local midPool = CENTER + Vector3.new(0, TIER_MID, -20)
	fillDisc(midPool + Vector3.new(0, -1.5, 0), 5, 14, Enum.Material.Air)
	fillDisc(midPool + Vector3.new(0, -1.8, 0), 3.6, 13, Enum.Material.Water)

	-- Grotto: an air pocket in the rock under the cove, with a stepped
	-- stair carved down from the sand.
	fillDisc(GROTTO_CENTER, 14, 15, Enum.Material.Air)
	fillBox(CENTER + Vector3.new(-60, -3, 178), Vector3.new(10, 10, 16), Enum.Material.Air)
	fillBox(CENTER + Vector3.new(-60, -9, 166), Vector3.new(10, 10, 16), Enum.Material.Air)
	fillBox(CENTER + Vector3.new(-60, -14, 156), Vector3.new(10, 12, 14), Enum.Material.Air)

	-- Satellite isles: small grass-capped rock pucks.
	for _, isle in ipairs({
		{ center = PORTAL_ISLE, radius = 42 },
		{ center = CARNIVAL_ISLE, radius = 46 },
		{ center = BALLOON_ISLE, radius = 34 },
	}) do
		fillDisc(isle.center + Vector3.new(0, -8, 0), 16, isle.radius, Enum.Material.Rock)
		fillDisc(isle.center + Vector3.new(0, -1.5, 0), 5, isle.radius, Enum.Material.Grass)
	end

	-- Drifting rocks: unreachable scenery that sells the sky.
	for _, rock in ipairs({
		{ offset = Vector3.new(380, -30, 180), radius = 12 },
		{ offset = Vector3.new(-390, 40, -140), radius = 10 },
		{ offset = Vector3.new(150, 70, -330), radius = 9 },
	}) do
		local base = CENTER + rock.offset
		fillDisc(base + Vector3.new(0, -4, 0), 10, rock.radius, Enum.Material.Rock)
		fillDisc(base + Vector3.new(0, 0.5, 0), 3, rock.radius, Enum.Material.Grass)
	end
end

--[[
	The World Tree: a tapering part trunk crowned with cartoon canopy
	spheres, root flares at the base, a spiral stair climbing to the
	deck, hanging lianas, and fireflies. The pond and the tier falls
	are terrain water sculpted earlier; this is the wood.
]]
local function buildWorldTree(parent: Instance)
	-- Trunk: stacked tapering cylinders with a slight lean per segment.
	local segmentBase = TREE_BASE
	for segmentIndex = 0, 4 do
		local radius = 5.5 - segmentIndex * 0.5
		local segmentHeight = (TIER_DECK - TIER_HIGH + 6) / 5
		createPart({
			Name = "WorldTreeTrunk",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(segmentHeight + 1, radius * 2, radius * 2),
			CFrame = CFrame.new(
				segmentBase + Vector3.new(math.sin(segmentIndex) * 0.8, segmentHeight / 2, 0)
			) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(112, 82, 52),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		segmentBase += Vector3.new(0, segmentHeight, 0)
	end

	-- Root flares splaying from the base.
	for rootIndex = 0, 5 do
		local angle = rootIndex / 6 * math.pi * 2
		createPart({
			Name = "WorldTreeRoot",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(14, 3.4, 3.4),
			CFrame = CFrame.new(
				TREE_BASE + Vector3.new(math.cos(angle) * 8, 1.4, math.sin(angle) * 8)
			) * CFrame.Angles(0, -angle, math.rad(24)),
			Color = Color3.fromRGB(102, 74, 46),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
	end

	-- Canopy: five overlapping grass spheres, matching the game's
	-- cartoon style at colossal scale.
	local canopyCenter = TREE_BASE + Vector3.new(0, TIER_DECK - TIER_HIGH + 14, 0)
	for _, puff in ipairs({
		{ offset = Vector3.new(0, 4, 0), radius = 17 },
		{ offset = Vector3.new(-12, -2, 6), radius = 12 },
		{ offset = Vector3.new(12, -1, -6), radius = 12 },
		{ offset = Vector3.new(6, 0, 11), radius = 10 },
		{ offset = Vector3.new(-7, 1, -11), radius = 10 },
	}) do
		createPart({
			Name = "WorldTreeCanopy",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(puff.radius * 2, puff.radius * 2, puff.radius * 2),
			Position = canopyCenter + puff.offset,
			Color = Color3.fromRGB(74, 158, 62),
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = parent,
		})
	end

	-- The deck: a plank ring around the trunk below the canopy, with a
	-- rail of posts. Reached by the spiral stair.
	local deckY = CENTER.Y + TIER_DECK
	local deck = createPart({
		Name = "CanopyDeck",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 24, 24),
		CFrame = CFrame.new(Vector3.new(TREE_BASE.X, deckY, TREE_BASE.Z))
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = PLANK_COLOR,
		Material = Enum.Material.WoodPlanks,
		Parent = parent,
	})
	addBillboard(deck, "THE WORLD TREE", Color3.fromRGB(129, 236, 129), 34)
	for postIndex = 0, 11 do
		local angle = postIndex / 12 * math.pi * 2
		createPart({
			Name = "DeckRailPost",
			Size = Vector3.new(0.6, 3.4, 0.6),
			Position = Vector3.new(
				TREE_BASE.X + math.cos(angle) * 11.4,
				deckY + 2.2,
				TREE_BASE.Z + math.sin(angle) * 11.4
			),
			Color = WOOD_COLOR,
			Material = Enum.Material.Wood,
			CanCollide = false,
			Parent = parent,
		})
	end

	-- Spiral stair: two turns around the trunk from the hill to the
	-- deck rim.
	local STEP_COUNT = 26
	for stepIndex = 0, STEP_COUNT do
		local progress = stepIndex / STEP_COUNT
		local angle = progress * math.pi * 4
		local stepY = CENTER.Y + TIER_HIGH + 0.6 + progress * (TIER_DECK - TIER_HIGH - 1)
		createPart({
			Name = "SpiralStep",
			Size = Vector3.new(6.5, 0.9, 3),
			CFrame = CFrame.new(
				Vector3.new(
					TREE_BASE.X + math.cos(angle) * 9,
					stepY,
					TREE_BASE.Z + math.sin(angle) * 9
				)
			) * CFrame.Angles(0, -angle, 0),
			Color = PLANK_COLOR,
			Material = Enum.Material.WoodPlanks,
			Parent = parent,
		})
	end

	-- Lianas swing from the canopy; lilies and reeds dress the pond.
	placeProp(parent, naturePath("Big Liana"), TREE_BASE + Vector3.new(-16, 0, 10), 20, 30)
	placeProp(parent, naturePath("Liana"), TREE_BASE + Vector3.new(15, 0, -12), 16, 200)

	local pond = TREE_BASE + Vector3.new(30, 0, 35)
	placeProp(parent, naturePath("Water Lily"), pond + Vector3.new(-4, -0.4, 2), 1, 40)
	placeProp(parent, naturePath("Flower Water Lily"), pond + Vector3.new(4, -0.4, -3), 1.2, 160)
	placeProp(parent, naturePath("Reed"), pond + Vector3.new(-10, 0, -8), 3, 0)
	placeProp(parent, naturePath("Tall Reed"), pond + Vector3.new(10, 0, 8), 3.6, 90)

	addGlowMotes(parent, canopyCenter + Vector3.new(0, -6, 0), GOLD_COLOR, 26)
end

--[[
	The river's vertical moments: glassy waterfall columns at each tier
	lip, foam at their feet, and the sky-well column falling from the
	lagoon's hole straight through the island with mist at the rim.
	The flat water between them is terrain, sculpted earlier.
]]
local function buildFalls(parent: Instance)
	local function fallColumn(topPosition: Vector3, dropHeight: number, thickness: number)
		local column = createPart({
			Name = "Waterfall",
			Size = Vector3.new(thickness, dropHeight, 2.6),
			Position = topPosition - Vector3.new(0, dropHeight / 2, 0),
			Color = WATERFALL_COLOR,
			Material = Enum.Material.Glass,
			Transparency = 0.35,
			CanCollide = false,
			Parent = parent,
		})

		local foam = createPart({
			Name = "WaterfallFoam",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(thickness + 1.5, 2.4, 4),
			Position = topPosition - Vector3.new(0, dropHeight - 0.6, 0),
			Color = Color3.fromRGB(235, 248, 252),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.25,
			CanCollide = false,
			Parent = parent,
		})
		addGlowMotes(parent, foam.Position, Color3.fromRGB(220, 244, 252), 5)

		return column
	end

	-- High lip: pond overflow down to the mid pool's channel.
	fallColumn(CENTER + Vector3.new(-66, TIER_HIGH, -77), TIER_HIGH - TIER_MID, 5)
	-- Plateau lip: mid pool down to the lagoon.
	fallColumn(CENTER + Vector3.new(22, TIER_MID, 50), TIER_MID, 5)

	-- The sky-well: the lagoon drains through the island. The column
	-- runs from the water surface down past the keel.
	createPart({
		Name = "SkyWellColumn",
		Size = Vector3.new(9, 118, 9),
		Position = LAGOON_CENTER + Vector3.new(0, -59, 0),
		Color = WATERFALL_COLOR,
		Material = Enum.Material.Glass,
		Transparency = 0.4,
		CanCollide = false,
		Parent = parent,
	})
	local rim = createPart({
		Name = "SkyWellRim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 24, 24),
		CFrame = CFrame.new(LAGOON_CENTER + Vector3.new(0, 0.4, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(214, 230, 238),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.45,
		CanCollide = false,
		Parent = parent,
	})
	addBillboard(rim, "THE SKY-WELL", Color3.fromRGB(180, 226, 244), 7)
	addGlowMotes(parent, LAGOON_CENTER + Vector3.new(0, 1.5, 0), Color3.fromRGB(210, 240, 250), 16)

	-- Terrain water cannot slope, so each channel is a flat strip and
	-- the falls carry the height. The strips are decorative part water
	-- flush with the ground.
	for _, strip in ipairs({
		{
			from = TREE_BASE + Vector3.new(30, 0, 35),
			to = CENTER + Vector3.new(-66, TIER_HIGH, -77),
		},
		{
			from = CENTER + Vector3.new(0, TIER_MID, -20),
			to = CENTER + Vector3.new(22, TIER_MID, 50),
		},
		{ from = LAGOON_CENTER, to = LAGOON_CENTER },
	}) do
		local span = strip.to - strip.from
		local length = span.Magnitude
		if length > 4 then
			local midpoint = strip.from + span / 2
			createPart({
				Name = "RiverStrip",
				Size = Vector3.new(4.5, 0.4, length),
				CFrame = CFrame.lookAt(midpoint + Vector3.new(0, -0.1, 0), midpoint + span),
				Color = TERRAIN_WATER,
				Material = Enum.Material.Glass,
				Transparency = 0.3,
				CanCollide = false,
				Parent = parent,
			})
		end
	end
end

--[[
	The spawn plaza on the low tier: the landing pad centerpiece the
	cutscene targets, a tiered fountain, city benches and lamps, and a
	signpost sorting new arrivals toward the districts.
]]
local function buildPlaza(parent: Instance)
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

	for studIndex = 1, 8 do
		local angle = studIndex / 8 * math.pi * 2
		createPart({
			Name = "PadStud" .. studIndex,
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.2, 1.2, 1.2),
			Position = PAD_POSITION + Vector3.new(math.cos(angle) * 11, 1.2, math.sin(angle) * 11),
			Color = GOLD_COLOR,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = parent,
		})
	end

	-- Fountain: stone basin, column, and a crown of water.
	local fountainBase = CENTER + Vector3.new(-55, 0, 130)
	createPart({
		Name = "FountainBasin",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 15, 15),
		CFrame = CFrame.new(fountainBase + Vector3.new(0, 1, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(196, 188, 172),
		Material = Enum.Material.Cobblestone,
		Parent = parent,
	})
	createPart({
		Name = "FountainWater",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.7, 13, 13),
		CFrame = CFrame.new(fountainBase + Vector3.new(0, 2.1, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = TERRAIN_WATER,
		Material = Enum.Material.Glass,
		Transparency = 0.3,
		CanCollide = false,
		Parent = parent,
	})
	createPart({
		Name = "FountainColumn",
		Size = Vector3.new(1.6, 4.4, 1.6),
		Position = fountainBase + Vector3.new(0, 4.2, 0),
		Color = Color3.fromRGB(196, 188, 172),
		Material = Enum.Material.Cobblestone,
		CanCollide = false,
		Parent = parent,
	})
	local crown = createPart({
		Name = "FountainCrown",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3.4, 3.4, 3.4),
		Position = fountainBase + Vector3.new(0, 7, 0),
		Color = TERRAIN_WATER,
		Material = Enum.Material.Glass,
		Transparency = 0.3,
		CanCollide = false,
		Parent = parent,
	})
	addGlowMotes(parent, crown.Position, Color3.fromRGB(214, 240, 250), 5)

	for benchIndex, benchOffset in ipairs({ Vector3.new(-72, 0, 118), Vector3.new(-38, 0, 145) }) do
		placeProp(
			parent,
			cityPath("Benches & Picnic", if benchIndex == 1 then "Bench 1" else "Wooden Bench 2"),
			CENTER + benchOffset,
			3,
			benchIndex * 130,
			fallbackBench
		)
	end

	for lampIndex, lampOffset in ipairs({
		Vector3.new(-115, 0, 120),
		Vector3.new(-62, 0, 72),
		Vector3.new(-18, 0, 118),
	}) do
		local lamp = placeProp(
			parent,
			cityPath(
				"City Lamps",
				if lampIndex % 2 == 0 then "Round Street Lamp 1" else "Street Lamp 1"
			),
			CENTER + lampOffset,
			10,
			lampIndex * 70,
			fallbackLamp
		)
		if lamp ~= nil then
			addTopLight(lamp)
		end
	end

	local signpost = placeProp(
		parent,
		cityPath("Direction Signs", "Tall Direction Sign"),
		CENTER + Vector3.new(-40, 0, 92),
		6,
		20
	)
	if signpost == nil then
		local post = createPart({
			Name = "PlazaSignPost",
			Size = Vector3.new(0.8, 5, 0.8),
			Position = CENTER + Vector3.new(-40, 2.5, 92),
			Color = WOOD_COLOR,
			Material = Enum.Material.Wood,
			CanCollide = false,
			Parent = parent,
		})
		addBillboard(post, "TOWN AHEAD -- HATCHERY EAST -- PORTAL SOUTH", SIGN_TEXT_COLOR, 4)
	else
		local anyPart = signpost:FindFirstChildWhichIsA("BasePart", true)
		if anyPart ~= nil then
			addBillboard(anyPart, "TOWN AHEAD -- HATCHERY EAST -- PORTAL SOUTH", SIGN_TEXT_COLOR, 6)
		end
	end
end

--[[
	Cobbled roads linking the districts. Flat segments hug each tier;
	the tier changes ride sloped ramp parts so every route is walkable
	without jumping.
]]
local function buildRoads(parent: Instance)
	local function flatRoad(fromOffset: Vector3, toOffset: Vector3, width: number)
		local fromPosition = CENTER + fromOffset
		local toPosition = CENTER + toOffset
		local span = toPosition - fromPosition
		local length = span.Magnitude
		if length < 1 then
			return
		end

		local midpoint = fromPosition + span / 2 + Vector3.new(0, 0.14, 0)
		createPart({
			Name = "HubRoad",
			Size = Vector3.new(width, 0.25, length),
			CFrame = CFrame.lookAt(midpoint, midpoint + span * Vector3.new(1, 0, 1)),
			Color = Color3.fromRGB(178, 168, 152),
			Material = Enum.Material.Cobblestone,
			CanCollide = false,
			Parent = parent,
		})
	end

	local function ramp(fromOffset: Vector3, toOffset: Vector3, width: number)
		local fromPosition = CENTER + fromOffset
		local toPosition = CENTER + toOffset
		local span = toPosition - fromPosition
		local length = span.Magnitude
		local midpoint = fromPosition + span / 2

		createPart({
			Name = "HubRamp",
			Size = Vector3.new(width, 1, length + 2),
			CFrame = CFrame.lookAt(midpoint, toPosition),
			Color = Color3.fromRGB(178, 168, 152),
			Material = Enum.Material.Cobblestone,
			Parent = parent,
		})
	end

	-- Plaza to the town's south gate: flat, then the embankment ramp.
	flatRoad(Vector3.new(-70, 0, 95), Vector3.new(10, 0, 62), 7)
	ramp(Vector3.new(10, 0, 62), Vector3.new(40, TIER_MID, 32), 10)
	-- Gate approach to the market row.
	flatRoad(Vector3.new(40, TIER_MID, 32), Vector3.new(42, TIER_MID, 24), 8)
	-- Plaza to the cove and the portal bridge head.
	flatRoad(Vector3.new(-80, 0, 110), Vector3.new(-58, 0, 225), 6)
	-- Plaza to the lagoon overlook.
	flatRoad(Vector3.new(-70, 0, 100), Vector3.new(-24, 0, 78), 5)
	-- Lagoon east around to the hatchery.
	flatRoad(Vector3.new(82, 0, 78), Vector3.new(138, 0, 108), 6)
	-- West lawn to the carnival bridge head.
	flatRoad(Vector3.new(-120, 0, 82), Vector3.new(-225, 0, 58), 5)
	-- Mid tier east edge to the balloon bridge head.
	flatRoad(Vector3.new(150, TIER_MID, -70), Vector3.new(168, TIER_MID, -102), 5)
	-- High tier: pond side path to the stair foot.
	flatRoad(Vector3.new(-110, TIER_HIGH, -98), Vector3.new(-132, TIER_HIGH, -128), 4)
	-- Mid tier to high tier ramp on the west side.
	ramp(Vector3.new(-40, TIER_MID, -60), Vector3.new(-68, TIER_HIGH, -82), 8)
	-- Plaza to mid tier west ramp (second route up, by the falls).
	ramp(Vector3.new(-58, 0, 40), Vector3.new(-40, TIER_MID, -2), 8)
end

--[[
	Seats the bought TDS town ON the island's mid tier at native scale,
	fully walkable (anchor only, collision kept). Its real wall gaps
	become the gates: the south gap opens onto the market row and the
	ramp down to the plaza, the east gap onto a fenced cliff overlook.
	Embankments, grass walls, and bushes tuck the wall footings into
	the terrain so the town reads as grown-in.
]]
local function seatTown(parent: Instance)
	local template: Instance? = nil
	if packModelsFolder ~= nil then
		local pack = packModelsFolder:FindFirstChild("Tds_Town_Pack")
		template = if pack ~= nil then pack:FindFirstChild("Scenery") else nil
	end

	if template == nil or not template:IsA("Model") then
		-- Placeholder keep: four wall runs and two gate posts hold the
		-- town's footprint until the pack syncs.
		for _, wall in ipairs({
			{ offset = Vector3.new(0, 0, -97), size = Vector3.new(169, 14, 3) },
			{ offset = Vector3.new(0, 0, 97), size = Vector3.new(60, 14, 3) },
			{ offset = Vector3.new(-84, 0, 0), size = Vector3.new(3, 14, 195) },
			{ offset = Vector3.new(84, 0, 0), size = Vector3.new(3, 14, 195) },
		}) do
			createPart({
				Name = "FallbackTownWall",
				Size = wall.size,
				Position = TOWN_CENTER + wall.offset + Vector3.new(0, 7, 0),
				Color = Color3.fromRGB(124, 92, 70),
				Material = Enum.Material.Wood,
				Parent = parent,
			})
		end
		warn("HubService: TDS town pack missing; placeholder walls mark its footprint")
		return
	end

	local town = template:Clone()
	for _, descendant in ipairs(town:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	local boxCFrame, boxSize = town:GetBoundingBox()
	local target = TOWN_CENTER + Vector3.new(0, boxSize.Y / 2, 0)
	town:PivotTo(town:GetPivot() + (target - boxCFrame.Position))
	town.Name = "TdsTown"
	town.Parent = parent

	-- The gates, measured from the pack's own geometry: the south gap
	-- sits at ~42% of the width along the front wall, the east gap at
	-- ~18% of the depth along the east wall.
	local southGate = TOWN_CENTER + Vector3.new(-boxSize.X / 2 + boxSize.X * 0.42, 0, boxSize.Z / 2)
	local eastGate = TOWN_CENTER + Vector3.new(boxSize.X / 2, 0, -boxSize.Z / 2 + boxSize.Z * 0.18)

	-- Grass-wall skirts and bushes tuck the outer wall footings in.
	for skirtIndex = 0, 3 do
		placeProp(
			parent,
			bundlePath("Grass", 1 + skirtIndex % 3),
			TOWN_CENTER + Vector3.new(-boxSize.X / 2 - 4, 0, -70 + skirtIndex * 44),
			4,
			90
		)
	end
	for bushIndex = 0, 5 do
		placeProp(
			parent,
			naturePath(if bushIndex % 2 == 0 then "Bush" else "Tall Bush"),
			TOWN_CENTER
				+ Vector3.new(
					-boxSize.X / 2 + 8 + bushIndex * (boxSize.X - 16) / 5,
					0,
					boxSize.Z / 2 + 4 + rng:NextNumber(0, 3)
				),
			3,
			bushIndex * 61
		)
	end

	-- Gate lamps and the string lights over the south approach.
	for _, gatePosition in ipairs({ southGate, eastGate }) do
		local lamp = placeProp(
			parent,
			cityPath("City Lamps", "Street Lamp 2"),
			gatePosition + Vector3.new(6, 0, 3),
			9,
			0,
			fallbackLamp
		)
		if lamp ~= nil then
			addTopLight(lamp)
		end
	end

	local lightSpan = 16
	for _, postSide in ipairs({ -1, 1 }) do
		createPart({
			Name = "StringLightPost",
			Size = Vector3.new(0.7, 9, 0.7),
			Position = southGate + Vector3.new(postSide * lightSpan / 2, 4.5, 8),
			Color = WOOD_COLOR,
			Material = Enum.Material.Wood,
			CanCollide = false,
			Parent = parent,
		})
	end
	for beadIndex = 0, 8 do
		local progress = beadIndex / 8
		local sag = math.sin(progress * math.pi) * 2.2
		createPart({
			Name = "StringLightBead",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.8, 0.8, 0.8),
			Position = southGate + Vector3.new(-lightSpan / 2 + progress * lightSpan, 8.6 - sag, 8),
			Color = if beadIndex % 2 == 0 then GOLD_COLOR else Color3.fromRGB(255, 168, 120),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = parent,
		})
	end

	-- The east gate opens onto a fenced cliff overlook.
	for fenceIndex = 0, 2 do
		placeProp(
			parent,
			naturePath("Inf. Fence 1"),
			eastGate + Vector3.new(12, 0, -8 + fenceIndex * 8),
			3,
			90
		)
	end
	local overlookSign = createPart({
		Name = "OverlookSign",
		Size = Vector3.new(0.8, 4.4, 0.8),
		Position = eastGate + Vector3.new(10, 2.2, 12),
		Color = WOOD_COLOR,
		Material = Enum.Material.Wood,
		CanCollide = false,
		Parent = parent,
	})
	addBillboard(overlookSign, "CLIFF OVERLOOK -- MIND THE EDGE!", SIGN_TEXT_COLOR, 3)
end

--[[
	The market row at the town's south gate approach: the island shop
	and the group chest as gate-front stalls, so commerce lives at the
	town's doorstep without gambling on clipping its interior.
]]
local function buildMarketRow(parent: Instance)
	local shopBase = TOWN_CENTER + Vector3.new(-16, 0, 116)

	local counter = createPart({
		Name = "ShopCounter",
		Size = Vector3.new(10, 3.4, 3),
		Position = shopBase + Vector3.new(0, 1.7, 0),
		Color = WOOD_COLOR,
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	for _, postOffset in ipairs({ -4.6, 4.6 }) do
		createPart({
			Name = "ShopPost",
			Size = Vector3.new(0.8, 8, 0.8),
			Position = shopBase + Vector3.new(postOffset, 4, 0),
			Color = WHITE_COLOR,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = parent,
		})
	end
	for stripeIndex = 0, 4 do
		createPart({
			Name = "ShopAwning",
			Size = Vector3.new(2.2, 0.4, 5),
			CFrame = CFrame.new(shopBase + Vector3.new(-4.4 + stripeIndex * 2.2, 8.4, -0.6))
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

	local chestBase = TOWN_CENTER + Vector3.new(18, 0, 118)
	local body = createPart({
		Name = "GroupChest",
		Size = Vector3.new(5, 3, 3.4),
		Position = chestBase + Vector3.new(0, 1.5, 0),
		Color = Color3.fromRGB(110, 80, 48),
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	createPart({
		Name = "ChestLid",
		Size = Vector3.new(5.2, 1.4, 3.6),
		CFrame = CFrame.new(chestBase + Vector3.new(0, 3.4, -0.4))
			* CFrame.Angles(math.rad(-18), 0, 0),
		Color = Color3.fromRGB(96, 68, 38),
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	for _, bandX in ipairs({ -1.6, 1.6 }) do
		createPart({
			Name = "ChestBand",
			Size = Vector3.new(0.5, 3.2, 3.6),
			Position = chestBase + Vector3.new(bandX, 1.5, 0),
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

	placeProp(parent, naturePath("Potted Plant"), shopBase + Vector3.new(-8, 0, 2), 2.5, 0)
	placeProp(
		parent,
		cityPath("Restaurant Related", "Outside Parasol Table"),
		chestBase + Vector3.new(12, 0, -2),
		7,
		40
	)
end

--[[
	The Hatchery: a shard-dome, the top of a colossal hatched egg
	standing on its own jagged shell shards, sheltering pedestals that
	showcase the rarest eggs from the collection.
]]
local function buildHatchery(parent: Instance)
	local base = HATCHERY_CENTER

	createPart({
		Name = "HatcheryFloor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 34, 34),
		CFrame = CFrame.new(base + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(196, 188, 172),
		Material = Enum.Material.Cobblestone,
		CanCollide = false,
		Parent = parent,
	})

	-- Shell shards: jagged wedge pairs hold the dome nine studs up,
	-- leaving open walk-in gaps all around.
	for shardIndex = 0, 7 do
		local angle = shardIndex / 8 * math.pi * 2
		local shardPosition = base + Vector3.new(math.cos(angle) * 15, 0, math.sin(angle) * 15)
		createPart({
			Name = "ShellShard",
			Size = Vector3.new(4.4, 9, 1.6),
			CFrame = CFrame.new(shardPosition + Vector3.new(0, 4.5, 0))
				* CFrame.Angles(0, -angle + math.pi / 2, 0),
			Color = WHITE_COLOR,
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
		local wedge = Instance.new("WedgePart")
		wedge.Anchored = true
		wedge.Size = Vector3.new(4.4, 3, 1.6)
		wedge.CFrame = CFrame.new(shardPosition + Vector3.new(0, 10.5, 0))
			* CFrame.Angles(0, -angle + math.pi / 2, 0)
		wedge.Color = WHITE_COLOR
		wedge.Material = Enum.Material.SmoothPlastic
		wedge.TopSurface = Enum.SurfaceType.Smooth
		wedge.BottomSurface = Enum.SurfaceType.Smooth
		wedge.Parent = parent
	end

	-- The dome: stacked shrinking discs read as the egg's crown.
	local domeSpecs = { 16, 15.2, 14, 12.4, 10.4, 8, 5.4, 2.8 }
	for discIndex, radius in ipairs(domeSpecs) do
		createPart({
			Name = "HatcheryDome",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.5, radius * 2, radius * 2),
			CFrame = CFrame.new(base + Vector3.new(0, 9 + (discIndex - 1) * 1.4, 0))
				* CFrame.Angles(0, 0, math.rad(90)),
			Color = WHITE_COLOR,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = parent,
		})
	end
	createPart({
		Name = "HatcheryBand",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 33, 33),
		CFrame = CFrame.new(base + Vector3.new(0, 9, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = GOLD_COLOR,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = parent,
	})

	-- Pedestals with the legends on display.
	local showcase = {
		"Legendary Egg",
		"Mythical Egg",
		"Rainbow Egg",
		"Galaxy Admin Egg",
		"Celestial Griffin Egg",
	}
	for eggIndex, eggName in ipairs(showcase) do
		local angle = eggIndex / #showcase * math.pi * 2
		local pedestalBase = base + Vector3.new(math.cos(angle) * 9, 0, math.sin(angle) * 9)
		local pedestal = createPart({
			Name = "EggPedestal",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.4, 3.4, 3.4),
			CFrame = CFrame.new(pedestalBase + Vector3.new(0, 1.2, 0))
				* CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(120, 124, 140),
			Material = Enum.Material.Slate,
			Parent = parent,
		})
		local light = Instance.new("PointLight")
		light.Color = GOLD_COLOR
		light.Brightness = 1.1
		light.Range = 10
		light.Parent = pedestal

		placeProp(parent, eggPath(eggName), pedestalBase + Vector3.new(0, 2.4, 0), 3, eggIndex * 72)
	end

	local sign = createPart({
		Name = "HatcherySign",
		Size = Vector3.new(0.8, 4.6, 0.8),
		Position = base + Vector3.new(0, 2.3, 22),
		Color = WOOD_COLOR,
		Material = Enum.Material.Wood,
		CanCollide = false,
		Parent = parent,
	})
	addBillboard(sign, "THE HATCHERY -- LEGENDS ON DISPLAY!", GOLD_COLOR, 4)
	addGlowMotes(parent, base + Vector3.new(0, 7, 0), GOLD_COLOR, 14)

	for _, flowerSpec in ipairs({
		{ prop = "Flower 6", offset = Vector3.new(-20, 0, 8) },
		{ prop = "Flower 10", offset = Vector3.new(19, 0, -10) },
		{ prop = "Flower 3", offset = Vector3.new(8, 0, 21) },
	}) do
		placeProp(parent, naturePath(flowerSpec.prop), base + flowerSpec.offset, 2, 0)
	end
end

--[[
	The cove: the island's front porch. Sand underfoot (terrain), a
	fence line and telescopes at the rim looking out at the sky and
	the TDS island, beach-pack furniture, and the lagoon's toys.
]]
local function buildCove(parent: Instance)
	for fenceIndex = 0, 4 do
		placeProp(
			parent,
			naturePath("Inf. Fence 1"),
			CENTER + Vector3.new(-72 + fenceIndex * 36, 0, 232),
			3,
			0
		)
	end

	for _, scopeX in ipairs({ -20, 50 }) do
		local scopeBase = CENTER + Vector3.new(scopeX, 0, 228)
		createPart({
			Name = "TelescopeStand",
			Size = Vector3.new(0.8, 3.4, 0.8),
			Position = scopeBase + Vector3.new(0, 1.7, 0),
			Color = Color3.fromRGB(62, 74, 96),
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = parent,
		})
		createPart({
			Name = "TelescopeTube",
			Size = Vector3.new(0.9, 0.9, 3.2),
			CFrame = CFrame.new(scopeBase + Vector3.new(0, 3.8, 0))
				* CFrame.Angles(math.rad(20), 0, 0),
			Color = GOLD_COLOR,
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = parent,
		})
	end

	for benchIndex, benchX in ipairs({ -50, 25 }) do
		placeProp(
			parent,
			cityPath("Benches & Picnic", if benchIndex == 1 then "Wooden Bench 1" else "Bench 2"),
			CENTER + Vector3.new(benchX, 0, 222),
			3,
			180,
			fallbackBench
		)
	end

	local viewSign = createPart({
		Name = "ViewSign",
		Size = Vector3.new(10, 3, 0.5),
		Position = CENTER + Vector3.new(0, 5, 225),
		Color = WOOD_COLOR,
		Material = Enum.Material.Wood,
		CanCollide = false,
		Parent = parent,
	})
	addBillboard(viewSign, "TDS TOWN & NEW ISLANDS OUT THERE...", SIGN_TEXT_COLOR, 3)
	createPart({
		Name = "ViewSignPost",
		Size = Vector3.new(0.8, 5, 0.8),
		Position = CENTER + Vector3.new(0, 2.5, 225),
		Color = WOOD_COLOR,
		Material = Enum.Material.Wood,
		CanCollide = false,
		Parent = parent,
	})

	placeProp(
		parent,
		beachPath("Palm Tree"),
		CENTER + Vector3.new(-95, 0, 185),
		14,
		20,
		fallbackTree
	)
	placeProp(
		parent,
		beachPath("Curved Palm Tree"),
		CENTER + Vector3.new(85, 0, 175),
		13,
		200,
		fallbackTree
	)
	placeProp(parent, beachPath("Sunshade"), CENTER + Vector3.new(-45, 0, 190), 8, 60)
	placeProp(parent, beachPath("Beach Chair"), CENTER + Vector3.new(-38, 0, 196), 3, 150)
	placeProp(parent, beachPath("Beach Chair"), CENTER + Vector3.new(-52, 0, 199), 3, 190)
	placeProp(parent, beachPath("Sand Castle"), CENTER + Vector3.new(60, 0, 200), 5, 0)
	placeProp(parent, beachPath("Chest Scene"), CENTER + Vector3.new(-75, 0, 210), 4, 110)
	placeProp(parent, beachPath("Starfish"), CENTER + Vector3.new(20, 0, 215), 1.6, 0)
	placeProp(parent, beachPath("Surf Board"), CENTER + Vector3.new(95, 0, 195), 5, 15)
	placeProp(parent, beachPath("Buoy"), LAGOON_CENTER + Vector3.new(-30, 0.4, 28), 4, 0)
	placeProp(parent, seaPath("Turtle"), CENTER + Vector3.new(0, 0, 195), 4, 30)
	placeProp(parent, naturePath("Wooden Boat"), LAGOON_CENTER + Vector3.new(25, 0.2, 25), 3, 140)
end

--[[
	The crystal grotto in the rock under the cove, reached by the
	carved stair from the sand: part-built crystal clusters, a cave
	formation, treasure, and slow purple motes. A jellyfish drifts in
	the open sky just past the rim, visible from the grotto mouth and
	the portal bridge.
]]
local function buildGrotto(parent: Instance)
	for crystalIndex = 0, 4 do
		local angle = crystalIndex / 5 * math.pi * 2
		local crystalBase = GROTTO_CENTER
			+ Vector3.new(math.cos(angle) * 10, -6, math.sin(angle) * 10)
		local height = 3 + (crystalIndex % 3) * 1.6
		local crystal = createPart({
			Name = "GrottoCrystal",
			Size = Vector3.new(1.6, height, 1.6),
			CFrame = CFrame.new(crystalBase + Vector3.new(0, height / 2, 0)) * CFrame.Angles(
				math.rad(rng:NextNumber(-14, 14)),
				angle,
				math.rad(rng:NextNumber(-14, 14))
			),
			Color = CRYSTAL_COLOR,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			CanCollide = false,
			Parent = parent,
		})
		local light = Instance.new("PointLight")
		light.Color = CRYSTAL_COLOR
		light.Brightness = 1
		light.Range = 12
		light.Parent = crystal
	end

	placeProp(parent, cavePath(6), GROTTO_CENTER + Vector3.new(0, -7, -8), 5, 40)
	placeProp(parent, beachPath("Chest Scene"), GROTTO_CENTER + Vector3.new(4, -7, 6), 3.5, 210)
	for coinIndex = 0, 3 do
		createPart({
			Name = "GrottoCoin",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1, 1, 1),
			Position = GROTTO_CENTER + Vector3.new(2 + coinIndex * 1.4, -6.4, 7 - coinIndex),
			Color = GOLD_COLOR,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = parent,
		})
	end
	addGlowMotes(parent, GROTTO_CENTER + Vector3.new(0, -2, 0), CRYSTAL_COLOR, 12)

	placeProp(parent, seaPath("Jellyfish"), CENTER + Vector3.new(-95, -20, 260), 6, 0)
end

--[[
	A rope bridge between two points: sagging planks with segmented
	rope rails and posts at both ends. Fully walkable.
]]
local function buildRopeBridge(parent: Instance, fromPosition: Vector3, toPosition: Vector3)
	local span = toPosition - fromPosition
	local length = span.Magnitude
	local plankCount = math.max(math.floor(length / 3), 4)

	local previousRail: { [number]: Vector3 } = {}
	for plankIndex = 0, plankCount do
		local progress = plankIndex / plankCount
		local sag = math.sin(progress * math.pi) * -3
		local plankCenter = fromPosition + span * progress + Vector3.new(0, sag, 0)
		local ahead = fromPosition + span * math.min(progress + 0.02, 1)

		createPart({
			Name = "BridgePlank",
			Size = Vector3.new(5, 0.5, 2.2),
			CFrame = CFrame.lookAt(plankCenter, Vector3.new(ahead.X, plankCenter.Y, ahead.Z)),
			Color = PLANK_COLOR,
			Material = Enum.Material.WoodPlanks,
			Parent = parent,
		})

		for sideIndex, side in ipairs({ -1, 1 }) do
			local right = span:Cross(Vector3.yAxis).Unit
			local railPoint = plankCenter + right * side * 2.6 + Vector3.new(0, 2.2, 0)
			local previous = previousRail[sideIndex]
			if previous ~= nil then
				local ropeSpan = railPoint - previous
				createPart({
					Name = "BridgeRope",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(ropeSpan.Magnitude + 0.3, 0.35, 0.35),
					CFrame = CFrame.lookAt(previous + ropeSpan / 2, railPoint)
						* CFrame.Angles(0, math.rad(90), 0),
					Color = ROPE_COLOR,
					Material = Enum.Material.Fabric,
					CanCollide = false,
					Parent = parent,
				})
			end
			previousRail[sideIndex] = railPoint
		end
	end

	for _, endPosition in ipairs({ fromPosition, toPosition }) do
		for _, side in ipairs({ -1, 1 }) do
			local right = span:Cross(Vector3.yAxis).Unit
			createPart({
				Name = "BridgePost",
				Size = Vector3.new(0.9, 4.4, 0.9),
				Position = endPosition + right * side * 2.6 + Vector3.new(0, 2.2, 0),
				Color = WOOD_COLOR,
				Material = Enum.Material.Wood,
				CanCollide = false,
				Parent = parent,
			})
		end
	end
end

-- Rune slabs orbiting the portal ring, the sky whale, and the bobbing
-- balloon are all driven by one Heartbeat updater started later.
local orbitingRunes: { BasePart } = {}
local skyWhale: Model? = nil
local dockBalloon: BasePart? = nil

--[[
	The three satellite isles: the portal ring monument, the carnival
	with the prize wheel, and the balloon dock teasing future travel.
]]
local function buildSatellites(parent: Instance)
	-- Portal Ring isle: a broken stone circle with the green portal
	-- disc inside and runes orbiting it.
	local ringCenter = PORTAL_ISLE + Vector3.new(0, 9, 0)
	for blockIndex = 0, 11 do
		local angle = blockIndex / 12 * math.pi * 2
		createPart({
			Name = "PortalRingStone",
			Size = Vector3.new(2.6, 3.4, 2),
			CFrame = CFrame.new(
				ringCenter + Vector3.new(math.cos(angle) * 9, math.sin(angle) * 9, 0)
			) * CFrame.Angles(0, 0, angle),
			Color = Color3.fromRGB(96, 102, 116),
			Material = Enum.Material.Slate,
			Parent = parent,
		})
	end

	local swirl = createPart({
		Name = "Portal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 13, 13),
		CFrame = CFrame.new(ringCenter) * CFrame.Angles(0, math.rad(90), 0),
		Color = PORTAL_GREEN,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		CanCollide = false,
		Parent = parent,
	})
	swirl:SetAttribute("WorldIndex", 1)
	addPrompt(swirl, "Travel", "Portal")
	addBillboard(swirl, "PORTAL -- TRAVEL TO THE WORLDS!", PORTAL_GREEN, 10)
	addOutline(swirl, Color3.fromRGB(160, 255, 130))
	CollectionService:AddTag(swirl, "Portal")

	for runeIndex = 1, 5 do
		local rune = createPart({
			Name = "PortalRune",
			Size = Vector3.new(1.2, 1.8, 0.4),
			Position = ringCenter,
			Color = PORTAL_GREEN,
			Material = Enum.Material.Neon,
			Transparency = 0.15,
			CanCollide = false,
			CanQuery = false,
			Parent = parent,
		})
		orbitingRunes[runeIndex] = rune
	end

	placeProp(
		parent,
		naturePath("Pine Tree"),
		PORTAL_ISLE + Vector3.new(-26, 0, 14),
		11,
		30,
		fallbackTree
	)
	placeProp(
		parent,
		naturePath("Tall Pine Tree 2"),
		PORTAL_ISLE + Vector3.new(24, 0, -16),
		13,
		220,
		fallbackTree
	)
	placeProp(parent, naturePath("Big Rock"), PORTAL_ISLE + Vector3.new(18, 0, 20), 4, 70)

	-- Carnival isle: the prize wheel, two striped tents, a snack table
	-- with colossal candy, and its own lights.
	local wheelBase = CARNIVAL_ISLE
	local wheelHeight = 11
	for _, postOffset in ipairs({ -2.4, 2.4 }) do
		createPart({
			Name = "WheelPost",
			Size = Vector3.new(1.4, wheelHeight + 2, 1.4),
			Position = wheelBase + Vector3.new(0, (wheelHeight + 2) / 2, postOffset),
			Color = WOOD_COLOR,
			Material = Enum.Material.Wood,
			Parent = parent,
		})
	end
	local disc = createPart({
		Name = "WheelDisc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 18, 18),
		CFrame = CFrame.new(wheelBase + Vector3.new(0, wheelHeight, 0)),
		Color = WHITE_COLOR,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	for rewardIndex, reward in ipairs(GameConfig.wheel.rewards) do
		local angle = (rewardIndex - 1) / #GameConfig.wheel.rewards * math.pi * 2
		createPart({
			Name = "WheelSpoke" .. rewardIndex,
			Size = Vector3.new(0.4, 1.6, 7),
			CFrame = CFrame.new(wheelBase + Vector3.new(1.1, wheelHeight, 0))
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
		CFrame = CFrame.new(wheelBase + Vector3.new(1.1, wheelHeight + 10, 0))
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

	for tentIndex, tentOffset in ipairs({ Vector3.new(-22, 0, -14), Vector3.new(20, 0, 18) }) do
		local tentBase = CARNIVAL_ISLE + tentOffset
		createPart({
			Name = "TentPole",
			Size = Vector3.new(0.8, 9, 0.8),
			Position = tentBase + Vector3.new(0, 4.5, 0),
			Color = WOOD_COLOR,
			Material = Enum.Material.Wood,
			CanCollide = false,
			Parent = parent,
		})
		for panelIndex = 0, 7 do
			local angle = panelIndex / 8 * math.pi * 2
			local wedge = Instance.new("WedgePart")
			wedge.Anchored = true
			wedge.Size = Vector3.new(4.6, 4.6, 6.4)
			wedge.CFrame = CFrame.new(
				tentBase + Vector3.new(math.cos(angle) * 3.4, 6.4, math.sin(angle) * 3.4)
			) * CFrame.Angles(0, -angle + math.pi / 2, 0) * CFrame.Angles(math.rad(180), 0, 0)
			wedge.Color = if (panelIndex + tentIndex) % 2 == 0
				then Color3.fromRGB(235, 69, 44)
				else WHITE_COLOR
			wedge.Material = Enum.Material.SmoothPlastic
			wedge.CanCollide = false
			wedge.TopSurface = Enum.SurfaceType.Smooth
			wedge.BottomSurface = Enum.SurfaceType.Smooth
			wedge.Parent = parent
		end
	end

	placeProp(
		parent,
		cityPath("Restaurant Related", "Parasol"),
		CARNIVAL_ISLE + Vector3.new(-8, 0, 22),
		7,
		80
	)
	local candyCounter = createPart({
		Name = "CandyCounter",
		Size = Vector3.new(9, 3, 2.6),
		Position = CARNIVAL_ISLE + Vector3.new(12, 1.5, -18),
		Color = WOOD_COLOR,
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	addBillboard(candyCounter, "CARNIVAL SNACKS!", Color3.fromRGB(255, 168, 120), 6)
	placeProp(
		parent,
		foodPath("food_1"),
		candyCounter.Position + Vector3.new(-2.6, 1.6, 0),
		2.4,
		20
	)
	placeProp(
		parent,
		foodPath("food_12"),
		candyCounter.Position + Vector3.new(0.4, 1.6, 0),
		2.8,
		200
	)
	placeProp(parent, foodPath("food_24"), candyCounter.Position + Vector3.new(3, 1.6, 0), 2.4, 90)

	local carnivalLamp = placeProp(
		parent,
		cityPath("City Lamps", "Round Street Lamp 2"),
		CARNIVAL_ISLE + Vector3.new(0, 0, -28),
		9,
		0,
		fallbackLamp
	)
	if carnivalLamp ~= nil then
		addTopLight(carnivalLamp)
	end

	-- Balloon dock: the moored hot-air balloon that bobs on the wind.
	local dockCenter = BALLOON_ISLE
	createPart({
		Name = "DockPlatform",
		Size = Vector3.new(14, 1, 14),
		Position = dockCenter + Vector3.new(0, 0.5, 0),
		Color = PLANK_COLOR,
		Material = Enum.Material.WoodPlanks,
		Parent = parent,
	})
	createPart({
		Name = "MooringPost",
		Size = Vector3.new(1, 5, 1),
		Position = dockCenter + Vector3.new(5, 2.5, 5),
		Color = WOOD_COLOR,
		Material = Enum.Material.Wood,
		CanCollide = false,
		Parent = parent,
	})

	createPart({
		Name = "BalloonBasket",
		Size = Vector3.new(4.4, 3.2, 4.4),
		Position = dockCenter + Vector3.new(0, 3.4, 0),
		Color = Color3.fromRGB(140, 104, 62),
		Material = Enum.Material.Wood,
		CanCollide = false,
		Parent = parent,
	})
	local envelope = createPart({
		Name = "BalloonEnvelope",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(15, 16, 15),
		Position = dockCenter + Vector3.new(0, 15, 0),
		Color = Color3.fromRGB(235, 69, 44),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = parent,
	})
	for ropeIndex = 0, 3 do
		local angle = ropeIndex / 4 * math.pi * 2 + math.pi / 4
		createPart({
			Name = "BalloonRope",
			Size = Vector3.new(0.3, 7, 0.3),
			Position = dockCenter + Vector3.new(math.cos(angle) * 2, 8.2, math.sin(angle) * 2),
			Color = ROPE_COLOR,
			Material = Enum.Material.Fabric,
			CanCollide = false,
			Parent = parent,
		})
	end
	dockBalloon = envelope
	local dockSign = createPart({
		Name = "DockSign",
		Size = Vector3.new(0.8, 4.4, 0.8),
		Position = dockCenter + Vector3.new(-6, 2.2, 6),
		Color = WOOD_COLOR,
		Material = Enum.Material.Wood,
		CanCollide = false,
		Parent = parent,
	})
	addBillboard(dockSign, "AIR TRAVEL -- COMING SOON!", SIGN_TEXT_COLOR, 3)

	-- The bridges: cove to the portal ring, west lawn to the carnival,
	-- mid-tier east edge to the balloon dock.
	buildRopeBridge(parent, CENTER + Vector3.new(-55, 0, 235), PORTAL_ISLE + Vector3.new(2, 0, -40))
	buildRopeBridge(
		parent,
		CENTER + Vector3.new(-228, 0, 58),
		CARNIVAL_ISLE + Vector3.new(44, 0, 2)
	)
	buildRopeBridge(
		parent,
		CENTER + Vector3.new(170, TIER_MID, -105),
		BALLOON_ISLE + Vector3.new(-30, 0, 10)
	)
end

--[[
	The forest, in species bands: pines crown the high tier, broadleaf
	hugs the town's north and west walls, scatter fills the low tier
	and its rim, and understory props thicken the floor everywhere.
	Deterministic jitter keeps it organic but identical every server.
]]
local function buildForest(parent: Instance)
	local PINES = {
		"Tall Pine Tree",
		"Pine Tree",
		"Tall Pine Tree 2",
		"Pine Tree 2",
		"Tall Pine Tree 3",
		"Weird Pine Tree",
		"Tall Pine Tree 4",
	}
	local BROADLEAF = {
		"Tall Tree",
		"Tree",
		"Double Tree",
		"Birch Tree",
		"Tree 2",
		"Squared Tree",
		"Bigger Tree",
		"U Shaped Tree",
	}

	local function jitter(amount: number): Vector3
		return Vector3.new(rng:NextNumber(-amount, amount), 0, rng:NextNumber(-amount, amount))
	end

	-- Pine band: two arcs around the high tier, clear of the tree,
	-- pond, and stair.
	local pineIndex = 0
	for _, arc in ipairs({
		{
			center = Vector3.new(-145, TIER_HIGH, -130),
			radius = 72,
			fromAngle = 100,
			toAngle = 320,
			count = 10,
		},
		{
			center = Vector3.new(-100, TIER_HIGH, -195),
			radius = 42,
			fromAngle = 120,
			toAngle = 300,
			count = 6,
		},
	}) do
		for arcStep = 0, arc.count - 1 do
			local angle =
				math.rad(arc.fromAngle + (arc.toAngle - arc.fromAngle) * arcStep / (arc.count - 1))
			pineIndex += 1
			placeProp(
				parent,
				naturePath(PINES[pineIndex % #PINES + 1]),
				CENTER
					+ arc.center
					+ Vector3.new(math.cos(angle) * arc.radius, 0, math.sin(angle) * arc.radius)
					+ jitter(6),
				13 + (pineIndex % 4),
				pineIndex * 53,
				fallbackTree
			)
		end
	end

	-- Broadleaf hugging the town's west and north walls.
	local leafIndex = 0
	for wallStep = 0, 5 do
		leafIndex += 1
		placeProp(
			parent,
			naturePath(BROADLEAF[leafIndex % #BROADLEAF + 1]),
			CENTER + Vector3.new(-45 + rng:NextNumber(-5, 3), TIER_MID, -150 + wallStep * 30),
			11 + (leafIndex % 4),
			leafIndex * 77,
			fallbackTree
		)
	end
	for wallStep = 0, 3 do
		leafIndex += 1
		placeProp(
			parent,
			naturePath(BROADLEAF[leafIndex % #BROADLEAF + 1]),
			CENTER + Vector3.new(-10 + wallStep * 40, TIER_MID, -180 + rng:NextNumber(-4, 4)),
			12 + (leafIndex % 3),
			leafIndex * 77,
			fallbackTree
		)
	end
	leafIndex += 1
	placeProp(
		parent,
		naturePath("Rooted Tree"),
		CENTER + Vector3.new(150, TIER_MID, -160),
		13,
		40,
		fallbackTree
	)

	-- Low tier scatter and rim ring.
	for _, spot in ipairs({
		Vector3.new(-150, 0, 40),
		Vector3.new(-170, 0, 120),
		Vector3.new(-130, 0, 190),
		Vector3.new(135, 0, 70),
		Vector3.new(185, 0, 60),
		Vector3.new(200, 0, 150),
		Vector3.new(120, 0, 200),
		Vector3.new(-20, 0, 120),
		Vector3.new(95, 0, 55),
		Vector3.new(-125, 0, 65),
	}) do
		leafIndex += 1
		placeProp(
			parent,
			naturePath(BROADLEAF[leafIndex % #BROADLEAF + 1]),
			CENTER + spot + jitter(7),
			11 + (leafIndex % 4),
			leafIndex * 31,
			fallbackTree
		)
	end
	-- Rim ring: explicit spots, each at its tier's height, so no tree
	-- spawns buried in the plateau or hill.
	for rimStep, rimSpot in ipairs({
		Vector3.new(210, 0, 85),
		Vector3.new(144, 0, 200),
		Vector3.new(22, 0, 252),
		Vector3.new(-107, 0, 226),
		Vector3.new(-196, 0, 127),
		Vector3.new(-225, 0, 20),
		Vector3.new(-160, TIER_HIGH, -120),
		Vector3.new(-22, TIER_MID, -174),
		Vector3.new(150, TIER_MID, -178),
		Vector3.new(196, 0, -47),
	}) do
		leafIndex += 1
		placeProp(
			parent,
			naturePath(
				if rimStep % 3 == 0
					then PINES[rimStep % #PINES + 1]
					else BROADLEAF[leafIndex % #BROADLEAF + 1]
			),
			CENTER + rimSpot + jitter(6),
			12 + (rimStep % 4),
			rimStep * 47,
			fallbackTree
		)
	end

	-- Hatchery grove.
	placeProp(
		parent,
		naturePath("Birch Tree"),
		HATCHERY_CENTER + Vector3.new(-28, 0, -18),
		12,
		30,
		fallbackTree
	)
	placeProp(
		parent,
		naturePath("Tree 2"),
		HATCHERY_CENTER + Vector3.new(30, 0, -22),
		11,
		140,
		fallbackTree
	)
	placeProp(
		parent,
		naturePath("Tall Tree"),
		HATCHERY_CENTER + Vector3.new(26, 0, 30),
		13,
		260,
		fallbackTree
	)

	-- Understory: bushes, flowers, mushrooms, rocks, logs, stumps, and
	-- a bamboo cluster near the lower falls.
	local UNDERSTORY = {
		{ prop = "Bush", height = 3 },
		{ prop = "Bush 2", height = 3 },
		{ prop = "Tall Bush Flower", height = 3.5 },
		{ prop = "Tall Bush Flower 2", height = 3.5 },
		{ prop = "Flower 1", height = 2 },
		{ prop = "Flower 4", height = 2 },
		{ prop = "Flower 6", height = 2 },
		{ prop = "Flower 8", height = 2 },
		{ prop = "Flower 10", height = 2 },
		{ prop = "Mushroom", height = 2.4 },
		{ prop = "Big Mushroom", height = 3.6 },
		{ prop = "Rock 1", height = 3 },
		{ prop = "Rock 2", height = 2.6 },
		{ prop = "Big Rock", height = 4.4 },
		{ prop = "Round Rock", height = 2.6 },
		{ prop = "Log 1", height = 2 },
		{ prop = "Log 2", height = 2 },
		{ prop = "Tree Stump", height = 2.4 },
		{ prop = "Round Plant", height = 2.4 },
		{ prop = "Plant", height = 2.4 },
	}
	local understorySpots = {
		Vector3.new(-120, 0, 150),
		Vector3.new(-150, 0, 90),
		Vector3.new(-100, 0, 45),
		Vector3.new(-30, 0, 130),
		Vector3.new(100, 0, 90),
		Vector3.new(140, 0, 60),
		Vector3.new(175, 0, 110),
		Vector3.new(110, 0, 165),
		Vector3.new(-165, TIER_HIGH, -90),
		Vector3.new(-190, TIER_HIGH, -140),
		Vector3.new(-120, TIER_HIGH, -190),
		Vector3.new(-70, TIER_HIGH, -145),
		Vector3.new(-45, TIER_MID, -35),
		Vector3.new(-40, TIER_MID, -110),
		Vector3.new(150, TIER_MID, -125),
		Vector3.new(20, TIER_MID, -185),
		Vector3.new(90, TIER_MID, -190),
		Vector3.new(-95, 0, 230),
		Vector3.new(80, 0, 230),
		Vector3.new(-200, 0, 60),
	}
	for spotIndex, spot in ipairs(understorySpots) do
		local pick = UNDERSTORY[(spotIndex * 7) % #UNDERSTORY + 1]
		placeProp(
			parent,
			naturePath(pick.prop),
			CENTER + spot + jitter(5),
			pick.height,
			spotIndex * 83
		)
	end

	for bambooIndex = 1, 3 do
		placeProp(
			parent,
			bundlePath("Bamboo Packs", bambooIndex),
			CENTER + Vector3.new(34 + bambooIndex * 5, 0, 58 + bambooIndex * 3),
			7,
			bambooIndex * 120
		)
	end
	placeProp(parent, bundlePath("Stones Pack", 2), CENTER + Vector3.new(-14, 0, 60), 2.6, 50)
	placeProp(parent, bundlePath("Stones Pack", 5), CENTER + Vector3.new(96, 0, 130), 3, 190)
end

--[[
	One Heartbeat drives every ambient motion: the sky whale's slow
	orbit around the island, the runes circling the portal ring, and
	the balloon's bob. Skipping missing pieces keeps the loop safe
	when packs have not synced.
]]
local function startAmbientLoop()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(deltaSeconds)
		elapsed += deltaSeconds

		local whale = skyWhale
		if whale ~= nil and whale.Parent ~= nil then
			local angle = elapsed * (math.pi * 2 / 90)
			local position = CENTER
				+ Vector3.new(
					math.cos(angle) * 380,
					40 + math.sin(elapsed * 0.35) * 6,
					math.sin(angle) * 380
				)
			local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
			whale:PivotTo(CFrame.lookAt(position, position + tangent))
		end

		local ringCenter = PORTAL_ISLE + Vector3.new(0, 9, 0)
		for runeIndex, rune in ipairs(orbitingRunes) do
			if rune.Parent ~= nil then
				local runeAngle = elapsed * 0.7 + runeIndex * (math.pi * 2 / #orbitingRunes)
				rune.CFrame = CFrame.new(
					ringCenter
						+ Vector3.new(
							math.cos(runeAngle) * 13,
							math.sin(runeAngle * 1.7) * 3,
							math.sin(runeAngle) * 13
						)
				) * CFrame.Angles(0, runeAngle, 0)
			end
		end

		local balloon = dockBalloon
		if balloon ~= nil and balloon.Parent ~= nil then
			balloon.Position = BALLOON_ISLE + Vector3.new(0, 15 + math.sin(elapsed * 0.8) * 1.4, 0)
		end
	end)
end

--[[
	The TDS town island: the bought map floating as its own island in
	the terrace's view. Unlike hub decorations, the map keeps its
	authored collision -- only anchoring is forced -- so every street,
	roof, and prop is physically walkable.
]]
local function buildTdsIsland(modelsFolder: Instance)
	if Workspace:FindFirstChild("TdsIsland") ~= nil then
		return
	end

	local pack = modelsFolder:FindFirstChild("Tds_Town_Pack")
	local template = if pack ~= nil then pack:FindFirstChild("Scenery") else nil
	if template == nil or not template:IsA("Model") then
		warn("TDS town pack missing; skipping the TDS island")
		return
	end

	local tds = GameConfig.tdsIsland
	local islandCenter = Vector3.new(tds.centerX, tds.surfaceY, tds.centerZ)
	-- The platform outsizes the map enough to leave the arrival strip
	-- clear on the hub-facing edge.
	local platformSize = tds.footprint + 60

	local islandFolder = Instance.new("Folder")
	islandFolder.Name = "TdsIsland"

	createPart({
		Name = "IslandGrass",
		Size = Vector3.new(platformSize, ISLAND_THICKNESS, platformSize),
		Position = islandCenter - Vector3.new(0, ISLAND_THICKNESS / 2, 0),
		Color = GRASS_COLOR,
		Material = Enum.Material.Grass,
		Parent = islandFolder,
	})

	createPart({
		Name = "IslandDirt",
		Size = Vector3.new(platformSize - 50, 30, platformSize - 50),
		Position = islandCenter - Vector3.new(0, ISLAND_THICKNESS + 15, 0),
		Color = DIRT_COLOR,
		Material = Enum.Material.Ground,
		Parent = islandFolder,
	})

	for shelfIndex, shelf in ipairs({
		{ size = 250, height = 26, drop = 47 },
		{ size = 150, height = 22, drop = 70 },
		{ size = 70, height = 18, drop = 89 },
	}) do
		createPart({
			Name = "IslandRock" .. shelfIndex,
			Size = Vector3.new(shelf.size, shelf.height, shelf.size),
			Position = islandCenter - Vector3.new(0, shelf.drop, 0),
			Color = ROCK_COLOR,
			Material = Enum.Material.Slate,
			Parent = islandFolder,
		})
	end

	local town = template:Clone()
	for _, descendant in ipairs(town:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	local extents = town:GetExtentsSize()
	local widest = math.max(extents.X, extents.Z)
	if widest < 1 then
		town:Destroy()
		islandFolder:Destroy()
		return
	end

	town:ScaleTo(tds.footprint / widest)

	-- Nudged away from the arrival edge so the pad and portal stay in
	-- the open.
	local boxCFrame, boxSize = town:GetBoundingBox()
	local target = islandCenter + Vector3.new(0, boxSize.Y / 2, 25)
	town:PivotTo(town:GetPivot() + (target - boxCFrame.Position))
	town.Name = "TdsTown"
	town.Parent = islandFolder

	-- The arrival strip: teleports land on the pad, the sign says where
	-- you are, and the portal takes you anywhere else.
	local padPosition = islandCenter + Vector3.new(0, 0, tds.padOffsetZ)
	local pad = createPart({
		Name = "TdsArrivalPad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 22, 22),
		CFrame = CFrame.new(padPosition + Vector3.new(0, 0.3, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = GOLD_COLOR,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = islandFolder,
	})
	addBillboard(pad, "TDS TOWN -- EXPLORE THE STREETS!", GOLD_COLOR, 9)

	for _, pillarOffset in ipairs({ -8, 8 }) do
		createPart({
			Name = "PortalPillar",
			Size = Vector3.new(2, 15, 2),
			Position = padPosition + Vector3.new(pillarOffset + 34, 7.5, 0),
			Color = Color3.fromRGB(62, 74, 96),
			Material = Enum.Material.Slate,
			Parent = islandFolder,
		})
	end

	createPart({
		Name = "PortalArch",
		Size = Vector3.new(20, 2, 2),
		Position = padPosition + Vector3.new(34, 16, 0),
		Color = Color3.fromRGB(62, 74, 96),
		Material = Enum.Material.Slate,
		Parent = islandFolder,
	})

	-- Same orientation convention as every other portal: the cylinder's
	-- flat axis faces the walker so PortalFx spins its rings correctly.
	local swirl = createPart({
		Name = "Portal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 13, 13),
		CFrame = CFrame.new(padPosition + Vector3.new(34, 7.5, 0))
			* CFrame.Angles(0, math.rad(90), 0),
		Color = PORTAL_GREEN,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		CanCollide = false,
		Parent = islandFolder,
	})
	addPrompt(swirl, "Travel", "Portal")
	addBillboard(swirl, "PORTAL -- TRAVEL BACK!", PORTAL_GREEN, 9)
	addOutline(swirl, Color3.fromRGB(160, 255, 130))
	CollectionService:AddTag(swirl, "Portal")

	islandFolder.Parent = Workspace
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

	sculptIsland()
	buildWorldTree(hubFolder)
	buildFalls(hubFolder)
	buildPlaza(hubFolder)
	buildRoads(hubFolder)
	seatTown(hubFolder)
	buildMarketRow(hubFolder)
	buildHatchery(hubFolder)
	buildCove(hubFolder)
	buildGrotto(hubFolder)
	buildSatellites(hubFolder)
	buildForest(hubFolder)

	-- The sky whale spawns on its orbit; the ambient loop flies it.
	skyWhale = placeProp(hubFolder, seaPath("Whale"), CENTER + Vector3.new(380, 40, 0), 24, 90)
	startAmbientLoop()

	-- The previous separate TDS island, preserved behind its flag.
	if GameConfig.tdsIsland.enabled and modelsFolder ~= nil then
		buildTdsIsland(modelsFolder)
	end

	hubFolder.Parent = Workspace
end

return HubService
