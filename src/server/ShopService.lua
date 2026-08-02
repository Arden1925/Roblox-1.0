--[[
	Tracks which game passes each player owns. Ownership checks hit the
	Marketplace API, which is slow and can fail, so results are cached per
	player and refreshed when a purchase completes in-session.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)

local ownedByUserId: { [number]: { [string]: boolean } } = {}

local ShopService = {}

local function passKeyForId(gamePassId: number): string?
	for _, pass in ipairs(GameConfig.passes) do
		if pass.gamePassId == gamePassId then
			return pass.key
		end
	end

	return nil
end

--[[
	Fetches ownership of every configured pass for a player. Yields; call
	from a spawned task at join time so later lookups are instant.
]]
function ShopService.prefetchAsync(player: Player)
	local owned = {}
	ownedByUserId[player.UserId] = owned

	for _, pass in ipairs(GameConfig.passes) do
		if pass.gamePassId ~= 0 then
			-- UserOwnsGamePassAsync throws on Marketplace outages; treat
			-- failure as not-owned and let a rejoin retry it.
			local success, result = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.gamePassId)
			end)

			owned[pass.key] = success and result == true
		end
	end
end

function ShopService.playerOwnsPass(player: Player, passKey: string): boolean
	local owned = ownedByUserId[player.UserId]
	if owned == nil then
		return false
	end

	return owned[passKey] == true
end

function ShopService.forgetPlayer(player: Player)
	ownedByUserId[player.UserId] = nil
end

function ShopService.start()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player, gamePassId, wasPurchased)
			if not wasPurchased then
				return
			end

			local passKey = passKeyForId(gamePassId)
			local owned = ownedByUserId[player.UserId]
			if passKey ~= nil and owned ~= nil then
				owned[passKey] = true
			end
		end
	)
end

return ShopService
