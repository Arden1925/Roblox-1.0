--[[
	The RNG spice: Golden Pads and Falling Stars. Every interval a random
	grow pad per world turns gold (x5 growth, announced by its color),
	and every few minutes a star crashes somewhere with a sky-high beam
	-- first to touch it wins size and coins scaled to the world. Both
	create "drop everything" moments without touching core balance.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Server = script.Parent
local EconomyService = require(Server.EconomyService)
local SizeService = require(Server.SizeService)

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local WorldLayout = require(Shared.WorldLayout)

local GOLD_COLOR = Color3.fromRGB(255, 215, 0)
local STAR_LIFETIME_SECONDS = 60

local EventService = {}

local function padsInWorld(worldIndex: number): { BasePart }
	local minZ, maxZ = WorldLayout.boundsForWorld(worldIndex)
	local pads = {}

	for _, pad in ipairs(CollectionService:GetTagged("GrowPad")) do
		if
			pad:IsA("BasePart")
			and pad:IsDescendantOf(workspace)
			and pad.Position.Z >= minZ
			and pad.Position.Z < maxZ
		then
			table.insert(pads, pad)
		end
	end

	return pads
end

local function goldenPadRound()
	for worldIndex = 1, WorldLayout.worldCount() do
		local pads = padsInWorld(worldIndex)
		if #pads == 0 then
			continue
		end

		local pad = pads[math.random(#pads)]
		local originalColor = pad.Color

		pad:SetAttribute(
			"GoldenUntil",
			Workspace:GetServerTimeNow() + GameConfig.events.goldenPadDurationSeconds
		)
		pad.Color = GOLD_COLOR

		task.delay(GameConfig.events.goldenPadDurationSeconds, function()
			if pad.Parent ~= nil then
				pad.Color = originalColor
			end
		end)
	end
end

local function spawnStar()
	local worldIndex = math.random(WorldLayout.worldCount())
	local minZ = WorldLayout.boundsForWorld(worldIndex)
	local position =
		Vector3.new(math.random(-40, 40), WorldLayout.baseY + 2, minZ + math.random(40, 180))

	local star = Instance.new("Part")
	star.Name = "FallingStar"
	star.Shape = Enum.PartType.Ball
	star.Size = Vector3.new(4, 4, 4)
	star.Position = position
	star.Color = GOLD_COLOR
	star.Material = Enum.Material.Neon
	star.Anchored = true
	star.CanCollide = false
	CollectionService:AddTag(star, "Spinner")

	-- The beam is the announcement: visible from the whole world.
	local beam = Instance.new("Part")
	beam.Name = "StarBeam"
	beam.Size = Vector3.new(1.5, 200, 1.5)
	beam.Position = position + Vector3.new(0, 100, 0)
	beam.Color = GOLD_COLOR
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.5
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false

	local claimed = false
	star.Touched:Connect(function(hit)
		if claimed then
			return
		end

		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player == nil then
			return
		end
		claimed = true

		SizeService.grantMaxSize(player, GameConfig.events.starSizeBase * worldIndex)
		EconomyService.awardCoins(player, GameConfig.events.starCoinsBase * worldIndex)
		star:Destroy()
		beam:Destroy()
	end)

	star.Parent = workspace
	beam.Parent = workspace

	task.delay(STAR_LIFETIME_SECONDS, function()
		star:Destroy()
		beam:Destroy()
	end)
end

function EventService.start()
	task.spawn(function()
		while true do
			task.wait(GameConfig.events.goldenPadIntervalSeconds)
			goldenPadRound()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(GameConfig.events.starIntervalSeconds)
			spawnStar()
		end
	end)
end

return EventService
