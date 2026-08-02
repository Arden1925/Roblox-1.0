--[[
	The side buttons (Shop, Rebirth, and Shrink for pass owners) and the
	Robux shop window: featured passes get big gradient banner cards, the
	rest sit two per row, and each world's city item card lights up only
	while you stand in that city. Purchases prompt Roblox's own dialog;
	ownership that matters is verified server-side.
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

local PANEL_COLOR = Color3.fromRGB(24, 30, 38)
local CARD_COLOR = Color3.fromRGB(47, 54, 64)
local ACCENT_COLOR = Color3.fromRGB(76, 209, 55)
local CITY_COLOR = Color3.fromRGB(156, 136, 255)
local FEATURED_COLOR = Color3.fromRGB(253, 203, 110)
local DISABLED_COLOR = Color3.fromRGB(72, 84, 96)

-- Passes that earn the big banner treatment.
local FEATURED_KEYS = { Vip = true, SizeMaster = true }

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
	}) :: TextButton
	UiBuilder.round(button, 10)
	UiBuilder.hoverPop(button)

	return button
end

-- A row frame the vertical list stacks; cards go inside side by side.
local function createRow(parent: Instance, order: number, height: number): Frame
	local row = UiBuilder.create("Frame", {
		Name = "Row" .. order,
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, height),
		BackgroundTransparency = 1,
		Parent = parent,
	}) :: Frame

	UiBuilder.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})

	return row
end

local function createCard(
	parent: Instance,
	order: number,
	widthScale: number,
	name: string,
	description: string,
	accent: Color3,
	featured: boolean
): TextButton
	-- Featured cards break the house style on purpose: razor-sharp
	-- corners, a hot gradient, a sweeping shimmer, and rainbow-shining
	-- names -- the storefront look that grabs eyes.
	local card = UiBuilder.create("Frame", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(widthScale, -8, 1, 0),
		BackgroundColor3 = CARD_COLOR,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = parent,
	})
	if featured then
		UiBuilder.stroke(card, Color3.fromRGB(255, 60, 120), 3)
		UiBuilder.gradient(card, Color3.fromRGB(255, 94, 58), Color3.fromRGB(120, 40, 190))
		UiBuilder.shimmer(card)
	else
		UiBuilder.round(card, 12)
		UiBuilder.stroke(card, accent, 1)
	end

	local nameLabel = UiBuilder.create("TextLabel", {
		Name = "CardName",
		Position = UDim2.new(0, 12, 0, 8),
		Size = UDim2.new(1, -24, 0, if featured then 28 else 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = name,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = if featured then 24 else 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	}) :: TextLabel

	if featured then
		UiBuilder.shineText(nameLabel)
	end

	UiBuilder.create("TextLabel", {
		Name = "CardDescription",
		Position = UDim2.new(0, 12, 0, if featured then 38 else 32),
		Size = UDim2.new(1, -24, 0, 34),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = description,
		TextColor3 = Color3.fromRGB(210, 218, 226),
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})

	local actionButton = UiBuilder.create("TextButton", {
		Name = "ActionButton",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -8),
		Size = UDim2.new(0, if featured then 150 else 110, 0, 34),
		BackgroundColor3 = DISABLED_COLOR,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 15,
		Parent = card,
	}) :: TextButton
	UiBuilder.round(actionButton, 8)
	UiBuilder.hoverPop(actionButton)

	return actionButton
end

local function wirePassCard(button: TextButton, pass: { [string]: any })
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

local function wireCityCard(button: TextButton, worldIndex: number, world: { [string]: any })
	local product = world.cityProduct

	local function refresh()
		local inCity = localPlayer:GetAttribute("CurrentWorld") == worldIndex

		if product.productId == 0 then
			button.BackgroundColor3 = DISABLED_COLOR
			button.Text = "COMING SOON"
			button.TextSize = 13
		elseif inCity then
			button.BackgroundColor3 = CITY_COLOR
			button.Text = string.format("R$ %d", product.robuxPrice)
			button.TextSize = 15
		else
			button.BackgroundColor3 = DISABLED_COLOR
			button.Text = string.format("VISIT %s", string.upper(world.name))
			button.TextSize = 11
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

local function createSectionHeader(parent: Instance, order: number, text: string, color: Color3)
	UiBuilder.create("TextLabel", {
		Name = text,
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, 30),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = text,
		TextColor3 = color,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	})
end

local function buildShopWindow(parent: Instance): Frame
	local window = UiBuilder.create("Frame", {
		Name = "ShopWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 620, 0, 500),
		BackgroundColor3 = PANEL_COLOR,
		BorderSizePixel = 0,
		Visible = false,
		Parent = parent,
	}) :: Frame
	UiBuilder.round(window, 16)
	UiBuilder.stroke(window, ACCENT_COLOR, 2)
	UiBuilder.gradient(window, Color3.fromRGB(38, 48, 62), PANEL_COLOR)

	UiBuilder.create("TextLabel", {
		Name = "Title",
		Position = UDim2.new(0, 20, 0, 10),
		Size = UDim2.new(0.5, 0, 0, 34),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "SHOP",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window,
	})

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
		Parent = window,
	}) :: TextButton
	UiBuilder.round(closeButton, 8)
	UiBuilder.hoverPop(closeButton)

	closeButton.Activated:Connect(function()
		window.Visible = false
	end)

	local cardList = UiBuilder.create("ScrollingFrame", {
		Name = "CardList",
		Position = UDim2.new(0, 12, 0, 52),
		Size = UDim2.new(1, -24, 1, -64),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = window,
	})

	UiBuilder.create("UIListLayout", {
		Padding = UDim.new(0, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = cardList,
	})

	-- Featured banners first, then the standard passes two per row.
	createSectionHeader(cardList, 0, "FEATURED", FEATURED_COLOR)

	local order = 1
	for _, pass in ipairs(GameConfig.passes) do
		if FEATURED_KEYS[pass.key] then
			local row = createRow(cardList, order, 110)
			order += 1
			wirePassCard(
				createCard(row, 1, 1, pass.name, pass.description, FEATURED_COLOR, true),
				pass
			)
		end
	end

	createSectionHeader(cardList, order, "GAME PASSES", ACCENT_COLOR)
	order += 1

	local currentRow: Frame? = nil
	local slotInRow = 2
	for _, pass in ipairs(GameConfig.passes) do
		if not FEATURED_KEYS[pass.key] then
			if slotInRow == 2 then
				currentRow = createRow(cardList, order, 96)
				order += 1
				slotInRow = 0
			end
			slotInRow += 1

			wirePassCard(
				createCard(
					currentRow :: Frame,
					slotInRow,
					0.5,
					pass.name,
					pass.description,
					ACCENT_COLOR,
					false
				),
				pass
			)
		end
	end

	createSectionHeader(cardList, order, "CITY ITEMS", CITY_COLOR)
	order += 1

	slotInRow = 2
	for worldIndex, world in ipairs(GameConfig.worlds) do
		if slotInRow == 2 then
			currentRow = createRow(cardList, order, 96)
			order += 1
			slotInRow = 0
		end
		slotInRow += 1

		local product = world.cityProduct
		wireCityCard(
			createCard(
				currentRow :: Frame,
				slotInRow,
				0.5,
				string.format("%s (%s)", product.name, world.name),
				product.description,
				CITY_COLOR,
				false
			),
			worldIndex,
			world
		)
	end

	return window
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
		if shopWindow.Visible then
			shopWindow.Visible = false
		else
			UiBuilder.popOpen(shopWindow)
		end
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
