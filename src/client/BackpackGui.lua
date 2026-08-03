--[[
	The backpack: a pulsing button on the left edge, opening a large
	tabbed inventory -- Pets (equip and unequip), Boosts (upgrade levels
	and running timed effects), and a placeholder tab for whatever comes
	next. Reads the inventory the server publishes as attributes; every
	action is a request the server validates.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Client = script.Parent
local PetViewport = require(Client.PetViewport)
local Toast = require(Client.Toast)
local UiBuilder = require(Client.UiBuilder)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local PetCatalog = require(Shared.PetCatalog)
local PetModels = require(Shared.PetModels)
local Remotes = require(Shared.Remotes)

local CARD_COLOR = Color3.fromRGB(47, 54, 64)
local ACCENT_COLOR = Color3.fromRGB(255, 121, 198)
local EQUIPPED_COLOR = Color3.fromRGB(76, 209, 55)

local TABS = { "Pets", "Boosts", "Soon" }

local localPlayer = Players.LocalPlayer

local BackpackGui = {}

local function timedEffectLines(): { string }
	local lines = {}
	local now = Workspace:GetServerTimeNow()

	for _, effectKey in ipairs({
		"GrowthPotion",
		"SpeedPotion",
		"JumpPotion",
		"CoinPotion",
		"VentGrease",
		"EmberShield",
		"CloudBoots",
		"MysteryGrowth",
	}) do
		local untilTime = localPlayer:GetAttribute(effectKey .. "Until")
		if typeof(untilTime) == "number" and untilTime > now then
			table.insert(
				lines,
				string.format("%s -- %d min left", effectKey, math.ceil((untilTime - now) / 60))
			)
		end
	end

	return lines
end

local function fillPetsTab(page: ScrollingFrame)
	local petsJson = localPlayer:GetAttribute("PetsJson")
	local namesJson = localPlayer:GetAttribute("PetNamesJson")
	local equippedIndex = localPlayer:GetAttribute("EquippedPetIndex")
	local petIds = if typeof(petsJson) == "string" then HttpService:JSONDecode(petsJson) else {}
	local nicknames = if typeof(namesJson) == "string"
		then HttpService:JSONDecode(namesJson)
		else {}

	if #petIds == 0 then
		UiBuilder.create("TextLabel", {
			Size = UDim2.new(1, -20, 0, 60),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = "No pets yet -- hatch an egg at a world's egg capsule!",
			TextColor3 = Color3.fromRGB(178, 190, 195),
			TextSize = 17,
			TextWrapped = true,
			Parent = page,
		})

		return
	end

	for order, petId in ipairs(petIds) do
		local info = PetCatalog.infoFor(petId)
		if info == nil then
			continue
		end

		-- Duplicates of one species are separate pets, so cards key off
		-- the inventory index, and equip requests send that index.
		local isEquipped = order == equippedIndex
		local rank = PetModels.tierRank(info.tierName)
		local nickname = nicknames[tostring(order)]
		local mutation = info.mutation

		-- Every card gets the same outline treatment (thickness 2, tier
		-- color; green when equipped) so the grid reads as one set.
		local card = UiBuilder.create("Frame", {
			Name = "Pet" .. order,
			LayoutOrder = if isEquipped then 0 else order,
			Size = UDim2.new(0, 150, 0, 196),
			BackgroundColor3 = CARD_COLOR,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Parent = page,
		})
		UiBuilder.round(card, 12)

		local cardStroke =
			UiBuilder.stroke(card, if isEquipped then EQUIPPED_COLOR else info.tierColor, 2)

		-- Hard-to-get tiers announce themselves: a breathing aura stroke,
		-- and rainbow shine on the very top tier.
		if rank >= 4 then
			UiBuilder.pulse(cardStroke)
		end

		-- The 3D pet, spinning in its frame; click it for a happy twirl.
		local viewportButton = UiBuilder.create("TextButton", {
			Name = "ViewportButton",
			Position = UDim2.new(0, 8, 0, 6),
			Size = UDim2.new(1, -16, 0, 80),
			BackgroundColor3 = Color3.fromRGB(28, 34, 44),
			BorderSizePixel = 0,
			Text = "",
			Parent = card,
		}) :: TextButton
		UiBuilder.round(viewportButton, 10)

		local viewport =
			PetViewport.create(viewportButton, petId, UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0))

		viewportButton.Activated:Connect(function()
			if viewport ~= nil then
				PetViewport.celebrate(viewport)
			end
			UiBuilder.popOpen(card)
		end)

		-- Nickname (or species) on top; a nicknamed pet shows its
		-- species in the tier line below.
		local nameLabel = UiBuilder.create("TextLabel", {
			Name = "PetName",
			Position = UDim2.new(0, 8, 0, 88),
			Size = UDim2.new(1, -16, 0, 18),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Text = if nickname ~= nil then nickname else info.baseName,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextScaled = true,
			Parent = card,
		}) :: TextLabel

		if info.tierName == "Ultra" then
			UiBuilder.shineText(nameLabel)
		end

		-- The mutation sits right under the name, in its own color,
		-- exactly like the hatch reveal showed it.
		if mutation ~= nil then
			UiBuilder.create("TextLabel", {
				Name = "PetMutation",
				Position = UDim2.new(0, 8, 0, 106),
				Size = UDim2.new(1, -16, 0, 14),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBlack,
				Text = "\u{2726} " .. string.upper(mutation.name) .. " \u{2726}",
				TextColor3 = mutation.color,
				TextSize = 12,
				Parent = card,
			})
		end

		UiBuilder.create("TextLabel", {
			Name = "PetTier",
			Position = UDim2.new(0, 8, 0, if mutation ~= nil then 120 else 108),
			Size = UDim2.new(1, -16, 0, 34),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = string.format(
				"%s (%s)\n+%d%% growth",
				info.baseName,
				info.tierName,
				info.bonus * 100
			),
			TextColor3 = info.tierColor,
			TextSize = 12,
			Parent = card,
		})

		local equipButton = UiBuilder.create("TextButton", {
			Name = "EquipButton",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -16, 0, 30),
			BackgroundColor3 = if isEquipped then EQUIPPED_COLOR else ACCENT_COLOR,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Text = if isEquipped then "UNEQUIP" else "EQUIP",
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 15,
			Parent = card,
		})
		UiBuilder.round(equipButton, 8)
		UiBuilder.hoverPop(equipButton)

		equipButton.Activated:Connect(function()
			task.spawn(function()
				local equipPet = Remotes.get("EquipPet") :: RemoteFunction

				-- InvokeServer throws if the server errors mid-call.
				local invoked, _success, message = pcall(function()
					return equipPet:InvokeServer(if isEquipped then 0 else order)
				end)

				Toast.show(if invoked then message else "Something went wrong -- try again.")
			end)
		end)
	end
