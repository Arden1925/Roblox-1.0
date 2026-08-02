--[[
	Every tunable number in the game lives here so balancing is a matter of
	editing one file. Systems read from this table and never hardcode
	gameplay values.
]]

local GameConfig = {
	growth = {
		-- How often the server grants growth and updates bodies. Smaller
		-- feels smoother but costs more server work.
		tickSeconds = 0.25,
		sizePerTick = 1,
		-- How quickly Current Size climbs back to Max Size after shrinking.
		-- This is the "vulnerability window" that makes shrinking a real
		-- decision, so keep it slow enough to matter.
		regrowPerSecond = 6,
	},

	shrink = {
		-- Current Size a Shrink Pad pulls you down to, and how fast.
		shrunkSize = 10,
		shrinkPerSecond = 80,
	},

	scale = {
		-- Character scale is a saturating curve so early growth is
		-- dramatic and huge sizes cannot break physics.
		minimum = 0.45,
		maximum = 6,
		-- Size at which a character reaches half of the scale range.
		halfwaySize = 200,
	},

	rebirth = {
		-- First rebirth needs this Max Size; each later rebirth needs one
		-- more multiple of it.
		baseRequiredSize = 250,
		-- Permanent growth bonus per rebirth (0.5 = +50% each).
		multiplierPerRebirth = 0.5,
	},

	gates = {
		-- How close a qualifying player must be before a gate or crack
		-- opens, and how long it stays open after they leave.
		openRange = 16,
		closeDelaySeconds = 1,
	},

	data = {
		storeName = "PlayerData_v1",
		autosaveSeconds = 120,
		loadAttempts = 3,
		retryBaseSeconds = 2,
	},

	-- Paste real game pass IDs here after creating the passes on the
	-- Roblox website (Creator Hub -> your experience -> Monetization).
	-- Entries with gamePassId = 0 appear in the shop as "coming soon".
	passes = {
		{
			key = "DoubleGrowth",
			name = "2x Growth",
			description = "Permanently grow twice as fast on every pad.",
			robuxPrice = 99,
			gamePassId = 0,
		},
		{
			key = "InstantShrink",
			name = "Instant Shrink",
			description = "Shrink on demand with a button, anywhere.",
			robuxPrice = 149,
			gamePassId = 0,
		},
	},
}

return GameConfig
