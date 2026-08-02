--[[
	Game feel for size changes: growth sparkles and a camera punch when
	shrinking. This is deliberately a feature, not polish -- the constant
	sensory feedback on the number going up is what makes the loop stick.
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

local localPlayer = Players.LocalPlayer

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
