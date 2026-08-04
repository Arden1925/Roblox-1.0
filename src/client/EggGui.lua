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

-- Built-in engine sounds, so the hatch has audio without any uploads.
local SHAKE_SOUND = "rbxasset://sounds/snap.mp3"
local REVEAL_SOUND = "rbxasset://sounds/electronicpingshort.wav"

local CONFETTI_COLORS = {
	Color3.fromRGB(255, 154, 162),
	Color3.fromRGB(255, 183, 121),
	Color3.fromRGB(253, 255, 171),
	Color3.fromRGB(158, 240, 155),
	Color3.fromRGB(154, 206, 255),
	Color3.fromRGB(216, 178, 255),
}

local localPlayer = Players.LocalPlayer

-- One egg at a time: while a reveal is playing, hatch clicks and the
-- egg stand prompt are both ignored, so cinematics can never stack.
local revealActive = false

-- ScreenGuis this module switched off for the reveal, so it restores
-- exactly what it hid and nothing else.
local hiddenGuis: { ScreenGui } = {}

local EggGui = {}

--[[
	The reveal is a fullscreen moment; the rest of the HUD (size meter,
	sliders, backpack button, quest board) only clutters it and clashes
	with the overlay. Everything except this gui and toasts switches
	off for the duration and comes back exactly as it was.
]]
local function setHudHidden(ownGui: ScreenGui, hidden: boolean)
	if hidden then
		local playerGui = ownGui.Parent
		if playerGui == nil then
			return
		end

		for _, child in ipairs(playerGui:GetChildren()) do
			local shouldHide = child:IsA("ScreenGui")
				and child ~= ownGui
				and child.Name ~= "ToastGui"
				and child.Enabled
			if shouldHide then
				child.Enabled = false
				table.insert(hiddenGuis, child)
			end
		end
	else
		for _, gui in ipairs(hiddenGuis) do
			gui.Enabled = true
		end
		table.clear(hiddenGuis)
	end
end

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

local function playSound(parent: Instance, soundId: string, playbackSpeed: number)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 0.6
	sound.PlaybackSpeed = playbackSpeed
	sound.Parent = parent
	sound:Play()

	task.delay(3, function()
		sound:Destroy()
	end)
end

-- A ring of thin rays snapping outward from the egg, plus a shower of
-- spinning confetti squares -- the moment of the crack.
local function playBurst(overlay: Frame, tierColor: Color3)
	for rayIndex = 1, 10 do
		local ray = UiBuilder.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.4, 0),
			Size = UDim2.new(0, 4, 0, 30),
			BackgroundColor3 = tierColor,
			BorderSizePixel = 0,
			Rotation = rayIndex * 36,
			ZIndex = 8,
			Parent = overlay,
		})

		TweenService:Create(ray, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
			Size = UDim2.new(0, 3, 0, 240),
			BackgroundTransparency = 1,
		}):Play()
	end

	for confettiIndex = 1, 24 do
		local angle = confettiIndex / 24 * math.pi * 2
		local distance = 160 + math.random(0, 140)
		local piece = UiBuilder.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.4, 0),
			Size = UDim2.new(0, 10, 0, 10),
			BackgroundColor3 = CONFETTI_COLORS[confettiIndex % #CONFETTI_COLORS + 1],
			BorderSizePixel = 0,
			ZIndex = 8,
			Parent = overlay,
		})

		TweenService:Create(piece, TweenInfo.new(0.9, Enum.EasingStyle.Quad), {
			Position = UDim2.new(
				0.5,
				math.cos(angle) * distance,
				0.4,
				math.sin(angle) * distance - 40
			),
			Rotation = math.random(180, 540),
			BackgroundTransparency = 1,
		}):Play()
	end
end

