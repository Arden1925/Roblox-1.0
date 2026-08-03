--[[
	The slider panel on the right edge: speed for everyone (a narrow,
	comfort-only range) and body size for Size Master owners. The size
	slider is this pass's entire product, so non-owners see it locked
	with a one-tap purchase prompt.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Client = script.Parent
local Toast = require(Client.Toast)
local UiBuilder = require(Client.UiBuilder)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local PANEL_COLOR = Color3.fromRGB(24, 30, 38)
local SPEED_COLOR = Color3.fromRGB(0, 206, 201)
local SIZE_COLOR = Color3.fromRGB(255, 159, 67)
local HANDLE_NEUTRAL = Color3.fromRGB(245, 246, 250)

local GLOW_FILL = Color3.fromRGB(255, 217, 59)
local GLOW_EDGE = Color3.fromRGB(255, 233, 106)
local FROST_FILL = Color3.fromRGB(90, 122, 148)
local FROST_HANDLE = Color3.fromRGB(191, 228, 250)
local FROST_EDGE = Color3.fromRGB(127, 182, 221)
local FROST_FLAKE = Color3.fromRGB(223, 242, 255)

-- Tiny drags still count as a direction; the value range is only 8
-- units wide, so per-move deltas are small.
local DIRECTION_THRESHOLD = 0.03
local RETRIGGER_SECONDS = 0.1
local PARTICLE_SECONDS = 0.28
local MELT_DELAY_SECONDS = 0.45

local RECOLOR_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ICICLE_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ICICLE_HEIGHTS = { 14, 9, 6 }

local localPlayer = Players.LocalPlayer

local SizeSpeedControls = {}

type SliderEffects = {
	fill: Frame,
	handle: GuiButton,
	handleStroke: UIStroke,
	halo: Frame,
	icicles: { Frame },
	generation: number,
}

--[[
	Effect rig for the speed slider: a halo that lights up behind the
	handle when charging, and icicles that grow off it when frozen.
	Everything is parented to the handle so the effects follow the drag
	instead of flying across the panel.
]]
local function createSliderEffects(sliderHolder: Frame): SliderEffects?
	local track = sliderHolder:FindFirstChild("SliderTrack")
	if track == nil then
		return nil
	end

	local fill = track:FindFirstChild("SliderFill")
	local handle = track:FindFirstChild("SliderHandle")
	if fill == nil or handle == nil or not handle:IsA("GuiButton") then
		return nil
	end

	local handleStroke = handle:FindFirstChildOfClass("UIStroke")
	if handleStroke == nil then
		handleStroke = UiBuilder.stroke(handle, SPEED_COLOR, 2)
	end

	local halo = UiBuilder.create("Frame", {
		Name = "EffectHalo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, 14, 1, 14),
		BackgroundColor3 = GLOW_EDGE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = handle,
	}) :: Frame
	UiBuilder.round(halo, 18)

	local icicles = {}
	for icicleIndex = 1, #ICICLE_HEIGHTS do
		local icicle = UiBuilder.create("Frame", {
			Name = "Icicle" .. icicleIndex,
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.new(0, 2 + (icicleIndex - 1) * 7, 1, -3),
			Size = UDim2.new(0, 5, 0, 0),
			BackgroundColor3 = FROST_HANDLE,
			BorderSizePixel = 0,
			Parent = handle,
		}) :: Frame
		UiBuilder.round(icicle, 3)
		table.insert(icicles, icicle)
	end

	return {
		fill = fill :: Frame,
		handle = handle,
		handleStroke = handleStroke,
		halo = halo,
		icicles = icicles,
		generation = 0,
	}
end

local function meltLater(effects: SliderEffects)
	effects.generation += 1
	local generation = effects.generation

	task.delay(MELT_DELAY_SECONDS, function()
		if effects.generation ~= generation then
			return
		end

		TweenService:Create(effects.fill, RECOLOR_INFO, {
			BackgroundColor3 = SPEED_COLOR,
		}):Play()
		TweenService:Create(effects.handle, RECOLOR_INFO, {
			BackgroundColor3 = HANDLE_NEUTRAL,
		}):Play()
		TweenService:Create(effects.handleStroke, RECOLOR_INFO, {
			Color = SPEED_COLOR,
			Thickness = 2,
		}):Play()
		TweenService:Create(effects.halo, RECOLOR_INFO, {
			BackgroundTransparency = 1,
		}):Play()

		for _, icicle in ipairs(effects.icicles) do
			TweenService:Create(icicle, ICICLE_INFO, {
				Size = UDim2.new(0, 5, 0, 0),
			}):Play()
		end
	end)
end

-- Two small bolts flick off the handle and fade -- sparks at the
-- source, not a panel-wide light show.
local function spawnSparks(effects: SliderEffects)
	for sparkIndex = 1, 2 do
		local direction = if sparkIndex == 1 then -1 else 1
		local spark = UiBuilder.create("TextLabel", {
			Name = "Spark",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, direction * 10, 0, -2),
			Size = UDim2.new(0, 16, 0, 16),
			Rotation = direction * 25,
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Text = "\u{26A1}",
			TextColor3 = GLOW_EDGE,
			TextSize = 13,
			Parent = effects.handle,
		})

		local flick = TweenService:Create(spark, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
			Position = UDim2.new(0.5, direction * 20, 0, -14),
			TextTransparency = 1,
		})
		flick:Play()
		flick.Completed:Connect(function()
			spark:Destroy()
		end)
	end
