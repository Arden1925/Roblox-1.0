--[[
	Pet inventories, egg hatching, mutations, nicknames, equipping, and
	the floating followers you see beside each owner. Up to slotCount
	pets ride along at once (three for everyone, plus a coin-bought
	fourth slot and the ExtraPetSlot game pass); the equipped pets'
	summed growth bonus is published as the PetGrowthBonus attribute so
	SizeService reads it without depending on this module; the full
	inventory, nickname map, and equipped index list are published as
	JSON attributes for the backpack UI.

	Pets are identified to clients by their inventory index, not their
	id: duplicates of the same pet are separate creatures that can carry
	different nicknames.

	Followers scale with their owner: the character's scale (derived
	from the CurrentSize attribute) multiplies each pet's build-time
	scale, so a giant walks with giant pets at matching spacing instead
	of tiny ones drifting ever further away as the anchor offsets scale.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")

local Server = script.Parent
local EconomyService = require(Server.EconomyService)
local QuestService = require(Server.QuestService)
local WorldService = require(Server.WorldService)

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local PetCatalog = require(Shared.PetCatalog)
local PetModels = require(Shared.PetModels)
local SizeFormula = require(Shared.SizeFormula)

-- One anchor spot per equipped slot, in HRP-local studs: right, left,
-- behind, then the two wide flanks for the purchasable slots. Humanoid
-- scaling scales attachment offsets, which is exactly right once the
-- pets themselves scale to match.
local FOLLOW_OFFSETS = {
	Vector3.new(3.5, 2, 2),
	Vector3.new(-3.5, 2, 2),
	Vector3.new(0, 2, 4.5),
	Vector3.new(6, 2.5, 4),
	Vector3.new(-6, 2.5, 4),
}

local NAME_TAG_OFFSET_Y = 2.4
local RESCALE_EPSILON = 0.01
local HATCH_COOLDOWN_SECONDS = 1.5

local NICKNAME_MINIMUM_LENGTH = 2
local NICKNAME_MAXIMUM_LENGTH = 20

-- Owner speed (studs/s) above which a rigged pet swaps Idle for Run.
local RUN_SPEED_THRESHOLD = 4
local ANIMATION_FADE_SECONDS = 0.2
-- The hand-authored float for pets that shipped without animations.
local BOB_STUDS = 0.28
local BOB_SPEED = 2.2

type FollowerRecord = {
	model: Model,
	baseScale: number,
	billboard: BillboardGui,
	anchorName: string,
	appliedScale: number,
	bodyAttachment: Attachment,
	idleTrack: AnimationTrack?,
	runTrack: AnimationTrack?,
	bobPhase: number,
}

local petsByPlayer: { [Player]: { string } } = {}
local nicknamesByPlayer: { [Player]: { [string]: string } } = {}
local equippedIndicesByPlayer: { [Player]: { number } } = {}
local followersByPlayer: { [Player]: { [number]: FollowerRecord } } = {}
local extraSlotByPlayer: { [Player]: boolean } = {}
local lastHatchAtByPlayer: { [Player]: number } = {}

local PetService = {}

local function slotCount(player: Player): number
	local count = GameConfig.petSlots.base
	if extraSlotByPlayer[player] then
		count += 1
	end
	if player:GetAttribute("OwnsExtraPetSlot") == true then
		count += 1
	end

	return count
end

local function equippedIndices(player: Player): { number }
	local indices = equippedIndicesByPlayer[player]
	if indices == nil then
		indices = {}
		equippedIndicesByPlayer[player] = indices
	end

	return indices
end

-- The character scale the owner is currently rendered at, floored so
-- shrunk players keep readable (not microscopic) pets.
local function characterScaleFor(player: Player): number
	-- On the Main Island everyone is rendered at base size, so their
	-- pets match.
	if player:GetAttribute("InHub") == true then
		return 1
	end

	local currentSize = player:GetAttribute("CurrentSize")
	if typeof(currentSize) ~= "number" then
		return 1
	end

	return math.max(SizeFormula.scaleForSize(currentSize), 0.75)
end

local function nicknameFor(player: Player, petIndex: number): string?
	local nicknames = nicknamesByPlayer[player]

	return if nicknames ~= nil then nicknames[tostring(petIndex)] else nil
end

local function publishInventory(player: Player)
	local pets = petsByPlayer[player] or {}
	local indices = equippedIndices(player)

	player:SetAttribute("PetsJson", HttpService:JSONEncode(pets))
	player:SetAttribute("PetNamesJson", HttpService:JSONEncode(nicknamesByPlayer[player] or {}))
	player:SetAttribute("EquippedPetsJson", HttpService:JSONEncode(indices))
	player:SetAttribute("PetSlots", slotCount(player))

	local totalBonus = 0
	for _, index in ipairs(indices) do
		local info = PetCatalog.infoFor(pets[index] or "")
		if info ~= nil then
			totalBonus += info.bonus
		end
	end
	player:SetAttribute("PetGrowthBonus", totalBonus)
end

local function destroyFollower(player: Player, petIndex: number)
	local followers = followersByPlayer[player]
	local record = if followers ~= nil then followers[petIndex] else nil
	if record == nil then
		return
	end

	record.model:Destroy()
	followers[petIndex] = nil

	-- The anchor attachment lives on the character, not the follower,
	-- so it must be cleaned up separately.
	local character = player.Character
	local rootPart = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if rootPart ~= nil then
		local anchor = rootPart:FindFirstChild(record.anchorName)
		if anchor ~= nil then
			anchor:Destroy()
		end
	end
end

local function destroyAllFollowers(player: Player)
	local followers = followersByPlayer[player]
	if followers == nil then
		return
	end

	for petIndex in pairs(followers) do
		destroyFollower(player, petIndex)
	end
end

--[[
	The follower's name tag: the nickname (or species) on top, the
	species and tier below, and -- when the pet is mutated -- a third
	line in the mutation's color, matching the backpack card layout.
]]
local function buildNameTag(
	parent: BasePart,
	info: PetCatalog.PetInfo,
	nickname: string?
): BillboardGui
	local mutation = info.mutation
	local lineCount = if mutation ~= nil then 3 else 2

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 140, 0, 16 * lineCount + 6)
	billboard.StudsOffset = Vector3.new(0, 2.4, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 45
	billboard.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = billboard

	local function addLine(order: number, text: string, color: Color3, textSize: number)
		local label = Instance.new("TextLabel")
		label.LayoutOrder = order
		label.Size = UDim2.new(1, 0, 0, textSize + 4)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.Text = text
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.4
		label.TextSize = textSize
		label.Parent = billboard
	end

	local title = if nickname ~= nil then nickname else info.baseName
	addLine(1, title, Color3.fromRGB(255, 255, 255), 14)
	addLine(2, string.format("%s (%s)", info.baseName, info.tierName), info.tierColor, 11)
	if mutation ~= nil then
		addLine(3, "\u{2726} " .. string.upper(mutation.name) .. " \u{2726}", mutation.color, 12)
	end

	return billboard
end

--[[
	Rig detection for the pack animals that shipped with animations:
	parts held together by Motor6Ds (or serving as the rig root) must
	NOT be welded to the body, or the welds freeze the joints and the
	animation cannot move anything.
]]
local function collectRiggedParts(model: Model): { [Instance]: boolean }
	local riggedParts: { [Instance]: boolean } = {}

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			if descendant.Part0 ~= nil then
				riggedParts[descendant.Part0] = true
			end
			if descendant.Part1 ~= nil then
				riggedParts[descendant.Part1] = true
			end
		end
	end

	return riggedParts
end

-- Starts the pack's own Idle/Run tracks on a rigged pet. Returns nil
-- tracks for pets without animations; those get the swim-bob instead.
local function startPackAnimations(model: Model): (AnimationTrack?, AnimationTrack?)
	local controller = model:FindFirstChildWhichIsA("AnimationController", true)
	local animator = if controller ~= nil
		then controller:FindFirstChildWhichIsA("Animator")
		else nil
	local animations = model:FindFirstChild("Animations", true)
	if animator == nil or animations == nil then
		return nil, nil
	end

	local function loadTrack(trackName: string): AnimationTrack?
		local animation = animations:FindFirstChild(trackName)
		if animation == nil or not animation:IsA("Animation") then
			return nil
		end

		-- LoadAnimation throws on malformed animation content; a pet
		-- with a broken track should fall back to the bob, not error.
		local loaded, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)

		return if loaded then track else nil
	end

	local idleTrack = loadTrack("Idle")
	local runTrack = loadTrack("Run")
	if idleTrack ~= nil then
		idleTrack.Looped = true
		idleTrack:Play(ANIMATION_FADE_SECONDS)
	end
	if runTrack ~= nil then
		runTrack.Looped = true
	end

	return idleTrack, runTrack
