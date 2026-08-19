--[[
	Owns each player's persisted client settings -- music volume, sfx
	volume, and reduced motion -- and mirrors them to that player's
	client through the SyncState remote. Writes arrive from the
	untrusted SetSetting remote, so every value is validated and clamped
	here before it sticks.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TidetownShared = ReplicatedStorage.TidetownShared
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

export type Settings = {
	musicVolume: number,
	sfxVolume: number,
	reducedMotion: boolean,
}

local settingsByPlayer: { [Player]: Settings } = {}
local syncStateRemote: RemoteEvent? = nil

local SettingsService = {}

local function copySettings(settings: Settings): Settings
	return {
		musicVolume = settings.musicVolume,
		sfxVolume = settings.sfxVolume,
		reducedMotion = settings.reducedMotion,
	}
end

--[[
	Sends the player's full settings table to their client. Called after
	every mutation so the client never has to ask.
]]
function SettingsService.pushState(player: Player)
	local settings = settingsByPlayer[player]
	if settings == nil or syncStateRemote == nil then
		return
	end

	syncStateRemote:FireClient(player, "settings", copySettings(settings))
end

function SettingsService.initializePlayer(player: Player, settings: Settings)
	-- Copied so this service owns its slice outright instead of
	-- aliasing the loaded PlayerData table.
	settingsByPlayer[player] = copySettings(settings)
	SettingsService.pushState(player)
end

function SettingsService.snapshot(player: Player): Settings?
	local settings = settingsByPlayer[player]
	if settings == nil then
		return nil
	end

	-- Copied so the save snapshot cannot alias live state that a later
	-- SetSetting could mutate mid-save.
	return copySettings(settings)
end

function SettingsService.removePlayer(player: Player)
	settingsByPlayer[player] = nil
end

--[[
	Applies one setting from the SetSetting remote. Clients can send
	anything, so the key must be known and the value the right type;
	volumes are clamped to 0..1.
]]
function SettingsService.set(player: Player, key: any, value: any): (boolean, string?)
	local settings = settingsByPlayer[player]
	if settings == nil then
		return false, "Not ready"
	end

	if typeof(key) ~= "string" then
		return false, "Unknown setting"
	end

	if key == "musicVolume" or key == "sfxVolume" then
		-- NaN passes the typeof check and can survive math.clamp; the
		-- self-inequality test is the reliable way to reject it.
		if typeof(value) ~= "number" or value ~= value then
			return false, "Invalid value"
		end

		local clamped = math.clamp(value, 0, 1)
		if key == "musicVolume" then
			settings.musicVolume = clamped
		else
			settings.sfxVolume = clamped
		end
	elseif key == "reducedMotion" then
		if typeof(value) ~= "boolean" then
			return false, "Invalid value"
		end

		settings.reducedMotion = value
	else
		return false, "Unknown setting"
	end

	SettingsService.pushState(player)

	return true, nil
end

--[[
	Fetches the SyncState remote once. TidetownRemotes.get yields, which
	is why init calls start from a spawned task.
]]
function SettingsService.start()
	syncStateRemote = TidetownRemotes.get("SyncState") :: RemoteEvent
end

return SettingsService