end

local function spawnSnowflake(effects: SliderEffects)
	local flake = UiBuilder.create("TextLabel", {
		Name = "Snowflake",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, math.random(-16, 16), 0, -8),
		Size = UDim2.new(0, 14, 0, 14),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "\u{2744}",
		TextColor3 = FROST_FLAKE,
		TextSize = 13,
		Parent = effects.handle,
	})

	local drift = TweenService:Create(flake, TweenInfo.new(0.6, Enum.EasingStyle.Sine), {
		Position = flake.Position + UDim2.new(0, 0, 0, 22),
		TextTransparency = 1,
	})
	drift:Play()
	drift.Completed:Connect(function()
		flake:Destroy()
	end)
end

local function playCharge(effects: SliderEffects, withParticles: boolean)
	TweenService:Create(effects.fill, RECOLOR_INFO, {
		BackgroundColor3 = GLOW_FILL,
	}):Play()
	TweenService:Create(effects.handleStroke, RECOLOR_INFO, {
		Color = GLOW_EDGE,
		Thickness = 4,
	}):Play()
	TweenService:Create(effects.halo, RECOLOR_INFO, {
		BackgroundTransparency = 0.55,
	}):Play()

	if withParticles then
		spawnSparks(effects)
	end

	meltLater(effects)
end

local function playFrost(effects: SliderEffects, withParticles: boolean)
	TweenService:Create(effects.fill, RECOLOR_INFO, {
		BackgroundColor3 = FROST_FILL,
	}):Play()
	TweenService:Create(effects.handle, RECOLOR_INFO, {
		BackgroundColor3 = FROST_HANDLE,
	}):Play()
	TweenService:Create(effects.handleStroke, RECOLOR_INFO, {
		Color = FROST_EDGE,
		Thickness = 3,
	}):Play()

	for icicleIndex, icicle in ipairs(effects.icicles) do
		TweenService:Create(icicle, ICICLE_INFO, {
			Size = UDim2.new(0, 5, 0, ICICLE_HEIGHTS[icicleIndex]),
		}):Play()
	end

	if withParticles then
		spawnSnowflake(effects)
	end

	meltLater(effects)
end

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
		ClipsDescendants = true,
		Parent = screenGui,
	}) :: Frame
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

	local lastSpeed = GameConfig.speed.default
	local lastEffectAt = 0
	local lastParticleAt = 0
	local speedEffects: SliderEffects? = nil

	UiBuilder.slider(
		sliderHolder,
		GameConfig.speed.minimum,
		GameConfig.speed.maximum,
		GameConfig.speed.default,
		SPEED_COLOR,
		function(value)
			-- Effects re-trigger while dragging so the state holds, but
			-- particles get their own slower throttle so the handle is
			-- never buried in sparks or snow.
			local now = os.clock()
			if speedEffects ~= nil and now - lastEffectAt > RETRIGGER_SECONDS then
				local withParticles = now - lastParticleAt > PARTICLE_SECONDS
				if value > lastSpeed + DIRECTION_THRESHOLD then
					lastEffectAt = now
					playCharge(speedEffects, withParticles)
				elseif value < lastSpeed - DIRECTION_THRESHOLD then
					lastEffectAt = now
					playFrost(speedEffects, withParticles)
				end
				if withParticles and lastEffectAt == now then
					lastParticleAt = now
				end
			end
			lastSpeed = value

			task.spawn(function()
				local setDesiredSpeed = Remotes.get("SetDesiredSpeed") :: RemoteEvent
				setDesiredSpeed:FireServer(value)
			end)
		end
	)

	speedEffects = createSliderEffects(sliderHolder)

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
	UiBuilder.cartoonify(panel)
end

return SizeSpeedControls
