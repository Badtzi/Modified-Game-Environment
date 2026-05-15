--[[
	AimReplication.luau
	Place in: StarterCharacterScripts
	
	Rotates the upper body (arms + weapon) to follow aim pitch for all players.
	- Local player: reads camera pitch directly (no network delay)
	- Other players: reads AimPitch attribute set by server via ReplicateAim remote
	- Only applies when a tool is equipped
	- Smoothly lerps to prevent jitter
	
	R6 only.
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Character = script.Parent
local Humanoid = Character:WaitForChild("Humanoid")

-- R6 shoulder C0 decomposed into position and rotation
-- Right Shoulder default C0 = CFrame.new(1, 0.5, 0) * CFrame.Angles(0, math.pi/2, 0)
-- Left Shoulder default C0  = CFrame.new(-1, 0.5, 0) * CFrame.Angles(0, -math.pi/2, 0)
local RIGHT_SHOULDER_POS = CFrame.new(1, 0.5, 0)
local RIGHT_SHOULDER_ROT = CFrame.Angles(0, math.pi / 2, 0)
local LEFT_SHOULDER_POS = CFrame.new(-1, 0.5, 0)
local LEFT_SHOULDER_ROT = CFrame.Angles(0, -math.pi / 2, 0)

-- Settings
local LERP_SPEED = 12
local MAX_PITCH = math.rad(70)

-- Per-player tracking
local playerAimData = {}

local function getToolEquipped(character)
	return character:FindFirstChildOfClass("Tool") ~= nil
end

local function processCharacter(dt, player, character)
	if not character then return end
	local hum = character:FindFirstChild("Humanoid")
	if not hum or hum.RigType ~= Enum.HumanoidRigType.R6 then return end

	local torso = character:FindFirstChild("Torso")
	if not torso then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")

	local rightShoulder = torso:FindFirstChild("Right Shoulder")
	local leftShoulder = torso:FindFirstChild("Left Shoulder")
	if not rightShoulder or not leftShoulder then return end

	local hasToolEquipped = getToolEquipped(character)
	local inTakedown = character:GetAttribute("TakedownActive")
		or character:GetAttribute("BipodActive")
		or character:GetAttribute("BipodDeploying")
		or character:GetAttribute("PatrolActive")
		or character:GetAttribute("InspectActive")
		or false
	local inProne = character:GetAttribute("IsProne") or false

	-- Prone with no tool: reset arms to defaults and skip entirely.
	-- The prone animation handles arm positioning when unarmed. Without this,
	-- the pitch compensation (torso is ~90° rotated in prone) produces extreme
	-- arm angles that fling the arms upward.
	if inProne and not hasToolEquipped then
		rightShoulder.C0 = RIGHT_SHOULDER_POS * RIGHT_SHOULDER_ROT
		leftShoulder.C0 = LEFT_SHOULDER_POS * LEFT_SHOULDER_ROT
		return
	end

	-- Get target pitch (zero during takedowns so arms follow the takedown animation)
	local targetPitch = 0
	if hasToolEquipped and not inTakedown then
		if player == LocalPlayer then
			targetPitch = math.asin(workspace.CurrentCamera.CFrame.LookVector.Y)
		else
			targetPitch = character:GetAttribute("AimPitch") or 0
		end
		-- During prone, remove pitch clamp. The extreme torso rotation shifts the
		-- effective pitch range — the normal ±70° clamp cuts off valid aim directions
		-- and causes the gun to stick in weird orientations.
		if not inProne then
			targetPitch = math.clamp(targetPitch, -MAX_PITCH, MAX_PITCH)
		end
	end

	-- Initialize tracking
	if not playerAimData[player] then
		playerAimData[player] = {
			currentPitch = 0,
			savedToolAnimC0 = nil,
			savedToolAnimInstance = nil, -- track which Motor6D we captured from
		}
	end
	local data = playerAimData[player]

	-- Smooth lerp
	data.currentPitch = data.currentPitch + (targetPitch - data.currentPitch) * (1 - math.exp(-dt * LERP_SPEED))

	if math.abs(data.currentPitch) < 0.001 and (not hasToolEquipped or inTakedown) then
		data.currentPitch = 0
		data.savedToolAnimC0 = nil
	end

	-- During takedowns, force pitch to zero immediately (no lerp) and skip all C0 modification
	if inTakedown then
		data.currentPitch = 0
		-- Restore default shoulder C0 so takedown animation has full control
		rightShoulder.C0 = RIGHT_SHOULDER_POS * RIGHT_SHOULDER_ROT
		leftShoulder.C0 = LEFT_SHOULDER_POS * LEFT_SHOULDER_ROT
		-- Restore toolAnim C0
		local toolAnim = torso:FindFirstChild("toolAnim")
		if toolAnim and data.savedToolAnimC0 then
			toolAnim.C0 = data.savedToolAnimC0
			data.savedToolAnimC0 = nil
		end
		return
	end

	local pitch = data.currentPitch

	-- Compensate for Torso's animated pitch relative to HRP.
	if hrp and torso then
		local hrpPitch = math.asin(hrp.CFrame.LookVector.Y)
		local torsoPitch = math.asin(torso.CFrame.LookVector.Y)
		pitch = pitch - (torsoPitch - hrpPitch)
	end

	-- AimLockDisabled: skip all arm/tool rotation (reset to defaults)
	-- Used when weapon is in a "neutral" state (e.g. grenade EMPTY after throw)
	local aimDisabled = character:GetAttribute("AimLockDisabled") or false
	if aimDisabled then
		rightShoulder.C0 = RIGHT_SHOULDER_POS * RIGHT_SHOULDER_ROT
		leftShoulder.C0 = LEFT_SHOULDER_POS * LEFT_SHOULDER_ROT
		local toolAnim = torso:FindFirstChild("toolAnim")
		if toolAnim and data.savedToolAnimC0 then
			toolAnim.C0 = data.savedToolAnimC0
		end
		return
	end

	-- Yaw compensation: only when YawLockActive attribute is true
	local yawCompensation = 0
	local yawActive = character:GetAttribute("YawLockActive") or false
	if yawActive and hrp and torso then
		local relCF = hrp.CFrame:ToObjectSpace(torso.CFrame)
		local _, yawOffset, _ = relCF:ToEulerAnglesYXZ()
		yawCompensation = yawOffset
	end

	-- Combined aim CFrame (both rotate around Torso center)
	local aimCF = CFrame.Angles(pitch, -yawCompensation, 0)

	-- Apply to shoulders (aimCF first = shared pivot at Torso center)
	rightShoulder.C0 = aimCF * RIGHT_SHOULDER_POS * RIGHT_SHOULDER_ROT
	leftShoulder.C0 = aimCF * LEFT_SHOULDER_POS * LEFT_SHOULDER_ROT

	-- Apply to weapon (same shared pivot)
	local toolAnim = torso:FindFirstChild("toolAnim")
	if toolAnim and hasToolEquipped then
		-- Re-capture C0 if the toolAnim Motor6D was recreated (mode switch, re-equip)
		-- or if we don't have a saved C0 yet
		if not data.savedToolAnimC0 or data.savedToolAnimInstance ~= toolAnim then
			data.savedToolAnimC0 = toolAnim.C0
			data.savedToolAnimInstance = toolAnim
		end
		toolAnim.C0 = aimCF * data.savedToolAnimC0
	else
		if data.savedToolAnimC0 and toolAnim then
			toolAnim.C0 = data.savedToolAnimC0
		end
		data.savedToolAnimC0 = nil
		data.savedToolAnimInstance = nil
	end
end

local function isLocalViewmodelActive()
	local vmRig = workspace.CurrentCamera:FindFirstChild("TREK_Viewmodel")
	if not vmRig then return false end
	local cam = workspace.CurrentCamera
	return (cam.CFrame.Position - cam.Focus.Position).Magnitude < 2
end

RunService.RenderStepped:Connect(function(dt)
	local viewmodelActive = isLocalViewmodelActive()

	for _, player in ipairs(Players:GetPlayers()) do
		-- Skip local player when viewmodel handles first person
		-- Reset joints to defaults so viewmodel gets clean C0 values
		if player == LocalPlayer and viewmodelActive then
			local data = playerAimData[player]
			if data and data.currentPitch ~= 0 then
				local character = player.Character
				if character then
					local torso = character:FindFirstChild("Torso")
					if torso then
						local rs = torso:FindFirstChild("Right Shoulder")
						local ls = torso:FindFirstChild("Left Shoulder")
						if rs then rs.C0 = RIGHT_SHOULDER_POS * RIGHT_SHOULDER_ROT end
						if ls then ls.C0 = LEFT_SHOULDER_POS * LEFT_SHOULDER_ROT end
						local ta = torso:FindFirstChild("toolAnim")
						if ta and data.savedToolAnimC0 then
							ta.C0 = data.savedToolAnimC0
						end
					end
				end
				data.currentPitch = 0
			end
			continue
		end

		local character = player.Character
		if character then
			processCharacter(dt, player, character)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	playerAimData[player] = nil
end)
