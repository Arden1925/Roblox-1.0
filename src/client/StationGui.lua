--[[
	The coin shop at every world's Station: potions on the left, the
	permanent upgrades (with their ever-rising prices) on the right.
	Also drives the Mystery Machine prompt. Prices shown here are
	recomputed from the same config the server uses, and every purchase
	is validated server-side.
]]

local CollectionService = game:GetService("CollectionService")
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
local POTION_COLOR = Color3.fromRGB(0, 206, 201)
local UPGRADE_COLOR = Color3.fromRGB(255, 159, 67)

local localPlayer = Players.LocalPlayer

local StationGui = {}

local function upgradeCost(upgrade: { [string]: any }): number?
	local level = localPlayer:GetAttribute("Upgrade" .. upgrade.key)
	if typeof(level) ~= "number" then
		level = 0
	end

	if level >= upgrade.maxLevel then
		return nil
	end

	return math.floor(upgrade.baseCost * upgrade.costGrowth ^ level)
end

local function createItemCard(
	parent: Instance,
	order: number,
	titleText: string,
	bodyText: string,
	buttonText: string,
	accent: Color3,
	onBuy: () -> ()
)
	local card = UiBuilder.create("Frame", {
		Name = titleText,
		LayoutOrder = order,
		Size = UDim2.new(1, -12, 0, 96),
		BackgroundColor3 = CARD_COLOR,
		BorderSizePixel = 0,
		Parent = parent,
	})
	UiBuilder.round(card, 10)
	UiBuilder.stroke(card, accent, 1)

	UiBuilder.create("TextLabel", {
		Position = UDim2.new(0, 10, 0, 6),
		Size = UDim2.new(1, -20, 0, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = titleText,
		TextColor3 = accent,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	UiBuilder.create("TextLabel", {
		Position = UDim2.new(0, 10, 0, 28),
		Size = UDim2.new(1, -20, 0, 30),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = bodyText,
		TextColor3 = Color3.fromRGB(210, 218, 226),
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})

	local buyButton = UiBuilder.create("TextButton", {
		Name = "BuyButton",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -20, 0, 30),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = buttonText,
		TextColor3 = Color3.fromRGB(24, 30, 38),
		TextSize = 14,
		Parent = card,
	})
	UiBuilder.round(buyButton, 8)
	UiBuilder.hoverPop(buyButton)

	buyButton.Activated:Connect(onBuy)
end

local function invokeAndToast(remoteName: string, argument: string?)
	task.spawn(function()
		local remote = Remotes.get(remoteName) :: RemoteFunction

		-- InvokeServer throws if the server errors mid-call.
		local invoked, _success, message = pcall(function()
			return remote:InvokeServer(argument)
		end)

		Toast.show(if invoked then message else "Something went wrong -- try again.")
	end)
end

local function openStation(window: Frame, worldIndex: number)
	for _, child in ipairs(window:GetChildren()) do
		local clearable = child:IsA("Frame") or child:IsA("TextLabel")
		if clearable and child.Name ~= "CloseButton" and child.Name ~= "HeaderBanner" then
			child:Destroy()
		end
	end

	-- The corner tab renames itself to the current world's station.
	local banner = window:FindFirstChild("HeaderBanner")
	local bannerTitle = if banner ~= nil then banner:FindFirstChild("Title") else nil
	if bannerTitle ~= nil and bannerTitle:IsA("TextLabel") then
		bannerTitle.Text = string.upper(GameConfig.worlds[worldIndex].name)
	end

	local columns = {
		{ name = "PotionColumn", header = "POTIONS", accent = POTION_COLOR, x = 0 },
		{ name = "UpgradeColumn", header = "FOREVER UPGRADES", accent = UPGRADE_COLOR, x = 0.5 },
	}

	local columnFrames = {}
	for _, column in ipairs(columns) do
		UiBuilder.create("TextLabel", {
			Name = column.header,
			Position = UDim2.new(column.x, 16, 0, 46),
			Size = UDim2.new(0.5, -24, 0, 22),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Text = column.header,
			TextColor3 = column.accent,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = window,
		})

		local columnFrame = UiBuilder.create("ScrollingFrame", {
			Name = column.name,
			Position = UDim2.new(column.x, 12, 0, 72),
			Size = UDim2.new(0.5, -20, 1, -84),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 4,
			Parent = window,
		})

		UiBuilder.create("UIListLayout", {
			Padding = UDim.new(0, 8),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = columnFrame,
		})

		columnFrames[column.name] = columnFrame
	end

	for order, potion in ipairs(GameConfig.potions) do
		local cost = potion.baseCost * worldIndex
		createItemCard(
			columnFrames.PotionColumn,
			order,
			potion.name,
			potion.description,
			string.format("BUY -- %d COINS", cost),
			POTION_COLOR,
			function()
				invokeAndToast("BuyPotion", potion.key)
			end
		)
	end

	for order, upgrade in ipairs(GameConfig.upgrades) do
		local cost = upgradeCost(upgrade)
		local level = localPlayer:GetAttribute("Upgrade" .. upgrade.key)
		if typeof(level) ~= "number" then
			level = 0
		end

		createItemCard(
			columnFrames.UpgradeColumn,
			order,
			string.format("%s  Lv.%d", upgrade.name, level),
			upgrade.description,
			if cost ~= nil then string.format("UPGRADE -- %d COINS", cost) else "MAX LEVEL",
			UPGRADE_COLOR,
			function()
				invokeAndToast("BuyUpgrade", upgrade.key)
				-- Rebuild so the next price shows immediately.
				task.delay(0.3, openStation, window, worldIndex)
			end
		)
	end

	UiBuilder.popOpen(window)
end

function StationGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = UiBuilder.create("ScreenGui", {
		Name = "StationGui",
		ResetOnSpawn = false,
		DisplayOrder = 6,
		Parent = playerGui,
	})

	local window = UiBuilder.create("Frame", {
		Name = "StationWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 560, 0, 430),
		BackgroundColor3 = PANEL_COLOR,
		BorderSizePixel = 0,
		Visible = false,
		Parent = screenGui,
	}) :: Frame
	UiBuilder.round(window, 16)
	UiBuilder.stroke(window, POTION_COLOR, 2)

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
		ZIndex = 2,
		Parent = window,
	})
	UiBuilder.round(closeButton, 8)

	closeButton.Activated:Connect(function()
		window.Visible = false
	end)

	UiBuilder.cartoonizeWindow(window, POTION_COLOR, "STATION")

	local function watchStation(station: Instance)
		local prompt = station:FindFirstChildOfClass("ProximityPrompt")
		if prompt == nil then
			return
		end

		prompt.Triggered:Connect(function(playerWhoTriggered)
			local worldIndex = station:GetAttribute("WorldIndex")
			if playerWhoTriggered == localPlayer and typeof(worldIndex) == "number" then
				openStation(window, worldIndex)
			end
		end)
	end

	local function watchMachine(machine: Instance)
		local prompt = machine:FindFirstChildOfClass("ProximityPrompt")
		if prompt == nil then
			return
		end

		prompt.Triggered:Connect(function(playerWhoTriggered)
			if playerWhoTriggered == localPlayer then
				invokeAndToast("UseMysteryMachine", nil)
			end
		end)
	end

	for _, station in ipairs(CollectionService:GetTagged("ShopStation")) do
		watchStation(station)
	end
	CollectionService:GetInstanceAddedSignal("ShopStation"):Connect(watchStation)

	for _, machine in ipairs(CollectionService:GetTagged("MysteryMachine")) do
		watchMachine(machine)
	end
	CollectionService:GetInstanceAddedSignal("MysteryMachine"):Connect(watchMachine)
end

return StationGui
