--[[
	The join experience: a full-screen loading cover with rotating pro
	tips while the world streams in, then the winged landing cutscene
	the server triggers when it drops the player onto the Main Island --
	a superman dive from the sky, touchdown, and a size-glitch beat
	where the character flickers big and small until their real size
	settles. All character scaling here is client-local, so the server's
	size replication is never fought.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent
local SoundController = require(Client.SoundController)
local UiBuilder = require(Client.UiBuilder)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local COVER_COLOR = Color3.fromRGB(18, 24, 44)
local COVER_BOTTOM_COLOR = Color3.fromRGB(38, 52, 96)
local TITLE_COLOR = Color3.fromRGB(255, 202, 58)
local TIP_COLOR = Color3.fromRGB(178, 190, 195)
local WING_COLOR = Color3.fromRGB(245, 246, 250)

local TIP_SWAP_SECONDS = 4
local MINIMUM_COVER_SECONDS = 1.5
-- If the server never calls for a landing (brand-new player in the
-- tutorial), the cover lets go on its own.
local COVER_TIMEOUT_SECONDS = 8
local DIVE_SECONDS = 2.4
local FLARE_SECONDS = 0.7
local GLITCH_STEP_SECONDS = 0.24
local GLITCH_FACTORS = { 1.9, 0.5, 2.4, 0.4, 1.6, 0.7 }

local CLICK_SOUND = "rbxasset://sounds/snap.mp3"
local WHOOSH_SOUND = "rbxasset://sounds/electronicpingshort.wav"

local localPlayer = Players.LocalPlayer

local LoadingGui = {}

-- Fisher-Yates over a copy, so tips come out in a fresh random order
-- every session and never repeat until the list runs dry.
local function shuffledTips(): { string }
	local tips = table.clone(GameConfig.proTips)
	for tipIndex = #tips, 2, -1 do
		local swapIndex = math.random(tipIndex)
		tips[tipIndex], tips[swapIndex] = tips[swapIndex], tips[tipIndex]
	end

	return tips
end

local function buildCover(screenGui: ScreenGui): (Frame, TextLabel)
	local cover = UiBuilder.create("Frame", {
		Name = "LoadingCover",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = COVER_COLOR,
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = screenGui,
	}) :: Frame
	UiBuilder.gradient(cover, COVER_COLOR, COVER_BOTTOM_COLOR)

	local title = UiBuilder.create("TextLabel", {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.38, 0),
		Size = UDim2.new(0, 560, 0, 64),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Text = "+1 SIZE ESCAPE",
		TextColor3 = TITLE_COLOR,
		TextSize = 52,
		ZIndex = 11,
		Parent = cover,
	}) :: TextLabel
	UiBuilder.shineText(title)

	local status = UiBuilder.create("TextLabel", {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 400, 0, 28),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "GETTING THINGS READY",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 20,
		ZIndex = 11,
		Parent = cover,
	}) :: TextLabel

	local tipLabel = UiBuilder.create("TextLabel", {
		Name = "ProTip",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -36),
		Size = UDim2.new(0, 620, 0, 44),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = TIP_COLOR,
		TextSize = 16,
		TextWrapped = true,
		ZIndex = 11,
		Parent = cover,
	}) :: TextLabel

	-- The breathing dots: cheap motion that says "not frozen".
	task.spawn(function()
		local dotCount = 0
		while cover.Parent ~= nil do
			dotCount = (dotCount + 1) % 4
			status.Text = "GETTING THINGS READY" .. string.rep(".", dotCount)
			task.wait(0.4)
		end
	end)

	return cover, tipLabel
end

