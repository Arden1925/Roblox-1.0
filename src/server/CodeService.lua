--[[
	Promo code redemption: each code in GameConfig.codes pays out once
	per player, ever. Redeemed codes ride the normal save pipeline, and
	rewards reuse the wheel's reward kinds so adding a code is one
	config line.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)

local redeemedByPlayer: { [Player]: { [string]: boolean } } = {}

local awardCoins: (Player, number) -> () = function() end
local grantMaxSize: (Player, number) -> () = function() end

local CodeService = {}

local function findCode(codeText: string): { [string]: any }?
	for _, spec in ipairs(GameConfig.codes) do
		if spec.code == codeText then
			return spec
		end
	end

	return nil
end

-- Wired as RedeemCode.OnServerInvoke.
function CodeService.redeem(player: Player, codeText: any): (boolean, string)
	local redeemed = redeemedByPlayer[player]
	if redeemed == nil or typeof(codeText) ~= "string" then
		return false, "Try again in a moment."
	end

	local trimmed = string.upper(string.match(codeText, "^%s*(.-)%s*$") :: string)
	if #trimmed == 0 then
		return false, "Type a code first!"
	end

	local spec = findCode(trimmed)
	if spec == nil then
		return false, "That code does not exist -- check the spelling!"
	end

	if redeemed[trimmed] then
		return false, "You already used that code."
	end

	if spec.kind == "coins" then
		awardCoins(player, spec.amount)
	elseif spec.kind == "maxSize" then
		grantMaxSize(player, spec.amount)
	elseif spec.kind == "effect" then
		local expiresAt = Workspace:GetServerTimeNow() + spec.durationSeconds
		player:SetAttribute(spec.effectKey .. "Until", expiresAt)
	end

	redeemed[trimmed] = true

	return true, string.format("Code redeemed: %s!", spec.label)
end

function CodeService.initializePlayer(player: Player, redeemedCodes: { string })
	local redeemed = {}
	for _, code in ipairs(redeemedCodes) do
		redeemed[code] = true
	end
	redeemedByPlayer[player] = redeemed
end

function CodeService.snapshot(player: Player): { string }?
	local redeemed = redeemedByPlayer[player]
	if redeemed == nil then
		return nil
	end

	local list = {}
	for code in pairs(redeemed) do
		table.insert(list, code)
	end
	-- Sorted so identical progress always serializes identically.
	table.sort(list)

	return list
end

function CodeService.removePlayer(player: Player)
	redeemedByPlayer[player] = nil
end

function CodeService.start(dependencies: {
	awardCoins: (Player, number) -> (),
	grantMaxSize: (Player, number) -> (),
})
	awardCoins = dependencies.awardCoins
	grantMaxSize = dependencies.grantMaxSize
end

return CodeService
