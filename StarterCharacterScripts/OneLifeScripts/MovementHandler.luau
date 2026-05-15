-- GLOBALS
repeat wait() until game.Players.LocalPlayer.Character
repeat wait() until game.Players.LocalPlayer.CharacterAppearanceLoaded

local plr = game.Players.LocalPlayer
local chr = plr.Character
local hum:Humanoid = chr:WaitForChild('Humanoid')
local plrconfig = chr:WaitForChild('TREK_PlrConfig')

game.Players.LocalPlayer.Character:WaitForChild('Humanoid')
game.Players.LocalPlayer.Character:WaitForChild('TREK_PlrConfig')
game.Players.LocalPlayer.PlayerGui:WaitForChild('GunHud')

-- MODULES
local controls = require(script.Parent:WaitForChild('ControlsModule'))

-- LOCAL VALUES
local lasthealth = chr.Humanoid.Health

local tween = function(object,goal,tt,es,ed)
	return game:GetService("TweenService"):Create(object,TweenInfo.new(tt,Enum.EasingStyle[es],Enum.EasingDirection[ed],0,false,0),goal)
end

-- FUNCTIONS
local function input(input, done)
	if input.KeyCode == shared.S.globalConfig.SprintKey then
		controls.startSprint()
		return
	end

	if done then return end

	local inputs = {
		[shared.S.globalConfig.CrouchKey] = controls.crouch;
		[shared.S.globalConfig.UncrouchKey or Enum.KeyCode.X] = controls.uncrouch;
	}

	local func = inputs[input.KeyCode]
	if func then
		func()
	end
end

local function sprintStateChanged()
	if controls.sprintstate.Value == false then
		controls.stopSprint()
	else
		controls.startSprint()
	end
end

local function sprintingChanged()	
	if controls.sprinting.Value == true then		
		if controls.crouching.Value == true then controls.crouch() end

		chr:SetAttribute("IsSprinting", true)
		chr:WaitForChild('Humanoid').WalkSpeed = shared.S.globalConfig.Sprint
	else
		chr:SetAttribute("IsSprinting", false)

		-- Don't change WalkSpeed if prone (prone sets WalkSpeed = 0)
		if controls.isProne() then return end

		if not controls.crouching.Value then
			chr:WaitForChild('Humanoid').WalkSpeed = shared.S.globalConfig.Default
		end
	end
end

local function crouchingChanged()
	-- Skip if prone system is setting Crouching.Value internally
	if controls.isCrouchSuppressed() then return end

	if controls.crouching.Value == true then
		controls.startCrouch()
	else
		controls.stopCrouch()
	end
end

local function seatChanged()
	if hum.SeatPart then
		if controls.sprintstate.Value then controls.stopSprint() end
		if controls.isProne() then controls.stopProne() end
		if controls.crouching.Value then controls.crouch() end

		plrconfig.CanSprint.Value = false
	else
		plrconfig.CanSprint.Value = true
	end
end

-- EXECUTION
game:GetService("UserInputService").InputBegan:Connect(input)

game:GetService("UserInputService").InputEnded:Connect(function(input, done)
	if input.KeyCode == shared.S.globalConfig.SprintKey then
		controls.stopSprint()
	end
end)

hum.WalkSpeed = shared.S.globalConfig.Default
chr:SetAttribute("IsSprinting", false)
chr:SetAttribute("IsCrouching", false)
chr:SetAttribute("IsProne", false)

hum.WalkSpeed = shared.S.globalConfig.Default

controls.sprintstate:GetPropertyChangedSignal('Value'):Connect(sprintStateChanged)
controls.sprinting:GetPropertyChangedSignal('Value'):Connect(sprintingChanged)
controls.crouching:GetPropertyChangedSignal('Value'):Connect(crouchingChanged)

hum:GetPropertyChangedSignal('SeatPart'):Connect(seatChanged)
seatChanged()

while true do
	if chr:WaitForChild("Humanoid").MoveDirection.Magnitude > 0 then
		if controls.crouching.Value == true then
			-- Animate handles crouch movement
		elseif controls.isProne() then
			-- Prone crawl handled by ProneController
		elseif controls.sprintstate.Value == true then
			controls.sprinting.Value = true
		end
	elseif chr:WaitForChild("Humanoid").MoveDirection.Magnitude <= 0 then
		if controls.crouching.Value == true then
			-- Animate handles crouch idle
		elseif controls.isProne() then
			-- Prone idle handled by ProneController
		elseif controls.sprintstate.Value == true then
			controls.sprinting.Value = false
		end
	end

	task.wait(.1)
end
