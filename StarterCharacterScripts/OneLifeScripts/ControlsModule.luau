local controls = {}

-- VARIABLES
local plr = game.Players.LocalPlayer
local chr = plr.Character

local plrconfig = chr:WaitForChild('TREK_PlrConfig')

controls.sprinting = plrconfig:WaitForChild('Sprinting')
controls.sprintstate = plrconfig:WaitForChild('SprintEnabled')
controls.crouching = plrconfig:WaitForChild('Crouching')

-- Prone controller: lives in TREK_SERVICES > TREK_Modules > ProneController
local ProneController
pcall(function()
	ProneController = require(shared.S.TREK_Modules.ProneController)
end)
if not ProneController then
	warn("[ControlsModule] ProneController not found, prone disabled")
end

local proneActive = false
local suppressCrouchHandler = false

-- MODULES
local pars = RaycastParams.new()
pars.FilterType = Enum.RaycastFilterType.Exclude
pars.IgnoreWater = false
pars.FilterDescendantsInstances = {workspace:WaitForChild('IgnoreList'),chr}

-- ============================================================
-- CROUCH (C key — goes deeper: standing ? crouch ? prone)
-- ============================================================

function controls.crouch()
	if not shared.S.globalConfig.canCrouch then return end
	if chr.Humanoid.SeatPart and not controls.crouching.Value then return end

	if proneActive then
		return
	end

	if controls.crouching.Value then
		controls.startProne()
	else
		controls.crouching.Value = true
	end
end

-- ============================================================
-- UNCROUCH (X key — goes higher: prone ? crouch ? standing)
-- ============================================================

function controls.uncrouch()
	if proneActive then
		controls.stopProne()
	elseif controls.crouching.Value then
		controls.crouching.Value = false
	end
end

-- ============================================================
-- SPRINT
-- ============================================================

function controls.sprint()
	if not shared.S.globalConfig.canSprint then return end
	if chr.Humanoid.SeatPart and not controls.sprintstate.Value then return end

	if plrconfig.CanSprint.Value then controls.sprintstate.Value = not controls.sprintstate.Value end
end

function controls.stopSprint()
	controls.sprintstate.Value = false
	controls.sprinting.Value = false
	-- Don't change WalkSpeed if prone (prone sets WalkSpeed = 0)
	if not proneActive then
		chr:WaitForChild("Humanoid").WalkSpeed = shared.S.globalConfig.Default
	end
end

function controls.startSprint()
	if not shared.S.globalConfig.canSprint then return end
	if chr.Humanoid.SeatPart and not controls.sprintstate.Value then return end
	if not plrconfig.CanSprint.Value then return end

	if proneActive then
		controls.stopProne()
	end
	if controls.crouching.Value then
		controls.crouching.Value = false
	end

	controls.sprintstate.Value = true
end

-- ============================================================
-- CROUCH STATE HANDLERS
-- ============================================================

function controls.startCrouch()
	if proneActive then return end -- don't apply crouch settings during prone
	if controls.sprintstate.Value then controls.sprint() end

	task.wait()

	chr:WaitForChild('Humanoid').WalkSpeed = (shared.S.globalConfig.Crouch)

	chr:SetAttribute("IsCrouching", true)
	if chr:WaitForChild('Humanoid').RigType == Enum.HumanoidRigType.R6 then chr:WaitForChild('Humanoid').HipHeight = -1.1 end
end

function controls.stopCrouch()
	if proneActive then return end -- don't apply standing settings during prone
	if chr:WaitForChild('Humanoid').RigType == Enum.HumanoidRigType.R6 then chr:WaitForChild('Humanoid').HipHeight = 0 end

	chr:SetAttribute("IsCrouching", false)
	chr:WaitForChild('Humanoid').WalkSpeed = (not controls.sprintstate.Value and shared.S.globalConfig.Default or shared.S.globalConfig.Sprint)
end

-- ============================================================
-- PRONE STATE HANDLERS
-- ============================================================

function controls.startProne()
	proneActive = true
	chr:SetAttribute("IsProne", true)
	chr:SetAttribute("IsCrouching", false)

	-- Set Crouching BoolValue = true so the state machine is consistent.
	-- The suppress flag stays true through the next resumption cycle so
	-- MovementHandler's deferred crouchingChanged listener sees it.
	if not controls.crouching.Value then
		suppressCrouchHandler = true
		controls.crouching.Value = true
		task.defer(function()
			suppressCrouchHandler = false
		end)
	end

	-- Clear sprint state if active — prone overrides everything
	if controls.sprintstate.Value then
		controls.sprintstate.Value = false
	end
	if controls.sprinting.Value then
		controls.sprinting.Value = false
	end
	chr:SetAttribute("IsSprinting", false)

	local hum = chr:WaitForChild('Humanoid')

	-- Only set HipHeight if not already at prone value (dive tween may have
	-- already brought it there — re-writing causes a one-frame jitter)
	if hum.RigType == Enum.HumanoidRigType.R6 then
		if math.abs(hum.HipHeight - (-2)) > 0.5 then
			hum.HipHeight = -2
		end
	end

	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.AutoRotate = false

	-- Kill any residual velocity (from dive, sprint, etc.) so the character
	-- doesn't slide after entering prone
	local hrp = chr:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
	end

	if ProneController then
		ProneController.enter(chr, hum)
	else
		warn("[ControlsModule] ProneController is nil, cannot enter prone visuals")
	end
end

function controls.stopProne()
	if ProneController then
		ProneController.exit(chr, chr:WaitForChild('Humanoid'))
	end

	proneActive = false
	chr:SetAttribute("IsProne", false)

	local hum = chr:WaitForChild('Humanoid')

	if hum.RigType == Enum.HumanoidRigType.R6 then
		hum.HipHeight = -1.1
	end

	hum.WalkSpeed = shared.S.globalConfig.Crouch
	hum.JumpPower = 50
	hum.AutoRotate = true

	chr:SetAttribute("IsCrouching", true)
end

function controls.isProne()
	return proneActive
end

function controls.isCrouchSuppressed()
	return suppressCrouchHandler
end

return controls
