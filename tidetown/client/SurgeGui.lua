--[[
	The high-tide surge HUD: a wave banner under the tide clock, a slim
	barrier health bar that shakes on hits, the big bottom-right DEFLECT
	button with a conic cooldown radial and a gold Sparker-ready glow,
	and the end-of-surge results card. Everything here is a view over
	SurgeEvent broadcasts -- the server runs the fight and rate-limits
	deflects; the client cooldown only mirrors it to stop mashing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Client = script.Parent
local TidetownUi = require(Client.TidetownUi)

local TidetownShared = ReplicatedStorage:WaitForChild("TidetownShared")
local TidePhase = require(TidetownShared.TidePhase)
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

local OUTLINE_NAVY = Color3.fromRGB(31, 41, 74)
local BANNER_COLOR = Color3.fromRGB(0, 104, 148)
local DEFLECT_COLOR = Color3.fromRGB(0, 148, 176)
local SPARK_GOLD = Color3.fromRGB(255, 202, 58)
local BAR_HEALTHY_COLOR = Color3.fromRGB(87, 199, 255)
local BAR_WORRIED_COLOR = Color3.fromRGB(255, 179, 0)
local BAR_CRITICAL_COLOR = Color3.fromRGB(235, 69, 44)
local RESULTS_WIN_COLOR = Color3.fromRGB(46, 125, 50)
local RESULTS_HOLD_COLOR = Color3.fromRGB(69, 90, 100)

local BANNER_HOLD_SECONDS = 2
local RESULTS_HOLD_SECONDS = 6
local COOLDOWN_TICK_SECONDS = 0.03
-- The charm can never legally reduce the cooldown this far; the floor
-- only guards the radial math against a bad config edit.
local COOLDOWN_FLOOR_SECONDS = 0.25
local BAR_TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SHAKE_STEP_INFO = TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local localPlayer = Players.LocalPlayer

-- The charm's per-level cooldown cut lives in the shop upgrade table;
-- resolved once so every press does not rescan the list.
local charmCutSeconds = 0
for _, upgrade in ipairs(TidetownConfig.shop.upgrades) do
	if upgrade.key == "deflectCharm" and typeof(upgrade.cooldownCutSeconds) == "number" then
		charmCutSeconds = upgrade.cooldownCutSeconds
	end
end

local SurgeGui = {}

--[[
	Builds the conic cooldown overlay without any image assets: each
	half of the circle owns a full-size dark disc clipped to that half,
	and rotating a hard-edged transparency gradient sweeps the visible
	part of the disc like a clock hand. The clip frames stay axis-
	aligned on purpose -- rotated frames escape ClipsDescendants, so
	only the gradients are allowed to turn. Returns a setter taking the
	covered fraction of the circle (1 = full pie, 0 = clear).
]]
local function buildCooldownRadial(button: GuiObject): (number) -> ()
	local overlay = TidetownUi.create("Frame", {
		Name = "CooldownRadial",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 6,
		Parent = button,
	}) :: Frame

	local function buildHalf(name: string, clipX: number, discX: number): UIGradient
		local clip = TidetownUi.create("Frame", {
			Name = name,
			Position = UDim2.new(clipX, 0, 0, 0),
			Size = UDim2.new(0.5, 0, 1, 0),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 6,
			Parent = overlay,
		}) :: Frame

		local disc = TidetownUi.create("Frame", {
			Name = "Disc",
			Position = UDim2.new(discX, 0, 0, 0),
			Size = UDim2.new(2, 0, 1, 0),
			BackgroundColor3 = OUTLINE_NAVY,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = clip,
		}) :: Frame
		TidetownUi.create("UICorner", {
			CornerRadius = UDim.new(1, 0),
			Parent = disc,
		})

		local gradient = TidetownUi.create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.499, 0),
				NumberSequenceKeypoint.new(0.5, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = disc,
		}) :: UIGradient

		return gradient
	end

	local rightGradient = buildHalf("RightHalf", 0.5, -1)
	local leftGradient = buildHalf("LeftHalf", 0, 0)
	rightGradient.Rotation = 0
	leftGradient.Rotation = 180

	return function(fraction: number)
		local angle = math.clamp(fraction, 0, 1) * 360
		overlay.Visible = angle > 1
		rightGradient.Rotation = math.clamp(angle, 0, 180)
		leftGradient.Rotation = math.clamp(angle, 180, 360)
	end
