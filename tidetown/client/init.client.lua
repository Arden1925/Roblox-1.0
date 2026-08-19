--[[
	Tidetown client entry point. Starts every controller from a spawned
	task because several of them wait for replicated instances
	(PlayerGui, TidetownShared, remotes) and startup must never block
	the main task. LoadingGui goes first so its cover is up before
	anything streams in.
]]

local Client = script
local BountyGui = require(Client.BountyGui)
local CameraFx = require(Client.CameraFx)
local CatchController = require(Client.CatchController)
local EggGui = require(Client.EggGui)
local HudGui = require(Client.HudGui)
local LoadingGui = require(Client.LoadingGui)
local MountController = require(Client.MountController)
local ReefGui = require(Client.ReefGui)
local SettingsGui = require(Client.SettingsGui)
local ShopGui = require(Client.ShopGui)
local SoundController = require(Client.SoundController)
local SurgeGui = require(Client.SurgeGui)
local SwimController = require(Client.SwimController)
local TeamGui = require(Client.TeamGui)
local TideController = require(Client.TideController)
local TidepediaGui = require(Client.TidepediaGui)
local Toast = require(Client.Toast)
local TutorialGui = require(Client.TutorialGui)

task.spawn(LoadingGui.start)
task.spawn(Toast.start)
task.spawn(CameraFx.start)
task.spawn(HudGui.start)
task.spawn(TideController.start)
task.spawn(SwimController.start)
task.spawn(CatchController.start)
task.spawn(EggGui.start)
task.spawn(TeamGui.start)
task.spawn(ShopGui.start)
task.spawn(SettingsGui.start)
task.spawn(SoundController.start)
task.spawn(TidepediaGui.start)
task.spawn(BountyGui.start)
task.spawn(ReefGui.start)
task.spawn(SurgeGui.start)
task.spawn(MountController.start)
task.spawn(TutorialGui.start)
