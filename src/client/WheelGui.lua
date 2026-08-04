--[[
	The prize wheel window: a carnival wheel of colored wedges that
	whirls past a fixed pointer and stops on the slice the server
	rolled. Opens from the wheel on the Main Island or its side button.
	Free-spin timing arrives as attributes; the actual roll is entirely
	server-side, so the wind-up, ratchet ticks, slow-motion landing,
	and tier-scaled celebrations here are presentation only.
]]

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent
local SoundController = require(Client.SoundController)
local Toast = require(Client.Toast)
local UiBuilder = require(Client.UiBuilder)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local PANEL_COLOR = Color3.fromRGB(24, 30, 38)
local GOLD_COLOR = Color3.fromRGB(253, 203, 110)
local READY_COLOR = Color3.fromRGB(76, 209, 55)
local LOCKED_COLOR = Color3.fromRGB(72, 84, 96)
local DISC_COLOR = Color3.fromRGB(58, 63, 72)
local BULB_LIT_COLOR = Color3.fromRGB(255, 240, 170)
local BULB_DIM_COLOR = Color3.fromRGB(146, 110, 50)

local WHEEL_DIAMETER = 260
local SLICE_INNER_RADIUS = 34
local SLICE_OUTER_RADIUS = 118
local BULB_RING_RADIUS = 124
local BULB_DIAMETER = 9
local HUB_DIAMETER = 52

local WIND_UP_DEGREES = 12
local WIND_UP_SECONDS = 0.4
local FAST_SPIN_SECONDS = 3.4
local SLOW_MO_SECONDS = 0.6
-- How many slice widths the slow-motion crawl covers; a couple keeps
-- two or three suspense ticks before the pointer settles.
local SLOW_MO_SLICES = 2.3
local EXTRA_TURNS = 4
-- The fast phase samples only the front of an ease-out curve so it
-- hands the slow-mo phase a wheel that is still visibly moving.
local FAST_CURVE_CUT = 0.75

local POINTER_BEND_DEGREES = 9
local BULB_CHASE_SECONDS = 0.07
local CELEBRATION_SECONDS = 2.4
local RAY_COUNT = 12

-- Built-in engine sounds, so the wheel has audio without any uploads.
local TICK_SOUND = "rbxasset://sounds/snap.mp3"
local REWARD_SOUND = "rbxasset://sounds/electronicpingshort.wav"
local TICK_VOLUME = 0.3
-- The launch crosses dozens of boundaries per second; rate-limiting
-- the ticks keeps the ratchet from machine-gunning the mixer.
local TICK_MINIMUM_GAP = 0.05
local TICK_PITCH_BASE = 0.75
local TICK_PITCH_RISE = 0.7

local WIND_UP_INFO =
	TweenInfo.new(WIND_UP_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local BEND_RECOVER_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SLICE_POP_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)

-- Tier names come from GameConfig; the rank decides how hard the
-- client celebrates. Unknown tiers fall back to the smallest party.
local TIER_RANKS = {
	common = 1,
	uncommon = 2,
	rare = 3,
	epic = 4,
	jackpot = 5,
}

local CONFETTI_COLORS = {
	Color3.fromRGB(255, 154, 162),
	Color3.fromRGB(255, 183, 121),
	Color3.fromRGB(253, 255, 171),
	Color3.fromRGB(158, 240, 155),
	Color3.fromRGB(154, 206, 255),
	Color3.fromRGB(216, 178, 255),
}

-- One bar per screen edge; each gradient runs solid at the edge and
-- clear toward the middle so the flash frames the wheel, never hides
-- it.
local VIGNETTE_SIDES = {
	{ position = UDim2.new(0, 0, 0, 0), size = UDim2.new(1, 0, 0.16, 0), gradientRotation = 90 },
	{
		position = UDim2.new(0, 0, 0.84, 0),
		size = UDim2.new(1, 0, 0.16, 0),
		gradientRotation = 270,
	},
	{ position = UDim2.new(0, 0, 0, 0), size = UDim2.new(0.14, 0, 1, 0), gradientRotation = 0 },
	{
		position = UDim2.new(0.86, 0, 0, 0),
		size = UDim2.new(0.14, 0, 1, 0),
		gradientRotation = 180,
	},
}

