--[[
	The game's audio layer: a Music group looping the configured
	playlist and an Sfx group for one-shot effects, each behind a
	SoundGroup so the settings sliders can turn a whole bus at once.
	Other modules route sounds through playSfx instead of raw Sounds so
	nothing escapes the volume controls.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)

local SFX_LIFETIME_SECONDS = 4

local musicGroup: SoundGroup? = nil
local sfxGroup: SoundGroup? = nil

local SoundController = {}

function SoundController.setMusicVolume(fraction: number)
	if musicGroup ~= nil then
		musicGroup.Volume = math.clamp(fraction, 0, 1)
	end
end

function SoundController.setSfxVolume(fraction: number)
	if sfxGroup ~= nil then
		sfxGroup.Volume = math.clamp(fraction, 0, 1)
	end
end

function SoundController.musicVolume(): number
	return if musicGroup ~= nil then musicGroup.Volume else GameConfig.audio.musicVolume
end

function SoundController.sfxVolume(): number
	return if sfxGroup ~= nil then sfxGroup.Volume else GameConfig.audio.sfxVolume
end

--[[
	One-shot effect routed through the Sfx bus. The sound destroys
	itself shortly after so spammy effects cannot pile up instances.
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
	music.Name = "Music"
	music.Volume = GameConfig.audio.musicVolume
	music.Parent = SoundService
	musicGroup = music

	local sfx = Instance.new("SoundGroup")
	sfx.Name = "Sfx"
	sfx.Volume = GameConfig.audio.sfxVolume
	sfx.Parent = SoundService
	sfxGroup = sfx

	-- The playlist loops forever, one track at a time; an empty id list
	-- (nothing uploaded yet) simply means silence, never an error.
	if #GameConfig.audio.musicIds == 0 then
		return
	end

	local track = Instance.new("Sound")
	track.Name = "MusicTrack"
	track.SoundGroup = music
	track.Parent = music

	local trackIndex = 0
	while true do
		trackIndex = trackIndex % #GameConfig.audio.musicIds + 1
		track.SoundId = GameConfig.audio.musicIds[trackIndex]
		track:Play()
		track.Ended:Wait()
	end
end

return SoundController
