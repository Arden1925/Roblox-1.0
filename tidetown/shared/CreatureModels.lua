--[[
	Builds the 3D model for any species key from the Sea Animals asset
	pack in ReplicatedStorage.Assets.Models: the species' modelName
	picks the animal, the model is normalized to a target height and
	centered on the origin, and a role accent adds a colored light so
	the four defense roles read at a glance even on unrigged, static
	meshes. Used by UI viewports on the client and by followers, reef
	tanks, mounts, and surge ferals on the server; a primitive fallback
	keeps every caller working if the asset pack is ever missing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = script.Parent
local CreatureCatalog = require(Shared.CreatureCatalog)

-- Pack models whose child name differs from the species' display name.
-- Unlisted names resolve directly, then with spaces stripped.
local MODEL_ALIASES = {
	["Electric Eel"] = "ElectricEel",
	["Steampunk Turtle"] = "SteampunkTurtle",
	["Fruit Turtle"] = "FruitTurtle",
	["Flower Whale"] = "FlowerWhale",
}

-- Accent colors per defense role: the one visual promise that a wall of
-- static fish still reads as Anchor/Sprayer/Herder/Sparker.
local ROLE_COLORS: { [string]: Color3 } = {
	Anchor = Color3.fromRGB(141, 110, 99),
	Sprayer = Color3.fromRGB(79, 195, 247),
	Herder = Color3.fromRGB(174, 213, 129),
	Sparker = Color3.fromRGB(255, 213, 79),
}

local CreatureModels = {}

function CreatureModels.roleColor(role: string): Color3
	return ROLE_COLORS[role] or Color3.fromRGB(255, 255, 255)
end

local function findPackTemplate(packName: string, modelName: string): Instance?
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local modelsFolder = if assetsFolder ~= nil then assetsFolder:FindFirstChild("Models") else nil
	local pack = if modelsFolder ~= nil then modelsFolder:FindFirstChild(packName) else nil
	local inner = if pack ~= nil then pack:FindFirstChild("Models") else nil
	if inner == nil then
		return nil
	end

	local template = inner:FindFirstChild(modelName)

	if template == nil and MODEL_ALIASES[modelName] ~= nil then
		template = inner:FindFirstChild(MODEL_ALIASES[modelName])
	end

	if template == nil then
		template = inner:FindFirstChild(string.gsub(modelName, " ", ""))
	end

	return template
end

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

local function largestPart(container: Model): BasePart?
	local best: BasePart? = nil
	local bestVolume = 0

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local size = descendant.Size
			local volume = size.X * size.Y * size.Z
			if volume > bestVolume then
				bestVolume = volume
				best = descendant
			end
		end
	end

	return best
end

-- The stand-in when the asset pack is missing: a tinted ball with eyes,
-- so every screen still shows something alive.
local function buildFallback(model: Model, tint: Color3)
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(1.8, 1.8, 1.8)
	body.CFrame = CFrame.new(0, 0, 0)
	body.Color = tint
	body.Material = Enum.Material.SmoothPlastic
	body.Parent = model

	for _, sideX in ipairs({ -0.4, 0.4 }) do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(0.3, 0.3, 0.3)
		eye.CFrame = CFrame.new(sideX, 0.3, -0.8)
		eye.Color = Color3.fromRGB(20, 20, 25)
		eye.Material = Enum.Material.SmoothPlastic
		eye.Parent = model
	end
end

--[[
	Normalizes a cloned pack model: inert parts, a known height, the
	bounding box centered on the origin, and the pivot pinned to the
	centered geometry. Pack authors left pivots wherever the asset
	happened to sit, and anything that later calls PivotTo positions
	the PIVOT -- an off-pivot model would fling away from where it was
	aimed.
]]
local function normalize(model: Model, targetHeight: number): boolean
	makeInert(model)

	local extents = model:GetExtentsSize()
	if extents.Y < 0.05 then
		return false
	end

	model:ScaleTo(targetHeight / extents.Y)

	local boxCFrame = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() - boxCFrame.Position)
	model.WorldPivot = CFrame.new()
	model.PrimaryPart = largestPart(model)

	return true
end

--[[
	Builds a species model centered on the origin, heightStuds tall.
	Always returns a model: unknown species and missing packs fall back
	to the primitive stand-in rather than nil, so callers never branch.
]]
function CreatureModels.build(speciesKey: string, heightStuds: number): Model
	local species = CreatureCatalog.speciesFor(speciesKey)

	local model = Instance.new("Model")
	model.Name = if species ~= nil then species.name else speciesKey

	local template = if species ~= nil
		then findPackTemplate("Sea_Animals_Pack", species.modelName)
		else nil

	if template ~= nil then
		local clone = template:Clone()
		clone.Parent = model
	else
		local tint = if species ~= nil
			then CreatureCatalog.rarityColor(species.rarity)
			else Color3.fromRGB(120, 190, 230)
		buildFallback(model, tint)
	end

	if not normalize(model, heightStuds) then
		buildFallback(model, Color3.fromRGB(120, 190, 230))
		normalize(model, heightStuds)
	end

	-- Legendaries glow softly and every creature carries its role
	-- accent light, so rarity and role both read at a glance.
	if species ~= nil and model.PrimaryPart ~= nil then
		local light = Instance.new("PointLight")
		light.Color = CreatureModels.roleColor(species.role)
		light.Brightness = if species.rarity == "legendary" then 1.6 else 0.8
		light.Range = if species.rarity == "legendary" then 8 else 5
		light.Parent = model.PrimaryPart
	end

	return model
end

--[[
	Builds an egg model from the Classic Studs pack, normalized and
	centered like a creature. Falls back to a studded primitive egg so
	the hatch cinematic always has something to crack.
]]
function CreatureModels.buildEgg(modelName: string, heightStuds: number): Model
	local model = Instance.new("Model")
	model.Name = modelName

	local template = findPackTemplate("Classic_Studs_Eggs_Pack", modelName)
	if template ~= nil then
		local clone = template:Clone()
		clone.Parent = model
	else
		local body = Instance.new("Part")
		body.Name = "Shell"
		body.Shape = Enum.PartType.Ball
		body.Size = Vector3.new(1.6, 2, 1.6)
		body.CFrame = CFrame.new(0, 0, 0)
		body.Color = Color3.fromRGB(236, 224, 200)
		body.Material = Enum.Material.Slate
		body.Parent = model
	end

	if not normalize(model, heightStuds) then
		model:Destroy()

		return CreatureModels.buildEgg("", heightStuds)
	end

	return model
end

return CreatureModels