end

function SurgeGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = TidetownUi.create("ScreenGui", {
		Name = "TidetownSurge",
		ResetOnSpawn = false,
		DisplayOrder = 20,
		Parent = playerGui,
	}) :: ScreenGui

	-- Wave banner, sitting just under the HUD's tide clock banner.
	local banner = TidetownUi.create("Frame", {
		Name = "WaveBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 112),
		Size = UDim2.new(0, 280, 0, 44),
		BackgroundColor3 = BANNER_COLOR,
		BorderSizePixel = 0,
		Visible = false,
		Parent = screenGui,
	}) :: Frame
	TidetownUi.round(banner, 12)
	TidetownUi.stroke(banner, OUTLINE_NAVY, 3)

	local bannerLabel = TidetownUi.create("TextLabel", {
		Name = "BannerLabel",
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.new(0, 8, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 22,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Parent = banner,
	}) :: TextLabel
	TidetownUi.cartoonify(banner)

	-- Slim barrier bar, attached below the wave banner slot.
	local barFrame = TidetownUi.create("Frame", {
		Name = "BarrierBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 162),
		Size = UDim2.new(0, 280, 0, 14),
		BackgroundColor3 = OUTLINE_NAVY,
		BorderSizePixel = 0,
		Visible = false,
		Parent = screenGui,
	}) :: Frame
	TidetownUi.round(barFrame, 7)
	TidetownUi.stroke(barFrame, OUTLINE_NAVY, 2)
	local barBasePosition = barFrame.Position

	local barFill = TidetownUi.create("Frame", {
		Name = "BarrierFill",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = BAR_HEALTHY_COLOR,
		BorderSizePixel = 0,
		Parent = barFrame,
	}) :: Frame
	TidetownUi.round(barFill, 7)

	-- Deflect control, bottom-right corner (the Dismount button sits
	-- above this region -- see the client layout map).
	local deflectContainer = TidetownUi.create("Frame", {
		Name = "DeflectContainer",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -20),
		Size = UDim2.new(0, 120, 0, 146),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screenGui,
	}) :: Frame

	local sparkLabel = TidetownUi.create("TextLabel", {
		Name = "SparkLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = "SPARK!",
		TextSize = 18,
		TextColor3 = SPARK_GOLD,
		Visible = false,
		Parent = deflectContainer,
	}) :: TextLabel

	local deflectButton = TidetownUi.create("TextButton", {
		Name = "DeflectButton",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 22),
		Size = UDim2.new(0, 100, 0, 100),
		BackgroundColor3 = DEFLECT_COLOR,
		BorderSizePixel = 0,
		Text = "🌀",
		TextSize = 44,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Parent = deflectContainer,
	}) :: TextButton
	TidetownUi.create("UICorner", {
		CornerRadius = UDim.new(1, 0),
		Parent = deflectButton,
	})
	TidetownUi.stroke(deflectButton, OUTLINE_NAVY, 3)
	TidetownUi.gloss(deflectButton)
	TidetownUi.hoverPop(deflectButton)

	-- A second stroke carries the Sparker glow so toggling it never
	-- fights the base outline or the pulse tween.
	local glowStroke = TidetownUi.stroke(deflectButton, SPARK_GOLD, 4)
	glowStroke.Enabled = false
	TidetownUi.pulse(glowStroke)

	TidetownUi.create("TextLabel", {
		Name = "DeflectCaption",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = "DEFLECT",
		TextSize = 16,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Parent = deflectContainer,
	})

	local setCooldownCovered = buildCooldownRadial(deflectButton)
	TidetownUi.cartoonify(deflectContainer)

	-- Results card, shown once per surge when the server closes it out.
	local resultsCard = TidetownUi.create("Frame", {
		Name = "ResultsCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.35, 0),
		Size = UDim2.new(0, 340, 0, 120),
		BackgroundColor3 = RESULTS_WIN_COLOR,
		BorderSizePixel = 0,
		Visible = false,
		Parent = screenGui,
	}) :: Frame
	TidetownUi.round(resultsCard, 16)
	TidetownUi.stroke(resultsCard, OUTLINE_NAVY, 3.5)
	TidetownUi.gloss(resultsCard)

	local resultsTitle = TidetownUi.create("TextLabel", {
		Name = "ResultsTitle",
		Position = UDim2.new(0, 12, 0, 16),
		Size = UDim2.new(1, -24, 0, 40),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 28,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Parent = resultsCard,
	}) :: TextLabel

	local resultsDetail = TidetownUi.create("TextLabel", {
		Name = "ResultsDetail",
		Position = UDim2.new(0, 12, 0, 62),
		Size = UDim2.new(1, -24, 0, 40),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 20,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextWrapped = true,
		Parent = resultsCard,
	}) :: TextLabel
	TidetownUi.cartoonify(resultsCard)

	local deflectCharmLevel = 0
	local cooldownEndsAt = 0
	local cooldownToken = 0
	local bannerToken = 0
	local resultsToken = 0
	local shakeToken = 0

	local function setSparker(ready: boolean)
		glowStroke.Enabled = ready
		sparkLabel.Visible = ready
	end

	local function showBanner(text: string)
		bannerToken += 1
		local token = bannerToken

		bannerLabel.Text = text
		TidetownUi.popOpen(banner)

		task.delay(BANNER_HOLD_SECONDS, function()
			if token == bannerToken then
				banner.Visible = false
			end
		end)
	end

	local function cooldownSeconds(): number
		local base = TidetownConfig.surge.deflect.cooldownSeconds
		return math.max(base - deflectCharmLevel * charmCutSeconds, COOLDOWN_FLOOR_SECONDS)
	end

	local function beginCooldown(seconds: number)
		cooldownToken += 1
		local token = cooldownToken
		cooldownEndsAt = os.clock() + seconds

		task.spawn(function()
			while token == cooldownToken do
				local remaining = cooldownEndsAt - os.clock()
				if remaining <= 0 then
					break
				end

				setCooldownCovered(remaining / seconds)
				task.wait(COOLDOWN_TICK_SECONDS)
			end

			if token == cooldownToken then
				setCooldownCovered(0)
			end
		end)
	end

	local function shakeBar()
		shakeToken += 1
		local token = shakeToken

		task.spawn(function()
			for _, offset in ipairs({ -5, 4, -2, 0 }) do
				if token ~= shakeToken then
					return
				end

				local step = TweenService:Create(barFrame, SHAKE_STEP_INFO, {
					Position = barBasePosition + UDim2.fromOffset(offset, 0),
				})
				step:Play()
				step.Completed:Wait()
			end
		end)
	end

	local function showResults(cleared: boolean, stormglassTotal: number, salvageShells: number)
		resultsToken += 1
		local token = resultsToken

		if cleared then
			resultsCard.BackgroundColor3 = RESULTS_WIN_COLOR
			resultsTitle.Text = "SURGE CLEARED!"
			resultsDetail.Text = string.format("+%d ⚡ Stormglass", stormglassTotal)
		else
			resultsCard.BackgroundColor3 = RESULTS_HOLD_COLOR
			resultsTitle.Text = "The reef holds..."
			resultsDetail.Text = string.format("Salvage washed ashore: +%d 🐚", salvageShells)
		end

		TidetownUi.popOpen(resultsCard)

		task.delay(RESULTS_HOLD_SECONDS, function()
			if token == resultsToken then
				resultsCard.Visible = false
			end
		end)
	end

	local function hideAll()
		bannerToken += 1
		resultsToken += 1
		cooldownToken += 1
		banner.Visible = false
		barFrame.Visible = false
		deflectContainer.Visible = false
		resultsCard.Visible = false
		setSparker(false)
		setCooldownCovered(0)
	end

	local deflectRemote = TidetownRemotes.get("DeflectTap") :: RemoteEvent

	deflectButton.Activated:Connect(function()
		-- Client-side mirror of the server rate limit; the server still
		-- judges every tap by its own clock.
		if os.clock() < cooldownEndsAt then
			return
		end

		-- The glow clears optimistically: this same tap is the Sparker
		-- trigger when one is charged, and the server decides which.
		setSparker(false)
		deflectRemote:FireServer()
		beginCooldown(cooldownSeconds())
	end)

	local surgeRemote = TidetownRemotes.get("SurgeEvent") :: RemoteEvent
	surgeRemote.OnClientEvent:Connect(function(kind, payload)
		if typeof(kind) ~= "string" or typeof(payload) ~= "table" then
			return
		end

		if kind == "waveStarted" then
			if typeof(payload.wave) == "number" and typeof(payload.total) == "number" then
				showBanner(string.format("WAVE %d / %d", payload.wave, payload.total))
				deflectContainer.Visible = true
			end
		elseif kind == "waveCleared" then
			if typeof(payload.wave) == "number" and typeof(payload.stormglass) == "number" then
				showBanner(
					string.format("Wave %d cleared! +%d ⚡", payload.wave, payload.stormglass)
				)
			end
		elseif kind == "barrierHit" then
			if
				typeof(payload.health) == "number"
				and typeof(payload.maxHealth) == "number"
				and payload.maxHealth > 0
			then
				local fraction = math.clamp(payload.health / payload.maxHealth, 0, 1)
				barFrame.Visible = true
				barFill.BackgroundColor3 = if fraction > 0.5
					then BAR_HEALTHY_COLOR
					elseif fraction > 0.25 then BAR_WORRIED_COLOR
					else BAR_CRITICAL_COLOR
				TweenService:Create(barFill, BAR_TWEEN_INFO, {
					Size = UDim2.new(fraction, 0, 1, 0),
				}):Play()
				shakeBar()
			end
		elseif kind == "sparkerReady" then
			setSparker(true)
		elseif kind == "surgeEnded" then
			local stormglassTotal = if typeof(payload.stormglassTotal) == "number"
				then payload.stormglassTotal
				else 0
			local salvageShells = if typeof(payload.salvageShells) == "number"
				then payload.salvageShells
				else 0
			barFrame.Visible = false
			deflectContainer.Visible = false
			setSparker(false)
			showResults(payload.cleared == true, stormglassTotal, salvageShells)
		end
	end)

	-- The whole surge kit belongs to High tide only; any other phase
	-- sweeps every piece away, including a results card mid-display.
	local tideChanged = TidetownRemotes.get("TideChanged") :: RemoteEvent
	tideChanged.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" or typeof(payload.phase) ~= "string" then
			return
		end

		if payload.phase ~= TidePhase.High then
			hideAll()
		end
	end)

	-- The deflect charm shortens the cooldown; the level rides the shop
	-- state sync so the radial always matches what the server enforces.
	local syncRemote = TidetownRemotes.get("SyncState") :: RemoteEvent
	-- The join-burst state push can fire before this listener exists
	-- and queued events drain only into the first connection, so ask
	-- the server to resend our slices. task.defer runs after the
	-- Connect below, so the reply always finds the handler.
	task.defer(function()
		local requestSync = TidetownRemotes.get("RequestSync") :: RemoteEvent
		requestSync:FireServer("shop")
	end)
	syncRemote.OnClientEvent:Connect(function(kind, payload)
		if kind ~= "shop" or typeof(payload) ~= "table" then
			return
		end

		if typeof(payload.upgrades) == "table" then
			local level = payload.upgrades.deflectCharm
			if typeof(level) == "number" then
				deflectCharmLevel = level
			end
		end
	end)
end

return SurgeGui
