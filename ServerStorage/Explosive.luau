--[[
	Explosive.luau (LocalScript)
	Location: ServerStorage > TREKToolHandlers > Explosive
	
	Client handler for TREK Explosives. Follows the same patterns as Gun.luau
	for patrol, inspect, shiftlock, sprint, TurnToTarget, and keybinds.
	
	States: EQUIPPING, IDLE, PIN_PULLED, THROWING, EMPTY, RELOADING, PATROL, INSPECTING
]]

------------------------------------------------------------------------
-- PLAYER SETUP
------------------------------------------------------------------------

if not game.Players.LocalPlayer.Character then
	game.Players.LocalPlayer.CharacterAdded:Wait()
end

game.Players.LocalPlayer.Character:WaitForChild("Humanoid")
game.Players.LocalPlayer.Character:WaitForChild("TREK_PlrConfig")
game.Players.LocalPlayer.PlayerGui:WaitForChild("GunHud")

local UIS = game:GetService("UserInputService")
local RUNSERV = game:GetService("RunService")
local Debris = game:GetService("Debris")

local plr = game.Players.LocalPlayer
local chr = plr.Character
local mouseLegacy = plr:GetMouse()

------------------------------------------------------------------------
-- SHIFTLOCK (same pattern as Gun.luau)
------------------------------------------------------------------------

local shiftLockToggle = plr:WaitForChild("PlayerScripts")
	:WaitForChild("CustomShiftLock")
	:WaitForChild("SmoothShiftLock")
	:WaitForChild("ToggleShiftLock")

local shiftLockEditConfig = plr:WaitForChild("PlayerScripts")
	:WaitForChild("CustomShiftLock")
	:WaitForChild("SmoothShiftLock")
	:WaitForChild("EditConfig")

------------------------------------------------------------------------
-- TOOL & CONFIG
------------------------------------------------------------------------

local tool = script.Parent

local configModule
local configFolder = shared.S.ExplosiveConfigs
if configFolder then
	local configName = tool:GetAttribute("TConfigToUse") or tool.Name
	configModule = configFolder:FindFirstChild(configName, true)
end

if not configModule then
	warn("[Explosive] No config found for:", tool.Name)
	return
end

local config = require(configModule)

------------------------------------------------------------------------
-- MODULES
------------------------------------------------------------------------

local controls = require(chr:WaitForChild("OneLifeScripts"):WaitForChild("ControlsModule"))

------------------------------------------------------------------------
-- REMOTES
------------------------------------------------------------------------

local ThrowRemote = shared.S.TREK_Remotes:WaitForChild("ExplosiveThrow")
local DropRemote = shared.S.TREK_Remotes:WaitForChild("ExplosiveDrop")
local PinPullRemote = shared.S.TREK_Remotes:WaitForChild("ExplosivePinPull")
local AmmoRemote = shared.S.TREK_Remotes:WaitForChild("ExplosiveAmmo")
local GFXRemote = shared.S.TREK_Remotes:WaitForChild("ExplosiveGFX")
local ConcussRemote = shared.S.TREK_Remotes:WaitForChild("ExplosiveConcuss")

------------------------------------------------------------------------
-- STATE
------------------------------------------------------------------------

local equipped = false
local state = "IDLE"
local patrolling = false
local inspecting = false
local currentInspectTrack = nil

local currentAmmo = config.MagCapacity or 1
local storedAmmo = config.ReservedAmmo or 3

local animations = {}
local animsLoaded = false

------------------------------------------------------------------------
-- HUD
------------------------------------------------------------------------

local hud = plr.PlayerGui:WaitForChild("GunHud")
local ammohud = plr.PlayerGui:WaitForChild("AmmoCounter")
local marker = hud:WaitForChild("Hitmarker")

local main = configModule:WaitForChild("MainHud")
local currentmain = nil

local function updateAmmo()
	if not currentmain or not currentmain:FindFirstChild("Main") then return end
	currentmain.Main:WaitForChild("Ammo").Text = tostring(currentAmmo)
	local maxDisplay = (config.ReservedAmmo == math.huge and config.MagCapacity) or storedAmmo
	currentmain.Main:WaitForChild("MaxAmmo").Text = tostring(maxDisplay)
end

local function showHud()
	currentmain = main:Clone()
	currentmain.Parent = ammohud
	currentmain.Visible = true
	marker.Visible = true
	updateAmmo()
