--[[
	Pet inventories, egg hatching, mutations, nicknames, equipping, and
	the floating follower you see beside each owner. The equipped pet's
	growth bonus is published as the PetGrowthBonus attribute so
	SizeService reads it without depending on this module; the full
	inventory and nickname map are published as JSON attributes for the
	backpack UI.

	Pets are identified to clients by their inventory index, not their
	id: duplicates of the same pet are separate creatures that can carry
	different nicknames.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")

local Server = script.Parent
local EconomyService = require(Server.EconomyService)
local QuestService = require(Server.QuestService)

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local PetCatalog = require(Shared.PetCatalog)
local PetModels = require(Shared.PetModels)

local FOLLOW_OFFSET = Vector3.new(3.5, 2, 2)

local NICKNAME_MINIMUM_LENGTH = 2
local NICKNAME_MAXIMUM_LENGTH = 20

local petsByPlayer: { [Player]: { string } } = {}
local nicknamesByPlayer: { [Player]: { [string]: string } } = {}
local equippedIndexByPlayer: { [Player]: number } = {}
local followerByPlayer: { [Player]: Model } = {}

local PetService = {}

local function equippedId(player: Player): string?
	local pets = petsByPlayer[player]
	local index = equippedIndexByPlayer[player]
	if pets == nil or index == nil then
		return nil
	end

	return pets[index]
end

local function nicknameFor(player: Player, petIndex: number): string?
	local nicknames = nicknamesByPlayer[player]

	return if nicknames ~= nil then nicknames[tostring(petIndex)] else nil
end

local function publishInventory(player: Player)
	player:SetAttribute("PetsJson", HttpService:JSONEncode(petsByPlayer[player] or {}))
	player:SetAttribute("PetNamesJson", HttpService:JSONEncode(nicknamesByPlayer[player] or {}))
	player:SetAttribute("EquippedPetIndex", equippedIndexByPlayer[player] or 0)

	local info = PetCatalog.infoFor(equippedId(player) or "")
	player:SetAttribute("PetGrowthBonus", if info ~= nil then info.bonus else 0)
end

local function destroyFollower(player: Player)
	local follower = followerByPlayer[player]
	if follower ~= nil then
		follower:Destroy()
		followerByPlayer[player] = nil
	end
end

--[[
	The follower's name tag: the nickname (or species) on top, the
	species and tier below, and -- when the pet is mutated -- a third
	line in the mutation's color, matching the backpack card layout.
]]
local function buildNameTag(parent: BasePart, info: PetCatalog.PetInfo, nickname: string?)
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
end

--[[
	Spawns the pet's real model beside its owner: every part welded to
	the primary part, unanchored and massless, with the body steered by
	physics constraints so the pet trails naturally as the player moves.
]]
local function createFollower(player: Player, petIndex: number)
	destroyFollower(player)

	local pets = petsByPlayer[player]
	local petId = if pets ~= nil then pets[petIndex] else nil
	local info = PetCatalog.infoFor(petId or "")
	local character = player.Character
	if petId == nil or info == nil or character == nil then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil then
		return
	end

	local model = PetModels.build(petId)
	local body = if model ~= nil then model.PrimaryPart else nil
	if model == nil or body == nil then
		return
	end

	model.Name = "PetFollower"
	model:PivotTo(rootPart.CFrame * CFrame.new(FOLLOW_OFFSET))

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			if part ~= body then
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

	local characterAttachment = Instance.new("Attachment")
	characterAttachment.Name = "PetAnchor"
	characterAttachment.Position = FOLLOW_OFFSET
	characterAttachment.Parent = rootPart

	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Attachment0 = attachment
	alignPosition.Attachment1 = characterAttachment
	alignPosition.MaxForce = 40000
	alignPosition.Responsiveness = 12
	alignPosition.Parent = body

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Attachment0 = attachment
	alignOrientation.Attachment1 = characterAttachment
	alignOrientation.MaxTorque = 40000
	alignOrientation.Responsiveness = 12
	alignOrientation.Parent = body

	buildNameTag(body, info, nicknameFor(player, petIndex))

	model.Parent = character
	followerByPlayer[player] = model
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

-- Wired as HatchEgg.OnServerInvoke; hatches the CURRENT world's coin egg.
function PetService.hatchEgg(player: Player): (boolean, any)
	local worldIndex = player:GetAttribute("CurrentWorld")
	if typeof(worldIndex) ~= "number" or GameConfig.worlds[worldIndex] == nil then
		return false, "Try again in a moment."
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

	EconomyService.spendForEgg(player, world.eggCost)
	local petIndex = PetService.grantPet(player, hatchedId)
	QuestService.increment(player, "eggsHatched")

	return true, { petId = hatchedId, petIndex = petIndex }
end

-- Wired as EquipPet.OnServerInvoke; equips by inventory index, 0 unequips.
function PetService.equipPet(player: Player, petIndex: any): (boolean, string)
	if petIndex == 0 or petIndex == "" then
		equippedIndexByPlayer[player] = nil
		destroyFollower(player)
		publishInventory(player)

		return true, "Pet unequipped."
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

	equippedIndexByPlayer[player] = petIndex
	createFollower(player, petIndex)
	publishInventory(player)

	local shownName = nicknameFor(player, petIndex) or info.name

	return true, string.format("%s equipped: +%d%% growth!", shownName, info.bonus * 100)
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
	if equippedIndexByPlayer[player] == petIndex then
		createFollower(player, petIndex)
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
	equippedPet: string
)
	petsByPlayer[player] = pets
	nicknamesByPlayer[player] = petNames

	-- Saves store the equipped pet as an id; the first owned copy wins.
	if equippedPet ~= "" then
		local savedIndex = table.find(pets, equippedPet)
		if savedIndex ~= nil then
			equippedIndexByPlayer[player] = savedIndex
		end
	end

	publishInventory(player)

	player.CharacterAdded:Connect(function()
		local equipped = equippedIndexByPlayer[player]
		if equipped ~= nil then
			-- Wait for the rig so the follower has a root to align to.
			task.delay(1, createFollower, player, equipped)
		end
	end)

	local equipped = equippedIndexByPlayer[player]
	if equipped ~= nil and player.Character ~= nil then
		createFollower(player, equipped)
	end
end

function PetService.snapshot(player: Player): ({ string }?, string?, { [string]: string }?)
	return petsByPlayer[player], equippedId(player) or "", nicknamesByPlayer[player]
end

function PetService.removePlayer(player: Player)
	petsByPlayer[player] = nil
	nicknamesByPlayer[player] = nil
	equippedIndexByPlayer[player] = nil
	followerByPlayer[player] = nil
end

return PetService
