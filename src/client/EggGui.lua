--[[
	Egg hatching: triggered at a world's egg capsule, shows the five pets
	and their odds, hatches for coins with a shake-and-reveal animation,
	and sells the Robux royal egg beside it. Also handles the limited pet
	pedestal at spawn. All rolls happen on the server; this UI displays.
]]

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Client = script.Parent
local PetViewport = require(Client.PetViewport)
local Toast = require(Client.Toast)
local UiBuilder = require(Client.UiBuilder)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local PetCatalog = require(Shared.PetCatalog)
local PetModels = require(Shared.PetModels)
local Remotes = require(Shared.Remotes)

local PANEL_COLOR = Color3.fromRGB(24, 30, 38)
local CARD_COLOR = Color3.fromRGB(47, 54, 64)
local COIN_COLOR = Color3.fromRGB(253, 203, 110)
local ROBUX_COLOR = Color3.fromRGB(0, 162, 255)

local SHAKE_INFO = TweenInfo.new(0.08, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, 5, true)

local localPlayer = Players.LocalPlayer

local EggGui = {}

local function buildPetRow(parent: Instance, order: number, info: PetCatalog.PetInfo, odds: string)
	local row = UiBuilder.create("Frame", {
		Name = info.id,
		LayoutOrder = order,
		Size = UDim2.new(1, -12, 0, 42),
		BackgroundColor3 = CARD_COLOR,
		BorderSizePixel = 0,
		Parent = parent,
	})
	UiBuilder.round(row, 8)
	UiBuilder.stroke(row, info.tierColor, 1)

	-- A live 3D thumbnail beats a colored square for "what can I get".
	PetViewport.create(row, info.id, UDim2.new(0, 36, 0, 36), UDim2.new(0, 4, 0, 3))

	UiBuilder.create("TextLabel", {
		Position = UDim2.new(0, 46, 0, 0),
		Size = UDim2.new(0.55, 0, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = string.format("%s (%s)", info.name, info.tierName),
		TextColor3 = info.tierColor,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	UiBuilder.create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.new(0.35, 0, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = odds,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})
end

local function playReveal(window: Frame, petId: string)
	local info = PetCatalog.infoFor(petId)
	if info == nil then
		return
	end

	local overlay = UiBuilder.create("Frame", {
		Name = "RevealOverlay",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = PANEL_COLOR,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = window,
	})

	local egg = UiBuilder.create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.45, 0),
		Size = UDim2.new(0, 120, 0, 120),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "\u{1F95A}",
		TextSize = 90,
		ZIndex = 6,
		Parent = overlay,
	})

	local shake = TweenService:Create(egg, SHAKE_INFO, { Rotation = 14 })
	shake:Play()

	shake.Completed:Connect(function()
		egg.Visible = false

		-- Burst: two rings of the pet's color expanding out of the egg.
		for ringIndex = 1, 2 do
			local ring = UiBuilder.create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.42, 0),
				Size = UDim2.new(0, 20, 0, 20),
				BackgroundTransparency = 1,
				ZIndex = 6,
				Parent = overlay,
			})
			UiBuilder.round(ring, 200)
			local ringStroke = UiBuilder.stroke(ring, info.tierColor, 4)

			local burst = TweenService:Create(
				ring,
				TweenInfo.new(0.6 + ringIndex * 0.2, Enum.EasingStyle.Quad),
				{ Size = UDim2.new(0, 260 + ringIndex * 80, 0, 260 + ringIndex * 80) }
			)
			burst:Play()
			TweenService:Create(
				ringStroke,
				TweenInfo.new(0.6 + ringIndex * 0.2, Enum.EasingStyle.Quad),
				{ Transparency = 1 }
			):Play()
		end

		-- The pet itself, in 3D, spinning fast out of the shell.
		local viewportHolder = UiBuilder.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.38, 0),
			Size = UDim2.new(0, 170, 0, 170),
			BackgroundTransparency = 1,
			ZIndex = 7,
			Parent = overlay,
		})
		PetViewport.create(viewportHolder, petId, UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), 4)
		UiBuilder.popOpen(viewportHolder)

		local reveal = UiBuilder.create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.62, 0),
			Size = UDim2.new(0, 320, 0, 80),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Text = string.format(
				"%s!\n%s  +%d%% growth",
				info.name,
				info.tierName,
				info.bonus * 100
			),
			TextColor3 = info.tierColor,
			TextSize = 26,
			TextWrapped = true,
			ZIndex = 7,
			Parent = overlay,
		}) :: TextLabel

		-- Top tiers get the full rainbow-shine treatment.
		if PetModels.tierRank(info.tierName) >= 5 then
			UiBuilder.shineText(reveal)
		end

		UiBuilder.popOpen(reveal)
		task.delay(2.6, function()
			overlay:Destroy()
		end)
	end)
end

local function buildWindow(parent: Instance): Frame
	local window = UiBuilder.create("Frame", {
		Name = "EggWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 420, 0, 470),
		BackgroundColor3 = PANEL_COLOR,
		BorderSizePixel = 0,
		Visible = false,
		Parent = parent,
	})
	UiBuilder.round(window, 16)
	UiBuilder.stroke(window, COIN_COLOR, 2)

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

	return window :: Frame
end

