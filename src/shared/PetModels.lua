--[[
	Builds a small 3D model for any pet id, deterministically: the same
	pet always looks the same everywhere, without any uploaded assets.
	The id's hash picks the body shape and proportions, the tier picks
	the color, and higher tiers earn extras -- horns, halos, and a
	glowing aura shell. Used by UI viewports on the client and by the
	in-world follower on the server.
]]

local Shared = script.Parent
local PetCatalog = require(Shared.PetCatalog)

local BODY_SHAPES = {
	Enum.PartType.Ball,
	Enum.PartType.Block,
	Enum.PartType.Cylinder,
}

-- Tiers at or above these ranks earn each extra.
local HORN_MINIMUM_RANK = 3
local HALO_MINIMUM_RANK = 5
local AURA_MINIMUM_RANK = 4

local TIER_RANKS = {
	Common = 1,
	Rare = 2,
	Epic = 3,
	Legendary = 4,
	Mythic = 5,
	Ultra = 6,
}

local PetModels = {}

local function hashString(text: string): number
	local hash = 5381

	for index = 1, #text do
		hash = (hash * 33 + string.byte(text, index)) % 1048576
	end

	return hash
end

local function createPart(properties: { [string]: any }): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
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

function PetModels.tierRank(tierName: string): number
	return TIER_RANKS[tierName] or 1
end

--[[
	Builds the pet model centered on the origin, roughly 2 studs tall.
	Returns nil for unknown ids so callers can fall back gracefully.
]]
function PetModels.build(petId: string): Model?
	local info = PetCatalog.infoFor(petId)
	if info == nil then
		return nil
	end

	local hash = hashString(petId)
	local rank = PetModels.tierRank(info.tierName)

	local model = Instance.new("Model")
	model.Name = info.name

	local bodyShape = BODY_SHAPES[hash % #BODY_SHAPES + 1]
	local bodyWidth = 1.4 + (hash % 5) * 0.12

	local body = createPart({
		Name = "Body",
		Shape = bodyShape,
		Size = Vector3.new(bodyWidth, 1.3, 1.1),
		CFrame = CFrame.new(0, 0, 0),
		Color = info.tierColor,
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	local head = createPart({
		Name = "Head",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.9, 0.9, 0.9),
		CFrame = CFrame.new(0, 0.95, -0.2),
		Color = info.tierColor:Lerp(Color3.fromRGB(255, 255, 255), 0.35),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})

	-- Eyes make it a creature instead of a shape.
	for _, sideX in ipairs({ -0.22, 0.22 }) do
		createPart({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.18, 0.18, 0.18),
			CFrame = head.CFrame * CFrame.new(sideX, 0.1, -0.38),
			Color = Color3.fromRGB(20, 20, 25),
			Material = Enum.Material.SmoothPlastic,
			Parent = model,
		})
	end

	-- Ears vary by hash so siblings in one egg still differ.
	if hash % 3 ~= 0 then
		for _, sideX in ipairs({ -0.3, 0.3 }) do
			createPart({
				Name = "Ear",
				Size = Vector3.new(0.2, 0.55, 0.2),
				CFrame = head.CFrame * CFrame.new(sideX, 0.5, 0),
				Color = info.tierColor,
				Material = Enum.Material.SmoothPlastic,
				Parent = model,
			})
		end
	end

	if rank >= HORN_MINIMUM_RANK then
		createPart({
			Name = "Horn",
			Size = Vector3.new(0.18, 0.6, 0.18),
			CFrame = head.CFrame * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(8)),
			Color = Color3.fromRGB(255, 234, 167),
			Material = Enum.Material.Neon,
			Parent = model,
		})
	end

	if rank >= HALO_MINIMUM_RANK then
		createPart({
			Name = "Halo",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, 1, 1),
			CFrame = head.CFrame * CFrame.new(0, 0.85, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(255, 234, 167),
			Material = Enum.Material.Neon,
			Parent = model,
		})
	end

	-- The aura: a glowing translucent shell around the whole pet, the
	-- visual signature of hard-to-get tiers.
	if rank >= AURA_MINIMUM_RANK then
		local aura = createPart({
			Name = "Aura",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.8, 2.8, 2.8),
			CFrame = CFrame.new(0, 0.3, 0),
			Color = info.tierColor,
			Material = Enum.Material.ForceField,
			Transparency = 0.35,
			Parent = model,
		})

		local light = Instance.new("PointLight")
		light.Color = info.tierColor
		light.Brightness = 1.5
		light.Range = 6
		light.Parent = aura
	end

	model.PrimaryPart = body

	return model
end

return PetModels
