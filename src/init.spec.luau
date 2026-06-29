return function()
	local signal = require(script.Parent)

	local newSignal: signal.Signal<...number | { number }>

	beforeEach(function()
		newSignal = signal.new() :: signal.Signal<...number | { number }>
	end)

	afterEach(function()
		newSignal:Destroy()
	end)

	describe("fire", function()
		it("should be able to pass primitive arguments", function()
			local toSend = 10
			local value

			newSignal:Connect(function(recieved)
				value = recieved
			end)

			newSignal:Fire(toSend)
			expect(value).to.equal(toSend)
		end)

		it("should be able to pass non-primitive arguments", function()
			local toSend = { 10, 20 }
			local value

			newSignal:Connect(function(recieved)
				value = recieved
			end)

			newSignal:Fire(toSend)
			expect(value).to.equal(toSend)
		end)
	end)

	describe("wait", function()
		it("should be able to wait for signal to be fired", function()
			local toSend1 = 10
			local toSend2 = 20

			coroutine.create(function()
				local waitResult1, waitResult2 = newSignal:Wait()
				expect(waitResult1).to.equal(toSend1)
				expect(waitResult2).to.equal(toSend2)
			end)

			newSignal:Fire(toSend1, toSend2)
		end)
	end)

	describe("disconnectAll", function()
		it("should disconnect all connections", function()
			local connection1 = newSignal:Connect(function() end)
			local connection2 = newSignal:Connect(function() end)
			newSignal:DisconnectAll()

			expect(connection1.Connected).to.equal(false)
			expect(connection2.Connected).to.equal(false)
		end)
	end)

	describe("disconnect", function()
		it("should disconnect connection", function()
			local connection = newSignal:Connect(function() end)
			connection:Disconnect()

			expect(connection.Connected).to.equal(false)
		end)

		it("should still work if connections are disconnected while firing", function()
			local value = 0

			newSignal:Connect(function()
				value += 1
			end)

			local connection
			connection = newSignal:Connect(function()
				connection:Disconnect()
				value += 1
			end)

			newSignal:Connect(function()
				value += 1
			end)

			newSignal:Fire()

			expect(value).to.equal(3)
		end)
	end)
end
