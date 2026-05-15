-- PLAYER VARIABLES
if not game.Players.LocalPlayer.Character then
	game.Players.LocalPlayer.CharacterAdded:Wait()
end

game.Players.LocalPlayer.Character:WaitForChild('Humanoid')
game.Players.LocalPlayer.Character:WaitForChild('TREK_PlrConfig')
game.Players.LocalPlayer.PlayerGui:WaitForChild('GunHud')

local UIS = game:GetService('UserInputService')
local RUNSERV = game:GetService('RunService')
local TweenService = game:GetService('TweenService')
local mouseModule = require(shared.S.TREK_Modules.MouseModuleV2)

-- GLOBALS
local plr = game.Players.LocalPlayer
local chr = plr.Character
local humanoid = chr:WaitForChild('Humanoid')

local shiftLockToggle = plr:WaitForChild("PlayerScripts")
	:WaitForChild("CustomShiftLock")
	:WaitForChild("SmoothShiftLock")
	:WaitForChild("ToggleShiftLock")

local shiftLockEditConfig = plr:WaitForChild("PlayerScripts")
	:WaitForChild("CustomShiftLock")
	:WaitForChild("SmoothShiftLock")
	:WaitForChild("EditConfig")

local mouse = mouseModule.new()
local mouseLegacy = plr:GetMouse()

mouse.TargetFilters:Set({workspace:WaitForChild('IgnoreList'), chr})
mouse:SetCollisionGroup('Default')

if shared.S.globalConfig['collisionGroupConfigs'] then
	if shared.S.globalConfig.collisionGroupConfigs['TMouseCollGroup'] then
		mouse:SetCollisionGroup('TMouseCollGroup')
	end
end

-- MELEE VARIABLES
local tool = script.Parent

local module
if tool:GetAttribute('TConfigToUse') then
	module = shared.S.MeleeConfigs:FindFirstChild(tool:GetAttribute('TConfigToUse'), true)
else
	module = shared.S.MeleeConfigs:FindFirstChild(tool.Name, true)
end

local config = require(module)
local currentMode = 1

-- INTERFACE VARIABLES
local hud = plr.PlayerGui:WaitForChild('GunHud')
local ammohud = plr.PlayerGui:WaitForChild('AmmoCounter')
local main = module:WaitForChild('MainHud')
local marker = hud:WaitForChild('Hitmarker')
local currentmain = main:Clone()

-- BOOLS
local equipped = false
local canSwing = true
local patrolling = false
local equipping = false
local inspecting = false
local inTakedown = false
local animsLoaded = false

local currentEquipTrack = nil
local currentInspectTrack = nil
local currentCombo = 0
local lastSwingTime = 0

-- TABLES
local animations = {}
local localcontrols = {}

-- MODULES
local controls = require(chr:WaitForChild('OneLifeScripts'):WaitForChild('ControlsModule'))
local universalFuncs = require(shared.S.TREK_Modules:WaitForChild('TREKUniversalFunctions'))
local Viewmodel = require(shared.S.TREK_Modules:WaitForChild("TREKViewmodel"))

-- CACHED OBJECTS
local ignoreList = workspace:WaitForChild('IgnoreList')
local soundOrigin = nil -- set on equip

-- Reusable overlap params for hitbox
local hitboxParams = OverlapParams.new()
hitboxParams.FilterType = Enum.RaycastFilterType.Exclude
hitboxParams.FilterDescendantsInstances = {chr, ignoreList}

-- Scripts to disable/enable during takedowns (shared between sync and cancel)
local takedownScriptNames = {
	"Directional Walking Script",
	"MovementLean",
	"Realistic Head Movement",
	"CameraBobbing"
}

-- R6 default Motor6D C0 values for joint reset after takedown
local R6_JOINT_DEFAULTS = {
	RootJoint = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
	Neck = CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
	['Right Shoulder'] = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	['Left Shoulder'] = CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
	['Right Hip'] = CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	['Left Hip'] = CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
}

-- UTILITY FUNCTIONS
local function tween(object, goal, tt, es, ed)
	return TweenService:Create(object, TweenInfo.new(tt, Enum.EasingStyle[es], Enum.EasingDirection[ed], 0, false, 0), goal)
