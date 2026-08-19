--[[
	Keeps the character afloat in the tide. The built-in swimming state
	only exists in Terrain water and the tide is plain parts, so this
	applies a gentle upward VectorForce whenever the character sinks
	below the surface. Force only, never Humanoid state changes -- the
	default controller keeps running, and jumping paddles the player up
	naturally.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Slightly stronger than gravity so a submerged character drifts up
-- to the surface instead of hovering in place.
local BUOYANCY_GRAVITY_MULTIPLIER = 1.08
-- The force engages once the root sinks below the surface plus this
-- slack, which keeps the character bobbing near the waterline instead
-- of toggling every frame exactly at it.
local SURFACE_SLACK_STUDS = 0.5
-- Falling into deep water should feel like water, not air: sink
-- speed is capped while buoyancy is active.
local MAXIMUM_SINK_STUDS_PER_SECOND = 12

local localPlayer = Players.LocalPlayer

local waterParts: { BasePart } = {}
local buoyancyForce: VectorForce? = nil
local forceRoot: BasePart? = nil

--[[
	The top of whichever water slab spans the given X, or nil on dry
	land. Read from the parts' actual positions so the client tween and
	the server snap can never disagree with the buoyancy line.
]]
local function waterTopAt(positionX: number): number?
	for _, part in ipairs(waterParts) do
		if math.abs(positionX - part.Position.X) <= part.Size.X / 2 then
			return part.Position.Y + part.Size.Y / 2
		end
	end

	return nil
end

--[[
	Builds a fresh attachment and disabled VectorForce on each new
	character; the old pair is destroyed with the old character, so no
	explicit cleanup is needed.
]]
local function attachForce(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root == nil or not root:IsA("BasePart") then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "BuoyancyAttachment"
	attachment.Parent = root

	local force = Instance.new("VectorForce")
	force.Name = "BuoyancyForce"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.Force = Vector3.zero
	force.Enabled = false
	force.Parent = root

	forceRoot = root
	buoyancyForce = force
end

local function onHeartbeat()
	local force = buoyancyForce
	local root = forceRoot
	if force == nil or root == nil or root.Parent == nil then
		return
	end

	local character = localPlayer.Character
	if character == nil then
		force.Enabled = false
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		force.Enabled = false
		return
	end

	-- Mounted riders are carried by their seat weld; buoyancy would
	-- fight it.
	if humanoid.Sit or humanoid.SeatPart ~= nil then
		force.Enabled = false
		return
	end

	local surfaceY = waterTopAt(root.Position.X)
	if surfaceY == nil or root.Position.Y >= surfaceY + SURFACE_SLACK_STUDS then
		force.Enabled = false
		return
	end

	-- Recomputed every frame because tools and accessories change the
	-- assembly mass.
	local upward = root.AssemblyMass * Workspace.Gravity * BUOYANCY_GRAVITY_MULTIPLIER
	force.Force = Vector3.new(0, upward, 0)
	force.Enabled = true

	local velocity = root.AssemblyLinearVelocity
	if velocity.Y < -MAXIMUM_SINK_STUDS_PER_SECOND then
		root.AssemblyLinearVelocity =
			Vector3.new(velocity.X, -MAXIMUM_SINK_STUDS_PER_SECOND, velocity.Z)
	end
end

local SwimController = {}

function SwimController.start()
	local tideFolder = Workspace:WaitForChild("Tidetown")
	for _, name in ipairs({ "Water", "FloodWater" }) do
		local part = tideFolder:WaitForChild(name)
		if part:IsA("BasePart") then
			table.insert(waterParts, part)
		end
	end

	localPlayer.CharacterAdded:Connect(attachForce)
	if localPlayer.Character ~= nil then
		attachForce(localPlayer.Character)
	end

	RunService.Heartbeat:Connect(onHeartbeat)
end

return SwimController
