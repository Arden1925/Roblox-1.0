--[[
	Single source of truth for the remotes the client and server share.
	Declaring every remote in one table means a typo in a remote name fails
	loudly at the assert below instead of silently waiting forever.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLDER_NAME = "Remotes"

local REMOTE_CLASS_BY_NAME = {
	AttemptRebirth = "RemoteFunction",
	RequestInstantShrink = "RemoteEvent",
	RequestTeleport = "RemoteFunction",
}

local Remotes = {}

--[[
	Creates the remotes folder and every declared remote. The server calls
	this exactly once during boot, before any client can ask for them.
]]
function Remotes.createAll()
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	for name, className in pairs(REMOTE_CLASS_BY_NAME) do
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
	end

	folder.Parent = ReplicatedStorage
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
