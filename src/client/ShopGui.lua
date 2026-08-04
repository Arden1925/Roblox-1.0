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
local QuestGui = require(Client.QuestGui)
local RebirthGui = require(Client.RebirthGui)
local SettingsGui = require(Client.SettingsGui)
local Toast = require(Client.Toast)
local UiBuilder = require(Client.UiBuilder)
local WheelGui = require(Client.WheelGui)

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

-- The circular icon buttons with captions that every simulator uses.
local SIDE_BUTTON_STYLES = {
	Shop = { icon = "\u{1F6D2}", color = Color3.fromRGB(235, 69, 44) },
	Rebirth = { icon = "\u{2728}", color = Color3.fromRGB(155, 89, 217) },
	Quests = { icon = "\u{1F4DC}", color = Color3.fromRGB(255, 177, 66) },
	Shrink = { icon = "\u{1F53D}", color = Color3.fromRGB(52, 172, 224) },
	Wheel = { icon = "\u{1F3A1}", color = Color3.fromRGB(253, 203, 110) },
	Settings = { icon = "\u{2699}", color = Color3.fromRGB(99, 110, 114) },
}

local function createSideButton(parent: Instance, order: number, text: string): TextButton
	local style = SIDE_BUTTON_STYLES[text]

	return UiBuilder.iconButton(parent, order, style.icon, text, style.color)
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
	UiBuilder.gloss(card)

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
	UiBuilder.bubbly(cardList)

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

	-- Value packs: escalating one-time bundles, banner-styled so the
	-- Starter Pack is the first thing a new player's eye lands on.
	createSectionHeader(cardList, order, "VALUE PACKS", FEATURED_COLOR)
	order += 1

	local function wireProductCard(button: TextButton, product: { [string]: any })
		if product.productId ~= 0 then
			button.BackgroundColor3 = ACCENT_COLOR
			button.Text = string.format("R$ %d", product.robuxPrice)
		else
			button.BackgroundColor3 = DISABLED_COLOR
			button.Text = "COMING SOON"
		end

		button.Activated:Connect(function()
			if product.productId ~= 0 then
				MarketplaceService:PromptProductPurchase(localPlayer, product.productId)
			else
				Toast.show("Packs unlock once the game is published!")
			end
		end)
	end

	-- Featured styling already gives every pack the shimmer and shining
	-- title treatment.
	for _, pack in ipairs(GameConfig.packs) do
		local row = createRow(cardList, order, 110)
		order += 1
		wireProductCard(
			createCard(row, 1, 1, pack.name, pack.description, FEATURED_COLOR, true),
			pack
		)
	end

	local luckRow = createRow(cardList, order, 110)
	order += 1
	wireProductCard(
		createCard(
			luckRow,
			1,
			1,
			GameConfig.serverLuck.name,
			GameConfig.serverLuck.description,
			FEATURED_COLOR,
			true
		),
		GameConfig.serverLuck
	)

	UiBuilder.cartoonizeWindow(window, Color3.fromRGB(235, 69, 44))

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
		Size = UDim2.new(0, 110, 0, 360),
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
	rebirthButton.Activated:Connect(RebirthGui.open)

	local questsButton = createSideButton(buttonColumn, 3, "Quests")
	questsButton.Activated:Connect(function()
		QuestGui.toggle()
	end)

	local wheelButton = createSideButton(buttonColumn, 5, "Wheel")
	wheelButton.Activated:Connect(function()
		WheelGui.toggle()
	end)

	local settingsButton = createSideButton(buttonColumn, 6, "Settings")
	settingsButton.Activated:Connect(function()
		SettingsGui.toggle()
	end)

	-- The Shrink button exists only for Instant Shrink owners, appearing
	-- the moment the pass is bought.
	local function refreshShrinkButton()
		local owns = localPlayer:GetAttribute("OwnsInstantShrink") == true
		local existing = buttonColumn:FindFirstChild("ShrinkButton")

		if owns and existing == nil then
			local shrinkButton = createSideButton(buttonColumn, 4, "Shrink")
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