local function openForWorld(window: Frame, worldIndex: number)
	for _, child in ipairs(window:GetChildren()) do
		if child.Name ~= "CloseButton" and (child:IsA("Frame") or child:IsA("TextLabel")) then
			child:Destroy()
		end
	end

	local world = GameConfig.worlds[worldIndex]

	UiBuilder.create("TextLabel", {
		Name = "Title",
		Position = UDim2.new(0, 16, 0, 10),
		Size = UDim2.new(1, -70, 0, 32),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = string.upper(world.eggName),
		TextColor3 = COIN_COLOR,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = window,
	})

	local list = UiBuilder.create("Frame", {
		Name = "PetList",
		Position = UDim2.new(0, 10, 0, 50),
		Size = UDim2.new(1, -20, 0, 230),
		BackgroundTransparency = 1,
		Parent = window,
	})

	UiBuilder.create("UIListLayout", {
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})

	local pool = PetCatalog.coinEggPool(worldIndex)
	local totalWeight = 0
	for _, entry in ipairs(pool) do
		totalWeight += entry.weight
	end

	for order, entry in ipairs(pool) do
		local info = PetCatalog.infoFor(entry.id)
		if info ~= nil then
			local odds = string.format("%.1f%%", entry.weight / totalWeight * 100)
			buildPetRow(list, order, info, odds)
		end
	end

	local hatchButton = UiBuilder.create("TextButton", {
		Name = "HatchButton",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 292),
		Size = UDim2.new(1, -20, 0, 52),
		BackgroundColor3 = COIN_COLOR,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		Text = string.format("HATCH -- %d COINS", world.eggCost),
		TextColor3 = Color3.fromRGB(45, 52, 54),
		TextSize = 20,
		Parent = window,
	})
	UiBuilder.round(hatchButton, 12)
	UiBuilder.hoverPop(hatchButton)

	hatchButton.Activated:Connect(function()
		task.spawn(function()
			local hatchEgg = Remotes.get("HatchEgg") :: RemoteFunction

			-- InvokeServer throws if the server errors mid-call.
			local invoked, success, result = pcall(function()
				return hatchEgg:InvokeServer()
			end)

			if not invoked then
				Toast.show("Something went wrong -- try again.")
			elseif not success then
				Toast.show(result)
			else
				playReveal(window, result)
			end
		end)
	end)

	local robuxEgg = world.robuxEgg
	local robuxAvailable = robuxEgg.productId ~= 0

	local robuxButton = UiBuilder.create("TextButton", {
		Name = "RobuxEggButton",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 354),
		Size = UDim2.new(1, -20, 0, 52),
		BackgroundColor3 = if robuxAvailable then ROBUX_COLOR else CARD_COLOR,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		Text = if robuxAvailable
			then string.format("%s -- R$ %d", string.upper(robuxEgg.name), robuxEgg.robuxPrice)
			else string.format("%s -- COMING SOON", string.upper(robuxEgg.name)),
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 17,
		Parent = window,
	})
	UiBuilder.round(robuxButton, 12)
	UiBuilder.hoverPop(robuxButton)

	robuxButton.Activated:Connect(function()
		if robuxAvailable then
			MarketplaceService:PromptProductPurchase(localPlayer, robuxEgg.productId)
		else
			Toast.show("The royal egg unlocks once the game is published!")
		end
	end)

	UiBuilder.create("TextLabel", {
		Name = "RoyalHint",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 412),
		Size = UDim2.new(1, -20, 0, 44),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "The royal egg holds 3 exclusive pets, stronger than anything the coin egg hatches.",
		TextColor3 = Color3.fromRGB(178, 190, 195),
		TextSize = 13,
		TextWrapped = true,
		Parent = window,
	})

	UiBuilder.popOpen(window)
end

function EggGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = UiBuilder.create("ScreenGui", {
		Name = "EggGui",
		ResetOnSpawn = false,
		DisplayOrder = 6,
		Parent = playerGui,
	})

	local window = buildWindow(screenGui)

	local function watchStand(stand: Instance)
		local prompt = stand:FindFirstChildOfClass("ProximityPrompt")
		if prompt == nil then
			return
		end

		prompt.Triggered:Connect(function(playerWhoTriggered)
			local worldIndex = stand:GetAttribute("WorldIndex")
			if playerWhoTriggered == localPlayer and typeof(worldIndex) == "number" then
				openForWorld(window, worldIndex)
			end
		end)
	end

	local function watchLimited(pedestal: Instance)
		local prompt = pedestal:FindFirstChildOfClass("ProximityPrompt")
		if prompt == nil then
			return
		end

		prompt.Triggered:Connect(function(playerWhoTriggered)
			if playerWhoTriggered ~= localPlayer then
				return
			end

			if GameConfig.limitedPet.productId ~= 0 then
				MarketplaceService:PromptProductPurchase(
					localPlayer,
					GameConfig.limitedPet.productId
				)
			else
				Toast.show("The limited pet unlocks once the game is published!")
			end
		end)
	end

	for _, stand in ipairs(CollectionService:GetTagged("EggStand")) do
		watchStand(stand)
	end
	CollectionService:GetInstanceAddedSignal("EggStand"):Connect(watchStand)

	for _, pedestal in ipairs(CollectionService:GetTagged("LimitedDisplay")) do
		watchLimited(pedestal)
	end
	CollectionService:GetInstanceAddedSignal("LimitedDisplay"):Connect(watchLimited)
end

return EggGui
