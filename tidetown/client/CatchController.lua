--[[
	The bottom-center CAST button and its timing ring. Pressing CAST
	asks the server to open a cast; the reply carries the ring speed
	and where the perfect moment sits, so the ring drawn here always
	matches the window the server judges by. A second press (or the
	ring running out) resolves the cast, and the result lands as a
	toast plus a brief creature reveal card. The server stays the only
	judge -- this module mirrors the cooldown and the zone/phase rules
	just to keep hopeless requests off the wire and to explain WHY the
	button is gray.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent
local CameraFx = require(Client.CameraFx)
local TidetownUi = require(Client.TidetownUi)
local Toast = require(Client.Toast)

local TidetownShared = ReplicatedStorage:WaitForChild("TidetownShared")
local CreatureCatalog = require(TidetownShared.CreatureCatalog)
local CreatureModels = require(TidetownShared.CreatureModels)
local TideLayout = require(TidetownShared.TideLayout)
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

local BUTTON_DIAMETER = 96
local RING_MAXIMUM_DIAMETER = 230
-- The sweep ends just past the button's edge, so "the ring reached
-- the button" and "the ring is done" read as the same moment.
local RING_MINIMUM_DIAMETER = 100
local RING_EXPIRY_GRACE_SECONDS = 0.05
local ZONE_POLL_SECONDS = 0.5
local CARD_SECONDS = 2.4
local CARD_HEIGHT = 252
local VIEWPORT_MODEL_HEIGHT_STUDS = 2
local CARD_SPIN_RADIANS_PER_SECOND = 1.4

local OUTLINE_NAVY = Color3.fromRGB(31, 41, 74)
local CARD_INTERIOR_COLOR = Color3.fromRGB(244, 250, 255)
local ENABLED_COLOR = Color3.fromRGB(0, 152, 178)
local ACTIVE_COLOR = Color3.fromRGB(255, 145, 40)
local DISABLED_COLOR = Color3.fromRGB(125, 134, 148)
local MARKER_GOLD = Color3.fromRGB(255, 213, 79)
local NEW_BADGE_COLOR = Color3.fromRGB(255, 179, 0)

local FLASH_INFO = TweenInfo.new(0.09, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true)
local CARD_CLOSE_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.In)

type ActiveCast = {
	castId: string,
	token: number,
}

type CatchGui = {
	screenGui: ScreenGui,
	castButton: TextButton,
	sweepRing: Frame,
	perfectMarker: Frame,
	markerStroke: UIStroke,
	reasonLabel: TextLabel,
}

local localPlayer = Players.LocalPlayer

local currentCard: Frame? = nil

local function capitalizeRarity(rarity: string): string
	return string.upper(string.sub(rarity, 1, 1)) .. string.sub(rarity, 2)
end

local function resultToast(payload: { [string]: any })
	if typeof(payload.quality) ~= "string" then
		return
	end

	local shells = if typeof(payload.shells) == "number" then math.floor(payload.shells) else 0

	if payload.quality == "miss" then
		Toast.push(string.format("Splash! It slipped away... +%d🐚", shells), "info")
		return
	end

	if typeof(payload.speciesName) ~= "string" or typeof(payload.rarity) ~= "string" then
		return
	end

	local prefix = if payload.quality == "perfect" then "Perfect!" else "Caught!"
	local style = if payload.rarity == "epic" or payload.rarity == "legendary"
		then "rare"
		elseif payload.quality == "perfect" then "good"
		else "info"

	Toast.push(
		string.format(
			"%s %s (%s) +%d🐚",
			prefix,
			payload.speciesName,
			capitalizeRarity(payload.rarity),
			shells
		),
		style
	)
end

--[[
	The brief center-screen reveal card: a spinning viewport of the
	species, its name in the rarity color, and a NEW! badge on first
	catches. The camera framing copies PetViewport: the distance comes
	from the model's real bounds, so big and small species fill the
	card the same way.
]]
local function showResultCard(parent: Instance, payload: { [string]: any })
	if currentCard ~= nil then
		currentCard:Destroy()
		currentCard = nil
	end

	local rarityColor = CreatureCatalog.rarityColor(payload.rarity)

	local card = TidetownUi.create("Frame", {
		Name = "CatchResultCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.new(0, 220, 0, CARD_HEIGHT),
		BackgroundColor3 = CARD_INTERIOR_COLOR,
		BorderSizePixel = 0,
		Parent = parent,
	}) :: Frame
	TidetownUi.round(card, 16)
	TidetownUi.stroke(card, rarityColor, 4)

	local viewport = TidetownUi.create("ViewportFrame", {
		Name = "CreatureViewport",
		Position = UDim2.new(0, 10, 0, 10),
		Size = UDim2.new(1, -20, 0, 160),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(200, 200, 210),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-1, -1, -0.5),
		Parent = card,
	}) :: ViewportFrame

	local model = CreatureModels.build(payload.speciesKey, VIEWPORT_MODEL_HEIGHT_STUDS)
	local _, boxSize = model:GetBoundingBox()
	local radius = math.max(boxSize.X, boxSize.Y, boxSize.Z)
	local distance = radius * 1.4 + 0.6

	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.new(Vector3.new(0, boxSize.Y * 0.18, -distance), Vector3.new(0, 0, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	model.Parent = viewport

	local speciesName = if typeof(payload.speciesName) == "string"
		then payload.speciesName
		else payload.speciesKey
	TidetownUi.create("TextLabel", {
		Name = "NameLabel",
		Position = UDim2.new(0, 10, 0, 176),
		Size = UDim2.new(1, -20, 0, 26),
		BackgroundTransparency = 1,
		Text = speciesName,
		TextSize = 22,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Parent = card,
	})

	TidetownUi.create("TextLabel", {
		Name = "RarityLabel",
		Position = UDim2.new(0, 10, 0, 204),
		Size = UDim2.new(1, -20, 0, 20),
		BackgroundTransparency = 1,
		Text = capitalizeRarity(payload.rarity),
		TextSize = 17,
		TextColor3 = rarityColor,
		Parent = card,
	})

	if payload.isNew == true then
		local badge = TidetownUi.create("TextLabel", {
			Name = "NewBadge",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -18, 0, 12),
			Size = UDim2.new(0, 64, 0, 28),
			Rotation = 12,
			BackgroundColor3 = NEW_BADGE_COLOR,
			BorderSizePixel = 0,
			Text = "NEW!",
			TextSize = 17,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			ZIndex = 3,
			Parent = card,
		}) :: TextLabel
		TidetownUi.round(badge, 10)
		TidetownUi.stroke(badge, OUTLINE_NAVY, 3)
	end

	TidetownUi.cartoonify(card)
	TidetownUi.popOpen(card)
	currentCard = card

	-- A gentle spin sells the 3D model. One lightweight loop per card
	-- is fine: a card lives for a couple of seconds and there is only
	-- ever one at a time.
	task.spawn(function()
		local angle = 0
		while card.Parent ~= nil do
			local delta = task.wait()
			angle += delta * CARD_SPIN_RADIANS_PER_SECOND
			model:PivotTo(CFrame.Angles(0, angle, 0))
		end
	end)

	task.delay(CARD_SECONDS, function()
		if card.Parent == nil then
			return
		end

		local scale = card:FindFirstChildOfClass("UIScale")
		if scale ~= nil then
			local closeTween = TweenService:Create(scale, CARD_CLOSE_INFO, { Scale = 0 })
			closeTween:Play()
			closeTween.Completed:Wait()
		end
		if currentCard == card then
			currentCard = nil
		end
		card:Destroy()
	end)
end

local function buildGui(playerGui: Instance): CatchGui
	local screenGui = TidetownUi.create("ScreenGui", {
		Name = "TidetownCatch",
		ResetOnSpawn = false,
		DisplayOrder = 10,
		Parent = playerGui,
	}) :: ScreenGui

	local holder = TidetownUi.create("Frame", {
		Name = "CastHolder",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.new(0, RING_MAXIMUM_DIAMETER, 0, RING_MAXIMUM_DIAMETER),
		BackgroundTransparency = 1,
		Parent = screenGui,
	}) :: Frame

	-- The gold target ring: repositioned per cast to the diameter the
	-- sweep will have at the perfect moment, so WHERE the flash will
	-- sit is visible from the first frame of the ring.
	local perfectMarker = TidetownUi.create("Frame", {
		Name = "PerfectMarker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(RING_MAXIMUM_DIAMETER, RING_MAXIMUM_DIAMETER),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = holder,
	}) :: Frame
	TidetownUi.create("UICorner", {
		CornerRadius = UDim.new(1, 0),
		Parent = perfectMarker,
	})
	local markerStroke = TidetownUi.stroke(perfectMarker, MARKER_GOLD, 5)

	local sweepRing = TidetownUi.create("Frame", {
		Name = "SweepRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(RING_MAXIMUM_DIAMETER, RING_MAXIMUM_DIAMETER),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = holder,
	}) :: Frame
	TidetownUi.create("UICorner", {
		CornerRadius = UDim.new(1, 0),
		Parent = sweepRing,
	})
	TidetownUi.stroke(sweepRing, Color3.fromRGB(255, 255, 255), 4)

	local castButton = TidetownUi.create("TextButton", {
		Name = "CastButton",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(BUTTON_DIAMETER, BUTTON_DIAMETER),
		BackgroundColor3 = DISABLED_COLOR,
		BorderSizePixel = 0,
		Text = "CAST",
		TextSize = 26,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		ZIndex = 2,
		Parent = holder,
	}) :: TextButton
	TidetownUi.round(castButton, BUTTON_DIAMETER / 2)
	TidetownUi.stroke(castButton, OUTLINE_NAVY, 4)
	TidetownUi.gloss(castButton)
	TidetownUi.hoverPop(castButton)

	-- The reason label shares the ring's space: it only shows while
	-- the button is gray, and the rings only show while it is not.
	local reasonLabel = TidetownUi.create("TextLabel", {
		Name = "ReasonLabel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(0, 320, 0, 22),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 16,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Visible = false,
		Parent = holder,
	}) :: TextLabel

	TidetownUi.cartoonify(holder)

	return {
		screenGui = screenGui,
		castButton = castButton,
		sweepRing = sweepRing,
		perfectMarker = perfectMarker,
		markerStroke = markerStroke,
		reasonLabel = reasonLabel,
	}
end

local CatchController = {}

function CatchController.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local gui = buildGui(playerGui)

	local beginCastRemote = TidetownRemotes.get("BeginCast") :: RemoteFunction
	local resolveCastRemote = TidetownRemotes.get("ResolveCast") :: RemoteFunction
	local tideFolder = Workspace:WaitForChild("Tidetown")

	local activeCast: ActiveCast? = nil
	local castToken = 0
	local requestInFlight = false
	local lastBeginAt = 0
	local castingAllowed = false
	local sweepTween: Tween? = nil

	local function applyAvailability(allowed: boolean, reason: string)
		castingAllowed = allowed
		gui.castButton.BackgroundColor3 = if allowed then ENABLED_COLOR else DISABLED_COLOR
		gui.reasonLabel.Text = reason
		gui.reasonLabel.Visible = reason ~= ""
	end

	--[[
		Mirrors the server's zone/phase rules so the button can gray
		out with a reason instead of letting every press bounce off
		the server. The server still validates everything.
	]]
	local function refreshAvailability()
		if activeCast ~= nil or requestInFlight then
			return
		end

		local character = localPlayer.Character
		local root: Instance? = if character ~= nil
			then character:FindFirstChild("HumanoidRootPart")
			else nil
		local phase = tideFolder:GetAttribute("Phase")

		if root == nil or not root:IsA("BasePart") then
			applyAvailability(false, "")
			return
		end

		if typeof(phase) ~= "string" then
			applyAvailability(false, "The tide is settling...")
			return
		end

		local zoneKey = TideLayout.zoneAt(root.Position)
		if zoneKey == nil then
			applyAvailability(false, "Nothing bites here")
		elseif not TideLayout.castableAt(zoneKey, phase) then
			applyAvailability(false, "The tide is wrong for this spot")
		else
			applyAvailability(true, "")
		end
	end

	local function clearRing()
		if sweepTween ~= nil then
			sweepTween:Cancel()
			sweepTween = nil
		end
		gui.sweepRing.Visible = false
		gui.perfectMarker.Visible = false
		gui.castButton.Text = "CAST"
	end

	-- Both tweens reverse, so the marker thickness and the button
	-- color spring back on their own after the flash.
	local function flashPerfect()
		TweenService:Create(gui.markerStroke, FLASH_INFO, { Thickness = 9 }):Play()
		TweenService:Create(gui.castButton, FLASH_INFO, {
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		}):Play()
	end

	--[[
		Resolves the active cast, from the second tap or the ring
		running out. The server scores the tap on its own clock; this
		side only renders whatever comes back.
	]]
	local function finishCast()
		local cast = activeCast
		if cast == nil or requestInFlight then
			return
		end

		requestInFlight = true
		-- The expected errors are a server handler fault or the
		-- remote dying mid-flight; either way the cast just fizzles.
		local ok, success, payload = pcall(function()
			return resolveCastRemote:InvokeServer(cast.castId)
		end)
		requestInFlight = false

		activeCast = nil
		clearRing()

		if not ok then
			Toast.push("The cast fizzled -- try again", "bad")
		elseif success ~= true then
			if typeof(payload) == "string" then
				Toast.push(payload, "bad")
			end
		elseif typeof(payload) == "table" then
			resultToast(payload)
			-- Rewards land in the body, scaled with value: perfect taps
			-- kick the camera, top rarities flare the world.
			if payload.quality == "perfect" then
				CameraFx.punchFov(-4)
			end
			if payload.rarity == "epic" or payload.rarity == "legendary" then
				CameraFx.flash()
			end
			if typeof(payload.speciesKey) == "string" and typeof(payload.rarity) == "string" then
				showResultCard(gui.screenGui, payload)
			end
		end

		refreshAvailability()
	end

	local function beginRing(payload: { [string]: any })
		castToken += 1
		local token = castToken
		activeCast = { castId = payload.castId, token = token }

		gui.castButton.Text = "NOW!"
		gui.castButton.BackgroundColor3 = ACTIVE_COLOR
		gui.reasonLabel.Visible = false

		local markerDiameter = RING_MAXIMUM_DIAMETER
			+ (RING_MINIMUM_DIAMETER - RING_MAXIMUM_DIAMETER) * payload.perfectAt
		gui.perfectMarker.Size = UDim2.fromOffset(markerDiameter, markerDiameter)
		gui.perfectMarker.Visible = true

		gui.sweepRing.Size = UDim2.fromOffset(RING_MAXIMUM_DIAMETER, RING_MAXIMUM_DIAMETER)
		gui.sweepRing.Visible = true
		local tween = TweenService:Create(
			gui.sweepRing,
			TweenInfo.new(payload.ringSeconds, Enum.EasingStyle.Linear),
			{ Size = UDim2.fromOffset(RING_MINIMUM_DIAMETER, RING_MINIMUM_DIAMETER) }
		)
		sweepTween = tween
		tween:Play()

		-- The tutorial says "tap again on the flash" -- this is that
		-- flash, timed to the same fraction the server judges by.
		task.delay(payload.ringSeconds * payload.perfectAt, function()
			local current = activeCast
			if current ~= nil and current.token == token then
				flashPerfect()
			end
		end)

		-- An untapped ring still resolves, so the whiff consolation
		-- and the cooldown both come from the server, not a guess.
		task.delay(payload.ringSeconds + RING_EXPIRY_GRACE_SECONDS, function()
			local current = activeCast
			if current ~= nil and current.token == token then
				finishCast()
			end
		end)
	end

	local function onPressed()
		if requestInFlight then
			return
		end

		if activeCast ~= nil then
			finishCast()
			return
		end

		if not castingAllowed then
			return
		end

		-- Client cooldown mirror: mashing between casts never even
		-- reaches the server, which enforces the same number.
		if os.clock() - lastBeginAt < TidetownConfig.catch.castCooldownSeconds then
			return
		end

		requestInFlight = true
		-- The expected errors are a server handler fault or the
		-- remote dying mid-flight.
		local ok, success, payload = pcall(function()
			return beginCastRemote:InvokeServer()
		end)
		requestInFlight = false

		if not ok then
			Toast.push("The cast fizzled -- try again", "bad")
			return
		end

		if success ~= true then
			if typeof(payload) == "string" then
				Toast.push(payload, "bad")
			end
			return
		end

		if
			typeof(payload) ~= "table"
			or typeof(payload.castId) ~= "string"
			or typeof(payload.ringSeconds) ~= "number"
			or typeof(payload.perfectAt) ~= "number"
		then
			return
		end

		lastBeginAt = os.clock()
		beginRing(payload)
	end

	gui.castButton.Activated:Connect(onPressed)

	while true do
		refreshAvailability()
		task.wait(ZONE_POLL_SECONDS)
	end
end

return CatchController
