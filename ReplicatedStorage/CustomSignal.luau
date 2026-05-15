local CustomConnection = require(script.CustomConnection)

local CustomSignal = {}
CustomSignal.__index = CustomSignal

function CustomSignal.new()
	local signal = {}
	signal.connections = {}
	
	return setmetatable(signal, CustomSignal)
end

function CustomSignal:Run()
	for i, connection in pairs(self.connections) do
		connection:Run()
	end
end

function CustomSignal:Connect(func: () -> nil)
	local newConnection = CustomConnection.new(func)
	table.insert(self.connections, newConnection)
	return newConnection
end

return CustomSignal
