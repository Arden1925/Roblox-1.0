--[[
	The Team window: every owned creature as a card with its model, its
	rarity-colored border, and its defense role, plus the two ways a
	creature works for you -- swimming along as the companion or holding
	a slot on the three-creature defense team. Team edits build up in a
	local working list and only hit the server on Apply, so players can
	juggle roles and watch the link-bonus preview before committing.
	Reef-placed creatures are shown busy and cannot be drafted.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent
local TidetownUi = require(Client.TidetownUi)
local Toast = require(Client.Toast)

local TidetownShared = ReplicatedStorage:WaitForChild("TidetownShared")
local CreatureCatalog = require(TidetownShared.CreatureCatalog)
local CreatureModels = require(TidetownShared.CreatureModels)
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

local OUTLINE_NAVY = Color3.fromRGB(31, 41, 74)
local HEADER_COLOR = Color3.fromRGB(0, 148, 176)
local BUTTON_COLOR = Color3.fromRGB(38, 166, 154)
local CARD_COLOR = Color3.fromRGB(232, 244, 252)
local COMPANION_COLOR = Color3.fromRGB(66, 165, 245)
local COMPANION_ACTIVE_COLOR = Color3.fromRGB(255, 179, 0)
local DEFEND_COLOR = Color3.fromRGB(38, 166, 154)
local DEFEND_ACTIVE_COLOR = Color3.fromRGB(46, 125, 50)
local DISABLED_COLOR = Color3.fromRGB(144, 152, 161)
local APPLY_COLOR = Color3.fromRGB(46, 125, 50)
local LINK_GOLD = Color3.fromRGB(255, 179, 0)
local RENAME_BOX_COLOR = Color3.fromRGB(38, 50, 78)
local BUTTON_SLOT = 2
local MAX_TEAM = TidetownConfig.creatures.defenseTeamSize
local LINK_BONUS_PER_PAIR = TidetownConfig.creatures.linkBonusPerPairPercent

local localPlayer = Players.LocalPlayer

-- Server-synced state plus the local working copy of the defense team.
-- The working list resets to the server's team on every creatures sync,
-- so Apply is always a diff against what the server last confirmed.
local creaturesState: { any } = {}
local companionUid = ""
local serverTeam: { string } = {}
local workingTeam: { string } = {}
local reefPlacedUids: { [string]: boolean } = {}

local TeamGui = {}

local function creatureForUid(uid: string): any?
	for _, creature in ipairs(creaturesState) do
		if creature.uid == uid then
			return creature
		end
	end

	return nil
end

local function roleForUid(uid: string): string?
	local creature = creatureForUid(uid)
	if creature == nil then
		return nil
	end

	local species = CreatureCatalog.speciesFor(creature.species)

	return if species ~= nil then species.role else nil
end

-- The link bonus rewards mixing roles: every pair of DIFFERENT roles
-- in the working team adds a flat percent, previewed here exactly as
-- the surge will compute it.
local function linkBonusPercent(): number
	local distinctPairs = 0
	for first = 1, #workingTeam do
		for second = first + 1, #workingTeam do
			local roleA = roleForUid(workingTeam[first])
			local roleB = roleForUid(workingTeam[second])
			if roleA ~= nil and roleB ~= nil and roleA ~= roleB then
				distinctPairs += 1
			end
		end
	end

	return distinctPairs * LINK_BONUS_PER_PAIR
end

--[[
	Frames a centered model in a fresh ViewportFrame using the model's
	real bounds (the PetViewport math). Cards use a fixed slight yaw
	instead of a spin so a full grid of creatures costs nothing per
	frame.
]]
local function buildCardViewport(parent: Instance, speciesKey: string)
	local model = CreatureModels.build(speciesKey, 2)
	model:PivotTo(CFrame.Angles(0, math.rad(25), 0))

	local viewport = TidetownUi.create("ViewportFrame", {
		Name = "CreatureViewport",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(1, -12, 0, 92),
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

local function buildBadge(parent: Instance, name: string, icon: string, anchorX: number)
	TidetownUi.create("TextLabel", {
		Name = name,
		AnchorPoint = Vector2.new(anchorX, 0),
		Position = UDim2.new(anchorX, if anchorX == 1 then -6 else 6, 0, 6),
		Size = UDim2.new(0, 22, 0, 22),
		BackgroundTransparency = 1,
		Text = icon,
		TextSize = 18,
		Visible = false,
		ZIndex = 3,
		Parent = parent,
	})
end

function TeamGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = TidetownUi.create("ScreenGui", {
		Name = "TidetownTeamGui",
		ResetOnSpawn = false,
		DisplayOrder = 12,
		Parent = playerGui,
	}) :: ScreenGui

	-- The assigned slot in the shared left-edge icon column.
	local slotFrame = TidetownUi.create("Frame", {
		Name = "TeamButtonSlot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, (BUTTON_SLOT - 3.5) * 88),
		Size = UDim2.new(0, 64, 0, 80),
		BackgroundTransparency = 1,
		Parent = screenGui,
	}) :: Frame

	local teamButton = TidetownUi.iconButton(slotFrame, BUTTON_SLOT, "🐟", "Team", BUTTON_COLOR)

	local window = TidetownUi.create("Frame", {
		Name = "TeamWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 680, 0, 480),
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

	TidetownUi.cartoonizeWindow(window, HEADER_COLOR, "Team")

	local teamLabel = TidetownUi.create("TextLabel", {
		Name = "TeamCountLabel",
		Position = UDim2.new(0, 20, 0, 40),
		Size = UDim2.new(0, 150, 0, 34),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 17,
		TextColor3 = OUTLINE_NAVY,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window,
	}) :: TextLabel

	local linkLabel = TidetownUi.create("TextLabel", {
		Name = "LinkBonusLabel",
		Position = UDim2.new(0, 180, 0, 40),
		Size = UDim2.new(0, 200, 0, 34),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 17,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window,
	}) :: TextLabel

	local applyButton = TidetownUi.create("TextButton", {
		Name = "ApplyButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 40),
		Size = UDim2.new(0, 140, 0, 34),
		BackgroundColor3 = APPLY_COLOR,
		BorderSizePixel = 0,
		Text = "Apply Team",
		TextSize = 17,
		Parent = window,
	}) :: TextButton
	TidetownUi.round(applyButton, 10)
	TidetownUi.stroke(applyButton, OUTLINE_NAVY, 2.5)
	TidetownUi.hoverPop(applyButton)

	local scroll = TidetownUi.create("ScrollingFrame", {
		Name = "CreatureGrid",
		Position = UDim2.new(0, 16, 0, 84),
		Size = UDim2.new(1, -32, 1, -100),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = window,
	}) :: ScrollingFrame

	TidetownUi.create("UIGridLayout", {
		CellSize = UDim2.new(0, 150, 0, 214),
		CellPadding = UDim2.new(0, 10, 0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})

	TidetownUi.bubbly(scroll)

	local equipRemote = TidetownRemotes.get("EquipCompanion") :: RemoteFunction
	local renameRemote = TidetownRemotes.get("RenameCreature") :: RemoteFunction
	local setTeamRemote = TidetownRemotes.get("SetDefenseTeam") :: RemoteFunction
	local syncRemote = TidetownRemotes.get("SyncState") :: RemoteEvent
	-- The join-burst state push can fire before this listener exists
	-- and queued events drain only into the first connection, so ask
	-- the server to resend our slices. task.defer runs after the
	-- Connect below, so the reply always finds the handler.
	task.defer(function()
		local requestSync = TidetownRemotes.get("RequestSync") :: RemoteEvent
		requestSync:FireServer("creatures")
		requestSync:FireServer("reef")
	end)

	-- Team toggles refresh existing cards in place instead of tearing
	-- the grid down, so viewports are only rebuilt on real data syncs.
	local cardRefreshers: { () -> () } = {}

	local function refreshHeader()
		teamLabel.Text = string.format("Defense: %d/%d", #workingTeam, MAX_TEAM)

		local bonus = linkBonusPercent()
		linkLabel.Text = string.format("Link bonus: +%d%%", bonus)
		linkLabel.TextColor3 = if bonus > 0 then LINK_GOLD else Color3.fromRGB(255, 255, 255)
	end

	local function refreshTeamUi()
		refreshHeader()
		for _, refresh in ipairs(cardRefreshers) do
			refresh()
		end
	end

	local function buildCard(index: number, creature: any)
		local species = CreatureCatalog.speciesFor(creature.species)
		if species == nil then
			return
		end

		local uid: string = creature.uid

		local card = TidetownUi.create("Frame", {
			Name = "Card_" .. uid,
			LayoutOrder = index,
			BackgroundColor3 = CARD_COLOR,
			BorderSizePixel = 0,
			Parent = scroll,
		}) :: Frame
		TidetownUi.round(card, 14)
		TidetownUi.stroke(card, CreatureCatalog.rarityColor(species.rarity), 3)

		buildCardViewport(card, species.key)
		buildBadge(card, "DefenseBadge", "🛡️", 0)
		buildBadge(card, "ReefBadge", "🐠", 1)

		local shownName = if creature.nickname ~= "" then creature.nickname else species.name
		local nameLabel = TidetownUi.create("TextLabel", {
			Name = "NameLabel",
			Position = UDim2.new(0, 8, 0, 100),
			Size = UDim2.new(1, -42, 0, 22),
			BackgroundTransparency = 1,
			Text = shownName,
			TextSize = 16,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		}) :: TextLabel

		local renameButton = TidetownUi.create("TextButton", {
			Name = "RenameButton",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 99),
			Size = UDim2.new(0, 24, 0, 24),
			BackgroundTransparency = 1,
			Text = "✏️",
			TextSize = 16,
			Parent = card,
		}) :: TextButton

		local renameBox = TidetownUi.create("TextBox", {
			Name = "RenameBox",
			Position = UDim2.new(0, 8, 0, 100),
			Size = UDim2.new(1, -16, 0, 22),
			BackgroundColor3 = RENAME_BOX_COLOR,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Text = "",
			TextSize = 14,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Visible = false,
			ZIndex = 3,
			Parent = card,
		}) :: TextBox
		TidetownUi.round(renameBox, 6)

		local roleChip = TidetownUi.create("Frame", {
			Name = "RoleChip",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 126),
			Size = UDim2.new(0, 110, 0, 20),
			BackgroundColor3 = CreatureModels.roleColor(species.role),
			BorderSizePixel = 0,
			Parent = card,
		}) :: Frame
		TidetownUi.round(roleChip, 10)
		TidetownUi.stroke(roleChip, OUTLINE_NAVY, 2)

		TidetownUi.create("TextLabel", {
			Name = "RoleLabel",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = species.role,
			TextSize = 13,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Parent = roleChip,
		})

		local companionButton = TidetownUi.create("TextButton", {
			Name = "CompanionButton",
			Position = UDim2.new(0, 8, 0, 152),
			Size = UDim2.new(1, -16, 0, 26),
			BackgroundColor3 = COMPANION_COLOR,
			BorderSizePixel = 0,
			Text = "Companion",
			TextSize = 14,
			Parent = card,
		}) :: TextButton
		TidetownUi.round(companionButton, 8)
		TidetownUi.stroke(companionButton, OUTLINE_NAVY, 2)

		local defendButton = TidetownUi.create("TextButton", {
			Name = "DefendButton",
			Position = UDim2.new(0, 8, 0, 182),
			Size = UDim2.new(1, -16, 0, 26),
			BackgroundColor3 = DEFEND_COLOR,
			BorderSizePixel = 0,
			Text = "Defend",
			TextSize = 14,
			Parent = card,
		}) :: TextButton
		TidetownUi.round(defendButton, 8)
		TidetownUi.stroke(defendButton, OUTLINE_NAVY, 2)

		local function refresh()
			local isCompanion = companionUid == uid
			companionButton.Text = if isCompanion then "Companion ✓" else "Companion"
			companionButton.BackgroundColor3 = if isCompanion
				then COMPANION_ACTIVE_COLOR
				else COMPANION_COLOR

			local placed = reefPlacedUids[uid] == true
			if placed then
				defendButton.Text = "On Reef"
				defendButton.BackgroundColor3 = DISABLED_COLOR
				defendButton.AutoButtonColor = false
			elseif table.find(workingTeam, uid) ~= nil then
				defendButton.Text = "Defending ✓"
				defendButton.BackgroundColor3 = DEFEND_ACTIVE_COLOR
				defendButton.AutoButtonColor = true
			else
				defendButton.Text = "Defend"
				defendButton.BackgroundColor3 = DEFEND_COLOR
				defendButton.AutoButtonColor = true
			end

			local defenseBadge = card:FindFirstChild("DefenseBadge")
			if defenseBadge ~= nil and defenseBadge:IsA("TextLabel") then
				defenseBadge.Visible = table.find(serverTeam, uid) ~= nil
			end

			local reefBadge = card:FindFirstChild("ReefBadge")
			if reefBadge ~= nil and reefBadge:IsA("TextLabel") then
				reefBadge.Visible = placed
			end
		end

		companionButton.Activated:Connect(function()
			-- Clicking the current companion unequips it; the server
			-- treats an empty uid as "no companion".
			local target = if companionUid == uid then "" else uid
			local ok, message = equipRemote:InvokeServer(target)
			if ok == true then
				if target == "" then
					Toast.push("Companion is resting", "info")
				else
					Toast.push("Companion swimming beside you!", "good")
				end
			else
				Toast.push(
					if typeof(message) == "string" then message else "Cannot equip right now",
					"bad"
				)
			end
		end)

		defendButton.Activated:Connect(function()
			if reefPlacedUids[uid] == true then
				Toast.push("That creature is working your reef", "info")

				return
			end

			local foundIndex = table.find(workingTeam, uid)
			if foundIndex ~= nil then
				table.remove(workingTeam, foundIndex)
			elseif #workingTeam >= MAX_TEAM then
				Toast.push(string.format("Your team is full (%d)", MAX_TEAM), "info")

				return
			else
				table.insert(workingTeam, uid)
			end

			refreshTeamUi()
		end)

		renameButton.Activated:Connect(function()
			renameBox.Text = if creature.nickname ~= "" then creature.nickname else ""
			renameBox.Visible = true
			nameLabel.Visible = false
			renameBox:CaptureFocus()
		end)

		renameBox.FocusLost:Connect(function(enterPressed)
			renameBox.Visible = false
			nameLabel.Visible = true
			if not enterPressed then
				return
			end

			local newName = renameBox.Text
			if #newName < 2 or #newName > 20 then
				Toast.push("Names need 2 to 20 characters", "bad")

				return
			end

			local ok, message = renameRemote:InvokeServer(uid, newName)
			if ok == true then
				Toast.push("Renamed!", "good")
			else
				Toast.push(if typeof(message) == "string" then message else "Rename failed", "bad")
			end
		end)

		table.insert(cardRefreshers, refresh)
		refresh()
	end

	local function rebuildGrid()
		table.clear(cardRefreshers)
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		if #creaturesState == 0 then
			TidetownUi.create("TextLabel", {
				Name = "EmptyLabel",
				BackgroundTransparency = 1,
				Text = "Hatch eggs to meet your crew!",
				TextSize = 18,
				TextColor3 = OUTLINE_NAVY,
				Parent = scroll,
			})
		else
			for index, creature in ipairs(creaturesState) do
				buildCard(index, creature)
			end
		end

		refreshHeader()
	end

	applyButton.Activated:Connect(function()
		local ok, message = setTeamRemote:InvokeServer(table.clone(workingTeam))
		if ok == true then
			Toast.push("Defense team ready!", "good")
		else
			Toast.push(
				if typeof(message) == "string" then message else "Cannot set the team right now",
				"bad"
			)
		end
	end)

	teamButton.Activated:Connect(function()
		if window.Visible then
			window.Visible = false
		else
			TidetownUi.popOpen(window)
		end
	end)

	closeButton.Activated:Connect(function()
		window.Visible = false
	end)

	syncRemote.OnClientEvent:Connect(function(kind, payload)
		if typeof(payload) ~= "table" then
			return
		end

		if kind == "creatures" then
			creaturesState = if typeof(payload.creatures) == "table" then payload.creatures else {}
			companionUid = if typeof(payload.companionUid) == "string"
				then payload.companionUid
				else ""
			local newTeam = if typeof(payload.defenseTeam) == "table"
				then payload.defenseTeam
				else {}

			-- Any sync (a catch, a hatch, a rename) rebroadcasts the
			-- creatures slice; only a REAL team change may reset the
			-- player's unapplied working edits.
			local teamChanged = #newTeam ~= #serverTeam
			if not teamChanged then
				for index, uid in ipairs(newTeam) do
					if serverTeam[index] ~= uid then
						teamChanged = true
						break
					end
				end
			end

			serverTeam = newTeam
			if teamChanged then
				workingTeam = table.clone(serverTeam)
			end
			rebuildGrid()
		elseif kind == "reef" then
			reefPlacedUids = {}
			if typeof(payload.placed) == "table" then
				for _, uid in pairs(payload.placed) do
					if typeof(uid) == "string" then
						reefPlacedUids[uid] = true
					end
				end
			end
			rebuildGrid()
		end
	end)

	rebuildGrid()
end

return TeamGui
