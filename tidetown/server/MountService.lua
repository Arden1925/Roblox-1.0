--[[
	Owns surf mounts: which mounts each player has bought, and the live
	mount a player is riding during high tide. A ridden mount is a fully
	anchored model with an anchored Seat -- sitting welds the character
	to the seat even though nothing simulates -- and ONE Heartbeat
	connection steers every active mount from its occupant's replicated
	MoveDirection, floating the seat on the authoritative water level.
	Keeping mounts anchored and server-stepped means an exploiter can
	never fling one; the sea border and the loaner's deep-zone fence are
	clamps in this file, not client rules.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TidetownShared = ReplicatedStorage.TidetownShared
local CreatureModels = require(TidetownShared.CreatureModels)
local TideLayout = require(TidetownShared.TideLayout)
local TidePhase = require(TidetownShared.TidePhase)
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

local MAP_FOLDER_NAME = "Tidetown"
local MOUNT_STAND_NAME = "MountStand"
local STAND_WAIT_SECONDS = 30
local MOUNT_MODEL_HEIGHT_STUDS = 5
-- The seat's top face rides this far above the water surface, so the
-- rider's legs skim the waves instead of sinking.
local SEAT_TOP_ABOVE_WATER_STUDS = 1
-- The creature visual hangs this far below the seat so the rider sits
-- on its back rather than inside it.
local CREATURE_SEAT_DROP_STUDS = 1.5
local BORDER_MINIMUM_X = -740
local BORDER_MAXIMUM_X = 420
local BORDER_MINIMUM_Z = -185
local BORDER_MAXIMUM_Z = 185
-- The loaner tube cannot enter the Deep Reef; this fence sits just
-- shoreward of the zone edge so the clamp never argues with zoneAt.
local LOANER_MINIMUM_X = -455
local RIDE_REPORT_STUDS = 25
-- Sitting takes a frame or two to register as Occupant; without this
-- grace a fresh mount would read "rider left" and instantly despawn.
local OCCUPANT_GRACE_SECONDS = 2
local DISMOUNT_LIFT_STUDS = 2
local MOVE_EPSILON = 0.05

type MountConfig = {
	key: string,
	name: string,
	speedStudsPerSecond: number,
	deepAccess: boolean,
	modelName: string?,
}

type ActiveMount = {
	model: Model,
	seat: Seat,
	speedStudsPerSecond: number,
	deepAccess: boolean,
	isLoaner: boolean,
	yawRadians: number,
	distanceSinceReport: number,
	everOccupied: boolean,
	spawnedAtClock: number,
}

type Dependencies = {
	getPhase: () -> string,
	waterLevelNow: () -> number,
	onPhaseChanged: (callback: (phase: string) -> ()) -> (),
	reportBounty: (Player, string, number) -> (),
	pushToast: (Player, string, string?) -> (),
}

local MountService = {}

local mountsOwnedByPlayer: { [Player]: { string } } = {}
local activeMountsByPlayer: { [Player]: ActiveMount } = {}
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

-- Both the loaner and the owned mounts flatten into one shape here so
-- the ride code never branches on where a mount was configured.
local function configFor(mountKey: string): MountConfig?
	local mounts = TidetownConfig.mounts

	if mountKey == mounts.loaner.key then
		return {
			key = mounts.loaner.key,
			name = mounts.loaner.name,
			speedStudsPerSecond = mounts.loaner.speedStudsPerSecond,
			deepAccess = mounts.loaner.deepAccess,
			modelName = nil,
		}
	end

	for _, owned in ipairs(mounts.owned) do
		if owned.key == mountKey then
			return {
				key = owned.key,
				name = owned.name,
				speedStudsPerSecond = owned.speedStudsPerSecond,
				deepAccess = owned.deepAccess,
				modelName = owned.modelName,
			}
		end
	end

	return nil
end

local function findMountTemplate(modelName: string): Instance?
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local modelsFolder = if assetsFolder ~= nil then assetsFolder:FindFirstChild("Models") else nil
	local pack = if modelsFolder ~= nil
		then modelsFolder:FindFirstChild("Sea_Animals_Pack")
		else nil
	local inner = if pack ~= nil then pack:FindFirstChild("Models") else nil
	if inner == nil then
		return nil
	end

	local template = inner:FindFirstChild(modelName)
	if template == nil then
		template = inner:FindFirstChild(string.gsub(modelName, " ", ""))
	end

	return template
end

--[[
	Builds the creature visual for an owned mount. Mount model names
	point straight at the Sea Animals pack rather than at catalog
	species, so the template is cloned and normalized here;
	CreatureModels.build covers the missing-pack case because it always
	returns SOMETHING rideable.
]]
local function buildMountVisual(modelName: string): Model
	local template = findMountTemplate(modelName)
	if template == nil then
		return CreatureModels.build(modelName, MOUNT_MODEL_HEIGHT_STUDS)
	end

	local visual = Instance.new("Model")
	visual.Name = modelName

	local clone = template:Clone()
	clone.Parent = visual

	for _, descendant in ipairs(visual:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end

	local extents = visual:GetExtentsSize()
	if extents.Y >= 0.05 then
		visual:ScaleTo(MOUNT_MODEL_HEIGHT_STUDS / extents.Y)
	end

	-- Center the bounding box on the pivot so PivotTo aims the body,
	-- not wherever the pack author left the pivot.
	local boxCFrame = visual:GetBoundingBox()
	visual:PivotTo(visual:GetPivot() - boxCFrame.Position)
	visual.WorldPivot = CFrame.new()

	return visual
end

local function buildLoanerVisual(): Part
	local ring = Instance.new("Part")
	ring.Name = "Tube"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.9, 4.5, 4.5)
	ring.Color = Color3.fromRGB(255, 110, 92)
	ring.Material = Enum.Material.Neon
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	-- A cylinder's axis is X; rolling it a quarter turn lays the ring
	-- flat on the water like an inner tube.
	ring.CFrame = CFrame.new(0, -0.8, 0) * CFrame.Angles(0, 0, math.rad(90))

	return ring
end

--[[
	Assembles a mount around the origin: an anchored Seat as the
	primary part with the visual placed relative to it, so one PivotTo
	per Heartbeat moves the whole thing rigidly.
]]
local function buildMountModel(mountConfig: MountConfig): (Model, Seat)
	local model = Instance.new("Model")
	model.Name = mountConfig.name

	local seat = Instance.new("Seat")
	seat.Name = "MountSeat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.Color = Color3.fromRGB(48, 62, 71)
	seat.Material = Enum.Material.SmoothPlastic
	seat.Anchored = true
	seat.CanCollide = false
	seat.CFrame = CFrame.new()
	seat.Parent = model

	if mountConfig.modelName == nil then
		local ring = buildLoanerVisual()
		ring.Parent = model
	else
		local visual = buildMountVisual(mountConfig.modelName)
		visual:PivotTo(CFrame.new(0, -CREATURE_SEAT_DROP_STUDS, 0))
		visual.Parent = model
	end

	model.PrimaryPart = seat

	return model, seat
end

local function mountParent(): Instance
	local folder = Workspace:FindFirstChild(MAP_FOLDER_NAME)

	return if folder ~= nil then folder else Workspace
end

-- Shortest-arc turn toward the target heading, capped by the mount's
-- turn rate so a direction flip sweeps instead of snapping.
local function turnToward(currentYaw: number, targetYaw: number, maxStepRadians: number): number
	local delta = (targetYaw - currentYaw + math.pi) % (2 * math.pi) - math.pi

	return currentYaw + math.clamp(delta, -maxStepRadians, maxStepRadians)
end

local function despawnMount(player: Player, teleportToSpawn: boolean)
	local mount = activeMountsByPlayer[player]
	if mount == nil then
		return
	end

	activeMountsByPlayer[player] = nil

	local occupant = mount.seat.Occupant
	if occupant ~= nil then
		-- Break the seat weld before destroying the model so the
		-- character never rides the mount into Destroy.
		local weld = mount.seat:FindFirstChild("SeatWeld")
		if weld ~= nil then
			weld:Destroy()
		end

		occupant.Sit = false
	end

	mount.model:Destroy()
	player:SetAttribute("Mounted", false)

	if teleportToSpawn then
		local character = player.Character
		if character ~= nil then
			local landing = TideLayout.spawnPosition() + Vector3.new(0, DISMOUNT_LIFT_STUDS, 0)
			character:PivotTo(CFrame.new(landing))
		end
	end
end

-- Falling means the water under every mount is about to vanish, so
-- riders go back to the boardwalk instead of being beached mid-sea.
local function forceDismountAll()
	for player in pairs(activeMountsByPlayer) do
		despawnMount(player, true)
	end
end

--[[
	The one Heartbeat for every active mount: read the occupant's
	replicated MoveDirection, turn and slide the anchored model, float
	the seat on the live water level, and clamp inside the borders. A
	seat with no occupant past the sit grace means the rider jumped
	off, and the character is left where they are to swim.
]]
local function stepMounts(deltaSeconds: number)
	local activeDependencies = dependencies
	if activeDependencies == nil then
		return
	end

	local waterLevel = activeDependencies.waterLevelNow()
	local maxTurnRadians = math.rad(TidetownConfig.mounts.turnDegreesPerSecond) * deltaSeconds

	for player, mount in pairs(activeMountsByPlayer) do
		local occupant = mount.seat.Occupant

		if occupant == nil then
			local pastGrace = os.clock() - mount.spawnedAtClock > OCCUPANT_GRACE_SECONDS
			if mount.everOccupied or pastGrace then
				despawnMount(player, false)
			end
		else
			mount.everOccupied = true

			local pivot = mount.model:GetPivot()
			local position = pivot.Position
			local moveDirection = occupant.MoveDirection
			local horizontal = Vector3.new(moveDirection.X, 0, moveDirection.Z)

			if horizontal.Magnitude > MOVE_EPSILON then
				local direction = horizontal.Unit
				local targetYaw = math.atan2(-direction.X, -direction.Z)
				mount.yawRadians = turnToward(mount.yawRadians, targetYaw, maxTurnRadians)
				position += direction * mount.speedStudsPerSecond * deltaSeconds
			end

			local minimumX = if mount.isLoaner then LOANER_MINIMUM_X else BORDER_MINIMUM_X
			local clampedX = math.clamp(position.X, minimumX, BORDER_MAXIMUM_X)
			local clampedZ = math.clamp(position.Z, BORDER_MINIMUM_Z, BORDER_MAXIMUM_Z)
			local seatCenterY = waterLevel + SEAT_TOP_ABOVE_WATER_STUDS - mount.seat.Size.Y / 2

			mount.model:PivotTo(
				CFrame.new(clampedX, seatCenterY, clampedZ) * CFrame.Angles(0, mount.yawRadians, 0)
			)

			-- Distance is measured after the clamp so grinding against
			-- a border wall never farms the surf bounty.
			local movedStuds = (Vector3.new(clampedX, 0, clampedZ) - Vector3.new(
				pivot.Position.X,
				0,
				pivot.Position.Z
			)).Magnitude
			mount.distanceSinceReport += movedStuds

			if mount.distanceSinceReport >= RIDE_REPORT_STUDS then
				local wholeStuds = math.floor(mount.distanceSinceReport)
				mount.distanceSinceReport -= wholeStuds
				activeDependencies.reportBounty(player, "rideDistance", wholeStuds)
			end
		end
	end
end

--[[
	Sends the player's owned-mount list to their client. Called after
	every mutation so the client never has to ask.
]]
function MountService.pushState(player: Player)
	local owned = mountsOwnedByPlayer[player]
	if owned == nil or syncStateRemote == nil then
		return
	end

	syncStateRemote:FireClient(player, "mounts", { mountsOwned = copyStringList(owned) })
end

function MountService.initializePlayer(player: Player, mountsOwned: { string })
	-- Copied so this service owns its slice outright instead of
	-- aliasing the loaded PlayerData table.
	mountsOwnedByPlayer[player] = copyStringList(mountsOwned)
	player:SetAttribute("Mounted", false)
	MountService.pushState(player)
end

function MountService.snapshot(player: Player): { string }?
	local owned = mountsOwnedByPlayer[player]
	if owned == nil then
		return nil
	end

	-- Copied so the save snapshot cannot alias live state that a later
	-- purchase could mutate mid-save.
	return copyStringList(owned)
end

function MountService.removePlayer(player: Player)
	despawnMount(player, false)
	mountsOwnedByPlayer[player] = nil
end

function MountService.ownsMount(player: Player, mountKey: string): boolean
	local owned = mountsOwnedByPlayer[player]
	if owned == nil then
		return false
	end

	return listContains(owned, mountKey)
end

--[[
	Adds a mount to the player's owned list. ShopService validated the
	key and took the Stormglass before calling; granting twice is a
	harmless no-op so a shop retry can never duplicate.
]]
function MountService.grantMount(player: Player, mountKey: string)
	local owned = mountsOwnedByPlayer[player]
	if owned == nil or typeof(mountKey) ~= "string" then
		return
	end

	if listContains(owned, mountKey) then
		return
	end

	table.insert(owned, mountKey)
	MountService.pushState(player)
end

--[[
	Whether the player is riding, and whether that ride reaches the
	deep-only species. CatchService gates Deep Reef casts on both.
]]
function MountService.isMounted(player: Player): (boolean, boolean)
	local mount = activeMountsByPlayer[player]
	if mount == nil then
		return false, false
	end

	return true, mount.deepAccess
end

--[[
	Spawns a mount under the player at the water surface and sits them
	on it. The mountKey arrives from the untrusted RequestMount remote
	(and the pier prompt), so every gate -- phase, ownership, a living
	character -- is checked here.
]]
function MountService.requestMount(player: Player, mountKey: any): (boolean, any)
	local activeDependencies = dependencies
	if mountsOwnedByPlayer[player] == nil or activeDependencies == nil then
		return false, "Not ready"
	end

	if typeof(mountKey) ~= "string" then
		return false, "Unknown mount"
	end

	if activeDependencies.getPhase() ~= TidePhase.High then
		return false, "The tide is too low to ride"
	end

	local mountConfig = configFor(mountKey)
	if mountConfig == nil then
		return false, "Unknown mount"
	end

	local isLoaner = mountKey == TidetownConfig.mounts.loaner.key
	if not isLoaner and not MountService.ownsMount(player, mountKey) then
		return false, "You do not own that mount"
	end

	if activeMountsByPlayer[player] ~= nil then
		return false, "You are already riding"
	end

	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if root == nil or not root:IsA("BasePart") or humanoid == nil or humanoid.Health <= 0 then
		return false, "You cannot ride right now"
	end

	local model, seat = buildMountModel(mountConfig)

	-- Spawn where the rider stands, clamped into the same fences the
	-- ride obeys, facing the way they already face.
	local minimumX = if isLoaner then LOANER_MINIMUM_X else BORDER_MINIMUM_X
	local spawnX = math.clamp(root.Position.X, minimumX, BORDER_MAXIMUM_X)
	local spawnZ = math.clamp(root.Position.Z, BORDER_MINIMUM_Z, BORDER_MAXIMUM_Z)
	local seatCenterY = activeDependencies.waterLevelNow()
		+ SEAT_TOP_ABOVE_WATER_STUDS
		- seat.Size.Y / 2
	local look = root.CFrame.LookVector
	local yawRadians = math.atan2(-look.X, -look.Z)

	model:PivotTo(CFrame.new(spawnX, seatCenterY, spawnZ) * CFrame.Angles(0, yawRadians, 0))
	model.Parent = mountParent()
	seat:Sit(humanoid)

	activeMountsByPlayer[player] = {
		model = model,
		seat = seat,
		speedStudsPerSecond = mountConfig.speedStudsPerSecond,
		deepAccess = mountConfig.deepAccess,
		isLoaner = isLoaner,
		yawRadians = yawRadians,
		distanceSinceReport = 0,
		everOccupied = false,
		spawnedAtClock = os.clock(),
	}
	player:SetAttribute("Mounted", true)

	return true, { mountKey = mountKey }
end

--[[
	Voluntary dismount from the Dismount remote: the rider steps back
	onto the boardwalk spawn rather than dropping mid-sea, so the
	button is always a safe exit.
]]
function MountService.dismount(player: Player): (boolean, any)
	if activeMountsByPlayer[player] == nil then
		return false, "You are not riding"
	end

	despawnMount(player, true)

	return true, true
end

--[[
	Wires dependencies, fetches the SyncState remote (yields, which is
	fine on the init script's thread), starts the mount Heartbeat,
	registers the Falling forced dismount, and hooks the pier stand
	prompt. The stand lookup runs in its own task and tolerates absence
	so a missing map piece can never stall the service.
]]
function MountService.start(dependencyTable: Dependencies)
	dependencies = dependencyTable

	local remote = TidetownRemotes.get("SyncState")
	if remote:IsA("RemoteEvent") then
		syncStateRemote = remote
	end

	dependencyTable.onPhaseChanged(function(phase: string)
		if phase == TidePhase.Falling then
			forceDismountAll()
		end
	end)

	RunService.Heartbeat:Connect(stepMounts)

	task.spawn(function()
		local folder = Workspace:WaitForChild(MAP_FOLDER_NAME, STAND_WAIT_SECONDS)
		local stand = if folder ~= nil
			then folder:WaitForChild(MOUNT_STAND_NAME, STAND_WAIT_SECONDS)
			else nil
		local prompt = if stand ~= nil then stand:FindFirstChildOfClass("ProximityPrompt") else nil
		if prompt == nil then
			return
		end

		-- The prompt stays enabled at all phases on purpose; the
		-- friendly rejection toast below teaches the tide rule.
		prompt.Triggered:Connect(function(triggeringPlayer: Player)
			local ok, result =
				MountService.requestMount(triggeringPlayer, TidetownConfig.mounts.loaner.key)
			if not ok and typeof(result) == "string" then
				dependencyTable.pushToast(triggeringPlayer, result, "bad")
			end
		end)
	end)
end

return MountService