end

--[[
	Spawns one equipped pet's real model beside its owner, steered by
	physics constraints so the pet trails naturally as the player moves.
	Rigged pack animals keep their Motor6D skeletons free and play their
	bundled animations; everything else is welded rigid and floats on
	the heartbeat swim-bob. slotNumber picks the anchor spot, so
	multiple pets fan out around the character instead of stacking.
]]
local function createFollower(player: Player, petIndex: number, slotNumber: number)
	destroyFollower(player, petIndex)

	local offset = FOLLOW_OFFSETS[slotNumber]
	local pets = petsByPlayer[player]
	local petId = if pets ~= nil then pets[petIndex] else nil
	local info = PetCatalog.infoFor(petId or "")
	local character = player.Character
	if offset == nil or petId == nil or info == nil or character == nil then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil then
		return
	end

	local model = PetModels.build(petId)
	if model == nil then
		return
	end

	-- Rigged animals are driven from their rig root so animations sway
	-- the body around a stable core; unrigged pets keep the old
	-- largest-part anchor.
	local riggedParts = collectRiggedParts(model)
	local rigRoot = model:FindFirstChild("RootPart", true)
	local body: BasePart? = nil
	if rigRoot ~= nil and rigRoot:IsA("BasePart") and next(riggedParts) ~= nil then
		riggedParts[rigRoot] = true
		body = rigRoot
		model.PrimaryPart = rigRoot
	else
		riggedParts = {}
		body = model.PrimaryPart
	end
	if body == nil then
		model:Destroy()
		return
	end

	-- Scale the pet to its owner before anything is welded or aligned,
	-- so a giant's pets are giant from the first frame.
	local baseScale = model:GetScale()
	local characterScale = characterScaleFor(player)
	model:ScaleTo(baseScale * characterScale)

	model.Name = "PetFollower"
	model:PivotTo(rootPart.CFrame * CFrame.new(offset))

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			if part ~= body and not riggedParts[part] then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = body
				weld.Part1 = part
				weld.Parent = part
			end

			part.Anchored = false
			part.Massless = true
		end
	end

	local attachment = Instance.new("Attachment")
	attachment.Parent = body

	local anchorName = "PetAnchor" .. slotNumber
	local characterAttachment = Instance.new("Attachment")
	characterAttachment.Name = anchorName
	characterAttachment.Position = offset
	characterAttachment.Parent = rootPart

	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Attachment0 = attachment
	alignPosition.Attachment1 = characterAttachment
	alignPosition.MaxForce = 40000
	alignPosition.Responsiveness = 10
	alignPosition.Parent = body

	-- Softer than the position spring on purpose: the pet leans into
	-- turns and settles instead of snapping to the new heading.
	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Attachment0 = attachment
	alignOrientation.Attachment1 = characterAttachment
	alignOrientation.MaxTorque = 40000
	alignOrientation.Responsiveness = 5
	alignOrientation.Parent = body

	local billboard = buildNameTag(body, info, nicknameFor(player, petIndex))
	billboard.StudsOffset = Vector3.new(0, NAME_TAG_OFFSET_Y * characterScale, 0)

	model.Parent = character

	local idleTrack, runTrack = startPackAnimations(model)

	local followers = followersByPlayer[player]
	if followers == nil then
		followers = {}
		followersByPlayer[player] = followers
	end
	followers[petIndex] = {
		model = model,
		baseScale = baseScale,
		billboard = billboard,
		anchorName = anchorName,
		appliedScale = characterScale,
		bodyAttachment = attachment,
		idleTrack = idleTrack,
		runTrack = runTrack,
		bobPhase = petIndex,
	}
