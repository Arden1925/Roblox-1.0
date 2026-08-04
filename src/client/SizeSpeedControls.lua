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

-- The size slider's own pair of moods: amber swell for growing, cool
-- lavender squish for shrinking.
local GROW_FILL = Color3.fromRGB(255, 184, 76)
local GROW_EDGE = Color3.fromRGB(255, 214, 120)
local SHRINK_FILL = Color3.fromRGB(162, 155, 254)
local SHRINK_HANDLE = Color3.fromRGB(216, 210, 255)
local SHRINK_EDGE = Color3.fromRGB(140, 130, 240)

-- Tiny drags still count as a direction; the value range is only 8
-- units wide, so per-move deltas are small.
local DIRECTION_THRESHOLD = 0.03
-- The size slider reports 0..1 fractions, so its direction threshold
-- must be far finer than the speed slider's 8-unit range.
local FRACTION_THRESHOLD = 0.004
local RETRIGGER_SECONDS = 0.1
local PARTICLE_SECONDS = 0.28
local MELT_DELAY_SECONDS = 0.45

local RECOLOR_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ICICLE_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ICICLE_HEIGHTS = { 14, 9, 6 }
local ICICLE_WIDTH = 5
local HALO_DIAMETER = 36

local localPlayer = Players.LocalPlayer

local SizeSpeedControls = {}

type SliderEffects = {
	fill: Frame,
	handle: GuiButton,
	handleStroke: UIStroke,
	halo: Frame,
	icicles: { Frame },
	generation: number,
	neutralFill: Color3,
}

--[[
	Effect rig for the speed slider: a halo that lights up behind the
	handle when charging, and icicles that grow off it when frozen. The
	icicles and particles ride on the handle; the halo cannot, because a
	child always renders in front of its parent under Sibling ZIndex
	rules, so it sits on the track and follows the handle by signal.
]]
local function createSliderEffects(sliderHolder: Frame, neutralFill: Color3): SliderEffects?
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
		handleStroke = UiBuilder.stroke(handle, neutralFill, 2)
	end

	local halo = UiBuilder.create("Frame", {
		Name = "EffectHalo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = handle.Position,
		Size = UDim2.new(0, HALO_DIAMETER, 0, HALO_DIAMETER),
		BackgroundColor3 = GLOW_EDGE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = -1,
		Parent = track,
	}) :: Frame
	UiBuilder.round(halo, HALO_DIAMETER // 2)

	handle:GetPropertyChangedSignal("Position"):Connect(function()
		halo.Position = handle.Position
	end)

	local icicles = {}
	for icicleIndex = 1, #ICICLE_HEIGHTS do
		local icicle = UiBuilder.create("Frame", {
			Name = "Icicle" .. icicleIndex,
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.new(0, 2 + (icicleIndex - 1) * 7, 1, -3),
			Size = UDim2.new(0, ICICLE_WIDTH, 0, 0),
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
		neutralFill = neutralFill,
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
			BackgroundColor3 = effects.neutralFill,
		}):Play()
		TweenService:Create(effects.handle, RECOLOR_INFO, {
			BackgroundColor3 = HANDLE_NEUTRAL,
		}):Play()
		TweenService:Create(effects.handleStroke, RECOLOR_INFO, {
			Color = effects.neutralFill,
			Thickness = 2,
		}):Play()
		TweenService:Create(effects.halo, RECOLOR_INFO, {
			BackgroundTransparency = 1,
		}):Play()

		for _, icicle in ipairs(effects.icicles) do
			TweenService:Create(icicle, ICICLE_INFO, {
				Size = UDim2.new(0, ICICLE_WIDTH, 0, 0),
			}):Play()
		end
	end)
end

