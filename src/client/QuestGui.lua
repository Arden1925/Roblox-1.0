--[[
	Daily quests and the login streak: a shining side button opens the
	board -- three quests with progress bars and claim buttons, plus the
	seven-day streak strip. Also watches the group chest's prompt and the
	welcome-back popup for offline growth. All claims are validated
	server-side; this window renders attributes.
]]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Client = script.Parent
local Toast = require(Client.Toast)
local UiBuilder = require(Client.UiBuilder)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local PANEL_COLOR = Color3.fromRGB(26, 38, 32)
local ROW_COLOR = Color3.fromRGB(44, 62, 52)
local ACCENT_COLOR = Color3.fromRGB(255, 202, 58)
local READY_COLOR = Color3.fromRGB(76, 209, 55)
local LOCKED_COLOR = Color3.fromRGB(72, 84, 96)

-- Streak chip states: claimed days go this green, today's claimable
-- chip glows gold (ACCENT_COLOR), and still-locked days sit dark
-- behind gray chains.
local CLAIMED_COLOR = Color3.fromRGB(84, 178, 108)
local CHAIN_COLOR = Color3.fromRGB(120, 128, 140)
local CHAIN_DARK = Color3.fromRGB(62, 68, 80)

local SECONDS_PER_DAY = 24 * 60 * 60

-- The window is laid out as a running cursor -- quests, then the
-- streak strip, then the claim button -- and sized to fit, so sections
-- can never overlap no matter how many quests the server sends.
local WINDOW_WIDTH = 400
local CONTENT_TOP = 60
local SIDE_MARGIN = 16
local QUEST_ROW_HEIGHT = 56
local QUEST_ROW_SPACING = 6
local SECTION_SPACING = 14
local STREAK_TITLE_HEIGHT = 20
local STREAK_BOX_HEIGHT = 40
local STREAK_BUTTON_HEIGHT = 42
local BOTTOM_MARGIN = 14

local localPlayer = Players.LocalPlayer

-- Set when the countdown loop watches the server clock cross UTC
-- midnight: the server's StreakClaimable attribute stays stale-false
-- until the next claim or rejoin, so the client carries the truth
-- itself until fresh attributes arrive.
local sawMidnightRollover = false

local QuestGui = {}

local function invokeAndToast(remoteName: string, argument: any)
	task.spawn(function()
		local remote = Remotes.get(remoteName) :: RemoteFunction

		-- InvokeServer throws if the server errors mid-call.
		local invoked, _success, message = pcall(function()
			return remote:InvokeServer(argument)
		end)

		Toast.show(if invoked then message else "Something went wrong -- try again.")
	end)
end

local PROTECTED_NAMES = {
	Title = true,
	CloseButton = true,
	HeaderBanner = true,
}

-- Two crossed link bands and a little padlock: the universal "not yet"
-- costume for a locked reward chip.
local function addChains(dayBox: Frame)
	for _, rotation in ipairs({ 35, -35 }) do
		local band = UiBuilder.create("Frame", {
			Name = "ChainBand",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(1.35, 0, 0, 4),
			Rotation = rotation,
			BackgroundColor3 = CHAIN_COLOR,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = dayBox,
		})
		UiBuilder.round(band, 2)

		-- Small dark notches make the band read as chain links rather
		-- than a plain strap.
		for linkIndex = 1, 3 do
			UiBuilder.create("Frame", {
				Name = "ChainLink",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(linkIndex * 0.25, 0, 0.5, 0),
				Size = UDim2.new(0, 3, 0, 2),
				BackgroundColor3 = CHAIN_DARK,
				BorderSizePixel = 0,
				ZIndex = 4,
				Parent = band,
			})
		end
	end

	local lock = UiBuilder.create("Frame", {
		Name = "ChainLock",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 2),
		Size = UDim2.new(0, 12, 0, 10),
		BackgroundColor3 = CHAIN_DARK,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = dayBox,
	})
	UiBuilder.round(lock, 3)

	local shackle = UiBuilder.create("Frame", {
		Name = "ChainShackle",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, 1),
		Size = UDim2.new(0, 8, 0, 5),
		BackgroundColor3 = CHAIN_DARK,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = lock,
	})
	UiBuilder.round(shackle, 3)
end