local localPlayer = Players.LocalPlayer

local WheelGui = {}

local function rewardColor(reward: { [string]: any }): Color3
	return Color3.fromRGB(reward.color[1], reward.color[2], reward.color[3])
end

--[[
	SoundController.playSfx pins one-shot volume at 0.6, but the
	ratchet ticks fire many times per second and must sit under the
	rest of the mix -- so this builds its own quiet Sound while still
	handing it to the Sfx bus, keeping the settings slider in charge.
]]
local function playTick(parent: Instance, playbackSpeed: number)
	local sfxGroup = SoundService:FindFirstChild("Sfx")
	local sound = Instance.new("Sound")
	sound.SoundId = TICK_SOUND
	sound.Volume = TICK_VOLUME
	sound.PlaybackSpeed = playbackSpeed
	if sfxGroup ~= nil and sfxGroup:IsA("SoundGroup") then
		sound.SoundGroup = sfxGroup
	end
	sound.Parent = parent
	sound:Play()

	-- Snap is short; a quick cleanup stops rapid ticks piling up
	-- dead instances.
	task.delay(1, function()
		sound:Destroy()
	end)
end

-- A negative offset paints the parked look (every other bulb lit);
-- during a spin the lit window walks the ring instead, one step per
-- call, which reads as lights chasing each other.
local function paintBulbs(bulbs: { Frame }, offset: number)
	for bulbIndex, bulb in ipairs(bulbs) do
		local lit = if offset < 0 then bulbIndex % 2 == 0 else (bulbIndex + offset) % 3 == 0
		bulb.BackgroundColor3 = if lit then BULB_LIT_COLOR else BULB_DIM_COLOR
	end
end

--[[
	One wedge of the wheel: a rounded card whose width matches the
	chord of its slice at mid-radius, rotated so its long axis points
	out from the hub. Cards overlap slightly near the hub, where the
	hub cap hides the seams. High tiers dress up so they pop even
	while the wheel is parked.
]]
local function buildSliceCard(disc: Frame, rewardIndex: number, reward: { [string]: any }): Frame
	local sliceCount = #GameConfig.wheel.rewards
	local sliceAngle = 360 / sliceCount
	local angle = math.rad((rewardIndex - 1) * sliceAngle)
	local midRadius = (SLICE_INNER_RADIUS + SLICE_OUTER_RADIUS) / 2
	local cardWidth = math.floor(2 * midRadius * math.sin(math.rad(sliceAngle / 2)))
	local cardLength = SLICE_OUTER_RADIUS - SLICE_INNER_RADIUS

	local card = UiBuilder.create("Frame", {
		Name = "Slice" .. rewardIndex,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, math.sin(angle) * midRadius, 0.5, -math.cos(angle) * midRadius),
		Size = UDim2.new(0, cardWidth, 0, cardLength),
		Rotation = (rewardIndex - 1) * sliceAngle,
		BackgroundColor3 = rewardColor(reward),
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = disc,
	}) :: Frame
	UiBuilder.round(card, 8)

	-- The label reads outward from the hub, the way real carnival
	-- wheels paint their prizes along each wedge.
	local label = UiBuilder.create("TextLabel", {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, cardLength - 8, 0, cardWidth - 8),
		Rotation = -90,
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = reward.label,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
		ZIndex = 3,
		Parent = card,
	}) :: TextLabel
	UiBuilder.create("UITextSizeConstraint", {
		MaxTextSize = 13,
		Parent = label,
	})

	local tierRank = if TIER_RANKS[reward.tier] ~= nil then TIER_RANKS[reward.tier] else 1
	if tierRank >= 4 then
		local stroke = UiBuilder.stroke(card, Color3.fromRGB(255, 255, 255), 2)
		UiBuilder.pulse(stroke)
	end
	if tierRank >= 5 then
		UiBuilder.shineText(label)
	end

	return card
