--!strict
--!optimize 2

-- Values
local taskSpawn = task.spawn
local tableInsert = table.insert
local tableRemove = table.remove
local tableUnpack = table.unpack
local tablePack = table.pack
local threadPool = {} :: { thread }

local MAX_RUNNERS = 32

-- Types
-- Signal type
type signalData<callback = (...any?) -> (), args... = ...any?> = {
	_head: Connection<callback, args...>?,
}

type signalPrototype<callback = (...any?) -> (), args... = ...any?> = {
	Fire: (self: Signal<callback, args...>, args...) -> (),
	FireDeferred: (self: Signal<callback, args...>, args...) -> (),
	Connect: (self: Signal<callback, args...>, callback: callback) -> Connection<callback, args...>,
	Once: (self: Signal<callback, args...>, callback: callback) -> Connection<callback, args...>,
	Wait: (self: Signal<callback, args...>) -> args...,
	DisconnectAll: (self: Signal<callback, args...>) -> (),
	Destroy: (self: Signal<callback, args...>) -> (),
}

export type Signal<callback = (...any?) -> (), args... = ...any?> = setmetatable<signalData<callback, args...>, {__index: signalPrototype<callback, args...>}>

-- Connection type
type connectionData<callback = (...any?) -> (), args... = ...any?> = {
	_signal: Signal<callback, args...>?,
	_next: Connection<callback, args...>?,
	_previous: Connection<callback, args...>?,
	_callback: callback?,

	Connected: boolean,
}

type connectionPrototype<callback = (...any?) -> (), args... = ...any?> = {
	Disconnect: (self: Connection<callback, args...>) -> (),
}

export type Connection<callback = (...any?) -> (), args... = ...any?> = setmetatable<connectionData<callback, args...>, {__index: connectionPrototype<callback, args...>}>

-- Functions

--[=[
	@return thread;

	Acquires unused threads which could be reused or creates new one if there's no such and stores another running into
	threadPool.
]=]
local function acquireRunner(): thread
	local amount = #threadPool

	if amount > 0 then
		return tableRemove(threadPool, amount) :: thread
	end

	local runner = coroutine.create(function(callback, args)
		while true do
			local success, errorMessage = xpcall(callback, debug.traceback, tableUnpack(args))

			if not success then
				warn(errorMessage)
			end

			if #threadPool < MAX_RUNNERS then
				tableInsert(threadPool, coroutine.running())
			end

			callback, args = coroutine.yield()
		end
	end)

	return runner
end

-- Connection
local connection = {}
connection._prototype = {} :: connectionPrototype<>
connection.__index = connection._prototype

--[=[
	@return ;

	Disconnects connection.
]=]
function connection._prototype:Disconnect()
	if not self.Connected then
		return
	end

	self.Connected = false

	local signal = self._signal
	local next = self._next
	local previous = self._previous

	if next then
		next._previous = previous
	end

	if previous then
		previous._next = next
	end

	if self == signal._head then
		signal._head = if next then next else if previous then previous else nil
	end

	self._signal = nil
	self._callback = nil
	self._previous = nil
	self._next = nil
end

connection.__metatable = "You're not permitted to get this metatable"

--[=[
	@param signal Signal<callbackT, args...>;
	@param callback callbackT;
	@return Connection<callbackT, args...>;

	Creates new Connection metatable.
]=]
function connection.new<callbackT, args...>(signal: Signal<callbackT, args...>, callback: callbackT): Connection<callbackT, args...>
	local previous = signal._head

	return setmetatable({
		_signal = signal,
		_next = nil,
		_previous = previous,
		_callback = callback,
		Connected = true,
	} :: connectionData<callbackT, args...>, connection) :: Connection<callbackT, args...>
end

setmetatable(connection._prototype, {
	__index = function(_, key)
		if key ~= "_next" and key ~= "_previous"
		and key ~= "_callback" and key ~= "_signal" then
			error(string.format("%s is an invalid member of connection._prototype", tostring(key)))
		end
	end,

	__newindex = function(_, key)
		if key ~= "_next" and key ~= "_previous"
		and key ~= "_callback" and key ~= "_signal" then
			error(string.format("%s is an invalid member of connection._prototype", tostring(key)))
		end
	end,

	__metatable = "You're not permitted to get this metatable"
})

-- Signal
local signal = {}
signal._prototype = {} :: signalPrototype<>
signal.__index = signal._prototype

--[=[
	@param ... args...;
	@return ;

	Fires all connections' callbacks.
]=]
function signal._prototype:Fire(...)
	local node = self._head
	local args = tablePack(...)

	while node do
		taskSpawn(acquireRunner(), node._callback, args)

		node = node._previous
	end
end

--[=[
	@param ... args...;
	@return ;

	Fires all connections' callbacks at the end of resumption cycle.
]=]
function signal._prototype:FireDeferred(...)
	local args = tablePack(...)

	task.defer(function()
		self:Fire(table.unpack(args, 1, args.n))
	end)
end

--[=[
	@param callback callbackT;
	@return Connection<callbackT>;

	Creates Connection metatable with passed callback linked to Signal.
]=]
function signal._prototype:Connect<callbackT>(callback: callbackT): Connection<callbackT>
	local newConnection = connection.new(self, callback)
	local head = self._head

	if head then
		head._next = newConnection
	end
	self._head = newConnection

	return newConnection
end

--[=[
	@param callback callbackT;
	@return Connection<callbackT, args...>;

	Connects the callback and returns a Connection that automatically 
	disconnects itself after the first time the signal is fired.
]=]
function signal._prototype:Once<callbackT>(callback: callbackT): Connection<callbackT>
	local newConnection: Connection<>
	newConnection = self:Connect(function(...)
		newConnection:Disconnect()
		callback(...)
	end)

	return newConnection
end

--[=[
	@return args...;

	Returns arguments passed through :Fire() method. Yields current thread until fire.
]=]
function signal._prototype:Wait<callbackT, Args...>(): Args...
	local freeThread = acquireRunner()

	local newConnection: Connection<callbackT, Args...>
	newConnection = self:Connect(function(...)
		newConnection:Disconnect()
		taskSpawn(freeThread, ...)
	end)

	return coroutine.yield()
end

--[=[
	@return ;

	Disconnects all connections linked to Signal;
]=]
function signal._prototype:DisconnectAll()
	local node = self._head

	while node do
		local previous = node._previous

		node.Connected = false
		node._signal = nil
		node._next = nil
		node._previous = nil
		node._callback = nil

		node = previous
	end

	self._head = nil
end

--[=[
	@return ;

	Unsets metatable, cleaning all links to Signal and disconnects all connections, so
	GC could collect all of them.
]=]
function signal._prototype:Destroy()
	self:DisconnectAll()
	setmetatable(self, nil)
end

signal.__metatable = "You're not permitted to get this metatable"

--[=[
	@return Signal<callbackT, args...>;

	Creates new Signal metatable;
]=]
function signal.new(): Signal<>
	return setmetatable({
		_head = nil :: Connection<>?,
	}, signal) :: Signal<>
end

setmetatable(signal._prototype, {
	__index = function(_, key)
		if key ~= "_head" then
			error(string.format("%s is an invalid member of signal._prototype", tostring(key)))
		end
	end,

	__newindex = function(_, key)
		print(key)
		if key ~= "_head" then
			error(string.format("%s is an invalid member of signal._prototype", tostring(key)))
		end
	end,

	__metatable = "You're not permitted to get this metatable"
})

return table.freeze(signal)
