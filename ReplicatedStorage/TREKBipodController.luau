--[[
	TREKBipodController.luau
	Location: ReplicatedStorage > TREK_SERVICES > TREK_Modules

	Client-side handler for the bipod system.

	NOTE: "Realistic Head Movement" is NOT in the interfering scripts list.
	That script has its own internal bipod attribute check that resets the neck
	to default during deploy and handles the transition frame on undeploy.
	Externally toggling Enabled on that script causes it to re-initialize and
	capture a corrupted neckC0 baseline, producing persistent head drift.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

repeat task.wait() until shared.S and shared.S.TREK_Remotes

local Remotes = shared.S.TREK_Remotes
local DeployRemote = Remotes:WaitForChild("BipodDeploy")
local UndeployRemote = Remotes:WaitForChild("BipodUndeploy")
local AimRemote = Remotes:WaitForChild("BipodAim")

local shiftLockToggle = player:WaitForChild("PlayerScripts")
	:WaitForChild("CustomShiftLock")
	:WaitForChild("SmoothShiftLock")
	:WaitForChild("ToggleShiftLock")

local shiftLockEditConfig = player:WaitForChild("PlayerScripts")
	:WaitForChild("CustomShiftLock")
	:WaitForChild("SmoothShiftLock")
	:WaitForChild("EditConfig")

-- Scripts to disable during bipod deploy. These write to HRP CFrame or produce
-- movement effects that conflict with the bipod weld assembly.
-- NOTE: "Realistic Head Movement" is intentionally NOT here — it handles
-- bipod state internally via attribute checks. Toggling its Enabled property
-- causes re-initialization which corrupts its saved neckC0 baseline.
local INTERFERING_SCRIPT_NAMES = {
	"Directional Walking Script",
	"MovementLean",
	"CameraBobbing",
}

local AIM_POS_EPSILON = 0.05

local BipodController = {}

-- Internal state
local active = false
local activeTool = nil
local activeCharacter = nil
local activeConfig = nil
local activeModeIndex = nil
local aimStreamInterval = 1 / 30

local disabledScripts = {}

local attributeConnection = nil
local deathConnection = nil
local characterRemovingConnection = nil

local aimLoopConnection = nil
local lastSentTarget = nil
local timeSinceLastSend = 0

local savedMouseBehavior = nil
local savedCameraMode = nil

-- ============================================================
-- SHIFTLOCK CONTROL
-- ============================================================

local function captureAndDisableShiftlock()
	savedMouseBehavior = UserInputService.MouseBehavior

	shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", true)
	shiftLockToggle:Fire(false)
	shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", false)
end

local function restoreShiftlock()
	local wasShiftlockOn = (savedMouseBehavior == Enum.MouseBehavior.LockCenter)

	shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", true)
	shiftLockToggle:Fire(wasShiftlockOn)
	if wasShiftlockOn then
		shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", false)
	end

	savedMouseBehavior = nil
end

-- ============================================================
-- CAMERA MODE CONTROL
-- ============================================================

local function forceThirdPerson()
	savedCameraMode = player.CameraMode
	player.CameraMode = Enum.CameraMode.Classic
end

local function restoreCameraMode()
	if savedCameraMode then
		player.CameraMode = savedCameraMode
		savedCameraMode = nil
	end
end

-- ============================================================
-- SURFACE CHECK
-- ============================================================

local function hasDeployAttribute(part)
	if not part then return false end
	if part:GetAttribute("CanDeployBipod") == true then return true end
	if part.Parent and part.Parent:GetAttribute("CanDeployBipod") == true then return true end
	return false
end

local function checkSurfaceClient(tool, character)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {character, tool, workspace:FindFirstChild("IgnoreList")}

	local sensorPart = tool:FindFirstChild("BipodSensor")

	if sensorPart then
		local parts = workspace:GetPartBoundsInBox(sensorPart.CFrame, sensorPart.Size, overlapParams)
		for _, part in ipairs(parts) do
			if hasDeployAttribute(part) then
				return true
			end
		end
	end

	local pivotPart = tool:FindFirstChild("BipodPivot", true)
	if pivotPart then
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {character, tool, workspace:FindFirstChild("IgnoreList")}
		rayParams.IgnoreWater = true

		local result = workspace:Raycast(pivotPart.Position, Vector3.new(0, -3, 0), rayParams)
		if result and hasDeployAttribute(result.Instance) then
			return true
		end
	end

	return false
end

-- ============================================================
-- HELPERS
-- ============================================================

local function disableInterferingScripts(character)
	disabledScripts = {}
	for _, scriptName in ipairs(INTERFERING_SCRIPT_NAMES) do
		local inst = character:FindFirstChild(scriptName, true)
		if inst and inst:IsA("LocalScript") and inst.Enabled then
			inst.Enabled = false
			table.insert(disabledScripts, inst)
		end
	end
end

local function restoreInterferingScripts()
	for _, inst in ipairs(disabledScripts) do
		if inst and inst.Parent then
			inst.Enabled = true
		end
	end
	disabledScripts = {}
end

local function disconnectAll()
	if attributeConnection          then attributeConnection:Disconnect();          attributeConnection = nil          end
	if deathConnection              then deathConnection:Disconnect();              deathConnection = nil              end
	if characterRemovingConnection  then characterRemovingConnection:Disconnect();  characterRemovingConnection = nil  end
end

-- ============================================================
-- AIM LOOP
-- ============================================================

local function aimTick(dt)
	if not activeCharacter then return end
	if not activeCharacter:GetAttribute("BipodActive") then return end

	timeSinceLastSend = timeSinceLastSend + dt
	if timeSinceLastSend < aimStreamInterval then return end

	local mouse = player:GetMouse()
	local target = mouse.Hit.Position

	if lastSentTarget then
		if (target - lastSentTarget).Magnitude < AIM_POS_EPSILON then return end
	end

	timeSinceLastSend = 0
	lastSentTarget = target
	AimRemote:FireServer(target)
end

local function startAimLoop()
	if aimLoopConnection then return end
	lastSentTarget = nil
	timeSinceLastSend = 0
	aimLoopConnection = RunService.RenderStepped:Connect(aimTick)
end

local function stopAimLoop()
	if aimLoopConnection then
		aimLoopConnection:Disconnect()
		aimLoopConnection = nil
	end
	lastSentTarget = nil
	timeSinceLastSend = 0
end

-- ============================================================
-- CLEANUP
-- ============================================================

local function fullCleanup()
	stopAimLoop()

	if activeCharacter then
		activeCharacter:SetAttribute("MovementAnimsLocked", false)
	end

	restoreInterferingScripts()
	restoreShiftlock()
	restoreCameraMode()
	disconnectAll()

	active = false
	activeTool = nil
	activeCharacter = nil
	activeConfig = nil
	activeModeIndex = nil
end

-- ============================================================
-- PUBLIC API
-- ============================================================

function BipodController.isDeployed()
	local character = player.Character
	if not character then return false end
	return character:GetAttribute("BipodActive") == true
end

function BipodController.isDeploying()
	local character = player.Character
	if not character then return false end
	return character:GetAttribute("BipodDeploying") == true
end

function BipodController.isActive()
	return active
end

function BipodController.canDeployOnSurface(tool, character, modeConfig)
	if not tool or not character or not modeConfig then return false end
	if not modeConfig.BipodMode then return false end
	return checkSurfaceClient(tool, character)
end

function BipodController.deploy(tool, character, modeIndex, config)
	-- Stale state recovery
	if active then
		local chr = player.Character
		if chr and not chr:GetAttribute("BipodActive") and not chr:GetAttribute("BipodDeploying") then
			fullCleanup()
		else
			return false
		end
	end

	if not tool or not character or not config then return false end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end

	if character:GetAttribute("BipodActive") or character:GetAttribute("BipodDeploying") then
		return false
	end

	if character:GetAttribute("TakedownActive") or character:GetAttribute("InTakedown") then
		return false
	end

	local modeConfig = config[modeIndex]
	if not modeConfig or not modeConfig.BipodMode then return false end

	if not checkSurfaceClient(tool, character) then
		return false
	end

	active = true
	activeTool = tool
	activeCharacter = character
	activeConfig = config
	activeModeIndex = modeIndex

	local rate = tonumber(modeConfig.BipodAimRate) or 30
	if rate < 5  then rate = 5  end
	if rate > 60 then rate = 60 end
	aimStreamInterval = 1 / rate

	character:SetAttribute("MovementAnimsLocked", true)

	disableInterferingScripts(character)
	captureAndDisableShiftlock()
	forceThirdPerson()

	DeployRemote:FireServer(tool.Name, modeIndex)

	attributeConnection = character.AttributeChanged:Connect(function(attrName)
		if attrName == "BipodActive" then
			if character:GetAttribute("BipodActive") then
				startAimLoop()
			else
				stopAimLoop()
			end
		end
		if attrName == "BipodActive" or attrName == "BipodDeploying" then
			local isActive    = character:GetAttribute("BipodActive")    == true
			local isDeploying = character:GetAttribute("BipodDeploying") == true
			if not isActive and not isDeploying then
				fullCleanup()
			end
		end
	end)

	deathConnection = humanoid.Died:Connect(function()
		BipodController.cancel()
	end)

	characterRemovingConnection = player.CharacterRemoving:Connect(function()
		BipodController.cancel()
	end)

	return true
end

function BipodController.undeploy(tool, character)
	if not active then return false end
	if not character then return false end

	UndeployRemote:FireServer()
	return true
end

function BipodController.cancel()
	if active then
		pcall(function() UndeployRemote:FireServer() end)
	end
	fullCleanup()
end

return BipodController
