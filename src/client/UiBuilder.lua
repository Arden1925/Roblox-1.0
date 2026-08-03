--[[
	Shared UI toolkit: instance building plus the handful of effects that
	give every window in the game the same feel -- gradients, hover pops,
	springy open animations, pulsing glows, and a draggable slider. One
	implementation here keeps ten GUIs consistent.
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Cartoon-style: hovers overshoot and settle with a springy wobble
-- instead of a flat ease.
local HOVER_IN_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
local HOVER_OUT_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local OPEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PULSE_INFO = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local UiBuilder = {}

function UiBuilder.create(className: string, properties: { [string]: any }): Instance
	local instance = Instance.new(className)

	for key, value in pairs(properties) do
		if key ~= "Parent" then
			instance[key] = value
		end
	end

	instance.Parent = properties.Parent

	return instance
end

function UiBuilder.round(instance: Instance, radius: number)
	UiBuilder.create("UICorner", {
		CornerRadius = UDim.new(0, radius),
		Parent = instance,
	})
end

function UiBuilder.gradient(instance: Instance, topColor: Color3, bottomColor: Color3)
	UiBuilder.create("UIGradient", {
		Color = ColorSequence.new(topColor, bottomColor),
		Rotation = 90,
		Parent = instance,
	})
end

function UiBuilder.stroke(instance: Instance, color: Color3, thickness: number): UIStroke
	local stroke = UiBuilder.create("UIStroke", {
		Color = color,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = instance,
	})

	return stroke :: UIStroke
end

-- Cartoon hover: the button bounces up in size with a little tilt, then
-- springs back. UIScale means the button's own Size (and any layout
-- using it) is never disturbed.
function UiBuilder.hoverPop(button: GuiButton)
	local scale = UiBuilder.create("UIScale", {
		Scale = 1,
		Parent = button,
	}) :: UIScale

	local restRotation = button.Rotation

	button.MouseEnter:Connect(function()
		TweenService:Create(scale, HOVER_IN_INFO, { Scale = 1.12 }):Play()
		TweenService:Create(button, HOVER_IN_INFO, { Rotation = restRotation - 3 }):Play()
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(scale, HOVER_OUT_INFO, { Scale = 1 }):Play()
		TweenService:Create(button, HOVER_OUT_INFO, { Rotation = restRotation }):Play()
	end)
end

-- Springy pop for opening windows; returns the tween so callers can
-- chain on Completed if they need to.
function UiBuilder.popOpen(window: GuiObject): Tween
	local scale = window:FindFirstChildOfClass("UIScale")
	if scale == nil then
		scale = UiBuilder.create("UIScale", { Parent = window }) :: UIScale
	end

	scale.Scale = 0.7
	window.Visible = true

	local tween = TweenService:Create(scale, OPEN_INFO, { Scale = 1 })
	tween:Play()

	return tween
end

-- An endlessly breathing glow, for buttons that want to be noticed.
function UiBuilder.pulse(stroke: UIStroke)
	TweenService:Create(stroke, PULSE_INFO, {
		Thickness = stroke.Thickness + 2,
		Transparency = 0.5,
	}):Play()
end

--[[
	Special-item text: a rainbow gradient that slowly sweeps through the
	label, plus a flashing brightness pulse. One looping tween each, so
	the cost stays fixed no matter how long the label lives.
]]
function UiBuilder.shineText(label: TextLabel)
	local gradient = UiBuilder.create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 89, 94)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 202, 58)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(138, 201, 38)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(25, 130, 196)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 89, 94)),
		}),
		Rotation = 0,
		Parent = label,
	}) :: UIGradient

	TweenService:Create(
		gradient,
		TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
		{ Rotation = 360 }
	):Play()

	TweenService:Create(
		label,
		TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ TextTransparency = 0.35 }
	):Play()
end

--[[
	A bright band that sweeps across a card forever -- the classic
	storefront shimmer that pulls the eye to featured items.
]]
function UiBuilder.shimmer(card: GuiObject)
	local band = UiBuilder.create("Frame", {
		Name = "Shimmer",
		Position = UDim2.new(-0.3, 0, 0, 0),
		Size = UDim2.new(0.18, 0, 1, 0),
		Rotation = 12,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = card,
	})

	UiBuilder.create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = band,
	})

	TweenService:Create(
		band,
		TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, false, 1),
		{ Position = UDim2.new(1.2, 0, 0, 0) }
	):Play()
end

--[[
	A draggable horizontal slider. Calls onChanged with a value in
	[minimum, maximum] while dragging and on release. Returns a function
	that moves the handle programmatically (for initial values).
]]
function UiBuilder.slider(
	parent: Instance,
	minimum: number,
	maximum: number,
	initial: number,
	accentColor: Color3,
	onChanged: (number) -> ()
): (number) -> ()
	-- Inset by half the handle's width on each side so the handle sits
	-- fully inside the holder even at the extremes.
	local track = UiBuilder.create("Frame", {
		Name = "SliderTrack",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, -24, 0, 10),
		BackgroundColor3 = Color3.fromRGB(72, 84, 96),
		BorderSizePixel = 0,
		Parent = parent,
	})
	UiBuilder.round(track, 5)

	local fill = UiBuilder.create("Frame", {
		Name = "SliderFill",
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = accentColor,
		BorderSizePixel = 0,
		Parent = track,
	})
	UiBuilder.round(fill, 5)

	local handle = UiBuilder.create("TextButton", {
		Name = "SliderHandle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 22, 0, 22),
		BackgroundColor3 = Color3.fromRGB(245, 246, 250),
		BorderSizePixel = 0,
		Text = "",
		Parent = track,
	})
	UiBuilder.round(handle, 11)
	UiBuilder.stroke(handle, accentColor, 2)

	local function fractionToValue(fraction: number): number
		return minimum + (maximum - minimum) * math.clamp(fraction, 0, 1)
	end

	local function moveTo(value: number)
		local fraction = (value - minimum) / (maximum - minimum)
		fraction = math.clamp(fraction, 0, 1)
		handle.Position = UDim2.new(fraction, 0, 0.5, 0)
		fill.Size = UDim2.new(fraction, 0, 1, 0)
	end

	local dragging = false

	local function updateFromInput(inputPosition: Vector2)
		local fraction = (inputPosition.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
		local value = fractionToValue(fraction)
		moveTo(value)
		onChanged(value)
	end

	handle.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			updateFromInput(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			updateFromInput(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)

	moveTo(initial)

	return moveTo
end

return UiBuilder
