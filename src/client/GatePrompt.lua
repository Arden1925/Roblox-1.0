--[[
	Floating labels over gates and cracks telling the local player, in
	color, whether they fit: the moment-to-moment guidance that teaches
	the grow-versus-shrink loop without a tutorial.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent
local UiBuilder = require(Client.UiBuilder)

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local SizeFormula = require(Shared.SizeFormula)

local SIZE_GATE_TAG = "SizeGate"
local SQUEEZE_CRACK_TAG = "SqueezeCrack"

local UPDATE_INTERVAL_SECONDS = 0.15
local VISIBLE_RANGE = 70

local CAN_PASS_COLOR = Color3.fromRGB(76, 209, 55)
local BLOCKED_GATE_COLOR = Color3.fromRGB(232, 65, 24)
local BLOCKED_CRACK_COLOR = Color3.fromRGB(255, 168, 1)

local localPlayer = Players.LocalPlayer

local labelByBarrier: { [BasePart]: TextLabel } = {}

local GatePrompt = {}

local function createLabel(barrier: BasePart): TextLabel
	local billboard = UiBuilder.create("BillboardGui", {
		Name = "GatePrompt",
		Adornee = barrier,
		Size = UDim2.new(0, 240, 0, 44),
		StudsOffsetWorldSpace = Vector3.new(0, barrier.Size.Y / 2 + 3, 0),
		AlwaysOnTop = true,
		MaxDistance = VISIBLE_RANGE,
		Parent = barrier,
	})

	local label = UiBuilder.create("TextLabel", {
		Name = "PromptText",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "",
		TextColor3 = CAN_PASS_COLOR,
		TextSize = 20,
		TextStrokeTransparency = 0.4,
		Parent = billboard,
	})

	return label :: TextLabel
end

--[[
	Mirrors the server's crack allowance (Super Squeeze pass or an active
	Slick Coating) so the prompt never contradicts what the gate will do.
]]
local function crackAllowance(): number
	if localPlayer:GetAttribute("OwnsSuperSqueeze") == true then
		return GameConfig.passEffects.superSqueezeAllowance
	end

	local greaseUntil = localPlayer:GetAttribute("VentGreaseUntil")
	if typeof(greaseUntil) == "number" and greaseUntil > Workspace:GetServerTimeNow() then
		return GameConfig.passEffects.superSqueezeAllowance
	end

	return 1
end

local function updateLabel(barrier: BasePart, label: TextLabel, currentSize: number)
	if CollectionService:HasTag(barrier, SIZE_GATE_TAG) then
		local requiredSize = barrier:GetAttribute("RequiredSize")
		if typeof(requiredSize) ~= "number" then
			return
		end

		if SizeFormula.canPassGate(currentSize, requiredSize) then
			label.Text = "WALK THROUGH"
			label.TextColor3 = CAN_PASS_COLOR
		else
			label.Text = string.format("NEEDS %d SIZE - YOU HAVE %d", requiredSize, currentSize)
			label.TextColor3 = BLOCKED_GATE_COLOR
		end

		return
	end

	local maxAllowedSize = barrier:GetAttribute("MaxAllowedSize")
	if typeof(maxAllowedSize) ~= "number" then
		return
	end

	if SizeFormula.canFitCrack(currentSize, maxAllowedSize, crackAllowance()) then
		label.Text = "SQUEEZE THROUGH"
		label.TextColor3 = CAN_PASS_COLOR
	else
		label.Text = "TOO BIG - FIND A SHRINK PAD"
		label.TextColor3 = BLOCKED_CRACK_COLOR
	end
end

local function watchTag(tag: string)
	for _, barrier in ipairs(CollectionService:GetTagged(tag)) do
		if barrier:IsA("BasePart") then
			labelByBarrier[barrier] = createLabel(barrier)
		end
	end

	CollectionService:GetInstanceAddedSignal(tag):Connect(function(barrier)
		if barrier:IsA("BasePart") then
			labelByBarrier[barrier] = createLabel(barrier)
		end
	end)

	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(barrier)
		labelByBarrier[barrier] = nil
	end)
end

function GatePrompt.start()
	watchTag(SIZE_GATE_TAG)
	watchTag(SQUEEZE_CRACK_TAG)

	local sinceUpdate = 0

	RunService.Heartbeat:Connect(function(deltaSeconds)
		sinceUpdate += deltaSeconds
		if sinceUpdate < UPDATE_INTERVAL_SECONDS then
			return
		end
		sinceUpdate = 0

		local currentSize = localPlayer:GetAttribute("CurrentSize")
		if typeof(currentSize) ~= "number" then
			return
		end

		for barrier, label in pairs(labelByBarrier) do
			if barrier:IsDescendantOf(Workspace) then
				updateLabel(barrier, label, currentSize)
			end
		end
	end)
end

return GatePrompt
