--[[
	Owns the two per-player currency balances: Shells (time-earned) and
	Stormglass (skill-earned). The balances live here as plain numbers;
	the player attributes and the leaderstats board are mirrors updated
	on every change, so the HUD and the leaderboard can never disagree
	with the number a spend actually checked against.

	Other services never touch balances directly -- they go through
	award and spend, and spend fails atomically when the balance is
	short. The two currencies stay disjoint on purpose: nothing here
	converts one into the other.
]]

type Balance = {
	shells: number,
	stormglass: number,
}

local balancesByPlayer: { [Player]: Balance } = {}

local CurrencyService = {}

--[[
	Floors an amount to a whole, non-negative number. NaN passes a
	typeof check and survives math.floor, and would poison a balance
	forever, so the self-inequality test rejects it at the single entry
	point for currency math.
]]
local function flooredAmount(amount: number): number
	if typeof(amount) ~= "number" or amount ~= amount then
		return 0
	end

	return math.max(math.floor(amount), 0)
end

local function syncShells(player: Player, balance: Balance)
	player:SetAttribute("Shells", balance.shells)

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats ~= nil then
		local shellsValue = leaderstats:FindFirstChild("Shells")
		if shellsValue ~= nil and shellsValue:IsA("IntValue") then
			shellsValue.Value = balance.shells
		end
	end
end

-- Stormglass is deliberately not a leaderstat: the board shows Shells
-- and Tidepedia only, so the attribute is the sole mirror.
local function syncStormglass(player: Player, balance: Balance)
	player:SetAttribute("Stormglass", balance.stormglass)
end

--[[
	Builds the leaderstats board once per player. The Tidepedia value
	is created here alongside Shells because Roblox reads the whole
	board from one "leaderstats" folder; TidepediaService keeps that
	second value current.
]]
local function ensureLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") ~= nil then
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local shellsValue = Instance.new("IntValue")
	shellsValue.Name = "Shells"
	shellsValue.Parent = leaderstats

	local tidepediaValue = Instance.new("IntValue")
	tidepediaValue.Name = "Tidepedia"
	tidepediaValue.Parent = leaderstats

	leaderstats.Parent = player
end

function CurrencyService.initializePlayer(player: Player, shells: number, stormglass: number)
	local balance = {
		shells = flooredAmount(shells),
		stormglass = flooredAmount(stormglass),
	}
	balancesByPlayer[player] = balance

	ensureLeaderstats(player)
	syncShells(player, balance)
	syncStormglass(player, balance)
end

function CurrencyService.snapshot(player: Player): (number?, number?)
	local balance = balancesByPlayer[player]
	if balance == nil then
		return nil, nil
	end

	return balance.shells, balance.stormglass
end

function CurrencyService.removePlayer(player: Player)
	balancesByPlayer[player] = nil
end

function CurrencyService.awardShells(player: Player, amount: number)
	local balance = balancesByPlayer[player]
	if balance == nil then
		return
	end

	local floored = flooredAmount(amount)
	if floored == 0 then
		return
	end

	balance.shells += floored
	syncShells(player, balance)
end

function CurrencyService.spendShells(player: Player, amount: number): boolean
	local balance = balancesByPlayer[player]
	if balance == nil then
		return false
	end

	local floored = flooredAmount(amount)
	if balance.shells < floored then
		return false
	end

	balance.shells -= floored
	syncShells(player, balance)

	return true
end

function CurrencyService.awardStormglass(player: Player, amount: number)
	local balance = balancesByPlayer[player]
	if balance == nil then
		return
	end

	local floored = flooredAmount(amount)
	if floored == 0 then
		return
	end

	balance.stormglass += floored
	syncStormglass(player, balance)
end

function CurrencyService.spendStormglass(player: Player, amount: number): boolean
	local balance = balancesByPlayer[player]
	if balance == nil then
		return false
	end

	local floored = flooredAmount(amount)
	if balance.stormglass < floored then
		return false
	end

	balance.stormglass -= floored
	syncStormglass(player, balance)

	return true
end

return CurrencyService
