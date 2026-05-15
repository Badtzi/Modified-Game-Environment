local UserInputService = game:GetService("UserInputService")

local HelperMethods = {}

local Camera = workspace.Camera

local function mustIgnoreInput(m, gameProcessedEvent): boolean
	return m._ignoreGameProcessedEvents and gameProcessedEvent
end

local function getRaycastParameters(m)
	local parameters = RaycastParams.new()
	parameters.CollisionGroup = m._collisionGroup
	parameters.FilterDescendantsInstances = m.TargetFilters:Get()
	parameters.FilterType = m._filterType
	parameters.IgnoreWater = m._ignoreWater
	return parameters
end

local function castRay(m)
	return workspace:Raycast(m.Origin.Position, m.UnitRay.Direction * m._rayLength, getRaycastParameters(m))
end

local function updateLocation(m)
	m.Location = m:GetLocation()
	m.X = m.Location.X
	m.Y = m.Location.Y

	m.ViewSize = Camera.ViewportSize
	m.ViewSizeX = m.ViewSize.X
	m.ViewSizeY = m.ViewSize.Y

	m.UnitRay = Camera:ViewportPointToRay(m.X, m.Y)
	m.Origin = CFrame.new(m.UnitRay.Origin)
	
	local raycastResult = castRay(m)
	
	if raycastResult then
		m.Hit = CFrame.new(raycastResult.Position)
		m.Target = raycastResult.Instance
	else
		m.Hit = m.Origin + (m.UnitRay.Direction * m._rayLength)
		m.Target = nil
	end
end

local function onInputBegan(m, input, gameProcessedEvent)
	if mustIgnoreInput(m, gameProcessedEvent) then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		m.Button1Down:Run()
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		m.Button2Down:Run()
	end
	
	if input.UserInputType == Enum.UserInputType.MouseButton3 then
		m.Button3Down:Run()
	end
end

local function onInputEnded(m, input, gameProcessedEvent)
	if mustIgnoreInput(m, gameProcessedEvent) then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		m.Button1Up:Run()
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		m.Button2Up:Run()
	end
	
	if input.UserInputType == Enum.UserInputType.MouseButton3 then
		m.Button3Up:Run()
	end
end

local function onInputChanged(m, input, gameProcessedEvent)
	if mustIgnoreInput(m, gameProcessedEvent) then
		return
	end
	
	updateLocation(m)
	
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		m.Move:Run()
	end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		if input.Position.Z == 1 then
			m.WheelForward:Run()
		elseif input.Position.Z == -1 then
			m.WheelBackward:Run()
		end
	end
end

function HelperMethods.connectSignals(m)
	UserInputService.InputChanged:Connect(function(input, gameProcessedEvent)
		onInputChanged(m, input, gameProcessedEvent)
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
		onInputBegan(m, input, gameProcessedEvent)
	end)

	UserInputService.InputEnded:Connect(function(input, gameProcessedEvent)
		onInputEnded(m, input, gameProcessedEvent)
	end)
end

return HelperMethods
