--[[
	The settings window: music and effects volume on the shared sound
	buses, plus a reset-character escape hatch for stuck players. Opens
	from its side button; more settings slot in as sections later.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent
local SoundController = require(Client.SoundController)
local Toast = require(Client.Toast)
local UiBuilder = require(Client.UiBuilder)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local PANEL_COLOR = Color3.fromRGB(24, 30, 38)
local ACCENT_COLOR = Color3.fromRGB(99, 110, 114)
local MUSIC_COLOR = Color3.fromRGB(0, 206, 201)
local SFX_COLOR = Color3.fromRGB(255, 159, 67)
local RESET_COLOR = Color3.fromRGB(235, 69, 44)

local TEST_SOUND = "rbxasset://sounds/snap.mp3"
-- The slider fires on every mouse move; one test click per beat is
-- plenty to judge the volume.
local TEST_THROTTLE_SECONDS = 0.3

local localPlayer = Players.LocalPlayer

local SettingsGui = {}

local function buildVolumeSection(
	window: Frame,
	offsetY: number,
	titleFormat: string,
	accent: Color3,
	initial: number,
	onChanged: (number) -> ()
): TextLabel
	local title = UiBuilder.create("TextLabel", {
		Name = "SectionTitle",
		Position = UDim2.new(0, 24, 0, offsetY),
		Size = UDim2.new(1, -48, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = string.format(titleFormat, math.floor(initial * 100)),
		TextColor3 = accent,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window,
	}) :: TextLabel

	local holder = UiBuilder.create("Frame", {
		Name = "SliderHolder",
		Position = UDim2.new(0, 24, 0, offsetY + 26),
		Size = UDim2.new(1, -48, 0, 22),
		BackgroundTransparency = 1,
		Parent = window,
	})

	UiBuilder.slider(holder, 0, 1, initial, accent, function(value)
		title.Text = string.format(titleFormat, math.floor(value * 100))
		onChanged(value)
	end)

	return title
end

function SettingsGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = UiBuilder.create("ScreenGui", {
		Name = "SettingsGui",
		ResetOnSpawn = false,
		DisplayOrder = 7,
		Parent = playerGui,
	})

	local window = UiBuilder.create("Frame", {
		Name = "SettingsWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 400, 0, 380),
		BackgroundColor3 = PANEL_COLOR,
		BorderSizePixel = 0,
		Visible = false,
		Parent = screenGui,
	}) :: Frame
	UiBuilder.round(window, 16)
	UiBuilder.stroke(window, ACCENT_COLOR, 2)

	local closeButton = UiBuilder.create("TextButton", {
		Name = "CloseButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.new(0, 34, 0, 34),
		BackgroundColor3 = RESET_COLOR,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "X",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 18,
		ZIndex = 2,
		Parent = window,
	}) :: TextButton
	UiBuilder.round(closeButton, 8)
	UiBuilder.hoverPop(closeButton)

	closeButton.Activated:Connect(function()
		window.Visible = false
	end)

	buildVolumeSection(
		window,
		70,
		"MUSIC VOLUME -- %d%%",
		MUSIC_COLOR,
		SoundController.musicVolume(),
		SoundController.setMusicVolume
	)

	local lastTestAt = 0
	buildVolumeSection(
		window,
		140,
		"EFFECTS VOLUME -- %d%%",
		SFX_COLOR,
		SoundController.sfxVolume(),
		function(value)
			SoundController.setSfxVolume(value)
			if os.clock() - lastTestAt > TEST_THROTTLE_SECONDS then
				lastTestAt = os.clock()
				SoundController.playSfx(screenGui, TEST_SOUND, 1)
			end
		end
	)

	local resetButton = UiBuilder.create("TextButton", {
		Name = "ResetButton",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 226),
		Size = UDim2.new(1, -48, 0, 46),
		BackgroundColor3 = RESET_COLOR,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		Text = "RESET CHARACTER",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 17,
		Parent = window,
	}) :: TextButton
	UiBuilder.round(resetButton, 10)
	UiBuilder.hoverPop(resetButton)

	resetButton.Activated:Connect(function()
		window.Visible = false
		Toast.show("Respawning at your checkpoint...")
		task.spawn(function()
			local resetCharacter = Remotes.get("ResetCharacter") :: RemoteEvent
			resetCharacter:FireServer()
		end)
	end)

	UiBuilder.create("TextLabel", {
		Name = "ComingSoon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 290),
		Size = UDim2.new(1, -48, 0, 60),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "Music plays once soundtrack ids are added. More settings coming soon!",
		TextColor3 = Color3.fromRGB(178, 190, 195),
		TextSize = 13,
		TextWrapped = true,
		Parent = window,
	})

	UiBuilder.cartoonizeWindow(window, ACCENT_COLOR, "SETTINGS")

	SettingsGui.toggle = function()
		if window.Visible then
			window.Visible = false
		else
			UiBuilder.popOpen(window)
		end
	end
end

-- Replaced at start(); declared so ShopGui can wire its side button.
SettingsGui.toggle = function() end

return SettingsGui
