--[[
	The side buttons (Shop, Rebirth, and Shrink for pass owners), and the
	shop window: every game pass with live owned-state, plus each city's
	exclusive item, buyable only while standing in that city. Purchases
	prompt Roblox's own dialog; ownership that matters is verified
	server-side, so everything here is presentation.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent
local Toast = require(Client.Toast)
local UiBuilder = require(Client.UiBuilder)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local PANEL_COLOR = Color3.fromRGB(30, 39, 46)
local CARD_COLOR = Color3.fromRGB(47, 54, 64)
local ACCENT_COLOR = Color3.fromRGB(76, 209, 55)
local CITY_COLOR = Color3.fromRGB(156, 136, 255)
local DISABLED_COLOR = Color3.fromRGB(72, 84, 96)

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

local function createCard(parent: Instance, order: number, name: string, description: string)
	local card = UiBuilder.create("Frame", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(1, -16, 0, 84),
		BackgroundColor3 = CARD_COLOR,
		BorderSizePixel = 0,
		Parent = parent,
	})

	UiBuilder.create("UICorner", {
		CornerRadius = UDim.new(0, 10),
		Parent = card,
	})

	UiBuilder.create("TextLabel", {
		Name = "CardName",
		Position = UDim2.new(0, 12, 0, 8),
		Size = UDim2.new(1, -140, 0, 24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = name,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	UiBuilder.create("TextLabel", {
		Name = "CardDescription",
		Position = UDim2.new(0, 12, 0, 36),
		Size = UDim2.new(1, -140, 0, 40),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = description,
		TextColor3 = Color3.fromRGB(210, 218, 226),
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})

	local actionButton = UiBuilder.create("TextButton", {
		Name = "ActionButton",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0, 112, 0, 40),
		BackgroundColor3 = DISABLED_COLOR,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 16,
		Parent = card,
	})

	UiBuilder.create("UICorner", {
		CornerRadius = UDim.new(0, 10),
		Parent = actionButton,
	})

	return actionButton :: TextButton
end

local function createSectionHeader(parent: Instance, order: number, text: string)
	UiBuilder.create("TextLabel", {
		Name = text,
		LayoutOrder = order,
		Size = UDim2.new(1, -16, 0, 28),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = text,
		TextColor3 = Color3.fromRGB(210, 218, 226),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	})
end

local function addPassCard(parent: Instance, order: number, pass: { [string]: any })
	local button = createCard(parent, order, pass.name, pass.description)

	local function refresh()
		if localPlayer:GetAttribute("Owns" .. pass.key) == true then
			button.BackgroundColor3 = DISABLED_COLOR
			button.Text = "OWNED"
		elseif pass.gamePassId ~= 0 then
			button.BackgroundColor3 = ACCENT_COLOR
			button.Text = string.format("R$ %d", pass.robuxPrice)
		else
			button.BackgroundColor3 = DISABLED_COLOR
			button.Text = "COMING SOON"
		end
	end

	button.Activated:Connect(function()
		local owned = localPlayer:GetAttribute("Owns" .. pass.key) == true
		if not owned and pass.gamePassId ~= 0 then
			MarketplaceService:PromptGamePassPurchase(localPlayer, pass.gamePassId)
		end
	end)

	localPlayer:GetAttributeChangedSignal("Owns" .. pass.key):Connect(refresh)
	refresh()
end

local function addCityCard(
	parent: Instance,
	order: number,
	worldIndex: number,
	world: { [string]: any }
)
	local product = world.cityProduct
	local title = string.format("%s (%s)", product.name, world.name)
	local button = createCard(parent, order, title, product.description)

	local function refresh()
		local inCity = localPlayer:GetAttribute("CurrentWorld") == worldIndex

		if product.productId == 0 then
			button.BackgroundColor3 = DISABLED_COLOR
			button.Text = "COMING SOON"
		elseif inCity then
			button.BackgroundColor3 = CITY_COLOR
			button.Text = string.format("R$ %d", product.robuxPrice)
		else
			button.BackgroundColor3 = DISABLED_COLOR
			button.Text = string.format("VISIT %s", string.upper(world.name))
			button.TextSize = 12
		end

		if inCity then
			button.TextSize = 16
		end
	end

	button.Activated:Connect(function()
		local inCity = localPlayer:GetAttribute("CurrentWorld") == worldIndex
		if inCity and product.productId ~= 0 then
			MarketplaceService:PromptProductPurchase(localPlayer, product.productId)
		elseif not inCity then
			Toast.show(string.format("Travel to %s to buy its city item!", world.name))
		end
	end)

	localPlayer:GetAttributeChangedSignal("CurrentWorld"):Connect(refresh)
	refresh()
end

local function buildShopWindow(parent: Instance): Frame
	local window = UiBuilder.create("Frame", {
		Name = "ShopWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 420, 0, 440),
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

	UiBuilder.create("UIListLayout", {
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = cardList,
	})

	createSectionHeader(cardList, 0, "GAME PASSES")
	for order, pass in ipairs(GameConfig.passes) do
		addPassCard(cardList, order, pass)
	end

	createSectionHeader(cardList, 100, "CITY ITEMS")
	for worldIndex, world in ipairs(GameConfig.worlds) do
		addCityCard(cardList, 100 + worldIndex, worldIndex, world)
	end

	return window :: Frame
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
			local invoked, _success, message = pcall(function()
				return attemptRebirth:InvokeServer()
			end)

			if invoked and message ~= nil then
				Toast.show(message)
			elseif not invoked then
				Toast.show("Something went wrong -- try again.")
			end
		end)
	end)

	-- The Shrink button exists only for Instant Shrink owners, appearing
	-- the moment the pass is bought.
	local function refreshShrinkButton()
		local owns = localPlayer:GetAttribute("OwnsInstantShrink") == true
		local existing = buttonColumn:FindFirstChild("ShrinkButton")

		if owns and existing == nil then
			local shrinkButton = createSideButton(buttonColumn, 3, "Shrink")
			shrinkButton.Name = "ShrinkButton"
			shrinkButton.Activated:Connect(function()
				task.spawn(function()
					local requestInstantShrink = Remotes.get("RequestInstantShrink") :: RemoteEvent
					requestInstantShrink:FireServer()
				end)
			end)
		elseif not owns and existing ~= nil then
			existing:Destroy()
		end
	end

	localPlayer:GetAttributeChangedSignal("OwnsInstantShrink"):Connect(refreshShrinkButton)
	refreshShrinkButton()

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player, _gamePassId, wasPurchased)
			if player == localPlayer and wasPurchased then
				Toast.show("Purchase complete -- thank you!")
			end
		end
	)
end

return ShopGui