-- The opposite of chains: a white check and a gold sparkle, worn by
-- chips whose reward is already banked.
local function addClaimedMark(dayBox: Frame)
	UiBuilder.create("TextLabel", {
		Name = "ClaimedCheck",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -1, 0, 1),
		Size = UDim2.new(0, 14, 0, 14),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "\u{2713}",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 13,
		ZIndex = 3,
		Parent = dayBox,
	})

	UiBuilder.create("TextLabel", {
		Name = "ClaimedSparkle",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 1, 1, -1),
		Size = UDim2.new(0, 12, 0, 12),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "\u{2726}",
		TextColor3 = ACCENT_COLOR,
		TextSize = 11,
		ZIndex = 3,
		Parent = dayBox,
	})
end

local function rebuild(container: Frame)
	for _, child in ipairs(container:GetChildren()) do
		local rebuildable = child:IsA("Frame") or child:IsA("TextLabel") or child:IsA("TextButton")
		if rebuildable and not PROTECTED_NAMES[child.Name] then
			child:Destroy()
		end
	end

	local questsJson = localPlayer:GetAttribute("QuestsJson")
	local quests = if typeof(questsJson) == "string" then HttpService:JSONDecode(questsJson) else {}

	local cursorY = CONTENT_TOP

	for questIndex, quest in ipairs(quests) do
		local row = UiBuilder.create("Frame", {
			Name = quest.key,
			Position = UDim2.new(0, SIDE_MARGIN, 0, cursorY),
			Size = UDim2.new(1, -SIDE_MARGIN * 2, 0, QUEST_ROW_HEIGHT),
			BackgroundColor3 = ROW_COLOR,
			BorderSizePixel = 0,
			Parent = container,
		})
		UiBuilder.round(row, 10)
		UiBuilder.stroke(row, if quest.claimed then LOCKED_COLOR else ACCENT_COLOR, 1)

		UiBuilder.create("TextLabel", {
			Position = UDim2.new(0, 10, 0, 4),
			Size = UDim2.new(1, -120, 0, 22),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = quest.description,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})

		local barBackground = UiBuilder.create("Frame", {
			Position = UDim2.new(0, 10, 1, -18),
			Size = UDim2.new(1, -130, 0, 8),
			BackgroundColor3 = LOCKED_COLOR,
			BorderSizePixel = 0,
			Parent = row,
		})
		UiBuilder.round(barBackground, 4)

		local fill = UiBuilder.create("Frame", {
			Size = UDim2.new(math.clamp(quest.progress / quest.target, 0, 1), 0, 1, 0),
			BackgroundColor3 = ACCENT_COLOR,
			BorderSizePixel = 0,
			Parent = barBackground,
		})
		UiBuilder.round(fill, 4)

		local complete = quest.progress >= quest.target
		local claimButton = UiBuilder.create("TextButton", {
			Name = "ClaimButton",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.new(0, 96, 0, 38),
			BackgroundColor3 = if quest.claimed
				then LOCKED_COLOR
				elseif complete then READY_COLOR
				else LOCKED_COLOR,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Text = if quest.claimed
				then "CLAIMED"
				elseif complete then string.format("+%d $", quest.rewardCoins)
				else string.format("%d/%d", quest.progress, quest.target),
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = 14,
			Parent = row,
		}) :: TextButton
		UiBuilder.round(claimButton, 8)
		UiBuilder.hoverPop(claimButton)

		claimButton.Activated:Connect(function()
			invokeAndToast("ClaimQuest", questIndex)
		end)

		cursorY += QUEST_ROW_HEIGHT + QUEST_ROW_SPACING
	end

	cursorY += SECTION_SPACING - QUEST_ROW_SPACING

	-- The streak strip: seven day boxes, tomorrow always visible.
	local streakCount = localPlayer:GetAttribute("StreakCount")
	if typeof(streakCount) ~= "number" then
		streakCount = 0
	end
	local claimable = localPlayer:GetAttribute("StreakClaimable") == true or sawMidnightRollover

	UiBuilder.create("TextLabel", {
		Name = "StreakTitle",
		Position = UDim2.new(0, SIDE_MARGIN, 0, cursorY),
		Size = UDim2.new(1, -SIDE_MARGIN * 2, 0, STREAK_TITLE_HEIGHT),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = string.format("LOGIN STREAK -- DAY %d", streakCount),
		TextColor3 = ACCENT_COLOR,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = container,
	})

	cursorY += STREAK_TITLE_HEIGHT + QUEST_ROW_SPACING

	-- The strip wraps every seven days; day 8 lights one box again. A
	-- streak of zero must light nothing, and (0 - 1) % 7 is 6 in Luau,
	-- so the zero case cannot share the modulo expression. Claimed days
	-- are green with a check, today's claimable chip glows gold, and
	-- locked days sit dark behind chains.
	local cycleClaimed = if streakCount > 0 then (streakCount - 1) % 7 + 1 else 0
	local todayIndex = 0
	if claimable then
		-- A finished row rolls over: the next claim starts a fresh cycle.
		if cycleClaimed >= 7 then
			cycleClaimed = 0
		end
		todayIndex = cycleClaimed + 1
	end

	for dayIndex = 1, 7 do
		local claimed = dayIndex <= cycleClaimed
		local isToday = dayIndex == todayIndex

		local dayBox = UiBuilder.create("Frame", {
			Name = "Day" .. dayIndex,
			Position = UDim2.new(0, SIDE_MARGIN + (dayIndex - 1) * 52, 0, cursorY),
			Size = UDim2.new(0, 46, 0, STREAK_BOX_HEIGHT),
			BackgroundColor3 = if claimed
				then CLAIMED_COLOR
				elseif isToday then ACCENT_COLOR
				else ROW_COLOR,
			BorderSizePixel = 0,
			Parent = container,
		})
		UiBuilder.round(dayBox, 8)

		UiBuilder.create("TextLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = string.format("%d\n$%d", dayIndex, GameConfig.streakRewards[dayIndex].coins),
			TextColor3 = if claimed or isToday
				then Color3.fromRGB(255, 255, 255)
				else Color3.fromRGB(178, 190, 195),
			TextSize = 12,
			Parent = dayBox,
		})

		if claimed then
			addClaimedMark(dayBox)
		elseif isToday then
			local stroke = UiBuilder.stroke(dayBox, Color3.fromRGB(255, 255, 255), 2)
			UiBuilder.pulse(stroke)
		else
			addChains(dayBox)
		end
	end

	cursorY += STREAK_BOX_HEIGHT + SECTION_SPACING

	local streakButton = UiBuilder.create("TextButton", {
		Name = "StreakButton",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, cursorY),
		Size = UDim2.new(1, -SIDE_MARGIN * 2, 0, STREAK_BUTTON_HEIGHT),
		BackgroundColor3 = if claimable then READY_COLOR else LOCKED_COLOR,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		Text = if claimable then "CLAIM TODAY'S REWARD" else "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 16,
		Parent = container,
	}) :: TextButton
	UiBuilder.round(streakButton, 10)
	UiBuilder.hoverPop(streakButton)

	if claimable then
		streakButton.Activated:Connect(function()
			invokeAndToast("ClaimStreak", nil)
		end)
	else
		-- Already claimed: the button becomes a live countdown to the
		-- next reward. The server's day boundary is UTC, so the time
		-- left falls straight out of the server clock. The server only
		-- republishes StreakClaimable on claims and joins, so when the
		-- clock crosses midnight this loop rebuilds the window itself
		-- to flip into the claimable state. The loop dies with the
		-- button on the next rebuild.
		local builtDay = math.floor(Workspace:GetServerTimeNow() / SECONDS_PER_DAY)
		task.spawn(function()
			while streakButton.Parent ~= nil do
				local serverNow = math.floor(Workspace:GetServerTimeNow())
				if math.floor(serverNow / SECONDS_PER_DAY) > builtDay then
					sawMidnightRollover = true
					rebuild(container)
					break
				end

				local secondsLeft = SECONDS_PER_DAY - serverNow % SECONDS_PER_DAY
				streakButton.Text = string.format(
					"NEXT REWARD IN %02d:%02d:%02d",
					math.floor(secondsLeft / 3600),
					math.floor(secondsLeft / 60) % 60,
					secondsLeft % 60
				)
				task.wait(1)
			end
		end)
	end

	cursorY += STREAK_BUTTON_HEIGHT + BOTTOM_MARGIN
	container.Size = UDim2.new(0, WINDOW_WIDTH, 0, cursorY)
