--Camera bobbing

local runService = game:GetService("RunService")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")

local WALK_BOB_INTENSITY = 0.25
local SPRINT_BOB_INTENSITY = 0.50

function updateBobbleEffect()
	local currentTime = tick()

	if humanoid.MoveDirection.Magnitude > 0 then
		local isSprinting = character:GetAttribute("IsSprinting") == true
		local bobIntensity = isSprinting and SPRINT_BOB_INTENSITY or WALK_BOB_INTENSITY

		local bobbleX = math.cos(currentTime * 10) * bobIntensity
		local bobbleY = math.abs(math.sin(currentTime * 10)) * bobIntensity        

		local bobble = Vector3.new(bobbleX, bobbleY, 0)

		humanoid.CameraOffset = humanoid.CameraOffset:Lerp(bobble, .10)
	else
		humanoid.CameraOffset = humanoid.CameraOffset * .75
	end
end

runService.RenderStepped:Connect(updateBobbleEffect)