end

-- Tears down and respawns every equipped follower in slot order --
-- the one honest way to keep slots, offsets, and models in sync after
-- any change to the equipped list.
local function rebuildFollowers(player: Player)
	destroyAllFollowers(player)

	for slotNumber, petIndex in ipairs(equippedIndices(player)) do
		createFollower(player, petIndex, slotNumber)
	end
end

-- Follows the owner's size: rescales live followers when the
-- character's scale has moved enough to notice.
local function rescaleFollowers(player: Player)
	local followers = followersByPlayer[player]
	if followers == nil then
		return
	end

	local characterScale = characterScaleFor(player)
	for _, record in pairs(followers) do
		if math.abs(characterScale - record.appliedScale) > RESCALE_EPSILON then
			record.model:ScaleTo(record.baseScale * characterScale)
			record.billboard.StudsOffset = Vector3.new(0, NAME_TAG_OFFSET_Y * characterScale, 0)
			record.appliedScale = characterScale
		end
	end
end

-- Every Ultra-tier pet the wheel jackpot can grant: the royal-egg
-- exclusives, never the limited pet. Returns the pet's display name.
function PetService.grantRandomUltraPet(player: Player): string?
	local pool = {}
	for worldIndex, world in ipairs(GameConfig.worlds) do
		for _, petSpec in ipairs(world.robuxEgg.pets) do
			if petSpec.tier >= 6 then
				table.insert(pool, string.format("r%d:%s", worldIndex, petSpec.name))
			end
		end
	end
	if #pool == 0 then
		return nil
	end

	local petId = pool[math.random(#pool)]
	PetService.grantPet(player, petId)

	local info = PetCatalog.infoFor(petId)

	return if info ~= nil then info.name else petId
end

--[[
	The wheel's mutation reroll: the first equipped pet trades its
	mutation for a fresh guaranteed one, weighted by the normal mutation
	chances so relative rarities still hold. Returns the pet's new full
	name, or nil when nothing is equipped.
]]
function PetService.rerollEquippedPetMutation(player: Player): string?
	local pets = petsByPlayer[player]
	local petIndex = equippedIndices(player)[1]
	if pets == nil or petIndex == nil or pets[petIndex] == nil then
		return nil
	end

	-- Scaling one uniform sample into the combined chance guarantees a
	-- hit somewhere in the list instead of the usual mostly-nothing.
	local totalChance = 0
	for _, spec in ipairs(GameConfig.mutations) do
		totalChance += spec.chance
	end
	local mutationKey = PetCatalog.rollMutation(math.random() * totalChance)
	if mutationKey == nil then
		mutationKey = GameConfig.mutations[#GameConfig.mutations].key
	end

	local newId = PetCatalog.mutatedId(PetCatalog.baseId(pets[petIndex]), mutationKey :: string)
	pets[petIndex] = newId
	rebuildFollowers(player)
	publishInventory(player)

	local info = PetCatalog.infoFor(newId)

	return if info ~= nil then info.name else newId
end

-- Returns the granted pet's inventory index, or nil if the id is bogus.
function PetService.grantPet(player: Player, petId: string): number?
	local pets = petsByPlayer[player]
	if pets == nil or PetCatalog.infoFor(petId) == nil then
		return nil
	end

	table.insert(pets, petId)
	publishInventory(player)

	return #pets
end

--[[
	Wired as HatchEgg.OnServerInvoke; hatches the requested world's coin
	egg. The hatchery on the Main Island sells every world's egg from
	one row of capsules, so the world comes from the stand the player
	used -- gated by the world they have genuinely reached on foot.
]]
function PetService.hatchEgg(player: Player, requestedWorld: any): (boolean, any)
	-- One egg at a time: the client locks the UI during the reveal,
	-- and this cooldown backs it up against autoclickers and exploits.
	-- Only a hatch that actually happens arms it, so a player short on
	-- coins keeps getting the honest cost message.
	local now = os.clock()
	local lastHatchAt = lastHatchAtByPlayer[player]
	if lastHatchAt ~= nil and now - lastHatchAt < HATCH_COOLDOWN_SECONDS then
		return false, "One egg at a time!"
	end

	local worldIndex = requestedWorld
	if typeof(worldIndex) ~= "number" then
		worldIndex = player:GetAttribute("CurrentWorld")
	end
	if typeof(worldIndex) ~= "number" or GameConfig.worlds[worldIndex] == nil then
		return false, "Try again in a moment."
	end

	local reached = WorldService.reachedWorld(player)
	if reached ~= nil and worldIndex > reached then
		return false,
			string.format("Reach %s on foot to unlock its egg!", GameConfig.worlds[worldIndex].name)
	end

	local world = GameConfig.worlds[worldIndex]
	local coins = player:GetAttribute("Coins")
	if typeof(coins) ~= "number" or coins < world.eggCost then
		return false, string.format("The %s costs %d coins.", world.eggName, world.eggCost)
	end

	-- Luck skews the top slot's weight: rebirth luck is personal, the
	-- Server Luck Boost (a workspace attribute) lifts everyone at once.
	local luckMultiplier = 1
	local rebirths = player:GetAttribute("Rebirths")
	if typeof(rebirths) == "number" then
		luckMultiplier += rebirths * GameConfig.rebirth.luckPerRebirth
	end

	local serverLuckUntil = Workspace:GetAttribute("ServerLuckUntil")
	if typeof(serverLuckUntil) == "number" and serverLuckUntil > Workspace:GetServerTimeNow() then
		luckMultiplier *= GameConfig.serverLuck.weightMultiplier
	end

	local pool = PetCatalog.coinEggPool(worldIndex)
	pool[#pool].weight *= luckMultiplier

	local totalWeight = 0
	for _, entry in ipairs(pool) do
		totalWeight += entry.weight
	end

	local roll = math.random() * totalWeight
	local hatchedId = pool[#pool].id
	for _, entry in ipairs(pool) do
		roll -= entry.weight
		if roll <= 0 then
			hatchedId = entry.id
			break
		end
	end

	-- The mutation roll layers on top of whatever rarity was hatched.
	local mutationKey = PetCatalog.rollMutation(math.random())
	if mutationKey ~= nil then
		hatchedId = PetCatalog.mutatedId(hatchedId, mutationKey)
	end

	lastHatchAtByPlayer[player] = now
	EconomyService.spendForEgg(player, world.eggCost)
	local petIndex = PetService.grantPet(player, hatchedId)
	QuestService.increment(player, "eggsHatched")

	return true, { petId = hatchedId, petIndex = petIndex }
end

--[[
	Wired as EquipPet.OnServerInvoke. Toggles by inventory index: an
	equipped pet unequips, an unequipped one takes the next free slot
	(if any). 0 clears every slot at once.
]]
function PetService.equipPet(player: Player, petIndex: any): (boolean, string)
	if petIndex == 0 or petIndex == "" then
		equippedIndicesByPlayer[player] = {}
		destroyAllFollowers(player)
		publishInventory(player)

		return true, "All pets unequipped."
	end

	local pets = petsByPlayer[player]
	if typeof(petIndex) ~= "number" or pets == nil then
		return false, "Try again in a moment."
	end

	local petId = pets[petIndex]
	local info = PetCatalog.infoFor(petId or "")
	if petId == nil or info == nil then
		return false, "You do not own that pet."
	end

	local indices = equippedIndices(player)
	local alreadyAt = table.find(indices, petIndex)
	if alreadyAt ~= nil then
		table.remove(indices, alreadyAt)
		rebuildFollowers(player)
		publishInventory(player)

		local shownName = nicknameFor(player, petIndex) or info.name

		return true, string.format("%s unequipped.", shownName)
	end

	local capacity = slotCount(player)
	if #indices >= capacity then
		return false, string.format("All %d pet slots are full -- unequip one first!", capacity)
	end

	table.insert(indices, petIndex)
	rebuildFollowers(player)
	publishInventory(player)

	local shownName = nicknameFor(player, petIndex) or info.name

	return true, string.format("%s equipped: +%d%% growth!", shownName, info.bonus * 100)
end

-- Wired as BuyPetSlot.OnServerInvoke: the coin-bought fourth slot.
function PetService.buyPetSlot(player: Player): (boolean, string)
	if extraSlotByPlayer[player] then
		return false, "You already own the coin pet slot!"
	end

	local cost = GameConfig.petSlots.coinSlotCost
	if not EconomyService.spendCoins(player, cost) then
		return false, string.format("The extra pet slot costs %d coins.", cost)
	end

	extraSlotByPlayer[player] = true
	publishInventory(player)

	return true, string.format("Pet slot unlocked -- you can now equip %d!", slotCount(player))
end

--[[
	Wired as RenamePet.OnServerInvoke. Names pass through Roblox's text
	filter before they are stored; a name the filter would censor is
	rejected outright rather than saved full of hashtags. Studio test
	sessions skip the filter because it only works in published games.
]]
function PetService.renamePet(player: Player, petIndex: any, requestedName: any): (boolean, string)
	local pets = petsByPlayer[player]
	if typeof(petIndex) ~= "number" or pets == nil or pets[petIndex] == nil then
		return false, "You do not own that pet."
	end

	if typeof(requestedName) ~= "string" then
		return false, "That name will not work."
	end

	local trimmed = string.match(requestedName, "^%s*(.-)%s*$") :: string
	if #trimmed < NICKNAME_MINIMUM_LENGTH or #trimmed > NICKNAME_MAXIMUM_LENGTH then
		return false,
			string.format(
				"Names must be %d-%d characters.",
				NICKNAME_MINIMUM_LENGTH,
				NICKNAME_MAXIMUM_LENGTH
			)
	end

	if string.match(trimmed, "%c") ~= nil then
		return false, "That name will not work."
	end

	if not RunService:IsStudio() then
		-- FilterStringAsync throws on outages and in unpublished games;
		-- treat any failure as "cannot verify", never as "allowed".
		local filterOk, filtered = pcall(function()
			local result = TextService:FilterStringAsync(trimmed, player.UserId)

			return result:GetNonChatStringForBroadcastAsync()
		end)

		if not filterOk then
			return false, "Naming is unavailable right now -- try again soon."
		end

		if filtered ~= trimmed then
			return false, "That name is not allowed."
		end
	end

	local nicknames = nicknamesByPlayer[player]
	if nicknames == nil then
		return false, "Try again in a moment."
	end

	nicknames[tostring(petIndex)] = trimmed
	publishInventory(player)

	-- A renamed equipped pet gets its name tag rebuilt immediately.
	local slotNumber = table.find(equippedIndices(player), petIndex)
	if slotNumber ~= nil then
		createFollower(player, petIndex, slotNumber)
	end

	return true, string.format("Named your pet %s!", trimmed)
end

function PetService.grantRobuxEggPet(player: Player, worldIndex: number)
	local pool = PetCatalog.robuxEggPool(worldIndex)
	PetService.grantPet(player, pool[math.random(#pool)])
end

function PetService.grantLimitedPet(player: Player)
	PetService.grantPet(player, PetCatalog.limitedPetId())
end

function PetService.initializePlayer(
	player: Player,
	pets: { string },
	petNames: { [string]: string },
	equippedPets: { string },
	extraSlotBought: boolean
)
	petsByPlayer[player] = pets
	nicknamesByPlayer[player] = petNames
	extraSlotByPlayer[player] = extraSlotBought

	-- Saves store equipped pets as ids; each id claims its first
	-- still-unclaimed copy, so duplicate species resolve to distinct
	-- inventory indices. Anything past the slot cap is dropped.
	local indices = equippedIndices(player)
	local claimed: { [number]: boolean } = {}
	for _, savedId in ipairs(equippedPets) do
		if #indices >= slotCount(player) then
			break
		end

		for index, ownedId in ipairs(pets) do
			if ownedId == savedId and not claimed[index] then
				claimed[index] = true
				table.insert(indices, index)
				break
			end
		end
	end

	publishInventory(player)

	player.CharacterAdded:Connect(function()
		-- Wait for the rig so the followers have a root to align to.
		task.delay(1, rebuildFollowers, player)
	end)

	if player.Character ~= nil then
		rebuildFollowers(player)
	end

	-- Followers grow and shrink with their owner, and drop to base
	-- size alongside them on the Main Island.
	player:GetAttributeChangedSignal("CurrentSize"):Connect(function()
		rescaleFollowers(player)
	end)
	player:GetAttributeChangedSignal("InHub"):Connect(function()
		rescaleFollowers(player)
	end)

	-- Buying the ExtraPetSlot pass mid-session bumps the published
	-- slot count immediately.
	player:GetAttributeChangedSignal("OwnsExtraPetSlot"):Connect(function()
		publishInventory(player)
	end)
end

function PetService.snapshot(
	player: Player
): ({ string }?, { string }?, { [string]: string }?, boolean)
	local pets = petsByPlayer[player]
	if pets == nil then
		return nil, nil, nil, false
	end

	local equippedIds = {}
	for _, index in ipairs(equippedIndices(player)) do
		local petId = pets[index]
		if petId ~= nil then
			table.insert(equippedIds, petId)
		end
	end

	return pets, equippedIds, nicknamesByPlayer[player], extraSlotByPlayer[player] == true
end

function PetService.removePlayer(player: Player)
	petsByPlayer[player] = nil
	nicknamesByPlayer[player] = nil
	equippedIndicesByPlayer[player] = nil
	followersByPlayer[player] = nil
	extraSlotByPlayer[player] = nil
	lastHatchAtByPlayer[player] = nil
end

--[[
	One heartbeat keeps every follower alive: rigged pack animals swap
	between their bundled Idle and Run tracks with the owner's speed,
	and pets without animations ride a gentle sine bob on their body
	attachment -- so nothing ever floats frozen.
]]
function PetService.start()
	local bobClock = 0

	RunService.Heartbeat:Connect(function(deltaSeconds)
		bobClock += deltaSeconds

		for player, followers in pairs(followersByPlayer) do
			local character = player.Character
			local characterRoot = if character ~= nil
				then character:FindFirstChild("HumanoidRootPart")
				else nil
			local speed = 0
			if characterRoot ~= nil and characterRoot:IsA("BasePart") then
				speed = characterRoot.AssemblyLinearVelocity.Magnitude
			end

			for _, record in pairs(followers) do
				local idleTrack = record.idleTrack
				local runTrack = record.runTrack
				if idleTrack ~= nil and runTrack ~= nil then
					if speed > RUN_SPEED_THRESHOLD and not runTrack.IsPlaying then
						runTrack:Play(ANIMATION_FADE_SECONDS)
						idleTrack:Stop(ANIMATION_FADE_SECONDS)
					elseif speed <= RUN_SPEED_THRESHOLD and not idleTrack.IsPlaying then
						idleTrack:Play(ANIMATION_FADE_SECONDS)
						runTrack:Stop(ANIMATION_FADE_SECONDS)
					end
				elseif idleTrack == nil then
					record.bodyAttachment.Position = Vector3.new(
						0,
						math.sin((bobClock + record.bobPhase) * BOB_SPEED)
							* -BOB_STUDS
							* record.appliedScale,
						0
					)
				end
			end
		end
	end)
end

return PetService
