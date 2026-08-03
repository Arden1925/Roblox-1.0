--[[
	The portal-gun look: swirling green rings and orbiting sparks around
	every portal disc, plus a gentle lean toward you as you approach --
	the swirl follows you a little, then lets go past arm's length. All
	parts are created locally, so the whole show costs the server
	nothing and other players' effects never stack.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PORTAL_TAG = "Portal"

local SWIRL_GREEN = Color3.fromRGB(97, 255, 66)
local DEEP_GREEN = Color3.fromRGB(32, 178, 40)

-- How close you must be before the swirl starts leaning toward you,
-- and how far it may lean.
local FOLLOW_RANGE = 18
local MAX_LEAN = math.rad(18)

local ORBITER_COUNT = 5

type PortalEffect = {
	base: CFrame,
	rings: { BasePart },
	orbiters: { BasePart },
	container: Folder,
}

local effects: { [BasePart]: PortalEffect } = {}

local localPlayer = Players.LocalPlayer

local PortalEffects = {}

local function createLocalPart(properties: { [string]: any }): BasePart
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

local function buildEffect(portal: BasePart)
	if effects[portal] ~= nil then
		return
	end

	local container = Instance.new("Folder")
	container.Name = "PortalEffects"

	local rings = {}
	for ringIndex = 1, 3 do
		local diameter = 13 + ringIndex * 2.2
		local ring = createLocalPart({
			Name = "SwirlRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.35, diameter, diameter),
			Color = if ringIndex % 2 == 0 then DEEP_GREEN else SWIRL_GREEN,
			Material = Enum.Material.Neon,
			Transparency = 0.25 + ringIndex * 0.15,
			Parent = container,
		})

		table.insert(rings, ring)
	end

	local orbiters = {}
	for _ = 1, ORBITER_COUNT do
		local orb = createLocalPart({
			Name = "SwirlSpark",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.7, 0.7, 0.7),
			Color = SWIRL_GREEN,
			Material = Enum.Material.Neon,
			Parent = container,
		})

		table.insert(orbiters, orb)
	end

	local light = Instance.new("PointLight")
	light.Color = SWIRL_GREEN
	light.Brightness = 2
	light.Range = 14
	light.Parent = portal

	container.Parent = Workspace

	effects[portal] = {
		base = portal.CFrame,
		rings = rings,
		orbiters = orbiters,
		container = container,
	}
end

local function removeEffect(portal: BasePart)
	local effect = effects[portal]
	if effect ~= nil then
		effect.container:Destroy()
		effects[portal] = nil
	end
end

local function updateEffect(effect: PortalEffect, elapsed: number)
	local center = effect.base

	-- Lean toward the local player while they are close: full lean at
	-- point blank, none at FOLLOW_RANGE, so the portal seems to notice
	-- you and then lose interest.
	local character = localPlayer.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart ~= nil then
		local offset = rootPart.Position - center.Position
		local distance = offset.Magnitude
		if distance < FOLLOW_RANGE and distance > 0.1 then
			local lean = MAX_LEAN * (1 - distance / FOLLOW_RANGE)
			local localOffset = center:VectorToObjectSpace(offset.Unit)
			center = center * CFrame.Angles(localOffset.Y * lean, -localOffset.X * lean, 0)
		end
	end

	for ringIndex, ring in ipairs(effect.rings) do
		local direction = if ringIndex % 2 == 0 then -1 else 1
		local speed = 0.8 + ringIndex * 0.5
		ring.CFrame = center * CFrame.Angles(direction * elapsed * speed, 0, 0)
	end

	for orbIndex, orb in ipairs(effect.orbiters) do
		local phase = elapsed * 2 + orbIndex * (math.pi * 2 / ORBITER_COUNT)
		local radius = 5 + math.sin(elapsed * 1.5 + orbIndex) * 2
		orb.CFrame = center
			* CFrame.new(
				math.sin(elapsed + orbIndex) * 0.8,
				math.cos(phase) * radius,
				math.sin(phase) * radius
			)
	end
end

function PortalEffects.start()
	for _, portal in ipairs(CollectionService:GetTagged(PORTAL_TAG)) do
		if portal:IsA("BasePart") then
			buildEffect(portal)
		end
	end

	CollectionService:GetInstanceAddedSignal(PORTAL_TAG):Connect(function(portal)
		if portal:IsA("BasePart") then
			buildEffect(portal)
		end
	end)

	CollectionService:GetInstanceRemovedSignal(PORTAL_TAG):Connect(removeEffect)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(deltaSeconds)
		elapsed += deltaSeconds

		for _, effect in pairs(effects) do
			updateEffect(effect, elapsed)
		end
	end)
end

return PortalEffects
