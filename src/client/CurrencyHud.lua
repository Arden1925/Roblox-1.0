--[[
	The left-edge counters: coins (with a little bounce whenever the
	balance rises) and current speed setting. Reads the attributes the
	server publishes; owns pixels and nothing else.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Client = script.Parent
local UiBuilder = require(Client.UiBuilder)

local COIN_COLOR = Color3.fromRGB(253, 203, 110)
local SPEED_COLOR = Color3.fromRGB(0, 206, 201)
local PANEL_COLOR = Color3.fromRGB(30, 39, 46)

local BOUNCE_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local localPlayer = Players.LocalPlayer

local CurrencyHud = {}

local function createCounter(
	parent: Instance,
	order: number,
	icon: string,
	color: Color3
): TextLabel
	local frame = UiBuilder.create("Frame", {
		Name = icon .. "Counter",
		LayoutOrder = order,
		Size = UDim2.new(0, 130, 0, 34),
		BackgroundColor3 = PANEL_COLOR,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Parent = parent,
	})
	UiBuilder.round(frame, 10)
	UiBuilder.stroke(frame, color, 1)

	UiBuilder.create("TextLabel", {
		Name = "Icon",
		Position = UDim2.new(0, 6, 0, 0),
		Size = UDim2.new(0, 26, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = icon,
		TextColor3 = color,
		TextSize = 18,
		Parent = frame,
	})

	local valueLabel = UiBuilder.create("TextLabel", {
		Name = "Value",
		Position = UDim2.new(0, 34, 0, 0),
		Size = UDim2.new(1, -40, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "0",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})

	return valueLabel :: TextLabel
end

function CurrencyHud.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = UiBuilder.create("ScreenGui", {
		Name = "CurrencyHud",
		ResetOnSpawn = false,
		Parent = playerGui,
	})

	local column = UiBuilder.create("Frame", {
		Name = "CounterColumn",
		Position = UDim2.new(0, 12, 0, 60),
		Size = UDim2.new(0, 130, 0, 80),
		BackgroundTransparency = 1,
		Parent = screenGui,
	})

	UiBuilder.create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = column,
	})

	local coinsLabel = createCounter(column, 1, "$", COIN_COLOR)
	local speedLabel = createCounter(column, 2, ">>", SPEED_COLOR)

	local lastCoins = 0
	local function refreshCoins()
		local coins = localPlayer:GetAttribute("Coins")
		if typeof(coins) ~= "number" then
			return
		end

		coinsLabel.Text = tostring(coins)

		if coins > lastCoins then
			coinsLabel.TextSize = 22
			TweenService:Create(coinsLabel, BOUNCE_INFO, { TextSize = 17 }):Play()
		end
		lastCoins = coins
	end

	local function refreshSpeed()
		local speed = localPlayer:GetAttribute("SpeedSetting")
		if typeof(speed) == "number" then
			speedLabel.Text = string.format("Speed %d", speed)
		end
	end

	localPlayer:GetAttributeChangedSignal("Coins"):Connect(refreshCoins)
	localPlayer:GetAttributeChangedSignal("SpeedSetting"):Connect(refreshSpeed)

	refreshCoins()
	refreshSpeed()
end

return CurrencyHud
