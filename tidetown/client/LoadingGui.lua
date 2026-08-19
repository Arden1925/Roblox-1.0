--[[
	The full-screen loading cover: a deep teal wash, the TIDETOWN
	title, an animated wave bar, and rotating pro tips from the config.
	Shown the moment the client boots and faded away when the server
	flips the player's TidetownReady attribute. A failsafe timer fades
	it anyway, because an opaque cover that can never leave is worse
	than watching the map stream in.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Client = script.Parent
local TidetownUi = require(Client.TidetownUi)

local TidetownShared = ReplicatedStorage:WaitForChild("TidetownShared")
local TidetownConfig = require(TidetownShared.TidetownConfig)

local READY_ATTRIBUTE = "TidetownReady"
local FAILSAFE_SECONDS = 20
local TIP_SWAP_SECONDS = 3.5
local FADE_SECONDS = 0.7

local COVER_TOP_COLOR = Color3.fromRGB(6, 66, 84)
local COVER_BOTTOM_COLOR = Color3.fromRGB(3, 36, 48)
local ACCENT_TEAL = Color3.fromRGB(72, 219, 209)
local TRACK_COLOR = Color3.fromRGB(10, 48, 62)

local FADE_INFO = TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local WAVE_INFO = TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local WAVE_TRACK_WIDTH = 260
local WAVE_BAND_WIDTH = 88

local localPlayer = Players.LocalPlayer

local LoadingGui = {}

-- Everything visible fades in one sweep: backgrounds, text, and the
-- sticker outlines cartoonify added.
local function fadeDescendantsOut(screenGui: ScreenGui)
	for _, descendant in ipairs(screenGui:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			TweenService:Create(descendant, FADE_INFO, {
				TextTransparency = 1,
				BackgroundTransparency = 1,
			}):Play()
		elseif descendant:IsA("Frame") then
			TweenService:Create(descendant, FADE_INFO, { BackgroundTransparency = 1 }):Play()
		elseif descendant:IsA("UIStroke") then
			TweenService:Create(descendant, FADE_INFO, { Transparency = 1 }):Play()
		end
	end
end

local function buildCover(playerGui: Instance): (ScreenGui, TextLabel)
	local screenGui = TidetownUi.create("ScreenGui", {
		Name = "TidetownLoading",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
		Parent = playerGui,
	}) :: ScreenGui

	-- The gradient multiplies the background color, so the cover stays
	-- white underneath and the teal lives entirely in the gradient.
	local cover = TidetownUi.create("Frame", {
		Name = "Cover",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Parent = screenGui,
	}) :: Frame
	TidetownUi.gradient(cover, COVER_TOP_COLOR, COVER_BOTTOM_COLOR)

	TidetownUi.create("TextLabel", {
		Name = "TitleLabel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.36, 0),
		Size = UDim2.new(1, 0, 0, 84),
		BackgroundTransparency = 1,
		Text = "TIDETOWN",
		TextSize = 72,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Parent = cover,
	})

	TidetownUi.create("TextLabel", {
		Name = "SubtitleLabel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.36, 52),
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Text = "Hold tight -- the tide is coming in",
		TextSize = 19,
		TextColor3 = ACCENT_TEAL,
		Parent = cover,
	})

	local waveTrack = TidetownUi.create("Frame", {
		Name = "WaveTrack",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.56, 0),
		Size = UDim2.new(0, WAVE_TRACK_WIDTH, 0, 16),
		BackgroundColor3 = TRACK_COLOR,
		BorderSizePixel = 0,
		Parent = cover,
	}) :: Frame
	TidetownUi.round(waveTrack, 8)

	local waveBand = TidetownUi.create("Frame", {
		Name = "WaveBand",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, WAVE_BAND_WIDTH, 0, 12),
		BackgroundColor3 = ACCENT_TEAL,
		BorderSizePixel = 0,
		Parent = waveTrack,
	}) :: Frame
	TidetownUi.round(waveBand, 6)

	TidetownUi.create("TextLabel", {
		Name = "WaveEmoji",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -2),
		Size = UDim2.new(0, 32, 0, 22),
		BackgroundTransparency = 1,
		Text = "🌊",
		TextSize = 18,
		Parent = waveBand,
	})

	-- The little surf sweeps back and forth forever; the tween dies
	-- with the gui when the cover is destroyed.
	TweenService:Create(waveBand, WAVE_INFO, {
		Position = UDim2.new(1, -WAVE_BAND_WIDTH, 0.5, 0),
	}):Play()

	local tipLabel = TidetownUi.create("TextLabel", {
		Name = "TipLabel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.68, 0),
		Size = UDim2.new(0.7, 0, 0, 44),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 17,
		TextColor3 = Color3.fromRGB(235, 245, 255),
		TextWrapped = true,
		Parent = cover,
	}) :: TextLabel

	TidetownUi.cartoonify(cover)

	return screenGui, tipLabel
end

--[[
	Builds the cover immediately, then watches for the ready flag. The
	tip loop doubles as the module's lifetime: it stops as soon as the
	cover starts fading or is destroyed.
]]
function LoadingGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local screenGui, tipLabel = buildCover(playerGui)

	local fading = false

	local function fadeOut()
		if fading then
			return
		end
		fading = true

		fadeDescendantsOut(screenGui)
		task.delay(FADE_SECONDS + 0.1, function()
			screenGui:Destroy()
		end)
	end

	local function checkReady()
		if localPlayer:GetAttribute(READY_ATTRIBUTE) == true then
			fadeOut()
		end
	end

	-- The signal plus an initial check covers both orders: the server
	-- may flip the attribute before or after this module starts.
	localPlayer:GetAttributeChangedSignal(READY_ATTRIBUTE):Connect(checkReady)
	checkReady()

	task.delay(FAILSAFE_SECONDS, fadeOut)

	-- Random tip, but never the same one twice in a row, so a long
	-- load keeps teaching something new.
	local tips = TidetownConfig.proTips
	local lastIndex = 0
	while not fading and screenGui.Parent ~= nil do
		local index = math.random(#tips)
		if #tips > 1 and index == lastIndex then
			index = index % #tips + 1
		end
		lastIndex = index
		tipLabel.Text = "Pro tip: " .. tips[index]
		task.wait(TIP_SWAP_SECONDS)
	end
end

return LoadingGui