end

local function hideHud()
	marker.Visible = false
	if currentmain then currentmain:Destroy(); currentmain = nil end
end

------------------------------------------------------------------------
-- ANIMATIONS
------------------------------------------------------------------------

local function loadAnimations()
	if animsLoaded then return end

	local priorityMap = {
		Equip = Enum.AnimationPriority.Action4,
		Idle = Enum.AnimationPriority.Action,
		PinPull = Enum.AnimationPriority.Action4,
		PinPullIdle = Enum.AnimationPriority.Action,
		Throw = Enum.AnimationPriority.Action4,
		EmptyIdle = Enum.AnimationPriority.Action,
		Reload = Enum.AnimationPriority.Action4,
		Patrol = Enum.AnimationPriority.Action,
		Inspect = Enum.AnimationPriority.Action2,
	}

	local loopingAnims = {
		Idle = true,
		EmptyIdle = true,
		Patrol = true,
		PinPullIdle = true,
	}

	local animFolder = configModule:FindFirstChild("Animations")
	if not animFolder then return end

	for _, anim in ipairs(animFolder:GetChildren()) do
		if not anim:IsA("Animation") then continue end
		local track = chr.Humanoid:LoadAnimation(anim)
		local baseName = anim.Name
		track.Priority = priorityMap[baseName] or Enum.AnimationPriority.Action
		track.Looped = loopingAnims[baseName] or false
		animations[baseName] = track
	end

	animsLoaded = true
end

local function playAnim(name)
	local track = animations[name]
	if track then track:Play() end
	return track
end

local function stopAnim(name, fadeTime)
	local track = animations[name]
	if track and track.IsPlaying then track:Stop(fadeTime or 0.1) end
end

local function stopAllAnims(fadeTime)
	for _, track in pairs(animations) do
		if track.IsPlaying then track:Stop(fadeTime or 0) end
	end
end

------------------------------------------------------------------------
-- GRENADE MODEL VISIBILITY
------------------------------------------------------------------------

