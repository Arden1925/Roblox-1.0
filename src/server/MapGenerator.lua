--[[
	Builds the playable starter map: a chain of long square worlds, each
	split into three sections (grow, shrink, skill) with checkpoints
	between them, coin routes, an egg capsule, a shop station, and a
	portal -- separated by ever-taller climbable walls and ringed by
	borders. It runs only when the workspace has no tagged pads, so a
	hand-built map always wins.

	All gameplay meaning comes from tags and attributes (see
	GAME_DESIGN.md); all geometry math comes from WorldLayout so the
	progress tracker always agrees with what got built. Parts tagged
	Spinner are purely visual -- the client spins and bobs them.
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
local GATE_COLOR = Color3.fromRGB(232, 65, 24)
local CRACK_COLOR = Color3.fromRGB(255, 168, 1)
local HAZARD_COLOR = Color3.fromRGB(255, 71, 87)
local BOUNCE_COLOR = Color3.fromRGB(255, 121, 198)
local WALL_COLOR = Color3.fromRGB(87, 96, 111)
local BORDER_COLOR = Color3.fromRGB(47, 54, 64)
local STEP_COLOR = Color3.fromRGB(223, 228, 234)
-- Portal-gun green, per the reference everyone knows.
local PORTAL_COLOR = Color3.fromRGB(97, 255, 66)
local COIN_COLOR = Color3.fromRGB(253, 203, 110)
local CHECKPOINT_COLOR = Color3.fromRGB(0, 206, 201)

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
	-- Titles face you while you are near, then stop following: past this
	-- distance the label simply is not drawn.
	billboard.MaxDistance = 45
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

-- The "physical outline" on interactables: a glowing edge players spot
-- from across the world, even partly through obstacles.
local function addOutline(part: BasePart, color: Color3)
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineColor = color
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = part
end

-- Per-world identity used by the egg capsules and decorations, so every
-- world reads as its own place the moment you walk in.
local WORLD_THEMES = {
	{
		eggMaterial = Enum.Material.Grass,
		accent = Color3.fromRGB(120, 224, 76),
		pedestalColor = Color3.fromRGB(88, 62, 41),
	},
	{
		eggMaterial = Enum.Material.DiamondPlate,
		accent = Color3.fromRGB(116, 185, 255),
		pedestalColor = Color3.fromRGB(99, 110, 114),
	},
	{
		eggMaterial = Enum.Material.CrackedLava,
		accent = Color3.fromRGB(255, 118, 33),
		pedestalColor = Color3.fromRGB(45, 45, 45),
	},
	{
		eggMaterial = Enum.Material.Ice,
		accent = Color3.fromRGB(224, 238, 255),
		pedestalColor = Color3.fromRGB(190, 210, 255),
	},
}

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

local function createCoin(parent: Instance, position: Vector3, worldIndex: number)
	local coin = createPart({
		Name = "Coin",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 3, 3),
		Position = position + Vector3.new(0, WorldLayout.baseY, 0),
		Color = COIN_COLOR,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = parent,
	})

	coin:SetAttribute("WorldIndex", worldIndex)
	CollectionService:AddTag(coin, "Coin")
	CollectionService:AddTag(coin, "Spinner")
end

local function createCheckpoint(
	parent: Instance,
	worldIndex: number,
	checkpointIndex: number,
	position: Vector3
)
	local checkpoint = createPart({
		Name = "Checkpoint",
		Size = Vector3.new(12, 1, 6),
		Position = position + Vector3.new(0, WorldLayout.baseY, 0),
		Color = CHECKPOINT_COLOR,
		Material = Enum.Material.Neon,
		Parent = parent,
	})

	checkpoint:SetAttribute("WorldIndex", worldIndex)
	checkpoint:SetAttribute("CheckpointIndex", checkpointIndex)
	CollectionService:AddTag(checkpoint, "Checkpoint")
	addBillboard(checkpoint, "CHECKPOINT", CHECKPOINT_COLOR, 5)
end

--[[
	The portal proper is a flat green disc; the swirling rings and
	particles around it are drawn client-side by PortalFx so every player
	gets the full effect at local-only cost.
]]
local function createPortal(parent: Instance, worldIndex: number, minZ: number)
	local portal = createPart({
		Name = "Portal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 13, 13),
		CFrame = CFrame.new(-44, WorldLayout.baseY + 7, minZ + 20)
			* CFrame.Angles(0, 0, math.rad(90))
			* CFrame.Angles(math.rad(90), 0, 0),
		Color = PORTAL_COLOR,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		CanCollide = false,
		Parent = parent,
	})

	addPrompt(portal, "Open Portal", "World Portal")
	addOutline(portal, Color3.fromRGB(160, 255, 130))
	addBillboard(portal, "PORTAL", Color3.fromRGB(160, 255, 130), 9)
	CollectionService:AddTag(portal, "Portal")
end

local function createEggStand(parent: Instance, worldIndex: number, minZ: number)
	local world = GameConfig.worlds[worldIndex]
	local theme = WORLD_THEMES[worldIndex]
	local center = Vector3.new(42, WorldLayout.baseY, minZ + 22)

	local pedestal = createPart({
		Name = "EggStand",
		Size = Vector3.new(6, 2, 6),
		Position = center + Vector3.new(0, 1, 0),
		Color = theme.pedestalColor,
		Material = Enum.Material.Marble,
		Parent = parent,
	})

	-- A themed ring around the base sells each capsule as belonging to
	-- its world at a glance.
	createPart({
		Name = "EggRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 9, 9),
		CFrame = CFrame.new(center + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = theme.accent,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = parent,
	})

	createPart({
		Name = "EggCapsule",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(9, 7, 7),
		CFrame = CFrame.new(center + Vector3.new(0, 6.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(223, 249, 251),
		Material = Enum.Material.Glass,
		Transparency = 0.6,
		CanCollide = false,
		Parent = parent,
	})

	local egg = createPart({
		Name = "EggOrb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3.4, 3.4, 3.4),
		Position = center + Vector3.new(0, 6.5, 0),
		Color = theme.accent,
		Material = theme.eggMaterial,
		CanCollide = false,
		Parent = parent,
	})
	CollectionService:AddTag(egg, "Spinner")

	pedestal:SetAttribute("WorldIndex", worldIndex)
	addPrompt(pedestal, "View Eggs", world.eggName)
	-- Well above the capsule top (~10 studs) so the title never clips
	-- into the glass or the egg.
	addBillboard(pedestal, world.eggName, theme.accent, 14)
	addOutline(pedestal, theme.accent)
	CollectionService:AddTag(pedestal, "EggStand")
end

local function createStation(parent: Instance, worldIndex: number, minZ: number)
	local station = createPart({
		Name = "ShopStation",
		Size = Vector3.new(7, 8, 3),
		Position = Vector3.new(-42, WorldLayout.baseY + 4, minZ + 36),
		Color = Color3.fromRGB(34, 166, 179),
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})

	station:SetAttribute("WorldIndex", worldIndex)
	addPrompt(station, "Open Station", "Potions & Upgrades")
	addBillboard(station, "STATION", Color3.fromRGB(129, 236, 236), 6)
	addOutline(station, Color3.fromRGB(129, 236, 236))
	CollectionService:AddTag(station, "ShopStation")
end

local function createMysteryMachine(parent: Instance, worldIndex: number, minZ: number)
	local machine = createPart({
		Name = "MysteryMachine",
		Size = Vector3.new(6, 10, 5),
		Position = Vector3.new(-42, WorldLayout.baseY + 5, minZ + 52),
		Color = Color3.fromRGB(232, 67, 147),
		Material = Enum.Material.Metal,
		Parent = parent,
	})

	machine:SetAttribute("WorldIndex", worldIndex)
	addPrompt(machine, "Insert Coins", "Mystery Machine")
	addBillboard(machine, "MYSTERY MACHINE", Color3.fromRGB(255, 121, 198), 7)
	addOutline(machine, Color3.fromRGB(255, 121, 198))
	CollectionService:AddTag(machine, "MysteryMachine")
end

local function createLimitedDisplay(parent: Instance, minZ: number)
	local pedestal = createPart({
		Name = "LimitedDisplay",
		Size = Vector3.new(6, 2, 6),
		Position = Vector3.new(8, WorldLayout.baseY + 1, minZ + 10),
		Color = Color3.fromRGB(45, 52, 54),
		Material = Enum.Material.Marble,
		Parent = parent,
	})

	local orb = createPart({
		Name = "LimitedOrb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3.6, 3.6, 3.6),
		Position = Vector3.new(8, WorldLayout.baseY + 5.5, minZ + 10),
		Color = Color3.fromRGB(255, 234, 167),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = parent,
	})
	CollectionService:AddTag(orb, "Spinner")

	local limited = GameConfig.limitedPet
	addPrompt(pedestal, "View Limited Pet", limited.name)
	addBillboard(
		pedestal,
		string.format("LIMITED: %s -- R$ %d", limited.name, limited.robuxPrice),
		Color3.fromRGB(255, 234, 167),
		9
	)
	addOutline(pedestal, Color3.fromRGB(255, 234, 167))
	CollectionService:AddTag(pedestal, "LimitedDisplay")
end

--[[
	A wall across the world with a tagged barrier filling its opening.
	Used for both in-world gates (big enough to pass) and cracks (small
	enough to fit).
]]
local function createBarrierWall(
	parent: Instance,
	positionZ: number,
	openingWidth: number,
	openingHeight: number,
	tag: string,
	attributeName: string,
	attributeValue: number,
	barrierColor: Color3
)
	local wallHeight = math.max(20, openingHeight + 6)
	local sideWidth = (WorldLayout.width - openingWidth) / 2

	for _, sideX in ipairs({ -(openingWidth + sideWidth) / 2, (openingWidth + sideWidth) / 2 }) do
		createPart({
			Name = "BarrierWall",
			Size = Vector3.new(sideWidth, wallHeight, WALL_THICKNESS),
			Position = Vector3.new(sideX, WorldLayout.baseY + wallHeight / 2, positionZ),
			Color = WALL_COLOR,
			Material = Enum.Material.Slate,
			Parent = parent,
		})
	end

	createPart({
		Name = "BarrierWallTop",
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

	local barrier = createPart({
		Name = tag,
		Size = Vector3.new(openingWidth, openingHeight, WALL_THICKNESS),
		Position = Vector3.new(0, WorldLayout.baseY + openingHeight / 2, positionZ),
		Color = barrierColor,
		Material = Enum.Material.ForceField,
		Parent = parent,
	})

	barrier:SetAttribute(attributeName, attributeValue)
	CollectionService:AddTag(barrier, tag)
end

--[[
	The climbable boundary wall after a world, with floating steps on the
	approach side. Bigger characters jump higher, so the step spacing (a
	fraction of wall height) is what turns "grow" into "may pass".
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
		-- Fully solid: the world should feel like a place, not a fish
		-- tank with visible outside.
		createPart({
			Name = "Border",
			Size = border.size,
			Position = border.position + Vector3.new(0, WorldLayout.baseY, 0),
			Color = BORDER_COLOR,
			Material = Enum.Material.Slate,
			Parent = parent,
		})

		-- A glowing trim line breaks up the tall dark faces.
		local trimSize = if border.size.X > border.size.Z
			then Vector3.new(border.size.X, 0.8, border.size.Z + 0.4)
			else Vector3.new(border.size.X + 0.4, 0.8, border.size.Z)

		createPart({
			Name = "BorderTrim",
			Size = trimSize,
			Position = border.position
				+ Vector3.new(0, WorldLayout.baseY + 14 - border.size.Y / 2, 0),
			Color = Color3.fromRGB(0, 206, 201),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = parent,
		})
	end
end

-- Three glass regrowth pods on the spawn plaza: stand inside and grow
-- hands-free at a fraction of pad rate. The zone part is the pod floor.
local function createAfkPods(parent: Instance, minZ: number)
	for podIndex = 1, 3 do
		local center = Vector3.new(14 + podIndex * 8, WorldLayout.baseY, minZ + 34)

		local floor = createPart({
			Name = "AfkPod",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 6, 6),
			CFrame = CFrame.new(center + Vector3.new(0, 0.3, 0))
				* CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(0, 206, 201),
			Material = Enum.Material.Neon,
			Parent = parent,
		})
		CollectionService:AddTag(floor, "AfkPod")

		createPart({
			Name = "PodGlass",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(9, 5.5, 5.5),
			CFrame = CFrame.new(center + Vector3.new(0, 5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(198, 240, 255),
			Material = Enum.Material.Glass,
			Transparency = 0.65,
			CanCollide = false,
			Parent = parent,
		})

		createPart({
			Name = "PodCap",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(5.5, 2.4, 5.5),
			Position = center + Vector3.new(0, 9.6, 0),
			Color = Color3.fromRGB(99, 110, 114),
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = parent,
		})
	end

	local sign = createPart({
		Name = "PodSign",
		Size = Vector3.new(8, 0.4, 4),
		Position = Vector3.new(30, WorldLayout.baseY + 0.2, minZ + 27),
		Color = Color3.fromRGB(0, 206, 201),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = parent,
	})
	addBillboard(sign, "AFK GROW PODS", Color3.fromRGB(0, 206, 201), 4)
end

-- The group reward chest: a proper treasure chest with a lid, gold
-- banding, and a lock plate, claimable once by group members.
local function createGroupChest(parent: Instance, minZ: number)
	local center = Vector3.new(-8, WorldLayout.baseY, minZ + 10)

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
			Color = Color3.fromRGB(253, 203, 110),
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = parent,
		})
	end

	createPart({
		Name = "ChestLock",
		Size = Vector3.new(1, 1.2, 0.4),
		Position = center + Vector3.new(0, 1.8, 1.8),
		Color = Color3.fromRGB(253, 203, 110),
		Material = Enum.Material.Metal,
		CanCollide = false,
		Parent = parent,
	})

	addPrompt(body, "Claim Group Reward", "Group Chest")
	addBillboard(body, "GROUP REWARD -- JOIN & LIKE!", Color3.fromRGB(253, 203, 110), 6)
	addOutline(body, Color3.fromRGB(253, 203, 110))
	CollectionService:AddTag(body, "GroupChest")
end

-- A crusher bar over the main lane: rises and slams on a slow sine
-- cycle. Caught players lose Current Size only.
local function createCrusher(parent: Instance, worldIndex: number, minZ: number)
	local cycleSeconds = GameConfig.mechanisms.crusherCycleSeconds[worldIndex]
	if cycleSeconds == nil or cycleSeconds <= 0 then
		return
	end

	local crusher = createPart({
		Name = "Crusher",
		Size = Vector3.new(24, 2.5, 5),
		Position = Vector3.new(0, WorldLayout.baseY + 9, minZ + 70),
		Color = Color3.fromRGB(120, 90, 200),
		Material = Enum.Material.DiamondPlate,
		Parent = parent,
	})

	crusher:SetAttribute("CycleSeconds", cycleSeconds)
	crusher:SetAttribute("DropHeight", 7.5)

	for _, sideX in ipairs({ -13, 13 }) do
		createPart({
			Name = "CrusherPost",
			Size = Vector3.new(2, 12, 2),
			Position = Vector3.new(sideX, WorldLayout.baseY + 6, minZ + 70),
			Color = Color3.fromRGB(87, 96, 111),
			Material = Enum.Material.Metal,
			Parent = parent,
		})
	end

	CollectionService:AddTag(crusher, "Crusher")
end

--[[
	A cracked boulder sealing a side alcove: only characters at or above
	its CrushSize smash through. Built as a main rock with satellite
	rocks and dark crack seams so it reads as breakable at a glance.
]]
local function createBoulder(parent: Instance, position: Vector3, crushSize: number, accent: Color3)
	local boulder = createPart({
		Name = "CrushBoulder",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(8, 8, 8),
		Position = position + Vector3.new(0, WorldLayout.baseY + 3.5, 0),
		Color = Color3.fromRGB(120, 110, 100),
		Material = Enum.Material.Rock,
		Parent = parent,
	})

	boulder:SetAttribute("CrushSize", crushSize)
	CollectionService:AddTag(boulder, "CrushBoulder")

	for _, offset in ipairs({ Vector3.new(-4, -1, 2), Vector3.new(4.2, -1.5, -1) }) do
		createPart({
			Name = "BoulderChunk",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(3.4, 3.4, 3.4),
			Position = position + offset + Vector3.new(0, WorldLayout.baseY + 2, 0),
			Color = Color3.fromRGB(107, 98, 89),
			Material = Enum.Material.Rock,
			CanCollide = false,
			Parent = parent,
		})
	end

	for crackIndex = 1, 3 do
		createPart({
			Name = "BoulderCrack",
			Size = Vector3.new(0.25, 4.5, 0.25),
			CFrame = CFrame.new(position + Vector3.new(0, WorldLayout.baseY + 3.5, 0))
				* CFrame.Angles(0, crackIndex * 2, math.rad(20 * crackIndex))
				* CFrame.new(0, 0, -3.9),
			Color = Color3.fromRGB(35, 32, 30),
			Material = Enum.Material.Slate,
			CanCollide = false,
			Parent = parent,
		})
	end

	addBillboard(boulder, string.format("SMASH -- Size %d", crushSize), accent, 7)
end

--[[
	An updraft: a fan grate with a glowing ring whose air column lifts
	small bodies up to a coin ledge. Big characters walk over it like it
	is not there -- shrinking is the ticket up.
]]
local function createUpdraft(
	parent: Instance,
	worldIndex: number,
	position: Vector3,
	maxLiftSize: number,
	ledgeHeight: number
)
	local grate = createPart({
		Name = "Updraft",
		Size = Vector3.new(7, 0.6, 7),
		Position = position + Vector3.new(0, WorldLayout.baseY + 0.3, 0),
		Color = Color3.fromRGB(87, 96, 111),
		Material = Enum.Material.DiamondPlate,
		Parent = parent,
	})

	grate:SetAttribute("MaxLiftSize", maxLiftSize)
	CollectionService:AddTag(grate, "Updraft")

	local ring = createPart({
		Name = "UpdraftRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 8, 8),
		CFrame = CFrame.new(position + Vector3.new(0, WorldLayout.baseY + 0.7, 0))
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(129, 236, 236),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = parent,
	})
	CollectionService:AddTag(ring, "Spinner")

	addBillboard(grate, string.format("UPDRAFT -- Size %d or less", maxLiftSize), ring.Color, 5)

	-- The payoff ledge, floating beside the column.
	createPart({
		Name = "UpdraftLedge",
		Size = Vector3.new(10, 1, 10),
		Position = position + Vector3.new(9, WorldLayout.baseY + ledgeHeight, 0),
		Color = Color3.fromRGB(223, 228, 234),
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})

	for coinIndex = 1, 3 do
		createCoin(
			parent,
			position + Vector3.new(6 + coinIndex * 2, ledgeHeight + 1.5, 0),
			worldIndex
		)
	end
end

--[[
	The weight-plate bridge: a plank bridge with side rails that slides
	across a gap between two elevated platforms while enough combined
	Current Size stands on the pressure plate. Grow to hold it open,
	then cross -- or bring a friend.
]]
local function createPlateBridge(parent: Instance, worldIndex: number, minZ: number)
	local baseX = 38
	local platformY = WorldLayout.baseY + 8

	for _, spec in ipairs({ { minZ + 148, "NearPlatform" }, { minZ + 176, "FarPlatform" } }) do
		createPart({
			Name = spec[2],
			Size = Vector3.new(14, 1.2, 14),
			Position = Vector3.new(baseX, platformY, spec[1]),
			Color = Color3.fromRGB(99, 110, 114),
			Material = Enum.Material.Metal,
			Parent = parent,
		})
	end

	-- Steps up to the near platform.
	for stepIndex = 1, 2 do
		createPart({
			Name = "PlatformStep",
			Size = Vector3.new(8, 1.2, 5),
			Position = Vector3.new(
				baseX,
				WorldLayout.baseY + stepIndex * 2.6,
				minZ + 138 - stepIndex * 5
			),
			Color = Color3.fromRGB(223, 228, 234),
			Material = Enum.Material.SmoothPlastic,
			Parent = parent,
		})
	end

	-- The plate: base slab plus a fat red button that reads "stand here".
	local plate = createPart({
		Name = "WeightPlate",
		Size = Vector3.new(6, 0.6, 6),
		Position = Vector3.new(baseX - 3, platformY + 0.9, minZ + 148),
		Color = Color3.fromRGB(180, 90, 70),
		Material = Enum.Material.Neon,
		Parent = parent,
	})

	plate:SetAttribute("RequiredSize", 60)
	plate:SetAttribute("BridgeName", "VentBridge")
	addBillboard(plate, "HOLD 60+ SIZE TO EXTEND", Color3.fromRGB(255, 159, 67), 5)
	CollectionService:AddTag(plate, "WeightPlate")

	-- The bridge: main plank, cross planks, and side rails, parked
	-- inside the near platform until the plate is held.
	local bridge = createPart({
		Name = "VentBridge",
		Size = Vector3.new(6, 0.8, 16),
		Position = Vector3.new(baseX + 3, platformY, minZ + 154),
		Color = Color3.fromRGB(150, 110, 66),
		Material = Enum.Material.WoodPlanks,
		Parent = parent,
	})

	bridge:SetAttribute("ExtendZ", 14)
	CollectionService:AddTag(bridge, "MechBridge")

	for railOffset = -2.6, 2.6, 5.2 do
		local rail = createPart({
			Name = "BridgeRail",
			Size = Vector3.new(0.5, 1.6, 16),
			Position = Vector3.new(baseX + 3 + railOffset, platformY + 1.2, minZ + 154),
			Color = Color3.fromRGB(110, 80, 48),
			Material = Enum.Material.Wood,
			CanCollide = false,
			Parent = parent,
		})

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = bridge
		weld.Part1 = rail
		weld.Parent = rail
		rail.Anchored = false
	end

	for coinIndex = 1, 3 do
		createCoin(
			parent,
			Vector3.new(baseX - 4 + coinIndex * 3, platformY + 2, minZ + 176),
			worldIndex
		)
	end
end

--[[
	Per-world scenery so each world has its own vibe the moment you walk
	in: a meadow with trees and flowers, an industrial pipe yard, a
	glowing foundry, and a sky garden among clouds. Pure decoration --
	nothing here is tagged, so gameplay is untouched.
]]
local function createWorldDecor(parent: Instance, worldIndex: number, minZ: number)
	if worldIndex == 1 then
		for _, spot in ipairs({ { -36, 60 }, { 34, 100 }, { -30, 170 }, { 38, 150 } }) do
			createPart({
				Name = "TreeTrunk",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(7, 2, 2),
				CFrame = CFrame.new(spot[1], WorldLayout.baseY + 3.5, minZ + spot[2])
					* CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(110, 80, 48),
				Material = Enum.Material.Wood,
				Parent = parent,
			})

			createPart({
				Name = "TreeLeaves",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(7, 7, 7),
				Position = Vector3.new(spot[1], WorldLayout.baseY + 9, minZ + spot[2]),
				Color = Color3.fromRGB(88, 190, 60),
				Material = Enum.Material.Grass,
				CanCollide = false,
				Parent = parent,
			})
		end

		for _, spot in ipairs({ { -20, 35 }, { 24, 70 }, { -8, 130 }, { 12, 165 } }) do
			createPart({
				Name = "Flower",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(1, 1, 1),
				Position = Vector3.new(spot[1], WorldLayout.baseY + 0.5, minZ + spot[2]),
				Color = Color3.fromRGB(255, 121, 198),
				Material = Enum.Material.Neon,
				CanCollide = false,
				Parent = parent,
			})
		end

		-- First boulder: gentle requirement, coins waiting behind it.
		createBoulder(parent, Vector3.new(-34, 0, minZ + 118), 25, Color3.fromRGB(120, 224, 76))
		for coinIndex = 1, 3 do
			createCoin(parent, Vector3.new(-40 + coinIndex * 2, 2, minZ + 126), worldIndex)
		end
	elseif worldIndex == 2 then
		for _, spot in ipairs({ { -34, 55 }, { 34, 130 }, { -30, 175 } }) do
			for sideOffset = -4, 4, 8 do
				createPart({
					Name = "PipeLeg",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(12, 2, 2),
					CFrame = CFrame.new(
						spot[1] + sideOffset,
						WorldLayout.baseY + 6,
						minZ + spot[2]
					) * CFrame.Angles(0, 0, math.rad(90)),
					Color = Color3.fromRGB(120, 130, 140),
					Material = Enum.Material.Metal,
					Parent = parent,
				})
			end

			createPart({
				Name = "PipeTop",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(10, 2.4, 2.4),
				CFrame = CFrame.new(spot[1], WorldLayout.baseY + 12, minZ + spot[2]),
				Color = Color3.fromRGB(99, 110, 114),
				Material = Enum.Material.CorrodedMetal,
				Parent = parent,
			})
		end

		createUpdraft(parent, worldIndex, Vector3.new(-24, 0, minZ + 155), 25, 15)
		createPlateBridge(parent, worldIndex, minZ)
	elseif worldIndex == 3 then
		for _, spot in ipairs({ { -36, 45 }, { 36, 95 }, { -34, 185 } }) do
			createPart({
				Name = "LavaPool",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.4, 10, 10),
				CFrame = CFrame.new(spot[1], WorldLayout.baseY + 0.2, minZ + spot[2])
					* CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(255, 118, 33),
				Material = Enum.Material.Neon,
				CanCollide = false,
				Parent = parent,
			})
		end

		for _, spot in ipairs({ { -40, 70 }, { 40, 150 } }) do
			createPart({
				Name = "FoundryPillar",
				Size = Vector3.new(4, 18, 4),
				Position = Vector3.new(spot[1], WorldLayout.baseY + 9, minZ + spot[2]),
				Color = Color3.fromRGB(45, 45, 45),
				Material = Enum.Material.Basalt,
				Parent = parent,
			})
		end
	elseif worldIndex == 4 then
		for _, spot in ipairs({ { -30, 50, 14 }, { 32, 90, 18 }, { -26, 160, 22 } }) do
			for puffOffset = -3, 3, 3 do
				createPart({
					Name = "CloudPuff",
					Shape = Enum.PartType.Ball,
					Size = Vector3.new(6, 5, 5),
					Position = Vector3.new(
						spot[1] + puffOffset,
						WorldLayout.baseY + spot[3],
						minZ + spot[2]
					),
					Color = Color3.fromRGB(245, 246, 250),
					Material = Enum.Material.SmoothPlastic,
					CanCollide = false,
					Parent = parent,
				})
			end
		end
	end
end

-- A raised side ledge with coins: the optional "extra route" that pays
-- players for going out of their way.
local function createCoinLedge(parent: Instance, worldIndex: number, minZ: number, sideX: number)
	createPart({
		Name = "LedgeStep",
		Size = Vector3.new(10, 1, 8),
		Position = Vector3.new(sideX, WorldLayout.baseY + 3, minZ + 150),
		Color = STEP_COLOR,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})

	createPart({
		Name = "CoinLedge",
		Size = Vector3.new(12, 1, 34),
		Position = Vector3.new(sideX, WorldLayout.baseY + 6, minZ + 170),
		Color = STEP_COLOR,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})

	for offset = 0, 2 do
		createCoin(parent, Vector3.new(sideX, 8, minZ + 160 + offset * 10), worldIndex)
	end
end

local function buildWorldFlavor(parent: Instance, worldIndex: number, minZ: number)
	if worldIndex == 2 then
		-- The vent: a ceiling low enough that regrown players get stuck,
		-- so the corridor itself enforces "stay small".
		createPart({
			Name = "VentCeiling",
			Size = Vector3.new(WorldLayout.width, 1, 26),
			Position = Vector3.new(0, WorldLayout.baseY + 6.5, minZ + 123),
			Color = WALL_COLOR,
			Material = Enum.Material.DiamondPlate,
			Parent = parent,
		})
		createPad(parent, "ShrinkPad", Vector3.new(0, 0.5, minZ + 123), SHRINK_PAD_COLOR)
	elseif worldIndex == 3 then
		for _, patch in ipairs({ { -14, 120 }, { 10, 128 }, { -6, 150 }, { 18, 158 }, { 0, 166 } }) do
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

		-- A fading-platform bridge to a bonus island: optional skill
		-- content with a faster payoff.
		for bridgeIndex = 1, 3 do
			local platform = createPart({
				Name = "FadingPlatform",
				Size = Vector3.new(8, 1, 8),
				Position = Vector3.new(
					-34 + bridgeIndex * 9,
					WorldLayout.baseY + 4 + bridgeIndex * 3,
					minZ + 178
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
			Position = Vector3.new(6, WorldLayout.baseY + 15, minZ + 178),
			Color = Color3.fromRGB(255, 159, 67),
			Material = Enum.Material.Slate,
			Parent = parent,
		})
		createPad(parent, "GrowPad", Vector3.new(6, 16.5, minZ + 178), GROW_PAD_COLOR)

		-- The foundry vault: a serious boulder hiding a golden stash.
		createBoulder(parent, Vector3.new(36, 0, minZ + 66), 120, Color3.fromRGB(255, 118, 33))
		for coinIndex = 1, 4 do
			createCoin(parent, Vector3.new(30 + coinIndex * 3, 2, minZ + 58), worldIndex)
		end
	elseif worldIndex == 4 then
		local bounce = createPart({
			Name = "BouncePad",
			Size = Vector3.new(10, 1, 10),
			Position = Vector3.new(0, WorldLayout.baseY + 0.7, minZ + 150),
			Color = BOUNCE_COLOR,
			Material = Enum.Material.Neon,
			Parent = parent,
		})
		CollectionService:AddTag(bounce, "BouncePad")

		for stepIndex = 1, 3 do
			local platform = createPart({
				Name = "FadingPlatform",
				Size = Vector3.new(9, 1, 9),
				Position = Vector3.new(
					stepIndex * 10 - 20,
					WorldLayout.baseY + 12 + stepIndex * 4,
					minZ + 158 + stepIndex * 6
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
			Position = Vector3.new(10, WorldLayout.baseY + 27, minZ + 185),
			Color = Color3.fromRGB(190, 210, 255),
			Material = Enum.Material.Slate,
			Parent = parent,
		})
		for _, padX in ipairs({ 2, 18 }) do
			createPad(parent, "GrowPad", Vector3.new(padX, 28.5, minZ + 185), GROW_PAD_COLOR)
		end

		createUpdraft(parent, worldIndex, Vector3.new(-28, 0, minZ + 60), 25, 20)
	end
end

local function buildWorld(parent: Instance, worldIndex: number)
	local world = GameConfig.worlds[worldIndex]
	local minZ, maxZ = WorldLayout.boundsForWorld(worldIndex)
	local floorColor = world.floorColor

	createPart({
		Name = "Floor",
		Size = Vector3.new(WorldLayout.width, 1, WorldLayout.length),
		Position = Vector3.new(0, WorldLayout.baseY - 0.5, (minZ + maxZ) / 2),
		Color = Color3.fromRGB(floorColor[1], floorColor[2], floorColor[3]),
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})

	-- Plaza: portal, egg capsule, station, and (every Nth world) the
	-- Mystery Machine.
	createPortal(parent, worldIndex, minZ)
	createEggStand(parent, worldIndex, minZ)
	createStation(parent, worldIndex, minZ)
	createWorldDecor(parent, worldIndex, minZ)
	createCrusher(parent, worldIndex, minZ)
	if worldIndex % GameConfig.economy.mysteryMachineEveryNWorlds == 0 then
		createMysteryMachine(parent, worldIndex, minZ)
	end
	if worldIndex == 1 then
		createAfkPods(parent, minZ)
		createGroupChest(parent, minZ)
	end

	-- Section A -- grow: pads, a few coins, then a gate that demands
	-- real growth for this world.
	for _, padX in ipairs({ -16, 0, 16 }) do
		createPad(parent, "GrowPad", Vector3.new(padX, 0.5, minZ + 52), GROW_PAD_COLOR)
	end
	for _, coinX in ipairs({ -30, 30 }) do
		createCoin(parent, Vector3.new(coinX, 2, minZ + 60), worldIndex)
	end
	createBarrierWall(
		parent,
		minZ + 80,
		16,
		12 + worldIndex * 3,
		"SizeGate",
		"RequiredSize",
		world.gateRequiredSize,
		GATE_COLOR
	)
	createCheckpoint(parent, worldIndex, 1, Vector3.new(0, 0.5, minZ + 88))

	-- Section B -- shrink: a shrink pad, a crack, and world flavor that
	-- punishes staying big.
	createPad(parent, "ShrinkPad", Vector3.new(0, 0.5, minZ + 96), SHRINK_PAD_COLOR)
	createBarrierWall(parent, minZ + 110, 5, 5, "SqueezeCrack", "MaxAllowedSize", 15, CRACK_COLOR)
	createCheckpoint(parent, worldIndex, 2, Vector3.new(0, 0.5, minZ + 140))

	-- Section C -- skill and payout: flavor obstacles, the coin ledge,
	-- and pads to get big for the exit wall.
	buildWorldFlavor(parent, worldIndex, minZ)
	createCoinLedge(parent, worldIndex, minZ, if worldIndex % 2 == 0 then 44 else -44)
	for _, coinZ in ipairs({ 148, 156, 164 }) do
		createCoin(parent, Vector3.new(-24, 2, minZ + coinZ), worldIndex)
	end
	for _, padX in ipairs({ -12, 12 }) do
		createPad(parent, "GrowPad", Vector3.new(padX, 0.5, minZ + 188), GROW_PAD_COLOR)
	end

	if world.exitWallHeight ~= nil then
		createBoundaryWall(parent, worldIndex)
	end
end

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

	for worldIndex in ipairs(GameConfig.worlds) do
		buildWorld(map, worldIndex)
	end

	local firstMinZ = WorldLayout.boundsForWorld(1)
	createLimitedDisplay(map, firstMinZ)
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