end

--[[
	Assembles the carnival wheel: a static rim of chase bulbs, a
	rotating disc of wedges built from the reward list (however many
	there are), a gold hub cap over the messy center, and a fixed
	pointer at the top that the spin animation bends on each peg.
]]
local function buildWheel(window: Frame): (Frame, Frame, TextLabel, { Frame }, { Frame })
	local wheelArea = UiBuilder.create("Frame", {
		Name = "WheelArea",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.new(0, WHEEL_DIAMETER, 0, WHEEL_DIAMETER),
		BackgroundColor3 = DISC_COLOR,
		BorderSizePixel = 0,
		Parent = window,
	}) :: Frame
	UiBuilder.round(wheelArea, WHEEL_DIAMETER // 2)
	UiBuilder.stroke(wheelArea, GOLD_COLOR, 3)

	-- Rotating this one transparent frame spins every wedge together
	-- while the rim, hub, and pointer stay put.
	local disc = UiBuilder.create("Frame", {
		Name = "Disc",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = wheelArea,
	}) :: Frame

	local slices = {}
	for rewardIndex, reward in ipairs(GameConfig.wheel.rewards) do
		table.insert(slices, buildSliceCard(disc, rewardIndex, reward))
	end

	-- Two bulbs per slice keeps the ring density matched to any
	-- reward count, and the total stays even for the parked
	-- alternating pattern.
	local bulbs = {}
	local bulbCount = #GameConfig.wheel.rewards * 2
	for bulbIndex = 1, bulbCount do
		local angle = math.rad((bulbIndex - 1) * 360 / bulbCount)
		local bulb = UiBuilder.create("Frame", {
			Name = "Bulb" .. bulbIndex,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(
				0.5,
				math.sin(angle) * BULB_RING_RADIUS,
				0.5,
				-math.cos(angle) * BULB_RING_RADIUS
			),
			Size = UDim2.new(0, BULB_DIAMETER, 0, BULB_DIAMETER),
			BackgroundColor3 = BULB_DIM_COLOR,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = wheelArea,
		}) :: Frame
		UiBuilder.round(bulb, BULB_DIAMETER)
		table.insert(bulbs, bulb)
	end
	paintBulbs(bulbs, -1)

	local hubCap = UiBuilder.create("Frame", {
		Name = "HubCap",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, HUB_DIAMETER, 0, HUB_DIAMETER),
		BackgroundColor3 = GOLD_COLOR,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = wheelArea,
	})
	UiBuilder.round(hubCap, HUB_DIAMETER // 2)
	UiBuilder.create("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "\u{1F3A1}",
		TextSize = 26,
		ZIndex = 6,
		Parent = hubCap,
	})

	local arrow = UiBuilder.create("TextLabel", {
		Name = "Pointer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.new(0, 34, 0, 34),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "\u{1F53B}",
		TextSize = 30,
		ZIndex = 7,
		Parent = wheelArea,
	}) :: TextLabel

	return wheelArea, disc, arrow, bulbs, slices
end

--[[
	Steps the disc by hand on Heartbeat instead of one big tween: the
	tick-and-bend callback needs every intermediate rotation, and the
	spin is stitched from phases with different easing curves.
	Yields; call from a spawned task.
]]
local function driveRotation(
	disc: Frame,
	target: number,
	seconds: number,
	ease: (number) -> number,
	onStep: (number) -> ()
)
	local startRotation = disc.Rotation
	local startClock = os.clock()

	while true do
		RunService.Heartbeat:Wait()
		local alpha = math.clamp((os.clock() - startClock) / seconds, 0, 1)
		disc.Rotation = startRotation + (target - startRotation) * ease(alpha)
		onStep(disc.Rotation)
		if alpha >= 1 then
			break
		end
	end
