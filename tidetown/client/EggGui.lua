--[[
	The right-edge egg strip: every held egg is a small card with a
	bottom-up charge fill that grows as the player catches, pulsing gold
	once the egg is ready. Clicking a ready egg asks the server to hatch
	it and plays the reveal cinematic -- three escalating shakes, a white
	flash, then the creature spinning in with its rarity and a NEW badge.
	Reduced motion swaps the theatrics for a plain result card.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Client = script.Parent
local TidetownUi = require(Client.TidetownUi)
local Toast = require(Client.Toast)

local TidetownShared = ReplicatedStorage:WaitForChild("TidetownShared")
local CreatureCatalog = require(TidetownShared.CreatureCatalog)
local CreatureModels = require(TidetownShared.CreatureModels)
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

local OUTLINE_NAVY = Color3.fromRGB(31, 41, 74)
local CARD_COLOR = Color3.fromRGB(248, 240, 220)
local FILL_COLOR = Color3.fromRGB(0, 172, 193)
local READY_GOLD = Color3.fromRGB(255, 193, 7)
local NEW_GOLD = Color3.fromRGB(255, 179, 0)
local COVER_COLOR = Color3.fromRGB(8, 14, 28)
local CARD_SIZE = 64
local CARD_GAP = 12
local SHAKE_STEP_INFO = TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local COVER_IN_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH_IN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH_OUT_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SPIN_RADIANS_PER_SECOND = 1.6
local RESULT_AUTO_CLOSE_SECONDS = 6

local localPlayer = Players.LocalPlayer

-- Egg definitions by key, so a synced egg record resolves to its
-- display name and hatch model without searching the config each time.
local EGG_TYPES: { [string]: any } = {}
for _, eggType in ipairs(TidetownConfig.eggs.types) do
	EGG_TYPES[eggType.key] = eggType
end

local reducedMotion = false
local hatching = false
local spinConnection: RBXScriptConnection? = nil
local closeToken = 0

local EggGui = {}

local function stopSpin()
	if spinConnection ~= nil then
		spinConnection:Disconnect()
		spinConnection = nil
	end
end

-- One Heartbeat connection at most: only the cinematic's reveal model
-- ever spins, and it stops the previous spin before starting.
local function startSpin(model: Model)
	stopSpin()

	local angle = 0
	spinConnection = RunService.Heartbeat:Connect(function(deltaSeconds)
		angle += deltaSeconds * SPIN_RADIANS_PER_SECOND
		model:PivotTo(CFrame.Angles(0, angle, 0))
	end)
end

--[[
	Frames a centered model in a fresh ViewportFrame using the model's
	real bounds (the PetViewport math), so tall whales and tiny crabs
	both fill the frame instead of cropping or drowning in margin.
]]
local function buildViewport(
	parent: Instance,
	model: Model,
	size: UDim2,
	position: UDim2
): ViewportFrame
	local viewport = TidetownUi.create("ViewportFrame", {
		Name = "ModelViewport",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 200, 210),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-1, -1, -0.5),
		ZIndex = 2,
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

	return viewport
end

--[[
	Three escalating shake bursts on the egg viewport. Each step waits
	on its tween, so the whole sequence reads as a rhythm rather than a
	blur; bailing out when the viewport dies keeps a mid-shake close
	from tweening a destroyed frame.
]]
local function shakeViewport(viewport: ViewportFrame)
	for burst = 1, 3 do
		local amplitude = 3 + burst * 3
		for _, direction in ipairs({ -1, 1, -1, 1, 0 }) do
			if viewport.Parent == nil then
				return
			end

			local step = TweenService:Create(viewport, SHAKE_STEP_INFO, {
				Rotation = direction * amplitude,
			})
			step:Play()
			step.Completed:Wait()
		end

		task.wait(0.35 - burst * 0.08)
	end
end

local function capitalize(word: string): string
	return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
end

-- The reveal card: the hatched creature, its name in white, its rarity
-- in the rarity color, and a tilted NEW! sticker for first-time species.
local function showResult(content: Frame, result: any)
	local model = CreatureModels.build(result.speciesKey, 2)
	buildViewport(content, model, UDim2.new(0, 280, 0, 280), UDim2.new(0.5, 0, 0.42, 0))

	if reducedMotion then
		model:PivotTo(CFrame.Angles(0, math.rad(35), 0))
	else
		startSpin(model)
	end

	local species = CreatureCatalog.speciesFor(result.speciesKey)
	local displayName = if typeof(result.speciesName) == "string"
		then result.speciesName
		elseif species ~= nil then species.name
		else "???"
	local rarity = if typeof(result.rarity) == "string" then result.rarity else "common"

	TidetownUi.create("TextLabel", {
		Name = "SpeciesName",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.64, 0),
		Size = UDim2.new(0, 520, 0, 40),
		BackgroundTransparency = 1,
		Text = displayName,
		TextSize = 34,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		ZIndex = 3,
		Parent = content,
	})

	TidetownUi.create("TextLabel", {
		Name = "RarityLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.64, 42),
		Size = UDim2.new(0, 520, 0, 26),
		BackgroundTransparency = 1,
		Text = capitalize(rarity),
		TextSize = 20,
		TextColor3 = CreatureCatalog.rarityColor(rarity),
		ZIndex = 3,
		Parent = content,
	})

	if result.isNew == true then
		local badge = TidetownUi.create("TextLabel", {
			Name = "NewBadge",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 118, 0.3, 0),
			Size = UDim2.new(0, 92, 0, 36),
			Rotation = 12,
			BackgroundColor3 = NEW_GOLD,
			BorderSizePixel = 0,
			Text = "NEW!",
			TextSize = 20,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			ZIndex = 4,
			Parent = content,
		})
		TidetownUi.round(badge, 10)
		TidetownUi.stroke(badge, OUTLINE_NAVY, 3)
	end

	TidetownUi.create("TextLabel", {
		Name = "ContinueHint",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.86, 0),
		Size = UDim2.new(0, 400, 0, 20),
		BackgroundTransparency = 1,
		Text = "Tap anywhere to continue",
		TextSize = 15,
		TextColor3 = Color3.fromRGB(210, 225, 240),
		ZIndex = 3,
		Parent = content,
	})
