--[[
	Game feel for size changes: growth sparkles and a camera punch when
	shrinking. This is deliberately a feature, not polish -- the constant
	sensory feedback on the number going up is what makes the loop stick.
]]

local Players = game:GetService("Players")
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

function EffectsController.start()
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
