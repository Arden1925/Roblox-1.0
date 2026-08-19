--[[
	The Bounties window: the three daily bounties as progress rows with
	a claim button that lights up at full, plus the streak strip -- the
	one place the game says out loud that streaks pause on missed days
	and never reset -- with the milestone chips underneath showing what
	each streak length pays. The window is fully rebuilt from every
	"bounties" sync, so claiming and progress both reflect instantly.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent
local TidetownUi = require(Client.TidetownUi)
local Toast = require(Client.Toast)

local TidetownShared = ReplicatedStorage:WaitForChild("TidetownShared")
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

local OUTLINE_NAVY = Color3.fromRGB(31, 41, 74)
local HEADER_COLOR = Color3.fromRGB(239, 108, 0)
local BUTTON_COLOR = Color3.fromRGB(255, 143, 0)
local ROW_COLOR = Color3.fromRGB(232, 244, 252)
local TRACK_COLOR = Color3.fromRGB(72, 84, 96)
local FILL_COLOR = Color3.fromRGB(38, 166, 154)
local CLAIM_READY_COLOR = Color3.fromRGB(46, 125, 50)
local CLAIM_DISABLED_COLOR = Color3.fromRGB(144, 152, 161)
local CHIP_COLOR = Color3.fromRGB(84, 110, 122)
local CHIP_CLAIMED_COLOR = Color3.fromRGB(255, 179, 0)
local STREAK_GOLD = Color3.fromRGB(255, 179, 0)
local BUTTON_SLOT = 5

local localPlayer = Players.LocalPlayer

-- Server-synced bounty state. Milestones default to config (all
-- unclaimed) so the strip renders before the first sync lands.
local bountyList: { any } = {}
local streakCount = 0
local milestonesState: { any } = {}

for _, milestone in ipairs(TidetownConfig.bounties.streakMilestones) do
	table.insert(milestonesState, {
		days = milestone.days,
		shellReward = milestone.shellReward,
		claimed = false,
	})
end

local BountyGui = {}

-- The reward suffix shown on each row, so the price of finishing is
-- visible before the claim button ever lights up.
local function rewardSuffix(entry: any): string
	local suffix = ""
	if typeof(entry.shellReward) == "number" and entry.shellReward > 0 then
		suffix ..= string.format(" +%d🐚", entry.shellReward)
	end
	if typeof(entry.stormglassReward) == "number" and entry.stormglassReward > 0 then
		suffix ..= string.format(" +%d⚡", entry.stormglassReward)
	end

	return suffix
end

function BountyGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = TidetownUi.create("ScreenGui", {
		Name = "TidetownBountyGui",
		ResetOnSpawn = false,
		DisplayOrder = 15,
		Parent = playerGui,
	}) :: ScreenGui

	-- The assigned slot in the shared left-edge icon column.
	local slotFrame = TidetownUi.create("Frame", {
		Name = "BountyButtonSlot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, (BUTTON_SLOT - 3.5) * 88),
		Size = UDim2.new(0, 64, 0, 80),
		BackgroundTransparency = 1,
		Parent = screenGui,
	}) :: Frame

	local openButton =
		TidetownUi.iconButton(slotFrame, BUTTON_SLOT, "📜", "Bounties", BUTTON_COLOR)

	local window = TidetownUi.create("Frame", {
		Name = "BountyWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 560, 0, 410),
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

	TidetownUi.cartoonizeWindow(window, HEADER_COLOR, "Bounties")

	local rowsFrame = TidetownUi.create("Frame", {
		Name = "BountyRows",
		Position = UDim2.new(0, 20, 0, 44),
		Size = UDim2.new(1, -40, 0, 236),
		BackgroundTransparency = 1,
		Parent = window,
	}) :: Frame

	TidetownUi.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = rowsFrame,
	})

	local streakLabel = TidetownUi.create("TextLabel", {
		Name = "StreakLabel",
		Position = UDim2.new(0, 20, 0, 292),
		Size = UDim2.new(1, -40, 0, 26),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 18,
		TextColor3 = STREAK_GOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window,
	}) :: TextLabel
	streakLabel:SetAttribute("KeepTextColor", true)

	local chipRow = TidetownUi.create("Frame", {
		Name = "MilestoneChips",
		Position = UDim2.new(0, 20, 0, 326),
		Size = UDim2.new(1, -40, 0, 40),
		BackgroundTransparency = 1,
		Parent = window,
	}) :: Frame

	TidetownUi.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = chipRow,
	})

	local claimRemote = TidetownRemotes.get("ClaimBounty") :: RemoteFunction
	local syncRemote = TidetownRemotes.get("SyncState") :: RemoteEvent
	-- The join-burst state push can fire before this listener exists
	-- and queued events drain only into the first connection, so ask
	-- the server to resend our slices. task.defer runs after the
	-- Connect below, so the reply always finds the handler.
	task.defer(function()
		local requestSync = TidetownRemotes.get("RequestSync") :: RemoteEvent
		requestSync:FireServer("bounties")
	end)

	local function buildRow(index: number, entry: any)
		local target = if typeof(entry.target) == "number" then entry.target else 1
		local progress = if typeof(entry.progress) == "number" then entry.progress else 0
		local claimed = entry.claimed == true
		local ready = progress >= target
		local text = if typeof(entry.text) == "string" then entry.text else "Bounty"

		-- string.format throws on a template/argument mismatch; a server
		-- payload with odd text should fall back to the raw string, not
		-- break the whole window.
		local formatOk, formatted = pcall(string.format, text, target)
		local rowText = if formatOk then formatted else text

		local row = TidetownUi.create("Frame", {
			Name = "BountyRow_" .. index,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 72),
			BackgroundColor3 = ROW_COLOR,
			BorderSizePixel = 0,
			Parent = rowsFrame,
		}) :: Frame
		TidetownUi.round(row, 12)
		TidetownUi.stroke(row, OUTLINE_NAVY, 2.5)

		TidetownUi.create("TextLabel", {
			Name = "BountyText",
			Position = UDim2.new(0, 12, 0, 6),
			Size = UDim2.new(1, -152, 0, 26),
			BackgroundTransparency = 1,
			Text = rowText .. rewardSuffix(entry),
			TextSize = 15,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})

		local track = TidetownUi.create("Frame", {
			Name = "ProgressTrack",
			Position = UDim2.new(0, 12, 0, 42),
			Size = UDim2.new(1, -164, 0, 16),
			BackgroundColor3 = TRACK_COLOR,
			BorderSizePixel = 0,
			Parent = row,
		}) :: Frame
		TidetownUi.round(track, 8)

		local fraction = math.clamp(progress / math.max(target, 1), 0, 1)
		local fill = TidetownUi.create("Frame", {
			Name = "ProgressFill",
			Size = UDim2.new(fraction, 0, 1, 0),
			BackgroundColor3 = FILL_COLOR,
			BorderSizePixel = 0,
			Parent = track,
		}) :: Frame
		TidetownUi.round(fill, 8)

		TidetownUi.create("TextLabel", {
			Name = "ProgressCount",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = string.format("%d/%d", math.min(progress, target), target),
			TextSize = 12,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			ZIndex = 3,
			Parent = track,
		})

		local claimButton = TidetownUi.create("TextButton", {
			Name = "ClaimButton",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.new(0, 128, 0, 40),
			BackgroundColor3 = if ready and not claimed
				then CLAIM_READY_COLOR
				else CLAIM_DISABLED_COLOR,
			BorderSizePixel = 0,
			AutoButtonColor = ready and not claimed,
			Text = if claimed then "Claimed ✓" else "Claim",
			TextSize = 16,
			Parent = row,
		}) :: TextButton
		TidetownUi.round(claimButton, 10)
		local claimStroke = TidetownUi.stroke(claimButton, OUTLINE_NAVY, 2.5)

		if ready and not claimed then
			TidetownUi.pulse(claimStroke)
			TidetownUi.hoverPop(claimButton)
		end

		claimButton.Activated:Connect(function()
			if claimed or not ready then
				return
			end

			local ok, message = claimRemote:InvokeServer(index)
			if ok == true then
				Toast.push("Bounty claimed!" .. rewardSuffix(entry), "good")
			else
				Toast.push(
					if typeof(message) == "string" then message else "Cannot claim that yet",
					"bad"
				)
			end
		end)
	end

	local function rebuildRows()
		for _, child in ipairs(rowsFrame:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		if #bountyList == 0 then
			TidetownUi.create("TextLabel", {
				Name = "EmptyLabel",
				Size = UDim2.new(1, 0, 0, 72),
				BackgroundTransparency = 1,
				Text = "Fresh bounties wash in with the day's tide!",
				TextSize = 18,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Parent = rowsFrame,
			})

			return
		end

		for index, entry in ipairs(bountyList) do
			buildRow(index, entry)
		end
	end

	local function rebuildStreak()
		streakLabel.Text = string.format("🔥 Streak: %d days (pauses, never resets)", streakCount)

		for _, child in ipairs(chipRow:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		for order, milestone in ipairs(milestonesState) do
			local days = if typeof(milestone.days) == "number" then milestone.days else 0
			local shells = if typeof(milestone.shellReward) == "number"
				then milestone.shellReward
				else 0
			local claimed = milestone.claimed == true

			local chip = TidetownUi.create("TextLabel", {
				Name = "MilestoneChip_" .. days,
				LayoutOrder = order,
				Size = UDim2.new(0, 130, 0, 36),
				BackgroundColor3 = if claimed then CHIP_CLAIMED_COLOR else CHIP_COLOR,
				BorderSizePixel = 0,
				Text = if claimed
					then string.format("✓ %dd +%d🐚", days, shells)
					else string.format("%dd +%d🐚", days, shells),
				TextSize = 14,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Parent = chipRow,
			}) :: TextLabel
			TidetownUi.round(chip, 10)
			TidetownUi.stroke(chip, OUTLINE_NAVY, 2.5)
		end
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

	syncRemote.OnClientEvent:Connect(function(kind, payload)
		if kind ~= "bounties" or typeof(payload) ~= "table" then
			return
		end

		bountyList = if typeof(payload.list) == "table" then payload.list else {}
		streakCount = if typeof(payload.streakCount) == "number" then payload.streakCount else 0
		if typeof(payload.milestones) == "table" and #payload.milestones > 0 then
			milestonesState = payload.milestones
		end

		rebuildRows()
		rebuildStreak()
	end)

	rebuildRows()
	rebuildStreak()
end

return BountyGui
