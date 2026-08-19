--[[
	Mount controls in the bottom-right corner, above the surge deflect
	button: a Dismount button whenever the server marks the player
	mounted, and -- during high tide, once the player owns a real mount
	-- a Ride chip that opens a mini list of the loaner tube plus every
	owned mount. The server owns all mount rules; this module only asks
	and shows the answer.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Client = script.Parent
local TidetownUi = require(Client.TidetownUi)
local Toast = require(Client.Toast)

local TidetownShared = ReplicatedStorage:WaitForChild("TidetownShared")
local TidePhase = require(TidetownShared.TidePhase)
local TidetownConfig = require(TidetownShared.TidetownConfig)
local TidetownRemotes = require(TidetownShared.TidetownRemotes)

local OUTLINE_NAVY = Color3.fromRGB(31, 41, 74)
local DISMOUNT_COLOR = Color3.fromRGB(235, 69, 44)
local RIDE_COLOR = Color3.fromRGB(0, 148, 176)
local LIST_COLOR = Color3.fromRGB(244, 250, 255)
local ROW_COLOR = Color3.fromRGB(0, 121, 155)
local ROW_HEIGHT = 46

local localPlayer = Players.LocalPlayer

local MountController = {}

local function mountDisplayText(name: string, speed: number, deepAccess: boolean): string
	local suffix = if deepAccess then " · Deep" else ""

	return string.format("%s  🌊%d%s", name, speed, suffix)
end

function MountController.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local screenGui = TidetownUi.create("ScreenGui", {
		Name = "TidetownMount",
		ResetOnSpawn = false,
		DisplayOrder = 18,
		Parent = playerGui,
	}) :: ScreenGui

	-- The deflect button owns the corner itself; these sit just above
	-- its 146-pixel container (see the client layout map).
	local dismountButton = TidetownUi.create("TextButton", {
		Name = "DismountButton",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -176),
		Size = UDim2.new(0, 132, 0, ROW_HEIGHT),
		BackgroundColor3 = DISMOUNT_COLOR,
		BorderSizePixel = 0,
		Text = "⬇ Dismount",
		TextSize = 18,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Visible = false,
		Parent = screenGui,
	}) :: TextButton
	TidetownUi.round(dismountButton, 14)
	TidetownUi.stroke(dismountButton, OUTLINE_NAVY, 3)
	TidetownUi.gloss(dismountButton)
	TidetownUi.hoverPop(dismountButton)

	local rideChip = TidetownUi.create("TextButton", {
		Name = "RideChip",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -164, 1, -176),
		Size = UDim2.new(0, 96, 0, ROW_HEIGHT),
		BackgroundColor3 = RIDE_COLOR,
		BorderSizePixel = 0,
		Text = "🏄 Ride",
		TextSize = 18,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Visible = false,
		Parent = screenGui,
	}) :: TextButton
	TidetownUi.round(rideChip, 14)
	TidetownUi.stroke(rideChip, OUTLINE_NAVY, 3)
	TidetownUi.gloss(rideChip)
	TidetownUi.hoverPop(rideChip)

	local rideList = TidetownUi.create("Frame", {
		Name = "RideList",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -232),
		Size = UDim2.new(0, 250, 0, 60),
		BackgroundColor3 = LIST_COLOR,
		BorderSizePixel = 0,
		Visible = false,
		Parent = screenGui,
	}) :: Frame
	TidetownUi.round(rideList, 14)
	TidetownUi.stroke(rideList, OUTLINE_NAVY, 3)

	TidetownUi.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = rideList,
	})

	TidetownUi.cartoonify(screenGui)

	local phase: string = TidePhase.Low
	local ownedKeys: { string } = {}
	local requestBusy = false

	local requestRemote = TidetownRemotes.get("RequestMount") :: RemoteFunction
	local dismountRemote = TidetownRemotes.get("Dismount") :: RemoteFunction

	local function requestMount(mountKey: string)
		-- One request in flight at a time; a lagging InvokeServer must
		-- not queue up a pile of mounts from double-taps.
		if requestBusy then
			return
		end

		requestBusy = true
		local ok, message = requestRemote:InvokeServer(mountKey)
		requestBusy = false

		if ok == true then
			rideList.Visible = false
		else
			Toast.push(
				if typeof(message) == "string" then message else "Cannot ride right now",
				"bad"
			)
		end
	end

	local function addRow(order: number, mountKey: string, text: string)
		local row = TidetownUi.create("TextButton", {
			Name = "Row_" .. mountKey,
			LayoutOrder = order,
			Size = UDim2.new(1, -16, 0, ROW_HEIGHT),
			BackgroundColor3 = ROW_COLOR,
			BorderSizePixel = 0,
			Text = text,
			TextSize = 16,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Parent = rideList,
		}) :: TextButton
		TidetownUi.round(row, 10)
		TidetownUi.stroke(row, OUTLINE_NAVY, 2)

		row.Activated:Connect(function()
			requestMount(mountKey)
		end)
	end

	local function rebuildRideList()
		for _, child in ipairs(rideList:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end

		local loaner = TidetownConfig.mounts.loaner
		addRow(
			1,
			loaner.key,
			mountDisplayText(loaner.name, loaner.speedStudsPerSecond, loaner.deepAccess)
		)

		local rowCount = 1
		for _, mount in ipairs(TidetownConfig.mounts.owned) do
			if table.find(ownedKeys, mount.key) ~= nil then
				rowCount += 1
				addRow(
					rowCount,
					mount.key,
					mountDisplayText(mount.name, mount.speedStudsPerSecond, mount.deepAccess)
				)
			end
		end

		rideList.Size = UDim2.new(0, 250, 0, rowCount * (ROW_HEIGHT + 6) + 10)
	end

	local function refreshVisibility()
		dismountButton.Visible = localPlayer:GetAttribute("Mounted") == true

		-- The loaner comes from the pier prompt, so the chip only earns
		-- its screen space once a real mount is owned.
		local chipVisible = phase == TidePhase.High and #ownedKeys > 0
		rideChip.Visible = chipVisible
		if not chipVisible then
			rideList.Visible = false
		end
	end

	dismountButton.Activated:Connect(function()
		local ok, message = dismountRemote:InvokeServer()
		if ok ~= true and typeof(message) == "string" then
			Toast.push(message, "bad")
		end
	end)

	rideChip.Activated:Connect(function()
		if rideList.Visible then
			rideList.Visible = false
		else
			rebuildRideList()
			TidetownUi.popOpen(rideList)
		end
	end)

	localPlayer:GetAttributeChangedSignal("Mounted"):Connect(refreshVisibility)

	local syncRemote = TidetownRemotes.get("SyncState") :: RemoteEvent
	syncRemote.OnClientEvent:Connect(function(kind, payload)
		if kind ~= "mounts" or typeof(payload) ~= "table" then
			return
		end

		if typeof(payload.mountsOwned) == "table" then
			local keys: { string } = {}
			for _, key in ipairs(payload.mountsOwned) do
				if typeof(key) == "string" then
					table.insert(keys, key)
				end
			end
			ownedKeys = keys
			refreshVisibility()
		end
	end)

	local tideChanged = TidetownRemotes.get("TideChanged") :: RemoteEvent
	tideChanged.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" or typeof(payload.phase) ~= "string" then
			return
		end

		phase = payload.phase
		refreshVisibility()
	end)

	-- Late join: the tide folder attributes already carry the phase in
	-- flight, so the chip is right before the first broadcast lands.
	local tideFolder = Workspace:WaitForChild("Tidetown")
	local initialPhase = tideFolder:GetAttribute("Phase")
	if typeof(initialPhase) == "string" then
		phase = initialPhase
	end

	refreshVisibility()
end

return MountController
