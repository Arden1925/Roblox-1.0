--[[
	The always-on HUD: the tide clock banner at top-center (phase name,
	countdown bar, next-phase hint, and the current zone underneath),
	plus the two currency chips at top-left. Purely presentational --
	every number shown here comes from server-owned attributes or the
	TideChanged broadcast, never from client math.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent
local TidetownUi = require(Client.TidetownUi)

local TidetownShared = ReplicatedStorage:WaitForChild("TidetownShared")
local TideLayout = require(TidetownShared.TideLayout)
local TidePhase = require(TidetownShared.TidePhase)
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

local PHASE_LABELS: { [string]: string } = {
	[TidePhase.Low] = "🏖️ Low Tide",
	[TidePhase.Rising] = "🌊 Tide Rising!",
	[TidePhase.High] = "🌊 High Tide",
	[TidePhase.Falling] = "🌤️ Tide Falling",
}

local PHASE_HINTS: { [string]: string } = {
	[TidePhase.Low] = "Next: the sea comes back",
	[TidePhase.Rising] = "Next: high-tide surfing",
	[TidePhase.High] = "Next: the water recedes",
	[TidePhase.Falling] = "Next: tide pools open up",
}

local PHASE_COLORS: { [string]: Color3 } = {
	[TidePhase.Low] = Color3.fromRGB(214, 168, 96),
	[TidePhase.Rising] = Color3.fromRGB(0, 148, 176),
	[TidePhase.High] = Color3.fromRGB(0, 104, 148),
	[TidePhase.Falling] = Color3.fromRGB(86, 176, 188),
}

local OUTLINE_NAVY = Color3.fromRGB(31, 41, 74)
local SHELL_CHIP_COLOR = Color3.fromRGB(255, 167, 64)
local STORMGLASS_CHIP_COLOR = Color3.fromRGB(126, 87, 194)
local BANNER_COLOR_INFO = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Reverses, so one tween is both the bounce out and the settle back.
local BOUNCE_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
local ZONE_POLL_SECONDS = 0.5
local COUNTDOWN_TICK_SECONDS = 0.2

local localPlayer = Players.LocalPlayer

local function phaseDurationSeconds(phase: string): number
	local tide = TidetownConfig.tide
	if phase == TidePhase.Rising then
		return tide.risingSeconds
	elseif phase == TidePhase.High then
		return tide.highSeconds
	elseif phase == TidePhase.Falling then
		return tide.fallingSeconds
	end

	return tide.lowSeconds
end

local function formatClock(seconds: number): string
	local wholeSeconds = math.max(math.floor(seconds + 0.5), 0)

	return string.format("%d:%02d", math.floor(wholeSeconds / 60), wholeSeconds % 60)
end

local function buildCurrencyChip(
	parent: Instance,
	order: number,
	name: string,
	icon: string,
	color: Color3
): (TextLabel, UIScale)
	local chip = TidetownUi.create("Frame", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(0, 150, 0, 40),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = parent,
	}) :: Frame
	TidetownUi.round(chip, 20)
	TidetownUi.stroke(chip, OUTLINE_NAVY, 3)
	TidetownUi.gloss(chip)

	TidetownUi.create("TextLabel", {
		Name = "Icon",
		Position = UDim2.new(0, 10, 0, 0),
		Size = UDim2.new(0, 26, 1, 0),
		BackgroundTransparency = 1,
		Text = icon,
		TextSize = 20,
		Parent = chip,
	})

	local valueLabel = TidetownUi.create("TextLabel", {
		Name = "Value",
		Position = UDim2.new(0, 42, 0, 0),
		Size = UDim2.new(1, -50, 1, 0),
		BackgroundTransparency = 1,
		Text = "0",
		TextSize = 20,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = chip,
	}) :: TextLabel

	local scale = TidetownUi.create("UIScale", { Parent = chip }) :: UIScale
	TidetownUi.cartoonify(chip)

	return valueLabel, scale
end

local ODOMETER_RATE = 8
local GOLD_FLASH_COLOR = Color3.fromRGB(255, 199, 92)

--[[
	Currency text never snaps: the displayed number rolls toward the
	real value like an odometer, and gains bounce the chip and flash
	the digits gold. Spending rolls down quietly -- losses should never
	celebrate.
]]
local function wireCurrencyChip(attributeName: string, valueLabel: TextLabel, scale: UIScale)
	local shown = 0
	local target = 0

	local initial = localPlayer:GetAttribute(attributeName)
	if typeof(initial) == "number" then
		shown = initial
		target = initial
		valueLabel.Text = tostring(math.floor(initial))
	end

	localPlayer:GetAttributeChangedSignal(attributeName):Connect(function()
		local value = localPlayer:GetAttribute(attributeName)
		if typeof(value) ~= "number" then
			return
		end

		if value > target then
			TweenService:Create(scale, BOUNCE_INFO, { Scale = 1.2 }):Play()
			TweenService:Create(valueLabel, BOUNCE_INFO, { TextColor3 = GOLD_FLASH_COLOR }):Play()
		end
		target = value
	end)

	RunService.Heartbeat:Connect(function(deltaTime)
		if shown == target then
			return
		end

		shown += (target - shown) * math.min(1, deltaTime * ODOMETER_RATE)
		if math.abs(target - shown) < 0.5 then
			shown = target
		end
		valueLabel.Text = tostring(math.floor(shown))
	end)
end

local HudGui = {}

function HudGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = TidetownUi.create("ScreenGui", {
		Name = "TidetownHud",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		Parent = playerGui,
	}) :: ScreenGui

	local banner = TidetownUi.create("Frame", {
		Name = "TideBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0, 340, 0, 74),
		BackgroundColor3 = PHASE_COLORS[TidePhase.Low],
		BorderSizePixel = 0,
		Parent = screenGui,
	}) :: Frame
	TidetownUi.round(banner, 14)
	TidetownUi.stroke(banner, OUTLINE_NAVY, 3)

	local phaseLabel = TidetownUi.create("TextLabel", {
		Name = "PhaseLabel",
		Position = UDim2.new(0, 12, 0, 4),
		Size = UDim2.new(1, -88, 0, 28),
		BackgroundTransparency = 1,
		Text = PHASE_LABELS[TidePhase.Low],
		TextSize = 22,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = banner,
	}) :: TextLabel

	local countdownLabel = TidetownUi.create("TextLabel", {
		Name = "CountdownLabel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 4),
		Size = UDim2.new(0, 68, 0, 28),
		BackgroundTransparency = 1,
		Text = "0:00",
		TextSize = 22,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = banner,
	}) :: TextLabel

	local hintLabel = TidetownUi.create("TextLabel", {
		Name = "HintLabel",
		Position = UDim2.new(0, 12, 0, 32),
		Size = UDim2.new(1, -24, 0, 16),
		BackgroundTransparency = 1,
		Text = PHASE_HINTS[TidePhase.Low],
		TextSize = 14,
		TextColor3 = Color3.fromRGB(235, 245, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = banner,
	}) :: TextLabel

	local barTrack = TidetownUi.create("Frame", {
		Name = "CountdownTrack",
		Position = UDim2.new(0, 12, 1, -16),
		Size = UDim2.new(1, -24, 0, 8),
		BackgroundColor3 = OUTLINE_NAVY,
		BorderSizePixel = 0,
		Parent = banner,
	}) :: Frame
	TidetownUi.round(barTrack, 4)

	local barFill = TidetownUi.create("Frame", {
		Name = "CountdownFill",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Parent = barTrack,
	}) :: Frame
	TidetownUi.round(barFill, 4)

	local zoneLabel = TidetownUi.create("TextLabel", {
		Name = "ZoneLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 6),
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 15,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Parent = banner,
	}) :: TextLabel

	TidetownUi.cartoonify(banner)

	local chipColumn = TidetownUi.create("Frame", {
		Name = "CurrencyColumn",
		Position = UDim2.new(0, 12, 0, 12),
		Size = UDim2.new(0, 150, 0, 92),
		BackgroundTransparency = 1,
		Parent = screenGui,
	}) :: Frame

	TidetownUi.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = chipColumn,
	})

	local shellsLabel, shellsScale =
		buildCurrencyChip(chipColumn, 1, "ShellChip", "🐚", SHELL_CHIP_COLOR)
	wireCurrencyChip("Shells", shellsLabel, shellsScale)

	local stormglassLabel, stormglassScale =
		buildCurrencyChip(chipColumn, 2, "StormglassChip", "⚡", STORMGLASS_CHIP_COLOR)
	wireCurrencyChip("Stormglass", stormglassLabel, stormglassScale)

	local currentEndsAt = Workspace:GetServerTimeNow()
	local barTween: Tween? = nil

	local function applyPhase(phase: string, endsAt: number, seconds: number)
		currentEndsAt = endsAt
		phaseLabel.Text = PHASE_LABELS[phase] or phase
		hintLabel.Text = PHASE_HINTS[phase] or ""

		local color = PHASE_COLORS[phase]
		if color ~= nil then
			TweenService:Create(banner, BANNER_COLOR_INFO, { BackgroundColor3 = color }):Play()
		end

		-- The bar restarts at the true remaining fraction, so a late
		-- joiner mid-phase sees a partially drained bar, not a full one.
		local remaining = math.max(endsAt - Workspace:GetServerTimeNow(), 0)
		local fraction = if seconds > 0 then math.clamp(remaining / seconds, 0, 1) else 0

		if barTween ~= nil then
			barTween:Cancel()
		end
		barFill.Size = UDim2.new(fraction, 0, 1, 0)
		local tween = TweenService:Create(
			barFill,
			TweenInfo.new(remaining, Enum.EasingStyle.Linear),
			{ Size = UDim2.new(0, 0, 1, 0) }
		)
		barTween = tween
		tween:Play()
	end

	-- Late join: the folder attributes already describe the phase in
	-- flight, so the banner is right before the first broadcast lands.
	local tideFolder = Workspace:WaitForChild("Tidetown")
	local initialPhase = tideFolder:GetAttribute("Phase")
	local initialEndsAt = tideFolder:GetAttribute("PhaseEndsAt")
	if typeof(initialPhase) == "string" and typeof(initialEndsAt) == "number" then
		applyPhase(initialPhase, initialEndsAt, phaseDurationSeconds(initialPhase))
	end

	local tideChanged = TidetownRemotes.get("TideChanged") :: RemoteEvent
	tideChanged.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		if
			typeof(payload.phase) == "string"
			and typeof(payload.endsAt) == "number"
			and typeof(payload.seconds) == "number"
		then
			applyPhase(payload.phase, payload.endsAt, payload.seconds)
		end
	end)

	task.spawn(function()
		while true do
			countdownLabel.Text = formatClock(currentEndsAt - Workspace:GetServerTimeNow())
			task.wait(COUNTDOWN_TICK_SECONDS)
		end
	end)

	task.spawn(function()
		while true do
			local zoneText = ""
			local character = localPlayer.Character
			local root: Instance? = nil
			if character ~= nil then
				root = character:FindFirstChild("HumanoidRootPart")
			end
			if root ~= nil and root:IsA("BasePart") then
				local zoneKey = TideLayout.zoneAt(root.Position)
				if zoneKey ~= nil then
					local zoneInfo = TideLayout.zoneInfo(zoneKey)
					zoneText = if zoneInfo ~= nil then zoneInfo.name else zoneKey
				end
			end
			zoneLabel.Text = zoneText
			task.wait(ZONE_POLL_SECONDS)
		end
	end)
end

return HudGui
