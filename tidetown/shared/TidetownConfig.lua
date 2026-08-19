--[[
	Every tunable number in Tidetown lives here so balancing is a matter
	of editing one file. Systems read from this table and never hardcode
	gameplay values.

	The two structural balance rules the numbers below implement:

	1. Disjoint currencies: Shells are time-earned (catching, reef,
	   salvage) and buy eggs, reef, and cosmetics. Stormglass is
	   skill-earned (cleared surge waves, deep catches) and buys mounts
	   and surge gear -- things Shells can never touch.
	2. RNG decides WHICH creature, never how strong: all species sit in
	   a narrow power band as role side-grades.
]]

local TidetownConfig = {
	-- The tide clock, in seconds per phase. One full cycle is exactly
	-- seven minutes; Rising and Falling are the wave-wall transitions
	-- that visually mask streaming work.
	tide = {
		lowSeconds = 240,
		risingSeconds = 18,
		highSeconds = 150,
		fallingSeconds = 12,
		-- Water surface heights, in world Y. Low leaves the flats (top
		-- Y = 0) exposed; high floods the town ground (Y = 2) to the
		-- waist but never reaches the pier deck (Y = 7).
		lowWaterY = -2.5,
		highWaterY = 4.5,
		-- The siren sounds this long before the water starts rising.
		sirenLeadSeconds = 10,
	},

	-- World layout, all in studs. The sea lies at negative X and the
	-- town inland at positive X; Z is the shoreline width. Zone bounds
	-- are closed on min and open on max.
	layout = {
		shoreWidth = 360,
		zones = {
			{ key = "DeepReef", name = "Deep Reef", minX = -720, maxX = -460, floorY = -12 },
			{ key = "Cave", name = "Glowcave Shallows", minX = -460, maxX = -240, floorY = 0 },
			{ key = "Beach", name = "Tidepool Flats", minX = -240, maxX = -30, floorY = 0 },
			{ key = "Town", name = "Old Tidetown", minX = 90, maxX = 420, floorY = 2 },
		},
		beachSand = { minX = -30, maxX = 40, topY = 3 },
		boardwalk = { minX = 40, maxX = 90, deckY = 7 },
		townGroundY = 2,
		-- Reef plots line the seaward edge of the boardwalk, one pad
		-- per player slot, spaced along Z.
		reefPlotCount = 8,
		reefPlotSpacing = 40,
		reefPlotX = 46,
		spawnPosition = { x = 60, y = 8, z = 0 },
	},

	-- The cast minigame. The server issues a randomized ring per cast
	-- (so autoclickers cannot memorize a rhythm) and judges the tap by
	-- its own clock, never the client's.
	catch = {
		castCooldownSeconds = 0.8,
		ringSecondsMinimum = 1.1,
		ringSecondsMaximum = 1.6,
		perfectAtMinimum = 0.55,
		perfectAtMaximum = 0.85,
		perfectWindowFraction = 0.07,
		goodWindowFraction = 0.24,
		-- Grace added to the server-side judgment to absorb network
		-- latency; generous for Good, tight for Perfect.
		latencyGraceFraction = 0.05,
		-- Rarity weights by quality. Perfect is strictly better -- the
		-- promise that skill visibly bends luck.
		rarityWeightsGood = { common = 70, rare = 24, epic = 5.5, legendary = 0.5 },
		rarityWeightsPerfect = { common = 40, rare = 38, epic = 17, legendary = 5 },
		-- Soft pity, persisted per player: after this many casts
		-- without the named rarity (or better), the next catch is
		-- floored to it.
		pityRareCasts = 10,
		pityEpicCasts = 40,
		-- Shell payout per catch: base by rarity, scaled by zone.
		shellsByRarity = { common = 6, rare = 14, epic = 40, legendary = 120 },
		zoneShellMultipliers = { Beach = 1, Town = 1.6, Cave = 2.4, DeepReef = 3.5 },
		perfectShellMultiplier = 1.5,
		missConsolationShells = 2,
		-- A successful catch sometimes uncovers a buried egg for the
		-- zone instead of paying bonus shells.
		eggFindChance = 0.03,
	},

	-- Eggs charge from successful catches instead of real-time timers:
	-- playing IS the incubation. Odds are published in the shop UI.
	eggs = {
		maxHeld = 3,
		types = {
			{
				key = "beachEgg",
				name = "Tidepool Egg",
				zone = "Beach",
				shellCost = 120,
				catchesToHatch = 5,
				modelName = "Rare Egg",
				rarityWeights = { common = 62, rare = 32, epic = 6, legendary = 0 },
			},
			{
				key = "townEgg",
				name = "Harbor Egg",
				zone = "Town",
				shellCost = 320,
				catchesToHatch = 8,
				modelName = "Epic Egg",
				rarityWeights = { common = 48, rare = 38, epic = 12.5, legendary = 1.5 },
			},
			{
				key = "caveEgg",
				name = "Glowcave Egg",
				zone = "Cave",
				shellCost = 750,
				catchesToHatch = 12,
				modelName = "Exclusive Egg",
				rarityWeights = { common = 35, rare = 40, epic = 20, legendary = 5 },
			},
			{
				key = "deepEgg",
				name = "Abyssal Egg",
				zone = "DeepReef",
				shellCost = 1600,
				catchesToHatch = 16,
				modelName = "Celestial Axolotl Egg",
				rarityWeights = { common = 0, rare = 35, epic = 45, legendary = 20 },
			},
		},
	},

	-- Creature power: one narrow band, so every species is a side-grade
	-- and collecting is about roles and looks, never raw power.
	creatures = {
		rarityMultipliers = { common = 1, rare = 1.12, epic = 1.25, legendary = 1.4 },
		rarityColors = {
			common = { 176, 190, 197 },
			rare = { 77, 171, 247 },
			epic = { 171, 71, 188 },
			legendary = { 255, 179, 0 },
		},
		-- Base stats per defense role, multiplied by the rarity band.
		roles = {
			Anchor = {
				barrierArmorPercent = 8,
				selfDamagePerSecond = 2,
				description = "Shields the barrier",
			},
			Sprayer = {
				damagePerSecond = 6,
				rangeStuds = 26,
				description = "Shoots the farthest foe",
			},
			Herder = { slowFraction = 0.3, radiusStuds = 14, description = "Slows everything near" },
			Sparker = {
				burstDamage = 26,
				radiusStuds = 12,
				chargeSeconds = 7,
				description = "Tap to detonate",
			},
		},
		-- Placing creatures with DIFFERENT roles links them: each
		-- distinct-role pair adds this bonus to every linked stat. The
		-- bonus is explicit and positively framed (glowing lines in the
		-- UI), never a hidden same-role penalty.
		linkBonusPerPairPercent = 8,
		followerHeightStuds = 2,
		defenseTeamSize = 3,
	},

	-- The high-tide surge: per-player enemy lanes aimed at each keeper's
	-- own reef plot, scaled to that keeper's rank, so newbies and
	-- veterans share a server without sharing a difficulty curve.
	surge = {
		waveCount = 4,
		enemiesBaseCount = 4,
		enemiesPerWave = 1,
		enemyBaseHealth = 18,
		enemyHealthPerWave = 6,
		enemyHealthPerRankPercent = 5,
		enemySpeedStudsPerSecond = 6,
		enemyBountyShells = 6,
		enemyBountyPerWave = 2,
		-- The feral wave skins, weakest first; the model is tinted dark
		-- so ferals never read as catchable creatures.
		enemySpeciesByWave = { "crab", "crab", "tigerfish", "skeletalShark" },
		barrierBaseHealth = 100,
		secondsBetweenWaves = 8,
		-- Stormglass per cleared wave; full engagement (at least one
		-- landed deflect or Sparker trigger) is required for the full
		-- amount, otherwise half -- winning while AFK pays a different,
		-- smaller number.
		stormglassByWave = { 2, 2, 3, 4 },
		disengagedStormglassFraction = 0.5,
		-- Uncleared enemies convert to salvage piles worth this fraction
		-- of their bounty: failure pays out in kind, never punishes.
		salvageFraction = 0.4,
		deflect = {
			cooldownSeconds = 3,
			radiusStuds = 14,
			damage = 10,
			knockbackStuds = 8,
		},
	},

	-- The reef plot: a persistent, publicly visible aquarium that pays
	-- capped passive Shells. Offline accrual is deliberately under a
	-- third of the active rate.
	reef = {
		startingSlots = 2,
		maxSlots = 6,
		slotUpgradeCosts = { 150, 400, 900, 1800 },
		shellsPerMinuteByRarity = { common = 1.2, rare = 2, epic = 3.2, legendary = 5 },
		offlineRateFraction = 0.3,
		offlineCapHours = 8,
		poolCap = 4000,
	},

	-- Tidepedia: every first catch is a permanent record. Buffs are
	-- hard-capped; past the cap new entries pay decor pride, not power.
	tidepedia = {
		buffPerEntryPercent = 0.5,
		aggregateCapPercent = 12,
		entriesPerKeeperRank = 3,
		-- Zone gates: casting in a zone needs this many total entries.
		-- The Deep Reef also needs a mount to physically reach.
		zoneEntryGates = { Beach = 0, Town = 6, Cave = 12, DeepReef = 18 },
	},

	-- Mounts: the loaner tube means every player surfs their very first
	-- flood; owned mounts add speed and the deep-only catch access.
	mounts = {
		loaner = {
			key = "loanerTube",
			name = "Pier Inner Tube",
			speedStudsPerSecond = 24,
			deepAccess = false,
		},
		owned = {
			{
				key = "belugaCruiser",
				name = "Beluga Cruiser",
				modelName = "Beluga Whale",
				stormglassCost = 25,
				speedStudsPerSecond = 34,
				deepAccess = true,
			},
			{
				key = "ancientSovereign",
				name = "Ancient Sovereign",
				modelName = "Ancient Whale",
				stormglassCost = 90,
				speedStudsPerSecond = 40,
				deepAccess = true,
			},
		},
		turnDegreesPerSecond = 90,
		mountHeightStuds = 4,
	},

	-- Shop stock beyond eggs and mounts. kind picks the purchase
	-- handler; maxLevel marks ladder upgrades.
	shop = {
		upgrades = {
			{
				key = "barrierPlating",
				name = "Barrier Plating",
				description = "The boardwalk barrier takes +25 health per level.",
				currency = "stormglass",
				costs = { 6, 12, 20 },
				healthPerLevel = 25,
			},
			{
				key = "deflectCharm",
				name = "Deflect Charm",
				description = "Your deflect recharges half a second faster per level.",
				currency = "stormglass",
				costs = { 8, 16 },
				cooldownCutSeconds = 0.5,
			},
		},
		decorations = {
			{ key = "kelpGarden", name = "Kelp Garden", shellCost = 200 },
			{ key = "coralArch", name = "Coral Arch", shellCost = 450 },
			{ key = "sunkenLantern", name = "Sunken Lantern", shellCost = 800 },
		},
		trails = {
			{
				key = "seafoamTrail",
				name = "Seafoam Trail",
				shellCost = 300,
				color = { 178, 235, 242 },
			},
			{
				key = "sunsetTrail",
				name = "Sunset Trail",
				shellCost = 300,
				color = { 255, 171, 145 },
			},
			{ key = "inkTrail", name = "Ink Trail", shellCost = 550, color = { 69, 90, 100 } },
			{
				key = "starlightTrail",
				name = "Starlight Trail",
				shellCost = 900,
				color = { 255, 245, 157 },
			},
		},
	},

	-- Daily bounties: three rolled per day from these templates. The
	-- streak counts days with at least one claim and PAUSES on a missed
	-- day -- absence is un-rewarded, never punished.
	bounties = {
		perDay = 3,
		templates = {
			{ key = "catchAny", text = "Catch %d creatures", target = 15, shellReward = 120 },
			{ key = "perfectCasts", text = "Land %d perfect casts", target = 5, shellReward = 150 },
			{
				key = "clearWaves",
				text = "Clear %d surge waves",
				target = 6,
				shellReward = 140,
				stormglassReward = 2,
			},
			{
				key = "collectReef",
				text = "Collect %d Shells from your reef",
				target = 200,
				shellReward = 100,
			},
			{ key = "hatchEggs", text = "Hatch %d egg", target = 1, shellReward = 160 },
			{
				key = "rideDistance",
				text = "Surf %d studs on a mount",
				target = 800,
				shellReward = 140,
				stormglassReward = 2,
			},
		},
		streakMilestones = {
			{ days = 3, shellReward = 300 },
			{ days = 7, shellReward = 800 },
			{ days = 14, shellReward = 2000 },
		},
	},

	-- Client settings, persisted per player. Defaults are what a brand
	-- new account hears and sees.
	settings = {
		defaults = {
			musicVolume = 0.6,
			sfxVolume = 0.8,
			reducedMotion = false,
		},
	},

	data = {
		storeName = "TidetownPlayer_v1",
		autosaveSeconds = 120,
		loadAttempts = 3,
		retryBaseSeconds = 2,
	},

	-- Shown once to new players; kept short and concrete on purpose.
	-- The first session deliberately teaches only rescue-cast-hatch;
	-- the reef and the surge introduce themselves after one full cycle.
	tutorialSteps = {
		"Welcome, Tidekeeper! Tap CAST at a glowing pool, then tap again on the flash.",
		"A PERFECT tap rolls rarer creatures. Watch the shrinking ring!",
		"Eggs charge as you catch -- five good catches cracks your first one.",
		"When the siren sounds, the sea comes back. High ground is your friend!",
		"Your reef plot on the boardwalk earns Shells even while you sleep.",
		"At high tide, grab the pier inner tube and surf the flooded streets!",
	},

	-- Rotated on the loading screen; one random tip per swap so long
	-- loads teach something new each time.
	proTips = {
		"Perfect casts roll on a strictly better table. Skill bends luck.",
		"Eggs hatch from catches, not clocks. Keep casting!",
		"Different roles link up: mix Anchor, Sprayer, Herder, and Sparker.",
		"Stormglass only comes from surges and the deep. Spend it on mounts!",
		"Your reef keeps earning while you are away -- capped, never wasted.",
		"The Deep Reef opens at 18 Tidepedia entries and a real mount.",
		"Salvage piles after a rough surge are still yours. Scoop them up!",
		"Bounty streaks pause when you miss a day. They never reset.",
	},
}

return TidetownConfig
