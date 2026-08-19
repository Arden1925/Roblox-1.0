--[[
	The Tidepedia window: the permanent collection log. One tab per
	zone, gated by total entries so the log itself is the key to new
	water; a grid of species cards where caught creatures pose in a
	viewport and uncaught ones stay dark silhouettes (their rarity
	stroke still teases what tier hides there); and a header that sums
	the log into the two numbers it feeds back into play -- Keeper Rank
	and the hard-capped luck buff.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent
local TidetownUi = require(Client.TidetownUi)

local TidetownShared = ReplicatedStorage:WaitForChild("TidetownShared")
local CreatureCatalog = require(TidetownShared.CreatureCatalog)
local CreatureModels = require(TidetownShared.CreatureModels)
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

local OUTLINE_NAVY = Color3.fromRGB(31, 41, 74)
local HEADER_COLOR = Color3.fromRGB(94, 53, 177)
local BUTTON_COLOR = Color3.fromRGB(126, 87, 194)
local CARD_COLOR = Color3.fromRGB(232, 244, 252)
local UNCAUGHT_COLOR = Color3.fromRGB(44, 52, 78)
local TAB_COLOR = Color3.fromRGB(84, 110, 122)
local TAB_ACTIVE_COLOR = Color3.fromRGB(0, 148, 176)
local BUTTON_SLOT = 4

-- Tab order mirrors the unlock ladder so the next gate is always the
-- next tab to the right.
local ZONE_TABS = {
	{ key = "Beach", label = "Beach" },
	{ key = "Town", label = "Town" },
	{ key = "Cave", label = "Cave" },
	{ key = "DeepReef", label = "Deep Reef" },
}

local localPlayer = Players.LocalPlayer

-- Server-synced Tidepedia state; gates default to config so the window
-- renders sensibly before the first sync lands.
local entriesState: { [string]: number } = {}
local entryCount = 0
local luckPercentState = 0
local keeperRankState = 0
local gatesState: { [string]: number } = TidetownConfig.tidepedia.zoneEntryGates
local selectedZone = "Beach"

local TidepediaGui = {}

--[[
	Frames a centered model in a fresh ViewportFrame using the model's
	real bounds (the PetViewport math). A fixed slight yaw instead of a
	spin keeps a full grid of species free per frame.
]]
local function buildCardViewport(parent: Instance, speciesKey: string)
	local model = CreatureModels.build(speciesKey, 2)
	model:PivotTo(CFrame.Angles(0, math.rad(25), 0))

	local viewport = TidetownUi.create("ViewportFrame", {
		Name = "SpeciesViewport",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(1, -12, 0, 96),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 200, 210),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-1, -1, -0.5),
		Parent = parent,
	}) :: ViewportFrame

	local _, boxSize = model:GetBoundingBox()
	local radius = math.max(boxSize.X, boxSize.Y, boxSize.Z)
	local distance = radius * 1.4 + 0.6

	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.new(Vector3.new(0, boxSize.Y * 0.18, -distance), Vector3.new(0, 0, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	model.Parent = viewport
end

local function buildSpeciesCard(parent: Instance, index: number, species: CreatureCatalog.Species)
	local caught = entriesState[species.key] ~= nil

	local card = TidetownUi.create("Frame", {
		Name = "Card_" .. species.key,
		LayoutOrder = index,
		BackgroundColor3 = if caught then CARD_COLOR else UNCAUGHT_COLOR,
		BorderSizePixel = 0,
		Parent = parent,
	}) :: Frame
	TidetownUi.round(card, 14)
	TidetownUi.stroke(card, CreatureCatalog.rarityColor(species.rarity), 3)

	if caught then
		buildCardViewport(card, species.key)
	else
		-- The silhouette treatment: no model, just a question mark on a
		-- dark card. The rarity stroke stays visible as the tease.
		TidetownUi.create("TextLabel", {
			Name = "MysteryLabel",
			Position = UDim2.new(0, 0, 0, 6),
			Size = UDim2.new(1, 0, 0, 96),
			BackgroundTransparency = 1,
			Text = "?",
			TextSize = 46,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Parent = card,
		})
	end

	if species.deepOnly then
		-- Deep-only species need an owned mount to even reach; the badge
		-- explains the extra hurdle right on the card.
		TidetownUi.create("TextLabel", {
			Name = "MountBadge",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 6),
			Size = UDim2.new(0, 22, 0, 22),
			BackgroundTransparency = 1,
			Text = "🐋",
			TextSize = 18,
			ZIndex = 3,
			Parent = card,
		})
	end

	TidetownUi.create("TextLabel", {
		Name = "NameLabel",
		Position = UDim2.new(0, 6, 1, -28),
		Size = UDim2.new(1, -12, 0, 22),
		BackgroundTransparency = 1,
		Text = if caught then species.name else "???",
		TextSize = 15,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
end

function TidepediaGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = TidetownUi.create("ScreenGui", {
		Name = "TidetownTidepediaGui",
		ResetOnSpawn = false,
		DisplayOrder = 14,
		Parent = playerGui,
	}) :: ScreenGui

	-- The assigned slot in the shared left-edge icon column.
	local slotFrame = TidetownUi.create("Frame", {
		Name = "TidepediaButtonSlot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, (BUTTON_SLOT - 3.5) * 88),
		Size = UDim2.new(0, 64, 0, 80),
		BackgroundTransparency = 1,
		Parent = screenGui,
	}) :: Frame

	local openButton =
		TidetownUi.iconButton(slotFrame, BUTTON_SLOT, "📖", "Tidepedia", BUTTON_COLOR)

	local window = TidetownUi.create("Frame", {
		Name = "TidepediaWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 680, 0, 500),
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

	TidetownUi.cartoonizeWindow(window, HEADER_COLOR, "Tidepedia")

	local summaryLabel = TidetownUi.create("TextLabel", {
		Name = "SummaryLabel",
		Position = UDim2.new(0, 20, 0, 42),
		Size = UDim2.new(1, -40, 0, 26),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 18,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window,
	}) :: TextLabel

	local tabRow = TidetownUi.create("Frame", {
		Name = "TabRow",
		Position = UDim2.new(0, 20, 0, 76),
		Size = UDim2.new(1, -40, 0, 36),
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
		Name = "SpeciesGrid",
		Position = UDim2.new(0, 16, 0, 122),
		Size = UDim2.new(1, -32, 1, -138),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = window,
	}) :: ScrollingFrame

	TidetownUi.create("UIGridLayout", {
		CellSize = UDim2.new(0, 152, 0, 158),
		CellPadding = UDim2.new(0, 10, 0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})

	TidetownUi.bubbly(scroll)

	local lockLabel = TidetownUi.create("TextLabel", {
		Name = "LockLabel",
		Position = UDim2.new(0, 16, 0, 122),
		Size = UDim2.new(1, -32, 1, -138),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 22,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextWrapped = true,
		Visible = false,
		Parent = window,
	}) :: TextLabel

	local tabRefreshers: { () -> () } = {}

	local function refreshSummary()
		summaryLabel.Text = string.format(
			"%d / %d · Keeper Rank %d · Luck +%s%% (cap %d%%)",
			entryCount,
			CreatureCatalog.totalCount(),
			keeperRankState,
			string.format("%g", luckPercentState),
			TidetownConfig.tidepedia.aggregateCapPercent
		)
	end

	local function refreshTabs()
		for _, refresh in ipairs(tabRefreshers) do
			refresh()
		end
	end

	local function rebuildGrid()
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		local gate = gatesState[selectedZone] or 0
		local unlocked = entryCount >= gate
		scroll.Visible = unlocked
		lockLabel.Visible = not unlocked

		if not unlocked then
			lockLabel.Text = string.format("🔒 Log %d species to unlock", gate)

			return
		end

		for index, species in ipairs(CreatureCatalog.speciesInZone(selectedZone)) do
			buildSpeciesCard(scroll, index, species)
		end
	end

	for order, tab in ipairs(ZONE_TABS) do
		local tabButton = TidetownUi.create("TextButton", {
			Name = "Tab_" .. tab.key,
			LayoutOrder = order,
			Size = UDim2.new(0, 128, 1, 0),
			BackgroundColor3 = TAB_COLOR,
			BorderSizePixel = 0,
			Text = tab.label,
			TextSize = 15,
			Parent = tabRow,
		}) :: TextButton
		TidetownUi.round(tabButton, 10)
		TidetownUi.stroke(tabButton, OUTLINE_NAVY, 2.5)

		local function refresh()
			local locked = entryCount < (gatesState[tab.key] or 0)
			tabButton.Text = if locked then "🔒 " .. tab.label else tab.label
			tabButton.BackgroundColor3 = if tab.key == selectedZone
				then TAB_ACTIVE_COLOR
				else TAB_COLOR
		end

		tabButton.Activated:Connect(function()
			selectedZone = tab.key
			refreshTabs()
			rebuildGrid()
		end)

		table.insert(tabRefreshers, refresh)
		refresh()
	end

	openButton.Activated:Connect(function()
		if window.Visible then
			window.Visible = false
		else
			TidetownUi.popOpen(window)
		end
	end)

	closeButton.Activated:Connect(function()
		window.Visible = false
	end)

	local syncRemote = TidetownRemotes.get("SyncState") :: RemoteEvent
	syncRemote.OnClientEvent:Connect(function(kind, payload)
		if kind ~= "tidepedia" or typeof(payload) ~= "table" then
			return
		end

		entriesState = if typeof(payload.entries) == "table" then payload.entries else {}
		entryCount = if typeof(payload.count) == "number" then payload.count else 0
		luckPercentState = if typeof(payload.luckPercent) == "number"
			then payload.luckPercent
			else 0
		keeperRankState = if typeof(payload.keeperRank) == "number" then payload.keeperRank else 0
		gatesState = if typeof(payload.gates) == "table" then payload.gates else gatesState

		refreshSummary()
		refreshTabs()
		rebuildGrid()
	end)

	refreshSummary()
	rebuildGrid()
end

return TidepediaGui