local function setGrenadeVisible(visible)
	local grenadeModel = tool:FindFirstChild("GrenadeModel", true)
	if not grenadeModel then return end

	local transparency = visible and 0 or 1

	if grenadeModel:IsA("BasePart") then
		grenadeModel.Transparency = transparency
	elseif grenadeModel:IsA("Model") then
		for _, desc in ipairs(grenadeModel:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Transparency = transparency
			end
		end
	end
end

------------------------------------------------------------------------
-- MOTOR SETUP
------------------------------------------------------------------------

local function handleMotor()
	if not tool:FindFirstChild("AnimPart") then return end

	if chr.Humanoid.RigType == Enum.HumanoidRigType.R6 then
		local torso = chr:FindFirstChild("Torso")
		if torso and torso:FindFirstChild("toolAnim") then
			torso.toolAnim.Part0 = torso
			torso.toolAnim.Part1 = tool.AnimPart
		end
	end
end

------------------------------------------------------------------------
-- SOUND (routed through TREK GFX remote for all-client replication)
------------------------------------------------------------------------

local function fireGFXSound(soundName)
	shared.S.TREK_Remotes.GFX:FireServer("ExplosiveSound", 1, soundName)
end

------------------------------------------------------------------------
-- AIM HELPER (matches Gun.luau getFreshAimPosition pattern)
------------------------------------------------------------------------

local function getAimPosition()
	local cam = workspace.CurrentCamera
	local viewportSize = cam.ViewportSize
	local centerRay = cam:ViewportPointToRay(viewportSize.X / 2, viewportSize.Y / 2)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {chr, workspace:FindFirstChild("IgnoreList")}

	local result = workspace:Raycast(centerRay.Origin, centerRay.Direction * 3000, rayParams)
	return result and result.Position or (centerRay.Origin + centerRay.Direction * 3000)
end

local function getThrowDirection()
	local cam = workspace.CurrentCamera
	local viewportSize = cam.ViewportSize
	local centerRay = cam:ViewportPointToRay(viewportSize.X / 2, viewportSize.Y / 2)
	return centerRay.Direction.Unit
end

------------------------------------------------------------------------
-- PATROL (exact same pattern as Gun.luau)
------------------------------------------------------------------------

local localcontrols = {}

function localcontrols.cancelInspect()
	if not inspecting then return end
	if currentInspectTrack then
		currentInspectTrack:Stop(0.2)
		currentInspectTrack = nil
	end
	inspecting = false
end

function localcontrols.patrol()
	if state == "THROWING" or state == "RELOADING" or state == "EQUIPPING" or state == "PIN_PULLED" then return end
	if controls.sprinting.Value then controls.sprinting.Value = false end

	if inspecting then
		localcontrols.cancelInspect()
	end

	patrolling = not patrolling

	if patrolling then
		shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", true)
		shiftLockToggle:Fire(false)
		chr:SetAttribute("AimLockDisabled", false)

		if state == "IDLE" then stopAnim("Idle", 0.2) end
		if state == "EMPTY" then stopAnim("EmptyIdle", 0.2) end

		playAnim("Patrol")
		state = "PATROL"
	else
		stopAnim("Patrol", 0.2)

		if equipped then
			if currentAmmo > 0 then
				state = "IDLE"
				shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", false)
				shiftLockToggle:Fire(true)
				playAnim("Idle")
			else
				state = "EMPTY"
				shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", false)
				shiftLockToggle:Fire(true)
				chr:SetAttribute("AimLockDisabled", true)
				playAnim("EmptyIdle")
			end
		else
			shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", true)
			shiftLockToggle:Fire(false)
		end
	end
end

------------------------------------------------------------------------
-- INSPECT (exact same pattern as Gun.luau — only works in patrol)
------------------------------------------------------------------------

function localcontrols.inspect()
	if not equipped then return end
	if not patrolling then return end
	if inspecting then return end
	if state ~= "PATROL" then return end

	local inspectTrack = playAnim("Inspect")
	if not inspectTrack then return end

	inspecting = true
	currentInspectTrack = inspectTrack

	fireGFXSound("Inspect")

	task.spawn(function()
		inspectTrack.Stopped:Wait()
		inspecting = false
		currentInspectTrack = nil
	end)
end

------------------------------------------------------------------------
-- CORE ACTIONS
------------------------------------------------------------------------

local function onEquip()
	equipped = true
	dropFiredOnDeath = false

	shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", false)
	shiftLockToggle:Fire(true)

	loadAnimations()
	handleMotor()

	AmmoRemote:FireServer(tool.Name, "Query")

	if currentAmmo >= 1 then
		-- Has a grenade ready — play equip animation
		state = "EQUIPPING"
		setGrenadeVisible(true)

		fireGFXSound("Equip")
		local equipTrack = playAnim("Equip")

		if equipTrack then
			task.spawn(function()
				equipTrack.Stopped:Wait()
				if equipped then
					state = "IDLE"
					if not controls.sprinting.Value then
						playAnim("Idle")
					end
				end
			end)
		else
			state = "IDLE"
			if not controls.sprinting.Value then
				playAnim("Idle")
			end
		end
	else
		-- No grenade loaded — keep shiftlock but disable arm/tool aim rotation
		state = "EMPTY"
		setGrenadeVisible(false)
		chr:SetAttribute("AimLockDisabled", true)
		playAnim("EmptyIdle")
	end

	mouseLegacy.Icon = "rbxassetid://" .. shared.Cursors.Main
	UIS.MouseIconEnabled = true

	showHud()
end

local function onUnEquip()
	-- If pin was pulled, drop the live grenade no matter why we're unequipping
	-- (weapon switch, burning, manual unequip â€” all cases).
	-- Skip if death handler already fired the drop (dropFiredOnDeath flag).
	if state == "PIN_PULLED" and not dropFiredOnDeath then
		pcall(function()
			DropRemote:FireServer(tool.Name)
		end)
		currentAmmo -= 1
		updateAmmo()
	end

	equipped = false

	chr:SetAttribute("YawLockActive", false)
	chr:SetAttribute("AimLockDisabled", false)
	shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", true)
	shiftLockToggle:Fire(false)

	if currentInspectTrack then
		currentInspectTrack:Stop(0)
		currentInspectTrack = nil
	end
	inspecting = false

	if patrolling then localcontrols.patrol() end

	stopAllAnims(0)
	hideHud()

	mouseLegacy.Icon = ""
	UIS.MouseIconEnabled = true

	for name, track in pairs(animations) do
		track:Stop(0)
		track:Destroy()
		animations[name] = nil
	end
	animsLoaded = false

	state = "IDLE"
	patrolling = false
end

local function pinPull()
	if state ~= "IDLE" then return end
	if currentAmmo <= 0 then return end
	if patrolling then return end
	if inspecting then return end

	state = "PIN_PULLED"
	chr:SetAttribute("YawLockActive", true)
	stopAnim("Idle")

	fireGFXSound("PinPull")
	local pullTrack = playAnim("PinPull")

	-- Always notify server that pin was pulled. Server needs this for death-drop
	-- handling (if player dies with pin pulled, server drops the grenade).
	-- FuseStartsOnPull only controls whether the fuse timer starts now or on throw.
	PinPullRemote:FireServer(tool.Name)

	if pullTrack then
		task.spawn(function()
			pullTrack.Stopped:Wait()
			if equipped and state == "PIN_PULLED" then
				playAnim("PinPullIdle")
			end
		end)
	else
		playAnim("PinPullIdle")
	end
end

local function throw()
	if state ~= "PIN_PULLED" then return end

	state = "THROWING"
	chr:SetAttribute("YawLockActive", false)
	stopAnim("PinPullIdle")

	local direction = getThrowDirection()
	local hrp = chr:FindFirstChild("HumanoidRootPart")
	local origin = hrp and (hrp.Position + direction * 2 + Vector3.new(0, 1, 0)) or Vector3.zero

	fireGFXSound("Throw")
	local throwTrack = playAnim("Throw")

	setGrenadeVisible(false)

	ThrowRemote:FireServer(tool.Name, origin, direction)

	currentAmmo -= 1
	updateAmmo()

	task.spawn(function()
		if throwTrack then
			throwTrack.Stopped:Wait()
		else
			task.wait(0.5)
		end

		if not equipped then return end

		state = "EMPTY"
		chr:SetAttribute("AimLockDisabled", true)
		playAnim("EmptyIdle")
	end)
end

local function reload()
	if state ~= "EMPTY" then return end
	if storedAmmo <= 0 and config.ReservedAmmo ~= math.huge then return end
	if patrolling then return end

	state = "RELOADING"
	chr:SetAttribute("AimLockDisabled", false)
	stopAnim("EmptyIdle")

	fireGFXSound("Reload")
	local reloadTrack = playAnim("Reload")

	AmmoRemote:FireServer(tool.Name, "Reload")

	task.spawn(function()
		if reloadTrack then
			reloadTrack.Stopped:Wait()
		else
			task.wait(1)
		end

		if not equipped then return end

		setGrenadeVisible(true)

		state = "IDLE"
		shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", false)
		shiftLockToggle:Fire(true)
		playAnim("Idle")
	end)
end

------------------------------------------------------------------------
-- INPUT (matches Gun.luau input pattern with globalConfig keybinds)
------------------------------------------------------------------------

local function onClick()
	if not equipped then return end
	if chr.Humanoid.Health <= 0 then return end
	if patrolling then return end
	if inspecting then return end

	if state == "IDLE" then
		pinPull()
	elseif state == "PIN_PULLED" then
		throw()
	elseif state == "EMPTY" then
		reload()
	end
end

local function Reload()
	if state == "EMPTY" and not patrolling then
		reload()
	end
end

local function input(input, done)
	if equipped and not done then
		local inputs = {
			[shared.S.globalConfig.ReloadKey] = Reload,
			[shared.S.globalConfig.PatrolKey] = localcontrols.patrol,
			[shared.S.globalConfig.InspectKey or Enum.KeyCode.F] = localcontrols.inspect,
		}

		local func = inputs[input.KeyCode] or inputs[input.UserInputType]
		if func then func() end
	end
end

------------------------------------------------------------------------
-- AMMO SYNC
------------------------------------------------------------------------

AmmoRemote.OnClientEvent:Connect(function(toolName, current, stored)
	if toolName ~= tool.Name then return end
	currentAmmo = current
	storedAmmo = stored
	updateAmmo()
end)

------------------------------------------------------------------------
-- CONCUSSION EFFECTS
------------------------------------------------------------------------

local function applyConcussion(data)
	local concussType = data.Type
	local duration = data.Duration or 3

	local gui = Instance.new("ScreenGui")
	gui.Name = "ConcussionEffect"
	gui.IgnoreGuiInset = true
	gui.Parent = plr.PlayerGui

	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundTransparency = 0
	overlay.BorderSizePixel = 0
	overlay.Parent = gui

	if concussType == "Flashbang" then
		overlay.BackgroundColor3 = Color3.new(0, 0, 0)
		overlay.BackgroundTransparency = 0
		game:GetService("TweenService"):Create(overlay,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{BackgroundTransparency = 1}):Play()
	elseif concussType == "Concussion" then
		overlay.BackgroundColor3 = Color3.new(0, 0, 0)
		overlay.BackgroundTransparency = 0.3
		game:GetService("TweenService"):Create(overlay,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{BackgroundTransparency = 1}):Play()
	elseif concussType == "TunnelVision" then
		overlay.BackgroundColor3 = Color3.new(0, 0, 0)
		overlay.BackgroundTransparency = 1
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.8),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = overlay
		overlay.BackgroundTransparency = 0
		game:GetService("TweenService"):Create(overlay,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{BackgroundTransparency = 1}):Play()
	end

	task.delay(duration + 0.5, function()
		if gui and gui.Parent then gui:Destroy() end
	end)
