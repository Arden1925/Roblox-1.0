--[[
	Client entry point. Starts every controller from a spawned task
	because several of them wait for replicated instances (PlayerGui,
	Shared, remotes) and startup must never block the main task.
]]

local Client = script
local BackpackGui = require(Client.BackpackGui)
local CurrencyHud = require(Client.CurrencyHud)
local EffectsController = require(Client.EffectsController)
local EggGui = require(Client.EggGui)
local GatePrompt = require(Client.GatePrompt)
local PortalGui = require(Client.PortalGui)
local ShopGui = require(Client.ShopGui)
local SizeHud = require(Client.SizeHud)
local SizeSpeedControls = require(Client.SizeSpeedControls)
local StationGui = require(Client.StationGui)
local TutorialGui = require(Client.TutorialGui)

task.spawn(SizeHud.start)
task.spawn(CurrencyHud.start)
task.spawn(GatePrompt.start)
task.spawn(ShopGui.start)
task.spawn(BackpackGui.start)
task.spawn(EggGui.start)
task.spawn(StationGui.start)
task.spawn(PortalGui.start)
task.spawn(SizeSpeedControls.start)
task.spawn(TutorialGui.start)
task.spawn(EffectsController.start)
