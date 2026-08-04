--[[
	The portal destination picker. Walking up to any portal and triggering
	its prompt opens a list of every world: reached ones get a teleport
	button, unreached ones get a wobbling lock that explains itself when
	clicked. The server re-validates every teleport, so this UI can only
	ever ask.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Client = script.Parent
local Toast = require(Client.Toast)
local UiBuilder = require(Client.UiBuilder)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local PORTAL_TAG = "Portal"

local PANEL_COLOR = Color3.fromRGB(30, 39, 46)
local ROW_COLOR = Color3.fromRGB(47, 54, 64)
local UNLOCKED_COLOR = Color3.fromRGB(156, 136, 255)
local LOCKED_COLOR = Color3.fromRGB(72, 84, 96)

local LOCK_WOBBLE_INFO =
	TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local localPlayer = Players.LocalPlayer

local PortalGui = {}

local function createWorldRow(parent: Instance, worldIndex: number, window: Frame)
	local world = GameConfig.worlds[worldIndex]
	local reached = localPlayer:GetAttribute("ReachedWorld")
	local unlocked = typeof(reached) == "number" and reached >= worldIndex

	local row = UiBuilder.create("Frame", {
		Name = world.name,
		LayoutOrder = worldIndex,
		Size = UDim2.new(1, -16, 0, 56),
		BackgroundColor3 = ROW_COLOR,
		BorderSizePixel = 0,
		Parent = parent,
	})

	UiBuilder.create("UICorner", {
		CornerRadius = UDim.new(0, 10),
		Parent = row,
	})

	UiBuilder.create("TextLabel", {
		Name = "WorldName",
		Position = UDim2.new(0, 12, 0, 0),
		Size = UDim2.new(1, -140, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = string.format("%d. %s", worldIndex, world.name),
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local actionButton = UiBuilder.create("TextButton", {
		Name = "ActionButton",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, 110, 0, 38),
		BackgroundColor3 = if unlocked then UNLOCKED_COLOR else LOCKED_COLOR,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = if unlocked then "TELEPORT" else "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 16,
		Parent = row,
	})

	UiBuilder.create("UICorner", {
		CornerRadius = UDim.new(0, 10),
		Parent = actionButton,
	})

	if unlocked then
		actionButton.Activated:Connect(function()
			task.spawn(function()
				local requestTeleport = Remotes.get("RequestTeleport") :: RemoteFunction

				-- InvokeServer throws if the server errors mid-call; a
				-- toast beats a silent dead button.
				local invoked, success, message = pcall(function()
					return requestTeleport:InvokeServer(worldIndex)
				end)

				if invoked then
					Toast.show(message)
					if success then
						window.Visible = false
					end
				else
					Toast.show("Something went wrong -- try again.")
				end
			end)
		end)
	else
		local lockLabel = UiBuilder.create("TextLabel", {
			Name = "LockIcon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(0, 30, 0, 30),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = "\u{1F512}",
			TextSize = 22,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Rotation = -10,
			Parent = actionButton,
		})

		local wobbleTween = TweenService:Create(lockLabel, LOCK_WOBBLE_INFO, {
			Rotation = 10,
		})
		wobbleTween:Play()

		actionButton.Activated:Connect(function()
			Toast.show("You haven't met the requirements -- reach this world on foot first!")
		end)
	end
end

local function buildWindow(parent: Instance): Frame
	local window = UiBuilder.create("Frame", {
		Name = "PortalWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 380, 0, 330),
		BackgroundColor3 = PANEL_COLOR,
		BorderSizePixel = 0,
		Visible = false,
		Parent = parent,
	})

	UiBuilder.create("UICorner", {
		CornerRadius = UDim.new(0, 14),
		Parent = window,
	})

	UiBuilder.create("TextLabel", {
		Name = "Title",
		Position = UDim2.new(0, 16, 0, 8),
		Size = UDim2.new(1, -60, 0, 32),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "CHOOSE DESTINATION",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window,
	})

	local closeButton = UiBuilder.create("TextButton", {
		Name = "CloseButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.new(0, 32, 0, 32),
		BackgroundColor3 = Color3.fromRGB(232, 65, 24),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "X",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 18,
		Parent = window,
	})

	UiBuilder.create("UICorner", {
		CornerRadius = UDim.new(0, 8),
		Parent = closeButton,
	})

	closeButton.Activated:Connect(function()
		window.Visible = false
	end)

	local rowList = UiBuilder.create("ScrollingFrame", {
		Name = "RowList",
		Position = UDim2.new(0, 8, 0, 48),
		Size = UDim2.new(1, -16, 1, -56),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = window,
	})
	UiBuilder.bubbly(rowList)

	UiBuilder.create("UIListLayout", {
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = rowList,
	})

	UiBuilder.cartoonizeWindow(window, Color3.fromRGB(97, 200, 66))

	return window :: Frame
end

function PortalGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = UiBuilder.create("ScreenGui", {
		Name = "PortalGui",
		ResetOnSpawn = false,
		Parent = playerGui,
	})

	local window = buildWindow(screenGui)
	local rowList = window:FindFirstChild("RowList")

	local function openWindow()
		-- Rebuild rows on every open so lock states always reflect the
		-- latest ReachedWorld.
		for _, child in ipairs(rowList:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		for worldIndex = 1, #GameConfig.worlds do
			createWorldRow(rowList, worldIndex, window)
		end

		window.Visible = true
	end

	local function watchPortal(portal: Instance)
		local prompt = portal:FindFirstChildOfClass("ProximityPrompt")
		if prompt == nil then
			return
		end

		prompt.Triggered:Connect(function(playerWhoTriggered)
			if playerWhoTriggered == localPlayer then
				openWindow()
			end
		end)
	end

	for _, portal in ipairs(CollectionService:GetTagged(PORTAL_TAG)) do
		watchPortal(portal)
	end

	CollectionService:GetInstanceAddedSignal(PORTAL_TAG):Connect(watchPortal)
end

return PortalGui
