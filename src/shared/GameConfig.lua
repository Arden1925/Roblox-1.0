--[[
	Every tunable number in the game lives here so balancing is a matter of
	editing one file. Systems read from this table and never hardcode
	gameplay values.
]]

local GameConfig = {
	growth = {
		tickSeconds = 0.25,
		sizePerTick = 1,
		-- How quickly Current Size climbs back to Max Size after
		-- shrinking; the slowness is the vulnerability window that makes
		-- shrinking a real decision.
		regrowPerSecond = 6,
	},

	shrink = {
		shrunkSize = 10,
		shrinkPerSecond = 80,
	},

	scale = {
		-- Character scale is a saturating curve so early growth is
		-- dramatic and huge sizes cannot break physics.
		minimum = 0.45,
		maximum = 6,
		halfwaySize = 200,
	},

	speed = {
		-- The player-adjustable slider range. Deliberately narrow: speed
		-- is a comfort setting in this game, never the way you win.
		minimum = 12,
		maximum = 20,
		default = 16,
		potionBonus = 4,
		hardCap = 26,
	},

	rebirth = {
		-- First rebirth needs this Max Size; each later rebirth needs one
		-- more multiple of it.
		baseRequiredSize = 250,
		-- Permanent growth bonus per rebirth (0.5 = +50% each).
		multiplierPerRebirth = 0.5,
		-- Extra perks per rebirth, shown on the rebirth page: bonus coins
		-- forever, and better odds on every egg's top tier.
		coinBonusPerRebirth = 0.05,
		luckPerRebirth = 0.02,
		-- How long the rebirth machine cinematic holds the player.
		cinematicSeconds = 3.5,
	},

	offline = {
		-- Away-time growth per minute (scaled by rebirth multiplier),
		-- capped so a week away is a warm welcome, not a skipped game.
		sizePerMinute = 1,
		maxHours = 8,
	},

	afkPod = {
		-- Standing in a spawn pod grows you hands-free at this fraction
		-- of pad rate.
		growthFraction = 0.5,
	},

	events = {
		goldenPadIntervalSeconds = 90,
		goldenPadDurationSeconds = 20,
		goldenPadMultiplier = 5,
		starIntervalSeconds = 240,
		-- Star rewards scale with the world it lands in.
		starSizeBase = 60,
		starCoinsBase = 40,
	},

	shiny = {
		-- Chance any hatch comes out Shiny: sparkling look, bigger bonus.
		chance = 0.05,
		bonusMultiplier = 1.5,
	},

	mechanisms = {
		-- Weight plates hold bridges out while enough Current Size stands
		-- on them; bridges pull back in when the weight leaves.
		bridgeExtendSeconds = 2,
		bridgeRetractSeconds = 3,
		-- Boulders shatter for anyone at or above their CrushSize and
		-- grow back later.
		boulderRespawnSeconds = 60,
		-- Updrafts only lift bodies at or below their MaxLiftSize.
		updraftVelocity = 55,
		-- Crusher bar cycle per world (world 1 has none); slower is
		-- easier, and later worlds only tighten the timing a little.
		crusherCycleSeconds = { 0, 4, 3, 2.5 },
	},

	streakRewards = {
		{ coins = 100 },
		{ coins = 200 },
		{ coins = 350 },
		{ coins = 500 },
		{ coins = 750 },
		{ coins = 1000 },
		{ coins = 2000 },
	},

	-- Three are rolled per player per day; stat names are counted by
	-- QuestService as play happens.
	questTemplates = {
		{
			key = "HatchEggs",
			description = "Hatch %d eggs",
			stat = "eggsHatched",
			target = 2,
			rewardCoins = 250,
		},
		{
			key = "TouchCheckpoints",
			description = "Touch %d checkpoints",
			stat = "checkpoints",
			target = 4,
			rewardCoins = 200,
		},
		{
			key = "CollectCoins",
			description = "Pick up %d coins on the ground",
			stat = "coinPickups",
			target = 10,
			rewardCoins = 300,
		},
		{
			key = "UsePotions",
			description = "Drink %d potions",
			stat = "potionsUsed",
			target = 2,
			rewardCoins = 200,
		},
		{
			key = "GetLaunched",
			description = "Get launched %d times",
			stat = "launches",
			target = 3,
			rewardCoins = 150,
		},
	},

	group = {
		-- Paste the real group id once the group exists; 0 keeps the
		-- chest in "coming soon" mode.
		groupId = 0,
		rewardCoins = 750,
	},

	-- Escalating one-time value packs plus the server-wide luck boost.
	-- Paste developer product IDs after creating them.
	packs = {
		{
			key = "StarterPack",
			name = "Starter Pack",
			description = "+500 Max Size and 500 coins. Perfect first boost!",
			robuxPrice = 25,
			productId = 0,
			grantSize = 500,
			grantCoins = 500,
		},
		{
			key = "ProPack",
			name = "Pro Pack",
			description = "+2500 Max Size, 2500 coins, and a long Growth Potion.",
			robuxPrice = 99,
			productId = 0,
			grantSize = 2500,
			grantCoins = 2500,
			grantEffectKey = "GrowthPotion",
			grantEffectSeconds = 600,
		},
		{
			key = "MegaPack",
			name = "Mega Pack",
			description = "+8000 Max Size, 8000 coins, and +25% growth FOREVER.",
			robuxPrice = 299,
			productId = 0,
			grantSize = 8000,
			grantCoins = 8000,
			grantPermanentGrowth = 0.25,
		},
	},

	serverLuck = {
		name = "Server Luck Boost",
		description = "Doubles rare-pet odds for EVERYONE for 10 minutes.",
		robuxPrice = 49,
		productId = 0,
		durationSeconds = 600,
		weightMultiplier = 2,
	},

	gates = {
		openRange = 16,
		closeDelaySeconds = 1,
	},

	obstacles = {
		hazardDebounceSeconds = 1,
		fadeDelaySeconds = 0.8,
		fadeRespawnSeconds = 3,
		bounceVelocity = 90,
	},

	economy = {
		-- All coin awards scale with world index so later worlds pay
		-- more without any special casing.
		coinPickupBase = 5,
		checkpointCoinBase = 20,
		worldReachCoinBase = 100,
		coinRespawnSeconds = 45,
		mysteryMachineBaseCost = 400,
		-- Worlds whose index divides by this get a Mystery Machine.
		mysteryMachineEveryNWorlds = 3,
	},

	-- Coin-bought consumables at every world's station. Cost and instant
	-- amounts multiply by the station's world index.
	potions = {
		{
			key = "SizePotion",
			name = "Size Potion",
			description = "Instantly gain Max Size.",
			baseCost = 60,
			effect = "instantSize",
			amount = 40,
		},
		{
			key = "GrowthPotion",
			name = "Growth Potion",
			description = "x1.5 growth for 5 minutes.",
			baseCost = 90,
			effect = "timed",
			effectKey = "GrowthPotion",
			durationSeconds = 300,
		},
		{
			key = "SpeedPotion",
			name = "Speed Potion",
			description = "A little extra speed for 5 minutes.",
			baseCost = 45,
			effect = "timed",
			effectKey = "SpeedPotion",
			durationSeconds = 300,
		},
		{
			key = "JumpPotion",
			name = "Jump Potion",
			description = "Jump 25% higher for 5 minutes.",
			baseCost = 50,
			effect = "timed",
			effectKey = "JumpPotion",
			durationSeconds = 300,
		},
		{
			key = "CoinPotion",
			name = "Coin Potion",
			description = "Double all coins you earn for 5 minutes.",
			baseCost = 120,
			effect = "timed",
			effectKey = "CoinPotion",
			durationSeconds = 300,
		},
	},

	-- Permanent coin-bought upgrades; cost rises every level so coins
	-- always have somewhere meaningful to go.
	upgrades = {
		{
			key = "GrowthUpgrade",
			name = "Growth Training",
			description = "+10% growth per level, forever.",
			baseCost = 150,
			costGrowth = 1.6,
			maxLevel = 10,
			bonusPerLevel = 0.1,
		},
		{
			key = "CoinUpgrade",
			name = "Coin Magnet",
			description = "+10% coins per level, forever.",
			baseCost = 120,
			costGrowth = 1.6,
			maxLevel = 10,
			bonusPerLevel = 0.1,
		},
		{
			key = "JumpUpgrade",
			name = "Spring Legs",
			description = "+2% jump per level, forever.",
			baseCost = 100,
			costGrowth = 1.5,
			maxLevel = 5,
			bonusPerLevel = 0.02,
		},
	},

	passEffects = {
		autoGrowFraction = 0.25,
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

	-- Paste real game pass IDs after creating them on the Creator Hub.
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
			description = "Keep growing slowly even off the pads.",
			robuxPrice = 199,
			gamePassId = 0,
		},
		{
			key = "SuperSqueeze",
			name = "Super Squeeze",
			description = "Fit through cracks one size tier tighter.",
			robuxPrice = 249,
			gamePassId = 0,
		},
		{
			key = "Vip",
			name = "VIP",
			description = "A golden trail that grows with you, +25% growth.",
			robuxPrice = 299,
			gamePassId = 0,
		},
		{
			key = "DoubleRebirthBonus",
			name = "2x Rebirth Bonus",
			description = "Every rebirth grants double its multiplier.",
			robuxPrice = 399,
			gamePassId = 0,
		},
		{
			key = "SizeMaster",
			name = "Size Master",
			description = "A slider to set your body size, any time.",
			robuxPrice = 999,
			gamePassId = 0,
		},
	},

	-- Rarity tiers shared by all pets, weakest first. Each world's coin
	-- egg draws from three consecutive tiers, sliding up one tier per
	-- world, so later eggs are strictly better.
	petTiers = {
		{ name = "Common", color = { 178, 190, 195 }, bonus = 0.05 },
		{ name = "Rare", color = { 9, 132, 227 }, bonus = 0.12 },
		{ name = "Epic", color = { 156, 136, 255 }, bonus = 0.25 },
		{ name = "Legendary", color = { 253, 203, 110 }, bonus = 0.45 },
		{ name = "Mythic", color = { 232, 67, 147 }, bonus = 0.75 },
		{ name = "Ultra", color = { 255, 234, 167 }, bonus = 1 },
	},

	-- Chance weights for a coin egg's three tiers, weakest first.
	eggTierWeights = { 70, 25, 5 },

	-- The limited pet shown on a pedestal at spawn, Robux only.
	limitedPet = {
		name = "Ultra Dragon",
		description = "LIMITED -- x2.5 total growth aura.",
		robuxPrice = 799,
		productId = 0,
		bonus = 1.5,
	},

	-- One world per square platform, in walk order. exitWallHeight is the
	-- climbable wall to the NEXT world. Egg pets are listed weakest tier
	-- first: two on the egg's lowest tier, two on its middle, one on top.
	-- robuxEgg pets are exclusive, equal odds; paste product IDs later.
	worlds = {
		{
			name = "Sprout Meadows",
			floorColor = { 126, 214, 87 },
			exitWallHeight = 14,
			exitStepCount = 3,
			gateRequiredSize = 30,
			eggName = "Meadow Egg",
			eggCost = 100,
			eggPets = {
				"Sprout Bunny",
				"Daisy Chick",
				"Thorn Fox",
				"Bloom Deer",
				"Sunflower Bear",
			},
			robuxEgg = {
				name = "Meadow Royal Egg",
				robuxPrice = 149,
				productId = 0,
				pets = {
					{ name = "Royal Bunny", tier = 3, bonus = 0.3 },
					{ name = "Gilded Fox", tier = 3, bonus = 0.32 },
					{ name = "Crystal Bear", tier = 4, bonus = 0.5 },
				},
			},
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
			gateRequiredSize = 80,
			eggName = "Vent Egg",
			eggCost = 280,
			eggPets = { "Pipe Rat", "Gear Pup", "Steam Cat", "Bolt Owl", "Chrome Drake" },
			robuxEgg = {
				name = "Vent Royal Egg",
				robuxPrice = 199,
				productId = 0,
				pets = {
					{ name = "Neon Rat", tier = 4, bonus = 0.5 },
					{ name = "Piston Hound", tier = 4, bonus = 0.55 },
					{ name = "Turbine Drake", tier = 5, bonus = 0.8 },
				},
			},
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
			gateRequiredSize = 150,
			eggName = "Ember Egg",
			eggCost = 520,
			eggPets = {
				"Ash Imp",
				"Coal Golem",
				"Flame Lynx",
				"Magma Tortoise",
				"Inferno Phoenix",
			},
			robuxEgg = {
				name = "Ember Royal Egg",
				robuxPrice = 249,
				productId = 0,
				pets = {
					{ name = "Obsidian Imp", tier = 5, bonus = 0.8 },
					{ name = "Cinder Wolf", tier = 5, bonus = 0.85 },
					{ name = "Solar Phoenix", tier = 6, bonus = 1.1 },
				},
			},
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
			gateRequiredSize = 220,
			eggName = "Cloud Egg",
			eggCost = 800,
			eggPets = {
				"Nimbus Lamb",
				"Breeze Sprite",
				"Storm Eagle",
				"Aurora Whale",
				"Sky Serpent",
			},
			robuxEgg = {
				name = "Cloud Royal Egg",
				robuxPrice = 299,
				productId = 0,
				pets = {
					{ name = "Halo Lamb", tier = 6, bonus = 1.1 },
					{ name = "Tempest Eagle", tier = 6, bonus = 1.15 },
					{ name = "Galaxy Serpent", tier = 6, bonus = 1.25 },
				},
			},
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

	-- Shown once to new players; kept short and concrete on purpose.
	tutorialSteps = {
		"Stand on the GREEN pads to grow. Your SIZE number climbs at the top.",
		"The red gate ahead opens when you are big enough. Grow, then walk in.",
		"BLUE pads shrink your body. You never lose progress -- you regrow!",
		"Shrink small to fit through the orange crack, then regrow after.",
		"Hop the floating steps over the wall to reach the next world.",
		"Grab coins and touch checkpoints -- they save your spot and pay you!",
	},
}

return GameConfig