end

ConcussRemote.OnClientEvent:Connect(applyConcussion)

------------------------------------------------------------------------
-- EXPLOSIVE GFX (client-side visual events from server)
------------------------------------------------------------------------

GFXRemote.OnClientEvent:Connect(function(action, ...)
	local args = {...}

	if action == "GoLive" then
		local grenade = args[1]
		if not grenade then return end
		for _, desc in ipairs(grenade:GetDescendants()) do
			if desc:IsA("ParticleEmitter") then
				desc:Emit(desc:GetAttribute("EmitCount") or math.random(10, 30))
			end
		end

	elseif action == "Detonate" then
		local grenade = args[1]
		if grenade and grenade.Parent then
			for _, desc in ipairs(grenade:GetDescendants()) do
				if desc:IsA("ParticleEmitter") then desc.Enabled = false end
				if desc:IsA("Sound") then desc:Stop() end
			end
		end
	end
end)

------------------------------------------------------------------------
-- TURN TO TARGET (matches Gun.luau pattern)
------------------------------------------------------------------------

local function TurnToTarget()
	if not chr then return end
	if chr.Humanoid.SeatPart then return end
	if controls.sprinting.Value then return end
	if patrolling then return end

	local corePart = chr:FindFirstChild("HumanoidRootPart")
	if not corePart then return end

	local aimPos = getAimPosition()
	local lookAt = Vector3.new(aimPos.X, corePart.Position.Y, aimPos.Z)
	corePart:PivotTo(CFrame.new(corePart.Position, lookAt))
