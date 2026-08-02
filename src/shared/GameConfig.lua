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

	obstacles = {
		-- Touching a Hazard drops Current Size (never Max Size), at most
		-- once per debounce window.
		hazardDebounceSeconds = 1,
		-- FadingPlatform: time from first touch to vanishing, then time
		-- until it comes back.
		fadeDelaySeconds = 0.8,
		fadeRespawnSeconds = 3,
		bounceVelocity = 90,
	},

	passEffects = {
		-- AutoGrow earns this fraction of pad growth while off pads.
		autoGrowFraction = 0.25,
		-- SuperSqueeze (and the Slick Coating item) lets you fit cracks
		-- up to this multiple of their MaxAllowedSize.
		superSqueezeAllowance = 1.6,
		vipGrowthBonus = 0.25,
		cloudBootsJumpBonus = 0.5,
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
		{
			key = "AutoGrow",
			name = "Auto-Grow",
			description = "Keep growing slowly even when you are off the pads.",
			robuxPrice = 199,
			gamePassId = 0,
		},
		{
			key = "SuperSqueeze",
			name = "Super Squeeze",
			description = "Fit through cracks one size tier tighter than anyone else.",
			robuxPrice = 249,
			gamePassId = 0,
		},
		{
			key = "Vip",
			name = "VIP",
			description = "A golden trail that grows with you, plus +25% growth.",
			robuxPrice = 299,
			gamePassId = 0,
		},
		{
			key = "DoubleRebirthBonus",
			name = "2x Rebirth Bonus",
			description = "Every rebirth grants double its usual growth multiplier.",
			robuxPrice = 399,
			gamePassId = 0,
		},
	},

	-- One world per square platform, in walk order. exitWallHeight is the
	-- climbable wall to the NEXT world, so the last world has none.
	-- cityProduct is that world's Robux item, buyable only while inside
	-- the world; paste real developer product IDs over the zeros.
	worlds = {
		{
			name = "Sprout Meadows",
			floorColor = { 126, 214, 87 },
			exitWallHeight = 14,
			exitStepCount = 3,
			cityProduct = {
				key = "MeadowSurge",
				name = "Meadow Surge",
				description = "Instantly gain +300 Max Size.",
				robuxPrice = 45,
				productId = 0,
				effect = "instantSize",
				amount = 300,
			},
		},
		{
			name = "Vent City",
			floorColor = { 149, 175, 192 },
			exitWallHeight = 22,
			exitStepCount = 3,
			cityProduct = {
				key = "SlickCoating",
				name = "Slick Coating",
				description = "Squeeze through any crack for 5 minutes.",
				robuxPrice = 55,
				productId = 0,
				effect = "timed",
				effectKey = "VentGrease",
				durationSeconds = 300,
			},
		},
		{
			name = "Ember Foundry",
			floorColor = { 214, 108, 76 },
			exitWallHeight = 32,
			exitStepCount = 2,
			cityProduct = {
				key = "EmberShield",
				name = "Ember Shield",
				description = "Hazards cannot shrink you for 5 minutes.",
				robuxPrice = 65,
				productId = 0,
				effect = "timed",
				effectKey = "EmberShield",
				durationSeconds = 300,
			},
		},
		{
			name = "Cloud Capital",
			floorColor = { 190, 210, 255 },
			cityProduct = {
				key = "CloudBoots",
				name = "Cloud Boots",
				description = "Jump 50% higher for 5 minutes.",
				robuxPrice = 75,
				productId = 0,
				effect = "timed",
				effectKey = "CloudBoots",
				durationSeconds = 300,
			},
		},
	},
}

return GameConfig
