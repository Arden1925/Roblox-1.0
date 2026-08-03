--[[
	The rebirth page: the requirement bar, a NOW vs AFTER table of every
	perk rebirthing improves, and the big button that starts the machine.
	Everything is computed from the same config and formulas the server
	uses, so the preview always matches what the machine delivers.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent
local Toast = require(Client.Toast)
local UiBuilder = require(Client.UiBuilder)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)
local SizeFormula = require(Shared.SizeFormula)

local PANEL_COLOR = Color3.fromRGB(30, 26, 46)
local ROW_COLOR = Color3.fromRGB(52, 46, 75)
local ACCENT_COLOR = Color3.fromRGB(190, 120, 255)
local READY_COLOR = Color3.fromRGB(76, 209, 55)
local LOCKED_COLOR = Color3.fromRGB(72, 84, 96)

local localPlayer = Players.LocalPlayer

local RebirthGui = {}

local window: Frame? = nil

local function perkRows(rebirths: number): { { string } }
	local flags =
		{ doubleRebirthBonus = localPlayer:GetAttribute("OwnsDoubleRebirthBonus") == true }
	local nowMultiplier = SizeFormula.growthMultiplier(rebirths, flags)
	local afterMultiplier = SizeFormula.growthMultiplier(rebirths + 1, flags)

	return {
		{
			"Growth speed",
			string.format("x%.2f", nowMultiplier),
			string.format("x%.2f", afterMultiplier),
		},
		{
			"Coin bonus",
			string.format("+%d%%", rebirths * GameConfig.rebirth.coinBonusPerRebirth * 100),
			string.format("+%d%%", (rebirths + 1) * GameConfig.rebirth.coinBonusPerRebirth * 100),
		},
		{
			"Egg luck",
			string.format("+%d%%", rebirths * GameConfig.rebirth.luckPerRebirth * 100),
			string.format("+%d%%", (rebirths + 1) * GameConfig.rebirth.luckPerRebirth * 100),
		},
		{ "Max Size", "keeps growing", "resets to 0" },
	}
end

local function rebuild(container: Frame)
	for _, child in ipairs(container:GetChildren()) do
		local rebuildable = child:IsA("Frame") or child:IsA("TextLabel") or child:IsA("TextButton")
		if rebuildable and child.Name ~= "Title" and child.Name ~= "CloseButton" then
			child:Destroy()
		end
	end

	local rebirths = localPlayer:GetAttribute("Rebirths")
	local maxSize = localPlayer:GetAttribute("MaxSize")
	if typeof(rebirths) ~= "number" or typeof(maxSize) ~= "number" then
		return
	end

	local requiredSize = SizeFormula.requiredSizeForRebirth(rebirths)
	local ready = maxSize >= requiredSize

	UiBuilder.create("TextLabel", {
		Name = "Progress",
		Position = UDim2.new(0, 16, 0, 44),
		Size = UDim2.new(1, -32, 0, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = string.format("Max Size: %d / %d needed", maxSize, requiredSize),
		TextColor3 = if ready then READY_COLOR else Color3.fromRGB(255, 255, 255),
		TextSize = 17,
		Parent = container,
	})

	local barBackground = UiBuilder.create("Frame", {
		Name = "BarBackground",
		Position = UDim2.new(0, 16, 0, 70),
		Size = UDim2.new(1, -32, 0, 12),
		BackgroundColor3 = LOCKED_COLOR,
		BorderSizePixel = 0,
		Parent = container,
	})
	UiBuilder.round(barBackground, 6)

	local fill = UiBuilder.create("Frame", {
		Name = "BarFill",
		Size = UDim2.new(math.clamp(maxSize / requiredSize, 0, 1), 0, 1, 0),
		BackgroundColor3 = if ready then READY_COLOR else ACCENT_COLOR,
		BorderSizePixel = 0,
		Parent = barBackground,
	})
	UiBuilder.round(fill, 6)

	-- The NOW vs AFTER table: three columns, one row per perk.
	local headerRow = UiBuilder.create("Frame", {
		Name = "HeaderRow",
		Position = UDim2.new(0, 16, 0, 94),
		Size = UDim2.new(1, -32, 0, 22),
		BackgroundTransparency = 1,
		Parent = container,
	})

	for columnIndex, headerText in ipairs({ "PERK", "NOW", "AFTER" }) do
		UiBuilder.create("TextLabel", {
			Position = UDim2.new((columnIndex - 1) * 0.4, 0, 0, 0),
			Size = UDim2.new(if columnIndex == 1 then 0.4 else 0.3, 0, 1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Text = headerText,
			TextColor3 = ACCENT_COLOR,
			TextSize = 13,
			TextXAlignment = if columnIndex == 1
				then Enum.TextXAlignment.Left
				else Enum.TextXAlignment.Center,
			Parent = headerRow,
		})
	end

	for rowIndex, row in ipairs(perkRows(rebirths)) do
		local rowFrame = UiBuilder.create("Frame", {
			Name = row[1],
			Position = UDim2.new(0, 16, 0, 96 + rowIndex * 34),
			Size = UDim2.new(1, -32, 0, 30),
			BackgroundColor3 = ROW_COLOR,
			BorderSizePixel = 0,
			Parent = container,
		})
		UiBuilder.round(rowFrame, 8)

		for columnIndex, cellText in ipairs(row) do
			UiBuilder.create("TextLabel", {
				Position = UDim2.new(
					(columnIndex - 1) * 0.4,
					if columnIndex == 1 then 10 else 0,
					0,
					0
				),
				Size = UDim2.new(if columnIndex == 1 then 0.4 else 0.3, 0, 1, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Text = cellText,
				TextColor3 = if columnIndex == 3
					then Color3.fromRGB(255, 234, 167)
					else Color3.fromRGB(255, 255, 255),
				TextSize = 14,
				TextXAlignment = if columnIndex == 1
					then Enum.TextXAlignment.Left
					else Enum.TextXAlignment.Center,
				Parent = rowFrame,
			})
		end
	end

	local rebirthButton = UiBuilder.create("TextButton", {
		Name = "RebirthButton",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(1, -32, 0, 52),
		BackgroundColor3 = if ready then READY_COLOR else LOCKED_COLOR,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		Text = if ready then "ENTER THE MACHINE" else "KEEP GROWING...",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 20,
		Parent = container,
	}) :: TextButton
	UiBuilder.round(rebirthButton, 12)
	UiBuilder.hoverPop(rebirthButton)

	if ready then
		local stroke = UiBuilder.stroke(rebirthButton, Color3.fromRGB(255, 255, 255), 2)
		UiBuilder.pulse(stroke)
	end

	rebirthButton.Activated:Connect(function()
		task.spawn(function()
			local attemptRebirth = Remotes.get("AttemptRebirth") :: RemoteFunction

			-- InvokeServer throws if the server errors mid-call.
			local invoked, _success, message = pcall(function()
				return attemptRebirth:InvokeServer()
			end)

			Toast.show(if invoked then message else "Something went wrong -- try again.")

			if invoked and window ~= nil then
				window.Visible = false
			end
		end)
	end)
end

function RebirthGui.open()
	if window == nil then
		return
	end

	rebuild(window)
	UiBuilder.popOpen(window)
end

function RebirthGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = UiBuilder.create("ScreenGui", {
		Name = "RebirthGui",
		ResetOnSpawn = false,
		DisplayOrder = 7,
		Parent = playerGui,
	})

	local builtWindow = UiBuilder.create("Frame", {
		Name = "RebirthWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 420, 0, 330),
		BackgroundColor3 = PANEL_COLOR,
		BorderSizePixel = 0,
		Visible = false,
		Parent = screenGui,
	}) :: Frame
	UiBuilder.round(builtWindow, 16)
	UiBuilder.stroke(builtWindow, ACCENT_COLOR, 2)
	UiBuilder.gradient(builtWindow, Color3.fromRGB(58, 44, 92), PANEL_COLOR)

	UiBuilder.create("TextLabel", {
		Name = "Title",
		Position = UDim2.new(0, 16, 0, 10),
		Size = UDim2.new(1, -70, 0, 30),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "REBIRTH MACHINE",
		TextColor3 = ACCENT_COLOR,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = builtWindow,
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
		ZIndex = 2,
		Parent = builtWindow,
	}) :: TextButton
	UiBuilder.round(closeButton, 8)
	UiBuilder.hoverPop(closeButton)

	closeButton.Activated:Connect(function()
		builtWindow.Visible = false
	end)

	window = builtWindow

	-- Live refresh while the page is open, so the bar fills in front of
	-- the player as they grow.
	localPlayer:GetAttributeChangedSignal("MaxSize"):Connect(function()
		if builtWindow.Visible then
			rebuild(builtWindow)
		end
	end)
end

return RebirthGui
