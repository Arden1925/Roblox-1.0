--[[
	Validates and executes rebirths: trading all Max Size for a permanent
	growth multiplier. Validation lives here on the server because the
	client's rebirth button is a request, never a command.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent
local ShopService = require(Server.ShopService)
local SizeService = require(Server.SizeService)

local Shared = ReplicatedStorage.Shared
local SizeFormula = require(Shared.SizeFormula)

local RebirthService = {}

--[[
	Wired as AttemptRebirth.OnServerInvoke. Returns success plus a message
	the client shows verbatim, so all rebirth wording lives server-side.
]]
function RebirthService.attemptRebirth(player: Player): (boolean, string)
	local state = SizeService.getState(player)
	if state == nil then
		return false, "Your data is still loading -- try again in a moment."
	end

	local requiredSize = SizeFormula.requiredSizeForRebirth(state.rebirths)
	if state.maxSize < requiredSize then
		return false,
			string.format(
				"You need %d Max Size to rebirth (you have %d).",
				requiredSize,
				math.floor(state.maxSize)
			)
	end

	-- Capture the new count before applyRebirth mutates the live state
	-- table that getState returned.
	local newRebirths = state.rebirths + 1
	SizeService.applyRebirth(player)

	local newMultiplier = SizeFormula.growthMultiplier(newRebirths, {
		doubleRebirthBonus = ShopService.playerOwnsPass(player, "DoubleRebirthBonus"),
	})

	return true, string.format("Reborn! You now grow x%.1f as fast. Forever.", newMultiplier)
end

return RebirthService