end

-- The welcome-back popup for offline growth, shown once per session.
local function showOfflinePopup(parent: Instance, gain: number)
	local popup = UiBuilder.create("Frame", {
		Name = "WelcomeBack",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.new(0, 340, 0, 92),
		BackgroundColor3 = PANEL_COLOR,
		BorderSizePixel = 0,
		Parent = parent,
	}) :: Frame
	UiBuilder.round(popup, 14)
	local stroke = UiBuilder.stroke(popup, READY_COLOR, 2)
	UiBuilder.pulse(stroke)

	local title = UiBuilder.create("TextLabel", {
		Position = UDim2.new(0, 0, 0, 10),
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "WELCOME BACK!",
		TextColor3 = READY_COLOR,
		TextSize = 22,
		Parent = popup,
	}) :: TextLabel
	UiBuilder.shineText(title)

	UiBuilder.create("TextLabel", {
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = string.format("You grew +%d Max Size while away!", gain),
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 17,
		Parent = popup,
	})

	UiBuilder.popOpen(popup)
	task.delay(5, function()
		popup:Destroy()
	end)
end

function QuestGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = UiBuilder.create("ScreenGui", {
		Name = "QuestGui",
		ResetOnSpawn = false,
		DisplayOrder = 6,
		Parent = playerGui,
	})

	local window = UiBuilder.create("Frame", {
		Name = "QuestWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, WINDOW_WIDTH, 0, 350),
		BackgroundColor3 = PANEL_COLOR,
		BorderSizePixel = 0,
		Visible = false,
		Parent = screenGui,
	}) :: Frame
	UiBuilder.round(window, 16)
	UiBuilder.stroke(window, ACCENT_COLOR, 2)

	UiBuilder.create("TextLabel", {
		Name = "Title",
		Position = UDim2.new(0, 16, 0, 8),
		Size = UDim2.new(1, -70, 0, 30),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "DAILY QUESTS",
		TextColor3 = ACCENT_COLOR,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window,
	})

	local closeButton = UiBuilder.create("TextButton", {
		Name = "CloseButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.new(0, 34, 0, 34),
		BackgroundColor3 = Color3.fromRGB(232, 65, 24),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "X",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 18,
		ZIndex = 2,
		Parent = window,
	}) :: TextButton
	UiBuilder.round(closeButton, 8)
	UiBuilder.hoverPop(closeButton)

	closeButton.Activated:Connect(function()
		window.Visible = false
	end)

	UiBuilder.cartoonizeWindow(window, Color3.fromRGB(255, 177, 66))

	QuestGui.toggle = function()
		if window.Visible then
			window.Visible = false
		else
			rebuild(window)
			UiBuilder.popOpen(window)
		end
	end

	-- Claiming the streak changes StreakCount/StreakClaimable but sends
	-- QuestsJson back byte-identical, which fires no changed signal -- so
	-- the streak attributes must trigger a rebuild themselves.
	local function rebuildIfVisible()
		if window.Visible then
			rebuild(window)
		end
	end

	localPlayer:GetAttributeChangedSignal("QuestsJson"):Connect(rebuildIfVisible)

	-- Fresh streak attributes from the server supersede the client's
	-- midnight-rollover guess -- but only streak changes may clear it,
	-- or routine quest progress would revert an unlocked claim.
	for _, attributeName in ipairs({ "StreakCount", "StreakClaimable" }) do
		localPlayer:GetAttributeChangedSignal(attributeName):Connect(function()
			sawMidnightRollover = false
			rebuildIfVisible()
		end)
	end

	-- Group chest prompts: claim through the server and toast the reply.
	local function watchChest(chest: Instance)
		local prompt = chest:FindFirstChildOfClass("ProximityPrompt")
		if prompt ~= nil then
			prompt.Triggered:Connect(function(playerWhoTriggered)
				if playerWhoTriggered == localPlayer then
					invokeAndToast("ClaimGroupChest", nil)
				end
			end)
		end
	end

	for _, chest in ipairs(CollectionService:GetTagged("GroupChest")) do
		watchChest(chest)
	end
	CollectionService:GetInstanceAddedSignal("GroupChest"):Connect(watchChest)

	-- Offline growth popup: the attribute may already be set or may
	-- arrive shortly after join.
	local shown = false
	local function maybeShowOffline()
		local gain = localPlayer:GetAttribute("OfflineGain")
		if not shown and typeof(gain) == "number" and gain > 0 then
			shown = true
			showOfflinePopup(screenGui, gain)
		end
	end

	localPlayer:GetAttributeChangedSignal("OfflineGain"):Connect(maybeShowOffline)
	maybeShowOffline()
end

-- Replaced at start(); declared so ShopGui can wire its side button.
QuestGui.toggle = function() end

return QuestGui