end

local function findPlrAndChar(part)
	if not part or not part.Parent then return nil end

	local object = part
	while object and object.Parent ~= nil and not object.Parent:FindFirstChild('Humanoid') do
		object = object.Parent
	end

	local plr2 = game.Players:GetPlayerFromCharacter(object.Parent)
	if plr2 then return plr2, object.Parent end
	return nil
end

local function handleSound(sound)
	if not sound or not sound:IsA('Sound') then return end
	local s = sound:Clone()
	s.Parent = soundOrigin
	s:Play()
	universalFuncs.DestroyDelayed(s, s.TimeLength + 1)
end

-- GUI FUNCTIONS
local function showHud()
	currentmain = main:Clone()
	currentmain.Parent = ammohud
	currentmain.Visible = true
	marker.Visible = true

	for i = 1, 5 do
		if not equipped then
			currentmain.Visible = false
			break
		end
		currentmain.Visible = not currentmain.Visible
		task.wait(.06)
	end

	currentmain.Visible = equipped
end

local function hideHud()
	marker.Visible = false
	if currentmain then currentmain:Destroy() end
end

local function hitmarker(type)
	local markerClone, box = hud.Hitmarker.Marker:Clone(), hud.Hitmarker.Box:Clone()

	if type == 'armr' then
		box.UIStroke.Color = Color3.fromRGB(21, 0, 255)
	elseif type == 'plr' then
		box.UIStroke.Color = Color3.fromRGB(255, 32, 32)
	end

	markerClone.Parent = hud.Hitmarker
	box.Parent = hud.Hitmarker
	markerClone.Visible = true
	box.Visible = true

	tween(box, {Size = UDim2.new(0, 80, 0, 80)}, 0.25, "Cubic", "Out"):Play()
	tween(box.UIStroke, {Transparency = 1}, 0.25, "Linear", "Out"):Play()
	tween(box.UIStroke, {Thickness = 0}, 0.25, "Cubic", "In"):Play()
	tween(markerClone, {Size = UDim2.new(0, 50, 0, 50)}, 0.2, "Quint", "Out"):Play()
	tween(markerClone, {ImageTransparency = 1}, 0.2, "Linear", "Out"):Play()

	universalFuncs.DestroyDelayed(box, 0.5)
	universalFuncs.DestroyDelayed(markerClone, 0.5)
end

-- ANIMATION FUNCTIONS
local function loadAnimations()
	if animsLoaded then return end

	local priorityMap = {
		Idle = Enum.AnimationPriority.Action,
		Patrol = Enum.AnimationPriority.Action,
		SprintHold = Enum.AnimationPriority.Action2,
		Equip = Enum.AnimationPriority.Action4,
		Inspect = Enum.AnimationPriority.Action2,
		Swing1 = Enum.AnimationPriority.Action4,
		Swing2 = Enum.AnimationPriority.Action4,
		Swing3 = Enum.AnimationPriority.Action4,
		Swing4 = Enum.AnimationPriority.Action4,
		Swing = Enum.AnimationPriority.Action4,
		TakedownAttacker = Enum.AnimationPriority.Action4,
		TakedownVictim = Enum.AnimationPriority.Action4,
	}

	for _, anim in pairs(module.Animations:GetChildren()) do
		if not anim:IsA('Animation') then continue end
		if anim.AnimationId == '' then continue end

		local track = humanoid:LoadAnimation(anim)
		local baseName = anim.Name:match("^%d+(.+)$") or anim.Name
		track.Priority = priorityMap[baseName] or Enum.AnimationPriority.Action
		animations[anim.Name] = track
	end

	animsLoaded = true
end

local function determineAnim(anim, action, returnanim)
	local track = animations[tostring(currentMode) .. anim] or animations[anim]
	if not track then return end

	if action == 'play' then
		track:Play()
	else
		track:Stop()
	end

	if returnanim then return track end
end

