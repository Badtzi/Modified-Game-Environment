--[[
	TREKServerBipod.luau
	Location: ServerScriptService

	PIVOT-TO-HRP with two-pass Spherecast surface snap.

	SNAP LOGIC (Spherecast):
		Uses workspace:Spherecast() instead of Raycast for wider, more forgiving
		surface detection. A sphere sweeps through space rather than an infinitely
		thin ray, catching surfaces that a ray would miss by fractions of a stud.

		Pass 1: Spherecast straight down from above BipodPivot. If hit ? pivot is
		        above the part, snap to the hit point.
		Pass 2: If pass 1 misses (pivot is past the part horizontally), Spherecast
		        from pivot toward HRP to find the part's near face. Then Spherecast
		        down from above that point to find the top surface.

	CROSS-SCRIPT API:
		shared.BipodForceExit(player) — tear down synchronously.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

repeat task.wait() until shared.S and shared.S.TREK_Remotes and shared.S.GunConfigs

local Remotes = shared.S.TREK_Remotes
local GunConfigs = shared.S.GunConfigs

local DeployRemote = Remotes:WaitForChild("BipodDeploy")
local UndeployRemote = Remotes:WaitForChild("BipodUndeploy")
local AimRemote = Remotes:WaitForChild("BipodAim")

local SNAP_RAYCAST_UP_OFFSET = 5
local SNAP_RAYCAST_DISTANCE = 10
local SNAP_SPHERE_RADIUS = 1

local bipodStates = {}

-- ============================================================
-- HELPERS
-- ============================================================

local function findChildByMode(parent, modeIndex, baseName, extraFallback)
	if not parent then return nil end
	local modePrefixed = parent:FindFirstChild(tostring(modeIndex) .. baseName)
	if modePrefixed then return modePrefixed end
	local bareBase = parent:FindFirstChild(baseName)
	if bareBase then return bareBase end
	if extraFallback then
		local alt = parent:FindFirstChild(extraFallback)
		if alt then return alt end
	end
	return nil
end

local function findModeSwitchAnimation(configModule, outgoingModeIndex)
	local anims = configModule:FindFirstChild("Animations")
	if not anims then return nil end
	return findChildByMode(anims, outgoingModeIndex, "ModeSwitch", nil)
end

local function findModeSwitchSound(configModule, outgoingModeIndex)
	return findChildByMode(configModule, outgoingModeIndex, "ModeSwitch", "Switch")
end

local function playServerAnimation(character, animation, priority)
	if not animation then return nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
	if not ok or not track then return nil end

	track.Priority = priority or Enum.AnimationPriority.Action4
	track.Looped = false
	track:Play(0.1)
	return track
end

local function playSoundOnTool(tool, soundTemplate)
	if not soundTemplate or not soundTemplate:IsA("Sound") then return end
	if not tool then return end
	local main = tool:FindFirstChild("Main")
	if not main or not main:IsA("BasePart") then return end

	local s = soundTemplate:Clone()
	s.Parent = main
	s:Play()
	Debris:AddItem(s, (s.TimeLength or 1) + 1)
end

local function resolveTransitionTime(track, fallbackTime)
	if track and track.Length and track.Length > 0.1 then
		return track.Length
	end
	return fallbackTime
end

local function lockHumanoid(state, humanoid)
	state.savedWalkSpeed = humanoid.WalkSpeed
	state.savedJumpPower = humanoid.JumpPower
	state.savedAutoRotate = humanoid.AutoRotate

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false
end

local function restoreHumanoid(state, humanoid)
	if not humanoid then return end
	if state.savedWalkSpeed  ~= nil then humanoid.WalkSpeed  = state.savedWalkSpeed  end
	if state.savedJumpPower  ~= nil then humanoid.JumpPower  = state.savedJumpPower  end
	if state.savedAutoRotate ~= nil then humanoid.AutoRotate = state.savedAutoRotate end
end

local function clamp(v, mn, mx)
	if v < mn then return mn end
	if v > mx then return mx end
	return v
end

local function lerpTo(current, target, alpha)
	return current + (target - current) * alpha
end

local function computeAimAngles(pivotCF, worldTarget)
	local localTarget = pivotCF:PointToObjectSpace(worldTarget)
	local yaw = -math.atan2(localTarget.X, -localTarget.Z)
	local flatDist = math.sqrt(localTarget.X * localTarget.X + localTarget.Z * localTarget.Z)
	local pitch = math.atan2(localTarget.Y, flatDist)
	return yaw, pitch
end

-- ============================================================
-- SURFACE DETECTION
-- ============================================================

local function hasDeployAttribute(part)
	if not part then return false end
	if part:GetAttribute("CanDeployBipod") == true then return true end
	if part.Parent and part.Parent:GetAttribute("CanDeployBipod") == true then return true end
	return false
end

local function checkDeployableSurface(pivotPart, character, tool)
	local sensorPart = tool:FindFirstChild("BipodSensor")
	local deployPart = nil

	if sensorPart then
		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.FilterDescendantsInstances = {character, tool, workspace:FindFirstChild("IgnoreList")}

		local parts = workspace:GetPartBoundsInBox(sensorPart.CFrame, sensorPart.Size, overlapParams)
		for _, part in ipairs(parts) do
			if hasDeployAttribute(part) then
				deployPart = part
				break
			end
		end
	end

	if not deployPart then
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {character, tool, workspace:FindFirstChild("IgnoreList")}
		rayParams.IgnoreWater = true

		local result = workspace:Raycast(pivotPart.Position, Vector3.new(0, -3, 0), rayParams)
		if result and hasDeployAttribute(result.Instance) then
			return { deployPart = result.Instance, snapHit = result }
		end
		return nil
	end

	return { deployPart = deployPart, snapHit = nil }
end

-- ============================================================
-- TWO-PASS SPHERECAST SNAP
-- Spherecast sweeps a sphere through space, giving wider detection than a
-- thin ray. Catches surfaces that a ray would miss by fractions of a stud.
-- ============================================================

local function findSnapPoint(pivotPart, hrp, deployPart)
	if not deployPart then return nil end

	local includeParams = RaycastParams.new()
	includeParams.FilterType = Enum.RaycastFilterType.Include
	includeParams.FilterDescendantsInstances = {deployPart}

	-- Pass 1: Spherecast straight down from above pivot.
	local downOrigin = pivotPart.Position + Vector3.new(0, SNAP_RAYCAST_UP_OFFSET, 0)
	local downHit = workspace:Spherecast(downOrigin, SNAP_SPHERE_RADIUS, Vector3.new(0, -SNAP_RAYCAST_DISTANCE, 0), includeParams)

	if downHit then
		return downHit
	end

	-- Pass 2: Pivot is past the part horizontally. Spherecast toward the player
	-- to find the part's near face.
	if not hrp then return nil end

	local towardPlayer = (hrp.Position - pivotPart.Position)
	if towardPlayer.Magnitude < 0.1 then return nil end
	towardPlayer = towardPlayer.Unit

	local horizontalHit = workspace:Spherecast(pivotPart.Position, SNAP_SPHERE_RADIUS, towardPlayer * 20, includeParams)
	if not horizontalHit then return nil end

	-- Found the near face. Spherecast down from above that hit point to find
	-- the top surface at that XZ.
	local aboveHitPoint = horizontalHit.Position + Vector3.new(0, SNAP_RAYCAST_UP_OFFSET, 0)
	local topHit = workspace:Spherecast(aboveHitPoint, SNAP_SPHERE_RADIUS, Vector3.new(0, -SNAP_RAYCAST_DISTANCE, 0), includeParams)

	return topHit
end

-- ============================================================
-- CYCLE BREAKING
-- ============================================================

local function breakExistingPivotJoints(tool, pivotPart)
	local broken = {}

	for _, desc in ipairs(tool:GetDescendants()) do
		if desc:IsA("JointInstance") then
			if desc.Name == "BipodYawMotor" then continue end

			local savedPart0, savedPart1

			if desc.Part0 == pivotPart then
				savedPart0 = pivotPart
				desc.Part0 = nil
			end
			if desc.Part1 == pivotPart then
				savedPart1 = pivotPart
				desc.Part1 = nil
			end

			if savedPart0 or savedPart1 then
				table.insert(broken, {
					joint = desc,
					part0 = savedPart0,
					part1 = savedPart1,
				})
			end
		end
	end

	return broken
end

local function restoreBrokenPivotJoints(broken)
	if not broken then return end

	for _, entry in ipairs(broken) do
		local joint = entry.joint
		if not joint or not joint.Parent then continue end

		if entry.part0 then joint.Part0 = entry.part0 end
		if entry.part1 then joint.Part1 = entry.part1 end
	end
end

-- ============================================================
-- ASSEMBLY
-- ============================================================

local function buildAssembly(state, character, tool, pivotPart, snapHit)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	-- Step 1: Move HRP horizontally so pivot XZ aligns with snap point
	if snapHit then
		local xzOffset = Vector3.new(
			snapHit.Position.X - pivotPart.Position.X,
			0,
			snapHit.Position.Z - pivotPart.Position.Z
		)
		if xzOffset.Magnitude > 0.01 then
			hrp.CFrame = hrp.CFrame + xzOffset
		end
	end

	-- Step 2: Break existing pivot joints
	state.brokenPivotJoints = breakExistingPivotJoints(tool, pivotPart)

	-- Step 3: Snap pivot Y to surface top
	if snapHit then
		local pos = pivotPart.Position
		local rot = pivotPart.CFrame.Rotation
		pivotPart.CFrame = CFrame.new(pos.X, snapHit.Position.Y, pos.Z) * rot
	end

	-- Step 4: Anchor
	pivotPart.Anchored = true

	-- Step 5: Build motor
	local baseC0 = pivotPart.CFrame:ToObjectSpace(hrp.CFrame)

	local yawMotor = Instance.new("Motor6D")
	yawMotor.Name = "BipodYawMotor"
	yawMotor.Part0 = pivotPart
	yawMotor.Part1 = hrp
	yawMotor.C0 = baseC0
	yawMotor.C1 = CFrame.new()
	yawMotor.Parent = pivotPart

	state.pivotPart      = pivotPart
	state.yawMotor       = yawMotor
	state.yawMotorBaseC0 = baseC0

	return true
end

local function destroyAssembly(state)
	if state.yawMotor and state.yawMotor.Parent then state.yawMotor:Destroy() end
	state.yawMotor = nil

	if state.pivotPart and state.pivotPart.Parent then
		state.pivotPart.Anchored = false
	end

	restoreBrokenPivotJoints(state.brokenPivotJoints)
	state.brokenPivotJoints = nil

	state.pivotPart = nil
end

-- ============================================================
-- CLEANUP
-- ============================================================

local function cleanupPlayer(player, characterGone)
	local state = bipodStates[player]
	bipodStates[player] = nil
	if not state then return end

	if state.toolAncestryConn then
		state.toolAncestryConn:Disconnect()
		state.toolAncestryConn = nil
	end

	if state.animTrack then
		pcall(function() state.animTrack:Stop() end)
		state.animTrack = nil
	end

	destroyAssembly(state)

	if characterGone then return end

	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then restoreHumanoid(state, humanoid) end

	character:SetAttribute("BipodActive", false)
	character:SetAttribute("BipodDeploying", false)
end

-- ============================================================
-- CROSS-SCRIPT API
-- ============================================================

shared.BipodForceExit = function(player)
	if not player then return end
	if not bipodStates[player] then return end
	cleanupPlayer(player)
end

-- ============================================================
-- HEARTBEAT LOOP
-- ============================================================

RunService.Heartbeat:Connect(function(dt)
	for player, state in pairs(bipodStates) do
		if state.phase ~= "DEPLOYED" then continue end
		if not state.yawMotor or not state.yawMotor.Parent then continue end

		local alpha = 1 - math.exp(-state.turnSpeed * dt)
		state.currentYaw   = lerpTo(state.currentYaw,   state.targetYaw,   alpha)
		state.currentPitch = lerpTo(state.currentPitch, state.targetPitch, alpha)

		state.yawMotor.C0 = CFrame.Angles(state.currentPitch, state.currentYaw, 0) * state.yawMotorBaseC0
	end
end)

-- ============================================================
-- DEPLOY
-- ============================================================

DeployRemote.OnServerEvent:Connect(function(player, toolName, modeIndex)
	if typeof(toolName) ~= "string" then return end
	if typeof(modeIndex) ~= "number" then return end
	if bipodStates[player] then return end

	local character = player.Character
	if not character then return end

	if character:GetAttribute("InTakedown") or character:GetAttribute("TakedownActive") then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local tool = character:FindFirstChild(toolName)
	if not tool or not tool:IsA("Tool") then return end

	local configModule = GunConfigs:FindFirstChild(tool.Name, true)
	if not configModule then return end

	local config = require(configModule)
	local modeConfig = config[modeIndex]
	if not modeConfig or not modeConfig.BipodMode then return end

	local pivotName = modeConfig.BipodPivotPartName or "BipodPivot"
	local pivotPart = tool:FindFirstChild(pivotName, true)
	if not pivotPart then
		warn("[TREKServerBipod] Pivot part '" .. pivotName .. "' not found in tool " .. tool.Name)
		return
	end

	-- Create state and set attributes early
	local state = {
		phase = "VALIDATING",
		tool = tool,
		configModule = configModule,
		config = config,
		modeIndex = modeIndex,
		pivotPartName = pivotName,

		yawMin    = math.rad(tonumber(modeConfig.BipodYawMin)   or -45),
		yawMax    = math.rad(tonumber(modeConfig.BipodYawMax)   or  45),
		pitchMin  = math.rad(tonumber(modeConfig.BipodPitchMin) or -20),
		pitchMax  = math.rad(tonumber(modeConfig.BipodPitchMax) or  20),
		turnSpeed = tonumber(modeConfig.BipodTurnSpeed)         or   8,

		targetYaw    = 0,
		currentYaw   = 0,
		targetPitch  = 0,
		currentPitch = 0,
	}
	bipodStates[player] = state

	character:SetAttribute("BipodDeploying", true)
	character:SetAttribute("BipodActive", false)

	-- Yield so BipodDeploying=true replicates before potential false on validation fail
	task.wait()

	if not bipodStates[player] or bipodStates[player] ~= state then return end
	if not character.Parent then cleanupPlayer(player); return end
	if not tool.Parent or tool.Parent ~= character then cleanupPlayer(player); return end

	-- Validate surface
	local surfaceData = checkDeployableSurface(pivotPart, character, tool)
	if not surfaceData then
		cleanupPlayer(player)
		return
	end

	-- Validation passed
	state.phase = "DEPLOYING"

	lockHumanoid(state, humanoid)

	state.toolAncestryConn = tool.AncestryChanged:Connect(function(_, newParent)
		if newParent ~= character then
			cleanupPlayer(player)
		end
	end)

	local outgoingModeForDeploy = 1
	local deployAnim  = findModeSwitchAnimation(configModule, outgoingModeForDeploy)
	local deploySound = findModeSwitchSound(configModule, outgoingModeForDeploy)

	state.animTrack = playServerAnimation(character, deployAnim, Enum.AnimationPriority.Action4)
	playSoundOnTool(tool, deploySound)

	local fallbackTime = tonumber(modeConfig.DeployTime) or 1.0
	local deployTime = resolveTransitionTime(state.animTrack, fallbackTime)

	task.delay(deployTime, function()
		local currentState = bipodStates[player]
		if not currentState or currentState ~= state then return end
		if currentState.phase ~= "DEPLOYING" then return end

		if character:GetAttribute("InTakedown") or character:GetAttribute("TakedownActive") then
			cleanupPlayer(player)
			return
		end

		if not tool.Parent or tool.Parent ~= character then
			cleanupPlayer(player)
			return
		end

		local pivotPartNow = tool:FindFirstChild(pivotName, true)
		if not pivotPartNow then
			cleanupPlayer(player)
			return
		end

		-- Re-check surface at assembly time
		local finalSurfaceData = checkDeployableSurface(pivotPartNow, character, tool)
		if not finalSurfaceData then
			cleanupPlayer(player)
			return
		end

		-- Two-pass Spherecast snap
		local snapHit = findSnapPoint(pivotPartNow, hrp, finalSurfaceData.deployPart)

		if currentState.animTrack then
			pcall(function() currentState.animTrack:Stop(0) end)
			currentState.animTrack = nil
		end
		task.wait()

		if not bipodStates[player] or bipodStates[player] ~= state then return end
		if not tool.Parent or tool.Parent ~= character then
			cleanupPlayer(player)
			return
		end

		local ok = buildAssembly(currentState, character, tool, pivotPartNow, snapHit)
		if not ok then
			cleanupPlayer(player)
			return
		end

		currentState.phase = "DEPLOYED"
		character:SetAttribute("BipodDeploying", false)
		character:SetAttribute("BipodActive", true)
	end)
end)

-- ============================================================
-- AIM STREAM
-- ============================================================

AimRemote.OnServerEvent:Connect(function(player, worldTarget)
	if typeof(worldTarget) ~= "Vector3" then return end

	local state = bipodStates[player]
	if not state then return end
	if state.phase ~= "DEPLOYED" then return end
	if not state.pivotPart or not state.pivotPart.Parent then return end

	if worldTarget.X ~= worldTarget.X or worldTarget.Y ~= worldTarget.Y or worldTarget.Z ~= worldTarget.Z then return end

	local rawYaw, rawPitch = computeAimAngles(state.pivotPart.CFrame, worldTarget)
	state.targetYaw   = clamp(rawYaw,   state.yawMin,   state.yawMax)
	state.targetPitch = clamp(rawPitch, state.pitchMin, state.pitchMax)
end)

-- ============================================================
-- UNDEPLOY
-- ============================================================

UndeployRemote.OnServerEvent:Connect(function(player)
	local state = bipodStates[player]
	if not state then return end
	if state.phase == "UNDEPLOYING" then return end

	local character = player.Character
	if not character then cleanupPlayer(player); return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then cleanupPlayer(player); return end

	local modeConfig = state.config[state.modeIndex]
	local outgoingModeForUndeploy = state.modeIndex

	state.phase = "UNDEPLOYING"
	character:SetAttribute("BipodActive", false)
	character:SetAttribute("BipodDeploying", true)

	destroyAssembly(state)

	if state.animTrack then
		pcall(function() state.animTrack:Stop() end)
		state.animTrack = nil
	end

	local undeployAnim  = findModeSwitchAnimation(state.configModule, outgoingModeForUndeploy)
	local undeploySound = findModeSwitchSound(state.configModule, outgoingModeForUndeploy)

	state.animTrack = playServerAnimation(character, undeployAnim, Enum.AnimationPriority.Action4)
	playSoundOnTool(state.tool, undeploySound)

	local fallbackTime = tonumber(modeConfig.UndeployTime) or 0.8
	local undeployTime = resolveTransitionTime(state.animTrack, fallbackTime)

	task.delay(undeployTime, function()
		local currentState = bipodStates[player]
		if not currentState or currentState ~= state then return end
		cleanupPlayer(player)
	end)
end)

-- ============================================================
-- LIFECYCLE CLEANUP
-- ============================================================

local function bindPlayer(player)
	player.CharacterAdded:Connect(function()
		cleanupPlayer(player, true)
	end)
	player.CharacterRemoving:Connect(function()
		cleanupPlayer(player, true)
	end)
end

Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player)
	cleanupPlayer(player, true)
end)

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end