-- The name-your-pet box on the reveal screen; submits to the server,
-- which filters the name before storing it.
local function buildNamePrompt(overlay: Frame, petIndex: number, titleLabel: TextLabel)
	local nameBox = UiBuilder.create("TextBox", {
		Name = "NameBox",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, -55, 0.78, 0),
		Size = UDim2.new(0, 200, 0, 36),
		BackgroundColor3 = CARD_COLOR,
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		PlaceholderText = "Name your new pet...",
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 15,
		ZIndex = 9,
		Parent = overlay,
	}) :: TextBox
	UiBuilder.round(nameBox, 8)
	UiBuilder.stroke(nameBox, COIN_COLOR, 1)

	local submitButton = UiBuilder.create("TextButton", {
		Name = "SubmitName",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 75, 0.78, 0),
		Size = UDim2.new(0, 50, 0, 36),
		BackgroundColor3 = COIN_COLOR,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		Text = "OK",
		TextColor3 = Color3.fromRGB(45, 52, 54),
		TextSize = 16,
		ZIndex = 9,
		Parent = overlay,
	}) :: TextButton
	UiBuilder.round(submitButton, 8)
	UiBuilder.hoverPop(submitButton)

	submitButton.Activated:Connect(function()
		local requestedName = nameBox.Text
		task.spawn(function()
			local renamePet = Remotes.get("RenamePet") :: RemoteFunction

			-- InvokeServer throws if the server errors mid-call.
			local invoked, success, message = pcall(function()
				return renamePet:InvokeServer(petIndex, requestedName)
			end)

			if invoked and success then
				titleLabel.Text = string.match(requestedName, "^%s*(.-)%s*$") :: string
				nameBox.Visible = false
				submitButton.Visible = false
			end

			Toast.show(if invoked then message else "Something went wrong -- try again.")
		end)
	end)
end

