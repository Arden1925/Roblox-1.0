--[[
	The skill layer: hazards that shrink you on touch, platforms that fade
	under your feet, and bounce pads. All of them punish or reward Current
	Size and positioning only -- Max Size is never touched, keeping the
	game's "you never lose progress" promise.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent
local QuestService = require(Server.QuestService)
local ShopService = require(Server.ShopService)
local SizeService = require(Server.SizeService)

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)

local HAZARD_TAG = "Hazard"
local FADING_PLATFORM_TAG = "FadingPlatform"
local BOUNCE_PAD_TAG = "BouncePad"

local BOUNCE_DEBOUNCE_SECONDS = 0.2

local hazardDebounceByPlayer: { [Player]: number } = {}
local bounceDebounceByPlayer: { [Player]: number } = {}
local fadingPlatforms: { [BasePart]: boolean } = {}

local ObstacleService = {}

local function playerFromHit(hit: BasePart): Player?
	local character = hit.Parent
	if character == nil then
		return nil
	end

	return Players:GetPlayerFromCharacter(character)
end

local function onHazardTouched(hit: BasePart)
	local player = playerFromHit(hit)
	if player == nil then
		return
	end

	local debounceUntil = hazardDebounceByPlayer[player]
	if debounceUntil ~= nil and os.clock() < debounceUntil then
		return
	end
	hazardDebounceByPlayer[player] = os.clock() + GameConfig.obstacles.hazardDebounceSeconds

	-- Ember Shield (a city item) makes hazards harmless.
	if ShopService.effectActive(player, "EmberShield") then
		return
	end

	SizeService.forceShrink(player)
end

local function onFadingPlatformTouched(platform: BasePart, hit: BasePart)
	if playerFromHit(hit) == nil or fadingPlatforms[platform] then
		return
	end
	fadingPlatforms[platform] = true

	local originalTransparency = platform.Transparency

	task.spawn(function()
		-- A short warning flicker before the drop, so vanishing feels
		-- fair instead of random.
		task.wait(GameConfig.obstacles.fadeDelaySeconds / 2)
		platform.Transparency = 0.5
		task.wait(GameConfig.obstacles.fadeDelaySeconds / 2)

		platform.Transparency = 0.9
		platform.CanCollide = false

		task.wait(GameConfig.obstacles.fadeRespawnSeconds)

		platform.Transparency = originalTransparency
		platform.CanCollide = true
		fadingPlatforms[platform] = nil
	end)
end

local function onBouncePadTouched(hit: BasePart)
	local player = playerFromHit(hit)
	if player == nil then
		return
	end

	local debounceUntil = bounceDebounceByPlayer[player]
	if debounceUntil ~= nil and os.clock() < debounceUntil then
		return
	end
	bounceDebounceByPlayer[player] = os.clock() + BOUNCE_DEBOUNCE_SECONDS

	local character = player.Character
	if character == nil then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart ~= nil then
		local velocity = rootPart.AssemblyLinearVelocity
		rootPart.AssemblyLinearVelocity =
			Vector3.new(velocity.X, GameConfig.obstacles.bounceVelocity, velocity.Z)
		QuestService.increment(player, "launches")
	end
end

local function connectTag(tag: string, onTouched: (BasePart, BasePart) -> ())
	local function watch(part: Instance)
		if part:IsA("BasePart") then
			part.Touched:Connect(function(hit)
				onTouched(part, hit)
			end)
		end
	end

	for _, part in ipairs(CollectionService:GetTagged(tag)) do
		watch(part)
	end

	CollectionService:GetInstanceAddedSignal(tag):Connect(watch)
end

function ObstacleService.start()
	connectTag(HAZARD_TAG, function(_, hit)
		onHazardTouched(hit)
	end)

	connectTag(FADING_PLATFORM_TAG, onFadingPlatformTouched)

	connectTag(BOUNCE_PAD_TAG, function(_, hit)
		onBouncePadTouched(hit)
	end)

	Players.PlayerRemoving:Connect(function(player)
		hazardDebounceByPlayer[player] = nil
		bounceDebounceByPlayer[player] = nil
	end)
end

return ObstacleService
