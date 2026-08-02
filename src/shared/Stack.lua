--[[
	A last-in, first-out container. Doubles as the project's reference
	implementation of the typed prototype-based class pattern described in
	STYLE_GUIDE.md, so new classes can copy its shape.
]]

local Stack = {}
Stack.__index = Stack

export type ClassType = typeof(setmetatable(
	{} :: {
		_items: { any },
		_size: number,
	},
	Stack
))

function Stack.new(): ClassType
	local self = {
		_items = {},
		_size = 0,
	}

	setmetatable(self, Stack)

	return self
end

function Stack.push(self: ClassType, item: any)
	self._size += 1
	self._items[self._size] = item
end

function Stack.pop(self: ClassType): any
	if self._size == 0 then
		return nil
	end

	local item = self._items[self._size]

	-- Clear the slot so popped values can be garbage collected instead of
	-- lingering in the array.
	self._items[self._size] = nil
	self._size -= 1

	return item
end

function Stack.peek(self: ClassType): any
	return self._items[self._size]
end

function Stack.isEmpty(self: ClassType): boolean
	return self._size == 0
end

function Stack.isStack(instance): boolean
	return getmetatable(instance) == Stack
end

return Stack