local function handleMotor()
	if not tool:FindFirstChild('AnimPart') then return end

	local motorParent
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		motorParent = chr:FindFirstChild('Right Arm')
	elseif humanoid.RigType == Enum.HumanoidRigType.R15 then
		motorParent = chr:FindFirstChild('RightHand')
	end
	if not motorParent then return end

	local motor = motorParent:FindFirstChild('meleeToolAnim')
	if not motor then
		motor = Instance.new('Motor6D')
		motor.Name = 'meleeToolAnim'
		motor.Parent = motorParent
	end

	motor.Part0 = motorParent
	motor.Part1 = tool.AnimPart
end

-- HITBOX FUNCTION
local function performHitbox()
	local cfg = config[currentMode]
	local hrp = chr:FindFirstChild('HumanoidRootPart')
	if not hrp then return {} end

	local hitboxCF = hrp.CFrame * CFrame.new(0, 0, -(cfg.Range / 2))
	local hitboxSize = Vector3.new(cfg.HitboxWidth or 4, cfg.HitboxHeight or 6, cfg.Range)

	local parts = workspace:GetPartBoundsInBox(hitboxCF, hitboxSize, hitboxParams)

	local hitCharacters = {}
	local seen = {}

	for _, part in ipairs(parts) do
		local hitPlr, hitChr = findPlrAndChar(part)
		if hitPlr and hitChr and not seen[hitChr] then
			if hitPlr ~= plr then
				if cfg.TeamKill or (hitPlr.Team ~= plr.Team) then
					seen[hitChr] = true
					table.insert(hitCharacters, { player = hitPlr, character = hitChr, part = part })
				end
			end
		end

		if part:FindFirstChild('THealth') and not seen[part] then
			seen[part] = true
			table.insert(hitCharacters, { player = nil, character = nil, part = part, isTHealth = true })
		end
	end

	return hitCharacters
end

local function calculateDamage(part)
	local cfg = config[currentMode]
	local damage = cfg.Damage
	if part.Name == 'Head' or part:FindFirstAncestor('Head') then
		damage = damage * cfg.headShotMultiplier
	end
	return damage
end

-- SWING FUNCTION
local function swing()
	if not equipped or not canSwing or equipping or inspecting or inTakedown or patrolling then return end
	if humanoid.Health <= 0 then return end

	local cfg = config[currentMode]

	local now = tick()
	if (now - lastSwingTime) > cfg.ComboResetTime then
		currentCombo = 0
	end

	currentCombo = currentCombo + 1
	if currentCombo > cfg.ComboCount then
		currentCombo = 1
	end
	lastSwingTime = now
	canSwing = false

	-- Stop idle/sprint to prevent blending
	if controls.sprinting.Value then
		determineAnim('SprintHold', 'stop')
	else
		determineAnim('Idle', 'stop')
	end

	-- Play swing animation
	local swingAnimName = 'Swing' .. currentCombo
	local swingTrack = determineAnim(swingAnimName, 'play', true)
	if not swingTrack then
		swingTrack = determineAnim('Swing', 'play', true)
	end

	-- Play swing sound via GFX remote (plays on ALL clients including local)
	-- Pass the swing name so GFXRender can find the combo-specific sound
	local swingAnimName = 'Swing' .. currentCombo
	shared.S.TREK_Remotes.GFX:FireServer('MeleeSwing', currentMode, swingAnimName)

	task.wait(0.1)

	-- Hitbox detection
	local hits = performHitbox()

	for _, hitData in ipairs(hits) do
		if hitData.isTHealth then
			shared.S.TREK_Remotes.MeleeDamage:FireServer(hitData.part, currentMode)
			hitmarker('armr')
		elseif hitData.character then
			local enemyHum = hitData.character:FindFirstChild('Humanoid')
			if enemyHum and enemyHum.Health > 0 then
				local predictedDamage = calculateDamage(hitData.part)

				if cfg.TakedownEnabled and enemyHum.Health <= predictedDamage then
					shared.S.TREK_Remotes.TakedownRequest:FireServer(hitData.character, currentMode)
				else
					shared.S.TREK_Remotes.MeleeDamage:FireServer(hitData.part, currentMode)
					hitmarker('plr')
					-- Hit sound played via GFX remote for ALL clients (including local)
					shared.S.TREK_Remotes.GFX:FireServer('MeleeHit', currentMode, 'Main')
				end
			end
		end
	end

	task.wait(cfg.SwingSpeed)

	if equipped and not inTakedown and not patrolling then
		if controls.sprinting.Value then
			determineAnim('SprintHold', 'play')
		else
			determineAnim('Idle', 'play')
		end
	end

	canSwing = true
