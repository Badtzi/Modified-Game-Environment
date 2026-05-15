-- Import services
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CustomSignal = require(script.CustomSignal)
local HelperMethods = require(script.HelperMethods)
local TargetFilters = require(script.TargetFilters)

-- Declare module
local Mouse = {}
Mouse.__index = Mouse

-- Create a new mouse instance
function Mouse.new()
	local m = {}
	
	m._ignoreGameProcessedEvents = true
	m._rayLength = 500
	m._filterType = Enum.RaycastFilterType.Exclude
	m._collisionGroup = "Default"
	m._ignoreWater = true
	
	m.Location = Vector2.new()
	m.X = 0
	m.Y = 0

	m.ViewSize = Vector2.new()
	m.ViewSizeX = 0
	m.ViewSizeY = 0
	
	m.TargetFilters = TargetFilters.new()
	m.UnitRay = Ray.new()
	m.Origin = CFrame.new()
	m.Hit = CFrame.new()
	m.Target = nil

	m.Button1Down = CustomSignal.new()
	m.Button1Up = CustomSignal.new()
	m.Button2Down = CustomSignal.new()
	m.Button2Up = CustomSignal.new()
	m.Button3Down = CustomSignal.new()
	m.Button3Up = CustomSignal.new()
	m.Move = CustomSignal.new()
	m.WheelBackward = CustomSignal.new()
	m.WheelForward = CustomSignal.new()

	-- The Idle method still requires an implementation.
	m.Idle = CustomSignal.new()
	
	HelperMethods.connectSignals(m)

	return setmetatable(m, Mouse)
end

-- Get the x,y location of the mouse on the screen
function Mouse:GetLocation(): Vector2
	return UserInputService:GetMouseLocation()
end

-- Get the change in x,y of the mouse position since the last recorded position
function Mouse:GetDelta(): Vector2
	return UserInputService:GetMouseDelta()
end

-- Get the ray length of the rays the mouse uses
function Mouse:GetRayLength(): number
	return self._rayLength	
end

-- Set the ray length of the rays the mouse uses
function Mouse:SetRayLength(rayLength: number): nil
	assert(typeof(rayLength) == "number", "Ray length must be a number")
	self._rayLength = rayLength
end

-- Enables the icon of the mouse
function Mouse:EnableIcon(): nil
	UserInputService.MouseIconEnabled = true
end

-- Disables the icon of the mouse
function Mouse:DisableIcon(): nil
	UserInputService.MouseIconEnabled = false
end

-- Gets the raycast filtertype
function Mouse:GetFilterType(): Enum.RaycastFilterType
	return self._filterType
end

-- Sets the raycast filtertype
function Mouse:SetFilterType(filterType: Enum.RaycastFilterType): nil
	assert(typeof(filterType) == "EnumItem", "Invalid filter type provided")
	self._filterType = filterType
end

-- Gets the raycast's collision group
function Mouse:GetCollisionGroup(): string
	return self._collisionGroup
end

-- Sets the raycast's collision group
function Mouse:SetCollisionGroup(name: string): nil
	if not PhysicsService:IsCollisionGroupRegistered(name) then 
		warn('invalid collision group provided, setting to default')
		self._collisionGroup = 'Default'
		return
	end
	
	self._collisionGroup = name
end

-- Checks if water is ignored while raycasting or not
function Mouse:GetIgnoreWater(): boolean
	return self._ignoreWater
end

-- Enables or disables whether water should be ignored while raycasting
function Mouse:SetIgnoreWater(ignoreWater: boolean): nil
	self._ignoreWater = ignoreWater and true or false
end

return Mouse