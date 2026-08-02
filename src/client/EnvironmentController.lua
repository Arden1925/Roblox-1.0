--[[
	Gives each world its own sky, seen only by the player standing in it:
	Lighting changed from a LocalScript never replicates, so everyone
	gets the sky of wherever they are. Palettes tween over a couple of
	seconds so crossing a wall feels like walking into new weather.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local TRANSITION_INFO = TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- One palette per world, indexed to match GameConfig.worlds.
local WORLD_PALETTES = {
	{
		clockTime = 13.5,
		atmosphereColor = Color3.fromRGB(199, 214, 199),
		atmosphereDecay = Color3.fromRGB(255, 220, 130),
		haze = 1.2,
		density = 0.26,
		outdoorAmbient = Color3.fromRGB(150, 160, 140),
	},
	{
		clockTime = 10,
		atmosphereColor = Color3.fromRGB(180, 190, 205),
		atmosphereDecay = Color3.fromRGB(140, 160, 185),
		haze = 2.4,
		density = 0.38,
		outdoorAmbient = Color3.fromRGB(130, 140, 155),
	},
	{
		clockTime = 17.6,
		atmosphereColor = Color3.fromRGB(215, 170, 155),
		atmosphereDecay = Color3.fromRGB(255, 110, 40),
		haze = 2.8,
		density = 0.42,
		outdoorAmbient = Color3.fromRGB(170, 120, 100),
	},
	{
		clockTime = 12,
		atmosphereColor = Color3.fromRGB(205, 225, 255),
		atmosphereDecay = Color3.fromRGB(255, 245, 220),
		haze = 0.8,
		density = 0.18,
		outdoorAmbient = Color3.fromRGB(180, 195, 215),
	},
}

local localPlayer = Players.LocalPlayer

local EnvironmentController = {}

local function applyPalette(worldIndex: number)
	local palette = WORLD_PALETTES[worldIndex]
	if palette == nil then
		return
	end

	TweenService:Create(Lighting, TRANSITION_INFO, {
		ClockTime = palette.clockTime,
		OutdoorAmbient = palette.outdoorAmbient,
	}):Play()

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere ~= nil then
		TweenService:Create(atmosphere, TRANSITION_INFO, {
			Color = palette.atmosphereColor,
			Decay = palette.atmosphereDecay,
			Haze = palette.haze,
			Density = palette.density,
		}):Play()
	end
end

function EnvironmentController.start()
	localPlayer:GetAttributeChangedSignal("CurrentWorld"):Connect(function()
		local worldIndex = localPlayer:GetAttribute("CurrentWorld")
		if typeof(worldIndex) == "number" then
			applyPalette(worldIndex)
		end
	end)

	local worldIndex = localPlayer:GetAttribute("CurrentWorld")
	if typeof(worldIndex) == "number" then
		applyPalette(worldIndex)
	end
end

return EnvironmentController
