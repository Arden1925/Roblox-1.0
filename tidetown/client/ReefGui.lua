--[[
	The My Reef window: the management side of the boardwalk reef plot.
	A grid of every possible tank slot -- filled slots show the working
	creature with a Remove button, unlocked empty slots offer Place
	(which opens a picker of creatures not already placed or drafted
	into the defense team), and locked slots show the padlock with a
	one-tap unlock that goes through the normal shop purchase. Below,
	the pending Shell pool with its Collect button and the honest rate
	line: what the reef pays per minute while playing, and the fraction
	it keeps paying while away.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Client = script.Parent
local TidetownUi = require(Client.TidetownUi)
local Toast = require(Client.Toast)

local TidetownShared = ReplicatedStorage:WaitForChild("TidetownShared")
local CreatureCatalog = require(TidetownShared.CreatureCatalog)
local CreatureModels = require(TidetownShared.CreatureModels)
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

local OUTLINE_NAVY = Color3.fromRGB(31, 41, 74)
local HEADER_COLOR = Color3.fromRGB(0, 137, 123)
local BUTTON_COLOR = Color3.fromRGB(0, 150, 136)
local CARD_COLOR = Color3.fromRGB(232, 244, 252)
local LOCKED_COLOR = Color3.fromRGB(44, 52, 78)
local PLACE_COLOR = Color3.fromRGB(66, 165, 245)
local REMOVE_COLOR = Color3.fromRGB(235, 69, 44)
local UNLOCK_COLOR = Color3.fromRGB(255, 179, 0)
local COLLECT_COLOR = Color3.fromRGB(46, 125, 50)
local PICKER_COLOR = Color3.fromRGB(244, 250, 255)
local BUTTON_SLOT = 3
local MAX_SLOTS = TidetownConfig.reef.maxSlots
local OFFLINE_PERCENT = math.floor(TidetownConfig.reef.offlineRateFraction * 100)
local BOUNCE_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)

local localPlayer = Players.LocalPlayer

-- Server-synced reef state plus the creature roster the picker and the
-- rate line read from.
local slotsUnlocked = TidetownConfig.reef.startingSlots
local placedState: { [string]: string } = {}
local poolState = 0
local nextSlotCost: number? = nil
local creaturesState: { any } = {}
local defenseTeamState: { string } = {}

local ReefGui = {}

local function creatureForUid(uid: string): any?
	for _, creature in ipairs(creaturesState) do
		if creature.uid == uid then
			return creature
		end
	end

	return nil
end

-- The active earn rate: the sum of each placed creature's per-minute
-- payout by rarity, exactly as the server accrues it.
local function ratePerMinute(): number
	local total = 0
	for _, uid in pairs(placedState) do
		local creature = creatureForUid(uid)
		local species = if creature ~= nil
			then CreatureCatalog.speciesFor(creature.species)
			else nil
		if species ~= nil then
			total += TidetownConfig.reef.shellsPerMinuteByRarity[species.rarity] or 0
		end
	end

	return total
end

-- Creatures free to place: owned, not already in a tank, and not
-- holding a defense-team slot (the server enforces the same rule).
local function unplacedCreatures(): { any }
	local placedByUid: { [string]: boolean } = {}
	for _, uid in pairs(placedState) do
		placedByUid[uid] = true
	end

	local list = {}
	for _, creature in ipairs(creaturesState) do
		local busy = placedByUid[creature.uid] == true
			or table.find(defenseTeamState, creature.uid) ~= nil
		if not busy then
			table.insert(list, creature)
		end
	end

	return list
end

--[[
	Frames a centered model in a fresh ViewportFrame using the model's
	real bounds (the PetViewport math), with a fixed slight yaw so the
	grid costs nothing per frame.
]]
local function buildCardViewport(parent: Instance, speciesKey: string)
	local model = CreatureModels.build(speciesKey, 2)
	model:PivotTo(CFrame.Angles(0, math.rad(25), 0))

	local viewport = TidetownUi.create("ViewportFrame", {
		Name = "CreatureViewport",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.new(1, -12, 0, 72),
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

function ReefGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = TidetownUi.create("ScreenGui", {
		Name = "TidetownReefGui",
		ResetOnSpawn = false,
		DisplayOrder = 13,
		Parent = playerGui,
	}) :: ScreenGui

	-- The assigned slot in the shared left-edge icon column.
	local slotFrame = TidetownUi.create("Frame", {
		Name = "ReefButtonSlot",
		AnchorPoint = Vector2.new(0, 0.5),
		-- Shifted below screen-center so the column clears the currency
		-- chips even on short viewports.
		Position = UDim2.new(0, 12, 0.5, (BUTTON_SLOT - 2.7) * 80),
		Size = UDim2.new(0, 64, 0, 80),
		BackgroundTransparency = 1,
		Parent = screenGui,
	}) :: Frame

	local openButton = TidetownUi.iconButton(slotFrame, BUTTON_SLOT, "🐠", "Reef", BUTTON_COLOR)

	local window = TidetownUi.create("Frame", {
		Name = "ReefWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 660, 0, 490),
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

	TidetownUi.cartoonizeWindow(window, HEADER_COLOR, "My Reef")

	local gridFrame = TidetownUi.create("Frame", {
		Name = "SlotGrid",
		Position = UDim2.new(0, 20, 0, 48),
		Size = UDim2.new(1, -40, 0, 330),
		BackgroundTransparency = 1,
		Parent = window,
	}) :: Frame

	TidetownUi.create("UIGridLayout", {
		CellSize = UDim2.new(0, 192, 0, 158),
		CellPadding = UDim2.new(0, 10, 0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = gridFrame,
	})

	local poolLabel = TidetownUi.create("TextLabel", {
		Name = "PoolLabel",
		Position = UDim2.new(0, 20, 0, 390),
		Size = UDim2.new(0, 260, 0, 40),
		BackgroundTransparency = 1,
		Text = "🐚 0 waiting",
		TextSize = 22,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window,
	}) :: TextLabel

	local poolScale = TidetownUi.create("UIScale", { Parent = poolLabel }) :: UIScale

	local collectButton = TidetownUi.create("TextButton", {
		Name = "CollectButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 388),
		Size = UDim2.new(0, 170, 0, 44),
		BackgroundColor3 = COLLECT_COLOR,
		BorderSizePixel = 0,
		Text = "COLLECT",
		TextSize = 19,
		Parent = window,
	}) :: TextButton
	TidetownUi.round(collectButton, 12)
	TidetownUi.stroke(collectButton, OUTLINE_NAVY, 3)
	TidetownUi.hoverPop(collectButton)

	local rateLabel = TidetownUi.create("TextLabel", {
		Name = "RateLabel",
		Position = UDim2.new(0, 20, 0, 436),
		Size = UDim2.new(1, -40, 0, 24),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 15,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window,
	}) :: TextLabel

	-- The creature picker overlay: filled per open, one slot at a time.
	local picker = TidetownUi.create("Frame", {
		Name = "PlacePicker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 340, 0, 360),
		BackgroundColor3 = PICKER_COLOR,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 10,
		Parent = window,
	}) :: Frame
	TidetownUi.round(picker, 14)
	TidetownUi.stroke(picker, OUTLINE_NAVY, 3)

	TidetownUi.create("TextLabel", {
		Name = "PickerTitle",
		Position = UDim2.new(0, 0, 0, 10),
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		Text = "Pick a creature",
		TextSize = 20,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		ZIndex = 11,
		Parent = picker,
	})

	local pickerList = TidetownUi.create("ScrollingFrame", {
		Name = "PickerList",
		Position = UDim2.new(0, 14, 0, 44),
		Size = UDim2.new(1, -28, 1, -104),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 11,
		Parent = picker,
	}) :: ScrollingFrame

	TidetownUi.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = pickerList,
	})

	local pickerCancel = TidetownUi.create("TextButton", {
		Name = "PickerCancel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(0, 140, 0, 36),
		BackgroundColor3 = REMOVE_COLOR,
		BorderSizePixel = 0,
		Text = "Cancel",
		TextSize = 16,
		ZIndex = 11,
		Parent = picker,
	}) :: TextButton
	TidetownUi.round(pickerCancel, 10)
	TidetownUi.stroke(pickerCancel, OUTLINE_NAVY, 2.5)

	local buyRemote = TidetownRemotes.get("BuyShopItem") :: RemoteFunction
	local clearRemote = TidetownRemotes.get("ClearReefSlot") :: RemoteFunction
	local collectRemote = TidetownRemotes.get("CollectReef") :: RemoteFunction
	local placeRemote = TidetownRemotes.get("PlaceReefCreature") :: RemoteFunction
	local syncRemote = TidetownRemotes.get("SyncState") :: RemoteEvent
	-- The join-burst state push can fire before this listener exists
	-- and queued events drain only into the first connection, so ask
	-- the server to resend our slices. task.defer runs after the
	-- Connect below, so the reply always finds the handler.
	task.defer(function()
		local requestSync = TidetownRemotes.get("RequestSync") :: RemoteEvent
		requestSync:FireServer("reef")
		requestSync:FireServer("creatures")
	end)

	local function refreshPoolRow()
		poolLabel.Text = string.format("🐚 %d waiting", poolState)
		rateLabel.Text = string.format(
			"+%s 🐚/min while you play, %d%% away",
			string.format("%g", ratePerMinute()),
			OFFLINE_PERCENT
		)
	end

	local function openPicker(slotIndex: number)
		for _, child in ipairs(pickerList:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		local candidates = unplacedCreatures()
		if #candidates == 0 then
			TidetownUi.create("TextLabel", {
				Name = "EmptyLabel",
				Size = UDim2.new(1, 0, 0, 60),
				BackgroundTransparency = 1,
				Text = "Everyone is busy -- hatch more eggs!",
				TextSize = 16,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextWrapped = true,
				ZIndex = 11,
				Parent = pickerList,
			})
		end

		for order, creature in ipairs(candidates) do
			local species = CreatureCatalog.speciesFor(creature.species)
			if species ~= nil then
				local shownName = if creature.nickname ~= ""
					then creature.nickname
					else species.name
				local pickButton = TidetownUi.create("TextButton", {
					Name = "Pick_" .. creature.uid,
					LayoutOrder = order,
					Size = UDim2.new(1, -8, 0, 34),
					BackgroundColor3 = PLACE_COLOR,
					BorderSizePixel = 0,
					Text = string.format("%s (%s)", shownName, species.rarity),
					TextSize = 15,
					ZIndex = 11,
					Parent = pickerList,
				}) :: TextButton
				TidetownUi.round(pickButton, 8)
				TidetownUi.stroke(pickButton, CreatureCatalog.rarityColor(species.rarity), 2.5)

				pickButton.Activated:Connect(function()
					picker.Visible = false
					local ok, message = placeRemote:InvokeServer(slotIndex, creature.uid)
					if ok == true then
						Toast.push(shownName .. " is working the reef!", "good")
					else
						Toast.push(
							if typeof(message) == "string" then message else "Cannot place that",
							"bad"
						)
					end
				end)
			end
		end

		TidetownUi.popOpen(picker)
	end

	local function buildFilledSlot(card: Frame, slotIndex: number, uid: string)
		local creature = creatureForUid(uid)
		local species = if creature ~= nil
			then CreatureCatalog.speciesFor(creature.species)
			else nil
		if creature == nil or species == nil then
			-- The reef sync can land before the creatures sync on join;
			-- the next "creatures" sync rebuilds this card with the
			-- viewport and real name.
			TidetownUi.create("TextLabel", {
				Name = "PendingLabel",
				Position = UDim2.new(0, 0, 0, 30),
				Size = UDim2.new(1, 0, 0, 40),
				BackgroundTransparency = 1,
				Text = "...",
				TextSize = 24,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Parent = card,
			})
		else
			TidetownUi.stroke(card, CreatureCatalog.rarityColor(species.rarity), 3)
			buildCardViewport(card, species.key)

			local shownName = if creature.nickname ~= "" then creature.nickname else species.name
			TidetownUi.create("TextLabel", {
				Name = "NameLabel",
				Position = UDim2.new(0, 8, 0, 78),
				Size = UDim2.new(1, -16, 0, 20),
				BackgroundTransparency = 1,
				Text = shownName,
				TextSize = 15,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = card,
			})
		end

		local removeButton = TidetownUi.create("TextButton", {
			Name = "RemoveButton",
			Position = UDim2.new(0, 10, 1, -40),
			Size = UDim2.new(1, -20, 0, 30),
			BackgroundColor3 = REMOVE_COLOR,
			BorderSizePixel = 0,
			Text = "Remove",
			TextSize = 14,
			Parent = card,
		}) :: TextButton
		TidetownUi.round(removeButton, 8)
		TidetownUi.stroke(removeButton, OUTLINE_NAVY, 2)

		removeButton.Activated:Connect(function()
			local ok, message = clearRemote:InvokeServer(slotIndex)
			if ok == true then
				Toast.push("Back with the crew!", "good")
			else
				Toast.push(
					if typeof(message) == "string" then message else "Cannot clear that slot",
					"bad"
				)
			end
		end)
	end

	local function buildEmptySlot(card: Frame, slotIndex: number)
		TidetownUi.create("TextLabel", {
			Name = "EmptyLabel",
			Position = UDim2.new(0, 0, 0, 34),
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			Text = "Empty tank",
			TextSize = 17,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Parent = card,
		})

		local placeButton = TidetownUi.create("TextButton", {
			Name = "PlaceButton",
			Position = UDim2.new(0, 10, 1, -40),
			Size = UDim2.new(1, -20, 0, 30),
			BackgroundColor3 = PLACE_COLOR,
			BorderSizePixel = 0,
			Text = "Place",
			TextSize = 14,
			Parent = card,
		}) :: TextButton
		TidetownUi.round(placeButton, 8)
		TidetownUi.stroke(placeButton, OUTLINE_NAVY, 2)

		placeButton.Activated:Connect(function()
			openPicker(slotIndex)
		end)
	end

	local function buildLockedSlot(card: Frame, slotIndex: number)
		card.BackgroundColor3 = LOCKED_COLOR

		TidetownUi.create("TextLabel", {
			Name = "PadlockLabel",
			Position = UDim2.new(0, 0, 0, 24),
			Size = UDim2.new(1, 0, 0, 46),
			BackgroundTransparency = 1,
			Text = "🔒",
			TextSize = 34,
			Parent = card,
		})

		-- Only the very next slot is purchasable; slots beyond it show
		-- the padlock alone until the ladder reaches them.
		local purchasable = slotIndex == slotsUnlocked + 1 and nextSlotCost ~= nil
		if purchasable then
			local unlockButton = TidetownUi.create("TextButton", {
				Name = "UnlockButton",
				Position = UDim2.new(0, 10, 1, -40),
				Size = UDim2.new(1, -20, 0, 30),
				BackgroundColor3 = UNLOCK_COLOR,
				BorderSizePixel = 0,
				Text = string.format("Unlock 🐚%d", nextSlotCost or 0),
				TextSize = 14,
				Parent = card,
			}) :: TextButton
			TidetownUi.round(unlockButton, 8)
			TidetownUi.stroke(unlockButton, OUTLINE_NAVY, 2)

			unlockButton.Activated:Connect(function()
				local ok, message = buyRemote:InvokeServer("reefSlot")
				if ok == true then
					Toast.push("New tank unlocked!", "good")
				else
					Toast.push(
						if typeof(message) == "string" then message else "Cannot unlock yet",
						"bad"
					)
				end
			end)
		else
			TidetownUi.create("TextLabel", {
				Name = "LockedLabel",
				Position = UDim2.new(0, 10, 1, -40),
				Size = UDim2.new(1, -20, 0, 30),
				BackgroundTransparency = 1,
				Text = "Locked",
				TextSize = 14,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Parent = card,
			})
		end
	end

	local function rebuildGrid()
		for _, child in ipairs(gridFrame:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		for slotIndex = 1, MAX_SLOTS do
			local card = TidetownUi.create("Frame", {
				Name = "Slot_" .. slotIndex,
				LayoutOrder = slotIndex,
				BackgroundColor3 = CARD_COLOR,
				BorderSizePixel = 0,
				Parent = gridFrame,
			}) :: Frame
			TidetownUi.round(card, 14)
			TidetownUi.stroke(card, OUTLINE_NAVY, 2.5)

			local uid = placedState[tostring(slotIndex)]
			if uid ~= nil then
				buildFilledSlot(card, slotIndex, uid)
			elseif slotIndex <= slotsUnlocked then
				buildEmptySlot(card, slotIndex)
			else
				buildLockedSlot(card, slotIndex)
			end
		end
	end

	collectButton.Activated:Connect(function()
		local ok, result = collectRemote:InvokeServer()
		if ok == true then
			local amount = if typeof(result) == "number" then result else 0
			Toast.push(string.format("+%d 🐚 collected!", amount), "good")
			poolScale.Scale = 1.3
			TweenService:Create(poolScale, BOUNCE_INFO, { Scale = 1 }):Play()
		else
			Toast.push(
				if typeof(result) == "string" then result else "Nothing to collect yet",
				"bad"
			)
		end
	end)

	pickerCancel.Activated:Connect(function()
		picker.Visible = false
	end)

	openButton.Activated:Connect(function()
		if window.Visible then
			window.Visible = false
		else
			TidetownUi.popOpen(window)
		end
	end)

	closeButton.Activated:Connect(function()
		window.Visible = false
		picker.Visible = false
	end)

	syncRemote.OnClientEvent:Connect(function(kind, payload)
		if typeof(payload) ~= "table" then
			return
		end

		if kind == "reef" then
			slotsUnlocked = if typeof(payload.slotsUnlocked) == "number"
				then payload.slotsUnlocked
				else slotsUnlocked
			placedState = if typeof(payload.placed) == "table" then payload.placed else {}
			poolState = if typeof(payload.pool) == "number" then payload.pool else 0
			nextSlotCost = if typeof(payload.nextSlotCost) == "number"
				then payload.nextSlotCost
				else nil
			rebuildGrid()
			refreshPoolRow()
		elseif kind == "creatures" then
			creaturesState = if typeof(payload.creatures) == "table" then payload.creatures else {}
			defenseTeamState = if typeof(payload.defenseTeam) == "table"
				then payload.defenseTeam
				else {}
			-- Names, rates, and the picker all depend on the roster.
			rebuildGrid()
			refreshPoolRow()
		end
	end)

	rebuildGrid()
	refreshPoolRow()
end

return ReefGui
