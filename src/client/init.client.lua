--[[
	Client entry point. Grows into the game's client-side bootstrapping (UI,
	input, camera) as systems are added; for now it only proves the Rojo
	sync and the shared modules are wired up correctly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- WaitForChild instead of a direct index: on the client, replicated
-- instances may not have arrived yet when this script first runs.
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GamePhase = require(Shared:WaitForChild("GamePhase"))

print("Client started in phase:", GamePhase.Lobby)