end

local function fillBoostsTab(page: ScrollingFrame)
	for order, upgrade in ipairs(GameConfig.upgrades) do
		local level = localPlayer:GetAttribute("Upgrade" .. upgrade.key)
		if typeof(level) ~= "number" then
			level = 0
		end

		local card = UiBuilder.create("Frame", {
			Name = upgrade.key,
			LayoutOrder = order,
			Size = UDim2.new(0, 220, 0, 84),
			BackgroundColor3 = CARD_COLOR,
			BorderSizePixel = 0,
			Parent = page,
		})
		UiBuilder.round(card, 12)
		UiBuilder.stroke(card, Color3.fromRGB(0, 206, 201), 1)

		UiBuilder.create("TextLabel", {
			Position = UDim2.new(0, 10, 0, 8),
			Size = UDim2.new(1, -20, 0, 24),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Text = string.format("%s  Lv.%d/%d", upgrade.name, level, upgrade.maxLevel),
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})

		UiBuilder.create("TextLabel", {
			Position = UDim2.new(0, 10, 0, 36),
			Size = UDim2.new(1, -20, 0, 40),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = upgrade.description .. " Buy levels at any world Station.",
			TextColor3 = Color3.fromRGB(178, 190, 195),
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})
	end

	local effectLines = timedEffectLines()
	local effectText = if #effectLines > 0
		then table.concat(effectLines, "\n")
		else "No timed boosts running right now."

	local effectsCard = UiBuilder.create("Frame", {
		Name = "ActiveEffects",
		LayoutOrder = 99,
		Size = UDim2.new(0, 220, 0, 110),
		BackgroundColor3 = CARD_COLOR,
		BorderSizePixel = 0,
		Parent = page,
	})
	UiBuilder.round(effectsCard, 12)
	UiBuilder.stroke(effectsCard, ACCENT_COLOR, 1)

	UiBuilder.create("TextLabel", {
		Position = UDim2.new(0, 10, 0, 8),
		Size = UDim2.new(1, -20, 0, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "ACTIVE BOOSTS",
		TextColor3 = ACCENT_COLOR,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = effectsCard,
	})

	UiBuilder.create("TextLabel", {
		Position = UDim2.new(0, 10, 0, 34),
		Size = UDim2.new(1, -20, 1, -42),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = effectText,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = effectsCard,
	})
end

local function fillSoonTab(page: ScrollingFrame)
	UiBuilder.create("TextLabel", {
		Size = UDim2.new(1, -20, 0, 80),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "More categories coming soon -- trails, titles, and beyond!",
		TextColor3 = Color3.fromRGB(178, 190, 195),
		TextSize = 17,
		TextWrapped = true,
		Parent = page,
	})
end

local FILLERS = {
	Pets = fillPetsTab,
	Boosts = fillBoostsTab,
	Soon = fillSoonTab,
}

function BackpackGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = UiBuilder.create("ScreenGui", {
		Name = "BackpackGui",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		Parent = playerGui,
	})

	-- The window fills most of the screen: inventory is a destination,
	-- not a popup. Slightly translucent gray so the world glows through
	-- without turning the panel flat.
	local window = UiBuilder.create("Frame", {
		Name = "BackpackWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0.72, 0, 0.72, 0),
		BackgroundColor3 = Color3.fromRGB(58, 63, 72),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Visible = false,
		Parent = screenGui,
	})
	UiBuilder.round(window, 16)
	UiBuilder.stroke(window, ACCENT_COLOR, 2)

	UiBuilder.create("TextLabel", {
		Name = "Title",
		Position = UDim2.new(0, 20, 0, 10),
		Size = UDim2.new(0.5, 0, 0, 34),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "BACKPACK",
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
	})
	UiBuilder.round(closeButton, 8)
	UiBuilder.hoverPop(closeButton)

	local tabBar = UiBuilder.create("Frame", {
		Name = "TabBar",
		Position = UDim2.new(0, 20, 0, 52),
		Size = UDim2.new(1, -40, 0, 38),
		BackgroundTransparency = 1,
		Parent = window,
	})

	UiBuilder.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabBar,
	})

	local page = UiBuilder.create("ScrollingFrame", {
		Name = "Page",
		Position = UDim2.new(0, 20, 0, 100),
		Size = UDim2.new(1, -40, 1, -116),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = window,
	}) :: ScrollingFrame

	UiBuilder.create("UIGridLayout", {
		CellPadding = UDim2.new(0, 12, 0, 12),
		CellSize = UDim2.new(0, 150, 0, 150),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = page,
	})

	local activeTab = "Pets"
	local tabButtons: { [string]: TextButton } = {}

	local function refreshPage()
		for _, child in ipairs(page:GetChildren()) do
			if child:IsA("Frame") or child:IsA("TextLabel") then
				child:Destroy()
			end
		end

		local gridLayout = page:FindFirstChildOfClass("UIGridLayout")
		if gridLayout ~= nil then
			-- Boost cards are wider than pet cards; the grid adapts per
			-- tab so nothing overlaps.
			gridLayout.CellSize = if activeTab == "Pets"
				then UDim2.new(0, 150, 0, 196)
				else UDim2.new(0, 220, 0, 110)
		end

		FILLERS[activeTab](page)

		for tabName, tabButton in pairs(tabButtons) do
			tabButton.BackgroundColor3 = if tabName == activeTab then ACCENT_COLOR else CARD_COLOR
		end
	end

	for order, tabName in ipairs(TABS) do
		local tabButton = UiBuilder.create("TextButton", {
			Name = tabName .. "Tab",
			LayoutOrder = order,
			Size = UDim2.new(0, 110, 1, 0),
			BackgroundColor3 = CARD_COLOR,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Text = string.upper(tabName),
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 16,
			Parent = tabBar,
		}) :: TextButton
		UiBuilder.round(tabButton, 10)
		UiBuilder.hoverPop(tabButton)
		tabButtons[tabName] = tabButton

		tabButton.Activated:Connect(function()
			activeTab = tabName
			refreshPage()
		end)
	end

	closeButton.Activated:Connect(function()
		window.Visible = false
	end)

	-- The backpack button: bottom-left circular icon, always breathing so
	-- new players notice it.
	local buttonHolder = UiBuilder.create("Frame", {
		Name = "BackpackButtonHolder",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -8),
		Size = UDim2.new(0, 64, 0, 80),
		BackgroundTransparency = 1,
		Parent = screenGui,
	})

	local backpackButton =
		UiBuilder.iconButton(buttonHolder, 1, "\u{1F392}", "Backpack", ACCENT_COLOR)

	local buttonStroke = UiBuilder.stroke(backpackButton, Color3.fromRGB(255, 255, 255), 1)
	UiBuilder.pulse(buttonStroke)

	backpackButton.Activated:Connect(function()
		if window.Visible then
			window.Visible = false
		else
			refreshPage()
			UiBuilder.popOpen(window)
		end
	end)

	-- Live refresh while open, so hatching, naming, or equipping shows
	-- instantly.
	for _, attributeName in ipairs({ "PetsJson", "PetNamesJson", "EquippedPetIndex" }) do
		localPlayer:GetAttributeChangedSignal(attributeName):Connect(function()
			if window.Visible then
				refreshPage()
			end
		end)
	end

	UiBuilder.cartoonizeWindow(window, Color3.fromRGB(255, 121, 198))
	UiBuilder.cartoonify(buttonHolder)
end

return BackpackGui
