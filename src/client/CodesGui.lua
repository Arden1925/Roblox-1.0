--[[
	The codes window: type a promo code, hit REDEEM, and the server hands
	out the reward. The side button and the window both wear a chunky
	cartoon bird built from rounded frames -- a wink at the little blue
	bird players follow for new codes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent
local Toast = require(Client.Toast)
local UiBuilder = require(Client.UiBuilder)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local PANEL_COLOR = Color3.fromRGB(24, 30, 38)
local BIRD_BLUE = Color3.fromRGB(74, 168, 224)
local BELLY_WHITE = Color3.fromRGB(255, 255, 255)
local BEAK_GOLD = Color3.fromRGB(247, 181, 56)
local EYE_NAVY = Color3.fromRGB(31, 41, 74)
-- A pale sky button so the sky-blue bird stays visible on top of it.
local BUTTON_COLOR = Color3.fromRGB(236, 246, 255)
local REDEEM_GREEN = Color3.fromRGB(76, 209, 55)
local PLACEHOLDER_BLUE = Color3.fromRGB(214, 234, 248)
local HINT_GRAY = Color3.fromRGB(148, 163, 184)

local WINDOW_WIDTH = 380
local WINDOW_HEIGHT = 240

-- ShopGui's ButtonColumn sits at x = 12, anchored to the screen's
-- vertical center, and lays its buttons out as a 2-wide grid of 64x80
-- cells with 6px row gaps, vertically centered in a 260px column. A
-- full grid (six buttons) therefore ends 126px below center, so this
-- holder hangs at center + 132 to line up under the left column with
-- the same row gap and no overlap -- clear of the backpack button
-- pinned to the bottom-left corner.
local SIDE_BUTTON_X = 12
local SIDE_BUTTON_Y_FROM_CENTER = 132

local localPlayer = Players.LocalPlayer

local CodesGui = {}

--[[
	One rounded body part for the bird. Everything is sized in scale
	units so the same drawing works at button size and window size, which
	is also why the corner radius is scale-based -- UiBuilder.round is
	pixel-based and would not shrink with the part.
]]
local function addBirdPart(
	bird: Frame,
	name: string,
	x: number,
	y: number,
	width: number,
	height: number,
	color: Color3,
	zIndex: number
): Frame
	local part = UiBuilder.create("Frame", {
		Name = name,
		Position = UDim2.new(x, 0, y, 0),
		Size = UDim2.new(width, 0, height, 0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = zIndex,
		Parent = bird,
	}) :: Frame

	UiBuilder.create("UICorner", {
		CornerRadius = UDim.new(0.5, 0),
		Parent = part,
	})

	return part
end

--[[
	Draws the little blue bird inside a square container: an ellipse-ish
	body, a round head overlapping its top-right, a white belly, a gold
	beak, and a navy eye. Returns the container so callers can place one
	bird on the side button and a bigger one in the window.
]]
local function buildBird(parent: GuiObject, position: UDim2, size: UDim2): Frame
	local bird = UiBuilder.create("Frame", {
		Name = "Bird",
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = parent,
	}) :: Frame

	addBirdPart(bird, "Body", 0.02, 0.34, 0.66, 0.5, BIRD_BLUE, 2)

	-- The beak: a gold square rotated 45 degrees so one corner points
	-- forward; the head is drawn after it to hide the square's base.
	local beak = UiBuilder.create("Frame", {
		Name = "Beak",
		Position = UDim2.new(0.8, 0, 0.19, 0),
		Size = UDim2.new(0.16, 0, 0.16, 0),
		Rotation = 45,
		BackgroundColor3 = BEAK_GOLD,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = bird,
	})
	UiBuilder.create("UICorner", {
		CornerRadius = UDim.new(0.2, 0),
		Parent = beak,
	})

	addBirdPart(bird, "Head", 0.42, 0.06, 0.44, 0.44, BIRD_BLUE, 4)
	addBirdPart(bird, "Belly", 0.28, 0.58, 0.26, 0.2, BELLY_WHITE, 4)
	addBirdPart(bird, "Eye", 0.68, 0.17, 0.1, 0.1, EYE_NAVY, 5)

	return bird
end

function CodesGui.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = UiBuilder.create("ScreenGui", {
		Name = "CodesGui",
		ResetOnSpawn = false,
		DisplayOrder = 7,
		Parent = playerGui,
	})

	local window = UiBuilder.create("Frame", {
		Name = "CodesWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, WINDOW_WIDTH, 0, WINDOW_HEIGHT),
		BackgroundColor3 = PANEL_COLOR,
		BorderSizePixel = 0,
		Visible = false,
		Parent = screenGui,
	}) :: Frame
	UiBuilder.round(window, 16)
	UiBuilder.stroke(window, BIRD_BLUE, 2)

	local closeButton = UiBuilder.create("TextButton", {
		Name = "CloseButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.new(0, 34, 0, 34),
		BackgroundColor3 = Color3.fromRGB(235, 69, 44),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "X",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 18,
		ZIndex = 2,
		Parent = window,
	}) :: TextButton
	UiBuilder.round(closeButton, 8)
	UiBuilder.hoverPop(closeButton)

	closeButton.Activated:Connect(function()
		window.Visible = false
	end)

	buildBird(window, UDim2.new(0, 22, 0, 62), UDim2.new(0, 116, 0, 116))

	local codeBox = UiBuilder.create("TextBox", {
		Name = "CodeBox",
		Position = UDim2.new(0, 152, 0, 64),
		Size = UDim2.new(0, 204, 0, 44),
		BackgroundColor3 = BIRD_BLUE,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.GothamBold,
		PlaceholderColor3 = PLACEHOLDER_BLUE,
		PlaceholderText = "TYPE CODE...",
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 18,
		Parent = window,
	}) :: TextBox
	UiBuilder.round(codeBox, 10)

	-- Codes are matched uppercase server-side; folding as the player
	-- types makes "sizeboost" and "SizeBoost" both redeem. The guard
	-- keeps the assignment from refiring this signal forever.
	codeBox:GetPropertyChangedSignal("Text"):Connect(function()
		local uppercased = string.upper(codeBox.Text)
		if codeBox.Text ~= uppercased then
			codeBox.Text = uppercased
		end
	end)

	local redeemButton = UiBuilder.create("TextButton", {
		Name = "RedeemButton",
		Position = UDim2.new(0, 152, 0, 120),
		Size = UDim2.new(0, 204, 0, 44),
		BackgroundColor3 = REDEEM_GREEN,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		Text = "REDEEM",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 18,
		Parent = window,
	}) :: TextButton
	UiBuilder.round(redeemButton, 10)
	UiBuilder.hoverPop(redeemButton)

	redeemButton.Activated:Connect(function()
		task.spawn(function()
			local redeemCode = Remotes.get("RedeemCode") :: RemoteFunction

			-- InvokeServer throws if the server errors mid-call.
			local invoked, success, message = pcall(function()
				return redeemCode:InvokeServer(codeBox.Text)
			end)

			Toast.show(if invoked then message else "Something went wrong -- try again.")

			-- A redeemed code deserves a little celebration: clear the
			-- box and bounce the window.
			if invoked and success == true then
				codeBox.Text = ""
				UiBuilder.popOpen(window)
			end
		end)
	end)

	UiBuilder.create("TextLabel", {
		Name = "HintLabel",
		Position = UDim2.new(0, 24, 0, 188),
		Size = UDim2.new(1, -48, 0, 30),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "Follow us for new codes!",
		TextColor3 = HINT_GRAY,
		TextSize = 14,
		TextWrapped = true,
		Parent = window,
	})

	UiBuilder.cartoonizeWindow(window, BIRD_BLUE, "CODES")

	local buttonHolder = UiBuilder.create("Frame", {
		Name = "CodesButtonHolder",
		Position = UDim2.new(0, SIDE_BUTTON_X, 0.5, SIDE_BUTTON_Y_FROM_CENTER),
		Size = UDim2.new(0, 64, 0, 80),
		BackgroundTransparency = 1,
		Parent = screenGui,
	})

	-- An empty icon keeps the button's centered-emoji plumbing out of
	-- the way; the bird frames layer on top instead.
	local codesButton = UiBuilder.iconButton(buttonHolder, 1, "", "Codes", BUTTON_COLOR)
	buildBird(codesButton, UDim2.new(0, 7, 0, 7), UDim2.new(1, -14, 1, -14))
	UiBuilder.cartoonify(buttonHolder)

	CodesGui.toggle = function()
		if window.Visible then
			window.Visible = false
		else
			UiBuilder.popOpen(window)
		end
	end

	codesButton.Activated:Connect(function()
		CodesGui.toggle()
	end)
end

-- Replaced at start(); declared so other screens can wire a shortcut.
CodesGui.toggle = function() end

return CodesGui
