--!strict

-- Values
local taskSpawn = task.spawn
local tableInsert = table.insert
local tableRemove = table.remove
local tableUnpack = table.unpack
local tablePack = table.pack
local threadPool = {} :: { thread }

local MAX_RUNNERS = 8

-- Functions

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
connection.__prototype = {}
connection.__index = connection.__prototype

type ConnectionPrototype<Args...> = {
	Disconnect: (self: Connection<Args...>) -> (),
}

type ConnectionData<Args...> = {
	_signal: Signal<Args...>,
	_next: Connection<Args...>?,
	_previous: Connection<Args...>?,
	_callback: (Args...) -> (),

	Connected: boolean,
}

export type Connection<Args...> = setmetatable<ConnectionData<Args...>, { __index: ConnectionPrototype<Args...> }>

function connection.__prototype:Disconnect()
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

function connection.new<Args...>(signal: Signal<Args...>, callback: (Args...) -> ()): Connection<Args...>
	local previous = signal._head

	return setmetatable({
		_signal = signal :: Signal<Args...>?,
		_next = nil :: Connection<Args...>?,
		_previous = previous :: Connection<Args...>?,
		_callback = callback :: (Args...) -> (),

		Connected = true,
	}, connection) :: Connection<Args...>
end

-- Signal
local signal = {}
signal.__prototype = {}
signal.__index = signal.__prototype

type SignalPrototype<Args...> = {
	Fire: (self: SignalPrototype<Args...>, Args...) -> (),
	Connect: (self: SignalPrototype<Args...>, callback: (Args...) -> ()) -> Connection<Args...>,
	Wait: (self: SignalPrototype<Args...>) -> Args...,
	DisconnectAll: (self: SignalPrototype<Args...>) -> (),
	Destroy: (self: SignalPrototype<Args...>) -> (),
}

type SignalData<Args...> = {
	_head: Connection<Args...>?,
}

export type Signal<Args...> = setmetatable<SignalData<Args...>, { __index: SignalPrototype<Args...> }>

function signal.__prototype:Fire(...)
	local node = self._head

	while node do
		taskSpawn(acquireRunner(), node._callback, tablePack(...))

		node = node._previous
	end
end

function signal.__prototype:Connect<Args...>(callback: (Args...) -> ()): Connection<Args...>
	local newConnection = connection.new(self, callback)
	local head = self._head

	if head then
		head._next = newConnection
	end
	self._head = newConnection

	return newConnection
end

function signal.__prototype:Wait<Args...>(): Args...
	local freeThread = acquireRunner()

	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		taskSpawn(freeThread, ...)
	end)

	return coroutine.yield()
end

function signal.__prototype:DisconnectAll()
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

function signal.__prototype:Destroy()
	self:DisconnectAll()
	setmetatable(self, nil)
end

function signal.new<Args...>(): Signal<Args...>
	return setmetatable({
		_head = nil :: Connection<Args...>?,
	}, signal) :: Signal<Args...>
end

return table.freeze(signal)
