--[[
	Client-side tide theater: smoothly animates the two giant water
	parts the server snaps between levels, tints the lighting teal
	while the town floods, schedules the incoming-tide siren, and
	throws a foam wall along the waterline when the water starts
	moving. The server owns the real water level; everything here is
	presentation layered over the TideChanged broadcast.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local TidetownShared = ReplicatedStorage:WaitForChild("TidetownShared")
local TidePhase = require(TidetownShared.TidePhase)
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

-- Paste a real siren asset id here to arm the pre-tide warning; zero
-- keeps the scheduling wired but silent.
local SIREN_SOUND_ID = 0

-- The seam between the sea part and the flood part -- the shoreline
-- where the foam wall erupts, spanning the full playable Z width.
local FOAM_LINE_X = -30
local FOAM_LINE_LENGTH_STUDS = 380
local FOAM_BURST_COUNT = 260
local FOAM_CLEANUP_SECONDS = 4

-- Flooded lighting: fog closes in and the ambient drifts toward teal.
local HIGH_TIDE_AMBIENT = Color3.fromRGB(96, 158, 168)
local AMBIENT_TINT_ALPHA = 0.4
local HIGH_TIDE_FOG_END = 700
local LIGHTING_SNAP_SECONDS = 0.5

-- Where the water starts when a transition begins, so the tween
-- always sweeps the full range even when replication has already
-- snapped the parts to their destination.
local START_LEVEL_BY_PHASE: { [string]: number } = {
	[TidePhase.Rising] = TidetownConfig.tide.lowWaterY,
	[TidePhase.Falling] = TidetownConfig.tide.highWaterY,
}

local waterParts: { BasePart } = {}
local activeWaterTweens: { [BasePart]: Tween } = {}
local reducedMotion = TidetownConfig.settings.defaults.reducedMotion
local sirenSound: Sound? = nil
local sirenToken = 0
local baseFogEnd = 100000
local baseAmbient = Color3.fromRGB(128, 128, 128)
local highFogEnd = HIGH_TIDE_FOG_END
local highAmbient = HIGH_TIDE_AMBIENT

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

local function cancelWaterTween(part: BasePart)
	local tween = activeWaterTweens[part]
	if tween ~= nil then
		tween:Cancel()
		activeWaterTweens[part] = nil
	end
end

local function waterCFrameAtTop(part: BasePart, topY: number): CFrame
	local position = part.Position

	return CFrame.new(position.X, topY - part.Size.Y / 2, position.Z)
end

local function snapWaterTop(part: BasePart, topY: number)
	cancelWaterTween(part)
	part.CFrame = waterCFrameAtTop(part, topY)
end

local function tweenWaterTop(part: BasePart, topY: number, seconds: number)
	cancelWaterTween(part)

	local tween = TweenService:Create(
		part,
		TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ CFrame = waterCFrameAtTop(part, topY) }
	)
	activeWaterTweens[part] = tween
	tween:Play()
end

local function burstFoamWall(topY: number)
	-- The foam wall is pure spectacle; players who opted into reduced
	-- motion skip it entirely.
	if reducedMotion then
		return
	end

	local holder = Instance.new("Part")
	holder.Name = "TidetownFoamLine"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(4, 1, FOAM_LINE_LENGTH_STUDS)
	holder.CFrame = CFrame.new(FOAM_LINE_X, topY, 0)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Color = ColorSequence.new(Color3.fromRGB(235, 250, 255))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5),
		NumberSequenceKeypoint.new(1, 4),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(1, 1.8)
	emitter.Speed = NumberRange.new(10, 16)
	emitter.SpreadAngle = Vector2.new(30, 30)
	emitter.Acceleration = Vector3.new(0, -14, 0)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Parent = holder

	holder.Parent = Workspace
	emitter:Emit(FOAM_BURST_COUNT)

	task.delay(FOAM_CLEANUP_SECONDS, function()
		holder:Destroy()
	end)
end

local function playSiren()
	-- A zero placeholder id never builds a Sound, so the siren skips
	-- silently until a creator pastes a real asset id above.
	if sirenSound == nil then
		return
	end

	sirenSound:Play()
end

local function scheduleSiren(phase: string, endsAt: number)
	-- Every phase change invalidates any siren scheduled before it.
	sirenToken += 1

	if phase ~= TidePhase.Low then
		return
	end

	local token = sirenToken
	local lead = TidetownConfig.tide.sirenLeadSeconds
	local delaySeconds = endsAt - lead - Workspace:GetServerTimeNow()
	if delaySeconds <= 0 then
		return
	end

	task.delay(delaySeconds, function()
		if token == sirenToken then
			playSiren()
		end
	end)
end

-- Per-phase color grading from docs/DESIGN_LANGUAGE.md: the mood shifts
-- ride a ColorCorrection tint over the authored map, never a repaint.
-- High gains a whisper of saturation (heavier, not brighter); Falling
-- desaturates into the silver ebb.
local PHASE_GRADING: { [string]: { tint: Color3, saturation: number } } = {
	[TidePhase.Low] = { tint = Color3.fromRGB(255, 242, 220), saturation = 0 },
	[TidePhase.Rising] = { tint = Color3.fromRGB(234, 244, 246), saturation = 0 },
	[TidePhase.High] = { tint = Color3.fromRGB(207, 230, 232), saturation = 0.05 },
	[TidePhase.Falling] = { tint = Color3.fromRGB(228, 235, 238), saturation = -0.05 },
}