end

function EggGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = TidetownUi.create("ScreenGui", {
		Name = "TidetownEggGui",
		ResetOnSpawn = false,
		DisplayOrder = 10,
		Parent = playerGui,
	}) :: ScreenGui

	local stripHeight = TidetownConfig.eggs.maxHeld * (CARD_SIZE + CARD_GAP)
	local strip = TidetownUi.create("Frame", {
		Name = "EggStrip",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0, CARD_SIZE + 8, 0, stripHeight),
		BackgroundTransparency = 1,
		Parent = screenGui,
	}) :: Frame

	TidetownUi.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, CARD_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = strip,
	})

	TidetownUi.cartoonify(strip)

	-- The cinematic layer sits above the rest of the UI; the cover is
	-- itself the click-to-dismiss button.
	local hatchGui = TidetownUi.create("ScreenGui", {
		Name = "TidetownHatchGui",
		ResetOnSpawn = false,
		DisplayOrder = 45,
		Parent = playerGui,
	}) :: ScreenGui

	local cover = TidetownUi.create("TextButton", {
		Name = "HatchCover",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = COVER_COLOR,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		Parent = hatchGui,
	}) :: TextButton

	TidetownUi.cartoonify(cover)

	local function closeCinematic()
		closeToken += 1
		stopSpin()

		local content = cover:FindFirstChild("HatchContent")
		if content ~= nil then
			content:Destroy()
		end
		cover.Visible = false
	end

	cover.Activated:Connect(closeCinematic)

	local function playCinematic(eggType: any, result: any)
		closeCinematic()
		closeToken += 1
		local token = closeToken

		local content = TidetownUi.create("Frame", {
			Name = "HatchContent",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Parent = cover,
		}) :: Frame

		cover.BackgroundTransparency = 1
		cover.Visible = true
		TweenService:Create(cover, COVER_IN_INFO, { BackgroundTransparency = 0.25 }):Play()

		if reducedMotion then
			showResult(content, result)
		else
			local modelName = if eggType ~= nil then eggType.modelName else ""
			local eggModel = CreatureModels.buildEgg(modelName, 3)
			local eggViewport = buildViewport(
				content,
				eggModel,
				UDim2.new(0, 280, 0, 280),
				UDim2.new(0.5, 0, 0.45, 0)
			)

			shakeViewport(eggViewport)
			if token ~= closeToken then
				return
			end

			local flash = TidetownUi.create("Frame", {
				Name = "HatchFlash",
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 5,
				Parent = content,
			}) :: Frame

			local flashIn =
				TweenService:Create(flash, FLASH_IN_INFO, { BackgroundTransparency = 0 })
			flashIn:Play()
			flashIn.Completed:Wait()
			if token ~= closeToken then
				return
			end

			-- The swap happens behind the white flash, so the egg never
			-- visibly blinks out of existence.
			eggViewport:Destroy()
			showResult(content, result)
			TweenService:Create(flash, FLASH_OUT_INFO, { BackgroundTransparency = 1 }):Play()
		end

		task.delay(RESULT_AUTO_CLOSE_SECONDS, function()
			if token == closeToken then
				closeCinematic()
			end
		end)
	end

	local hatchRemote = TidetownRemotes.get("HatchEgg") :: RemoteFunction
	local syncRemote = TidetownRemotes.get("SyncState") :: RemoteEvent

	local function requestHatch(egg: any)
		if egg.charge < egg.required then
			Toast.push(
				string.format("Charging: %d/%d -- keep catching!", egg.charge, egg.required),
				"info"
			)

			return
		end

		if hatching then
			return
		end
		hatching = true

		local ok, result = hatchRemote:InvokeServer(egg.uid)
		hatching = false

		if ok == true then
			playCinematic(EGG_TYPES[egg.eggKey], result)
		else
			Toast.push(
				if typeof(result) == "string" then result else "Cannot hatch right now",
				"bad"
			)
		end
	end

	local function buildEggCard(index: number, egg: any)
		local ready = egg.charge >= egg.required
		local eggType = EGG_TYPES[egg.eggKey]
		local eggName = if eggType ~= nil then eggType.name else "Egg"

		local card = TidetownUi.create("TextButton", {
			Name = "EggCard" .. index,
			LayoutOrder = index,
			Size = UDim2.new(0, CARD_SIZE, 0, CARD_SIZE),
			BackgroundColor3 = CARD_COLOR,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Parent = strip,
		}) :: TextButton
		TidetownUi.round(card, 14)
		local stroke = TidetownUi.stroke(card, if ready then READY_GOLD else OUTLINE_NAVY, 3)

		local fraction = math.clamp(egg.charge / math.max(egg.required, 1), 0, 1)
		local fill = TidetownUi.create("Frame", {
			Name = "ChargeFill",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, fraction, 0),
			BackgroundColor3 = FILL_COLOR,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			Parent = card,
		}) :: Frame
		TidetownUi.round(fill, 14)

		TidetownUi.create("TextLabel", {
			Name = "Initial",
			Position = UDim2.new(0, 0, 0, 0),
			Size = UDim2.new(1, 0, 1, -14),
			BackgroundTransparency = 1,
			Text = string.upper(string.sub(eggName, 1, 1)),
			TextSize = 26,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			ZIndex = 2,
			Parent = card,
		})

		TidetownUi.create("TextLabel", {
			Name = "ChargeLabel",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -3),
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundTransparency = 1,
			Text = if ready then "Ready!" else string.format("%d/%d", egg.charge, egg.required),
			TextSize = 11,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			ZIndex = 2,
			Parent = card,
		})

		if ready then
			TidetownUi.pulse(stroke)
			TidetownUi.hoverPop(card)
		end

		card.Activated:Connect(function()
			requestHatch(egg)
		end)
	end

	local function rebuildStrip(eggs: { any })
		for _, child in ipairs(strip:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		for index, egg in ipairs(eggs) do
			buildEggCard(index, egg)
		end
	end

	syncRemote.OnClientEvent:Connect(function(kind, payload)
		if typeof(payload) ~= "table" then
			return
		end

		if kind == "eggs" then
			rebuildStrip(if typeof(payload.eggs) == "table" then payload.eggs else {})
		elseif kind == "settings" then
			reducedMotion = payload.reducedMotion == true
		end
	end)
end

return EggGui