-- Text glyphs get their sticker outline from the cartoon pass a beat
-- after parenting, and outlines ignore TextTransparency; this fades
-- the outline alongside any glyph that fades itself out.
local function fadeOutlineLater(glyph: Instance, seconds: number)
	task.defer(function()
		local outline = glyph:FindFirstChild("TextOutline")
		if outline ~= nil and outline:IsA("UIStroke") then
			TweenService:Create(outline, TweenInfo.new(seconds, Enum.EasingStyle.Quad), {
				Transparency = 1,
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

		-- The cartoon pass adds the outline a beat after parenting, and
		-- outlines ignore TextTransparency -- fade it too or the glyph
		-- ends as a dark ghost for a frame.
		fadeOutlineLater(spark, 0.25)
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

	fadeOutlineLater(flake, 0.6)
end

local function spawnGrowGlyphs(effects: SliderEffects)
	for glyphIndex = 1, 2 do
		local direction = if glyphIndex == 1 then -1 else 1
		local glyph = UiBuilder.create("TextLabel", {
			Name = "GrowGlyph",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, direction * 9, 0, -2),
			Size = UDim2.new(0, 16, 0, 16),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Text = "+",
			TextColor3 = GROW_EDGE,
			TextSize = 15,
			Parent = effects.handle,
		})

		local rise = TweenService:Create(glyph, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
			Position = UDim2.new(0.5, direction * 18, 0, -16),
			TextSize = 19,
			TextTransparency = 1,
		})
		rise:Play()
		rise.Completed:Connect(function()
			glyph:Destroy()
		end)

		fadeOutlineLater(glyph, 0.3)
	end
end

local function spawnShrinkGlyph(effects: SliderEffects)
	local glyph = UiBuilder.create("TextLabel", {
		Name = "ShrinkGlyph",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, math.random(-12, 12), 0, -6),
		Size = UDim2.new(0, 16, 0, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "-",
		TextColor3 = SHRINK_HANDLE,
		TextSize = 17,
		Parent = effects.handle,
	})

	local sink = TweenService:Create(glyph, TweenInfo.new(0.45, Enum.EasingStyle.Sine), {
		Position = glyph.Position + UDim2.new(0, 0, 0, 18),
		TextSize = 11,
		TextTransparency = 1,
	})
	sink:Play()
	sink.Completed:Connect(function()
		glyph:Destroy()
	end)

	fadeOutlineLater(glyph, 0.45)
end

-- Charge and frost each repaint the FULL handle state -- including the
-- other effect's leftovers -- because a direction reversal mid-drag
-- keeps cancelling the pending melt, so nothing else would clear them.
local function playCharge(effects: SliderEffects, withParticles: boolean)
	TweenService:Create(effects.fill, RECOLOR_INFO, {
		BackgroundColor3 = GLOW_FILL,
	}):Play()
	TweenService:Create(effects.handle, RECOLOR_INFO, {
		BackgroundColor3 = HANDLE_NEUTRAL,
	}):Play()
	TweenService:Create(effects.handleStroke, RECOLOR_INFO, {
		Color = GLOW_EDGE,
		Thickness = 4,
	}):Play()
	TweenService:Create(effects.halo, RECOLOR_INFO, {
		BackgroundColor3 = GLOW_EDGE,
		BackgroundTransparency = 0.55,
	}):Play()

	for _, icicle in ipairs(effects.icicles) do
		TweenService:Create(icicle, ICICLE_INFO, {
			Size = UDim2.new(0, ICICLE_WIDTH, 0, 0),
		}):Play()
	end

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
	TweenService:Create(effects.halo, RECOLOR_INFO, {
		BackgroundTransparency = 1,
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

-- The size slider's versions of charge and frost: growing swells the
-- handle warm amber with rising plus signs, shrinking squishes it
-- lavender with sinking minus signs. Same repaint-everything rule.
local function playGrow(effects: SliderEffects, withParticles: boolean)
	TweenService:Create(effects.fill, RECOLOR_INFO, {
		BackgroundColor3 = GROW_FILL,
	}):Play()
	TweenService:Create(effects.handle, RECOLOR_INFO, {
		BackgroundColor3 = HANDLE_NEUTRAL,
	}):Play()
	TweenService:Create(effects.handleStroke, RECOLOR_INFO, {
		Color = GROW_EDGE,
		Thickness = 4,
	}):Play()
	TweenService:Create(effects.halo, RECOLOR_INFO, {
		BackgroundColor3 = GROW_EDGE,
		BackgroundTransparency = 0.55,
	}):Play()

	for _, icicle in ipairs(effects.icicles) do
		TweenService:Create(icicle, ICICLE_INFO, {
			Size = UDim2.new(0, ICICLE_WIDTH, 0, 0),
		}):Play()
	end

	if withParticles then
		spawnGrowGlyphs(effects)
	end

	meltLater(effects)
end

local function playShrink(effects: SliderEffects, withParticles: boolean)
	TweenService:Create(effects.fill, RECOLOR_INFO, {
		BackgroundColor3 = SHRINK_FILL,
	}):Play()
	TweenService:Create(effects.handle, RECOLOR_INFO, {
		BackgroundColor3 = SHRINK_HANDLE,
	}):Play()
	TweenService:Create(effects.handleStroke, RECOLOR_INFO, {
		Color = SHRINK_EDGE,
		Thickness = 3,
	}):Play()
	TweenService:Create(effects.halo, RECOLOR_INFO, {
		BackgroundTransparency = 1,
	}):Play()

	for _, icicle in ipairs(effects.icicles) do
		TweenService:Create(icicle, ICICLE_INFO, {
			Size = UDim2.new(0, ICICLE_WIDTH, 0, 0),
		}):Play()
	end

	if withParticles then
		spawnShrinkGlyph(effects)
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

	-- Bottom-right corner: out of the way of gameplay, mirroring the
	-- backpack button in the opposite corner, instead of the old box
	-- floating awkwardly at mid-screen height.
	local panel = UiBuilder.create("Frame", {
		Name = "SliderPanel",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -12),
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

	speedEffects = createSliderEffects(sliderHolder, SPEED_COLOR)

	local sizeSection = createSliderSection(panel, 2, "SIZE (SIZE MASTER)", SIZE_COLOR)
	local sizeHolder = UiBuilder.create("Frame", {
		Name = "SizeSliderHolder",
		Position = UDim2.new(0, 0, 0, 30),
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Parent = sizeSection,
	})

	local lastFraction = 1
	local lastSizeEffectAt = 0
	local lastSizeParticleAt = 0
	local sizeEffects: SliderEffects? = nil

	local function buildSizeControl()
		for _, child in ipairs(sizeHolder:GetChildren()) do
			child:Destroy()
		end
		sizeEffects = nil

		if localPlayer:GetAttribute("OwnsSizeMaster") == true then
			UiBuilder.slider(sizeHolder, 0, 1, 1, SIZE_COLOR, function(fraction)
				-- Same throttled direction FX as the speed slider, with
				-- the size slider's own grow/shrink identity.
				local now = os.clock()
				if sizeEffects ~= nil and now - lastSizeEffectAt > RETRIGGER_SECONDS then
					local withParticles = now - lastSizeParticleAt > PARTICLE_SECONDS
					if fraction > lastFraction + FRACTION_THRESHOLD then
						lastSizeEffectAt = now
						playGrow(sizeEffects, withParticles)
					elseif fraction < lastFraction - FRACTION_THRESHOLD then
						lastSizeEffectAt = now
						playShrink(sizeEffects, withParticles)
					end
					if withParticles and lastSizeEffectAt == now then
						lastSizeParticleAt = now
					end
				end
				lastFraction = fraction

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

			sizeEffects = createSliderEffects(sizeHolder, SIZE_COLOR)
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
