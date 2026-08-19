--[[
	Small stacking notifications in the lower third of the screen: catch
	results, purchase errors, bounty completions. Server systems reach it
	through the Toast remote; client modules call Toast.push directly.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Client = script.Parent
local TidetownUi = require(Client.TidetownUi)

local TidetownShared = ReplicatedStorage:WaitForChild("TidetownShared")
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

local SLIDE_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_INFO = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HOLD_SECONDS = 2.6
local MAXIMUM_VISIBLE = 4

local STYLE_COLORS: { [string]: Color3 } = {
	info = Color3.fromRGB(38, 70, 110),
	good = Color3.fromRGB(46, 125, 50),
	bad = Color3.fromRGB(183, 28, 28),
	rare = Color3.fromRGB(123, 31, 162),
}

local listFrame: Frame? = nil

local Toast = {}

local function ensureGui(): Frame
	if listFrame ~= nil then
		return listFrame
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = TidetownUi.create("ScreenGui", {
		Name = "TidetownToasts",
		ResetOnSpawn = false,
		DisplayOrder = 40,
		Parent = playerGui,
	}) :: ScreenGui

	local frame = TidetownUi.create("Frame", {
		Name = "ToastList",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.82, 0),
		Size = UDim2.new(0, 420, 0, 200),
		BackgroundTransparency = 1,
		Parent = screenGui,
	}) :: Frame

	TidetownUi.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})

	listFrame = frame

	return frame
end

function Toast.push(message: string, style: string?)
	local frame = ensureGui()

	-- Drop the oldest card when the stack is full, so spam can never
	-- fill the screen.
	local cards = {}
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(cards, child)
		end
	end
	if #cards >= MAXIMUM_VISIBLE then
		table.sort(cards, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		cards[1]:Destroy()
	end

	local color = STYLE_COLORS[style or "info"] or STYLE_COLORS.info

	local card = TidetownUi.create("TextLabel", {
		Name = "Toast",
		LayoutOrder = os.clock() * 1000,
		Size = UDim2.new(0, 400, 0, 40),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.08,
		Text = message,
		TextSize = 18,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextWrapped = true,
		Parent = frame,
	}) :: TextLabel
	TidetownUi.round(card, 12)
	TidetownUi.stroke(card, Color3.fromRGB(31, 41, 74), 2.5)
	TidetownUi.cartoonify(card)

	local scale = TidetownUi.create("UIScale", { Scale = 0.6, Parent = card }) :: UIScale
	TweenService:Create(scale, SLIDE_INFO, { Scale = 1 }):Play()

	task.delay(HOLD_SECONDS, function()
		if card.Parent == nil then
			return
		end

		local fade = TweenService:Create(card, FADE_INFO, {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})
		fade:Play()
		fade.Completed:Wait()
		card:Destroy()
	end)
end

function Toast.start()
	ensureGui()

	local remote = TidetownRemotes.get("Toast") :: RemoteEvent
	remote.OnClientEvent:Connect(function(message, style)
		if typeof(message) == "string" then
			Toast.push(message, if typeof(style) == "string" then style else nil)
		end
	end)
end

return Toast
