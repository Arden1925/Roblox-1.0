--[[
	Everything Robux: game pass ownership, developer product receipts, and
	the effects they grant.

	Ownership and timed effects are published as player attributes
	(Owns<PassKey> booleans, <EffectKey>Until server timestamps) so any
	system -- server or client -- can read them without depending on this
	module. Attributes also die with the player, which removes a whole
	class of cleanup bugs.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)

local VIP_TRAIL_COLOR = Color3.fromRGB(253, 203, 110)

-- Injected by init.server.lua so this module never has to require
-- SizeService or PetService (SizeService requires this module).
local grantMaxSize: (Player, number) -> () = function() end
local grantRobuxEggPet: (Player, number) -> () = function() end
local grantLimitedPet: (Player) -> () = function() end

local ShopService = {}

local function passKeyForId(gamePassId: number): string?
	for _, pass in ipairs(GameConfig.passes) do
		if pass.gamePassId == gamePassId then
			return pass.key
		end
	end

	return nil
end

-- Developer products come in three kinds; the receipt handler needs to
-- know which family an ID belongs to.
local function productForId(productId: number): ({ [string]: any }?, string?, number?)
	for worldIndex, world in ipairs(GameConfig.worlds) do
		if world.cityProduct.productId == productId then
			return world.cityProduct, "city", worldIndex
		end
		if world.robuxEgg.productId == productId then
			return world.robuxEgg, "egg", worldIndex
		end
	end

	if GameConfig.limitedPet.productId == productId then
		return GameConfig.limitedPet, "limited", nil
	end

	return nil, nil, nil
end

local function applyVipTrail(character: Model)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if rootPart == nil or rootPart:FindFirstChild("VipTrail") ~= nil then
		return
	end

	local topAttachment = Instance.new("Attachment")
	topAttachment.Name = "VipTrailTop"
	topAttachment.Position = Vector3.new(0, 1, 0)
	topAttachment.Parent = rootPart

	local bottomAttachment = Instance.new("Attachment")
	bottomAttachment.Name = "VipTrailBottom"
	bottomAttachment.Position = Vector3.new(0, -1, 0)
	bottomAttachment.Parent = rootPart

	local trail = Instance.new("Trail")
	trail.Name = "VipTrail"
	trail.Attachment0 = topAttachment
	trail.Attachment1 = bottomAttachment
	trail.Color = ColorSequence.new(VIP_TRAIL_COLOR)
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Lifetime = 0.4
	trail.FaceCamera = true
	trail.Parent = rootPart
end

local function enableVipPerks(player: Player)
	if player.Character ~= nil then
		task.spawn(applyVipTrail, player.Character)
	end

	player.CharacterAdded:Connect(function(character)
		if player:GetAttribute("OwnsVip") == true then
			task.spawn(applyVipTrail, character)
		end
	end)
end

--[[
	Fetches ownership of every configured pass for a player and publishes
	the results as attributes. Yields; call from a spawned task at join.
]]
function ShopService.prefetchAsync(player: Player)
	for _, pass in ipairs(GameConfig.passes) do
		if pass.gamePassId ~= 0 then
			-- UserOwnsGamePassAsync throws on Marketplace outages; treat
			-- failure as not-owned and let a rejoin retry it.
			local success, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.gamePassId)
			end)

			player:SetAttribute("Owns" .. pass.key, success and owns == true)
		else
			player:SetAttribute("Owns" .. pass.key, false)
		end
	end

	if player:GetAttribute("OwnsVip") == true then
		enableVipPerks(player)
	end
end

function ShopService.playerOwnsPass(player: Player, passKey: string): boolean
	return player:GetAttribute("Owns" .. passKey) == true
end

function ShopService.effectActive(player: Player, effectKey: string): boolean
	local untilTime = player:GetAttribute(effectKey .. "Until")

	return typeof(untilTime) == "number" and untilTime > Workspace:GetServerTimeNow()
end

local function grantProduct(player: Player, product: { [string]: any })
	if product.effect == "instantSize" then
		grantMaxSize(player, product.amount)
	elseif product.effect == "timed" then
		local expiresAt = Workspace:GetServerTimeNow() + product.durationSeconds
		player:SetAttribute(product.effectKey .. "Until", expiresAt)
	end
end

local function processReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if player == nil then
		-- Buyer left; Roblox will redeliver this receipt on their next
		-- join, so granting nothing now loses nothing.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local product, kind, worldIndex = productForId(receiptInfo.ProductId)
	if product == nil then
		-- An ID we do not recognize means the config and the website
		-- disagree. Granting closes the receipt: retrying forever would
		-- never succeed and would block the player's purchase queue.
		warn(string.format("Receipt for unknown product %d", receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if kind == "city" then
		grantProduct(player, product)
	elseif kind == "egg" then
		grantRobuxEggPet(player, worldIndex :: number)
	elseif kind == "limited" then
		grantLimitedPet(player)
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function ShopService.start(dependencies: {
	grantMaxSize: (Player, number) -> (),
	grantRobuxEggPet: (Player, number) -> (),
	grantLimitedPet: (Player) -> (),
})
	grantMaxSize = dependencies.grantMaxSize
	grantRobuxEggPet = dependencies.grantRobuxEggPet
	grantLimitedPet = dependencies.grantLimitedPet

	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player, gamePassId, wasPurchased)
			if not wasPurchased then
				return
			end

			local passKey = passKeyForId(gamePassId)
			if passKey ~= nil then
				player:SetAttribute("Owns" .. passKey, true)

				if passKey == "Vip" then
					enableVipPerks(player)
				end
			end
		end
	)
end

return ShopService
