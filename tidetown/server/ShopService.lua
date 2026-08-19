--[[
	The one buy router: every BuyShopItem key -- eggs, mounts, the next
	reef slot, surge-gear upgrades, reef decorations, and trails --
	resolves and pays out here, so pricing, ownership checks, and
	refunds live in a single place. This service owns the cosmetic and
	upgrade slices of PlayerData (upgrade levels, decorations, trails);
	eggs, mounts, and reef slots belong to their own services and are
	granted through injected dependencies AFTER the currency spend, with
	the spend refunded whenever the grant refuses.

	An equipped trail is a real Trail instance on the character's root,
	reapplied on every respawn, so the purchase is visible the moment
	the toast lands.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TidetownShared = ReplicatedStorage.TidetownShared
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

local TRAIL_NAME = "TidetownTrail"
local TRAIL_TOP_ATTACHMENT_NAME = "TidetownTrailTop"
local TRAIL_BOTTOM_ATTACHMENT_NAME = "TidetownTrailBottom"
local TRAIL_LIFETIME_SECONDS = 0.6
local ROOT_WAIT_SECONDS = 10

type ShopState = {
	upgrades: { [string]: number },
	decorationsOwned: { string },
	trailsOwned: { string },
	equippedTrail: string,
}

type EggOffer = { key: string, name: string, shellCost: number }
type MountOffer = { key: string, name: string, stormglassCost: number }
type UpgradeOffer = { key: string, name: string, costs: { number } }
type DecorationOffer = { key: string, name: string, shellCost: number }
type TrailOffer = { key: string, name: string, shellCost: number, color: { number } }

type Dependencies = {
	spendShells: (Player, number) -> boolean,
	spendStormglass: (Player, number) -> boolean,
	awardShells: (Player, number) -> (),
	grantEgg: (Player, string) -> boolean,
	grantMount: (Player, string) -> (),
	mountsOwnedList: (Player) -> { string },
	unlockNextSlot: (Player) -> (boolean, string),
	nextSlotCost: (Player) -> number?,
	pushToast: (Player, string, string?) -> (),
}

local ShopService = {}

local statesByPlayer: { [Player]: ShopState } = {}
local characterConnectionsByPlayer: { [Player]: RBXScriptConnection } = {}
local dependencies: Dependencies? = nil
local syncStateRemote: RemoteEvent? = nil

local function copyStringList(list: { string }): { string }
	local copy = {}
	for _, value in ipairs(list) do
		table.insert(copy, value)
	end

	return copy
end

local function listContains(list: { string }, value: string): boolean
	for _, entry in ipairs(list) do
		if entry == value then
			return true
		end
	end

	return false
end

local function trailConfigFor(trailKey: string): TrailOffer?
	for _, trailConfig in ipairs(TidetownConfig.shop.trails) do
		if trailConfig.key == trailKey then
			return trailConfig
		end
	end

	return nil
end

--[[
	Rebuilds the character's Trail to match the equipped key: the old
	instances are removed by name, then one Trail between two root
	attachments is created -- exactly one per player, replaced on every
	change and respawn.
]]
local function applyEquippedTrail(player: Player)
	local state = statesByPlayer[player]
	if state == nil then
		return
	end

	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return
	end

	local instanceNames = { TRAIL_NAME, TRAIL_TOP_ATTACHMENT_NAME, TRAIL_BOTTOM_ATTACHMENT_NAME }
	for _, instanceName in ipairs(instanceNames) do
		local existing = root:FindFirstChild(instanceName)
		if existing ~= nil then
			existing:Destroy()
		end
	end

	if state.equippedTrail == "" then
		return
	end

	local trailConfig = trailConfigFor(state.equippedTrail)
	if trailConfig == nil then
		return
	end

	local color = Color3.fromRGB(trailConfig.color[1], trailConfig.color[2], trailConfig.color[3])

	local topAttachment = Instance.new("Attachment")
	topAttachment.Name = TRAIL_TOP_ATTACHMENT_NAME
	topAttachment.Position = Vector3.new(0, 1, 0)
	topAttachment.Parent = root

	local bottomAttachment = Instance.new("Attachment")
	bottomAttachment.Name = TRAIL_BOTTOM_ATTACHMENT_NAME
	bottomAttachment.Position = Vector3.new(0, -1, 0)
	bottomAttachment.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = TRAIL_NAME
	trail.Attachment0 = topAttachment
	trail.Attachment1 = bottomAttachment
	trail.Color = ColorSequence.new(color)
	trail.Lifetime = TRAIL_LIFETIME_SECONDS
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.LightEmission = 0.4
	trail.FaceCamera = true
	trail.Parent = root
end

--[[
	Sends the player's full shop slice to their client. The owned-mount
	list rides along (via MountService's snapshot dependency) because
	the shop window prices mounts and needs ownership in one payload.
]]
function ShopService.pushState(player: Player)
	local state = statesByPlayer[player]
	local activeDependencies = dependencies
	if state == nil or syncStateRemote == nil then
		return
	end

	local mountsOwned: { string } = if activeDependencies ~= nil
		then activeDependencies.mountsOwnedList(player)
		else {}

	syncStateRemote:FireClient(player, "shop", {
		upgrades = table.clone(state.upgrades),
		decorationsOwned = copyStringList(state.decorationsOwned),
		trailsOwned = copyStringList(state.trailsOwned),
		equippedTrail = state.equippedTrail,
		mountsOwned = mountsOwned,
	})
end

local function buyEgg(player: Player, eggOffer: EggOffer, deps: Dependencies): (boolean, any)
	if not deps.spendShells(player, eggOffer.shellCost) then
		return false, "Not enough Shells"
	end

	if not deps.grantEgg(player, eggOffer.key) then
		-- The bag was full, so the spend must not stick: the exact
		-- cost goes straight back.
		deps.awardShells(player, eggOffer.shellCost)

		return false, "Egg bag full"
	end

	return true, eggOffer.name .. " purchased!"
end

local function buyMount(player: Player, mountOffer: MountOffer, deps: Dependencies): (boolean, any)
	if listContains(deps.mountsOwnedList(player), mountOffer.key) then
		return false, "Already owned"
	end

	if not deps.spendStormglass(player, mountOffer.stormglassCost) then
		return false, "Not enough Stormglass"
	end

	deps.grantMount(player, mountOffer.key)

	return true, mountOffer.name .. " is yours!"
end

local function buyReefSlot(player: Player, deps: Dependencies): (boolean, any)
	local cost = deps.nextSlotCost(player)
	if cost == nil then
		return false, "Reef fully expanded"
	end

	if not deps.spendShells(player, cost) then
		return false, "Not enough Shells"
	end

	local ok, message = deps.unlockNextSlot(player)
	if not ok then
		-- Shells never vanish into a slot that failed to open.
		deps.awardShells(player, cost)

		return false, message
	end

	return true, "Reef slot unlocked!"
end

local function buyUpgrade(
	player: Player,
	state: ShopState,
	upgradeOffer: UpgradeOffer,
	deps: Dependencies
): (boolean, any)
	local level = state.upgrades[upgradeOffer.key] or 0
	if level >= #upgradeOffer.costs then
		return false, "Fully upgraded"
	end

	if not deps.spendStormglass(player, upgradeOffer.costs[level + 1]) then
		return false, "Not enough Stormglass"
	end

	state.upgrades[upgradeOffer.key] = level + 1
	ShopService.pushState(player)

	return true, string.format("%s is now level %d!", upgradeOffer.name, level + 1)
end

local function buyDecoration(
	player: Player,
	state: ShopState,
	decorationOffer: DecorationOffer,
	deps: Dependencies
): (boolean, any)
	if listContains(state.decorationsOwned, decorationOffer.key) then
		return false, "Already owned"
	end

	if not deps.spendShells(player, decorationOffer.shellCost) then
		return false, "Not enough Shells"
	end

	table.insert(state.decorationsOwned, decorationOffer.key)
	ShopService.pushState(player)

	return true, decorationOffer.name .. " added to your reef!"
end

-- Owning a trail makes re-buying it a free equip, so one shop button
-- serves both purchase and wardrobe.
local function buyTrail(
	player: Player,
	state: ShopState,
	trailOffer: TrailOffer,
	deps: Dependencies
): (boolean, any)
	if listContains(state.trailsOwned, trailOffer.key) then
		if state.equippedTrail == trailOffer.key then
			return false, "Already equipped"
		end
	else
		if not deps.spendShells(player, trailOffer.shellCost) then
			return false, "Not enough Shells"
		end

		table.insert(state.trailsOwned, trailOffer.key)
	end

	state.equippedTrail = trailOffer.key
	applyEquippedTrail(player)
	ShopService.pushState(player)

	return true, trailOffer.name .. " equipped!"
end

function ShopService.initializePlayer(
	player: Player,
	upgrades: { [string]: number },
	decorationsOwned: { string },
	trailsOwned: { string },
	equippedTrail: string
)
	-- Copied so this service owns its slice outright instead of
	-- aliasing the loaded PlayerData table.
	statesByPlayer[player] = {
		upgrades = table.clone(upgrades),
		decorationsOwned = copyStringList(decorationsOwned),
		trailsOwned = copyStringList(trailsOwned),
		equippedTrail = equippedTrail,
	}

	-- Respawns must keep the equipped trail; the connection lives
	-- until the player leaves and is disconnected in removePlayer.
	characterConnectionsByPlayer[player] = player.CharacterAdded:Connect(function(character)
		task.spawn(function()
			-- The root often lags CharacterAdded by a frame; the
			-- timeout keeps a stuck spawn from leaking this task.
			character:WaitForChild("HumanoidRootPart", ROOT_WAIT_SECONDS)
			applyEquippedTrail(player)
		end)
	end)

	applyEquippedTrail(player)
	ShopService.pushState(player)
end

function ShopService.snapshot(
	player: Player
): ({ [string]: number }?, { string }?, { string }?, string?)
	local state = statesByPlayer[player]
	if state == nil then
		return nil, nil, nil, nil
	end

	-- Copied so the save snapshot cannot alias live state that a later
	-- purchase could mutate mid-save.
	return table.clone(state.upgrades),
		copyStringList(state.decorationsOwned),
		copyStringList(state.trailsOwned),
		state.equippedTrail
end

function ShopService.removePlayer(player: Player)
	local connection = characterConnectionsByPlayer[player]
	if connection ~= nil then
		connection:Disconnect()
	end

	characterConnectionsByPlayer[player] = nil
	statesByPlayer[player] = nil
end

--[[
	The player's level in a ladder upgrade, zero when unbought.
	SurgeService reads barrierPlating and deflectCharm through this.
]]
function ShopService.upgradeLevel(player: Player, upgradeKey: string): number
	local state = statesByPlayer[player]
	if state == nil then
		return 0
	end

	return state.upgrades[upgradeKey] or 0
end

--[[
	Resolves an item key from the untrusted BuyShopItem remote against
	the shop catalog and routes it to its purchase handler. Everything
	is validated against config and server state here -- the client's
	only contribution is the key string.
]]
function ShopService.buyItem(player: Player, itemKey: any): (boolean, any)
	local state = statesByPlayer[player]
	local activeDependencies = dependencies
	if state == nil or activeDependencies == nil then
		return false, "Not ready"
	end

	if typeof(itemKey) ~= "string" then
		return false, "Unknown item"
	end

	for _, eggOffer in ipairs(TidetownConfig.eggs.types) do
		if eggOffer.key == itemKey then
			return buyEgg(player, eggOffer, activeDependencies)
		end
	end

	for _, mountOffer in ipairs(TidetownConfig.mounts.owned) do
		if mountOffer.key == itemKey then
			return buyMount(player, mountOffer, activeDependencies)
		end
	end

	if itemKey == "reefSlot" then
		return buyReefSlot(player, activeDependencies)
	end

	for _, upgradeOffer in ipairs(TidetownConfig.shop.upgrades) do
		if upgradeOffer.key == itemKey then
			return buyUpgrade(player, state, upgradeOffer, activeDependencies)
		end
	end

	for _, decorationOffer in ipairs(TidetownConfig.shop.decorations) do
		if decorationOffer.key == itemKey then
			return buyDecoration(player, state, decorationOffer, activeDependencies)
		end
	end

	for _, trailOffer in ipairs(TidetownConfig.shop.trails) do
		if trailOffer.key == itemKey then
			return buyTrail(player, state, trailOffer, activeDependencies)
		end
	end

	return false, "Unknown item"
end

--[[
	Wires dependencies and fetches the SyncState remote (yields, which
	is fine on the init script's thread).
]]
function ShopService.start(dependencyTable: Dependencies)
	dependencies = dependencyTable

	local remote = TidetownRemotes.get("SyncState")
	if remote:IsA("RemoteEvent") then
		syncStateRemote = remote
	end
end

return ShopService
