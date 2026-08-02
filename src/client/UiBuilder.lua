--[[
	Tiny helper for building UI from code. Applies a property table to a
	new instance, setting Parent last so the instance never appears on
	screen half-configured.
]]

local UiBuilder = {}

function UiBuilder.create(className: string, properties: { [string]: any }): Instance
	local instance = Instance.new(className)

	for key, value in pairs(properties) do
		if key ~= "Parent" then
			instance[key] = value
		end
	end

	instance.Parent = properties.Parent

	return instance
end

return UiBuilder
