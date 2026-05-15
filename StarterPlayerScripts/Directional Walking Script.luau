-- Crouch-only directional hip rotation.
-- Hips face movement direction while crouching to compensate for missing
-- crouch-strafe animations. Hips only -- does not write RootJoint or Neck
-- (Realistic Head Movement owns Neck; aim/shiftlock systems own torso).

local RunService = game:GetService('RunService')
local plr = game.Players.LocalPlayer

local RANGE_OF_MOTION = math.rad(45)
local RANGE_OF_MOTION_XZ = 45 / 140
local LERP_SPEED = 0.005
local REST_EPSILON = 0.0005

local state

local function buildState(chr)
	local hum = chr:WaitForChild('Humanoid', 5)
	local hrp = chr:WaitForChild('HumanoidRootPart', 5)
	local torso = chr:WaitForChild('Torso', 5)
	if not (hum and hrp and torso) then return nil end

	local rightHip = torso:WaitForChild('Right Hip', 5)
	local leftHip = torso:WaitForChild('Left Hip', 5)
	if not (rightHip and leftHip) then return nil end

	return {
		chr = chr,
		hum = hum,
		hrp = hrp,
		rightHip = rightHip,
		leftHip = leftHip,
		rightHipC0 = rightHip.C0,
		leftHipC0 = leftHip.C0,
		atRest = true,
	}
end

if plr.Character then
	state = buildState(plr.Character)
end

plr.CharacterAdded:Connect(function(chr)
	state = buildState(chr)
end)

local function shouldRun(s)
	if not s.chr.Parent then return false end
	if s.hum.Health <= 0 then return false end
	if not s.chr:GetAttribute("IsCrouching") then return false end
	if s.chr:GetAttribute("BipodActive") then return false end
	if s.chr:GetAttribute("BipodDeploying") then return false end
	if s.chr:GetAttribute("IsProne") then return false end
	if s.chr:GetAttribute("TakedownActive") then return false end
	if s.chr:GetAttribute("InTakedown") then return false end
	return true
end

RunService.RenderStepped:Connect(function(dt)
	if not state then return end

	pcall(function()
		local s = state
		local active = shouldRun(s)
		local targetRight = s.rightHipC0
		local targetLeft = s.leftHipC0

		if active and s.hum.WalkSpeed > 0 then
			local dir = s.hrp.CFrame:VectorToObjectSpace(s.hrp.AssemblyLinearVelocity)
			dir = Vector3.new(dir.X / s.hum.WalkSpeed, 0, dir.Z / s.hum.WalkSpeed)

			local x = dir.X * (RANGE_OF_MOTION - (math.abs(dir.Z) * (RANGE_OF_MOTION / 2)))
			local xz = dir.X * (RANGE_OF_MOTION_XZ - (math.abs(dir.Z) * (RANGE_OF_MOTION_XZ / 2)))

			if dir.Z > 0.1 then
				x = -x
				xz = -xz
			end

			targetRight = s.rightHipC0 * CFrame.new(-xz, 0, 0) * CFrame.Angles(0, -x, 0)
			targetLeft = s.leftHipC0 * CFrame.new(-xz, 0, 0) * CFrame.Angles(0, -x, 0)
			s.atRest = false
		end

		if s.atRest and not active then return end

		local t = 1 - LERP_SPEED ^ dt
		s.rightHip.C0 = s.rightHip.C0:Lerp(targetRight, t)
		s.leftHip.C0 = s.leftHip.C0:Lerp(targetLeft, t)

		if not active then
			local rDelta = (s.rightHip.C0.Position - s.rightHipC0.Position).Magnitude
			local lDelta = (s.leftHip.C0.Position - s.leftHipC0.Position).Magnitude
			if rDelta < REST_EPSILON and lDelta < REST_EPSILON then
				s.rightHip.C0 = s.rightHipC0
				s.leftHip.C0 = s.leftHipC0
				s.atRest = true
			end
		end
	end)
end)
