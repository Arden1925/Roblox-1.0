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
local PORTAL_COLOR = Color3.fromRGB(0, 206, 201)
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

	-- Lampposts around the plaza so the hub reads warm at night.
	for _, lampOffset in ipairs({
		Vector3.new(-25, 0, 45),
		Vector3.new(25, 0, 45),
		Vector3.new(-35, 0, -10),
		Vector3.new(35, 0, -10),
		Vector3.new(0, 0, -60),
		Vector3.new(-90, 0, 60),
	}) do
		local base = CENTER + lampOffset
		createPart({
			Name = "LampPole",
			Size = Vector3.new(0.7, 9, 0.7),
			Position = base + Vector3.new(0, 4.5, 0),
			Color = Color3.fromRGB(62, 74, 96),
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = parent,
		})
		local globe = createPart({
			Name = "LampGlobe",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2, 2, 2),
			Position = base + Vector3.new(0, 10, 0),
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

	-- Simple part-built trees keep the cozy park feel without another
	-- asset pack.
	for _, treeSpec in ipairs({
		{ offset = Vector3.new(-45, 0, 70), height = 11 },
		{ offset = Vector3.new(50, 0, 66), height = 9 },
		{ offset = Vector3.new(-115, 0, -20), height = 12 },
		{ offset = Vector3.new(115, 0, 10), height = 10 },
		{ offset = Vector3.new(20, 0, -95), height = 12 },
	}) do
		local base = CENTER + treeSpec.offset
		createPart({
			Name = "TreeTrunk",
			Size = Vector3.new(2, treeSpec.height, 2),
			Position = base + Vector3.new(0, treeSpec.height / 2, 0),
			Color = WOOD_COLOR,
			Material = Enum.Material.Wood,
			Parent = parent,
		})
		for blobIndex, blobOffset in ipairs({
			Vector3.new(0, treeSpec.height + 2.5, 0),
			Vector3.new(2.4, treeSpec.height + 0.8, 1),
			Vector3.new(-2, treeSpec.height + 1, -1.6),
		}) do
			createPart({
				Name = "TreeLeaves" .. blobIndex,
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(7 - blobIndex, 6 - blobIndex, 7 - blobIndex),
				Position = base + blobOffset,
				Color = Color3.fromRGB(88, 178, 78),
				Material = Enum.Material.Grass,
				CanCollide = false,
				Parent = parent,
			})
		end
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

	for _, benchOffset in ipairs({ -60, -20, 20, 60 }) do
		createPart({
			Name = "TerraceBenchSeat",
			Size = Vector3.new(8, 0.8, 2.4),
			Position = Vector3.new(CENTER.X + benchOffset, hub.surfaceY + 1.6, TERRACE_EDGE_Z - 10),
			Color = PLANK_COLOR,
			Material = Enum.Material.WoodPlanks,
			Parent = parent,
		})
		for _, legOffset in ipairs({ -3.2, 3.2 }) do
			createPart({
				Name = "TerraceBenchLeg",
				Size = Vector3.new(0.8, 1.2, 2.2),
				Position = Vector3.new(
					CENTER.X + benchOffset + legOffset,
					hub.surfaceY + 0.6,
					TERRACE_EDGE_Z - 10
				),
				Color = WOOD_COLOR,
				Material = Enum.Material.Wood,
				CanCollide = false,
				Parent = parent,
			})
		end
	end

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

	for _, pillarOffset in ipairs({ -6, 6 }) do
		createPart({
			Name = "PortalPillar",
			Size = Vector3.new(2, 14, 2),
			Position = base + Vector3.new(pillarOffset, 7, 0),
			Color = Color3.fromRGB(62, 74, 96),
			Material = Enum.Material.Slate,
			Parent = parent,
		})
	end

	createPart({
		Name = "PortalArch",
		Size = Vector3.new(16, 2, 2),
		Position = base + Vector3.new(0, 14.5, 0),
		Color = Color3.fromRGB(62, 74, 96),
		Material = Enum.Material.Slate,
		Parent = parent,
	})

	local swirl = createPart({
		Name = "Portal",
		Size = Vector3.new(11, 12, 0.8),
		Position = base + Vector3.new(0, 7, 0),
		Color = PORTAL_COLOR,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		CanCollide = false,
		Parent = parent,
	})
	swirl:SetAttribute("WorldIndex", 1)
	addPrompt(swirl, "Travel", "Portal")
	addBillboard(swirl, "PORTAL -- TRAVEL TO THE WORLDS!", PORTAL_COLOR, 9)
	addOutline(swirl, PORTAL_COLOR)
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
end

local function buildWheel(parent: Instance)
	local base = CENTER + Vector3.new(-70, 0, -50)
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

	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local modelsFolder = if assetsFolder ~= nil then assetsFolder:FindFirstChild("Models") else nil
	if modelsFolder ~= nil then
		placeTown(hubFolder, modelsFolder)
		placeEggGarden(hubFolder, modelsFolder)
	else
		warn("ReplicatedStorage.Assets.Models missing; hub packs skipped")
	end

	hubFolder.Parent = Workspace
end

return HubService
