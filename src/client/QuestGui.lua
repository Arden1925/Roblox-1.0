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

local localPlayer = Players.LocalPlayer

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

local function rebuild(container: Frame)
	for _, child in ipairs(container:GetChildren()) do
		local rebuildable = child:IsA("Frame") or child:IsA("TextLabel") or child:IsA("TextButton")
		if rebuildable and child.Name ~= "Title" and child.Name ~= "CloseButton" then
			child:Destroy()
		end
	end

	local questsJson = localPlayer:GetAttribute("QuestsJson")
	local quests = if typeof(questsJson) == "string" then HttpService:JSONDecode(questsJson) else {}

	for questIndex, quest in ipairs(quests) do
		local row = UiBuilder.create("Frame", {
			Name = quest.key,
			Position = UDim2.new(0, 16, 0, 8 + questIndex * 62),
			Size = UDim2.new(1, -32, 0, 56),
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
	end

	-- The streak strip: seven day boxes, tomorrow always visible.
	local streakCount = localPlayer:GetAttribute("StreakCount")
	if typeof(streakCount) ~= "number" then
		streakCount = 0
	end
	local claimable = localPlayer:GetAttribute("StreakClaimable") == true

	UiBuilder.create("TextLabel", {
		Name = "StreakTitle",
		Position = UDim2.new(0, 16, 0, 208),
		Size = UDim2.new(1, -32, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = string.format("LOGIN STREAK -- DAY %d", streakCount),
		TextColor3 = ACCENT_COLOR,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = container,
	})

	for dayIndex = 1, 7 do
		local reached = dayIndex <= (streakCount - 1) % 7 + (if streakCount > 0 then 1 else 0)
		local dayBox = UiBuilder.create("Frame", {
			Name = "Day" .. dayIndex,
			Position = UDim2.new(0, 16 + (dayIndex - 1) * 52, 0, 232),
			Size = UDim2.new(0, 46, 0, 40),
			BackgroundColor3 = if reached then ACCENT_COLOR else ROW_COLOR,
			BorderSizePixel = 0,
			Parent = container,
		})
		UiBuilder.round(dayBox, 8)

		UiBuilder.create("TextLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = string.format("%d\n$%d", dayIndex, GameConfig.streakRewards[dayIndex].coins),
			TextColor3 = if reached
				then Color3.fromRGB(26, 38, 32)
				else Color3.fromRGB(255, 255, 255),
			TextSize = 12,
			Parent = dayBox,
		})
	end

	local streakButton = UiBuilder.create("TextButton", {
		Name = "StreakButton",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -32, 0, 42),
		BackgroundColor3 = if claimable then READY_COLOR else LOCKED_COLOR,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		Text = if claimable then "CLAIM TODAY'S REWARD" else "COME BACK TOMORROW",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 16,
		Parent = container,
	}) :: TextButton
	UiBuilder.round(streakButton, 10)
	UiBuilder.hoverPop(streakButton)

	streakButton.Activated:Connect(function()
		invokeAndToast("ClaimStreak", nil)
	end)
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
		Size = UDim2.new(0, 400, 0, 350),
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

	QuestGui.toggle = function()
		if window.Visible then
			window.Visible = false
		else
			rebuild(window)
			UiBuilder.popOpen(window)
		end
	end

	localPlayer:GetAttributeChangedSignal("QuestsJson"):Connect(function()
		if window.Visible then
			rebuild(window)
		end
	end)

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
