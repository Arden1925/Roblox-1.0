--[[
	Owns each player's kept creatures: the inventory, the equipped
	companion follower, and the three-slot defense team. Creatures only
	enter the inventory through grantCreature (eggs and the rescue
	starter -- catches feed the Tidepedia, never this list), so this
	service is the single authority on what a player owns, and every
	remote-facing mutation validates its arguments before touching
	state.

	The companion follower is a fully anchored model steered by ONE
	Heartbeat connection for the whole service: each frame every
	follower lerps toward a point behind-left of its owner with a
	gentle sine bob, which reads as swimming without any physics cost.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")

local TidetownShared = ReplicatedStorage.TidetownShared
local CreatureCatalog = require(TidetownShared.CreatureCatalog)
local CreatureModels = require(TidetownShared.CreatureModels)
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

local NICKNAME_MINIMUM_LENGTH = 2
local NICKNAME_MAXIMUM_LENGTH = 20
local FOLLOWER_SIDE_OFFSET_STUDS = -3
local FOLLOWER_BACK_OFFSET_STUDS = -2
local FOLLOWER_HEIGHT_OFFSET_STUDS = 2.5
local FOLLOWER_LERP_ALPHA = 0.15
local BOB_STUDS = 0.3
local BOB_RADIANS_PER_SECOND = 2.2
local RESCUE_POSITION = Vector3.new(0, 3.5, 20)
local STARTER_SPECIES_KEY = "axolotl"
local STARTER_EGG_KEY = "beachEgg"

export type CreatureRecord = {
	uid: string,
	species: string,
	nickname: string,
	caughtAt: number,
}

type PlayerState = {
	creatures: { CreatureRecord },
	companionUid: string,
	defenseTeam: { string },
	nextUid: number,
}

type FollowerRecord = {
	model: Model,
	bobPhase: number,
}

type Dependencies = {
	isReefPlaced: (Player, string) -> boolean,
	grantEgg: (Player, string) -> boolean,
	pushToast: (Player, string, string?) -> (),
}

local CreatureService = {}

local statesByPlayer: { [Player]: PlayerState } = {}
local followersByPlayer: { [Player]: FollowerRecord } = {}
local dependencies: Dependencies? = nil
local syncStateRemote: RemoteEvent? = nil
local bobClock = 0

local function copyCreature(record: CreatureRecord): CreatureRecord
	return {
		uid = record.uid,
		species = record.species,
		nickname = record.nickname,
		caughtAt = record.caughtAt,
	}
end

local function copyCreatureList(list: { CreatureRecord }): { CreatureRecord }
	local copy = {}
	for _, record in ipairs(list) do
		table.insert(copy, copyCreature(record))
	end

	return copy
end

local function copyStringList(list: { string }): { string }
	local copy = {}
	for _, value in ipairs(list) do
		table.insert(copy, value)
	end

	return copy
end

-- The name a follower tag and team card show: the player's nickname
-- when one is set, the species' display name otherwise.
local function displayNameFor(record: CreatureRecord): string
	if record.nickname ~= "" then
		return record.nickname
	end

	local species = CreatureCatalog.speciesFor(record.species)

	return if species ~= nil then species.name else record.species
end

--[[
	Sends the player's full creature slice to their client. Called
	after every mutation so the client never has to ask.
]]
function CreatureService.pushState(player: Player)
	local state = statesByPlayer[player]
	if state == nil or syncStateRemote == nil then
		return
	end

	syncStateRemote:FireClient(player, "creatures", {
		creatures = copyCreatureList(state.creatures),
		companionUid = state.companionUid,
		defenseTeam = copyStringList(state.defenseTeam),
	})
end

function CreatureService.creatureByUid(player: Player, uid: string): CreatureRecord?
	local state = statesByPlayer[player]
	if state == nil then
		return nil
	end

	for _, record in ipairs(state.creatures) do
		if record.uid == uid then
			return record
		end
	end

	return nil
end

local function destroyFollower(player: Player)
	local follower = followersByPlayer[player]
	if follower == nil then
		return
	end

	followersByPlayer[player] = nil
	follower.model:Destroy()
end

local function buildNameTag(model: Model, record: CreatureRecord)
	local primaryPart = model.PrimaryPart
	if primaryPart == nil then
		return
	end

	local species = CreatureCatalog.speciesFor(record.species)
	local rarity = if species ~= nil then species.rarity else "common"

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameTag"
	billboard.Size = UDim2.new(0, 120, 0, 22)
	billboard.StudsOffset = Vector3.new(0, 1.8, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 45
	billboard.Adornee = primaryPart

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = displayNameFor(record)
	label.TextColor3 = CreatureCatalog.rarityColor(rarity)
	label.TextStrokeTransparency = 0.4
	label.TextSize = 14
	label.Parent = billboard

	billboard.Parent = primaryPart
end

--[[
	Spawns (or replaces) the anchored follower model for a creature.
	The model starts at its target spot when the character exists so
	the first lerp frame never drags it across the map.
]]
local function spawnFollower(player: Player, record: CreatureRecord)
	destroyFollower(player)

	local model = CreatureModels.build(record.species, TidetownConfig.creatures.followerHeightStuds)
	model.Name = "CompanionFollower"
	buildNameTag(model, record)

	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root ~= nil and root:IsA("BasePart") then
		local rootCFrame = root.CFrame
		local offset = rootCFrame.RightVector * FOLLOWER_SIDE_OFFSET_STUDS
			+ rootCFrame.LookVector * FOLLOWER_BACK_OFFSET_STUDS
			+ Vector3.new(0, FOLLOWER_HEIGHT_OFFSET_STUDS, 0)
		model:PivotTo(rootCFrame.Rotation + (rootCFrame.Position + offset))
	end

	model.Parent = Workspace

	followersByPlayer[player] = {
		model = model,
		-- A random phase keeps a crowd of followers from bobbing in
		-- eerie unison.
		bobPhase = math.random() * math.pi * 2,
	}
end

function CreatureService.initializePlayer(
	player: Player,
	creatures: { CreatureRecord },
	companionUid: string,
	defenseTeam: { string },
	nextUid: number
)
	-- Copied so this service owns its slice outright instead of
	-- aliasing the loaded PlayerData table.
	local state: PlayerState = {
		creatures = copyCreatureList(creatures),
		companionUid = companionUid,
		defenseTeam = copyStringList(defenseTeam),
		nextUid = nextUid,
	}
	statesByPlayer[player] = state

	-- A saved companion uid may point at a creature that no longer
	-- exists (defensive against hand-edited saves); drop it quietly.
	local companion = CreatureService.creatureByUid(player, state.companionUid)
	if companion ~= nil then
		spawnFollower(player, companion)
	else
		state.companionUid = ""
	end

	CreatureService.pushState(player)
end

function CreatureService.snapshot(
	player: Player
): ({ CreatureRecord }?, string?, { string }?, number?)
	local state = statesByPlayer[player]
	if state == nil then
		return nil, nil, nil, nil
	end

	-- Copied so the save snapshot cannot alias live state that a later
	-- mutation could change mid-save.
	return copyCreatureList(state.creatures),
		state.companionUid,
		copyStringList(state.defenseTeam),
		state.nextUid
end

function CreatureService.removePlayer(player: Player)
	destroyFollower(player)
	statesByPlayer[player] = nil
end

--[[
	Adds one creature of the species to the player's inventory and
	returns its new uid, or nil when the species is unknown or the
	player has no state yet. Eggs and the rescue starter call this;
	nothing else creates creatures.
]]
function CreatureService.grantCreature(player: Player, speciesKey: string): string?
	local state = statesByPlayer[player]
	if state == nil or CreatureCatalog.speciesFor(speciesKey) == nil then
		return nil
	end

	local uid = "c" .. state.nextUid
	state.nextUid += 1

	table.insert(state.creatures, {
		uid = uid,
		species = speciesKey,
		nickname = "",
		caughtAt = os.time(),
	})

	CreatureService.pushState(player)

	return uid
end

--[[
	Equips (or, with "", unequips) the follower companion. Remote
	handler, so the uid is untrusted until proven owned.
]]
function CreatureService.equipCompanion(player: Player, uid: any): (boolean, any)
	local state = statesByPlayer[player]
	if state == nil then
		return false, "Not ready"
	end

	if typeof(uid) ~= "string" then
		return false, "That creature is not yours"
	end

	if uid == "" then
		destroyFollower(player)
		state.companionUid = ""
		CreatureService.pushState(player)

		return true, ""
	end

	local record = CreatureService.creatureByUid(player, uid)
	if record == nil then
		return false, "That creature is not yours"
	end

	spawnFollower(player, record)
	state.companionUid = uid
	CreatureService.pushState(player)

	return true, uid
end

--[[
	Replaces the defense team from the untrusted SetDefenseTeam remote.
	Only the array part of the table is read, so smuggled dictionary
	keys are ignored rather than validated.
]]
function CreatureService.setDefenseTeam(player: Player, uids: any): (boolean, any)
	local state = statesByPlayer[player]
	if state == nil then
		return false, "Not ready"
	end

	if typeof(uids) ~= "table" then
		return false, "Invalid team"
	end

	local team: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, uid in ipairs(uids) do
		if #team >= TidetownConfig.creatures.defenseTeamSize then
			return false, "Your team can only hold three"
		end

		if typeof(uid) ~= "string" or seen[uid] then
			return false, "Invalid team"
		end

		if CreatureService.creatureByUid(player, uid) == nil then
			return false, "That creature is not yours"
		end

		if dependencies ~= nil and dependencies.isReefPlaced(player, uid) then
			return false, "That creature is busy in your reef"
		end

		seen[uid] = true
		table.insert(team, uid)
	end

	state.defenseTeam = team
	CreatureService.pushState(player)

	return true, copyStringList(team)
end

--[[
	Renames a creature through the platform text filter. The filtered
	text is what gets stored, so a partially censored name sticks with
	its hashtags rather than being rejected.
]]
function CreatureService.renameCreature(player: Player, uid: any, name: any): (boolean, any)
	local state = statesByPlayer[player]
	if state == nil then
		return false, "Not ready"
	end

	if typeof(uid) ~= "string" then
		return false, "That creature is not yours"
	end

	local record = CreatureService.creatureByUid(player, uid)
	if record == nil then
		return false, "That creature is not yours"
	end

	if typeof(name) ~= "string" then
		return false, "That name will not work"
	end

	local trimmed = string.match(name, "^%s*(.-)%s*$") :: string
	if #trimmed < NICKNAME_MINIMUM_LENGTH or #trimmed > NICKNAME_MAXIMUM_LENGTH then
		return false,
			string.format(
				"Names must be %d-%d characters",
				NICKNAME_MINIMUM_LENGTH,
				NICKNAME_MAXIMUM_LENGTH
			)
	end

	if string.match(trimmed, "%c") ~= nil then
		return false, "That name will not work"
	end

	local finalName = trimmed
	if not RunService:IsStudio() then
		-- FilterStringAsync throws on moderation outages and in
		-- unpublished games; treat any failure as "cannot verify",
		-- never as "allowed".
		local filterOk, filtered = pcall(function()
			local result = TextService:FilterStringAsync(trimmed, player.UserId)

			return result:GetNonChatStringForBroadcastAsync()
		end)

		if not filterOk or typeof(filtered) ~= "string" then
			return false, "Naming is unavailable right now -- try again soon"
		end

		finalName = filtered
	end

	record.nickname = finalName

	-- A renamed equipped companion gets its name tag rebuilt so the
	-- floating tag never shows a stale name.
	if state.companionUid == uid then
		spawnFollower(player, record)
	end

	CreatureService.pushState(player)

	return true, finalName
end

--[[
	The combat-relevant stats of the current defense team, resolved
	through the catalog so SurgeService never needs to know about
	inventories. Unknown species (defensive) are skipped.
]]
function CreatureService.defenseTeamStats(player: Player): {
	{
		uid: string,
		speciesKey: string,
		role: string,
		rarity: string,
		multiplier: number,
	}
}
	local stats = {}
	local state = statesByPlayer[player]
	if state == nil then
		return stats
	end

	for _, uid in ipairs(state.defenseTeam) do
		local record = CreatureService.creatureByUid(player, uid)
		local species = if record ~= nil then CreatureCatalog.speciesFor(record.species) else nil
		if species ~= nil then
			table.insert(stats, {
				uid = uid,
				speciesKey = species.key,
				role = species.role,
				rarity = species.rarity,
				multiplier = CreatureCatalog.rarityMultiplier(species.rarity),
			})
		end
	end

	return stats
end

--[[
	The rescue-starter moment: a brand-new player picks up a stranded
	axolotl, gets it equipped as their companion, and receives a first
	egg. Owning ANY creature means the rescue already happened, so the
	prompt is safely re-triggerable.
]]
function CreatureService.grantStarter(player: Player)
	local state = statesByPlayer[player]
	if state == nil or #state.creatures > 0 then
		return
	end

	local uid = CreatureService.grantCreature(player, STARTER_SPECIES_KEY)
	if uid == nil then
		return
	end

	CreatureService.equipCompanion(player, uid)

	if dependencies ~= nil then
		dependencies.grantEgg(player, STARTER_EGG_KEY)
		dependencies.pushToast(player, "You rescued the little one!", "good")
	end
end

-- The physical rescue point on the dry sand: a glowing little mound
-- with a prompt. MapBuilder's RescueSpot is only decoration; this part
-- is the one that actually grants the starter.
local function buildRescuePrompt()
	local part = Instance.new("Part")
	part.Name = "RescuePoint"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.4, 1.4, 1.4)
	part.CFrame = CFrame.new(RESCUE_POSITION)
	part.Color = Color3.fromRGB(255, 170, 204)
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false

	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = Color3.fromRGB(255, 214, 236)
	sparkles.Parent = part

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Stranded Axolotl"
	prompt.ActionText = "Rescue the stranded axolotl"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(function(triggeringPlayer)
		CreatureService.grantStarter(triggeringPlayer)
	end)

	-- Parented under the map folder when MapBuilder already ran, so a
	-- map teardown in Studio testing takes the prompt with it.
	local mapFolder = Workspace:FindFirstChild("Tidetown")
	part.Parent = if mapFolder ~= nil then mapFolder else Workspace
end

-- The one Heartbeat for every follower: a frame-rate-friendly lerp
-- toward a spot behind-left of the owner, plus a sine bob, keeps the
-- companion feeling alive with zero physics.
local function stepFollowers(deltaSeconds: number)
	bobClock += deltaSeconds

	for player, follower in pairs(followersByPlayer) do
		local character = player.Character
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if root ~= nil and root:IsA("BasePart") then
			local rootCFrame = root.CFrame
			local bob = math.sin((bobClock + follower.bobPhase) * BOB_RADIANS_PER_SECOND)
				* BOB_STUDS
			local offset = rootCFrame.RightVector * FOLLOWER_SIDE_OFFSET_STUDS
				+ rootCFrame.LookVector * FOLLOWER_BACK_OFFSET_STUDS
				+ Vector3.new(0, FOLLOWER_HEIGHT_OFFSET_STUDS + bob, 0)
			local target = rootCFrame.Rotation + (rootCFrame.Position + offset)
			follower.model:PivotTo(follower.model:GetPivot():Lerp(target, FOLLOWER_LERP_ALPHA))
		end
	end
end

--[[
	Wires dependencies, fetches the SyncState remote (yields, which is
	why init calls start from a spawned task), starts the follower
	Heartbeat, and builds the rescue prompt.
]]
function CreatureService.start(dependencyTable: Dependencies)
	dependencies = dependencyTable
	syncStateRemote = TidetownRemotes.get("SyncState") :: RemoteEvent

	RunService.Heartbeat:Connect(stepFollowers)
	buildRescuePrompt()
end

return CreatureService
