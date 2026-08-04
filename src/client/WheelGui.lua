--[[
	The prize wheel window: a board-game spinner whose pointer whirls
	around fixed reward bubbles and stops on the slice the server
	rolled. Opens from the wheel on the Main Island or its side button.
	Free-spin timing arrives as attributes; the actual roll is entirely
	server-side, so the animation is presentation only.
]]

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Client = script.Parent
local Toast = require(Client.Toast)
local UiBuilder = require(Client.UiBuilder)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local PANEL_COLOR = Color3.fromRGB(24, 30, 38)
local GOLD_COLOR = Color3.fromRGB(253, 203, 110)
local READY_COLOR = Color3.fromRGB(76, 209, 55)
local LOCKED_COLOR = Color3.fromRGB(72, 84, 96)
local DISC_COLOR = Color3.fromRGB(58, 63, 72)

local WHEEL_DIAMETER = 260
local BUBBLE_DIAMETER = 60
local BUBBLE_RADIUS = 97
local SPIN_SECONDS = 3.4
local EXTRA_TURNS = 3

local localPlayer = Players.LocalPlayer

local WheelGui = {}

local function rewardColor(reward: { [string]: any }): Color3
	return Color3.fromRGB(reward.color[1], reward.color[2], reward.color[3])
end

local function buildWheel(window: Frame): Frame
	local wheelArea = UiBuilder.create("Frame", {
		Name = "WheelArea",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.new(0, WHEEL_DIAMETER, 0, WHEEL_DIAMETER),
		BackgroundColor3 = DISC_COLOR,
		BorderSizePixel = 0,
		Parent = window,
	}) :: Frame
	UiBuilder.round(wheelArea, WHEEL_DIAMETER // 2)
	UiBuilder.stroke(wheelArea, GOLD_COLOR, 3)

	local rewardCount = #GameConfig.wheel.rewards
	for rewardIndex, reward in ipairs(GameConfig.wheel.rewards) do
		local angle = math.rad(-90 + (rewardIndex - 1) * 360 / rewardCount)
		local bubble = UiBuilder.create("Frame", {
			Name = "Bubble" .. rewardIndex,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(
				0.5,
				math.cos(angle) * BUBBLE_RADIUS,
				0.5,
				math.sin(angle) * BUBBLE_RADIUS
			),
			Size = UDim2.new(0, BUBBLE_DIAMETER, 0, BUBBLE_DIAMETER),
			BackgroundColor3 = rewardColor(reward),
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = wheelArea,
		})
		UiBuilder.round(bubble, BUBBLE_DIAMETER // 2)

		UiBuilder.create("TextLabel", {
			Size = UDim2.new(1, -6, 1, -6),
			Position = UDim2.new(0, 3, 0, 3),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Text = reward.label,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 11,
			TextWrapped = true,
			ZIndex = 3,
			Parent = bubble,
		})
	end

	-- The pointer rides its own full-size frame: rotating that frame
	-- swings the arrow around the rim while every bubble stays upright.
	local pointer = UiBuilder.create("Frame", {
		Name = "Pointer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = wheelArea,
	}) :: Frame

	UiBuilder.create("TextLabel", {
		Name = "Arrow",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 42),
		Size = UDim2.new(0, 34, 0, 34),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "\u{1F53A}",
		TextSize = 30,
		ZIndex = 4,
		Parent = pointer,
	})

	local hubCap = UiBuilder.create("Frame", {
		Name = "HubCap",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 52, 0, 52),
		BackgroundColor3 = GOLD_COLOR,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = wheelArea,
	})
	UiBuilder.round(hubCap, 26)
	UiBuilder.create("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "\u{1F3A1}",
		TextSize = 26,
		ZIndex = 6,
		Parent = hubCap,
	})

	return pointer
end

function WheelGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = UiBuilder.create("ScreenGui", {
		Name = "WheelGui",
		ResetOnSpawn = false,
		DisplayOrder = 6,
		Parent = playerGui,
	})

	local window = UiBuilder.create("Frame", {
		Name = "WheelWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 420, 0, 470),
		BackgroundColor3 = PANEL_COLOR,
		BorderSizePixel = 0,
		Visible = false,
		Parent = screenGui,
	}) :: Frame
	UiBuilder.round(window, 16)
	UiBuilder.stroke(window, GOLD_COLOR, 2)

	local closeButton = UiBuilder.create("TextButton", {
		Name = "CloseButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.new(0, 34, 0, 34),
		BackgroundColor3 = Color3.fromRGB(232, 65, 24),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "X",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 18,
		ZIndex = 7,
		Parent = window,
	}) :: TextButton
	UiBuilder.round(closeButton, 8)
	UiBuilder.hoverPop(closeButton)

	closeButton.Activated:Connect(function()
		window.Visible = false
	end)

	local pointer = buildWheel(window)

	local statusLabel = UiBuilder.create("TextLabel", {
		Name = "StatusLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 330),
		Size = UDim2.new(1, -32, 0, 24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 16,
		Parent = window,
	}) :: TextLabel

	local spinButton = UiBuilder.create("TextButton", {
		Name = "SpinButton",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 366),
		Size = UDim2.new(1, -32, 0, 52),
		BackgroundColor3 = READY_COLOR,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		Text = "SPIN!",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 20,
		Parent = window,
	}) :: TextButton
	UiBuilder.round(spinButton, 12)
	UiBuilder.hoverPop(spinButton)

	UiBuilder.cartoonizeWindow(window, GOLD_COLOR, "PRIZE WHEEL")

	local spinning = false

	local function isReady(): (boolean, number, number)
		local nextAt = localPlayer:GetAttribute("WheelNextSpinAt")
		local credits = localPlayer:GetAttribute("WheelSpinCredits")
		local nextTime = if typeof(nextAt) == "number" then nextAt else 0
		local creditCount = if typeof(credits) == "number" then credits else 0

		return creditCount > 0 or os.time() >= nextTime, nextTime, creditCount
	end

	local function refresh()
		if spinning then
			return
		end

		local ready, nextTime, creditCount = isReady()
		local product = GameConfig.wheel.spinProduct
		if ready then
			statusLabel.Text = if creditCount > 0
				then string.format("EXTRA SPINS READY: %d", creditCount)
				else "FREE SPIN READY!"
			spinButton.Text = "SPIN!"
			spinButton.BackgroundColor3 = READY_COLOR
		else
			local waitSeconds = math.max(nextTime - os.time(), 0)
			statusLabel.Text = string.format(
				"Next free spin in %dh %02dm %02ds",
				waitSeconds // 3600,
				waitSeconds % 3600 // 60,
				waitSeconds % 60
			)
			spinButton.Text = string.format("SPIN NOW -- R$ %d", product.robuxPrice)
			spinButton.BackgroundColor3 = LOCKED_COLOR
		end
	end

	local function animateTo(rewardIndex: number)
		local rewardCount = #GameConfig.wheel.rewards
		local restRotation = pointer.Rotation % 360
		pointer.Rotation = restRotation
		local target = EXTRA_TURNS * 360 + (rewardIndex - 1) * 360 / rewardCount

		local spinTween = TweenService:Create(
			pointer,
			TweenInfo.new(SPIN_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Rotation = target }
		)
		spinTween:Play()
		spinTween.Completed:Wait()
	end

	spinButton.Activated:Connect(function()
		if spinning then
			return
		end

		local ready = isReady()
		if not ready then
			local product = GameConfig.wheel.spinProduct
			if product.productId ~= 0 then
				MarketplaceService:PromptProductPurchase(localPlayer, product.productId)
			else
				Toast.show("Extra spins unlock once the game is published!")
			end

			return
		end

		spinning = true
		statusLabel.Text = "SPINNING..."
		task.spawn(function()
			local spinWheel = Remotes.get("SpinWheel") :: RemoteFunction

			-- InvokeServer throws if the server errors mid-call.
			local invoked, success, result = pcall(function()
				return spinWheel:InvokeServer()
			end)

			if invoked and success and typeof(result) == "table" then
				animateTo(result.rewardIndex)
				Toast.show("You won " .. tostring(result.label) .. "!")
			else
				Toast.show(
					if invoked and not success
						then tostring(result)
						else "Something went wrong -- try again."
				)
			end

			spinning = false
			refresh()
		end)
	end)

	-- Live countdown while the window is open.
	task.spawn(function()
		while screenGui.Parent ~= nil do
			if window.Visible then
				refresh()
			end
			task.wait(1)
		end
	end)

	for _, attributeName in ipairs({ "WheelNextSpinAt", "WheelSpinCredits" }) do
		localPlayer:GetAttributeChangedSignal(attributeName):Connect(refresh)
	end

	WheelGui.toggle = function()
		if window.Visible then
			window.Visible = false
		else
			refresh()
			UiBuilder.popOpen(window)
		end
	end

	local function watchWheel(wheel: Instance)
		local prompt = wheel:FindFirstChildOfClass("ProximityPrompt")
		if prompt == nil then
			return
		end

		prompt.Triggered:Connect(function(playerWhoTriggered)
			if playerWhoTriggered == localPlayer then
				WheelGui.toggle()
			end
		end)
	end

	for _, wheel in ipairs(CollectionService:GetTagged("SpinWheel")) do
		watchWheel(wheel)
	end
	CollectionService:GetInstanceAddedSignal("SpinWheel"):Connect(watchWheel)
end

-- Replaced at start(); declared so ShopGui can wire its side button.
WheelGui.toggle = function() end

return WheelGui
