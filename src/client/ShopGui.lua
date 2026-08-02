--[[
	The side buttons (Shop, Rebirth, and Shrink for pass owners), the shop
	window built from GameConfig.passes, and the toast that shows server
	replies. Purchases prompt Roblox's own dialog; ownership that matters
	is verified server-side, so everything here is presentation.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Client = script.Parent
local UiBuilder = require(Client.UiBuilder)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local PANEL_COLOR = Color3.fromRGB(30, 39, 46)
local ACCENT_COLOR = Color3.fromRGB(76, 209, 55)
local DISABLED_COLOR = Color3.fromRGB(72, 84, 96)

local TOAST_VISIBLE_SECONDS = 2.5
local TOAST_FADE_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local localPlayer = Players.LocalPlayer

local ShopGui = {}

local function createSideButton(parent: Instance, order: number, text: string): TextButton
	local button = UiBuilder.create("TextButton", {
		Name = text .. "Button",
		LayoutOrder = order,
		Size = UDim2.new(0, 110, 0, 40),
		BackgroundColor3 = PANEL_COLOR,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = text,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 18,
		Parent = parent,
	})

	UiBuilder.create("UICorner", {
		CornerRadius = UDim.new(0, 10),
		Parent = button,
	})

	return button :: TextButton
end

local function createPassCard(parent: Instance, order: number, pass: { [string]: any })
	local card = UiBuilder.create("Frame", {
		Name = pass.key,
		LayoutOrder = order,
		Size = UDim2.new(1, -16, 0, 84),
		BackgroundColor3 = Color3.fromRGB(47, 54, 64),
		BorderSizePixel = 0,
		Parent = parent,
	})

	UiBuilder.create("UICorner", {
		CornerRadius = UDim.new(0, 10),
		Parent = card,
	})

	UiBuilder.create("TextLabel", {
		Name = "PassName",
		Position = UDim2.new(0, 12, 0, 8),
		Size = UDim2.new(1, -140, 0, 24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = pass.name,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	UiBuilder.create("TextLabel", {
		Name = "PassDescription",
		Position = UDim2.new(0, 12, 0, 36),
		Size = UDim2.new(1, -140, 0, 40),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = pass.description,
		TextColor3 = Color3.fromRGB(210, 218, 226),
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})

	local available = pass.gamePassId ~= 0
	local buyButton = UiBuilder.create("TextButton", {
		Name = "BuyButton",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0, 110, 0, 40),
		BackgroundColor3 = if available then ACCENT_COLOR else DISABLED_COLOR,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = if available then string.format("R$ %d", pass.robuxPrice) else "COMING SOON",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = if available then 18 else 13,
		Parent = card,
	})

	UiBuilder.create("UICorner", {
		CornerRadius = UDim.new(0, 10),
		Parent = buyButton,
	})

	if available then
		buyButton.Activated:Connect(function()
			MarketplaceService:PromptGamePassPurchase(localPlayer, pass.gamePassId)
		end)
	end
end

local function buildShopWindow(parent: Instance): Frame
	local window = UiBuilder.create("Frame", {
		Name = "ShopWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 380, 0, 320),
		BackgroundColor3 = PANEL_COLOR,
		BorderSizePixel = 0,
		Visible = false,
		Parent = parent,
	})

	UiBuilder.create("UICorner", {
		CornerRadius = UDim.new(0, 14),
		Parent = window,
	})

	UiBuilder.create("TextLabel", {
		Name = "Title",
		Position = UDim2.new(0, 16, 0, 8),
		Size = UDim2.new(1, -60, 0, 32),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "SHOP",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window,
	})

	local closeButton = UiBuilder.create("TextButton", {
		Name = "CloseButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.new(0, 32, 0, 32),
		BackgroundColor3 = Color3.fromRGB(232, 65, 24),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "X",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 18,
		Parent = window,
	})

	UiBuilder.create("UICorner", {
		CornerRadius = UDim.new(0, 8),
		Parent = closeButton,
	})

	closeButton.Activated:Connect(function()
		window.Visible = false
	end)

	local cardList = UiBuilder.create("ScrollingFrame", {
		Name = "CardList",
		Position = UDim2.new(0, 8, 0, 48),
		Size = UDim2.new(1, -16, 1, -56),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = window,
	})

	local listLayout = UiBuilder.create("UIListLayout", {
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = cardList,
	})

	for order, pass in ipairs(GameConfig.passes) do
		createPassCard(cardList, order, pass)
	end

	return window :: Frame
end

local function instantShrinkPassId(): number
	for _, pass in ipairs(GameConfig.passes) do
		if pass.key == "InstantShrink" then
			return pass.gamePassId
		end
	end

	return 0
end

function ShopGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = UiBuilder.create("ScreenGui", {
		Name = "ShopGui",
		ResetOnSpawn = false,
		Parent = playerGui,
	})

	local buttonColumn = UiBuilder.create("Frame", {
		Name = "ButtonColumn",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.new(0, 110, 0, 200),
		BackgroundTransparency = 1,
		Parent = screenGui,
	})

	UiBuilder.create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = buttonColumn,
	})

	local toast = UiBuilder.create("TextLabel", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.new(0, 420, 0, 40),
		BackgroundColor3 = PANEL_COLOR,
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

	local toastToken = 0
	local function showToast(message: string)
		toastToken += 1
		local token = toastToken

		toast.Text = message
		toast.TextTransparency = 0
		toast.BackgroundTransparency = 0.25

		task.delay(TOAST_VISIBLE_SECONDS, function()
			-- A newer toast owns the label now; let it manage the fade.
			if token ~= toastToken then
				return
			end

			local fadeTween = TweenService:Create(toast, TOAST_FADE_INFO, {
				TextTransparency = 1,
				BackgroundTransparency = 1,
			})
			fadeTween:Play()
		end)
	end

	local shopWindow = buildShopWindow(screenGui)

	local shopButton = createSideButton(buttonColumn, 1, "Shop")
	shopButton.Activated:Connect(function()
		shopWindow.Visible = not shopWindow.Visible
	end)

	local rebirthButton = createSideButton(buttonColumn, 2, "Rebirth")
	rebirthButton.Activated:Connect(function()
		task.spawn(function()
			local attemptRebirth = Remotes.get("AttemptRebirth") :: RemoteFunction

			-- InvokeServer throws if the server errors mid-call; a toast
			-- beats a silent dead button.
			local invoked, success, message = pcall(function()
				return attemptRebirth:InvokeServer()
			end)

			if invoked then
				showToast(message)
			else
				showToast("Something went wrong -- try again.")
			end
		end)
	end)

	local function addShrinkButtonIfOwned()
		local passId = instantShrinkPassId()
		if passId == 0 then
			return
		end

		-- Display-only check; the server verifies again on every use.
		-- UserOwnsGamePassAsync throws on Marketplace outages.
		local success, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(localPlayer.UserId, passId)
		end)

		if success and owns == true and buttonColumn:FindFirstChild("ShrinkButton") == nil then
			local shrinkButton = createSideButton(buttonColumn, 3, "Shrink")
			shrinkButton.Name = "ShrinkButton"
			shrinkButton.Activated:Connect(function()
				task.spawn(function()
					local requestInstantShrink = Remotes.get("RequestInstantShrink") :: RemoteEvent
					requestInstantShrink:FireServer()
				end)
			end)
		end
	end

	task.spawn(addShrinkButtonIfOwned)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player, gamePassId, wasPurchased)
			if player == localPlayer and wasPurchased then
				showToast("Purchase complete -- thank you!")
				task.spawn(addShrinkButtonIfOwned)
			end
		end
	)
end

return ShopGui