local gradingEffect: ColorCorrectionEffect? = nil

local function applyGrading(phase: string, seconds: number)
	local effect = gradingEffect
	local grading = PHASE_GRADING[phase]
	if effect == nil or grading == nil then
		return
	end

	TweenService:Create(
		effect,
		TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ TintColor = grading.tint, Saturation = grading.saturation }
	):Play()
end

local function applyLighting(flooded: boolean, seconds: number)
	local targetFogEnd = if flooded then highFogEnd else baseFogEnd
	local targetAmbient = if flooded then highAmbient else baseAmbient

	TweenService:Create(
		Lighting,
		TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ FogEnd = targetFogEnd, OutdoorAmbient = targetAmbient }
	):Play()
end

local function onTideChanged(phase: string, endsAt: number, waterY: number, seconds: number)
	scheduleSiren(phase, endsAt)

	if phase == TidePhase.Rising or phase == TidePhase.Falling then
		local remaining = math.max(endsAt - Workspace:GetServerTimeNow(), 0.1)
		local tweenSeconds = math.min(seconds, remaining)

		-- A transition that just began sweeps the whole range from its
		-- known start level; a mid-transition sync (late join) tweens
		-- from wherever the water happens to be.
		local freshTransition = remaining >= seconds - 1
		if freshTransition then
			local startLevel = START_LEVEL_BY_PHASE[phase]
			for _, part in ipairs(waterParts) do
				snapWaterTop(part, startLevel)
			end
			burstFoamWall(startLevel)
		end

		for _, part in ipairs(waterParts) do
			tweenWaterTop(part, waterY, tweenSeconds)
		end
		applyLighting(phase == TidePhase.Rising, tweenSeconds)
		applyGrading(phase, tweenSeconds)
	else
		-- Low and High are resting levels: kill any straggling tween
		-- and pin the water exactly where the server says it is.
		for _, part in ipairs(waterParts) do
			snapWaterTop(part, waterY)
		end
		applyLighting(phase == TidePhase.High, LIGHTING_SNAP_SECONDS)
		applyGrading(phase, LIGHTING_SNAP_SECONDS)
	end
end

local TideController = {}

function TideController.start()
	local tideFolder = Workspace:WaitForChild("Tidetown")
	for _, name in ipairs({ "Water", "FloodWater" }) do
		local part = tideFolder:WaitForChild(name)
		if part:IsA("BasePart") then
			table.insert(waterParts, part)
		end
	end

	-- The flood tint interpolates from whatever the place's lighting
	-- was authored with, so it composes with future lighting art.
	baseFogEnd = Lighting.FogEnd
	baseAmbient = Lighting.OutdoorAmbient
	highFogEnd = math.min(baseFogEnd, HIGH_TIDE_FOG_END)
	highAmbient = baseAmbient:Lerp(HIGH_TIDE_AMBIENT, AMBIENT_TINT_ALPHA)

	local grading = Instance.new("ColorCorrectionEffect")
	grading.Name = "TidetownGrading"
	grading.TintColor = PHASE_GRADING[TidePhase.Low].tint
	grading.Saturation = PHASE_GRADING[TidePhase.Low].saturation
	grading.Parent = Lighting
	gradingEffect = grading

	if SIREN_SOUND_ID ~= 0 then
		local sound = Instance.new("Sound")
		sound.Name = "TideSiren"
		sound.SoundId = "rbxassetid://" .. tostring(SIREN_SOUND_ID)
		sound.Volume = 0.6
		sound.Parent = Workspace
		sirenSound = sound
	end

	local syncState = TidetownRemotes.get("SyncState") :: RemoteEvent
	-- The join-burst state push can fire before this listener exists
	-- and queued events drain only into the first connection, so ask
	-- the server to resend our slices. task.defer runs after the
	-- Connect below, so the reply always finds the handler.
	task.defer(function()
		local requestSync = TidetownRemotes.get("RequestSync") :: RemoteEvent
		requestSync:FireServer("settings")
	end)
	syncState.OnClientEvent:Connect(function(kind, payload)
		if kind == "settings" and typeof(payload) == "table" then
			reducedMotion = payload.reducedMotion == true
		end
	end)

	local tideChanged = TidetownRemotes.get("TideChanged") :: RemoteEvent
	tideChanged.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		if
			typeof(payload.phase) == "string"
			and typeof(payload.endsAt) == "number"
			and typeof(payload.waterY) == "number"
			and typeof(payload.seconds) == "number"
		then
			onTideChanged(payload.phase, payload.endsAt, payload.waterY, payload.seconds)
		end
	end)

	-- Late join: the folder attributes describe the phase in flight,
	-- so water and lighting land in the right place before the first
	-- TideChanged broadcast arrives.
	local phase = tideFolder:GetAttribute("Phase")
	local endsAt = tideFolder:GetAttribute("PhaseEndsAt")
	local waterY = tideFolder:GetAttribute("WaterY")
	if typeof(phase) == "string" and typeof(endsAt) == "number" and typeof(waterY) == "number" then
		onTideChanged(phase, endsAt, waterY, phaseDurationSeconds(phase))
	end
end

return TideController