end

-- PATROL FUNCTION
function localcontrols.patrol()
	if inTakedown then return end
	if controls.sprinting.Value then controls.sprinting.Value = false end
	if inspecting then localcontrols.cancelInspect() end

	patrolling = not patrolling

	if patrolling then
		shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", true)
		shiftLockToggle:Fire(false)
		determineAnim('Patrol', 'play')
		determineAnim('Idle', 'stop')
	else
		if equipped then
			shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", false)
			shiftLockToggle:Fire(true)
		else
			shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", true)
			shiftLockToggle:Fire(false)
		end
		determineAnim('Patrol', 'stop')
		if equipped then determineAnim('Idle', 'play') end
	end
end

-- INSPECT FUNCTIONS
function localcontrols.cancelInspect()
	if not inspecting then return end
	if currentInspectTrack then
		currentInspectTrack:Stop(0.2)
		currentInspectTrack = nil
	end
	inspecting = false
end

function localcontrols.inspect()
	if not equipped or not patrolling or inspecting or inTakedown then return end

	local inspectTrack = determineAnim('Inspect', 'play', true)
	if not inspectTrack then return end

	inspecting = true
	currentInspectTrack = inspectTrack
	handleSound(module:FindFirstChild(tostring(currentMode) .. 'Inspect') or module:FindFirstChild('Inspect'))

	task.spawn(function()
		inspectTrack.Stopped:Wait()
		inspecting = false
		currentInspectTrack = nil
	end)
end

-- EQUIP / UNEQUIP
local function onEquip()
	equipped = true
	Viewmodel.equip(tool, chr)
	shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", false)
	shiftLockToggle:Fire(true)
	chr:SetAttribute("YawLockActive", false)

	-- Voice reaction: equipping melee weapon
	pcall(function()
		shared.S.TREK_Remotes.VoicePlayRequest:FireServer("EquipMelee")
	end)

	-- Cache sound origin
	soundOrigin = tool:FindFirstChild('Main') or tool:FindFirstChild('Handle') or tool.PrimaryPart or tool:FindFirstChildWhichIsA('BasePart')

	loadAnimations()
	handleMotor()

	handleSound(module:FindFirstChild(tostring(currentMode) .. 'Equip') or module:FindFirstChild('Equip'))

	local equipTrack = determineAnim('Equip', 'play', true)

	if equipTrack then
		equipping = true
		canSwing = false
		currentEquipTrack = equipTrack

		task.spawn(function()
			equipTrack.Stopped:Wait()
			if equipped then
				equipping = false
				canSwing = true
				currentEquipTrack = nil
				if not controls.sprinting.Value then
					determineAnim('Idle', 'play')
				else
					determineAnim('SprintHold', 'play')
				end
			end
		end)
	else
		if not controls.sprinting.Value then
			determineAnim('Idle', 'play')
		else
			determineAnim('SprintHold', 'play')
		end
	end

	if shared.Cursors then
		mouseLegacy.Icon = 'rbxassetid://' .. shared.Cursors.Main
	end
	UIS.MouseIconEnabled = true

	showHud()

	if currentmain and currentmain:FindFirstChild('Main') then
		local mainFrame = currentmain.Main
		if mainFrame:FindFirstChild('Ammo') then mainFrame.Ammo.Text = "--" end
		if mainFrame:FindFirstChild('MaxAmmo') then mainFrame.MaxAmmo.Text = "--" end
	end
end

