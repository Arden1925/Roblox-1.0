--[[
	Shared camera and world-flash effects: the FOV punch that makes a
	perfect catch land in the body, and a ColorCorrection flash that
	brightens the whole 3D world for reveal moments -- richer than a
	white frame because the scene itself flares. Both respect the
	reduced-motion setting and cancel by token so spammed rewards never
	stack drift into the camera.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local TidetownShared = ReplicatedStorage:WaitForChild("TidetownShared")
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

local FOV_RETURN_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FLASH_OUT_INFO = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH_BRIGHTNESS = 0.25
local FLASH_SATURATION = 0.15

local reducedMotion = false
local baseFieldOfView: number? = nil
local punchToken = 0
local flashEffect: ColorCorrectionEffect? = nil

local CameraFx = {}

--[[
	Kicks the field of view by delta (negative pulls in for impact,
	positive pushes out for speed) and springs back to the resting
	value. The resting value is captured only while no punch is live,
	so overlapping rewards can never walk the camera's baseline.
]]
function CameraFx.punchFov(delta: number)
	if reducedMotion then
		return
	end

	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	punchToken += 1
	local token = punchToken

	if baseFieldOfView == nil then
		baseFieldOfView = camera.FieldOfView
	end

	local restingFieldOfView = baseFieldOfView :: number
	camera.FieldOfView = restingFieldOfView + delta

	local settle = TweenService:Create(camera, FOV_RETURN_INFO, {
		FieldOfView = restingFieldOfView,
	})
	settle:Play()
	settle.Completed:Connect(function()
		if token == punchToken then
			baseFieldOfView = nil
		end
	end)
end

--[[
	Flares the whole world bright for a beat, then settles. Composes
	with 3D reveals (hatches, rare catches) where a flat white frame
	would hide the very thing being revealed.
]]
function CameraFx.flash()
	if reducedMotion then
		return
	end

	local effect = flashEffect
	if effect == nil then
		return
	end

	effect.Brightness = FLASH_BRIGHTNESS
	effect.Saturation = FLASH_SATURATION
	TweenService:Create(effect, FLASH_OUT_INFO, {
		Brightness = 0,
		Saturation = 0,
	}):Play()
end

function CameraFx.start()
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "TidetownFlash"
	effect.Brightness = 0
	effect.Saturation = 0
	effect.Parent = Lighting
	flashEffect = effect

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
		if kind == "settings" and typeof(payload) == "table" then
			reducedMotion = payload.reducedMotion == true
		end
	end)
end

return CameraFx