end

------------------------------------------------------------------------
-- RENDER LOOP
------------------------------------------------------------------------

local renderConn = nil

local function onRenderStepped()
	if not equipped then return end

	if state == "IDLE" or state == "PIN_PULLED" or state == "THROWING" then
		TurnToTarget()
	end
end

------------------------------------------------------------------------
-- EXECUTION
------------------------------------------------------------------------

tool.Equipped:Connect(onEquip)
tool.Unequipped:Connect(onUnEquip)

UIS.InputBegan:Connect(function(inp, done)
	if done then return end
	if not equipped then return end

	if inp.UserInputType == Enum.UserInputType.MouseButton1 then
		onClick()
	end

	input(inp, done)
end)

local dropFiredOnDeath = false

chr:WaitForChild("Humanoid").Died:Connect(function()
	-- Drop grenade IMMEDIATELY on death, before the character gets destroyed.
	-- This must happen before onUnEquip because character destruction can race
	-- with Unequipped, and the server needs the tool to still exist in the
	-- character for the drop to process.
	if state == "PIN_PULLED" and not dropFiredOnDeath then
		dropFiredOnDeath = true
		pcall(function()
			DropRemote:FireServer(tool.Name)
		end)
		currentAmmo -= 1
		state = "DROPPING" -- prevent onUnEquip from double-firing
	end
	onUnEquip()
end)

-- Sprint handling (matches Gun.luau pattern)
controls.sprinting:GetPropertyChangedSignal("Value"):Connect(function()
	if equipped then
		if controls.sprinting.Value then
			if patrolling then localcontrols.patrol() end
		end
	end
end)

renderConn = RUNSERV.RenderStepped:Connect(onRenderStepped)

tool.Destroying:Connect(function()
	if renderConn then renderConn:Disconnect() end
end)
