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

-- Tier heights above hub.surfaceY. Cliff-steep terrain: the town
-- plateau and the tree hill are real height, not mounds.
local TIER_MID = 22
local TIER_HIGH = 55
local TIER_DECK = 82

-- The client wires its landing listener during boot; this delay keeps
-- the cutscene event from firing before anyone is listening.
local WELCOME_DELAY_SECONDS = 1.2

local hub = GameConfig.hub
local CENTER = Vector3.new(hub.centerX, hub.surfaceY, hub.centerZ)

-- The spawn plaza sits on the low tier's west side; the landing pad is
-- its centerpiece and the cutscene target.
local PAD_POSITION = CENTER + Vector3.new(-90, 0, 95)
-- The dais top surface above the plaza floor; arrivals and the
-- cutscene both land relative to this.
local PAD_SURFACE_HEIGHT = 3.2

-- Anchor points the layout hangs off. Front of the island is +Z.
local TREE_BASE = CENTER + Vector3.new(-140, TIER_HIGH, -135)
local TOWN_CENTER = CENTER + Vector3.new(55, TIER_MID, -70)
local LAGOON_CENTER = CENTER + Vector3.new(30, 0, 70)
local LAGOON_RADIUS = 48
local HATCHERY_CENTER = CENTER + Vector3.new(150, 0, 120)
local GROTTO_CENTER = CENTER + Vector3.new(-60, -16, 150)
local PORTAL_ISLE = CENTER + Vector3.new(-60, -8, 330)
local CARNIVAL_ISLE = CENTER + Vector3.new(-300, 4, 60)
local BALLOON_ISLE = CENTER + Vector3.new(285, 26, -150)

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
	Sculpts the island body: a rolling low tier with grassy knolls and
	rim crags, a cliff-walled town plateau, a tall tree hill, the
	tapering rock keel, the sand cove, the lagoon with the sky-well
	carved through the island, the spring pond and mid pool, the
	open-cut grotto stair, and the satellite isles. Plateau and hill
	are stacked shrinking layers, so their faces read as real cliffs
	instead of smoothed mounds.
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

	-- Rolling ground: shallow grass knolls scattered across the lawns.
	for _, knoll in ipairs({
		{ offset = Vector3.new(-150, 0, 60), radius = 38, rise = 6 },
		{ offset = Vector3.new(-170, 0, 150), radius = 30, rise = 5 },
		{ offset = Vector3.new(170, 0, 60), radius = 24, rise = 4 },
		{ offset = Vector3.new(110, 0, 180), radius = 30, rise = 5 },
		{ offset = Vector3.new(-110, 0, 30), radius = 26, rise = 4 },
		{ offset = Vector3.new(75, 0, 138), radius = 22, rise = 3.5 },
	}) do
		terrain:FillBall(
			CENTER + knoll.offset + Vector3.new(0, knoll.rise - knoll.radius, 0),
			knoll.radius,
			Enum.Material.Grass
		)
	end

	-- Rim crags: rock teeth around the island edge.
	for _, crag in ipairs({
		{ offset = Vector3.new(215, 0, 90), radius = 12 },
		{ offset = Vector3.new(150, 0, 215), radius = 10 },
		{ offset = Vector3.new(-90, 0, 240), radius = 11 },
		{ offset = Vector3.new(-205, 0, 130), radius = 13 },
		{ offset = Vector3.new(-235, 0, 10), radius = 10 },
		{ offset = Vector3.new(205, 0, -25), radius = 11 },
	}) do
		terrain:FillBall(
			CENTER + crag.offset + Vector3.new(0, crag.radius * 0.35, 0),
			crag.radius,
			Enum.Material.Rock
		)
	end

	-- Town plateau: stacked shrinking rock slabs make ~70 degree cliff
	-- faces, sized tight to the town's measured 172 x 163 footprint.
	local plateauCenter = CENTER + Vector3.new(55, 0, -70)
	for layerIndex = 0, 4 do
		local shrink = (4 - layerIndex) * 10
		fillBox(
			plateauCenter + Vector3.new(0, 2 + layerIndex * 4.5, 0),
			Vector3.new(205 + shrink, 6, 195 + shrink),
			Enum.Material.Rock
		)
	end
	fillBox(
		plateauCenter + Vector3.new(0, TIER_MID - 1.5, 0),
		Vector3.new(205, 5, 195),
		Enum.Material.Grass
	)

	-- Tree hill: two stacked-disc lobes rising to the high tier.
	for _, lobe in ipairs({
		{ offset = Vector3.new(-145, 0, -130), radius = 95, topRadius = 62 },
		{ offset = Vector3.new(-100, 0, -195), radius = 60, topRadius = 38 },
	}) do
		local base = CENTER + lobe.offset
		for layerIndex = 0, 6 do
			local progress = layerIndex / 6
			local radius = lobe.radius + (lobe.topRadius - lobe.radius) * progress
			fillDisc(
				base + Vector3.new(0, 3 + progress * (TIER_HIGH - 8), 0),
				9,
				radius,
				Enum.Material.Rock
			)
		end
		fillDisc(base + Vector3.new(0, TIER_HIGH - 1.5, 0), 5, lobe.topRadius, Enum.Material.Grass)
	end

	-- Rock underside: shrinking discs taper the island to a keel.
	fillDisc(CENTER + Vector3.new(0, -20, 30), 24, 200, Enum.Material.Rock)
	fillDisc(CENTER + Vector3.new(20, -45, 0), 26, 140, Enum.Material.Rock)
	fillDisc(CENTER + Vector3.new(-30, -72, 10), 28, 85, Enum.Material.Rock)
	fillDisc(CENTER + Vector3.new(30, -105, -10), 30, 45, Enum.Material.Rock)

	-- Sand cove along the front edge.
	fillBox(CENTER + Vector3.new(-10, -1, 185), Vector3.new(200, 6, 90), Enum.Material.Sand)

	-- Lagoon: carve the basin, fill the water, then carve the sky-well
	-- straight through the island. The water ring holds; the hole
	-- falls into open sky (the safety net below catches the ride).
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

	-- Grotto: an air pocket under the cove, entered by an open-cut
	-- trench sloping down from the sand (stairs and rails are built in
	-- buildGrotto, so the hole reads as an entrance, not a trap).
	fillDisc(GROTTO_CENTER, 14, 15, Enum.Material.Air)
	fillBox(CENTER + Vector3.new(-60, -2, 182), Vector3.new(12, 8, 14), Enum.Material.Air)
	fillBox(CENTER + Vector3.new(-60, -7, 170), Vector3.new(12, 10, 14), Enum.Material.Air)
	fillBox(CENTER + Vector3.new(-60, -12, 158), Vector3.new(12, 12, 14), Enum.Material.Air)

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
		{ offset = Vector3.new(0, 5, 0), radius = 21 },
		{ offset = Vector3.new(-15, -2, 8), radius = 15 },
		{ offset = Vector3.new(15, -1, -8), radius = 15 },
		{ offset = Vector3.new(8, 0, 14), radius = 12 },
		{ offset = Vector3.new(-9, 1, -14), radius = 12 },
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
	local STEP_COUNT = 34
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
	The river's vertical moments: a 33-stud fall off the tree hill, a
	22-stud fall off the plateau cliff into the lagoon, and the
	sky-well column falling from the lagoon's hole straight through
	the island. Flat water between them is terrain, sculpted earlier.
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

	-- Hill lip: pond overflow plunges to the mid pool's channel, at
	-- the point the hill's top rim crosses the flow line.
	fallColumn(CENTER + Vector3.new(-92, TIER_HIGH, -90), TIER_HIGH - TIER_MID, 5)
	-- Plateau cliff lip: mid pool down to the lagoon.
	fallColumn(CENTER + Vector3.new(22, TIER_MID, 27), TIER_MID, 5)

	-- The sky-well: the lagoon drains through the island. The column
	-- runs from the water surface down past the keel.
	createPart({
		Name = "SkyWellColumn",
		Size = Vector3.new(9, 130, 9),
		Position = LAGOON_CENTER + Vector3.new(0, -65, 0),
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
	addBillboard(
		rim,
		"THE SKY-WELL -- JUMP IN, IT BRINGS YOU HOME!",
		Color3.fromRGB(180, 226, 244),
		7
	)
	addGlowMotes(parent, LAGOON_CENTER + Vector3.new(0, 1.5, 0), Color3.fromRGB(210, 240, 250), 16)

	-- Terrain water cannot slope, so each channel is a flat strip and
	-- the falls carry the height.
	for _, strip in ipairs({
		{
			from = TREE_BASE + Vector3.new(30, 0, 35),
			to = CENTER + Vector3.new(-92, TIER_HIGH, -90),
		},
		{
			from = CENTER + Vector3.new(0, TIER_MID, -20),
			to = CENTER + Vector3.new(22, TIER_MID, 27),
		},
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
	-- The landing dais: three stone steps to a gold-ringed marble top,
	-- rune beacons on the diagonals, and light rays climbing into the
	-- sky the cutscene dives out of. The pulse ring is named so the
	-- client can flare it on touchdown.
	for stepIndex, step in ipairs({
		{ diameter = 30, lift = 0.45 },
		{ diameter = 25, lift = 1.35 },
		{ diameter = 20, lift = 2.25 },
	}) do
		createPart({
			Name = "PadStep" .. stepIndex,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.9, step.diameter, step.diameter),
			CFrame = CFrame.new(PAD_POSITION + Vector3.new(0, step.lift, 0))
				* CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(
				205 - stepIndex * 12,
				199 - stepIndex * 12,
				186 - stepIndex * 10
			),
			Material = Enum.Material.Slate,
			Parent = parent,
		})
	end

	local pad = createPart({
		Name = "LandingPad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 18, 18),
		CFrame = CFrame.new(PAD_POSITION + Vector3.new(0, PAD_SURFACE_HEIGHT - 0.5, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = WHITE_COLOR,
		Material = Enum.Material.Marble,
		Parent = parent,
	})
	addBillboard(pad, "MAIN ISLAND", GOLD_COLOR, 12)

	createPart({
		Name = "PadPulseRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 19.5, 19.5),
		CFrame = CFrame.new(PAD_POSITION + Vector3.new(0, PAD_SURFACE_HEIGHT - 0.3, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = GOLD_COLOR,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = parent,
	})

	-- Light rays: tall soft neon columns rising from the pad, fading
	-- with height so the beam reads without blinding anyone.
	for rayIndex, raySpec in ipairs({
		{ offset = Vector3.new(0, 0, 0), height = 34, width = 1.6, tilt = 0 },
		{ offset = Vector3.new(-3.4, 0, 2), height = 26, width = 1, tilt = 4 },
		{ offset = Vector3.new(3.2, 0, -2.4), height = 28, width = 1, tilt = -4 },
	}) do
		createPart({
			Name = "PadRay" .. rayIndex,
			Size = Vector3.new(raySpec.width, raySpec.height, raySpec.width),
			CFrame = CFrame.new(
				PAD_POSITION + raySpec.offset + Vector3.new(0, raySpec.height / 2 + 3, 0)
			) * CFrame.Angles(0, 0, math.rad(raySpec.tilt)),
			Color = Color3.fromRGB(255, 233, 168),
			Material = Enum.Material.Neon,
			Transparency = 0.62,
			CanCollide = false,
			CanQuery = false,
			Parent = parent,
		})
	end

	-- Rune beacons on the diagonals: slate pillars, glowing orbs, and a
	-- tilted spinner ring the client already knows how to rotate.
	for beaconIndex = 1, 4 do
		local beaconAngle = (beaconIndex - 0.5) / 4 * math.pi * 2
		local beaconBase = PAD_POSITION
			+ Vector3.new(math.cos(beaconAngle) * 14, 0, math.sin(beaconAngle) * 14)

		createPart({
			Name = "BeaconPillar" .. beaconIndex,
			Size = Vector3.new(1.3, 9, 1.3),
			Position = beaconBase + Vector3.new(0, 4.5, 0),
			Color = Color3.fromRGB(62, 74, 96),
			Material = Enum.Material.Slate,
			Parent = parent,
		})

		local orb = createPart({
			Name = "BeaconOrb" .. beaconIndex,
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.8, 1.8, 1.8),
			Position = beaconBase + Vector3.new(0, 9.8, 0),
			Color = Color3.fromRGB(255, 233, 168),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = parent,
		})

		local orbLight = Instance.new("PointLight")
		orbLight.Color = GOLD_COLOR
		orbLight.Brightness = 1.6
		orbLight.Range = 18
		orbLight.Parent = orb

		local runeRing = createPart({
			Name = "BeaconRing" .. beaconIndex,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.25, 3.2, 3.2),
			CFrame = CFrame.new(beaconBase + Vector3.new(0, 9.8, 0))
				* CFrame.Angles(math.rad(25), 0, math.rad(115)),
			Color = GOLD_COLOR,
			Material = Enum.Material.Neon,
			Transparency = 0.35,
			CanCollide = false,
			Parent = parent,
		})
		CollectionService:AddTag(runeRing, "Spinner")
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
	the tier changes ride long sloped ramps so every route stays
	walkable at the new cliff heights. Two roads run into the town's
	open south and west sides.
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

	-- Plaza to the town's south entry: flat approach, long ramp up the
	-- cliff, then into the open south side.
	flatRoad(Vector3.new(-70, 0, 95), Vector3.new(10, 0, 68), 7)
	ramp(Vector3.new(10, 0, 68), Vector3.new(35, TIER_MID, 20), 10)
	flatRoad(Vector3.new(35, TIER_MID, 20), Vector3.new(20, TIER_MID, 8), 8)
	-- Plaza west ramp to the plateau, then into the open west side.
	ramp(Vector3.new(-58, 0, 40), Vector3.new(-42, TIER_MID, -6), 8)
	flatRoad(Vector3.new(-42, TIER_MID, -6), Vector3.new(-40, TIER_MID, -45), 5)
	flatRoad(Vector3.new(-40, TIER_MID, -45), Vector3.new(-26, TIER_MID, -60), 5)
	-- Plaza to the cove and the portal bridge head.
	flatRoad(Vector3.new(-80, 0, 110), Vector3.new(-58, 0, 225), 6)
	-- Plaza to the lagoon overlook.
	flatRoad(Vector3.new(-70, 0, 100), Vector3.new(-24, 0, 78), 5)
	-- Lagoon east around to the hatchery.
	flatRoad(Vector3.new(82, 0, 78), Vector3.new(138, 0, 108), 6)
	-- West lawn to the carnival bridge head.
	flatRoad(Vector3.new(-120, 0, 82), Vector3.new(-225, 0, 58), 5)
	-- Plateau east edge to the balloon bridge head.
	flatRoad(Vector3.new(140, TIER_MID, -70), Vector3.new(152, TIER_MID, -102), 5)
	-- High tier: pond side path to the stair foot.
	flatRoad(Vector3.new(-118, TIER_HIGH, -112), Vector3.new(-132, TIER_HIGH, -128), 4)
	-- Plateau to the hill top: one long ramp up the saddle.
	ramp(Vector3.new(-38, TIER_MID, -50), Vector3.new(-95, TIER_HIGH, -105), 8)
end

--[[
	Seats the bought TDS town ON the plateau at native scale, fully
	walkable. Measured live: the model is 172 x 163 with mostly open
	edges (it is a building cluster, not a walled town), so the roads
	run straight into its open south and west sides. The model sinks
	1.5 studs so every foundation beds into the grass, and a dense
	skirt of bushes, grass walls, and corner trees ties the outside
	edge into the island. The east cliff edge gets a fenced overlook.
]]
local function seatTown(parent: Instance)
	local template: Instance? = nil
	if packModelsFolder ~= nil then
		local pack = packModelsFolder:FindFirstChild("Tds_Town_Pack")
		template = if pack ~= nil then pack:FindFirstChild("Scenery") else nil
	end

	local halfX, halfZ = 86, 81.5

	if template ~= nil and template:IsA("Model") then
		local town = template:Clone()
		for _, descendant in ipairs(town:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end

		local boxCFrame, boxSize = town:GetBoundingBox()
		halfX, halfZ = boxSize.X / 2, boxSize.Z / 2
		local target = TOWN_CENTER + Vector3.new(0, boxSize.Y / 2 - 1.5, 0)
		town:PivotTo(town:GetPivot() + (target - boxCFrame.Position))
		town.Name = "TdsTown"
		town.Parent = parent
	else
		for _, marker in ipairs({
			{ offset = Vector3.new(0, 0, 0), size = Vector3.new(30, 18, 30) },
			{ offset = Vector3.new(-50, 0, -40), size = Vector3.new(24, 14, 24) },
			{ offset = Vector3.new(45, 0, 40), size = Vector3.new(24, 12, 24) },
		}) do
			createPart({
				Name = "FallbackTownBlock",
				Size = marker.size,
				Position = TOWN_CENTER + marker.offset + Vector3.new(0, marker.size.Y / 2, 0),
				Color = Color3.fromRGB(124, 92, 70),
				Material = Enum.Material.Wood,
				Parent = parent,
			})
		end
		warn("HubService: TDS town pack missing; placeholder blocks mark its footprint")
	end

	-- Dense skirt: bushes and grass walls every ~14 studs around the
	-- whole perimeter, skipping the two road mouths.
	local SKIRT = { "Bush", "Tall Bush", "Bush 2", "Tall Bush Flower", "Double Tall Bush" }
	local skirtIndex = 0
	local perimeter = {}
	for along = -halfX + 8, halfX - 8, 14 do
		table.insert(perimeter, Vector3.new(along, 0, halfZ + 5))
		table.insert(perimeter, Vector3.new(along, 0, -halfZ - 5))
	end
	for along = -halfZ + 8, halfZ - 8, 14 do
		table.insert(perimeter, Vector3.new(halfX + 5, 0, along))
		table.insert(perimeter, Vector3.new(-halfX - 5, 0, along))
	end
	for _, offset in ipairs(perimeter) do
		local worldSpot = TOWN_CENTER + offset
		-- Skip the south road mouth (near x -35 on the south edge) and
		-- the west road mouth (near z 10 on the west edge).
		local isSouthMouth = offset.Z > 0 and math.abs(offset.X - -35) < 16
		local isWestMouth = offset.X < 0 and math.abs(offset.Z - 10) < 16
		if not isSouthMouth and not isWestMouth then
			skirtIndex += 1
			if skirtIndex % 5 == 0 then
				placeProp(
					parent,
					bundlePath("Grass", 1 + skirtIndex % 3),
					worldSpot,
					4,
					skirtIndex * 47
				)
			else
				placeProp(
					parent,
					naturePath(SKIRT[skirtIndex % #SKIRT + 1]),
					worldSpot + Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2)),
					3 + (skirtIndex % 3),
					skirtIndex * 61
				)
			end
		end
	end

	-- Corner trees taller than the rooftops tuck the corners in.
	for cornerIndex, corner in ipairs({
		Vector3.new(-halfX - 8, 0, -halfZ - 8),
		Vector3.new(halfX + 8, 0, -halfZ - 8),
		Vector3.new(-halfX - 8, 0, halfZ + 8),
		Vector3.new(halfX + 8, 0, halfZ + 8),
	}) do
		placeProp(
			parent,
			naturePath(if cornerIndex % 2 == 0 then "Tall Tree" else "Bigger Tree"),
			TOWN_CENTER + corner,
			15 + cornerIndex,
			cornerIndex * 90,
			fallbackTree
		)
	end

	-- Lamps and string lights at the south road mouth, lamps at the
	-- west mouth.
	local southMouth = TOWN_CENTER + Vector3.new(-35, 0, halfZ)
	local westMouth = TOWN_CENTER + Vector3.new(-halfX, 0, 10)
	for _, lampSpec in ipairs({
		{ position = southMouth + Vector3.new(-9, 0, 6), yaw = 0 },
		{ position = southMouth + Vector3.new(9, 0, 6), yaw = 180 },
		{ position = westMouth + Vector3.new(-6, 0, -9), yaw = 90 },
		{ position = westMouth + Vector3.new(-6, 0, 9), yaw = 270 },
	}) do
		local lamp = placeProp(
			parent,
			cityPath("City Lamps", "Street Lamp 2"),
			lampSpec.position,
			9,
			lampSpec.yaw,
			fallbackLamp
		)
		if lamp ~= nil then
			addTopLight(lamp)
		end
	end

	local lightSpan = 18
	for _, postSide in ipairs({ -1, 1 }) do
		createPart({
			Name = "StringLightPost",
			Size = Vector3.new(0.7, 9, 0.7),
			Position = southMouth + Vector3.new(postSide * lightSpan / 2, 4.5, 10),
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
			Position = southMouth
				+ Vector3.new(-lightSpan / 2 + progress * lightSpan, 8.6 - sag, 10),
			Color = if beadIndex % 2 == 0 then GOLD_COLOR else Color3.fromRGB(255, 168, 120),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = parent,
		})
	end

	-- The plateau's east cliff edge: a fenced overlook with a bench.
	local overlook = CENTER + Vector3.new(150, TIER_MID, -70)
	for fenceIndex = 0, 2 do
		placeProp(
			parent,
			naturePath("Inf. Fence 1"),
			overlook + Vector3.new(4, 0, -10 + fenceIndex * 10),
			3,
			90
		)
	end
	placeProp(
		parent,
		cityPath("Benches & Picnic", "Wooden Bench 1"),
		overlook + Vector3.new(-4, 0, 0),
		3,
		90,
		fallbackBench
	)
	local overlookSign = createPart({
		Name = "OverlookSign",
		Size = Vector3.new(0.8, 4.4, 0.8),
		Position = overlook + Vector3.new(-2, 2.2, 14),
		Color = WOOD_COLOR,
		Material = Enum.Material.Wood,
		CanCollide = false,
		Parent = parent,
	})
	addBillboard(overlookSign, "CLIFF OVERLOOK -- MIND THE EDGE!", SIGN_TEXT_COLOR, 3)
end

--[[
	The market row flanking the road between the plaza and the town
	ramp: the island shop and the group chest as roadside stalls, clear
	of the lagoon basin.
]]
local function buildMarketRow(parent: Instance)
	local shopBase = CENTER + Vector3.new(-30, 0, 88)

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

	-- The group chest, giant edition: 3.5x per side with a glowing
	-- seam. The parts live in one model with the lid closed flat, so
	-- the client can swing the lid open and burst coins on a claim.
	local chestBase = CENTER + Vector3.new(-46, 0, 70)

	local chestModel = Instance.new("Model")
	chestModel.Name = "GroupChestModel"
	chestModel.Parent = parent

	local body = createPart({
		Name = "GroupChest",
		Size = Vector3.new(17.5, 10.5, 11.9),
		Position = chestBase + Vector3.new(0, 5.25, 0),
		Color = Color3.fromRGB(110, 80, 48),
		Material = Enum.Material.Wood,
		Parent = chestModel,
	})

	createPart({
		Name = "ChestLid",
		Size = Vector3.new(18.2, 4.2, 12.6),
		Position = chestBase + Vector3.new(0, 12.6, 0),
		Color = Color3.fromRGB(96, 68, 38),
		Material = Enum.Material.Wood,
		Parent = chestModel,
	})

	for _, bandX in ipairs({ -5.6, 5.6 }) do
		createPart({
			Name = "ChestBand",
			Size = Vector3.new(1.6, 10.9, 12.3),
			Position = chestBase + Vector3.new(bandX, 5.25, 0),
			Color = GOLD_COLOR,
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = chestModel,
		})
	end

	-- The glow seam between body and lid: treasure light leaking out.
	local seam = createPart({
		Name = "ChestSeam",
		Size = Vector3.new(17, 0.35, 12),
		Position = chestBase + Vector3.new(0, 10.5, 0),
		Color = Color3.fromRGB(255, 233, 168),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = chestModel,
	})

	local seamLight = Instance.new("PointLight")
	seamLight.Color = GOLD_COLOR
	seamLight.Brightness = 2
	seamLight.Range = 20
	seamLight.Parent = seam

	local chestLock = createPart({
		Name = "ChestLock",
		Size = Vector3.new(3, 3.6, 0.9),
		Position = chestBase + Vector3.new(0, 9.2, 6.2),
		Color = GOLD_COLOR,
		Material = Enum.Material.Metal,
		CanCollide = false,
		Parent = chestModel,
	})
	addOutline(chestLock, GOLD_COLOR)

	addPrompt(body, "Claim Group Reward", "Group Chest")
	addBillboard(body, "GROUP REWARD -- JOIN & LIKE!", GOLD_COLOR, 12)
	addOutline(body, GOLD_COLOR)
	CollectionService:AddTag(body, "GroupChest")

	placeProp(parent, naturePath("Potted Plant"), shopBase + Vector3.new(-8, 0, 2), 2.5, 0)
	placeProp(
		parent,
		cityPath("Restaurant Related", "Outside Parasol Table"),
		chestBase + Vector3.new(-10, 0, -6),
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

	-- The working row: one glass capsule per world holding that world's
	-- REAL egg, lined up south of the display dome. With the old world
	-- strip emptied, this is where eggs hatch now; the stands carry the
	-- same EggStand tag and WorldIndex attribute the egg window has
	-- always watched.
	local function findEggTemplate(eggModelName: string): Instance?
		for _, folderName in ipairs({ "Models", "Decoration" }) do
			local found = findProp({ "Classic_Studs_Eggs_Pack", folderName, eggModelName })
			if found ~= nil then
				return found
			end
		end

		return nil
	end

	for worldIndex, world in ipairs(GameConfig.worlds) do
		local standBase = base + Vector3.new((worldIndex - 2.5) * 15, 0, 27)

		local standPedestal = createPart({
			Name = "EggStand",
			Size = Vector3.new(7, 2, 7),
			Position = standBase + Vector3.new(0, 1, 0),
			Color = WHITE_COLOR,
			Material = Enum.Material.Marble,
			Parent = parent,
		})
		standPedestal:SetAttribute("WorldIndex", worldIndex)

		createPart({
			Name = "HatcheryCapsule",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(11, 8, 8),
			CFrame = CFrame.new(standBase + Vector3.new(0, 7.5, 0))
				* CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(223, 249, 251),
			Material = Enum.Material.Glass,
			Transparency = 0.65,
			CanCollide = false,
			Parent = parent,
		})

		local eggTemplate = findEggTemplate(world.eggModelName)
		if eggTemplate ~= nil then
			local container = Instance.new("Model")
			container.Name = world.eggName
			local clone = eggTemplate:Clone()
			clone.Parent = container
			makeInert(container)

			local extents = container:GetExtentsSize()
			if extents.Y >= 0.05 then
				container:ScaleTo(4.6 / extents.Y)

				-- Floats above the pedestal, centered in the glass.
				local boxCFrame, boxSize = container:GetBoundingBox()
				local target = standBase + Vector3.new(0, 3.4 + boxSize.Y / 2, 0)
				container:PivotTo(container:GetPivot() + (target - boxCFrame.Position))
				container.Parent = parent
			else
				container:Destroy()
			end
		else
			-- Fallback shell so the capsule never stands empty.
			createPart({
				Name = "HatcheryEggShell",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(4, 4.8, 4),
				Position = standBase + Vector3.new(0, 6.5, 0),
				Color = GOLD_COLOR,
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				Parent = parent,
			})
		end

		local hatchPrompt = Instance.new("ProximityPrompt")
		hatchPrompt.ActionText = "Hatch (Press E)"
		hatchPrompt.ObjectText = world.eggName
		hatchPrompt.HoldDuration = 0
		hatchPrompt.MaxActivationDistance = 16
		hatchPrompt.RequiresLineOfSight = false
		hatchPrompt.Parent = standPedestal

		addBillboard(
			standPedestal,
			string.format("%s -- %d COINS", string.upper(world.eggName), world.eggCost),
			GOLD_COLOR,
			11
		)
		CollectionService:AddTag(standPedestal, "EggStand")
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
	addBillboard(sign, "THE HATCHERY -- HATCH HERE, LEGENDS ON DISPLAY!", GOLD_COLOR, 4)
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
	The crystal grotto under the cove: entered by the open-cut trench
	from the sand, now with cobble stairs, rail fences around the top
	rim, and an entrance sign, so the hole is an invitation instead of
	a trap. Inside: crystals, a cave formation, treasure, purple
	motes. A jellyfish drifts just past the rim outside.
]]
local function buildGrotto(parent: Instance)
	-- The entry: three cobble ramps down the carved trench.
	for stepIndex, stepSpec in ipairs({
		{ from = Vector3.new(-60, 0.4, 188), to = Vector3.new(-60, -4.5, 176) },
		{ from = Vector3.new(-60, -4.5, 176), to = Vector3.new(-60, -9.5, 164) },
		{ from = Vector3.new(-60, -9.5, 164), to = Vector3.new(-60, -14.5, 154) },
	}) do
		local fromPosition = CENTER + stepSpec.from
		local toPosition = CENTER + stepSpec.to
		local span = toPosition - fromPosition
		local midpoint = fromPosition + span / 2
		createPart({
			Name = "GrottoStair" .. stepIndex,
			Size = Vector3.new(9, 1, span.Magnitude + 2),
			CFrame = CFrame.lookAt(midpoint, toPosition),
			Color = Color3.fromRGB(178, 168, 152),
			Material = Enum.Material.Cobblestone,
			Parent = parent,
		})
	end

	-- Rails around the top of the trench so nobody walks in blind.
	for _, railSpec in ipairs({
		{ offset = Vector3.new(-67, 0, 182), yaw = 0 },
		{ offset = Vector3.new(-53, 0, 182), yaw = 0 },
		{ offset = Vector3.new(-60, 0, 190), yaw = 90 },
	}) do
		placeProp(parent, naturePath("Fence 1"), CENTER + railSpec.offset, 2.6, railSpec.yaw)
	end
	local grottoSign = createPart({
		Name = "GrottoSign",
		Size = Vector3.new(0.8, 4.2, 0.8),
		Position = CENTER + Vector3.new(-70, 2.1, 190),
		Color = WOOD_COLOR,
		Material = Enum.Material.Wood,
		CanCollide = false,
		Parent = parent,
	})
	addBillboard(grottoSign, "THE CRYSTAL GROTTO -- STAIRS DOWN!", CRYSTAL_COLOR, 3)

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
		CENTER + Vector3.new(152, TIER_MID, -105),
		BALLOON_ISLE + Vector3.new(-30, 0, 10)
	)
end

--[[
	The forest, three times denser: pine rings crown the hill,
	broadleaf surrounds the town and fills the lawns, groves cluster
	on the knolls, understory clumps and grass tufts thicken every
	floor. Deterministic jitter keeps it organic and identical on
	every server.
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

	-- Pine crown: two rings on the main hill lobe plus one on the
	-- back lobe, clear of the tree, pond, stair, and falls line.
	local pineIndex = 0
	for _, arc in ipairs({
		{
			center = Vector3.new(-145, TIER_HIGH, -130),
			radius = 52,
			fromAngle = 110,
			toAngle = 330,
			count = 9,
		},
		{
			center = Vector3.new(-145, TIER_HIGH, -130),
			radius = 40,
			fromAngle = 130,
			toAngle = 300,
			count = 6,
		},
		{
			center = Vector3.new(-100, TIER_HIGH, -195),
			radius = 30,
			fromAngle = 100,
			toAngle = 320,
			count = 7,
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
					+ jitter(4),
				14 + (pineIndex % 5),
				pineIndex * 53,
				fallbackTree
			)
		end
	end

	-- Broadleaf lawns: scatter across the low tier, groves on the
	-- knolls, and the rim ring at explicit per-tier heights.
	local leafIndex = 0
	for _, spot in ipairs({
		Vector3.new(-150, 4, 40),
		Vector3.new(-170, 3, 120),
		Vector3.new(-130, 0, 190),
		Vector3.new(135, 0, 70),
		Vector3.new(185, 0, 60),
		Vector3.new(200, 0, 150),
		Vector3.new(120, 0, 200),
		Vector3.new(-20, 0, 120),
		Vector3.new(95, 0, 55),
		Vector3.new(-125, 0, 65),
		Vector3.new(-95, 0, 20),
		Vector3.new(-140, 2, -20),
		Vector3.new(175, 0, 20),
		Vector3.new(160, 0, 175),
		Vector3.new(60, 0, 165),
		Vector3.new(-180, 0, 90),
	}) do
		leafIndex += 1
		placeProp(
			parent,
			naturePath(BROADLEAF[leafIndex % #BROADLEAF + 1]),
			CENTER + spot + jitter(6),
			12 + (leafIndex % 5),
			leafIndex * 31,
			fallbackTree
		)
	end

	-- Knoll groves: three trees hugging each of the bigger knolls.
	for _, knollCenter in ipairs({
		Vector3.new(-150, 5, 60),
		Vector3.new(-170, 4, 150),
		Vector3.new(110, 4, 180),
	}) do
		for groveStep = 0, 2 do
			local angle = groveStep / 3 * math.pi * 2 + 0.6
			leafIndex += 1
			placeProp(
				parent,
				naturePath(BROADLEAF[leafIndex % #BROADLEAF + 1]),
				CENTER
					+ knollCenter
					+ Vector3.new(math.cos(angle) * 14, -2, math.sin(angle) * 14)
					+ jitter(4),
				13 + (leafIndex % 4),
				leafIndex * 77,
				fallbackTree
			)
		end
	end

	-- Rim ring: explicit spots, each at its tier's height.
	for rimStep, rimSpot in ipairs({
		Vector3.new(210, 0, 85),
		Vector3.new(144, 0, 200),
		Vector3.new(22, 0, 252),
		Vector3.new(-107, 0, 226),
		Vector3.new(-196, 0, 127),
		Vector3.new(-225, 0, 20),
		Vector3.new(-160, TIER_HIGH, -120),
		Vector3.new(-22, 0, -184),
		Vector3.new(150, 0, -185),
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
			CENTER + rimSpot + jitter(5),
			13 + (rimStep % 4),
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
	placeProp(
		parent,
		naturePath("Rooted Tree"),
		CENTER + Vector3.new(150, 0, -160),
		13,
		40,
		fallbackTree
	)

	-- Understory clumps: three props around each anchor.
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
	local understoryAnchors = {
		Vector3.new(-120, 0, 150),
		Vector3.new(-150, 0, 90),
		Vector3.new(-100, 0, 45),
		Vector3.new(-30, 0, 130),
		Vector3.new(100, 0, 90),
		Vector3.new(140, 0, 60),
		Vector3.new(175, 0, 110),
		Vector3.new(110, 0, 165),
		Vector3.new(-165, TIER_HIGH, -90),
		Vector3.new(-175, TIER_HIGH, -140),
		Vector3.new(-120, TIER_HIGH, -180),
		Vector3.new(-95, TIER_HIGH, -145),
		Vector3.new(-95, 0, 230),
		Vector3.new(80, 0, 230),
		Vector3.new(-200, 0, 60),
		Vector3.new(185, 0, 90),
	}
	for anchorIndex, anchor in ipairs(understoryAnchors) do
		for clumpStep = 0, 2 do
			local pick = UNDERSTORY[(anchorIndex * 7 + clumpStep * 3) % #UNDERSTORY + 1]
			placeProp(
				parent,
				naturePath(pick.prop),
				CENTER + anchor + jitter(8),
				pick.height,
				anchorIndex * 83 + clumpStep * 40
			)
		end
	end

	-- Grass tufts across every lawn, snapped to the tier under them.
	local function tierHeight(offset: Vector3): number
		if offset.X > -54 and offset.X < 164 and offset.Z > -174 and offset.Z < 34 then
			return TIER_MID
		end
		local flatOffset = Vector3.new(offset.X, 0, offset.Z)
		if
			(flatOffset - Vector3.new(-145, 0, -130)).Magnitude < 68
			or (flatOffset - Vector3.new(-100, 0, -195)).Magnitude < 44
		then
			return TIER_HIGH
		end
		return 0
	end

	for tuftIndex = 0, 23 do
		local angle = tuftIndex / 24 * math.pi * 2
		local radius = 90 + (tuftIndex % 5) * 26
		local offset = Vector3.new(math.cos(angle) * radius, 0, 40 + math.sin(angle) * radius)
			+ jitter(10)
		placeProp(
			parent,
			naturePath(if tuftIndex % 2 == 0 then "Tall Grass" else "Grass"),
			CENTER + offset + Vector3.new(0, tierHeight(offset), 0),
			1.6,
			tuftIndex * 29
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
					60 + math.sin(elapsed * 0.35) * 6,
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

--[[
	The safety net: a vast invisible catcher far under the island.
	Sky-well rides, bridge slips, and rim tumbles all land here and
	step back onto the pad instead of falling forever.
]]
local function buildSafetyNet(parent: Instance)
	local net = createPart({
		Name = "SafetyNet",
		Size = Vector3.new(1500, 4, 1500),
		Position = CENTER + Vector3.new(0, -170, 0),
		Transparency = 1,
		CanCollide = false,
		Parent = parent,
	})

	local lastCatch: { [Player]: number } = {}
	net.Touched:Connect(function(hit)
		local character = hit.Parent
		if character == nil then
			return
		end
		local player = game:GetService("Players"):GetPlayerFromCharacter(character)
		if player == nil then
			return
		end
		local now = os.clock()
		if lastCatch[player] ~= nil and now - lastCatch[player] < 3 then
			return
		end
		lastCatch[player] = now
		character:PivotTo(CFrame.new(PAD_POSITION + Vector3.new(0, PAD_SURFACE_HEIGHT + 4, 0)))
	end)
end

-- Pivot a player's character onto the pad; the client cutscene lifts
-- them into the sky itself, so no one can fall out of the world here.
local function placeAtPad(player: Player): boolean
	local character = player.Character
	if character == nil then
		return false
	end

	character:PivotTo(CFrame.new(PAD_POSITION + Vector3.new(0, PAD_SURFACE_HEIGHT + 4, 0)))

	return true
end

function HubService.landingPosition(): Vector3
	return PAD_POSITION + Vector3.new(0, PAD_SURFACE_HEIGHT + 4, 0)
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
	buildSafetyNet(hubFolder)
	skyWhale = placeProp(hubFolder, seaPath("Whale"), CENTER + Vector3.new(380, 60, 0), 24, 90)
	startAmbientLoop()

	-- The previous separate TDS island, preserved behind its flag.
	if GameConfig.tdsIsland.enabled and modelsFolder ~= nil then
		buildTdsIsland(modelsFolder)
	end

	hubFolder.Parent = Workspace
end

return HubService
