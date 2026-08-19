--[[
	The first-session tutorial: a center-bottom card walking through
	TidetownConfig.tutorialSteps with Next and Skip. It only appears
	when the server-owned TutorialDone attribute settles to anything but
	true, and both finishing and skipping fire MarkTutorialDone so the
	card never returns on later sessions.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent
local TidetownUi = require(Client.TidetownUi)

local TidetownShared = ReplicatedStorage:WaitForChild("TidetownShared")
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

local OUTLINE_NAVY = Color3.fromRGB(31, 41, 74)
local CARD_COLOR = Color3.fromRGB(244, 250, 255)
local NEXT_COLOR = Color3.fromRGB(0, 148, 176)
local SKIP_COLOR = Color3.fromRGB(125, 140, 158)
local TITLE_COLOR = Color3.fromRGB(255, 167, 64)

-- The attribute arrives once the server finishes loading the player's
-- data; the tutorial waits this long before assuming a fresh account.
local ATTRIBUTE_WAIT_SECONDS = 10
local ATTRIBUTE_POLL_SECONDS = 0.25

local localPlayer = Players.LocalPlayer

local TutorialGui = {}

local function tutorialDoneAttribute(): boolean?
	local value = localPlayer:GetAttribute("TutorialDone")

	return if typeof(value) == "boolean" then value else nil
end

function TutorialGui.start()
	-- Bounded poll instead of a signal race: the attribute may never
	-- arrive (data outage), and the poll cannot leave a dangling
	-- connection behind when the timeout wins.
	local deadline = os.clock() + ATTRIBUTE_WAIT_SECONDS
	while tutorialDoneAttribute() == nil and os.clock() < deadline do
		task.wait(ATTRIBUTE_POLL_SECONDS)
	end

	if tutorialDoneAttribute() == true then
		return
	end

	local steps = TidetownConfig.tutorialSteps
	if #steps == 0 then
		return
	end

	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local doneRemote = TidetownRemotes.get("MarkTutorialDone") :: RemoteEvent

	local screenGui = TidetownUi.create("ScreenGui", {
		Name = "TidetownTutorial",
		ResetOnSpawn = false,
		DisplayOrder = 30,
		Parent = playerGui,
	}) :: ScreenGui

	-- Center-bottom, high enough to clear the CAST ring and the toast
	-- stack that both live along the bottom edge.
	local card = TidetownUi.create("Frame", {
		Name = "TutorialCard",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -290),
		Size = UDim2.new(0, 400, 0, 168),
		BackgroundColor3 = CARD_COLOR,
		BorderSizePixel = 0,
		Visible = false,
		Parent = screenGui,
	}) :: Frame
	TidetownUi.round(card, 16)
	TidetownUi.stroke(card, OUTLINE_NAVY, 3.5)

	local stepCounter = TidetownUi.create("TextLabel", {
		Name = "StepCounter",
		Position = UDim2.new(0, 14, 0, 10),
		Size = UDim2.new(1, -28, 0, 22),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 16,
		TextColor3 = TITLE_COLOR,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	}) :: TextLabel

	local bodyLabel = TidetownUi.create("TextLabel", {
		Name = "BodyLabel",
		Position = UDim2.new(0, 14, 0, 36),
		Size = UDim2.new(1, -28, 0, 68),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 18,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	}) :: TextLabel

	local nextButton = TidetownUi.create("TextButton", {
		Name = "NextButton",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -12),
		Size = UDim2.new(0, 110, 0, 40),
		BackgroundColor3 = NEXT_COLOR,
		BorderSizePixel = 0,
		Text = "Next",
		TextSize = 18,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Parent = card,
	}) :: TextButton
	TidetownUi.round(nextButton, 12)
	TidetownUi.stroke(nextButton, OUTLINE_NAVY, 3)
	TidetownUi.hoverPop(nextButton)

	local skipButton = TidetownUi.create("TextButton", {
		Name = "SkipButton",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -12),
		Size = UDim2.new(0, 90, 0, 40),
		BackgroundColor3 = SKIP_COLOR,
		BorderSizePixel = 0,
		Text = "Skip",
		TextSize = 18,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Parent = card,
	}) :: TextButton
	TidetownUi.round(skipButton, 12)
	TidetownUi.stroke(skipButton, OUTLINE_NAVY, 3)
	TidetownUi.hoverPop(skipButton)

	TidetownUi.cartoonify(card)

	local stepIndex = 1
	local finished = false

	local function showStep()
		stepCounter.Text = string.format("Tutorial · Step %d / %d", stepIndex, #steps)
		bodyLabel.Text = steps[stepIndex]
		nextButton.Text = if stepIndex == #steps then "Done!" else "Next"
	end

	local function finish()
		-- Both paths land here, so guard the remote against a Skip tap
		-- racing the final Next.
		if finished then
			return
		end

		finished = true
		doneRemote:FireServer()
		screenGui:Destroy()
	end

	nextButton.Activated:Connect(function()
		if stepIndex >= #steps then
			finish()
			return
		end

		stepIndex += 1
		showStep()
		TidetownUi.popOpen(card)
	end)

	skipButton.Activated:Connect(finish)

	showStep()
	TidetownUi.popOpen(card)
end

return TutorialGui
