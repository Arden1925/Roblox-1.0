--[[
	Single source of truth for the remotes the client and server share.
	Declaring every remote in one table means a typo in a remote name fails
	loudly at the assert below instead of silently waiting forever.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLDER_NAME = "Remotes"

local REMOTE_CLASS_BY_NAME = {
	AttemptRebirth = "RemoteFunction",
	BuyPotion = "RemoteFunction",
	BuyUpgrade = "RemoteFunction",
	ClaimGroupChest = "RemoteFunction",
	ClaimQuest = "RemoteFunction",
	ClaimStreak = "RemoteFunction",
	EquipPet = "RemoteFunction",
	HatchEgg = "RemoteFunction",
	MarkTutorialDone = "RemoteEvent",
	RequestInstantShrink = "RemoteEvent",
	RequestTeleport = "RemoteFunction",
	SetDesiredSize = "RemoteEvent",
	SetDesiredSpeed = "RemoteEvent",
	UseMysteryMachine = "RemoteFunction",
}

local Remotes = {}

--[[
	Creates the remotes folder and every declared remote, returning them
	by name so the server can wire handlers without ever yielding. The
	server calls this exactly once during boot, before any client can
	ask for them.
]]
function Remotes.createAll(): { [string]: Instance }
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	local remoteByName = {}
	for name, className in pairs(REMOTE_CLASS_BY_NAME) do
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
		remoteByName[name] = remote
	end

	folder.Parent = ReplicatedStorage

	return remoteByName
end

--[[
	Returns the named remote, yielding until it exists. Safe to call during
	client startup; call it from a spawned task, never on the main task.
]]
function Remotes.get(name: string): Instance
	assert(REMOTE_CLASS_BY_NAME[name] ~= nil, string.format("%q is not a declared remote", name))

	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)

	return folder:WaitForChild(name)
end

return Remotes
