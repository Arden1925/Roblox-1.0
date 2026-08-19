--[[
	The settings window: music and effects volume sliders, the reduced
	motion toggle, and a short controls refresher. Every change fires
	the SetSetting remote so the server owns the persisted value; the
	SyncState echo is what updates the widgets, keeping this window a
	pure view over server state. Slider sends are throttled because the
	slider fires on every mouse move and the server only needs the
	value the hand settles on.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent
local TidetownUi = require(Client.TidetownUi)

local TidetownShared = ReplicatedStorage:WaitForChild("TidetownShared")
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

local OUTLINE_NAVY = Color3.fromRGB(31, 41, 74)
local HEADER_COLOR = Color3.fromRGB(125, 140, 158)
local BUTTON_COLOR = Color3.fromRGB(125, 140, 158)
local MUSIC_COLOR = Color3.fromRGB(0, 178, 172)
local SFX_COLOR = Color3.fromRGB(255, 159, 67)
local TOGGLE_ON_COLOR = Color3.fromRGB(46, 125, 50)
local TOGGLE_OFF_COLOR = Color3.fromRGB(99, 110, 114)
local BUTTON_SLOT = 6

-- One send per interval is plenty; the trailing flush guarantees the
-- final value of a drag always reaches the server.
local SEND_INTERVAL_SECONDS = 0.15

-- Sync echoes carry back exactly what this client last sent; moving
-- the handle for those would fight an in-progress drag, so only a
-- genuinely different value repositions it.
local SLIDER_ECHO_EPSILON = 0.004

local CONTROLS_HELP = "Tap CAST at a glowing pool, then tap again on the flash -- "
	.. "perfect taps roll rarer creatures. Eggs charge from catches. When the "
	.. "siren sounds, head for high ground and defend your reef!"

local localPlayer = Players.LocalPlayer

local SettingsGui = {}

function SettingsGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local defaults = TidetownConfig.settings.defaults
	local reducedMotion = defaults.reducedMotion

	local setSettingRemote: RemoteEvent? = nil

	local screenGui = TidetownUi.create("ScreenGui", {
		Name = "TidetownSettingsGui",
		ResetOnSpawn = false,
		DisplayOrder = 14,
		Parent = playerGui,
	}) :: ScreenGui

	-- The assigned slot in the shared left-edge icon column.
	local slotFrame = TidetownUi.create("Frame", {
		Name = "SettingsButtonSlot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, (BUTTON_SLOT - 3.5) * 88),
		Size = UDim2.new(0, 64, 0, 80),
		BackgroundTransparency = 1,
		Parent = screenGui,
	}) :: Frame

	local settingsButton =
		TidetownUi.iconButton(slotFrame, BUTTON_SLOT, "\u{2699}\u{FE0F}", "Settings", BUTTON_COLOR)

	local window = TidetownUi.create("Frame", {
		Name = "SettingsWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 420, 0, 400),
		BorderSizePixel = 0,
		Visible = false,
		Parent = screenGui,
	}) :: Frame

	local closeButton = TidetownUi.create("TextButton", {
		Name = "CloseButton",
		BorderSizePixel = 0,
		Text = "X",
		TextSize = 20,
		Parent = window,
	}) :: TextButton

	TidetownUi.cartoonizeWindow(window, HEADER_COLOR, "Settings")

	-- Builds one throttled sender per setting so both sliders can drag
	-- at once without sharing a pending value.
	local function makeThrottledSender(key: string): (number) -> ()
		local pendingValue: number? = nil
		local flushScheduled = false

		return function(value: number)
			pendingValue = value
			if flushScheduled then
				return
			end

			flushScheduled = true
			task.delay(SEND_INTERVAL_SECONDS, function()
				flushScheduled = false
				local remote = setSettingRemote
				if remote ~= nil and pendingValue ~= nil then
					remote:FireServer(key, pendingValue)
					pendingValue = nil
				end
			end)
		end
	end

	-- One volume row: a percent title over a TidetownUi slider wired
	-- to SetSetting. Returns an applier the sync handler uses to push
	-- server values back into the widgets.
	local function buildVolumeRow(
		offsetY: number,
		titleFormat: string,
		accent: Color3,
		settingKey: string,
		initial: number
	): (number) -> ()
		local currentValue = initial
		local send = makeThrottledSender(settingKey)

		local title = TidetownUi.create("TextLabel", {
			Name = settingKey .. "Title",
			Position = UDim2.new(0, 24, 0, offsetY),
			Size = UDim2.new(1, -48, 0, 20),
			BackgroundTransparency = 1,
			Text = string.format(titleFormat, math.floor(initial * 100 + 0.5)),
			TextSize = 17,
			TextColor3 = accent,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = window,
		}) :: TextLabel

		local holder = TidetownUi.create("Frame", {
			Name = settingKey .. "SliderHolder",
			Position = UDim2.new(0, 24, 0, offsetY + 26),
			Size = UDim2.new(1, -48, 0, 24),
			BackgroundTransparency = 1,
			Parent = window,
		}) :: Frame

		local moveHandle = TidetownUi.slider(holder, 0, 1, initial, accent, function(value)
			currentValue = value
			title.Text = string.format(titleFormat, math.floor(value * 100 + 0.5))
			send(value)
		end)

		return function(value: number)
			if math.abs(value - currentValue) <= SLIDER_ECHO_EPSILON then
				return
			end

			currentValue = value
			title.Text = string.format(titleFormat, math.floor(value * 100 + 0.5))
			moveHandle(value)
		end
	end

	local applyMusicValue =
		buildVolumeRow(52, "Music %d%%", MUSIC_COLOR, "musicVolume", defaults.musicVolume)
	local applySfxValue =
		buildVolumeRow(118, "SFX %d%%", SFX_COLOR, "sfxVolume", defaults.sfxVolume)

	TidetownUi.create("TextLabel", {
		Name = "ReducedMotionLabel",
		Position = UDim2.new(0, 24, 0, 190),
		Size = UDim2.new(0, 220, 0, 34),
		BackgroundTransparency = 1,
		Text = "Reduced Motion",
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window,
	})

	local toggleButton = TidetownUi.create("TextButton", {
		Name = "ReducedMotionToggle",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 190),
		Size = UDim2.new(0, 96, 0, 34),
		BackgroundColor3 = TOGGLE_OFF_COLOR,
		BorderSizePixel = 0,
		Text = "Off",
		TextSize = 16,
		Parent = window,
	}) :: TextButton
	TidetownUi.round(toggleButton, 10)
	TidetownUi.stroke(toggleButton, OUTLINE_NAVY, 2.5)
	TidetownUi.hoverPop(toggleButton)

	local function refreshToggle()
		toggleButton.Text = if reducedMotion then "On" else "Off"
		toggleButton.BackgroundColor3 = if reducedMotion then TOGGLE_ON_COLOR else TOGGLE_OFF_COLOR
	end

	TidetownUi.create("TextLabel", {
		Name = "HelpTitle",
		Position = UDim2.new(0, 24, 0, 244),
		Size = UDim2.new(1, -48, 0, 20),
		BackgroundTransparency = 1,
		Text = "How to play",
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window,
	})

	TidetownUi.create("TextLabel", {
		Name = "HelpText",
		Position = UDim2.new(0, 24, 0, 268),
		Size = UDim2.new(1, -48, 0, 110),
		BackgroundTransparency = 1,
		Text = CONTROLS_HELP,
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = window,
	})

	toggleButton.Activated:Connect(function()
		-- Optimistic flip so the toggle feels instant; the SyncState
		-- echo confirms (or corrects) it a beat later.
		reducedMotion = not reducedMotion
		refreshToggle()

		local remote = setSettingRemote
		if remote ~= nil then
			remote:FireServer("reducedMotion", reducedMotion)
		end
	end)

	settingsButton.Activated:Connect(function()
		if window.Visible then
			window.Visible = false
		else
			TidetownUi.popOpen(window)
		end
	end)

	closeButton.Activated:Connect(function()
		window.Visible = false
	end)

	refreshToggle()

	setSettingRemote = TidetownRemotes.get("SetSetting") :: RemoteEvent

	local syncRemote = TidetownRemotes.get("SyncState") :: RemoteEvent
	-- The join-burst state push can fire before this listener exists
	-- and queued events drain only into the first connection, so ask
	-- the server to resend our slices. task.defer runs after the
	-- Connect below, so the reply always finds the handler.
	task.defer(function()
		local requestSync = TidetownRemotes.get("RequestSync") :: RemoteEvent
		requestSync:FireServer("settings")
	end)
	syncRemote.OnClientEvent:Connect(function(kind, payload)
		if kind ~= "settings" or typeof(payload) ~= "table" then
			return
		end

		if typeof(payload.musicVolume) == "number" then
			applyMusicValue(math.clamp(payload.musicVolume, 0, 1))
		end

		if typeof(payload.sfxVolume) == "number" then
			applySfxValue(math.clamp(payload.sfxVolume, 0, 1))
		end

		if typeof(payload.reducedMotion) == "boolean" then
			reducedMotion = payload.reducedMotion
			refreshToggle()
		end
	end)
end

return SettingsGui
