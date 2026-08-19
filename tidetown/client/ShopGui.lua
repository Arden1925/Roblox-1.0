--[[
	The shop window: five tabs (Eggs, Mounts, Surge Gear, Reef, Style)
	built from TidetownConfig plus the server's shop/mounts/reef syncs
	for ownership, levels, and the next reef slot price. Egg cards
	publish their exact hatch odds -- rarity weights normalized to
	percentages and colored by rarity -- because promised transparency
	is part of the game's pitch. Every buy button routes through the
	one BuyShopItem remote and simply toasts whatever verdict the
	server returns; buttons the player cannot afford are grayed live
	off the Shells/Stormglass attributes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent
local TidetownUi = require(Client.TidetownUi)
local Toast = require(Client.Toast)

local TidetownShared = ReplicatedStorage:WaitForChild("TidetownShared")
local CreatureCatalog = require(TidetownShared.CreatureCatalog)
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

local OUTLINE_NAVY = Color3.fromRGB(31, 41, 74)
local HEADER_COLOR = Color3.fromRGB(240, 120, 60)
local SIDE_BUTTON_COLOR = Color3.fromRGB(235, 69, 44)
local CARD_COLOR = Color3.fromRGB(232, 244, 252)
local BUY_COLOR = Color3.fromRGB(46, 125, 50)
local EQUIP_COLOR = Color3.fromRGB(66, 165, 245)
local DISABLED_COLOR = Color3.fromRGB(144, 152, 161)
local TAB_ACTIVE_COLOR = Color3.fromRGB(240, 120, 60)
local TAB_IDLE_COLOR = Color3.fromRGB(99, 110, 114)
local DEEP_ACCESS_COLOR = Color3.fromRGB(255, 179, 0)
local BUTTON_SLOT = 1

local TAB_ORDER = { "Eggs", "Mounts", "SurgeGear", "Reef", "Style" }
local TAB_TITLES: { [string]: string } = {
	Eggs = "Eggs",
	Mounts = "Mounts",
	SurgeGear = "Surge Gear",
	Reef = "Reef",
	Style = "Style",
}

local RARITY_ORDER = { "common", "rare", "epic", "legendary" }
local RARITY_TITLES: { [string]: string } = {
	common = "Common",
	rare = "Rare",
	epic = "Epic",
	legendary = "Legendary",
}

type CardLine = {
	text: string,
	color: Color3?,
	tall: boolean?,
}

type CardSpec = {
	key: string,
	title: string,
	lines: { CardLine },
	buttonText: string,
	buttonColor: Color3?,
	currency: string?,
	cost: number?,
	locked: boolean?,
}

local localPlayer = Players.LocalPlayer

-- Server-synced ownership and pricing. Config supplies the catalog;
-- these decide which buttons read Owned, Equipped, MAX, or a price.
local upgradeLevels: { [string]: number } = {}
local decorationsOwned: { string } = {}
local trailsOwned: { string } = {}
local equippedTrail = ""
local mountsOwned: { string } = {}
local reefSlotsUnlocked = TidetownConfig.reef.startingSlots
local reefNextSlotCost: number? = nil
local reefSynced = false
local shellsBalance = 0
local stormglassBalance = 0

local ShopGui = {}

local function listContains(list: { string }, value: string): boolean
	for _, entry in ipairs(list) do
		if entry == value then
			return true
		end
	end

	return false
end

local function readBalances()
	local shells = localPlayer:GetAttribute("Shells")
	shellsBalance = if typeof(shells) == "number" then shells else 0

	local stormglass = localPlayer:GetAttribute("Stormglass")
	stormglassBalance = if typeof(stormglass) == "number" then stormglass else 0
end

local function balanceFor(currency: string?): number
	return if currency == "stormglass" then stormglassBalance else shellsBalance
end

local function canAfford(spec: CardSpec): boolean
	local cost = spec.cost
	if cost == nil then
		return true
	end

	return balanceFor(spec.currency) >= cost
end

-- Odds are published as clean percentages: whole numbers stay whole
-- and fractional ones keep a single decimal so 12.5% never lies as 12%.
local function formatPercent(fraction: number): string
	local percent = fraction * 100
	if percent == math.floor(percent) then
		return string.format("%d%%", percent)
	end

	return string.format("%.1f%%", percent)
end

function ShopGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = TidetownUi.create("ScreenGui", {
		Name = "TidetownShopGui",
		ResetOnSpawn = false,
		DisplayOrder = 13,
		Parent = playerGui,
	}) :: ScreenGui

	-- The assigned slot in the shared left-edge icon column.
	local slotFrame = TidetownUi.create("Frame", {
		Name = "ShopButtonSlot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, (BUTTON_SLOT - 3.5) * 88),
		Size = UDim2.new(0, 64, 0, 80),
		BackgroundTransparency = 1,
		Parent = screenGui,
	}) :: Frame

	local shopButton =
		TidetownUi.iconButton(slotFrame, BUTTON_SLOT, "\u{1F6D2}", "Shop", SIDE_BUTTON_COLOR)

	local window = TidetownUi.create("Frame", {
		Name = "ShopWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 700, 0, 500),
		BorderSizePixel = 0,
		Visible = false,
		Parent = screenGui,
	}) :: Frame

	local closeButton = TidetownUi.create("TextButton", {
		Name = "CloseButton",
		BorderSizePixel = 0,
		Text = "X",
		TextSize = 20,
		Parent = window,
	}) :: TextButton

	TidetownUi.cartoonizeWindow(window, HEADER_COLOR, "Shop")

	local tabRow = TidetownUi.create("Frame", {
		Name = "TabRow",
		Position = UDim2.new(0, 16, 0, 44),
		Size = UDim2.new(1, -32, 0, 36),
		BackgroundTransparency = 1,
		Parent = window,
	}) :: Frame

	TidetownUi.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabRow,
	})

	local scroll = TidetownUi.create("ScrollingFrame", {
		Name = "CardGrid",
		Position = UDim2.new(0, 16, 0, 90),
		Size = UDim2.new(1, -32, 1, -106),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = window,
	}) :: ScrollingFrame

	TidetownUi.create("UIGridLayout", {
		CellSize = UDim2.new(0, 206, 0, 230),
		CellPadding = UDim2.new(0, 10, 0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})

	TidetownUi.bubbly(scroll)

	local buyRemote = TidetownRemotes.get("BuyShopItem") :: RemoteFunction
	local syncRemote = TidetownRemotes.get("SyncState") :: RemoteEvent
	-- The join-burst state push can fire before this listener exists
	-- and queued events drain only into the first connection, so ask
	-- the server to resend our slices. task.defer runs after the
	-- Connect below, so the reply always finds the handler.
	task.defer(function()
		local requestSync = TidetownRemotes.get("RequestSync") :: RemoteEvent
		requestSync:FireServer("shop")
		requestSync:FireServer("mounts")
		requestSync:FireServer("reef")
	end)

	local activeTab = "Eggs"
	local tabButtons: { [string]: TextButton } = {}
	local cardRefreshers: { () -> () } = {}
	local buying = false

	local function purchase(itemKey: string)
		-- One purchase in flight at a time; a lagging InvokeServer
		-- must not let a double-click double-spend.
		if buying then
			return
		end

		buying = true
		local ok, message = buyRemote:InvokeServer(itemKey)
		buying = false

		local text = if typeof(message) == "string" then message else "The shop is busy"
		if ok == true then
			Toast.push(text, "good")
		else
			Toast.push(text, "bad")
		end
	end

	local function buildCard(order: number, spec: CardSpec)
		local card = TidetownUi.create("Frame", {
			Name = "Card_" .. spec.key,
			LayoutOrder = order,
			BackgroundColor3 = CARD_COLOR,
			BorderSizePixel = 0,
			Parent = scroll,
		}) :: Frame
		TidetownUi.round(card, 14)
		TidetownUi.stroke(card, OUTLINE_NAVY, 2.5)

		TidetownUi.create("TextLabel", {
			Name = "CardTitle",
			Position = UDim2.new(0, 10, 0, 8),
			Size = UDim2.new(1, -20, 0, 24),
			BackgroundTransparency = 1,
			Text = spec.title,
			TextSize = 17,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})

		local lineY = 38
		for index, line in ipairs(spec.lines) do
			local height = if line.tall == true then 42 else 20
			TidetownUi.create("TextLabel", {
				Name = "Line" .. index,
				Position = UDim2.new(0, 10, 0, lineY),
				Size = UDim2.new(1, -20, 0, height),
				BackgroundTransparency = 1,
				Text = line.text,
				TextSize = 14,
				TextColor3 = if line.color ~= nil
					then line.color
					else Color3.fromRGB(255, 255, 255),
				TextWrapped = line.tall == true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Parent = card,
			})
			lineY += height + 2
		end

		local buyButton = TidetownUi.create("TextButton", {
			Name = "BuyButton",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -20, 0, 32),
			BackgroundColor3 = BUY_COLOR,
			BorderSizePixel = 0,
			Text = spec.buttonText,
			TextSize = 16,
			Parent = card,
		}) :: TextButton
		TidetownUi.round(buyButton, 10)
		TidetownUi.stroke(buyButton, OUTLINE_NAVY, 2.5)
		TidetownUi.hoverPop(buyButton)

		local function refresh()
			local usable = spec.locked ~= true and canAfford(spec)
			if usable then
				buyButton.BackgroundColor3 = if spec.buttonColor ~= nil
					then spec.buttonColor
					else BUY_COLOR
				buyButton.AutoButtonColor = true
			else
				buyButton.BackgroundColor3 = DISABLED_COLOR
				buyButton.AutoButtonColor = false
			end
		end

		buyButton.Activated:Connect(function()
			if spec.locked == true then
				return
			end

			if not canAfford(spec) then
				local currencyName = if spec.currency == "stormglass"
					then "Stormglass"
					else "Shells"
				Toast.push("Not enough " .. currencyName, "bad")

				return
			end

			purchase(spec.key)
		end)

		table.insert(cardRefreshers, refresh)
		refresh()
	end

	local function buildEggsTab()
		for index, eggType in ipairs(TidetownConfig.eggs.types) do
			local totalWeight = 0
			for _, rarity in ipairs(RARITY_ORDER) do
				totalWeight += eggType.rarityWeights[rarity] or 0
			end

			local lines: { CardLine } = {}
			for _, rarity in ipairs(RARITY_ORDER) do
				local weight = eggType.rarityWeights[rarity] or 0
				-- Zero-weight rarities are left off the card entirely:
				-- publishing "Legendary 0%" reads like a taunt.
				if weight > 0 and totalWeight > 0 then
					table.insert(lines, {
						text = RARITY_TITLES[rarity] .. " " .. formatPercent(weight / totalWeight),
						color = CreatureCatalog.rarityColor(rarity),
					})
				end
			end
			table.insert(lines, {
				text = string.format("Hatches after %d catches", eggType.catchesToHatch),
			})

			buildCard(index, {
				key = eggType.key,
				title = eggType.name,
				lines = lines,
				buttonText = string.format("%d \u{1F41A}", eggType.shellCost),
				currency = "shells",
				cost = eggType.shellCost,
			})
		end
	end

	local function buildMountsTab()
		for index, mount in ipairs(TidetownConfig.mounts.owned) do
			local owned = listContains(mountsOwned, mount.key)

			local lines: { CardLine } = {
				{ text = string.format("Speed %d studs/s", mount.speedStudsPerSecond) },
			}
			if mount.deepAccess then
				table.insert(lines, { text = "Deep Reef access", color = DEEP_ACCESS_COLOR })
			end
			table.insert(lines, { text = "Ride the flood at high tide", tall = true })

			buildCard(index, {
				key = mount.key,
				title = mount.name,
				lines = lines,
				buttonText = if owned
					then "Owned"
					else string.format("%d \u{26A1}", mount.stormglassCost),
				currency = "stormglass",
				cost = if owned then nil else mount.stormglassCost,
				locked = owned,
			})
		end
	end

	local function buildSurgeGearTab()
		for index, upgrade in ipairs(TidetownConfig.shop.upgrades) do
			local level = upgradeLevels[upgrade.key] or 0
			local maxLevel = #upgrade.costs
			local maxed = level >= maxLevel

			buildCard(index, {
				key = upgrade.key,
				title = upgrade.name,
				lines = {
					{ text = upgrade.description, tall = true },
					{ text = string.format("Lv %d/%d", level, maxLevel) },
				},
				buttonText = if maxed
					then "MAX"
					else string.format("%d \u{26A1}", upgrade.costs[level + 1]),
				currency = "stormglass",
				cost = if maxed then nil else upgrade.costs[level + 1],
				locked = maxed,
			})
		end
	end

	local function buildReefTab()
		local slotCost = reefNextSlotCost
		local slotButtonText: string
		local slotLocked = false
		if not reefSynced then
			slotButtonText = "..."
			slotLocked = true
		elseif slotCost == nil then
			slotButtonText = "Fully expanded"
			slotLocked = true
		else
			slotButtonText = string.format("%d \u{1F41A}", slotCost)
		end

		buildCard(1, {
			key = "reefSlot",
			title = "Reef Slot",
			lines = {
				{
					text = string.format(
						"Slots open: %d/%d",
						reefSlotsUnlocked,
						TidetownConfig.reef.maxSlots
					),
				},
				{ text = "Room for one more reef worker earning Shells", tall = true },
			},
			buttonText = slotButtonText,
			currency = "shells",
			cost = slotCost,
			locked = slotLocked,
		})

		for index, decoration in ipairs(TidetownConfig.shop.decorations) do
			local owned = listContains(decorationsOwned, decoration.key)

			buildCard(index + 1, {
				key = decoration.key,
				title = decoration.name,
				lines = { { text = "Decorates your reef plot", tall = true } },
				buttonText = if owned
					then "Owned"
					else string.format("%d \u{1F41A}", decoration.shellCost),
				currency = "shells",
				cost = if owned then nil else decoration.shellCost,
				locked = owned,
			})
		end
	end

	local function buildStyleTab()
		for index, trail in ipairs(TidetownConfig.shop.trails) do
			local owned = listContains(trailsOwned, trail.key)
			local equipped = equippedTrail == trail.key
			local trailColor = Color3.fromRGB(trail.color[1], trail.color[2], trail.color[3])

			local buttonText: string
			local buttonColor: Color3? = nil
			local cost: number? = nil
			local locked = false
			if equipped then
				buttonText = "Equipped"
				locked = true
			elseif owned then
				buttonText = "Equip"
				buttonColor = EQUIP_COLOR
			else
				buttonText = string.format("%d \u{1F41A}", trail.shellCost)
				cost = trail.shellCost
			end

			buildCard(index, {
				key = trail.key,
				title = trail.name,
				lines = {
					{ text = "\u{25CF} \u{25CF} \u{25CF}", color = trailColor },
					{ text = "A glowing wake behind you", tall = true },
				},
				buttonText = buttonText,
				buttonColor = buttonColor,
				currency = "shells",
				cost = cost,
				locked = locked,
			})
		end
	end

	local tabBuilders: { [string]: () -> () } = {
		Eggs = buildEggsTab,
		Mounts = buildMountsTab,
		SurgeGear = buildSurgeGearTab,
		Reef = buildReefTab,
		Style = buildStyleTab,
	}

	local function refreshTabButtons()
		for key, button in pairs(tabButtons) do
			button.BackgroundColor3 = if key == activeTab then TAB_ACTIVE_COLOR else TAB_IDLE_COLOR
		end
	end

	local function rebuildActiveTab()
		table.clear(cardRefreshers)
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		tabBuilders[activeTab]()
		refreshTabButtons()
	end

	for order, tabKey in ipairs(TAB_ORDER) do
		local tabButton = TidetownUi.create("TextButton", {
			Name = tabKey .. "Tab",
			LayoutOrder = order,
			Size = UDim2.new(0, 118, 0, 36),
			BackgroundColor3 = TAB_IDLE_COLOR,
			BorderSizePixel = 0,
			Text = TAB_TITLES[tabKey],
			TextSize = 16,
			Parent = tabRow,
		}) :: TextButton
		TidetownUi.round(tabButton, 10)
		TidetownUi.stroke(tabButton, OUTLINE_NAVY, 2.5)

		tabButtons[tabKey] = tabButton
		tabButton.Activated:Connect(function()
			if activeTab ~= tabKey then
				activeTab = tabKey
				rebuildActiveTab()
			end
		end)
	end

	local function refreshCards()
		for _, refresh in ipairs(cardRefreshers) do
			refresh()
		end
	end

	shopButton.Activated:Connect(function()
		if window.Visible then
			window.Visible = false
		else
			TidetownUi.popOpen(window)
		end
	end)

	closeButton.Activated:Connect(function()
		window.Visible = false
	end)

	localPlayer:GetAttributeChangedSignal("Shells"):Connect(function()
		readBalances()
		refreshCards()
	end)

	localPlayer:GetAttributeChangedSignal("Stormglass"):Connect(function()
		readBalances()
		refreshCards()
	end)

	syncRemote.OnClientEvent:Connect(function(kind, payload)
		if typeof(payload) ~= "table" then
			return
		end

		if kind == "shop" then
			upgradeLevels = if typeof(payload.upgrades) == "table" then payload.upgrades else {}
			decorationsOwned = if typeof(payload.decorationsOwned) == "table"
				then payload.decorationsOwned
				else {}
			trailsOwned = if typeof(payload.trailsOwned) == "table" then payload.trailsOwned else {}
			equippedTrail = if typeof(payload.equippedTrail) == "string"
				then payload.equippedTrail
				else ""
			if typeof(payload.mountsOwned) == "table" then
				mountsOwned = payload.mountsOwned
			end
		elseif kind == "mounts" then
			mountsOwned = if typeof(payload.mountsOwned) == "table" then payload.mountsOwned else {}
		elseif kind == "reef" then
			reefSynced = true
			reefNextSlotCost = if typeof(payload.nextSlotCost) == "number"
				then payload.nextSlotCost
				else nil
			if typeof(payload.slotsUnlocked) == "number" then
				reefSlotsUnlocked = payload.slotsUnlocked
			end
		else
			return
		end

		-- Prices, levels, and ownership all live on the cards, so any
		-- of the three syncs redraws whichever tab is showing.
		rebuildActiveTab()
	end)

	readBalances()
	rebuildActiveTab()
end

return ShopGui
