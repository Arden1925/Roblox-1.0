--[[
	The phases the tide moves through, in cycle order. Reading a member
	that does not exist throws instead of silently returning nil,
	following the "Guarding against typos" pattern in STYLE_GUIDE.md.
]]

local TidePhase = {
	Low = "Low",
	Rising = "Rising",
	High = "High",
	Falling = "Falling",
}

setmetatable(TidePhase, {
	__index = function(_, key)
		error(string.format("%q is not a valid member of TidePhase", tostring(key)), 2)
	end,
})

return TidePhase
