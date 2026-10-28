--!strict

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
type signalData<callback = (...any?) -> (), Args... = ...any?> = {
	_head: Connection<callback, Args...>?,
}

type signalPrototype<callback = (...any?) -> (), Args... = ...any?> = {
	Fire: (self: Signal<callback, Args...>, Args...) -> (),
	FireDeferred: (self: Signal<callback, Args...>, Args...) -> (),
	Connect: (self: Signal<callback, Args...>, callback: callback) -> Connection<callback, Args...>,
	Once: (self: Signal<callback, Args...>, callback: callback) -> Connection<callback, Args...>,
	Wait: (self: Signal<callback, Args...>) -> Args...,
	DisconnectAll: (self: Signal<callback, Args...>) -> (),
	Destroy: (self: Signal<callback, Args...>) -> (),
}

export type Signal<callback = (...any?) -> (), Args... = ...any?> = setmetatable<signalData<callback, Args...>, {__index: signalPrototype<callback, Args...>}>

-- Connection type
type connectionData<callback = (...any?) -> (), Args... = ...any?> = {
	_signal: Signal<callback, Args...>?,
	_next: Connection<callback, Args...>?,
	_previous: Connection<callback, Args...>?,
	_callback: callback?,

	Connected: boolean,
}

type connectionPrototype<callback = (...any?) -> (), Args... = ...any?> = {
	Disconnect: (self: Connection<callback, Args...>) -> (),
}

export type Connection<callback = (...any?) -> (), Args... = ...any?> = setmetatable<connectionData<callback, Args...>, {__index: connectionPrototype<callback, Args...>}>

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

--[=[
	@param signal Signal<callbackT>;
	@param callback callbackT;
	@return Connection<callbackT>;

	Creates new Connection metatable.
]=]
function connection.new<callbackT>(signal: Signal<callbackT>, callback: callbackT): Connection<callbackT>
	local previous = signal._head

	return setmetatable({
		_signal = signal :: Signal<callbackT>?,
		_next = nil :: Connection<callbackT>?,
		_previous = previous :: Connection<callbackT>?,
		_callback = callback :: callbackT?,
	}, connection) :: Connection<callbackT>
end

-- Signal
local signal = {}
signal._prototype = {} :: signalPrototype<>
signal.__index = signal._prototype

--[=[
	@param ... Args...;
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
	@param ... Args...;
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
	@return Connection<callbackT>;

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
	@return Args...;

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

--[=[
	@return Signal<callbackT>;

	Creates new Signal metatable;
]=]
function signal.new(): Signal<>
	return setmetatable({
		_head = nil :: Connection<>?,
	}, signal) :: Signal<>
end

return table.freeze(signal)