local function dismissCover(cover: Frame)
	if cover.Parent == nil then
		return
	end

	for _, descendant in ipairs(cover:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			TweenService:Create(descendant, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		end
	end
	TweenService:Create(cover, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	task.delay(0.55, function()
		cover:Destroy()
	end)
end

-- Client-local superman wings: welded to the anchored root so they ride
-- the flight tweens, faded out after touchdown.
local function attachWings(rootPart: BasePart): { BasePart }
	local wings = {}

	for _, side in ipairs({ -1, 1 }) do
		for layerIndex = 1, 3 do
			local feather = Instance.new("Part")
			feather.Name = "CutsceneWing"
			feather.Size = Vector3.new(0.35, 0.9, 3.6 - layerIndex * 0.6)
			feather.Color = WING_COLOR
			feather.Material = Enum.Material.SmoothPlastic
			feather.CanCollide = false
			feather.CanQuery = false
			feather.Massless = true
			feather.CFrame = rootPart.CFrame
				* CFrame.new(side * (0.9 + layerIndex * 0.5), 0.9 - layerIndex * 0.28, 1.2)
				* CFrame.Angles(0, side * math.rad(20 + layerIndex * 14), side * math.rad(-14))
			feather.Parent = rootPart

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = rootPart
			weld.Part1 = feather
			weld.Parent = feather

			table.insert(wings, feather)
		end
	end

	return wings
end

local function removeWings(wings: { BasePart })
	for _, feather in ipairs(wings) do
		TweenService:Create(feather, TweenInfo.new(0.4), { Transparency = 1 }):Play()
	end
	task.delay(0.45, function()
		for _, feather in ipairs(wings) do
			feather:Destroy()
		end
	end)
end

--[[
	The landing itself. Runs entirely on this client: the character is
	already standing on the pad server-side, so every step here is
	cosmetic and safe to abort.
]]
local function playLanding(cover: Frame?, landingPosition: Vector3)
	local character = localPlayer.Character
	if character == nil then
		character = localPlayer.CharacterAdded:Wait()
	end
	local rootPart = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if rootPart == nil then
		if cover ~= nil then
			dismissCover(cover)
		end

		return
	end

	local camera = Workspace.CurrentCamera
	local originalScale = character:GetScale()
	local wings = {}

	-- Any error mid-cutscene must never strand an anchored character or
	-- a scriptable camera; expected failures are streaming hiccups.
	local played = pcall(function()
		local startPosition = landingPosition + Vector3.new(28, GameConfig.hub.skyDropHeight, 46)
		local hoverPosition = landingPosition + Vector3.new(0, 24, 0)

		rootPart.Anchored = true
		rootPart.CFrame = CFrame.lookAt(startPosition, hoverPosition)
		wings = attachWings(rootPart)

		camera.CameraType = Enum.CameraType.Scriptable

		local chase: RBXScriptConnection? = nil
		chase = RunService.RenderStepped:Connect(function()
			local toTarget = (landingPosition - rootPart.Position)
			local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
			local back = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, 1)
			camera.CFrame = CFrame.lookAt(
				rootPart.Position - back * 13 + Vector3.new(0, 6, 0),
				rootPart.Position
			)
		end)

		if cover ~= nil then
			dismissCover(cover)
		end
		SoundController.playSfx(rootPart, WHOOSH_SOUND, 0.5)

		local dive = TweenService:Create(
			rootPart,
			TweenInfo.new(DIVE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ CFrame = CFrame.lookAt(hoverPosition, landingPosition) }
		)
		dive:Play()
		dive.Completed:Wait()

		local upright = CFrame.lookAt(landingPosition, landingPosition + Vector3.new(0, 0, 60))
		local flare = TweenService:Create(
			rootPart,
			TweenInfo.new(FLARE_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ CFrame = upright }
		)
		flare:Play()
		flare.Completed:Wait()

		SoundController.playSfx(rootPart, CLICK_SOUND, 0.6)
		removeWings(wings)
		wings = {}

		if chase ~= nil then
			chase:Disconnect()
			chase = nil
		end

		-- Front camera for the glitch: the character stares at their own
		-- flickering body while their size finds itself again.
		local front = landingPosition + Vector3.new(0, 2.5, 10)
		camera.CFrame = CFrame.lookAt(front, landingPosition + Vector3.new(0, 2, 0))

		for _, factor in ipairs(GLITCH_FACTORS) do
			character:ScaleTo(originalScale * factor)
			SoundController.playSfx(rootPart, CLICK_SOUND, 0.7 + math.random() * 0.8)
			camera.CFrame = camera.CFrame
				* CFrame.new((math.random() - 0.5) * 0.8, (math.random() - 0.5) * 0.8, 0)
			task.wait(GLITCH_STEP_SECONDS)
		end

		character:ScaleTo(originalScale)
		SoundController.playSfx(rootPart, WHOOSH_SOUND, 1.4)
		task.wait(0.35)
	end)

	if not played then
		removeWings(wings)
	end

	-- Unconditional cleanup: the player must always get control back.
	pcall(function()
		character:ScaleTo(originalScale)
	end)
	rootPart.Anchored = false
	camera.CameraType = Enum.CameraType.Custom
end

function LoadingGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = UiBuilder.create("ScreenGui", {
		Name = "LoadingGui",
		ResetOnSpawn = false,
		DisplayOrder = 20,
		IgnoreGuiInset = true,
		Parent = playerGui,
	}) :: ScreenGui

	local cover, tipLabel = buildCover(screenGui)
	local coverShownAt = os.clock()
	local landingRequested = false

	task.spawn(function()
		local tips = shuffledTips()
		local tipIndex = 0
		while tipLabel.Parent ~= nil do
			tipIndex += 1
			if tipIndex > #tips then
				tips = shuffledTips()
				tipIndex = 1
			end
			tipLabel.Text = "PRO TIP: " .. tips[tipIndex]
			task.wait(TIP_SWAP_SECONDS)
		end
	end)

	-- New players never get a landing call; the cover fades on its own
	-- once their character exists and a beat has passed.
	task.spawn(function()
		local deadline = os.clock() + COVER_TIMEOUT_SECONDS
		while os.clock() < deadline and not landingRequested do
			if
				localPlayer.Character ~= nil
				and os.clock() - coverShownAt > MINIMUM_COVER_SECONDS + 1
			then
				break
			end
			task.wait(0.2)
		end

		if not landingRequested then
			dismissCover(cover)
		end
	end)

	local beginHubLanding = Remotes.get("BeginHubLanding") :: RemoteEvent
	beginHubLanding.OnClientEvent:Connect(function(landingPosition)
		if landingRequested or typeof(landingPosition) ~= "Vector3" then
			return
		end
		landingRequested = true

		task.spawn(function()
			-- Let the cover breathe for a moment even on instant loads.
			local shownFor = os.clock() - coverShownAt
			if cover.Parent ~= nil and shownFor < MINIMUM_COVER_SECONDS then
				task.wait(MINIMUM_COVER_SECONDS - shownFor)
			end

			playLanding(if cover.Parent ~= nil then cover else nil, landingPosition)
		end)
	end)
end

return LoadingGui
