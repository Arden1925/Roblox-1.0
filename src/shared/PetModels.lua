--[[
	Builds the 3D model for any pet id from the Sea Animals asset pack in
	ReplicatedStorage.Assets.Models: the pet's name picks the animal, the
	model is normalized to pet size and centered on the origin, and a
	mutation dresses it up -- a bigger body, a colored aura shell, themed
	particles, and light. Used by UI viewports on the client and by the
	in-world follower on the server; a primitive fallback pet keeps both
	working if the asset pack is ever missing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = script.Parent
local PetCatalog = require(Shared.PetCatalog)

-- Pets whose display name differs from the model name in the pack.
local MODEL_ALIASES = {
	["Electric Eel"] = "ElectricEel",
	["Steampunk Turtle"] = "SteampunkTurtle",
	["Fruit Turtle"] = "FruitTurtle",
	["Flower Whale"] = "FlowerWhale",
}

-- Base body height in studs before the mutation's scale multiplies it.
local BASE_HEIGHT = 2

local TIER_RANKS = {
	Common = 1,
	Rare = 2,
	Epic = 3,
	Legendary = 4,
	Mythic = 5,
	Ultra = 6,
}

-- Per-mutation particle tuning; color comes from the mutation spec.
-- Shadow and void smolder slowly with no glow, electric crackles fast,
-- magma sputters embers, and the two space tiers (cosmic, celestial)
-- add a second starfield emitter on top of their glow.
local MUTATION_PARTICLES: { [string]: { rate: number, speed: number, size: number } } = {
	shiny = { rate = 4, speed = 1, size = 0.25 },
	golden = { rate = 8, speed = 1.5, size = 0.3 },
	frozen = { rate = 8, speed = 0.6, size = 0.35 },
	toxic = { rate = 10, speed = 1, size = 0.35 },
	electric = { rate = 16, speed = 4, size = 0.2 },
	magma = { rate = 14, speed = 1.8, size = 0.3 },
	shadow = { rate = 10, speed = 0.5, size = 0.6 },
	rainbow = { rate = 14, speed = 2, size = 0.3 },
	void = { rate = 12, speed = 0.4, size = 0.55 },
	cosmic = { rate = 18, speed = 2.5, size = 0.35 },
	celestial = { rate = 20, speed = 2.2, size = 0.4 },
}

-- Mutations whose particles are darkness rather than light.
local UNLIT_MUTATIONS: { [string]: boolean } = {
	shadow = true,
	void = true,
}

-- Mutations that earn the extra starfield emitter.
local STARFIELD_MUTATIONS: { [string]: boolean } = {
	cosmic = true,
	celestial = true,
}

local PetModels = {}

function PetModels.tierRank(tierName: string): number
	return TIER_RANKS[tierName] or 1
end

local function findAnimalTemplate(baseName: string): Instance?
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local modelsFolder = if assetsFolder ~= nil then assetsFolder:FindFirstChild("Models") else nil
	local pack = if modelsFolder ~= nil
		then modelsFolder:FindFirstChild("Sea_Animals_Pack")
		else nil
	local animals = if pack ~= nil then pack:FindFirstChild("Models") else nil
	if animals == nil then
		return nil
	end

	local template = animals:FindFirstChild(baseName)
	if template == nil and MODEL_ALIASES[baseName] ~= nil then
		template = animals:FindFirstChild(MODEL_ALIASES[baseName])
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

-- The stand-in pet when the asset pack is missing: a tinted ball with
-- eyes, so every screen still shows something alive.
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
	The mutation's visual signature: a translucent colored shell with a
	glow light and a particle emitter tuned per mutation. Rainbow cycles
	its particle colors through the full wheel instead of one hue.
]]
local function applyMutationVisuals(model: Model, mutation: PetCatalog.PetMutation)
	local _, boxSize = model:GetBoundingBox()
	local shellDiameter = math.max(boxSize.X, boxSize.Y, boxSize.Z) + 0.8

	local shell = Instance.new("Part")
	shell.Name = "MutationAura"
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.new(shellDiameter, shellDiameter, shellDiameter)
	shell.CFrame = CFrame.new(0, 0, 0)
	shell.Color = mutation.color
	shell.Material = Enum.Material.ForceField
	shell.Transparency = 0.4
	shell.Anchored = true
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = false
	shell.CastShadow = false
	shell.Parent = model

	local light = Instance.new("PointLight")
	light.Color = mutation.color
	light.Brightness = 2
	light.Range = 8
	light.Parent = shell

	local tuning = MUTATION_PARTICLES[mutation.key]
	if tuning == nil then
		return
	end

	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = tuning.rate
	emitter.Speed = NumberRange.new(tuning.speed * 0.6, tuning.speed)
	emitter.Lifetime = NumberRange.new(0.6, 1.4)
	emitter.Size = NumberSequence.new(tuning.size)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.LightEmission = if UNLIT_MUTATIONS[mutation.key] == true then 0 else 0.8
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = shell

	if mutation.key == "rainbow" then
		emitter.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 80)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 255, 140)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 140, 255)),
		})
	else
		emitter.Color = ColorSequence.new(mutation.color)
	end

	-- Space pets float in their own tiny galaxy: a second, dimmer
	-- emitter of slow white stars behind the colored one.
	if STARFIELD_MUTATIONS[mutation.key] == true then
		local stars = emitter:Clone()
		stars.Rate = 8
		stars.Speed = NumberRange.new(0.3, 0.8)
		stars.Size = NumberSequence.new(0.15)
		stars.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		stars.Parent = shell
	end
end

--[[
	Builds the pet model centered on the origin, BASE_HEIGHT studs tall
	before the mutation scale. Returns nil for unknown ids so callers can
	fall back gracefully.
]]
function PetModels.build(petId: string): Model?
	local info = PetCatalog.infoFor(petId)
	if info == nil then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = info.name

	local template = findAnimalTemplate(info.baseName)
	if template ~= nil then
		local clone = template:Clone()
		clone.Parent = model
	else
		buildFallback(model, info.tierColor)
	end

	makeInert(model)

	local extents = model:GetExtentsSize()
	if extents.Y < 0.05 then
		model:Destroy()

		return nil
	end

	local targetHeight = BASE_HEIGHT * (if info.mutation ~= nil then info.mutation.scale else 1)
	model:ScaleTo(targetHeight / extents.Y)

	-- Recenter so the bounding box sits on the origin: viewport cameras
	-- and the follower's alignment both assume the pet is centered.
	local boxCFrame = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() - boxCFrame.Position)

	-- Pick the anchor part before any aura shell exists, so the follower
	-- aligns to the animal's body rather than the effect shell.
	model.PrimaryPart = largestPart(model)

	if info.mutation ~= nil then
		applyMutationVisuals(model, info.mutation)
	elseif PetModels.tierRank(info.tierName) >= 5 then
		-- Top tiers glow softly even unmutated, so a Mythic in a
		-- viewport reads as special at a glance.
		local body = model.PrimaryPart
		if body ~= nil then
			local light = Instance.new("PointLight")
			light.Color = info.tierColor
			light.Brightness = 1.5
			light.Range = 6
			light.Parent = body
		end
	end

	return model
end

return PetModels