local function onUnEquip()
	equipped = false
	Viewmodel.unequip()
	equipping = false
	inspecting = false
	inTakedown = false
	canSwing = true
	chr:SetAttribute("TakedownActive", false)
	chr:SetAttribute("YawLockActive", false)
	shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", true)
	shiftLockToggle:Fire(false)

	if currentEquipTrack then currentEquipTrack:Stop(0); currentEquipTrack = nil end
	if currentInspectTrack then currentInspectTrack:Stop(0); currentInspectTrack = nil end
	if takedownPositionEnforcer then takedownPositionEnforcer:Disconnect(); takedownPositionEnforcer = nil end

	if patrolling then localcontrols.patrol() end

	-- Clean up melee Motor6D
	local rightPart = (humanoid.RigType == Enum.HumanoidRigType.R6 and chr:FindFirstChild('Right Arm'))
		or chr:FindFirstChild('RightHand')
	if rightPart and rightPart:FindFirstChild('meleeToolAnim') then
		rightPart.meleeToolAnim.Part1 = nil
	end

	determineAnim('Idle', 'stop')
	if controls.sprinting then determineAnim('SprintHold', 'stop') end

	mouseLegacy.Icon = ''
	UIS.MouseIconEnabled = true
	hideHud()

	for name, track in pairs(animations) do
		if track then track:Stop(0); track:Destroy() end
		animations[name] = nil
	end
	animsLoaded = false
end

-- TAKEDOWN CLIENT HANDLERS
local takedownPositionEnforcer = nil

local function resetR6Joints()
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		-- R15 neck reset
		local head = chr:FindFirstChild('Head')
		if head then
			local neck = head:FindFirstChild('Neck')
			if neck then neck.C0 = CFrame.new(0, -0.5, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1) end
		end
		return
	end

	local torso = chr:FindFirstChild('Torso')
	if not torso then return end

	for jointName, defaultC0 in pairs(R6_JOINT_DEFAULTS) do
		local joint = torso:FindFirstChild(jointName) or chr.HumanoidRootPart:FindFirstChild(jointName)
		if joint then joint.C0 = defaultC0 end
	end
end

local function setTakedownScripts(disabled)
	local animateScript = chr:FindFirstChild('Animate')
	if animateScript then animateScript.Disabled = disabled end

	for _, scriptName in ipairs(takedownScriptNames) do
		local s = chr:FindFirstChild(scriptName, true) or chr.Parent:FindFirstChild(scriptName, true)
		if s and s:IsA("LocalScript") then s.Disabled = disabled end
	end
end

local function onTakedownSync(attackerChr, victimChr, duration, attackerCF, victimCF)
	inTakedown = true
	canSwing = false
	chr:SetAttribute("TakedownActive", true)
	chr:SetAttribute("YawLockActive", false)

	shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", false)
	shiftLockToggle:Fire(false)
	setTakedownScripts(true)

	-- Enforce positions locally on RenderStepped
	if attackerCF and victimCF and attackerChr and victimChr then
		local atkHRP = attackerChr:FindFirstChild('HumanoidRootPart')
		local vicHRP = victimChr:FindFirstChild('HumanoidRootPart')
		if atkHRP and vicHRP then
			atkHRP.CFrame = attackerCF
			vicHRP.CFrame = victimCF

			takedownPositionEnforcer = RUNSERV.RenderStepped:Connect(function()
				if not inTakedown or not atkHRP or not atkHRP.Parent or not atkHRP.Anchored then
					if takedownPositionEnforcer then
						takedownPositionEnforcer:Disconnect()
						takedownPositionEnforcer = nil
					end
					return
				end
				atkHRP.CFrame = attackerCF
				if vicHRP and vicHRP.Parent then vicHRP.CFrame = victimCF end
			end)
		end
	end
end

