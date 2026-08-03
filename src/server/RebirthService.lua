--[[
	Validates rebirths and runs the rebirth machine: a chamber assembles
	around the player, a syringe arm drains their growth (they visibly
	shrink), coin orbs spiral out of them into a collector, and the
	chamber releases them reborn. The reset applies at the END of the
	cinematic, so what players see is what happens.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Server = script.Parent
local ShopService = require(Server.ShopService)
local SizeService = require(Server.SizeService)

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local SizeFormula = require(Shared.SizeFormula)

local MACHINE_METAL = Color3.fromRGB(99, 110, 114)
local MACHINE_GLOW = Color3.fromRGB(0, 206, 201)
local SYRINGE_FLUID = Color3.fromRGB(76, 209, 55)
local COIN_GOLD = Color3.fromRGB(253, 203, 110)

local playersInMachine: { [Player]: boolean } = {}

local RebirthService = {}

local function createPart(properties: { [string]: any }): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	for key, value in pairs(properties) do
		if key ~= "Parent" then
			part[key] = value
		end
	end

	part.Parent = properties.Parent

	return part
end

--[[
	Builds and animates the machine around the character, yielding until
	the show is over. Returns nothing of gameplay consequence -- all the
	real changes happen after it in attemptRebirth.
]]
local function playCinematic(player: Player)
	local character = player.Character
	if character == nil then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil then
		return
	end

	local center = rootPart.CFrame
	rootPart.Anchored = true

	local machine = Instance.new("Folder")
	machine.Name = "RebirthMachine"

	-- Base ring and three pylons boxing the player in.
	createPart({
		Name = "MachineBase",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 14, 14),
		CFrame = center * CFrame.new(0, -2.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = MACHINE_METAL,
		Material = Enum.Material.DiamondPlate,
		Parent = machine,
	})

	for pylonIndex = 1, 3 do
		local angle = pylonIndex * math.pi * 2 / 3
		local pylon = createPart({
			Name = "Pylon",
			Size = Vector3.new(1.4, 12, 1.4),
			CFrame = center * CFrame.new(math.cos(angle) * 6, 3.5, math.sin(angle) * 6),
			Color = MACHINE_METAL,
			Material = Enum.Material.Metal,
			Parent = machine,
		})

		createPart({
			Name = "PylonLight",
			Size = Vector3.new(1.5, 0.6, 1.5),
			CFrame = pylon.CFrame * CFrame.new(0, 5, 0),
			Color = MACHINE_GLOW,
			Material = Enum.Material.Neon,
			Parent = machine,
		})
	end

	-- The glass tube drops over the player.
	local tube = createPart({
		Name = "GlassTube",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(16, 10, 10),
		CFrame = center * CFrame.new(0, 22, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(198, 240, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.55,
		Parent = machine,
	})

	-- Syringe arm: barrel, plunger, needle, angled at the player.
	local syringePivot = center * CFrame.new(5, 6, 0) * CFrame.Angles(0, 0, math.rad(-40))
	local barrel = createPart({
		Name = "SyringeBarrel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 1.4, 1.4),
		CFrame = syringePivot * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(223, 249, 251),
		Material = Enum.Material.Glass,
		Transparency = 0.3,
		Parent = machine,
	})

	local fluid = createPart({
		Name = "SyringeFluid",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 1.1, 1.1),
		CFrame = barrel.CFrame,
		Color = SYRINGE_FLUID,
		Material = Enum.Material.Neon,
		Parent = machine,
	})

	createPart({
		Name = "SyringeNeedle",
		Size = Vector3.new(0.15, 2.4, 0.15),
		CFrame = syringePivot * CFrame.new(0, -2.4, 0),
		Color = Color3.fromRGB(200, 205, 210),
		Material = Enum.Material.Metal,
		Parent = machine,
	})

	-- Coin collector funnel above; orbs will spiral into it.
	local funnel = createPart({
		Name = "CoinFunnel",
		Size = Vector3.new(3, 2, 3),
		CFrame = center * CFrame.new(0, 11, 0),
		Color = COIN_GOLD,
		Material = Enum.Material.Metal,
		Parent = machine,
	})

	machine.Parent = Workspace

	-- The tube drops and seals the player in.
	TweenService:Create(tube, TweenInfo.new(0.6, Enum.EasingStyle.Bounce), {
		CFrame = center * CFrame.new(0, 2.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
	}):Play()
	task.wait(0.8)

	-- The syringe draws the growth out -- the fluid grows as the player
	-- visibly shrinks.
	TweenService:Create(fluid, TweenInfo.new(1.2, Enum.EasingStyle.Quad), {
		Size = Vector3.new(2.4, 1.1, 1.1),
	}):Play()
	SizeService.forceShrink(player)

	-- Coins spiral up out of the player into the funnel.
	for orbIndex = 1, 8 do
		task.delay(orbIndex * 0.12, function()
			local orb = createPart({
				Name = "CoinOrb",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.8, 0.8, 0.8),
				CFrame = center * CFrame.new(0, 1, 0),
				Color = COIN_GOLD,
				Material = Enum.Material.Neon,
				Parent = machine,
			})

			local rise = TweenService:Create(
				orb,
				TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ CFrame = funnel.CFrame, Size = Vector3.new(0.2, 0.2, 0.2) }
			)
			rise:Play()
			rise.Completed:Connect(function()
				orb:Destroy()
			end)
		end)
	end

	task.wait(GameConfig.rebirth.cinematicSeconds - 0.8)

	-- The tube lifts away and the machine breaks down.
	TweenService:Create(tube, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
		CFrame = center * CFrame.new(0, 22, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Transparency = 1,
	}):Play()
	task.wait(0.5)

	machine:Destroy()

	if rootPart.Parent ~= nil then
		rootPart.Anchored = false
	end
end

--[[
	Wired as AttemptRebirth.OnServerInvoke. Returns quickly so the UI can
	close; the machine and the actual reset run in a spawned task.
]]
function RebirthService.attemptRebirth(player: Player): (boolean, string)
	local state = SizeService.getState(player)
	if state == nil then
		return false, "Your data is still loading -- try again in a moment."
	end

	if playersInMachine[player] then
		return false, "The machine is already running!"
	end

	local requiredSize = SizeFormula.requiredSizeForRebirth(state.rebirths)
	if state.maxSize < requiredSize then
		return false,
			string.format(
				"You need %d Max Size to rebirth (you have %d).",
				requiredSize,
				math.floor(state.maxSize)
			)
	end

	playersInMachine[player] = true

	local newRebirths = state.rebirths + 1
	local newMultiplier = SizeFormula.growthMultiplier(newRebirths, {
		doubleRebirthBonus = ShopService.playerOwnsPass(player, "DoubleRebirthBonus"),
	})

	task.spawn(function()
		playCinematic(player)

		-- The player may have left mid-cinematic.
		if player.Parent ~= nil and SizeService.getState(player) ~= nil then
			SizeService.applyRebirth(player)
		end
		playersInMachine[player] = nil
	end)

	return true, string.format("Reborn! You now grow x%.1f as fast. Forever.", newMultiplier)
end

return RebirthService
