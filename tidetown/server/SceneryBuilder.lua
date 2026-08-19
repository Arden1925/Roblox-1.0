--[[
	Dresses the finished Tidetown map (built by MapBuilder) with small,
	hand-placed scenery: tidepool-flat life, dune grass and lanterns
	along the boardwalk, pier clutter, far-west silhouettes, warm glow
	markers at the cave mouth, and lamp posts on the town approach.
	Every color is a Palette A anchor from docs/DESIGN_LANGUAGE.md.

	Placement is authored coordinate tables -- no randomness -- so every
	server composes the identical scene and screenshots stay comparable.
	Coordinates deliberately avoid the gameplay corridors: the surge
	lanes in front of each reef plot, the rescue mound, the spawn pad,
	the pier's center walkway, and the stair landings.

	Pack props go through placeProp with a part-built fallback each,
	following the HubService discipline: a missing pack never leaves a
	hole, and upgrading any prop later means editing one path string.

	Phone-first budget: every part is anchored and inert (no collision,
	query, touch, or shadow -- except the standable sea stacks), no
	emitters, and exactly six PointLights across the whole pass.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local TidetownShared = ReplicatedStorage.TidetownShared
local TideLayout = require(TidetownShared.TideLayout)
local TidetownConfig = require(TidetownShared.TidetownConfig)

local MAP_FOLDER_NAME = "Tidetown"
local SCENERY_FOLDER_NAME = "Scenery"

-- Palette A anchors (docs/DESIGN_LANGUAGE.md section 2).
local STARFISH_CORAL = Color3.fromRGB(239, 108, 77)
local AMBER_GLOW = Color3.fromRGB(255, 209, 102)
local BUOY_CORAL = Color3.fromRGB(255, 110, 92)
local BIO_VEIN_TEAL = Color3.fromRGB(72, 219, 209)
local SEA_STACK_NAVY = Color3.fromRGB(22, 36, 62)
local SHEEN_WHITE = Color3.fromRGB(239, 247, 249)
local WET_SAND_COLOR = Color3.fromRGB(216, 195, 145)
local DUNE_GRASS_GREEN = Color3.fromRGB(120, 176, 92)
local ROPE_BROWN = Color3.fromRGB(150, 115, 82)
local WOOD_COLOR = Color3.fromRGB(133, 100, 70)
local SHELL_CREAM = Color3.fromRGB(240, 231, 214)

local WARM_LIGHT_BRIGHTNESS = 0.8

local SceneryBuilder = {}

-- Resolved once in build(); every pack prop below prefers a real model
-- from here and falls back to simple part-work when it is missing.
local packModelsFolder: Instance? = nil

type PropPath = { string }
type PropFallback = (Instance, Vector3, number) -> ()

local function createPart(properties: { [string]: any }): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
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

-- Zone bounds come from the shared layout so scenery can never drift
-- from the geometry MapBuilder built from the same source of truth.
local function zoneBounds(zoneKey: string): { minX: number, maxX: number, floorY: number }
	local info = TideLayout.zoneInfo(zoneKey)
	assert(info ~= nil, string.format("Unknown zone %q", zoneKey))

	return info
end

local function beachPath(propName: string): PropPath
	return { "Beach_Summer_Asset_Pack_2025", "Models", propName }
end

local function naturePath(propName: string): PropPath
	return { "Low_Poly_Nature_Asset_Pack", "Low Poly Nature Asset Pack | Destiny Tech", propName }
end

local function findProp(path: PropPath): Instance?
	local current = packModelsFolder

	for _, segment in ipairs(path) do
		if current == nil then
			return nil
		end

		current = current:FindFirstChild(segment)
	end

	return current
end

-- Decorative clones never trap the player or cost a shadow pass.
local function makeInert(container: Model)
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
		end
	end
end

--[[
	The one prop entry point, following HubService.placeProp: clones the
	pack model at the path, scales it so its LARGEST extent matches
	targetStuds (flat props like towels keep sane footprints that pure
	height scaling would explode), and stands it bottom-down at the
	position. A missing model runs the part-built fallback at the same
	spot instead, so the scene composes identically without the packs.
]]
local function placeProp(
	parent: Instance,
	path: PropPath,
	position: Vector3,
	targetStuds: number,
	yaw: number?,
	fallback: PropFallback?
): Model?
	local template = findProp(path)
	if template == nil then
		if fallback ~= nil then
			fallback(parent, position, targetStuds)
		elseif packModelsFolder ~= nil then
			warn("SceneryBuilder: missing prop " .. table.concat(path, "/"))
		end

		return nil
	end

	local container = Instance.new("Model")
	container.Name = template.Name

	local clone = template:Clone()
	clone.Parent = container
	makeInert(container)

	local extents = container:GetExtentsSize()
	local largestExtent = math.max(extents.X, extents.Y, extents.Z)
	if largestExtent < 0.05 then
		container:Destroy()
		return nil
	end

	container:PivotTo(container:GetPivot() * CFrame.Angles(0, math.rad(yaw or 0), 0))
	container:ScaleTo(targetStuds / largestExtent)

	local boxCFrame, boxSize = container:GetBoundingBox()
	local target = position + Vector3.new(0, boxSize.Y / 2, 0)
	container:PivotTo(container:GetPivot() + (target - boxCFrame.Position))
	container.Parent = parent

	return container
end

-- Tips a placed prop toward world +Z over its own pivot -- for
-- surfboards resting against the pier's south rail instead of
-- standing bolt upright. The tilt axis is a world axis on purpose:
-- a local-axis pitch after the yaw placeProp applied would tip the
-- boards ALONG the rail instead of against it.
local function leanModel(container: Model?, pitchDegrees: number)
	if container == nil then
		return
	end

	local pivot = container:GetPivot()
	container:PivotTo(
		CFrame.new(pivot.Position) * CFrame.Angles(math.rad(pitchDegrees), 0, 0) * pivot.Rotation
	)
end

local function addWarmLight(part: BasePart, range: number)
	local light = Instance.new("PointLight")
	light.Color = AMBER_GLOW
	light.Brightness = WARM_LIGHT_BRIGHTNESS
	light.Range = range
	light.Parent = part
end

-- Fallbacks: deliberately simple, clearly placeholder shapes that keep
-- the composition intact until the matching pack model syncs in.
local function fallbackShell(parent: Instance, position: Vector3, targetStuds: number)
	createPart({
		Name = "FallbackShell",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(targetStuds, targetStuds, targetStuds),
		-- Sunk past center so only a shell-back cap shows above sand.
		Position = position + Vector3.new(0, targetStuds * 0.3, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = SHELL_CREAM,
		Parent = parent,
	})
end

local function fallbackDriftwood(parent: Instance, position: Vector3, targetStuds: number)
	-- A cylinder already lies along its local X axis, so no roll needed
	-- for a log resting on the sand.
	createPart({
		Name = "FallbackDriftwood",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(targetStuds, 1.1, 1.1),
		Position = position + Vector3.new(0, 0.45, 0),
		Material = Enum.Material.Wood,
		Color = WOOD_COLOR,
		Parent = parent,
	})
end

local function fallbackBucket(parent: Instance, position: Vector3, targetStuds: number)
	createPart({
		Name = "FallbackBucket",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(targetStuds, targetStuds * 0.8, targetStuds * 0.8),
		CFrame = CFrame.new(position + Vector3.new(0, targetStuds / 2, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.SmoothPlastic,
		Color = STARFISH_CORAL,
		Parent = parent,
	})
end

local function fallbackDuneGrass(parent: Instance, position: Vector3, targetStuds: number)
	for _, yaw in ipairs({ 40, 130 }) do
		createPart({
			Name = "FallbackDuneGrass",
			Size = Vector3.new(0.15, targetStuds, 0.9),
			CFrame = CFrame.new(position + Vector3.new(0, targetStuds / 2, 0))
				* CFrame.Angles(0, math.rad(yaw), 0),
			Material = Enum.Material.Grass,
			Color = DUNE_GRASS_GREEN,
			Parent = parent,
		})
	end
end

local function fallbackUmbrella(parent: Instance, position: Vector3, targetStuds: number)
	createPart({
		Name = "FallbackUmbrellaPole",
		Size = Vector3.new(0.3, targetStuds * 0.9, 0.3),
		Position = position + Vector3.new(0, targetStuds * 0.45, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = SHEEN_WHITE,
		Parent = parent,
	})
	createPart({
		Name = "FallbackUmbrellaCanopy",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, targetStuds * 0.85, targetStuds * 0.85),
		CFrame = CFrame.new(position + Vector3.new(0, targetStuds * 0.9, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.SmoothPlastic,
		Color = STARFISH_CORAL,
		Parent = parent,
	})
end

local function fallbackTowel(parent: Instance, position: Vector3, targetStuds: number)
	createPart({
		Name = "FallbackTowel",
		Size = Vector3.new(targetStuds, 0.12, targetStuds * 0.55),
		Position = position + Vector3.new(0, 0.06, 0),
		Material = Enum.Material.Fabric,
		Color = AMBER_GLOW,
		Parent = parent,
	})
end

local function fallbackSurfboard(parent: Instance, position: Vector3, targetStuds: number)
	createPart({
		Name = "FallbackSurfboard",
		Size = Vector3.new(1.7, targetStuds, 0.3),
		CFrame = CFrame.new(position + Vector3.new(0, targetStuds / 2, 0))
			* CFrame.Angles(math.rad(15), 0, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = STARFISH_CORAL,
		Parent = parent,
	})
end

local function fallbackBuoyRing(parent: Instance, position: Vector3, targetStuds: number)
	-- Rolled to face along Z so the ring hangs flat against the rail.
	createPart({
		Name = "FallbackBuoyRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, targetStuds, targetStuds),
		CFrame = CFrame.new(position + Vector3.new(0, targetStuds / 2, 0))
			* CFrame.Angles(0, math.rad(90), 0),
		Material = Enum.Material.SmoothPlastic,
		Color = BUOY_CORAL,
		Parent = parent,
	})
end

-- Five thin arms and a flat center disc, always part-built: the shape
-- reads at a glance and costs six tiny parts, no mesh streaming.
local function buildStarfish(parent: Instance, position: Vector3, yaw: number, color: Color3)
	local center = position + Vector3.new(0, 0.15, 0)

	createPart({
		Name = "StarfishCenter",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.25, 1.3, 1.3),
		CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.SmoothPlastic,
		Color = color,
		Parent = parent,
	})

	for armIndex = 0, 4 do
		createPart({
			Name = "StarfishArm",
			Size = Vector3.new(1.9, 0.22, 0.55),
			CFrame = CFrame.new(center)
				* CFrame.Angles(0, math.rad(yaw + armIndex * 72), 0)
				* CFrame.new(1.05, 0, 0),
			Material = Enum.Material.SmoothPlastic,
			Color = color,
			Parent = parent,
		})
	end
end

--[[
	Life on the tidepool flats (X -240..-30). Everything here sits under
	the high-tide waterline on purpose -- and none of it glows, so
	nothing shines oddly through the flood.
]]
local function buildFlats(parent: Instance)
	local floorY = zoneBounds("Beach").floorY

	-- Mostly sun-warm coral with a few gold outliers, per the LOW phase
	-- accent split.
	local starfishSpots = {
		{ x = -220, z = -150, yaw = 20 },
		{ x = -205, z = 95, yaw = 130, gold = true },
		{ x = -190, z = -40, yaw = 70 },
		{ x = -175, z = 160, yaw = 200 },
		{ x = -160, z = 10, yaw = 300, gold = true },
		{ x = -150, z = -120, yaw = 45 },
		{ x = -135, z = 70, yaw = 160 },
		{ x = -120, z = -170, yaw = 250 },
		{ x = -105, z = 140, yaw = 15, gold = true },
		{ x = -95, z = -60, yaw = 95 },
		{ x = -80, z = 35, yaw = 210 },
		{ x = -65, z = -140, yaw = 340 },
		{ x = -55, z = 110, yaw = 120, gold = true },
		{ x = -45, z = -15, yaw = 60 },
	}
	for _, spot in ipairs(starfishSpots) do
		local color = if spot.gold == true then AMBER_GLOW else STARFISH_CORAL
		buildStarfish(parent, Vector3.new(spot.x, floorY, spot.z), spot.yaw, color)
	end

	local shellSpots = {
		{ x = -225, z = 60, yaw = 30 },
		{ x = -210, z = -95, yaw = 110 },
		{ x = -185, z = 130, yaw = 210 },
		{ x = -170, z = -25, yaw = 80 },
		{ x = -140, z = 175, yaw = 300 },
		{ x = -125, z = -155, yaw = 150 },
		{ x = -100, z = 90, yaw = 40 },
		{ x = -85, z = -75, yaw = 260 },
		{ x = -60, z = 25, yaw = 190 },
		{ x = -40, z = -130, yaw = 330 },
	}
	for _, spot in ipairs(shellSpots) do
		placeProp(
			parent,
			beachPath("Shell"),
			Vector3.new(spot.x, floorY, spot.z),
			1,
			spot.yaw,
			fallbackShell
		)
	end

	local driftwoodSpots = {
		{ x = -215, z = 20, yaw = 25, prop = "Log 1" },
		{ x = -165, z = -95, yaw = 290, prop = "Log 2" },
		{ x = -112, z = 155, yaw = 70, prop = "Log 1" },
		{ x = -70, z = -45, yaw = 195, prop = "Log 2" },
	}
	for _, spot in ipairs(driftwoodSpots) do
		placeProp(
			parent,
			naturePath(spot.prop),
			Vector3.new(spot.x, floorY, spot.z),
			7,
			spot.yaw,
			fallbackDriftwood
		)
	end

	-- Spheres sunk past center read as low wet-sand mounds; diameter
	-- varies so the repetition never registers.
	local moundSpots = {
		{ x = -230, z = -70, diameter = 4.6 },
		{ x = -195, z = 40, diameter = 3.8 },
		{ x = -155, z = -180, diameter = 5.2 },
		{ x = -130, z = 120, diameter = 4.2 },
		{ x = -90, z = -110, diameter = 3.6 },
		{ x = -75, z = 170, diameter = 4.8 },
		{ x = -50, z = 60, diameter = 4 },
		{ x = -35, z = -20, diameter = 3.4 },
	}
	for _, spot in ipairs(moundSpots) do
		createPart({
			Name = "SandMound",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(spot.diameter, spot.diameter, spot.diameter),
			Position = Vector3.new(spot.x, floorY - spot.diameter * 0.2, spot.z),
			Material = Enum.Material.Sand,
			Color = WET_SAND_COLOR,
			Parent = parent,
		})
	end

	-- Abandoned buckets huddle at the dry sand line, where the water
	-- last chased their owners uphill.
	local bucketSpots = {
		{ x = -34, z = -58, yaw = 15 },
		{ x = -33, z = 84, yaw = 140 },
		{ x = -36, z = 148, yaw = 260 },
	}
	for _, spot in ipairs(bucketSpots) do
		placeProp(
			parent,
			beachPath("Shovel Bucket"),
			Vector3.new(spot.x, floorY, spot.z),
			1.4,
			spot.yaw,
			fallbackBucket
		)
	end

	-- Glossy sheen patches sell "just-drained" without any Glass cost;
	-- they float above the tide pool discs so nothing z-fights.
	local sheenSpots = {
		{ x = -200, z = -20, width = 12, depth = 8, yaw = 15 },
		{ x = -150, z = 100, width = 9, depth = 6, yaw = 70 },
		{ x = -120, z = -140, width = 11, depth = 7, yaw = 40 },
		{ x = -88, z = 55, width = 8, depth = 9, yaw = 110 },
		{ x = -55, z = -85, width = 10, depth = 6, yaw = 25 },
		{ x = -40, z = 135, width = 7, depth = 5, yaw = 85 },
	}
	for _, spot in ipairs(sheenSpots) do
		createPart({
			Name = "WetSheen",
			Size = Vector3.new(spot.width, 0.05, spot.depth),
			CFrame = CFrame.new(spot.x, floorY + 0.35, spot.z)
				* CFrame.Angles(0, math.rad(spot.yaw), 0),
			Material = Enum.Material.SmoothPlastic,
			Color = SHEEN_WHITE,
			Transparency = 0.55,
			Parent = parent,
		})
	end
end

--[[
	The dry sand strip and the boardwalk's seaward edge. Every X/Z here
	dodges the surge lanes (X -20..50 within 5 studs of each plot Z),
	the rescue mound at (0, 3.5, 20), the stair landings, and the spawn.
]]
local function buildDrySand(parent: Instance)
	local layout = TidetownConfig.layout
	local sandY = layout.beachSand.topY
	local deckY = layout.boardwalk.deckY
	local railX = layout.boardwalk.minX + 0.25

	-- West-edge tufts sit outside the surge corridor entirely; the
	-- boardwalk-side tufts thread between the plot Z bands.
	local grassSpots = {
		{ x = -26, z = -155, yaw = 10 },
		{ x = -24, z = -45, yaw = 95 },
		{ x = -27, z = 15, yaw = 220 },
		{ x = -25, z = 105, yaw = 160 },
		{ x = 34, z = -172, yaw = 45 },
		{ x = 36, z = -122, yaw = 300 },
		{ x = 33, z = -78, yaw = 130 },
		{ x = 35, z = 78, yaw = 200 },
		{ x = 37, z = 122, yaw = 70 },
		{ x = 34, z = 168, yaw = 340 },
	}
	for _, spot in ipairs(grassSpots) do
		placeProp(
			parent,
			naturePath("Tall Grass"),
			Vector3.new(spot.x, sandY, spot.z),
			2.4,
			spot.yaw,
			fallbackDuneGrass
		)
	end

	-- A small picnic vignette between the plot-20 stairs and the rescue
	-- mound, outside both keep-clear boxes.
	placeProp(parent, beachPath("Sunshade"), Vector3.new(16, sandY, 10), 8, 40, fallbackUmbrella)
	placeProp(parent, beachPath("Sunshade"), Vector3.new(12, sandY, 34), 8, 155, fallbackUmbrella)
	placeProp(parent, beachPath("Colored Towel"), Vector3.new(22, sandY, 4), 5, 15, fallbackTowel)
	placeProp(parent, beachPath("Colored Towel"), Vector3.new(8, sandY, 40), 5, 280, fallbackTowel)

	-- Rope coils on the deck edge, clear of every railing gap.
	for _, coilZ in ipairs({ -70, -50, 50, 70 }) do
		createPart({
			Name = "RopeCoil",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 1.8, 1.8),
			CFrame = CFrame.new(layout.boardwalk.minX + 2.5, deckY + 0.15, coilZ)
				* CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Fabric,
			Color = ROPE_BROWN,
			Parent = parent,
		})
	end

	-- Amber lanterns capping the seaward railing. Only three of the
	-- four carry a PointLight: the whole scenery pass is budgeted to
	-- six lights for phones, and the Neon cube still glows on its own.
	for index, lanternZ in ipairs({ -110, -70, 70, 110 }) do
		local lantern = createPart({
			Name = "RailLantern",
			Size = Vector3.new(0.7, 0.7, 0.7),
			Position = Vector3.new(railX, deckY + 3.35, lanternZ),
			Material = Enum.Material.Neon,
			Color = AMBER_GLOW,
			Parent = parent,
		})
		if index <= 3 then
			addWarmLight(lantern, 12)
		end
	end
end

--[[
	Clutter along the pier rails near the mount stand. Everything hugs
	the rails at |Z| > 3 so the center walkway stays walkable.
]]
local function buildPier(parent: Instance)
	local deckY = TidetownConfig.layout.boardwalk.deckY

	-- Two boards resting against the south rail, four studs apart and
	-- tipped toward it so they read as leaning, never standing.
	local firstBoard = placeProp(
		parent,
		beachPath("Surf Board"),
		Vector3.new(-66, deckY, 4.1),
		6.5,
		90,
		fallbackSurfboard
	)
	leanModel(firstBoard, 15)

	local secondBoard = placeProp(
		parent,
		beachPath("Surf Board 2"),
		Vector3.new(-62, deckY, 4.2),
		6.8,
		84,
		fallbackSurfboard
	)
	leanModel(secondBoard, 17)

	-- A stored buoy on the north rail top (the rail crests at deck+2.5).
	placeProp(
		parent,
		beachPath("Buoy"),
		Vector3.new(-50, deckY + 2.5, -4.75),
		2,
		0,
		fallbackBuoyRing
	)

	for _, barrel in ipairs({ { x = -42, z = 3.6 }, { x = -28, z = -3.6 } }) do
		createPart({
			Name = "PierBarrel",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.2, 2, 2),
			CFrame = CFrame.new(barrel.x, deckY + 1.1, barrel.z)
				* CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Wood,
			Color = WOOD_COLOR,
			Parent = parent,
		})
	end
end

--[[
	Far-west drama: ink-navy sea stacks on the horizon, coral marker
	buoys over the cave shallows, and bioluminescent veins on the
	drop-off that read through the water at high tide.
]]
local function buildHorizon(parent: Instance)
	local deepFloorY = zoneBounds("DeepReef").floorY
	local caveMinX = zoneBounds("Cave").minX

	-- Sea stacks are the one collidable scenery: big enough to stand
	-- on, so phasing through them would feel broken from a mount.
	local stackSpots = {
		{ x = -688, z = -125, height = 28, width = 9 },
		{ x = -681, z = -118, height = 14, width = 5 },
		{ x = -655, z = 35, height = 22, width = 7 },
		{ x = -635, z = 140, height = 30, width = 10 },
		{ x = -642, z = 147, height = 16, width = 6 },
	}
	for _, spot in ipairs(stackSpots) do
		createPart({
			Name = "SeaStack",
			Size = Vector3.new(spot.width, spot.height, spot.width),
			Position = Vector3.new(spot.x, deepFloorY + spot.height / 2, spot.z),
			Material = Enum.Material.Slate,
			Color = SEA_STACK_NAVY,
			CanCollide = true,
			Parent = parent,
		})
	end

	-- Static at Y 5: visible riding the flood at high tide, hovering
	-- as channel markers over the drained shallows at low.
	for _, buoy in ipairs({ { x = -305, z = -80 }, { x = -288, z = 95 } }) do
		createPart({
			Name = "MarkerBuoy",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.4, 2.4, 2.4),
			Position = Vector3.new(buoy.x, 5, buoy.z),
			Material = Enum.Material.SmoothPlastic,
			Color = BUOY_CORAL,
			Parent = parent,
		})
		createPart({
			Name = "MarkerBuoyPost",
			Size = Vector3.new(0.5, 1.8, 0.5),
			Position = Vector3.new(buoy.x, 6.9, buoy.z),
			Material = Enum.Material.SmoothPlastic,
			Color = SHEEN_WHITE,
			Parent = parent,
		})
	end

	-- Neon strips draped down the drop-off face where the cave shelf
	-- ends: Neon needs no PointLight to read through water.
	local veinSpots = {
		{ z = -150, tilt = 18, length = 8 },
		{ z = -60, tilt = -22, length = 9 },
		{ z = 40, tilt = 14, length = 7.5 },
		{ z = 120, tilt = -16, length = 8.5 },
	}
	for _, vein in ipairs(veinSpots) do
		createPart({
			Name = "BioVein",
			Size = Vector3.new(0.5, vein.length, 1.2),
			CFrame = CFrame.new(caveMinX - 0.2, -5, vein.z)
				* CFrame.Angles(0, 0, math.rad(vein.tilt)),
			Material = Enum.Material.Neon,
			Color = BIO_VEIN_TEAL,
			Parent = parent,
		})
	end
end

--[[
	Two amber torches flanking the stone arch nearest the shoreline
	center (the one at X -270, Z 40), so the dark band players see from
	the boardwalk has one warm point inviting them into the cave zone.
]]
local function buildCaveMouth(parent: Instance)
	local floorY = zoneBounds("Cave").floorY

	for _, torchX in ipairs({ -284, -256 }) do
		createPart({
			Name = "TorchPost",
			Size = Vector3.new(0.6, 4.8, 0.6),
			Position = Vector3.new(torchX, floorY + 2.4, 40),
			Material = Enum.Material.Wood,
			Color = WOOD_COLOR,
			Parent = parent,
		})

		-- The tip clears the high-tide waterline (Y 4.5) so the flame
		-- never glows from underwater during the flood.
		local tip = createPart({
			Name = "TorchTip",
			Size = Vector3.new(0.8, 0.8, 0.8),
			Position = Vector3.new(torchX, floorY + 5.2, 40),
			Material = Enum.Material.Neon,
			Color = AMBER_GLOW,
			Parent = parent,
		})
		addWarmLight(tip, 16)
	end
end

--[[
	Three lamp posts walking the eye from the boardwalk's town stairs
	toward the TDS streets. One shared PointLight (on the middle post)
	keeps the pass at exactly six lights; the Neon heads carry the rest.
]]
local function buildTownApproach(parent: Instance)
	local groundY = TidetownConfig.layout.townGroundY

	local lampSpots = {
		{ x = 100, z = 7 },
		{ x = 118, z = -7, lit = true },
		{ x = 136, z = 6 },
	}
	for _, spot in ipairs(lampSpots) do
		createPart({
			Name = "LampPost",
			Size = Vector3.new(0.7, 6.5, 0.7),
			Position = Vector3.new(spot.x, groundY + 3.25, spot.z),
			Material = Enum.Material.Wood,
			Color = WOOD_COLOR,
			Parent = parent,
		})

		local head = createPart({
			Name = "LampHead",
			Size = Vector3.new(1, 1, 1),
			Position = Vector3.new(spot.x, groundY + 7, spot.z),
			Material = Enum.Material.Neon,
			Color = AMBER_GLOW,
			Parent = parent,
		})
		if spot.lit == true then
			addWarmLight(head, 14)
		end
	end
end

--[[
	Dresses the built map once. Skips entirely when the map is missing
	(nothing to dress) or when a Scenery folder already exists (a
	rebuild, or a hand-dressed map -- either way the existing set wins).
]]
function SceneryBuilder.build()
	local tidetown = Workspace:FindFirstChild(MAP_FOLDER_NAME)
	if tidetown == nil then
		return
	end
	if tidetown:FindFirstChild(SCENERY_FOLDER_NAME) ~= nil then
		return
	end

	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	packModelsFolder = if assetsFolder ~= nil then assetsFolder:FindFirstChild("Models") else nil

	local sceneryFolder = Instance.new("Folder")
	sceneryFolder.Name = SCENERY_FOLDER_NAME

	-- An ordered list, not a dictionary: hash iteration order is not
	-- guaranteed, and identical build order keeps folder layout and
	-- replication batches the same on every server.
	local areaBuilders: { { name: string, build: (Instance) -> () } } = {
		{ name = "Flats", build = buildFlats },
		{ name = "DrySand", build = buildDrySand },
		{ name = "Pier", build = buildPier },
		{ name = "Horizon", build = buildHorizon },
		{ name = "CaveMouth", build = buildCaveMouth },
		{ name = "TownApproach", build = buildTownApproach },
	}
	for _, area in ipairs(areaBuilders) do
		local areaFolder = Instance.new("Folder")
		areaFolder.Name = area.name
		areaFolder.Parent = sceneryFolder
		area.build(areaFolder)
	end

	-- Parented last so the whole dressed set replicates in one batch.
	sceneryFolder.Parent = tidetown
end

return SceneryBuilder
