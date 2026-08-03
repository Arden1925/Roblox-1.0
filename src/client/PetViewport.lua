--[[
	A reusable spinning 3D pet display for UI frames. One shared
	Heartbeat connection rotates every live viewport, and viewports
	whose frames die are dropped automatically, so cost scales with what
	is actually on screen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = script.Parent
local UiBuilder = require(Client.UiBuilder)

local Shared = ReplicatedStorage.Shared
local PetModels = require(Shared.PetModels)

local SPIN_SPEED = 1.2

type ViewportEntry = {
	model: Model,
	angle: number,
	speed: number,
}

local entries: { [ViewportFrame]: ViewportEntry } = {}
local loopStarted = false

local PetViewport = {}

local function ensureLoop()
	if loopStarted then
		return
	end
	loopStarted = true

	RunService.Heartbeat:Connect(function(deltaSeconds)
		for viewport, entry in pairs(entries) do
			if viewport.Parent == nil then
				entries[viewport] = nil
			else
				entry.angle += deltaSeconds * entry.speed
				entry.model:PivotTo(CFrame.Angles(0, entry.angle, 0))
			end
		end
	end)
end

--[[
	Creates a spinning viewport for the pet inside the given parent.
	Returns the frame, or nil for unknown pets. spinSpeed above the
	default makes reveals feel more energetic.
]]
function PetViewport.create(
	parent: Instance,
	petId: string,
	size: UDim2,
	position: UDim2,
	spinSpeed: number?
): ViewportFrame?
	local model = PetModels.build(petId)
	if model == nil then
		return nil
	end

	local viewport = UiBuilder.create("ViewportFrame", {
		Name = "PetViewport",
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 200, 210),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-1, -1, -0.5),
		Parent = parent,
	}) :: ViewportFrame

	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.new(Vector3.new(0, 0.6, -3.4), Vector3.new(0, 0.3, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	model.Parent = viewport

	entries[viewport] = {
		model = model,
		angle = 0,
		speed = if spinSpeed ~= nil then spinSpeed else SPIN_SPEED,
	}
	ensureLoop()

	return viewport
end

-- A quick excited hop-and-twirl, for when a pet gets clicked.
function PetViewport.celebrate(viewport: ViewportFrame)
	local entry = entries[viewport]
	if entry == nil then
		return
	end

	local boostedUntil = os.clock() + 0.7
	local originalSpeed = entry.speed
	entry.speed = originalSpeed + 10

	task.delay(0.7, function()
		local current = entries[viewport]
		if current ~= nil and os.clock() >= boostedUntil then
			current.speed = originalSpeed
		end
	end)
end

return PetViewport
