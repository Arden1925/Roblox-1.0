--[[
	Server entry point. Grows into the game's server-side bootstrapping as
	systems are added; for now it only proves the Rojo sync and the shared
	modules are wired up correctly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GamePhase = require(Shared.GamePhase)

print("Server started in phase:", GamePhase.Lobby)
