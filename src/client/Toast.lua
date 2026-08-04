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
local activeFades: { Tween } = {}

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

	UiBuilder.cartoonify(screenGui)

	-- Returning the local (not the module-level optional) keeps the
	-- return type a guaranteed TextLabel for the type checker.
	local built = toastLabel :: TextLabel
	label = built

	return built
end

function Toast.show(message: string)
	local toastLabel = getLabel()

	activeToken += 1
	local token = activeToken

	-- A fade already in flight would keep dragging the new message
	-- toward invisible; kill it before resetting.
	for _, fade in ipairs(activeFades) do
		fade:Cancel()
	end
	table.clear(activeFades)

	toastLabel.Text = message
	toastLabel.TextTransparency = 0
	toastLabel.BackgroundTransparency = 0.25

	-- The cartoon outline does not obey TextTransparency, so it must be
	-- reset and faded explicitly or every toast leaves a permanent dark
	-- ghost of itself at the bottom of the screen.
	local outline = toastLabel:FindFirstChild("TextOutline")
	if outline ~= nil and outline:IsA("UIStroke") then
		outline.Transparency = 0
	end

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
		table.insert(activeFades, fadeTween)

		if outline ~= nil and outline:IsA("UIStroke") then
			local outlineFade = TweenService:Create(outline, FADE_INFO, { Transparency = 1 })
			outlineFade:Play()
			table.insert(activeFades, outlineFade)
		end
	end)
end

return Toast
