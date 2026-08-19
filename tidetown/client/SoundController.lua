--[[
	The Tidetown audio layer: one looping music track per tide phase,
	crossfaded on every TideChanged broadcast, behind a Music SoundGroup
	so the settings slider turns the whole bus at once. Every id below
	is a 0 placeholder for now -- a phase without a real id simply fades
	to silence, which keeps the crossfade wiring exercised so pasting
	ids in later is the only step left. An Sfx group exists for the same
	reason: the volume slider needs a bus to land on before any one-shot
	effects ship.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local TidetownShared = ReplicatedStorage:WaitForChild("TidetownShared")
local TidePhase = require(TidetownShared.TidePhase)
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

-- Paste real music asset ids here to give each phase its own track;
-- zero keeps that phase silent without touching any other wiring.
local SOUND_IDS: { [string]: number } = {
	[TidePhase.Low] = 0,
	[TidePhase.Rising] = 0,
	[TidePhase.High] = 0,
	[TidePhase.Falling] = 0,
}

-- Per-track ceiling inside the Music group; the user's music slider
-- scales the group, so tracks never need retuning per setting.
local TRACK_VOLUME = 0.5
local CROSSFADE_INFO = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local SFX_LIFETIME_SECONDS = 4
local TIDE_FOLDER_WAIT_SECONDS = 20

local musicGroup: SoundGroup? = nil
local sfxGroup: SoundGroup? = nil
local tracksByPhase: { [string]: Sound } = {}
local fadeTweens: { [Sound]: Tween } = {}
local activeTrack: Sound? = nil

local SoundController = {}

local function fadeTrack(track: Sound, targetVolume: number)
	local existing = fadeTweens[track]
	if existing ~= nil then
		existing:Cancel()
	end

	local tween = TweenService:Create(track, CROSSFADE_INFO, { Volume = targetVolume })
	fadeTweens[track] = tween

	tween.Completed:Connect(function(playbackState)
		-- A cancelled fade means a newer one took over; only a fade
		-- that truly reached silence may stop the track.
		if playbackState ~= Enum.PlaybackState.Completed then
			return
		end

		if fadeTweens[track] == tween then
			fadeTweens[track] = nil
		end

		if targetVolume <= 0 then
			track:Stop()
		end
	end)

	tween:Play()
end

local function crossfadeTo(phase: string)
	local nextTrack = tracksByPhase[phase]
	if nextTrack == activeTrack then
		return
	end

	if activeTrack ~= nil then
		fadeTrack(activeTrack, 0)
	end

	if nextTrack ~= nil then
		if not nextTrack.IsPlaying then
			nextTrack.Volume = 0
			nextTrack:Play()
		end

		fadeTrack(nextTrack, TRACK_VOLUME)
	end

	activeTrack = nextTrack
end

--[[
	Applies the player's persisted volumes to the two buses. The server
	echoes settings through SyncState on join and after every change,
	so this is the single place volume ever lands.
]]
local function applyVolumes(settings: { [string]: any })
	if musicGroup ~= nil and typeof(settings.musicVolume) == "number" then
		musicGroup.Volume = math.clamp(settings.musicVolume, 0, 1)
	end

	if sfxGroup ~= nil and typeof(settings.sfxVolume) == "number" then
		sfxGroup.Volume = math.clamp(settings.sfxVolume, 0, 1)
	end
end

--[[
	One-shot effect routed through the Sfx bus so nothing escapes the
	volume slider. The sound destroys itself shortly after playing so
	spammy callers cannot pile up instances.
]]
function SoundController.playSfx(parent: Instance, soundId: string, playbackSpeed: number)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 0.6
	sound.PlaybackSpeed = playbackSpeed
	sound.SoundGroup = sfxGroup
	sound.Parent = parent
	sound:Play()

	task.delay(SFX_LIFETIME_SECONDS, function()
		sound:Destroy()
	end)
end

function SoundController.start()
	local music = Instance.new("SoundGroup")
	music.Name = "TidetownMusic"
	music.Volume = TidetownConfig.settings.defaults.musicVolume
	music.Parent = SoundService
	musicGroup = music

	local sfx = Instance.new("SoundGroup")
	sfx.Name = "TidetownSfx"
	sfx.Volume = TidetownConfig.settings.defaults.sfxVolume
	sfx.Parent = SoundService
	sfxGroup = sfx

	for phase, soundId in pairs(SOUND_IDS) do
		if soundId ~= 0 then
			local track = Instance.new("Sound")
			track.Name = "Music" .. phase
			track.SoundId = "rbxassetid://" .. tostring(soundId)
			track.Looped = true
			track.Volume = 0
			track.SoundGroup = music
			track.Parent = music
			tracksByPhase[phase] = track
		end
	end

	local syncState = TidetownRemotes.get("SyncState") :: RemoteEvent
	syncState.OnClientEvent:Connect(function(kind, payload)
		if kind == "settings" and typeof(payload) == "table" then
			applyVolumes(payload)
		end
	end)

	local tideChanged = TidetownRemotes.get("TideChanged") :: RemoteEvent
	tideChanged.OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" and typeof(payload.phase) == "string" then
			crossfadeTo(payload.phase)
		end
	end)

	-- Late joiners get a TideChanged sync from the server, but the
	-- Workspace attribute is already replicated, so starting from it
	-- avoids a silent gap while that broadcast is in flight.
	local tideFolder = Workspace:WaitForChild("Tidetown", TIDE_FOLDER_WAIT_SECONDS)
	if tideFolder ~= nil then
		local phase = tideFolder:GetAttribute("Phase")
		if typeof(phase) == "string" then
			crossfadeTo(phase)
		end
	end
end

return SoundController
