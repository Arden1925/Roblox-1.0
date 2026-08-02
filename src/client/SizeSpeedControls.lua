--[[
	The slider panel on the right edge: speed for everyone (a narrow,
	comfort-only range) and body size for Size Master owners. The size
	slider is this pass's entire product, so non-owners see it locked
	with a one-tap purchase prompt.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent
local Toast = require(Client.Toast)
local UiBuilder = require(Client.UiBuilder)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local PANEL_COLOR = Color3.fromRGB(24, 30, 38)
local SPEED_COLOR = Color3.fromRGB(0, 206, 201)
local SIZE_COLOR = Color3.fromRGB(255, 159, 67)

local localPlayer = Players.LocalPlayer

local SizeSpeedControls = {}

local function sizeMasterPass(): { [string]: any }?
	for _, pass in ipairs(GameConfig.passes) do
		if pass.key == "SizeMaster" then
			return pass
		end
	end

	return nil
end

local function createSliderSection(
	parent: Instance,
	order: number,
	titleText: string,
	accent: Color3
): Frame
	local section = UiBuilder.create("Frame", {
		Name = titleText .. "Section",
		LayoutOrder = order,
		Size = UDim2.new(1, -16, 0, 64),
		BackgroundTransparency = 1,
		Parent = parent,
	})

	UiBuilder.create("TextLabel", {
		Name = "SectionTitle",
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = titleText,
		TextColor3 = accent,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = section,
	})

	return section :: Frame
end

function SizeSpeedControls.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = UiBuilder.create("ScreenGui", {
		Name = "SizeSpeedControls",
		ResetOnSpawn = false,
		Parent = playerGui,
	})

	local panel = UiBuilder.create("Frame", {
		Name = "SliderPanel",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 60),
		Size = UDim2.new(0, 190, 0, 160),
		BackgroundColor3 = PANEL_COLOR,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Parent = screenGui,
	})
	UiBuilder.round(panel, 12)

	local layout = UiBuilder.create("UIListLayout", {
		Padding = UDim.new(0, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = panel,
	})

	UiBuilder.create("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		Parent = panel,
	})

	-- The layout variable exists only to make the padding/order intent
	-- readable; silence the unused warning.
	local _ = layout

	local speedSection = createSliderSection(panel, 1, "SPEED", SPEED_COLOR)
	local sliderHolder = UiBuilder.create("Frame", {
		Name = "SpeedSliderHolder",
		Position = UDim2.new(0, 0, 0, 30),
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Parent = speedSection,
	})

	UiBuilder.slider(
		sliderHolder,
		GameConfig.speed.minimum,
		GameConfig.speed.maximum,
		GameConfig.speed.default,
		SPEED_COLOR,
		function(value)
			task.spawn(function()
				local setDesiredSpeed = Remotes.get("SetDesiredSpeed") :: RemoteEvent
				setDesiredSpeed:FireServer(value)
			end)
		end
	)

	local sizeSection = createSliderSection(panel, 2, "SIZE (SIZE MASTER)", SIZE_COLOR)
	local sizeHolder = UiBuilder.create("Frame", {
		Name = "SizeSliderHolder",
		Position = UDim2.new(0, 0, 0, 30),
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Parent = sizeSection,
	})

	local function buildSizeControl()
		for _, child in ipairs(sizeHolder:GetChildren()) do
			child:Destroy()
		end

		if localPlayer:GetAttribute("OwnsSizeMaster") == true then
			UiBuilder.slider(sizeHolder, 0, 1, 1, SIZE_COLOR, function(fraction)
				local maxSize = localPlayer:GetAttribute("MaxSize")
				if typeof(maxSize) ~= "number" then
					return
				end

				local shrunk = GameConfig.shrink.shrunkSize
				local target = shrunk + (maxSize - shrunk) * fraction

				task.spawn(function()
					local setDesiredSize = Remotes.get("SetDesiredSize") :: RemoteEvent
					setDesiredSize:FireServer(target)
				end)
			end)
		else
			local unlockButton = UiBuilder.create("TextButton", {
				Name = "UnlockButton",
				Size = UDim2.new(1, 0, 1, 4),
				BackgroundColor3 = SIZE_COLOR,
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBold,
				Text = "\u{1F512} UNLOCK -- R$ 999",
				TextColor3 = Color3.fromRGB(24, 30, 38),
				TextSize = 14,
				Parent = sizeHolder,
			}) :: TextButton
			UiBuilder.round(unlockButton, 8)
			UiBuilder.hoverPop(unlockButton)

			unlockButton.Activated:Connect(function()
				local pass = sizeMasterPass()
				if pass ~= nil and pass.gamePassId ~= 0 then
					MarketplaceService:PromptGamePassPurchase(localPlayer, pass.gamePassId)
				else
					Toast.show("Size Master unlocks once the game is published!")
				end
			end)
		end
	end

	localPlayer:GetAttributeChangedSignal("OwnsSizeMaster"):Connect(buildSizeControl)
	buildSizeControl()
end

return SizeSpeedControls
