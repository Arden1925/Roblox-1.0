--[[
	Client entry point. Starts every controller from a spawned task
	because several of them wait for replicated instances (PlayerGui,
	Shared, remotes) and startup must never block the main task.
	LoadingGui goes first so its cover is up before anything streams in.
]]

local Client = script
local BackpackGui = require(Client.BackpackGui)
local CodesGui = require(Client.CodesGui)
local CurrencyHud = require(Client.CurrencyHud)
local EffectsController = require(Client.EffectsController)
local EggGui = require(Client.EggGui)
local EnvironmentController = require(Client.EnvironmentController)
local GatePrompt = require(Client.GatePrompt)
local LoadingGui = require(Client.LoadingGui)
local PortalFx = require(Client.PortalFx)
local PortalGui = require(Client.PortalGui)
local QuestGui = require(Client.QuestGui)
local RebirthGui = require(Client.RebirthGui)
local SettingsGui = require(Client.SettingsGui)
local ShopGui = require(Client.ShopGui)
local SizeHud = require(Client.SizeHud)
local SizeSpeedControls = require(Client.SizeSpeedControls)
local SoundController = require(Client.SoundController)
local StationGui = require(Client.StationGui)
local TutorialGui = require(Client.TutorialGui)
local WheelGui = require(Client.WheelGui)

task.spawn(LoadingGui.start)
task.spawn(SoundController.start)
task.spawn(SizeHud.start)
task.spawn(CurrencyHud.start)
task.spawn(GatePrompt.start)
task.spawn(RebirthGui.start)
task.spawn(QuestGui.start)
task.spawn(WheelGui.start)
task.spawn(SettingsGui.start)
task.spawn(ShopGui.start)
task.spawn(BackpackGui.start)
task.spawn(CodesGui.start)
task.spawn(EggGui.start)
task.spawn(StationGui.start)
task.spawn(PortalGui.start)
task.spawn(SizeSpeedControls.start)
task.spawn(TutorialGui.start)
task.spawn(EffectsController.start)
task.spawn(PortalFx.start)
task.spawn(EnvironmentController.start)