--[[
	The full hatch cinematic, fullscreen so the odds menu stays hidden:
	the egg drops in and shakes harder and harder, cracks in a white
	flash and a burst of rays and confetti, then the pet spins out with
	its tier, its mutation, and a box to name it on the spot. Yields
	between beats; call from a spawned task.
]]
local function playReveal(screenGui: ScreenGui, window: Frame, petId: string, petIndex: number)
	local info = PetCatalog.infoFor(petId)
	if info == nil then
		-- Defensive: the server only sends catalog ids, but if one ever
		-- fails to resolve, the lock must not stay latched forever.
		revealActive = false
		UiBuilder.popOpen(window)

		return
	end

	setHudHidden(screenGui, true)

	local overlay = UiBuilder.create("Frame", {
		Name = "RevealOverlay",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(10, 12, 18),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = screenGui,
	}) :: Frame

	TweenService:Create(overlay, TweenInfo.new(0.3), { BackgroundTransparency = 0.2 }):Play()

	local egg = UiBuilder.create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, -0.2, 0),
		Size = UDim2.new(0, 140, 0, 140),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "\u{1F95A}",
		TextSize = 110,
		ZIndex = 7,
		Parent = overlay,
	}) :: TextLabel

	-- The drop: bounce into the middle of the screen.
	local drop = TweenService:Create(
		egg,
		TweenInfo.new(0.7, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0.4, 0) }
	)
	drop:Play()
	drop.Completed:Wait()

	-- Three shake bursts, each angrier than the last, each with a pulse
	-- ring so the tension is visible as well as audible.
	for stage = 1, 3 do
		playSound(overlay, SHAKE_SOUND, 0.8 + stage * 0.2)

		local ring = UiBuilder.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.4, 0),
			Size = UDim2.new(0, 60, 0, 60),
			BackgroundTransparency = 1,
			ZIndex = 6,
			Parent = overlay,
		})
		UiBuilder.round(ring, 200)
		local ringStroke = UiBuilder.stroke(ring, info.tierColor, 3)

		TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad), {
			Size = UDim2.new(0, 150 + stage * 60, 0, 150 + stage * 60),
		}):Play()
		TweenService:Create(ringStroke, TweenInfo.new(0.45), { Transparency = 1 }):Play()

		local shake = TweenService:Create(
			egg,
			TweenInfo.new(
				0.05,
				Enum.EasingStyle.Linear,
				Enum.EasingDirection.InOut,
				3 + stage * 2,
				true
			),
			{ Rotation = 6 + stage * 7 }
		)
		shake:Play()
		shake.Completed:Wait()
		egg.Rotation = 0
		task.wait(0.15)
	end

	-- The crack: white flash, the egg vanishes, rays and confetti fly.
	local flash = UiBuilder.create("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = overlay,
	})
	egg.Visible = false
	playBurst(overlay, info.tierColor)

	-- Rarer mutations ring higher: pitch climbs with the multiplier.
	local mutation = info.mutation
	local revealPitch = if mutation ~= nil then 0.9 + mutation.bonusMultiplier * 0.1 else 1
	playSound(overlay, REVEAL_SOUND, revealPitch)

	TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()

	-- The pet, big and spinning hard out of the shell.
	local viewportHolder = UiBuilder.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.36, 0),
		Size = UDim2.new(0, 230, 0, 230),
		BackgroundTransparency = 1,
		ZIndex = 7,
		Parent = overlay,
	})
	PetViewport.create(viewportHolder, petId, UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), 6)
	UiBuilder.popOpen(viewportHolder)

	local titleLabel = UiBuilder.create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.58, 0),
		Size = UDim2.new(0, 380, 0, 34),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = info.baseName .. "!",
		TextColor3 = info.tierColor,
		TextSize = 30,
		ZIndex = 7,
		Parent = overlay,
	}) :: TextLabel

	if PetModels.tierRank(info.tierName) >= 5 then
		UiBuilder.shineText(titleLabel)
	end
	UiBuilder.popOpen(titleLabel)

	-- The mutation announces itself right under the name, in its own
	-- color -- the moment players screenshot.
	if mutation ~= nil then
		local mutationLabel = UiBuilder.create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.645, 0),
			Size = UDim2.new(0, 380, 0, 26),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Text = "\u{2726} " .. string.upper(mutation.name) .. " \u{2726}",
			TextColor3 = mutation.color,
			TextSize = 22,
			ZIndex = 7,
			Parent = overlay,
		}) :: TextLabel
		UiBuilder.shineText(mutationLabel)
		UiBuilder.popOpen(mutationLabel)
	end

	UiBuilder.create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.7, 0),
		Size = UDim2.new(0, 380, 0, 24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = string.format("%s  --  +%d%% growth", info.tierName, info.bonus * 100),
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 17,
		ZIndex = 7,
		Parent = overlay,
	})

	buildNamePrompt(overlay, petIndex, titleLabel)

	local continueButton = UiBuilder.create("TextButton", {
		Name = "ContinueButton",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.86, 0),
		Size = UDim2.new(0, 180, 0, 42),
		BackgroundColor3 = Color3.fromRGB(76, 209, 55),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		Text = "CONTINUE",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 18,
		ZIndex = 9,
		Parent = overlay,
	}) :: TextButton
	UiBuilder.round(continueButton, 10)
	UiBuilder.hoverPop(continueButton)

	continueButton.Activated:Connect(function()
		setHudHidden(screenGui, false)
		revealActive = false
		overlay:Destroy()
		UiBuilder.popOpen(window)
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

	UiBuilder.cartoonizeWindow(window, COIN_COLOR, "EGGS")

	return window :: Frame
end

local function openForWorld(window: Frame, worldIndex: number)
	-- The egg stand prompt stays live during a reveal; reopening the
	-- odds menu would pop it straight over the cinematic.
	if revealActive then
		return
	end

	-- Buttons are GuiObjects too: the old Frame/TextLabel check let the
	-- hatch and Robux buttons duplicate on every reopen, stacking dead
	-- copies (and their connections) on top of each other.
	for _, child in ipairs(window:GetChildren()) do
		local clearable = child:IsA("GuiObject")
		if clearable and child.Name ~= "CloseButton" and child.Name ~= "HeaderBanner" then
			child:Destroy()
		end
	end

	local world = GameConfig.worlds[worldIndex]

	-- The corner tab renames itself to the current world's egg.
	local banner = window:FindFirstChild("HeaderBanner")
	local bannerTitle = if banner ~= nil then banner:FindFirstChild("Title") else nil
	if bannerTitle ~= nil and bannerTitle:IsA("TextLabel") then
		bannerTitle.Text = string.upper(world.eggName)
	end

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
		-- Take the reveal lock at the click, not at the reveal: the
		-- server round trip leaves a gap a double-click would slip
		-- through otherwise.
		if revealActive then
			return
		end
		revealActive = true

		-- The odds menu disappears the moment the hatch starts; the
		-- reveal plays fullscreen and brings the menu back afterward.
		window.Visible = false

		task.spawn(function()
			local hatchEgg = Remotes.get("HatchEgg") :: RemoteFunction

			-- InvokeServer throws if the server errors mid-call.
			local invoked, success, result = pcall(function()
				return hatchEgg:InvokeServer()
			end)

			local resultIsTable = invoked and success and typeof(result) == "table"
			if resultIsTable and typeof(result.petId) == "string" then
				local screenGui = window.Parent :: ScreenGui
				playReveal(screenGui, window, result.petId, result.petIndex)
			else
				revealActive = false
				UiBuilder.popOpen(window)
				Toast.show(
					if invoked and not success then result else "Something went wrong -- try again."
				)
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
