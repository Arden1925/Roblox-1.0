--[[
	Runs the high-tide surge defense. When the tide turns High, every
	keeper with a claimed reef plot gets a private lane of feral waves
	marching on their barrier. One service-wide Heartbeat moves every
	enemy and resolves all combat -- Sprayer beams, Herder slow zones,
	Sparker detonations, Anchor armor, and the distinct-role link
	bonus -- reusing per-surge tables so the hot loop allocates
	nothing. Deflect taps are rate limited on the server clock,
	Stormglass pays full only to keepers who actually engaged, and a
	lost surge converts leftover ferals into salvage piles instead of
	paying nothing at all.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TidetownShared = ReplicatedStorage.TidetownShared
local CreatureModels = require(TidetownShared.CreatureModels)
local TideLayout = require(TidetownShared.TideLayout)
local TidePhase = require(TidetownShared.TidePhase)
local TidetownConfig = require(TidetownShared.TidetownConfig)

local MAP_FOLDER_NAME = "Tidetown"
-- Mirrors the Barrier offset MapBuilder uses from the pad center, so a
-- missing barrier part still yields the right combat anchor.
local BARRIER_OFFSET_FROM_PAD = Vector3.new(-3, 2, 0)
local SPAWN_DISTANCE_STUDS = 55
local ENEMY_SPACING_STUDS = 4
local ENEMY_HEIGHT_STUDS = 1.6
-- Ferals ride just under the high-tide surface.
local ENEMY_WATERLINE_Y = TidetownConfig.tide.highWaterY - 0.2
-- Tinted near-black so ferals never read as catchable creatures.
local ENEMY_TINT = Color3.fromRGB(40, 40, 55)
local ENEMY_LIGHT_COLOR = Color3.fromRGB(255, 60, 50)
-- Enemies stop this short of the barrier face and gnaw from there.
local STOP_DISTANCE_STUDS = 2
local GNAW_HEALTH_PER_SECOND = 5
local BOB_AMPLITUDE_STUDS = 0.35
local BOB_RADIANS_PER_SECOND = 2.5
local ARMOR_CAP_FRACTION = 0.6
-- Stacked Herders compound multiplicatively but a single stack step
-- never exceeds this, so enemies always keep crawling forward.
local SLOW_CAP_FRACTION = 0.8
local LASER_FLASH_INTERVAL_SECONDS = 0.5
local LASER_VISIBLE_SECONDS = 0.12
local LASER_COLOR = Color3.fromRGB(120, 220, 255)
-- Barrier damage streams every frame; the remote fires at most this
-- often so gnawing never floods the client with events.
local BARRIER_EVENT_INTERVAL_SECONDS = 0.25
local WAVE_POLL_SECONDS = 0.25
-- Floor under the charm ladder so a future config change can never
-- turn the deflect into a zero-cooldown spam button.
local MINIMUM_DEFLECT_COOLDOWN_SECONDS = 0.5
-- Enemies walk the lane in +X: the sea is seaward at negative X.
local LANE_ROTATION = CFrame.lookAt(Vector3.zero, Vector3.xAxis)
local SALVAGE_COLOR = Color3.fromRGB(255, 199, 92)

-- Pulled from the shop upgrade templates once at load; the fallbacks
-- only matter if the templates are ever renamed.
local BARRIER_HEALTH_PER_LEVEL = 25
local DEFLECT_COOLDOWN_CUT_SECONDS = 0.5
for _, upgrade in ipairs(TidetownConfig.shop.upgrades :: { any }) do
	if upgrade.key == "barrierPlating" then
		BARRIER_HEALTH_PER_LEVEL = upgrade.healthPerLevel
	elseif upgrade.key == "deflectCharm" then
		DEFLECT_COOLDOWN_CUT_SECONDS = upgrade.cooldownCutSeconds
	end
end

type TeamMemberStats = {
	uid: string,
	speciesKey: string,
	role: string,
	rarity: string,
	multiplier: number,
}

export type Dependencies = {
	onPhaseChanged: (callback: (phase: string) -> ()) -> (),
	getPhase: () -> string,
	defenseTeamStats: (Player) -> { TeamMemberStats },
	plotIndexFor: (Player) -> number?,
	plotBarrier: (plotIndex: number) -> BasePart?,
	upgradeLevel: (Player, string) -> number,
	keeperRank: (Player) -> number,
	awardShells: (Player, number) -> (),
	awardStormglass: (Player, number) -> (),
	reportBounty: (Player, string, number) -> (),
	pushToast: (Player, string, string?) -> (),
	fireSurgeEvent: (Player, string, any) -> (),
}

type Enemy = {
	model: Model?,
	position: Vector3,
	baseY: number,
	bobOffset: number,
	health: number,
	maxHealth: number,
	wave: number,
	bountyShells: number,
	reachedBarrier: boolean,
	alive: boolean,
}

type SprayerState = {
	uid: string,
	damagePerSecond: number,
	rangeStuds: number,
	laser: BasePart?,
	originPosition: Vector3,
	nextFlashClock: number,
	flashUntilClock: number,
}

type HerderState = {
	slowFactor: number,
	radiusStuds: number,
}

type SparkerState = {
	uid: string,
	burstDamage: number,
	radiusStuds: number,
	chargeSeconds: number,
	chargeRemaining: number,
	ready: boolean,
}

type SurgeState = {
	player: Player,
	plotIndex: number,
	barrierPosition: Vector3,
	spawnX: number,
	barrierHealth: number,
	barrierMaxHealth: number,
	armorFraction: number,
	enemyHealthScale: number,
	wave: number,
	aliveCount: number,
	enemyPool: { Enemy },
	sprayers: { SprayerState },
	herders: { HerderState },
	sparkers: { SparkerState },
	engaged: boolean,
	stormglassTotal: number,
	active: boolean,
	failReason: string?,
	lastBarrierEventClock: number,
	container: Folder,
}

type SalvagePile = {
	part: BasePart,
	connection: RBXScriptConnection?,
	owner: Player,
	collected: boolean,
}

local dependencies: Dependencies? = nil
local surges: { [Player]: SurgeState } = {}
local salvagePiles: { SalvagePile } = {}
local lastDeflectClockByPlayer: { [Player]: number } = {}
local activeSurgeCount = 0
local mapFolder: Instance? = nil
local started = false

local SurgeService = {}

-- Enemies and lasers parent under the map folder when it exists so a
-- server without a built map still runs surges out of Workspace.
local function surgeParent(): Instance
	if mapFolder == nil or mapFolder.Parent == nil then
		mapFolder = Workspace:FindFirstChild(MAP_FOLDER_NAME)
	end

	return if mapFolder ~= nil then mapFolder else Workspace
end

-- The link bonus counts every pair of DIFFERENT roles in the team, so
-- mixing roles is rewarded without any hidden same-role penalty.
local function distinctRolePairs(teamStats: { TeamMemberStats }): number
	local pairCount = 0
	for firstIndex = 1, #teamStats do
		for secondIndex = firstIndex + 1, #teamStats do
			if teamStats[firstIndex].role ~= teamStats[secondIndex].role then
				pairCount += 1
			end
		end
	end

	return pairCount
end

local function clearAllSalvagePiles()
	for _, pile in ipairs(salvagePiles) do
		if pile.connection ~= nil then
			pile.connection:Disconnect()
		end

		pile.part:Destroy()
	end

	table.clear(salvagePiles)
end

local function spawnSalvagePile(owner: Player, position: Vector3, shellValue: number)
	local currentDependencies = dependencies
	if currentDependencies == nil then
		return
	end

	local part = Instance.new("Part")
	part.Name = "SalvagePile"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.6, 1.6, 1.6)
	part.Color = SALVAGE_COLOR
	part.Material = Enum.Material.Metal
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	-- Piles drop to the sand shelf under the lane so they are still
	-- reachable on foot once the water drains away.
	part.CFrame = CFrame.new(position.X, TidetownConfig.layout.beachSand.topY + 0.6, position.Z)

	local light = Instance.new("PointLight")
	light.Color = SALVAGE_COLOR
	light.Brightness = 1.2
	light.Range = 6
	light.Parent = part

	part.Parent = surgeParent()

	local pile: SalvagePile = {
		part = part,
		connection = nil,
		owner = owner,
		collected = false,
	}

	-- Only the owner collects: salvage is that keeper's consolation,
	-- not a free-for-all pickup.
	pile.connection = part.Touched:Connect(function(hit: BasePart)
		if pile.collected then
			return
		end

		local character = hit.Parent
		if character == nil or not character:IsA("Model") then
			return
		end

		if Players:GetPlayerFromCharacter(character) ~= owner then
			return
		end

		pile.collected = true
		if pile.connection ~= nil then
			pile.connection:Disconnect()
		end

		currentDependencies.awardShells(owner, shellValue)
		currentDependencies.pushToast(
			owner,
			string.format("Salvaged %d Shells from the wreck!", shellValue),
			"good"
		)
		part:Destroy()
	end)

	table.insert(salvagePiles, pile)
end

local function createLaser(parent: Instance): BasePart
	local laser = Instance.new("Part")
	laser.Name = "SprayerLaser"
	laser.Material = Enum.Material.Neon
	laser.Color = LASER_COLOR
	laser.Size = Vector3.new(0.15, 0.15, 1)
	laser.Transparency = 1
	laser.Anchored = true
	laser.CanCollide = false
	laser.CanQuery = false
	laser.CanTouch = false
	laser.CastShadow = false
	laser.Parent = parent

	return laser
end

local function buildEnemyModel(speciesKey: string, position: Vector3, parent: Instance): Model
	local model = CreatureModels.build(speciesKey, ENEMY_HEIGHT_STUDS)

	-- Strip the role accent light along with the tint: a feral must
	-- never carry the visual language of a friendly creature.
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Color = ENEMY_TINT
		elseif descendant:IsA("PointLight") then
			descendant:Destroy()
		end
	end

	local primary = model.PrimaryPart
	if primary ~= nil then
		local light = Instance.new("PointLight")
		light.Color = ENEMY_LIGHT_COLOR
		light.Brightness = 1.2
		light.Range = 6
		light.Parent = primary
	end

	model:PivotTo(CFrame.new(position) * LANE_ROTATION)
	model.Parent = parent

	return model
end

-- Pool records are reused across waves so the Heartbeat never chases
-- freshly allocated tables.
local function enemyAt(surge: SurgeState, index: number): Enemy
	local enemy = surge.enemyPool[index]
	if enemy == nil then
		enemy = {
			model = nil,
			position = Vector3.zero,
			baseY = 0,
			bobOffset = 0,
			health = 0,
			maxHealth = 0,
			wave = 1,
			bountyShells = 0,
			reachedBarrier = false,
			alive = false,
		}
		surge.enemyPool[index] = enemy
	end

	return enemy
end

local function spawnWave(surge: SurgeState, wave: number)
	local surgeConfig = TidetownConfig.surge
	local count = surgeConfig.enemiesBaseCount + surgeConfig.enemiesPerWave * (wave - 1)
	local speciesKey = surgeConfig.enemySpeciesByWave[wave]
		or surgeConfig.enemySpeciesByWave[#surgeConfig.enemySpeciesByWave]
	local health = (surgeConfig.enemyBaseHealth + surgeConfig.enemyHealthPerWave * (wave - 1))
		* surge.enemyHealthScale
	local bounty = surgeConfig.enemyBountyShells + surgeConfig.enemyBountyPerWave * (wave - 1)

	surge.wave = wave
	surge.aliveCount = count

	for index = 1, count do
		local enemy = enemyAt(surge, index)
		local laneZ = surge.barrierPosition.Z + (index - (count + 1) / 2) * ENEMY_SPACING_STUDS
		enemy.position = Vector3.new(surge.spawnX, ENEMY_WATERLINE_Y, laneZ)
		enemy.baseY = ENEMY_WATERLINE_Y
		enemy.bobOffset = index * 0.9
		enemy.health = health
		enemy.maxHealth = health
		enemy.wave = wave
		enemy.bountyShells = bounty
		enemy.reachedBarrier = false
		enemy.alive = true
		enemy.model = buildEnemyModel(speciesKey, enemy.position, surge.container)
	end
end

--[[
	One frame of one surge: enemy movement with Herder slowing, gnawing
	through Anchor armor, Sprayer damage with the throttled laser
	flash, Sparker charging, and the death sweep. Runs inside the
	single service Heartbeat, so nothing here may allocate instances or
	tables beyond the throttled remote payloads.
]]
local function stepSurge(
	surge: SurgeState,
	deltaTime: number,
	now: number,
	currentDependencies: Dependencies
)
	if surge.failReason ~= nil then
		return
	end

	local surgeConfig = TidetownConfig.surge
	local barrierPosition = surge.barrierPosition
	local gnawDamage = 0

	for _, enemy in ipairs(surge.enemyPool) do
		if enemy.alive then
			local positionX = enemy.position.X

			if not enemy.reachedBarrier then
				local distanceToBarrier = (enemy.position - barrierPosition).Magnitude

				local speedScale = 1
				for _, herder in ipairs(surge.herders) do
					if distanceToBarrier <= herder.radiusStuds then
						speedScale *= herder.slowFactor
					end
				end

				positionX += surgeConfig.enemySpeedStudsPerSecond * speedScale * deltaTime

				local stopX = barrierPosition.X - STOP_DISTANCE_STUDS
				if positionX >= stopX then
					positionX = stopX
					enemy.reachedBarrier = true
				end
			else
				gnawDamage += GNAW_HEALTH_PER_SECOND * deltaTime
			end

			local bobY = enemy.baseY
				+ math.sin(now * BOB_RADIANS_PER_SECOND + enemy.bobOffset) * BOB_AMPLITUDE_STUDS
			enemy.position = Vector3.new(positionX, bobY, enemy.position.Z)

			local model = enemy.model
			if model ~= nil then
				model:PivotTo(CFrame.new(enemy.position) * LANE_ROTATION)
			end
		end
	end

	if gnawDamage > 0 then
		surge.barrierHealth -= gnawDamage * (1 - surge.armorFraction)

		local intervalPassed = now - surge.lastBarrierEventClock >= BARRIER_EVENT_INTERVAL_SECONDS
		if intervalPassed or surge.barrierHealth <= 0 then
			surge.lastBarrierEventClock = now
			currentDependencies.fireSurgeEvent(surge.player, "barrierHit", {
				health = math.max(math.floor(surge.barrierHealth + 0.5), 0),
				maxHealth = surge.barrierMaxHealth,
			})
		end
	end

	for _, sprayer in ipairs(surge.sprayers) do
		-- The Sprayer picks the enemy nearest the barrier: the one
		-- about to do damage, which reads as smart on screen.
		local target: Enemy? = nil
		local bestX = -math.huge
		for _, enemy in ipairs(surge.enemyPool) do
			if enemy.alive and enemy.position.X > bestX then
				if (enemy.position - barrierPosition).Magnitude <= sprayer.rangeStuds then
					target = enemy
					bestX = enemy.position.X
				end
			end
		end

		local laser = sprayer.laser
		if target ~= nil then
			target.health -= sprayer.damagePerSecond * deltaTime

			if laser ~= nil and now >= sprayer.nextFlashClock then
				local origin = sprayer.originPosition
				local distance = (target.position - origin).Magnitude
				if distance > 0.5 then
					sprayer.nextFlashClock = now + LASER_FLASH_INTERVAL_SECONDS
					sprayer.flashUntilClock = now + LASER_VISIBLE_SECONDS
					laser.Size = Vector3.new(0.15, 0.15, distance)
					laser.CFrame = CFrame.lookAt(origin, target.position)
						* CFrame.new(0, 0, -distance / 2)
					laser.Transparency = 0.1
				end
			end
		end

		if laser ~= nil and laser.Transparency < 1 and now >= sprayer.flashUntilClock then
			laser.Transparency = 1
		end
	end

	for _, sparker in ipairs(surge.sparkers) do
		if not sparker.ready then
			sparker.chargeRemaining -= deltaTime
			if sparker.chargeRemaining <= 0 then
				sparker.ready = true
				currentDependencies.fireSurgeEvent(surge.player, "sparkerReady", {
					uid = sparker.uid,
				})
			end
		end
	end

	for _, enemy in ipairs(surge.enemyPool) do
		if enemy.alive and enemy.health <= 0 then
			enemy.alive = false
			surge.aliveCount -= 1

			local model = enemy.model
			if model ~= nil then
				model:Destroy()
				enemy.model = nil
			end
		end
	end

	if surge.barrierHealth <= 0 then
		surge.failReason = "barrier"
	end
end

--[[
	Tears one surge down exactly once: leftover ferals become salvage
	piles worth a fraction of their bounty, the lane props vanish, and
	the client always receives one closing surgeEnded event.
]]
local function finishSurge(surge: SurgeState)
	local currentDependencies = dependencies
	if currentDependencies == nil or surges[surge.player] ~= surge then
		return
	end

	surges[surge.player] = nil
	activeSurgeCount -= 1
	surge.active = false

	local surgeConfig = TidetownConfig.surge
	local cleared = surge.failReason == nil
		and surge.aliveCount == 0
		and surge.wave >= surgeConfig.waveCount

	local salvageShells = 0
	if not cleared then
		for _, enemy in ipairs(surge.enemyPool) do
			if enemy.alive then
				enemy.alive = false

				local pileValue = math.floor(enemy.bountyShells * surgeConfig.salvageFraction)
				if pileValue > 0 then
					salvageShells += pileValue
					spawnSalvagePile(surge.player, enemy.position, pileValue)
				end
			end
		end
	end

	surge.container:Destroy()

	currentDependencies.fireSurgeEvent(surge.player, "surgeEnded", {
		cleared = cleared,
		stormglassTotal = surge.stormglassTotal,
		salvageShells = salvageShells,
	})
end

--[[
	The per-surge wave sequencer, run in its own task: spawns each
	wave, then sleeps in short polls while the Heartbeat fights it out.
	Instance creation stays here so the Heartbeat never spawns models.
]]
local function runSurgeWaves(surge: SurgeState)
	local currentDependencies = dependencies
	if currentDependencies == nil then
		return
	end

	local surgeConfig = TidetownConfig.surge

	for wave = 1, surgeConfig.waveCount do
		if not surge.active or surge.failReason ~= nil then
			break
		end

		spawnWave(surge, wave)
		currentDependencies.fireSurgeEvent(surge.player, "waveStarted", {
			wave = wave,
			total = surgeConfig.waveCount,
			enemies = surge.aliveCount,
		})

		while surge.active and surge.failReason == nil and surge.aliveCount > 0 do
			task.wait(WAVE_POLL_SECONDS)
		end

		if not surge.active or surge.failReason ~= nil then
			break
		end

		-- Winning while AFK pays a deliberately smaller number: full
		-- Stormglass needs at least one landed deflect or Sparker
		-- trigger this surge.
		local fullAmount = surgeConfig.stormglassByWave[wave] or 0
		local amount = if surge.engaged
			then fullAmount
			else math.floor(fullAmount * surgeConfig.disengagedStormglassFraction)
		currentDependencies.awardStormglass(surge.player, amount)
		surge.stormglassTotal += amount
		currentDependencies.fireSurgeEvent(surge.player, "waveCleared", {
			wave = wave,
			stormglass = amount,
		})
		currentDependencies.reportBounty(surge.player, "clearWaves", 1)

		if wave < surgeConfig.waveCount then
			local remaining = surgeConfig.secondsBetweenWaves
			while remaining > 0 and surge.active and surge.failReason == nil do
				remaining -= task.wait(WAVE_POLL_SECONDS)
			end
		end
	end

	finishSurge(surge)
end

local function beginSurge(player: Player)
	local currentDependencies = dependencies
	if currentDependencies == nil or surges[player] ~= nil then
		return
	end

	if currentDependencies.getPhase() ~= TidePhase.High then
		return
	end

	local plotIndex = currentDependencies.plotIndexFor(player)
	if plotIndex == nil then
		return
	end

	local barrier = currentDependencies.plotBarrier(plotIndex)
	local barrierPosition = if barrier ~= nil
		then barrier.Position
		else TideLayout.plotPosition(plotIndex) + BARRIER_OFFSET_FROM_PAD

	local container = Instance.new("Folder")
	container.Name = "Surge" .. tostring(plotIndex)
	container.Parent = surgeParent()

	local teamStats = currentDependencies.defenseTeamStats(player)
	local roleConfigs = TidetownConfig.creatures.roles
	local linkScale = 1
		+ distinctRolePairs(teamStats) * TidetownConfig.creatures.linkBonusPerPairPercent / 100

	local sprayers: { SprayerState } = {}
	local herders: { HerderState } = {}
	local sparkers: { SparkerState } = {}
	local armorPercent = 0

	for _, member in ipairs(teamStats) do
		-- Every role stat scales by rarity AND the link bonus, so a
		-- mixed team is stronger stat-for-stat than a mono team.
		local statScale = member.multiplier * linkScale

		if member.role == "Anchor" then
			armorPercent += roleConfigs.Anchor.barrierArmorPercent * statScale
		elseif member.role == "Sprayer" then
			table.insert(sprayers, {
				uid = member.uid,
				damagePerSecond = roleConfigs.Sprayer.damagePerSecond * statScale,
				rangeStuds = roleConfigs.Sprayer.rangeStuds,
				laser = createLaser(container),
				originPosition = barrierPosition + Vector3.new(0.5, 1.8, #sprayers * 1.5),
				nextFlashClock = 0,
				flashUntilClock = 0,
			})
		elseif member.role == "Herder" then
			table.insert(herders, {
				slowFactor = 1
					- math.min(roleConfigs.Herder.slowFraction * statScale, SLOW_CAP_FRACTION),
				radiusStuds = roleConfigs.Herder.radiusStuds,
			})
		elseif member.role == "Sparker" then
			table.insert(sparkers, {
				uid = member.uid,
				burstDamage = roleConfigs.Sparker.burstDamage * statScale,
				radiusStuds = roleConfigs.Sparker.radiusStuds,
				chargeSeconds = roleConfigs.Sparker.chargeSeconds,
				chargeRemaining = roleConfigs.Sparker.chargeSeconds,
				ready = false,
			})
		end
	end

	local surgeConfig = TidetownConfig.surge
	local barrierMaxHealth = surgeConfig.barrierBaseHealth
		+ currentDependencies.upgradeLevel(player, "barrierPlating") * BARRIER_HEALTH_PER_LEVEL

	local surge: SurgeState = {
		player = player,
		plotIndex = plotIndex,
		barrierPosition = barrierPosition,
		spawnX = barrierPosition.X - SPAWN_DISTANCE_STUDS,
		barrierHealth = barrierMaxHealth,
		barrierMaxHealth = barrierMaxHealth,
		armorFraction = math.min(armorPercent / 100, ARMOR_CAP_FRACTION),
		-- Lanes scale to their keeper's rank, so veterans and newbies
		-- share a server without sharing a difficulty curve.
		enemyHealthScale = 1
			+ surgeConfig.enemyHealthPerRankPercent
				/ 100
				* currentDependencies.keeperRank(player),
		wave = 0,
		aliveCount = 0,
		enemyPool = {},
		sprayers = sprayers,
		herders = herders,
		sparkers = sparkers,
		engaged = false,
		stormglassTotal = 0,
		active = true,
		failReason = nil,
		lastBarrierEventClock = 0,
		container = container,
	}

	surges[player] = surge
	activeSurgeCount += 1

	currentDependencies.pushToast(player, "Feral waves are rushing your reef!", "bad")
	task.spawn(runSurgeWaves, surge)
end

local function handlePhaseChanged(phase: string)
	if phase == TidePhase.High then
		for _, player in ipairs(Players:GetPlayers()) do
			beginSurge(player)
		end
	elseif phase == TidePhase.Falling then
		-- High ended with waves still standing: every open surge fails
		-- now and pays out in salvage instead.
		for _, surge in pairs(surges) do
			if surge.failReason == nil then
				surge.failReason = "tide"
			end
		end
	elseif phase == TidePhase.Low then
		-- Uncollected piles wash away when the Falling phase ends.
		clearAllSalvagePiles()
	end
end

local function onHeartbeat(deltaTime: number)
	if activeSurgeCount == 0 then
		return
	end

	local currentDependencies = dependencies
	if currentDependencies == nil then
		return
	end

	local now = os.clock()
	for _, surge in pairs(surges) do
		stepSurge(surge, deltaTime, now, currentDependencies)
	end
end

--[[
	One deflect tap. The server, not the client button, owns the
	cooldown, so a hacked client firing DeflectTap every frame gains
	nothing. A lit Sparker converts the tap into its detonation;
	otherwise the tap shoves and chips enemies around the character.
]]
function SurgeService.handleDeflect(player: Player)
	local currentDependencies = dependencies
	if currentDependencies == nil then
		return
	end

	local cooldown = math.max(
		TidetownConfig.surge.deflect.cooldownSeconds
			- currentDependencies.upgradeLevel(player, "deflectCharm")
				* DEFLECT_COOLDOWN_CUT_SECONDS,
		MINIMUM_DEFLECT_COOLDOWN_SECONDS
	)
	local now = os.clock()
	local lastDeflect = lastDeflectClockByPlayer[player] or 0
	if now - lastDeflect < cooldown then
		return
	end

	lastDeflectClockByPlayer[player] = now

	local surge = surges[player]
	if surge == nil or not surge.active or surge.failReason ~= nil then
		return
	end

	local sparked = false
	for _, sparker in ipairs(surge.sparkers) do
		if sparker.ready then
			sparked = true
			sparker.ready = false
			sparker.chargeRemaining = sparker.chargeSeconds

			for _, enemy in ipairs(surge.enemyPool) do
				local inRange = (enemy.position - surge.barrierPosition).Magnitude
					<= sparker.radiusStuds
				if enemy.alive and inRange then
					enemy.health -= sparker.burstDamage
				end
			end
		end
	end

	if sparked then
		surge.engaged = true

		return
	end

	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return
	end

	local deflect = TidetownConfig.surge.deflect
	local rootPosition = root.Position
	local hitAny = false

	for _, enemy in ipairs(surge.enemyPool) do
		if enemy.alive and (enemy.position - rootPosition).Magnitude <= deflect.radiusStuds then
			enemy.health -= deflect.damage

			-- Knocked seaward, never past the spawn line, and back off
			-- the barrier so it has to march in again.
			local pushedX = math.max(enemy.position.X - deflect.knockbackStuds, surge.spawnX)
			enemy.position = Vector3.new(pushedX, enemy.position.Y, enemy.position.Z)
			enemy.reachedBarrier = false
			hitAny = true
		end
	end

	-- Engagement requires a LANDED deflect: swinging at empty water
	-- does not unlock the full Stormglass payout.
	if hitAny then
		surge.engaged = true
	end
end

function SurgeService.removePlayer(player: Player)
	lastDeflectClockByPlayer[player] = nil

	local surge = surges[player]
	if surge ~= nil then
		surges[player] = nil
		activeSurgeCount -= 1
		surge.active = false
		surge.container:Destroy()
	end

	-- A leaver's piles can never be collected, so they go now instead
	-- of waiting for the tide.
	for index = #salvagePiles, 1, -1 do
		local pile = salvagePiles[index]
		if pile.owner == player then
			if pile.connection ~= nil then
				pile.connection:Disconnect()
			end

			pile.part:Destroy()
			table.remove(salvagePiles, index)
		end
	end
end

function SurgeService.start(startDependencies: Dependencies)
	if started then
		return
	end
	started = true

	dependencies = startDependencies
	startDependencies.onPhaseChanged(handlePhaseChanged)
	RunService.Heartbeat:Connect(onHeartbeat)
end

return SurgeService
