--[[
	The first-join tutorial: one clear step at a time, Next and Skip, and
	never shown again once finished (the server persists the flag). Steps
	live in GameConfig so wording is a config edit, not a code change.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent
local UiBuilder = require(Client.UiBuilder)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local PANEL_COLOR = Color3.fromRGB(24, 30, 38)
local ACCENT_COLOR = Color3.fromRGB(76, 209, 55)

local localPlayer = Players.LocalPlayer

local TutorialGui = {}

local function markDone()
	task.spawn(function()
		local markTutorialDone = Remotes.get("MarkTutorialDone") :: RemoteEvent
		markTutorialDone:FireServer()
	end)
end

local function buildWindow(parent: Instance)
	local window = UiBuilder.create("Frame", {
		Name = "TutorialWindow",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -80),
		Size = UDim2.new(0, 460, 0, 150),
		BackgroundColor3 = PANEL_COLOR,
		BorderSizePixel = 0,
		Parent = parent,
	}) :: Frame
	UiBuilder.round(window, 14)
	local stroke = UiBuilder.stroke(window, ACCENT_COLOR, 2)
	UiBuilder.pulse(stroke)

	local stepLabel = UiBuilder.create("TextLabel", {
		Name = "StepLabel",
		Position = UDim2.new(0, 16, 0, 10),
		Size = UDim2.new(0, 120, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "",
		TextColor3 = ACCENT_COLOR,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window,
	}) :: TextLabel

	local bodyLabel = UiBuilder.create("TextLabel", {
		Name = "BodyLabel",
		Position = UDim2.new(0, 16, 0, 34),
		Size = UDim2.new(1, -32, 0, 62),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 17,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = window,
	}) :: TextLabel

	local nextButton = UiBuilder.create("TextButton", {
		Name = "NextButton",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -10),
		Size = UDim2.new(0, 110, 0, 34),
		BackgroundColor3 = ACCENT_COLOR,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		Text = "NEXT",
		TextColor3 = Color3.fromRGB(24, 30, 38),
		TextSize = 16,
		Parent = window,
	}) :: TextButton
	UiBuilder.round(nextButton, 10)
	UiBuilder.hoverPop(nextButton)

	local skipButton = UiBuilder.create("TextButton", {
		Name = "SkipButton",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -10),
		Size = UDim2.new(0, 80, 0, 34),
		BackgroundColor3 = Color3.fromRGB(72, 84, 96),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "SKIP",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 14,
		Parent = window,
	}) :: TextButton
	UiBuilder.round(skipButton, 10)

	local stepIndex = 1

	local function showStep()
		local steps = GameConfig.tutorialSteps
		stepLabel.Text = string.format("STEP %d OF %d", stepIndex, #steps)
		bodyLabel.Text = steps[stepIndex]
		nextButton.Text = if stepIndex == #steps then "DONE" else "NEXT"
	end

	nextButton.Activated:Connect(function()
		if stepIndex >= #GameConfig.tutorialSteps then
			markDone()
			window:Destroy()
		else
			stepIndex += 1
			showStep()
		end
	end)

	skipButton.Activated:Connect(function()
		markDone()
		window:Destroy()
	end)

	showStep()
	UiBuilder.popOpen(window)
end

function TutorialGui.start()
	-- TutorialDone arrives with the initial data load; wait briefly for
	-- it before deciding, defaulting to showing the tutorial.
	local deadline = os.clock() + 10
	while localPlayer:GetAttribute("TutorialDone") == nil and os.clock() < deadline do
		task.wait(0.25)
	end

	if localPlayer:GetAttribute("TutorialDone") == true then
		return
	end

	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = UiBuilder.create("ScreenGui", {
		Name = "TutorialGui",
		ResetOnSpawn = false,
		DisplayOrder = 8,
		Parent = playerGui,
	})

	buildWindow(screenGui)
end

return TutorialGui
