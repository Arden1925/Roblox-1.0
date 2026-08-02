--[[
	The phases a round moves through, in order. Reading a member that does
	not exist throws instead of silently returning nil, following the
	"Guarding against typos" pattern in STYLE_GUIDE.md.
]]

local GamePhase = {
	Lobby = "Lobby",
	Intermission = "Intermission",
	Playing = "Playing",
	Results = "Results",
}

setmetatable(GamePhase, {
	__index = function(_, key)
		error(string.format("%q is not a valid member of GamePhase", tostring(key)), 2)
	end,
})

return GamePhase
