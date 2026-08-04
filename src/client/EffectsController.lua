--[[
	Game feel for size changes: growth sparkles, a camera punch when
	shrinking, and a fullscreen glitch burst for cutscenes. This is
	deliberately a feature, not polish -- the constant sensory feedback
	on the number going up is what makes the loop stick.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local SHRINK_FOV_KICK = 12
local FOV_RECOVER_INFO = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- A shrink pad drains far faster than regrowth climbs, so any drop bigger
-- than this in one tick can only be a shrink, not noise.
local SHRINK_DETECTION_DROP = 5

local GROWTH_PARTICLE_COLOR = Color3.fromRGB(76, 209, 55)

local GLITCH_SLICE_COUNT = 3
local GLITCH_SWAP_COUNT = 24
-- Asymmetric on purpose: an even in/out kick reads as breathing, not
-- as a malfunction.
local GLITCH_FOV_KICK = 2
local GLITCH_FOV_DIP = 1
local GLITCH_SLICE_COLOR = Color3.fromRGB(230, 235, 245)
local GLITCH_MAGENTA = Color3.fromRGB(255, 0, 128)
local GLITCH_CYAN = Color3.fromRGB(0, 229, 255)
-- Mirrored offsets pull the magenta ghost left and the cyan one right,
-- which is what sells the RGB-split look.
local GLITCH_GHOST_OFFSETS = { -10, 10 }

local localPlayer = Players.LocalPlayer

-- The glitch overlay is built once and reused: the landing cutscene can
-- fire it on every respawn, and rebuilding frames each time would churn
-- instances for no visual gain.
local glitchGui: ScreenGui? = nil
local glitchSlices: { Frame } = {}
local glitchGhosts: { Frame } = {}
local glitchActive = false

local EffectsController = {}

local function attachEmitter(character: Model): ParticleEmitter?
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if rootPart == nil then
		return nil
	end

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "GrowthSparkles"
	emitter.Enabled = false
	emitter.Color = ColorSequence.new(GROWTH_PARTICLE_COLOR)
	emitter.Size = NumberSequence.new(0.35)
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(3, 6)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = rootPart

	return emitter
end

--[[
	Spins and bobs every part tagged Spinner (coins, egg orbs, the
	limited pedestal orb). Purely visual and client-side: the server
	never moves these parts, so touch detection stays at their true
	position while every client sees them alive.
]]
local function startSpinners()
	local basePositions: { [BasePart]: Vector3 } = {}

	local function track(part: Instance)
		if part:IsA("BasePart") then
			basePositions[part :: BasePart] = (part :: BasePart).Position
		end
	end

	for _, part in ipairs(CollectionService:GetTagged("Spinner")) do
		track(part)
	end
	CollectionService:GetInstanceAddedSignal("Spinner"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("Spinner"):Connect(function(part)
		basePositions[part] = nil
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(deltaSeconds)
		elapsed += deltaSeconds

		local spin = CFrame.Angles(0, elapsed * 2, 0)
		local bob = math.sin(elapsed * 2) * 0.5

		for part, basePosition in pairs(basePositions) do
			if part.Parent == nil then
				basePositions[part] = nil
			else
				part.CFrame = CFrame.new(basePosition + Vector3.new(0, bob, 0)) * spin
			end
		end
	end)
end

local function ensureGlitchGui(): ScreenGui
	if glitchGui ~= nil then
		return glitchGui
	end

	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "GlitchGui"
	screenGui.ResetOnSpawn = false
	-- Above every gameplay window: a screen tear that only covers half
	-- the HUD reads as a broken UI, not a broken world.
	screenGui.DisplayOrder = 30
	screenGui.IgnoreGuiInset = true
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	for sliceIndex = 1, GLITCH_SLICE_COUNT do
		local slice = Instance.new("Frame")
		slice.Name = "GlitchSlice" .. sliceIndex
		slice.Size = UDim2.new(1, 60, 0, 12 + sliceIndex * 6)
		slice.Position = UDim2.new(0, -30, sliceIndex / (GLITCH_SLICE_COUNT + 1), 0)
		slice.BackgroundColor3 = GLITCH_SLICE_COLOR
		slice.BackgroundTransparency = 0.75
		slice.BorderSizePixel = 0
		slice.Visible = false
		slice.ZIndex = 2
		slice.Parent = screenGui

		table.insert(glitchSlices, slice)
	end

	for ghostIndex, offset in ipairs(GLITCH_GHOST_OFFSETS) do
		local ghost = Instance.new("Frame")
		ghost.Name = "GlitchGhost" .. ghostIndex
		ghost.Size = UDim2.new(1, 24, 0, 5)
		ghost.Position = UDim2.new(0, offset, 0.4 + ghostIndex * 0.1, 0)
		ghost.BackgroundColor3 = if ghostIndex == 1 then GLITCH_MAGENTA else GLITCH_CYAN
		ghost.BackgroundTransparency = 0.55
		ghost.BorderSizePixel = 0
		ghost.Visible = false
		ghost.Parent = screenGui

		table.insert(glitchGhosts, ghost)
	end

	glitchGui = screenGui

	return screenGui
end

--[[
	A short fullscreen datamosh: horizontal slices jumping around, a
	magenta/cyan ghost pair for the RGB-split feel, and a small camera
	FieldOfView jitter. Non-yielding; the overlay hides itself and the
	FieldOfView is restored exactly when the duration ends.
]]
function EffectsController.glitch(durationSeconds: number)
	assert(typeof(durationSeconds) == "number", "durationSeconds must be a number")
	assert(durationSeconds > 0, "durationSeconds must be positive")

	-- Overlapping glitches would fight over the shared frames and could
	-- capture an already-kicked FieldOfView as the value to restore.
	if glitchActive then
		return
	end
	glitchActive = true

	local overlay = ensureGlitchGui()

	task.spawn(function()
		local camera = Workspace.CurrentCamera
		local originalFieldOfView = if camera ~= nil then camera.FieldOfView else 0

		overlay.Enabled = true

		local stepSeconds = durationSeconds / GLITCH_SWAP_COUNT
		for swapIndex = 1, GLITCH_SWAP_COUNT do
			-- Slices and ghosts alternate, so something always tears but
			-- nothing ever settles into a readable shape.
			local slicesVisible = swapIndex % 2 == 1

			for _, slice in ipairs(glitchSlices) do
				slice.Visible = slicesVisible
				slice.Position = UDim2.new(0, math.random(-40, 40), math.random(), 0)
			end

			for ghostIndex, ghost in ipairs(glitchGhosts) do
				ghost.Visible = not slicesVisible
				ghost.Position = UDim2.new(0, GLITCH_GHOST_OFFSETS[ghostIndex], math.random(), 0)
			end

			if camera ~= nil then
				camera.FieldOfView = originalFieldOfView
					+ (if slicesVisible then GLITCH_FOV_KICK else -GLITCH_FOV_DIP)
			end

			task.wait(stepSeconds)
		end

		for _, slice in ipairs(glitchSlices) do
			slice.Visible = false
		end
		for _, ghost in ipairs(glitchGhosts) do
			ghost.Visible = false
		end
		overlay.Enabled = false

		if camera ~= nil then
			camera.FieldOfView = originalFieldOfView
		end
		glitchActive = false
	end)
end

function EffectsController.start()
	startSpinners()

	local emitter: ParticleEmitter? = nil

	local function onCharacterAdded(character: Model)
		task.spawn(function()
			emitter = attachEmitter(character)
		end)
	end

	if localPlayer.Character ~= nil then
		onCharacterAdded(localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(onCharacterAdded)

	local lastSize = 0

	localPlayer:GetAttributeChangedSignal("CurrentSize"):Connect(function()
		local currentSize = localPlayer:GetAttribute("CurrentSize")
		if typeof(currentSize) ~= "number" then
			return
		end

		if currentSize > lastSize and emitter ~= nil then
			emitter:Emit(3)
		elseif currentSize < lastSize - SHRINK_DETECTION_DROP then
			local camera = Workspace.CurrentCamera
			if camera ~= nil then
				camera.FieldOfView = 70 + SHRINK_FOV_KICK

				local recoverTween = TweenService:Create(camera, FOV_RECOVER_INFO, {
					FieldOfView = 70,
				})
				recoverTween:Play()
			end
		end

		lastSize = currentSize
	end)
end

return EffectsController
