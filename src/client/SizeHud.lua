--[[
	The always-on HUD: the big size readout with the Current-vs-Max bar
	(the visible face of the shrink mechanic), and the rebirth summary.
	Everything renders from the attributes SizeService publishes, so this
	module owns pixels and nothing else.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Client = script.Parent
local UiBuilder = require(Client.UiBuilder)

local BAR_TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PUNCH_TWEEN_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local MILESTONE_SIZE = 100

local localPlayer = Players.LocalPlayer

local SizeHud = {}

local function buildGui(): { [string]: Instance }
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = UiBuilder.create("ScreenGui", {
		Name = "SizeHud",
		ResetOnSpawn = false,
		Parent = playerGui,
	})

	local sizePanel = UiBuilder.create("Frame", {
		Name = "SizePanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.new(0, 260, 0, 78),
		BackgroundColor3 = Color3.fromRGB(30, 39, 46),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = screenGui,
	})

	UiBuilder.create("UICorner", {
		CornerRadius = UDim.new(0, 12),
		Parent = sizePanel,
	})

	local sizeLabel = UiBuilder.create("TextLabel", {
		Name = "SizeLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(1, -16, 0, 40),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "SIZE 0",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 32,
		Parent = sizePanel,
	})

	local barBackground = UiBuilder.create("Frame", {
		Name = "BarBackground",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -24, 0, 12),
		BackgroundColor3 = Color3.fromRGB(72, 84, 96),
		BorderSizePixel = 0,
		Parent = sizePanel,
	})

	UiBuilder.create("UICorner", {
		CornerRadius = UDim.new(1, 0),
		Parent = barBackground,
	})

	local barFill = UiBuilder.create("Frame", {
		Name = "BarFill",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(76, 209, 55),
		BorderSizePixel = 0,
		Parent = barBackground,
	})

	UiBuilder.create("UICorner", {
		CornerRadius = UDim.new(1, 0),
		Parent = barFill,
	})

	local rebirthLabel = UiBuilder.create("TextLabel", {
		Name = "RebirthLabel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.new(0, 220, 0, 28),
		BackgroundColor3 = Color3.fromRGB(30, 39, 46),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "Rebirths 0 - x1.0 growth",
		TextColor3 = Color3.fromRGB(253, 203, 110),
		TextSize = 16,
		Parent = screenGui,
	})

	UiBuilder.create("UICorner", {
		CornerRadius = UDim.new(0, 8),
		Parent = rebirthLabel,
	})

	return {
		sizeLabel = sizeLabel,
		barFill = barFill,
		rebirthLabel = rebirthLabel,
	}
end

function SizeHud.start()
	local gui = buildGui()
	local lastMilestone = 0

	local function refresh()
		local currentSize = localPlayer:GetAttribute("CurrentSize")
		local maxSize = localPlayer:GetAttribute("MaxSize")
		if typeof(currentSize) ~= "number" or typeof(maxSize) ~= "number" then
			return
		end

		gui.sizeLabel.Text = string.format("SIZE %d", currentSize)

		local fillFraction = if maxSize > 0 then currentSize / maxSize else 0
		local fillTween = TweenService:Create(gui.barFill, BAR_TWEEN_INFO, {
			Size = UDim2.new(math.clamp(fillFraction, 0, 1), 0, 1, 0),
		})
		fillTween:Play()

		-- Celebrate each 100 Max Size the first time it is reached.
		local milestone = math.floor(maxSize / MILESTONE_SIZE)
		if milestone > lastMilestone then
			lastMilestone = milestone

			gui.sizeLabel.TextSize = 44
			local punchTween = TweenService:Create(gui.sizeLabel, PUNCH_TWEEN_INFO, {
				TextSize = 32,
			})
			punchTween:Play()
		end
	end

	local function refreshRebirths()
		local rebirths = localPlayer:GetAttribute("Rebirths")
		local multiplier = localPlayer:GetAttribute("GrowthMultiplier")
		if typeof(rebirths) ~= "number" or typeof(multiplier) ~= "number" then
			return
		end

		gui.rebirthLabel.Text = string.format("Rebirths %d - x%.1f growth", rebirths, multiplier)
	end

	localPlayer:GetAttributeChangedSignal("CurrentSize"):Connect(refresh)
	localPlayer:GetAttributeChangedSignal("MaxSize"):Connect(refresh)
	localPlayer:GetAttributeChangedSignal("Rebirths"):Connect(refreshRebirths)
	localPlayer:GetAttributeChangedSignal("GrowthMultiplier"):Connect(refreshRebirths)

	refresh()
	refreshRebirths()
end

return SizeHud
