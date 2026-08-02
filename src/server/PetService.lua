--[[
	Pet inventories, egg hatching, equipping, and the floating follower
	you see beside each owner. The equipped pet's growth bonus is
	published as the PetGrowthBonus attribute so SizeService reads it
	without depending on this module; the full inventory is published as
	a JSON attribute for the backpack UI.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = script.Parent
local EconomyService = require(Server.EconomyService)

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local PetCatalog = require(Shared.PetCatalog)
local PetModels = require(Shared.PetModels)

local FOLLOW_OFFSET = Vector3.new(3.5, 2, 2)

local petsByPlayer: { [Player]: { string } } = {}
local equippedByPlayer: { [Player]: string } = {}
local followerByPlayer: { [Player]: Model } = {}

local PetService = {}

local function publishInventory(player: Player)
	player:SetAttribute("PetsJson", HttpService:JSONEncode(petsByPlayer[player] or {}))
	player:SetAttribute("EquippedPet", equippedByPlayer[player] or "")

	local info = PetCatalog.infoFor(equippedByPlayer[player] or "")
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
	Spawns the pet's real model beside its owner: every part welded to
	the body, unanchored and massless, with the body steered by physics
	constraints so the pet trails naturally as the player moves.
]]
local function createFollower(player: Player, petId: string)
	destroyFollower(player)

	local info = PetCatalog.infoFor(petId)
	local character = player.Character
	if info == nil or character == nil then
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

	local body = model.PrimaryPart :: BasePart
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

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 120, 0, 34)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 45
	billboard.Parent = body

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = string.format("%s\n(%s)", info.name, info.tierName)
	nameLabel.TextColor3 = info.tierColor
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.TextSize = 12
	nameLabel.Parent = billboard

	model.Parent = character
	followerByPlayer[player] = model
end

function PetService.grantPet(player: Player, petId: string)
	local pets = petsByPlayer[player]
	if pets == nil or PetCatalog.infoFor(petId) == nil then
		return
	end

	table.insert(pets, petId)
	publishInventory(player)
end

-- Wired as HatchEgg.OnServerInvoke; hatches the CURRENT world's coin egg.
function PetService.hatchEgg(player: Player): (boolean, string)
	local worldIndex = player:GetAttribute("CurrentWorld")
	if typeof(worldIndex) ~= "number" or GameConfig.worlds[worldIndex] == nil then
		return false, "Try again in a moment."
	end

	local world = GameConfig.worlds[worldIndex]
	local coins = player:GetAttribute("Coins")
	if typeof(coins) ~= "number" or coins < world.eggCost then
		return false, string.format("The %s costs %d coins.", world.eggName, world.eggCost)
	end

	local pool = PetCatalog.coinEggPool(worldIndex)
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

	EconomyService.spendForEgg(player, world.eggCost)
	PetService.grantPet(player, hatchedId)

	return true, hatchedId
end

-- Wired as EquipPet.OnServerInvoke. An empty id unequips.
function PetService.equipPet(player: Player, petId: any): (boolean, string)
	if petId == "" then
		equippedByPlayer[player] = nil
		destroyFollower(player)
		publishInventory(player)

		return true, "Pet unequipped."
	end

	local pets = petsByPlayer[player]
	if typeof(petId) ~= "string" or pets == nil then
		return false, "Try again in a moment."
	end

	if table.find(pets, petId) == nil then
		return false, "You do not own that pet."
	end

	equippedByPlayer[player] = petId
	createFollower(player, petId)
	publishInventory(player)

	local info = PetCatalog.infoFor(petId)

	return true, string.format("%s equipped: +%d%% growth!", info.name, info.bonus * 100)
end

function PetService.grantRobuxEggPet(player: Player, worldIndex: number)
	local pool = PetCatalog.robuxEggPool(worldIndex)
	PetService.grantPet(player, pool[math.random(#pool)])
end

function PetService.grantLimitedPet(player: Player)
	PetService.grantPet(player, PetCatalog.limitedPetId())
end

function PetService.initializePlayer(player: Player, pets: { string }, equippedPet: string)
	petsByPlayer[player] = pets

	if equippedPet ~= "" and table.find(pets, equippedPet) ~= nil then
		equippedByPlayer[player] = equippedPet
	end

	publishInventory(player)

	player.CharacterAdded:Connect(function()
		local equipped = equippedByPlayer[player]
		if equipped ~= nil then
			-- Wait for the rig so the follower has a root to align to.
			task.delay(1, createFollower, player, equipped)
		end
	end)

	local equipped = equippedByPlayer[player]
	if equipped ~= nil and player.Character ~= nil then
		createFollower(player, equipped)
	end
end

function PetService.snapshot(player: Player): ({ string }?, string?)
	return petsByPlayer[player], equippedByPlayer[player] or ""
end

function PetService.removePlayer(player: Player)
	petsByPlayer[player] = nil
	equippedByPlayer[player] = nil
	followerByPlayer[player] = nil
end

return PetService
