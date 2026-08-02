--[[
	One shared toast label at the bottom of the screen for short messages
	from any system. A single label (instead of one per module) means
	messages never stack unreadably; the newest always wins.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Client = script.Parent
local UiBuilder = require(Client.UiBuilder)

local VISIBLE_SECONDS = 2.5
local FADE_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local localPlayer = Players.LocalPlayer

local label: TextLabel? = nil
local activeToken = 0

local Toast = {}

local function getLabel(): TextLabel
	if label ~= nil then
		return label
	end

	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = UiBuilder.create("ScreenGui", {
		Name = "ToastGui",
		ResetOnSpawn = false,
		DisplayOrder = 10,
		Parent = playerGui,
	})

	local toastLabel = UiBuilder.create("TextLabel", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.new(0, 440, 0, 40),
		BackgroundColor3 = Color3.fromRGB(30, 39, 46),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 17,
		TextTransparency = 1,
		TextWrapped = true,
		Parent = screenGui,
	})

	UiBuilder.create("UICorner", {
		CornerRadius = UDim.new(0, 10),
		Parent = toastLabel,
	})

	label = toastLabel :: TextLabel

	return label
end

function Toast.show(message: string)
	local toastLabel = getLabel()

	activeToken += 1
	local token = activeToken

	toastLabel.Text = message
	toastLabel.TextTransparency = 0
	toastLabel.BackgroundTransparency = 0.25

	task.delay(VISIBLE_SECONDS, function()
		-- A newer toast owns the label now; let it manage the fade.
		if token ~= activeToken then
			return
		end

		local fadeTween = TweenService:Create(toastLabel, FADE_INFO, {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})
		fadeTween:Play()
	end)
end

return Toast