end

-- Ease-out cubic sampled only up to FAST_CURVE_CUT and renormalized,
-- so the phase ends while the wheel still has speed to hand off.
local function fastSpinEase(alpha: number): number
	local sampled = 1 - (1 - alpha * FAST_CURVE_CUT) ^ 3
	return sampled / (1 - (1 - FAST_CURVE_CUT) ^ 3)
end

local function slowMoEase(alpha: number): number
	return 1 - (1 - alpha) ^ 2
end

-- Rays snapping outward plus a shower of spinning confetti squares,
-- centered on the window -- the same recipe as the egg crack, tuned
-- for the wheel.
local function burstConfetti(
	overlay: Frame,
	pieceCount: number,
	rayCount: number,
	accentColor: Color3
)
	for rayIndex = 1, rayCount do
		local ray = UiBuilder.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 4, 0, 30),
			BackgroundColor3 = accentColor,
			BorderSizePixel = 0,
			Rotation = rayIndex * 360 / rayCount,
			ZIndex = 8,
			Parent = overlay,
		})

		TweenService:Create(ray, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
			Size = UDim2.new(0, 3, 0, 260),
			BackgroundTransparency = 1,
		}):Play()
	end

	for pieceIndex = 1, pieceCount do
		local angle = pieceIndex / pieceCount * math.pi * 2
		local distance = 150 + math.random(0, 150)
		local piece = UiBuilder.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 10, 0, 10),
			BackgroundColor3 = CONFETTI_COLORS[pieceIndex % #CONFETTI_COLORS + 1],
			BorderSizePixel = 0,
			ZIndex = 9,
			Parent = overlay,
		})

		TweenService:Create(piece, TweenInfo.new(0.9, Enum.EasingStyle.Quad), {
			Position = UDim2.new(
				0.5,
				math.cos(angle) * distance,
				0.5,
				math.sin(angle) * distance - 40
			),
			Rotation = math.random(180, 540),
			BackgroundTransparency = 1,
		}):Play()
	end
end

local function flashScreen(overlay: Frame, color: Color3)
	local flash = UiBuilder.create("Frame", {
		Name = "Flash",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = overlay,
	})

	TweenService:Create(flash, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
		BackgroundTransparency = 1,
	}):Play()
end

local function flashVignette(overlay: Frame, accentColor: Color3)
	for _, side in ipairs(VIGNETTE_SIDES) do
		local bar = UiBuilder.create("Frame", {
			Name = "Vignette",
			Position = side.position,
			Size = side.size,
			BackgroundColor3 = accentColor,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			ZIndex = 7,
			Parent = overlay,
		})

		UiBuilder.create("UIGradient", {
			Rotation = side.gradientRotation,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = bar,
		})

		TweenService:Create(bar, TweenInfo.new(0.9, Enum.EasingStyle.Quad), {
			BackgroundTransparency = 1,
		}):Play()
	end
end

local function playGoldenRays(overlay: Frame)
	local spinner = UiBuilder.create("Frame", {
		Name = "RaySpinner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = overlay,
	})

	for rayIndex = 1, RAY_COUNT do
		local ray = UiBuilder.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 7, 0, 90),
			BackgroundColor3 = GOLD_COLOR,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Rotation = rayIndex * 360 / RAY_COUNT,
			ZIndex = 6,
			Parent = spinner,
		})

		TweenService:Create(ray, TweenInfo.new(1.3, Enum.EasingStyle.Quad), {
			Size = UDim2.new(0, 5, 0, 1100),
			BackgroundTransparency = 1,
		}):Play()
	end

	-- A slow twist sells "rays of light" instead of a static burst.
	TweenService:Create(spinner, TweenInfo.new(1.3, Enum.EasingStyle.Quad), {
		Rotation = 40,
	}):Play()
end

