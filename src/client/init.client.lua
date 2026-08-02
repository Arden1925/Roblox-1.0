--[[
	Client entry point. Starts every controller from a spawned task
	because several of them wait for replicated instances (PlayerGui,
	Shared, remotes) and startup must never block the main task.
]]

local Client = script
local EffectsController = require(Client.EffectsController)
local GatePrompt = require(Client.GatePrompt)
local PortalGui = require(Client.PortalGui)
local ShopGui = require(Client.ShopGui)
local SizeHud = require(Client.SizeHud)

task.spawn(SizeHud.start)
task.spawn(GatePrompt.start)
task.spawn(ShopGui.start)
task.spawn(PortalGui.start)
task.spawn(EffectsController.start)
