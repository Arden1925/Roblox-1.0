--[[
	Shared UI toolkit: instance building plus the handful of effects that
	give every window in the game the same feel -- gradients, hover pops,
	springy open animations, pulsing glows, and a draggable slider. One
	implementation here keeps ten GUIs consistent.
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local HOVER_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
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

-- Grows a button slightly under the cursor. UIScale means the button's
-- own Size (and any layout using it) is never disturbed.
function UiBuilder.hoverPop(button: GuiButton)
	local scale = UiBuilder.create("UIScale", {
		Scale = 1,
		Parent = button,
	}) :: UIScale

	button.MouseEnter:Connect(function()
		TweenService:Create(scale, HOVER_INFO, { Scale = 1.06 }):Play()
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(scale, HOVER_INFO, { Scale = 1 }):Play()
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
	local track = UiBuilder.create("Frame", {
		Name = "SliderTrack",
		Size = UDim2.new(1, 0, 0, 10),
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