-- Raw position jitter, not a tween: an impact should look rough for
-- a few frames and then simply stop. Yields; call from a spawned
-- task.
local function shakeWindow(window: Frame)
	local basePosition = window.Position
	for _ = 1, 10 do
		window.Position = basePosition + UDim2.fromOffset(math.random(-6, 6), math.random(-5, 5))
		task.wait(0.035)
	end
	window.Position = basePosition
end

--[[
	The escalating payoff: every tier pops the wheel and pings, then
	each rank stacks more on top -- uncommon adds confetti, rare a
	bigger burst with a gold flash, epic a screen-edge vignette in the
	slice's color, and the jackpot piles on golden rays, a second
	higher ping, and a window shake. Long-running pieces run in their
	own tasks, so callers are never blocked.
]]
local function celebrate(
	screenGui: ScreenGui,
	window: Frame,
	wheelArea: Frame,
	reward: { [string]: any }
)
	local tierRank = if TIER_RANKS[reward.tier] ~= nil then TIER_RANKS[reward.tier] else 1
	local accentColor = rewardColor(reward)

	local wheelScale = wheelArea:FindFirstChildOfClass("UIScale")
	if wheelScale == nil then
		wheelScale = UiBuilder.create("UIScale", { Parent = wheelArea }) :: UIScale
	end
	wheelScale.Scale = 1.08
	TweenService:Create(wheelScale, SLICE_POP_INFO, { Scale = 1 }):Play()

	SoundController.playSfx(window, REWARD_SOUND, 0.85 + tierRank * 0.1)

	if tierRank < 2 then
		return
	end

	-- Confetti and flashes live on their own fullscreen layer above
	-- the window, so nothing here disturbs the window's layout.
	local overlay = UiBuilder.create("Frame", {
		Name = "CelebrationOverlay",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 8,
		Parent = screenGui,
	}) :: Frame
	task.delay(CELEBRATION_SECONDS, function()
		overlay:Destroy()
	end)

	burstConfetti(overlay, 14 + tierRank * 8, if tierRank >= 3 then 10 else 0, accentColor)

	if tierRank >= 3 then
		flashScreen(overlay, GOLD_COLOR)
	end
	if tierRank >= 4 then
		flashVignette(overlay, accentColor)
	end
	if tierRank >= 5 then
		playGoldenRays(overlay)
		task.spawn(shakeWindow, window)
		task.delay(0.25, function()
			SoundController.playSfx(window, REWARD_SOUND, 1.6)
		end)
	end
end

function WheelGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = UiBuilder.create("ScreenGui", {
		Name = "WheelGui",
		ResetOnSpawn = false,
		DisplayOrder = 6,
		Parent = playerGui,
	}) :: ScreenGui

	local window = UiBuilder.create("Frame", {
		Name = "WheelWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 420, 0, 470),
		BackgroundColor3 = PANEL_COLOR,
		BorderSizePixel = 0,
		Visible = false,
		Parent = screenGui,
	}) :: Frame
	UiBuilder.round(window, 16)
	UiBuilder.stroke(window, GOLD_COLOR, 2)

	local closeButton = UiBuilder.create("TextButton", {
		Name = "CloseButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.new(0, 34, 0, 34),
		BackgroundColor3 = Color3.fromRGB(232, 65, 24),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "X",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 18,
		ZIndex = 7,
		Parent = window,
	}) :: TextButton
	UiBuilder.round(closeButton, 8)
	UiBuilder.hoverPop(closeButton)

	closeButton.Activated:Connect(function()
		window.Visible = false
	end)

	local wheelArea, disc, arrow, bulbs, slices = buildWheel(window)

	local statusLabel = UiBuilder.create("TextLabel", {
		Name = "StatusLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 330),
		Size = UDim2.new(1, -32, 0, 24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 16,
		Parent = window,
	}) :: TextLabel

	local spinButton = UiBuilder.create("TextButton", {
		Name = "SpinButton",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 366),
		Size = UDim2.new(1, -32, 0, 52),
		BackgroundColor3 = READY_COLOR,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		Text = "SPIN!",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 20,
		Parent = window,
	}) :: TextButton
	UiBuilder.round(spinButton, 12)
	UiBuilder.hoverPop(spinButton)

	UiBuilder.cartoonizeWindow(window, GOLD_COLOR, "PRIZE WHEEL")

	local spinning = false

	local function isReady(): (boolean, number, number)
		local nextAt = localPlayer:GetAttribute("WheelNextSpinAt")
		local credits = localPlayer:GetAttribute("WheelSpinCredits")
		local nextTime = if typeof(nextAt) == "number" then nextAt else 0
		local creditCount = if typeof(credits) == "number" then credits else 0

		return creditCount > 0 or os.time() >= nextTime, nextTime, creditCount
	end

	local function refresh()
		if spinning then
			return
		end

		local ready, nextTime, creditCount = isReady()
		local product = GameConfig.wheel.spinProduct
		if ready then
			statusLabel.Text = if creditCount > 0
				then string.format("EXTRA SPINS READY: %d", creditCount)
				else "FREE SPIN READY!"
			spinButton.Text = "SPIN!"
			spinButton.BackgroundColor3 = READY_COLOR
		else
			local waitSeconds = math.max(nextTime - os.time(), 0)
			statusLabel.Text = string.format(
				"Next free spin in %dh %02dm %02ds",
				waitSeconds // 3600,
				waitSeconds % 3600 // 60,
				waitSeconds % 60
			)
			spinButton.Text = string.format("SPIN NOW -- R$ %d", product.robuxPrice)
			spinButton.BackgroundColor3 = LOCKED_COLOR
		end
	end

	-- Each bend cancels the previous recover tween, so a fresh peg
	-- hit always starts from full deflection instead of stacking.
	local bendTween: Tween? = nil

	local function bendPointer()
		if bendTween ~= nil then
			bendTween:Cancel()
		end

		-- Kicked against the direction of travel, like a real pointer
		-- flap catching a peg, then springing straight again.
		arrow.Rotation = -POINTER_BEND_DEGREES
		local freshTween = TweenService:Create(arrow, BEND_RECOVER_INFO, { Rotation = 0 })
		bendTween = freshTween
		freshTween:Play()
	end

	--[[
		The full ride: a wind-up pull against the spin, a fast launch
		easing out over a few seconds, then a slow-motion crawl across
		the last couple of slices onto the server's slice. Every slice
		boundary that passes the pointer ticks (pitch rising) and
		bends the pointer. Yields; call from a spawned task.
	]]
	local function animateTo(rewardIndex: number)
		local sliceCount = #GameConfig.wheel.rewards
		local sliceAngle = 360 / sliceCount
		local halfSlice = sliceAngle / 2

		local restRotation = disc.Rotation % 360
		disc.Rotation = restRotation

		-- Positive disc rotation carries slices clockwise, so parking
		-- slice rewardIndex under the top pointer means rotating to
		-- the slice's negative base angle (mod 360), plus a few
		-- showmanship turns.
		local desired = (360 - (rewardIndex - 1) * sliceAngle) % 360
		local target = restRotation + (desired - restRotation) % 360 + EXTRA_TURNS * 360

		local chasing = true
		task.spawn(function()
			local offset = 0
			while chasing do
				offset += 1
				paintBulbs(bulbs, offset)
				task.wait(BULB_CHASE_SECONDS)
			end
			paintBulbs(bulbs, -1)
		end)

		-- The wind-up: a slow pull backward with one soft ratchet
		-- clack, so the launch reads as a release.
		playTick(wheelArea, 0.6)
		local windUp = TweenService:Create(disc, WIND_UP_INFO, {
			Rotation = restRotation - WIND_UP_DEGREES,
		})
		windUp:Play()
		windUp.Completed:Wait()

		local startRotation = disc.Rotation
		local boundariesPassed = math.floor((startRotation + halfSlice) / sliceAngle)
		local lastTickClock = 0

		local function onStep(rotation: number)
			local passed = math.floor((rotation + halfSlice) / sliceAngle)
			if passed <= boundariesPassed then
				return
			end
			boundariesPassed = passed

			local now = os.clock()
			if now - lastTickClock < TICK_MINIMUM_GAP then
				return
			end
			lastTickClock = now

			local progress = (rotation - startRotation) / (target - startRotation)
			playTick(wheelArea, TICK_PITCH_BASE + TICK_PITCH_RISE * progress)
			bendPointer()
		end

		local slowMoStart = target - sliceAngle * SLOW_MO_SLICES
		driveRotation(disc, slowMoStart, FAST_SPIN_SECONDS, fastSpinEase, onStep)
		driveRotation(disc, target, SLOW_MO_SECONDS, slowMoEase, onStep)

		chasing = false
		arrow.Rotation = 0

		-- The winning wedge takes a bow before the celebration.
		local slice = slices[rewardIndex]
		if slice ~= nil then
			local sliceScale = slice:FindFirstChildOfClass("UIScale")
			if sliceScale == nil then
				sliceScale = UiBuilder.create("UIScale", { Parent = slice }) :: UIScale
			end
			sliceScale.Scale = 1.3
			TweenService:Create(sliceScale, SLICE_POP_INFO, { Scale = 1 }):Play()
		end
	end

	spinButton.Activated:Connect(function()
		if spinning then
			return
		end

		local ready = isReady()
		if not ready then
			local product = GameConfig.wheel.spinProduct
			if product.productId ~= 0 then
				MarketplaceService:PromptProductPurchase(localPlayer, product.productId)
			else
				Toast.show("Extra spins unlock once the game is published!")
			end

			return
		end

		spinning = true
		statusLabel.Text = "SPINNING..."
		task.spawn(function()
			local spinWheel = Remotes.get("SpinWheel") :: RemoteFunction

			-- InvokeServer throws if the server errors mid-call.
			local invoked, success, result = pcall(function()
				return spinWheel:InvokeServer()
			end)

			if invoked and success and typeof(result) == "table" then
				-- The server's index is the single source of truth;
				-- an index outside the local list means mismatched
				-- config, so skip the show but still announce.
				local reward = GameConfig.wheel.rewards[result.rewardIndex]
				if reward ~= nil then
					animateTo(result.rewardIndex)
					celebrate(screenGui, window, wheelArea, reward)
				end
				Toast.show("You won " .. tostring(result.label) .. "!")
			else
				Toast.show(
					if invoked and not success
						then tostring(result)
						else "Something went wrong -- try again."
				)
			end

			spinning = false
			refresh()
		end)
	end)

	-- Live countdown while the window is open.
	task.spawn(function()
		while screenGui.Parent ~= nil do
			if window.Visible then
				refresh()
			end
			task.wait(1)
		end
	end)

	for _, attributeName in ipairs({ "WheelNextSpinAt", "WheelSpinCredits" }) do
		localPlayer:GetAttributeChangedSignal(attributeName):Connect(refresh)
	end

	WheelGui.toggle = function()
		if window.Visible then
			window.Visible = false
		else
			refresh()
			UiBuilder.popOpen(window)
		end
	end

	local function watchWheel(wheel: Instance)
		local prompt = wheel:FindFirstChildOfClass("ProximityPrompt")
		if prompt == nil then
			return
		end

		prompt.Triggered:Connect(function(playerWhoTriggered)
			if playerWhoTriggered == localPlayer then
				WheelGui.toggle()
			end
		end)
	end

	for _, wheel in ipairs(CollectionService:GetTagged("SpinWheel")) do
		watchWheel(wheel)
	end
	CollectionService:GetInstanceAddedSignal("SpinWheel"):Connect(watchWheel)
end

-- Replaced at start(); declared so ShopGui can wire its side button.
WheelGui.toggle = function() end

return WheelGui