local function onTakedownCancel()
	inTakedown = false
	canSwing = true
	chr:SetAttribute("TakedownActive", false)
	chr:SetAttribute("YawLockActive", false)

	if takedownPositionEnforcer then takedownPositionEnforcer:Disconnect(); takedownPositionEnforcer = nil end

	determineAnim('TakedownAttacker', 'stop')
	determineAnim('TakedownVictim', 'stop')

	-- Stop ALL playing animation tracks on the humanoid to kill orphans
	-- from scripts that were disabled mid-animation (e.g. Animate's walk track)
	-- Skip holster animations (Idle priority + Looped) — they're managed by the server
	if humanoid then
		for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
			if track.Priority == Enum.AnimationPriority.Idle and track.Looped then
				continue
			end
			track:Stop(0)
		end
	end

	resetR6Joints()
	setTakedownScripts(false)

	if equipped and not patrolling then
		shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", false)
		shiftLockToggle:Fire(true)
		if not controls.sprinting.Value then
			determineAnim('Idle', 'play')
		else
			determineAnim('SprintHold', 'play')
		end
	end
end

-- TURN TO TARGET
local function TurnToTarget()
	if not chr or humanoid.SeatPart or controls.sprinting.Value or patrolling or inTakedown then return end

	local corePart = chr:FindFirstChild('HumanoidRootPart')
	if not corePart then return end

	local lookAt = Vector3.new(mouse.Hit.Position.X, corePart.Position.Y, mouse.Hit.Position.Z)
	corePart:PivotTo(CFrame.new(corePart.Position, lookAt))
end

-- CROSSHAIR
local function mouseMoved()
	if not shared.Cursors then return end
	local t = mouse.Target
	marker.Position = UDim2.new(0, mouse.X, 0, mouse.Y) + UDim2.new(0, 0, 0, 9)

	if t ~= nil then
		if t.Parent:FindFirstChild('Humanoid') or t.Parent.Parent:FindFirstChild('Humanoid') then
			local player = (t.Parent:FindFirstChild('Humanoid') and game.Players:GetPlayerFromCharacter(t.Parent) or game.Players:GetPlayerFromCharacter(t.Parent.Parent))
			if player then
				if (player.Team == plr.Team and not config[currentMode].TeamKill) then
					mouseLegacy.Icon = 'rbxassetid://' .. shared.Cursors.Friendly
				else
					mouseLegacy.Icon = 'rbxassetid://' .. shared.Cursors.Enemy
				end
				return
			end
		end
	end
	mouseLegacy.Icon = 'rbxassetid://' .. shared.Cursors.Main
end

-- INPUT
local function input(inputObj, done)
	if equipped and not done then
		local inputs = {
			[shared.S.globalConfig.PatrolKey] = localcontrols.patrol,
			[shared.S.globalConfig.InspectKey or Enum.KeyCode.F] = localcontrols.inspect,
		}

		local func = inputs[inputObj.KeyCode] or inputs[inputObj.UserInputType]
		if func then func() end
	end
end

-- EXECUTION
tool.Equipped:Connect(onEquip)
tool.Unequipped:Connect(onUnEquip)

mouse.Button1Down:Connect(function()
	if equipped then task.spawn(swing) end
end)

mouse.Move:Connect(function()
	if equipped then mouseMoved() end
end)

RUNSERV.RenderStepped:Connect(function()
	if not equipped then return end
	if config[currentMode].TurnToTarget then TurnToTarget() end
end)

UIS.InputBegan:Connect(input)

shared.S.TREK_Remotes.TakedownSync.OnClientEvent:Connect(onTakedownSync)
shared.S.TREK_Remotes.TakedownCancel.OnClientEvent:Connect(onTakedownCancel)

controls.sprinting:GetPropertyChangedSignal('Value'):Connect(function()
	if equipped then
		if controls.sprinting.Value then
			if patrolling then localcontrols.patrol() end
			determineAnim('Idle', 'stop')
			determineAnim('SprintHold', 'play')
		else
			determineAnim('Idle', 'play')
			determineAnim('SprintHold', 'stop')
		end
	end
end)

humanoid.Died:Connect(function()
	onUnEquip()
	Viewmodel.unequip()
	canSwing = false
	if patrolling then localcontrols.patrol() end
end)

chr.ChildRemoved:Connect(function(child)
	if (humanoid.RigType == Enum.HumanoidRigType.R6 and child.Name == 'Right Arm') then
		tool.Parent = plr.Backpack
		tool:Destroy()
	end
	if (humanoid.RigType == Enum.HumanoidRigType.R15 and child.Name == 'RightHand') then
		tool.Parent = plr.Backpack
		tool:Destroy()
	end
end)
