-- PLAYER VARIABLES 
if not game.Players.LocalPlayer.Character then
	game.Players.LocalPlayer.CharacterAdded:Wait()
end

game.Players.LocalPlayer.Character:WaitForChild('Humanoid')
game.Players.LocalPlayer.Character:WaitForChild('TREK_PlrConfig')
game.Players.LocalPlayer.PlayerGui:WaitForChild('GunHud')

local UIS = game:GetService('UserInputService')
local RUNSERV = game:GetService('RunService')
local PService = game:GetService("PhysicsService")
local mouseModule = require(shared.S.TREK_Modules.MouseModuleV2)

-- GLOBALS
local plr = game.Players.LocalPlayer



-- Toggle Shiftlock Path
local shiftLockToggle = plr:WaitForChild("PlayerScripts")
	:WaitForChild("CustomShiftLock")
	:WaitForChild("SmoothShiftLock")
	:WaitForChild("ToggleShiftLock")

local shiftLockEditConfig = plr:WaitForChild("PlayerScripts")
	:WaitForChild("CustomShiftLock")
	:WaitForChild("SmoothShiftLock")
	:WaitForChild("EditConfig")

local chr = plr.Character
local plrconfig = chr:WaitForChild('TREK_PlrConfig')
local mouse = mouseModule.new()
local mouseLegacy = plr:GetMouse()
local defaultZoomOut = plr.CameraMaxZoomDistance
local defaultZoomIn = plr.CameraMinZoomDistance
local defaultFov = workspace.CurrentCamera.FieldOfView

mouse.TargetFilters:Set({workspace:WaitForChild('IgnoreList'), chr})
mouse:SetCollisionGroup('Default')

if shared.S.globalConfig['collisionGroupConfigs'] then
	if shared.S.globalConfig.collisionGroupConfigs['TMouseCollGroup'] then
		mouse:SetCollisionGroup('TMouseCollGroup')
	end
end
--mouse.TargetFilter = workspace:WaitForChild("IgnoreList")

-- GUN VARIABLES
local tool = script.Parent

local module
if tool:GetAttribute('TConfigToUse') then
	module = shared.S.GunConfigs:FindFirstChild(tool:GetAttribute('TConfigToUse'), true)
else
	module = shared.S.GunConfigs:FindFirstChild(tool.Name, true)
end

local config = require(module)

local currentMode = 1
local currentBarelIndex = 1
local currentZoomLevel = 1
local FOVToUse = 40

local currentBarrel = ((tool:FindFirstChild(tostring(currentMode)..'Barrel') and tool[tostring(currentMode)..'Barrel']) or tool.Barrel)

-- AMMO VARIABLES
local sharedClip = config[1].MagCapacity
local sharedCap = sharedClip
local tammo = tool:FindFirstChild('TAmmo')

-- INTERFACE VARIABLES
local hud = plr.PlayerGui:WaitForChild('GunHud')
local ammohud = plr.PlayerGui:WaitForChild('AmmoCounter')
local scope = plr.PlayerGui:WaitForChild('Scope')

local main = module:WaitForChild('MainHud')
local ammobar = hud:WaitForChild('AmmoBar')
local marker = hud:WaitForChild('Hitmarker')

local currentmain = main:Clone()

-- BOOLS
local zoomed = false
local patrolling = false
local equipped = false
local firing = false
local canfire = true
local reloading = false
local mouseClick = false
local charging = false
local chargecooldown = false
local animsLoaded = false
local equipping = false
local currentEquipTrack = nil
local switchingModes = false
local inspecting = false
local currentInspectTrack = nil
local boltLockedBack = false

-- RAY STUFF
local raypar = RaycastParams.new()
raypar.FilterType = Enum.RaycastFilterType.Exclude
raypar.FilterDescendantsInstances = {workspace:WaitForChild('IgnoreList'), plr.Character}
raypar.IgnoreWater = true

-- PROJECTILES
local FASTCAST = require(shared.S.TREK_Modules.FastCastRedux)
local caster = FASTCAST.new()
FASTCAST.VisualizeCasts = false

-- TABLES
local transparencies = {}
local ignoreList = {workspace.IgnoreList,chr}
local animations = {}
local localcontrols = {}
local modeStuff = {}
local activeProgressBars = {}

for name,tabl in pairs(config) do
	if type(tabl) ~= 'table' then continue end

	modeStuff[name] = {
		['clip'] = tabl.MagCapacity;
		['currentclip'] = tabl.MagCapacity;
		['stored'] = tabl.ReservedAmmo;
		['fastCastBehavior'] = FASTCAST.newBehavior();
		['zoomLevels'] = string.split(tostring(tabl.ZoomFov), ";");
		['rayParams'] = RaycastParams.new()
	}

	modeStuff[name].rayParams.FilterType = Enum.RaycastFilterType.Exclude
	modeStuff[name].rayParams.FilterDescendantsInstances = {workspace:WaitForChild('IgnoreList'), plr.Character}
	modeStuff[name].rayParams.IgnoreWater = true
	modeStuff[name].rayParams.CollisionGroup = tabl['CollisionGroup'] or 'Default'

	modeStuff[name].fastCastBehavior.RaycastParams = modeStuff[name].rayParams
	modeStuff[name].fastCastBehavior.MaxDistance = tabl.Distance
	modeStuff[name].fastCastBehavior.Acceleration = tabl.ProjectileAcceleration
	modeStuff[name].fastCastBehavior.CosmeticBulletTemplate = shared.S.TREK_EffectsStorage.ProjectileTypes[tabl.ProjectileName]
	modeStuff[name].fastCastBehavior.CosmeticBulletContainer = workspace:WaitForChild('IgnoreList')
end

-- MISC
local tween = function(object,goal,tt,es,ed)
	return game:GetService("TweenService"):Create(object,TweenInfo.new(tt,Enum.EasingStyle[es],Enum.EasingDirection[ed],0,false,0),goal)
end
local lastanim 

-- MODULES
local controls = require(chr:WaitForChild('OneLifeScripts'):WaitForChild('ControlsModule'))
local effects = require(shared.S.TREK_Modules.EffectsModule)
local impactEffects = require(shared.S.TREK_Modules.ImpactParticlesModule)
local universalFuncs = require(shared.S.TREK_Modules:WaitForChild('TREKUniversalFunctions'))

local shakeModule = require(shared.S.TREK_Modules.CameraShaker)

local camShake = shakeModule.new(Enum.RenderPriority.Camera.Value, function(shakeCf)
	workspace.CurrentCamera.CFrame = workspace.CurrentCamera.CFrame * shakeCf
end)

camShake:Start()

local Spring = require(shared.S.TREK_Modules:WaitForChild('Spring'))
local RecoilSpring = Spring.New(Vector3.new())

RecoilSpring.Speed	= 20
RecoilSpring.Damper	= 0.5

local Viewmodel = require(shared.S.TREK_Modules:WaitForChild("TREKViewmodel"))
local BipodController = require(shared.S.TREK_Modules:WaitForChild("TREKBipodController"))

local AnimEvents = require(shared.S.TREK_Modules:WaitForChild("AnimEventHandler"))

-- Fresh aim position: casts a ray from the camera center RIGHT NOW,
-- ignoring the stale cached mouse.Hit that only updates on mouse movement.
-- This ensures shots, spread, and character rotation always follow the
-- current camera direction, even during strafing, recoil, or camera shake.
local function getFreshAimPosition()
	-- Bipod mode: aim follows barrel, not camera
	if chr:GetAttribute("BipodActive") then
		if currentBarrel then
			-- Raycast from barrel along its forward direction
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = {workspace:FindFirstChild('IgnoreList'), plr.Character}
			rayParams.IgnoreWater = true

			local result = workspace:Raycast(currentBarrel.Position, currentBarrel.CFrame.LookVector * 3000, rayParams)
			if result then
				return result.Position
			else
				return currentBarrel.Position + currentBarrel.CFrame.LookVector * 3000
			end
		end
	end

	-- Normal mode: aim follows camera center (original behavior)
	local cam = workspace.CurrentCamera
	local viewportSize = cam.ViewportSize
	local centerRay = cam:ViewportPointToRay(viewportSize.X / 2, viewportSize.Y / 2)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {workspace:FindFirstChild('IgnoreList'), plr.Character}
	rayParams.IgnoreWater = true

	local result = workspace:Raycast(centerRay.Origin, centerRay.Direction * 3000, rayParams)
	if result then
		return result.Position
	else
		return centerRay.Origin + centerRay.Direction * 3000
	end
end


-- UNIVERSAL FUNCTIONS
local function findPlrAndChar(part)
	if not part then return nil end
	if not part.Parent then return nil end

	local object = part

	while object and object.Parent ~= nil and not object.Parent:FindFirstChild('Humanoid') do
		object = object.Parent
	end

	local plr2 = game.Players:GetPlayerFromCharacter(object.Parent)

	if plr2 then return plr2, object.Parent end
	return nil
end

-- GUI FUNCTIONS
local function updateAmmo()
	if not currentmain:FindFirstChild('Main') then warn('No main UI!') return end

	local mode = (config[currentMode].useSharedClip and 1) or currentMode
	local maxAmmo = (config[mode].ReservedAmmo == math.huge and config[mode].MagCapacity) or tool.LocalTAmmo[mode].Stored.Value

	currentmain.Main:WaitForChild('Ammo').Text = tostring(tool.LocalTAmmo[mode].Ammo.Value)
	currentmain.Main:WaitForChild('MaxAmmo').Text = tostring(maxAmmo)

	--[[if config[currentMode].useSharedClip then
		currentmain.Main:WaitForChild('Ammo').Text = string.gsub(config[currentMode].AmmoFormat, 'AMOUNT', tool.LocalTAmmo[mode].Ammo.Value)
		currentmain.Main:WaitForChild('MaxAmmo').Text = string.gsub(config[currentMode].AmmoFormat, 'AMOUNT', maxAmmo)
	else
		currentmain.Main:WaitForChild('Ammo').Text = string.gsub(config[currentMode].AmmoFormat, 'AMOUNT', tool.LocalTAmmo[mode].Ammo.Value)
		currentmain.Main:WaitForChild('MaxAmmo').Text = string.gsub(config[currentMode].AmmoFormat, 'AMOUNT', maxAmmo)
	end]]
end


local function hitmarker(type)
	local marker,box = hud.Hitmarker.Marker:Clone(), hud.Hitmarker.Box:Clone()

	if type then
		if type == 'armr' then
			box.UIStroke.Color = Color3.fromRGB(21, 0, 255)
		elseif type == 'plr' then
			box.UIStroke.Color = Color3.fromRGB(255, 32, 32)
		end
	end

	marker.Parent = hud.Hitmarker
	box.Parent = hud.Hitmarker

	marker.Visible = true
	box.Visible = true

	tween(box,{Size = UDim2.new(0,80,0,80)},0.25,"Cubic","Out"):Play()
	tween(box.UIStroke,{Transparency = 1},0.25,"Linear","Out"):Play()
	tween(box.UIStroke,{Thickness = 0},0.25,"Cubic","In"):Play()
	tween(marker,{Size = UDim2.new(0,50,0,50)},0.2,"Quint","Out"):Play()
	tween(marker,{ImageTransparency = 1},0.2,"Linear","Out"):Play()

	universalFuncs.DestroyDelayed(box, 0.5)
	universalFuncs.DestroyDelayed(marker, 0.5)
end

local function damageIndicator(damage,part,type)
	local dmg = hud.Hitmarker.Damage
	local c = dmg:Clone()

	if type == 'plr' then
		c.TextColor3 = Color3.fromRGB(229,0,0)
	elseif type == 'armr' then
		c.TextColor3 = Color3.fromRGB(21, 0, 255)
	end

	local sounds = shared.S.TREK_EffectsStorage.Sounds.DamageSounds:GetChildren()
	local s = sounds[math.random(1, #sounds)]:Clone()

	c.Parent = hud.Hitmarker
	c.Visible = true
	c.Text = damage

	s.Parent = tool
	s:Play()

	--local newPosX = x + math.random(-150,150)
	--local newPosY = y + math.random(-100,100)

	tween(c,{Position = UDim2.new(1,math.random(15,30),0,-math.random(15,30))},1,'Quart','Out'):Play()
	tween(c,{Size = UDim2.new(0,80,0,20)},0.5,'Quint','Out'):Play()
	tween(c,{TextTransparency = 1},1,'Linear','Out'):Play()

	universalFuncs.DestroyDelayed(s, s.TimeLength)
	universalFuncs.DestroyDelayed(c,2)
end

--[[
local function determinteClip()
	return ((config[currentMode].useSharedClip and sharedClip) or modeStuff[currentMode].clip)
end

local function determineCap()
	return ((config[currentMode].useSharedClip and sharedCap) or modeStuff[currentMode].MagCapacity)
end
]]

local function showHud()
	currentmain = main:Clone()
	currentmain.Parent = ammohud
	currentmain.Visible = true

	marker.Visible = true
	ammobar.Visible = true

	updateAmmo()

	for i = 1,5 do 
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
	ammobar.Visible = false

	if not currentmain then return end
	currentmain:Destroy()
end

local function startReloadGui()

end

local function endReloadGui()
	updateAmmo()
end

-- FUNCTIONS 1
local function createAmmoStore()
	local f = Instance.new('Folder')
	f.Parent = tool
	f.Name = 'LocalTAmmo'

	for name, config in pairs(config) do		
		if not config then continue end
		if not (typeof(config) == 'table') then continue end
		if not config['MagCapacity'] then continue end

		local w = Instance.new('Folder')
		w.Parent = f
		w.Name = name

		local v1,v2 = Instance.new('DoubleConstrainedValue'),Instance.new('DoubleConstrainedValue')
		v1.Name = 'Ammo'
		v1.MaxValue = config.MagCapacity
		v1.MinValue = 0
		v1.Value = config.MagCapacity
		v1.Parent = w

		v2.Name = 'Stored'
		v2.MaxValue = (config.ReservedAmmo == math.huge and math.huge) or config.ReservedAmmo
		v2.MinValue = 0
		v2.Value = (config.ReservedAmmo == math.huge and math.huge) or config.ReservedAmmo
		v2.Parent = w
	end
end
local function handleMotor()
	if not tool:FindFirstChild('AnimPart') then return end

	if chr:WaitForChild('Humanoid').RigType == Enum.HumanoidRigType.R6 then
		chr.Torso.toolAnim.Part0 = chr.Torso
		chr.Torso.toolAnim.Part1 = tool.AnimPart
	elseif chr:WaitForChild('Humanoid').RigType == Enum.HumanoidRigType.R15 then
		chr.UpperTorso.toolAnim.Part0 = chr.UpperTorso
		chr.UpperTorso.toolAnim.Part1 = tool.AnimPart
	end
end

local function loadAnimations()
	if animsLoaded then return end

	local priorityMap = {
		Idle = Enum.AnimationPriority.Action,
		Patrol = Enum.AnimationPriority.Action,

		SprintHold = Enum.AnimationPriority.Action2,
		SprintReload = Enum.AnimationPriority.Action4,

		Reload = Enum.AnimationPriority.Action4,
		ReloadEmpty = Enum.AnimationPriority.Action4,
		Recharge = Enum.AnimationPriority.Action2,
		RechargeStart = Enum.AnimationPriority.Action2,
		RechargeEnd = Enum.AnimationPriority.Action2,
		WindUp = Enum.AnimationPriority.Action2,
		WindDown = Enum.AnimationPriority.Action2,

		Recoil = Enum.AnimationPriority.Action3,
		AimRecoil = Enum.AnimationPriority.Action3,

		Equip = Enum.AnimationPriority.Action4,
		ModeSwitch = Enum.AnimationPriority.Action4,
		Inspect = Enum.AnimationPriority.Action2,
		AimIn = Enum.AnimationPriority.Action2,
	}

	-- Animations that SHOULD loop. Everything else plays once and stops.
	local loopingAnims = {
		Idle = true,
		Patrol = true,
		SprintHold = true,
		AimIn = true,
		CrouchIdle = true,
	}

	for _, anim in pairs(module.Animations:GetChildren()) do
		local track = chr.Humanoid:LoadAnimation(anim)
		local baseName = anim.Name:match("^%d+(.+)$") or anim.Name
		track.Priority = priorityMap[baseName] or Enum.AnimationPriority.Action
		track.Looped = loopingAnims[baseName] or false
		animations[anim.Name] = track
		AnimEvents.hook(track, tool)
	end

	animsLoaded = true
end

local function clearAnimations()
	table.clear(animations)
end

-- Force-stop all looping/persistent weapon animations across ALL modes.
-- Call this before any major state transition to prevent stale tracks
-- from a previous mode persisting after rapid input.
local function stopAllPersistentAnims(fadeTime)
	fadeTime = fadeTime or 0.1
	local persistentNames = {"Idle", "AimIn", "SprintHold", "Patrol", "Recoil", "AimRecoil"}

	for trackName, track in pairs(animations) do
		for _, baseName in ipairs(persistentNames) do
			-- Match exact name or mode-prefixed name (e.g. "2Idle", "1AimIn")
			if trackName == baseName or trackName:match("^%d+" .. baseName .. "$") then
				if track.IsPlaying then
					track:Stop(fadeTime)
				end
				break
			end
		end
	end
end

-- Continuous barrel particle effects (for flamethrowers, etc.)
-- Enable/disable barrel particles based on trigger state instead of per-shot emission.
-- Requires ContinuousBarrelFX = true in the gun config.
local function enableBarrelFX()
	if not config[currentMode].ContinuousBarrelFX then return end
	if not currentBarrel then return end
	for _, child in ipairs(currentBarrel:GetDescendants()) do
		if child:IsA("ParticleEmitter") then child.Enabled = true end
		if child:IsA("PointLight") or child:IsA("SpotLight") then child.Enabled = true end
	end
	-- Replicate barrel particles/lights to other clients
	shared.S.TREK_Remotes.GFX:FireServer('BarrelFXStart', currentMode, currentBarrel.Name)
	-- Start continuous fire sound on all clients via GFX remote
	if config[currentMode].ContinuousFireSound then
		shared.S.TREK_Remotes.GFX:FireServer('FireSoundStart', currentMode, currentBarrel.Name)
	end
end

local function disableBarrelFX()
	if not currentBarrel then return end
	for _, child in ipairs(currentBarrel:GetDescendants()) do
		if child:IsA("ParticleEmitter") then child.Enabled = false end
		if child:IsA("PointLight") or child:IsA("SpotLight") then child.Enabled = false end
	end
	-- Replicate barrel FX disable to other clients
	if config[currentMode] and config[currentMode].ContinuousBarrelFX then
		shared.S.TREK_Remotes.GFX:FireServer('BarrelFXStop', currentMode, currentBarrel.Name)
	end
	-- Stop continuous fire sound on all clients
	if config[currentMode] and config[currentMode].ContinuousFireSound then
		shared.S.TREK_Remotes.GFX:FireServer('FireSoundStop', currentMode, currentBarrel.Name)
	end
end

-- Charge barrel FX: enables/disables particles on a "BarrelCharge" part during windUp.
-- Place a Part called "BarrelCharge" in your tool with its own particle emitters.
-- These play during the charge phase only, then stop when actual firing begins.
local function enableBarrelChargeFX()
	if not config[currentMode].ContinuousBarrelFX then return end
	local chargeBarrel = tool:FindFirstChild("BarrelCharge")
	if not chargeBarrel then return end
	for _, child in ipairs(chargeBarrel:GetDescendants()) do
		if child:IsA("ParticleEmitter") then child.Enabled = true end
		if child:IsA("PointLight") or child:IsA("SpotLight") then child.Enabled = true end
	end
	-- Replicate to other clients
	shared.S.TREK_Remotes.GFX:FireServer('BarrelChargeFXStart', currentMode, 'BarrelCharge')
end

local function disableBarrelChargeFX()
	local chargeBarrel = tool:FindFirstChild("BarrelCharge")
	if not chargeBarrel then return end
	for _, child in ipairs(chargeBarrel:GetDescendants()) do
		if child:IsA("ParticleEmitter") then child.Enabled = false end
		if child:IsA("PointLight") or child:IsA("SpotLight") then child.Enabled = false end
	end
	-- Replicate to other clients
	if config[currentMode] and config[currentMode].ContinuousBarrelFX then
		shared.S.TREK_Remotes.GFX:FireServer('BarrelChargeFXStop', currentMode, 'BarrelCharge')
	end
end

local function determineAnim(animName, action, returnanim)
	-- Post-destruction animation remap: if the tool's destructible part was broken,
	-- try "Post"-prefixed animations first (e.g., "PostIdle", "2PostRecoil")
	local track
	if tool:GetAttribute("PostDestructionMode") then
		track = animations[tostring(currentMode).."Post"..animName] or animations["Post"..animName]
	end
	-- Fall back to normal animation lookup
	if not track then
		track = (animations[tostring(currentMode)..animName] ~= nil and animations[tostring(currentMode)..animName]) or animations[animName]
	end

	local anim: AnimationTrack = track
	if not anim then return end

	if action == 'play' then
		anim:Play()
	elseif action == 'stop' then
		anim:Stop()
	else
		-- nil action = just return the track (used by Recoil)
	end

	if returnanim then return anim end
end

local function handleReloadSound(sound)
	local s = sound:Clone()
	s.Parent = tool.Main
	s:Play()
	universalFuncs.DestroyDelayed(s, s.TimeLength + 1)
end

local function onEquip()
	-- Block equipping if the character is on fire
	if chr:GetAttribute("TBurningActive") then
		tool.Parent = plr.Backpack
		return
	end

	-- BIPOD: bipod modes can't survive an unequip/equip boundary because the weld
	-- assembly is destroyed when the tool leaves the character. Force back to mode 1
	-- so the player doesn't re-equip into a "deployed" mode without an actual deploy.
	if config[currentMode] and config[currentMode].BipodMode then
		currentMode = 1
		currentBarrel = ((tool:FindFirstChild(tostring(currentMode)..'Barrel') and tool[tostring(currentMode)..'Barrel']) or tool.Barrel)
	end

	if not tool:FindFirstChild('LocalTAmmo') then createAmmoStore() end
	if (chr.Humanoid.RigType == Enum.HumanoidRigType.R6 and not chr:FindFirstChild('Right Arm')) then
		tool:Destroy()
	end
	if (chr.Humanoid.RigType == Enum.HumanoidRigType.R15 and not chr:FindFirstChild('RightHand')) then
		tool:Destroy()
	end

	equipped = true
	Viewmodel.equip(tool, chr)
	shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", false)
	shiftLockToggle:Fire(true)
	chr:SetAttribute("YawLockActive", true)
	charging = false
	chargecooldown = false

	loadAnimations()
	handleMotor()

	-- Play Equip sound if one exists in the config module
	local equipSound = module:FindFirstChild(tostring(currentMode)..'Equip') or module:FindFirstChild('Equip')
	if equipSound and equipSound:IsA('Sound') then
		handleReloadSound(equipSound)
	end

	-- Try to play the Equip animation if one exists in the config
	local equipTrack = determineAnim('Equip', 'play', true)

	if equipTrack then
		-- Block firing/reloading while equip plays
		equipping = true
		canfire = false
		currentEquipTrack = equipTrack

		task.spawn(function()
			-- Waits for the track to finish OR get force-stopped by onUnEquip
			equipTrack.Stopped:Wait()

			-- Only transition to Idle if we're still equipped
			if equipped then
				equipping = false
				canfire = true
				currentEquipTrack = nil

				if not controls.sprinting.Value then
					determineAnim('Idle', 'play')
				else
					determineAnim('SprintHold', 'play')
				end
			end
		end)
	else
		-- No Equip animation found, go straight to Idle like normal
		if not controls.sprinting.Value then
			determineAnim('Idle','play')
		else
			determineAnim('SprintHold','play')
		end
	end

	mouseLegacy.Icon = 'rbxassetid://'..shared.Cursors.Main
	UIS.MouseIconEnabled = true

	showHud()
end

local function onUnEquip()
	if BipodController.isDeployed() or BipodController.isDeploying() then
		BipodController.cancel()
	end

	equipped = false
	Viewmodel.unequip()
	equipping = false
	switchingModes = false
	inspecting = false
	canfire = true
	boltLockedBack = false
	chr:SetAttribute("YawLockActive", false)
	chr:SetAttribute("PatrolActive", false)
	chr:SetAttribute("InspectActive", false)
	shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", true)
	shiftLockToggle:Fire(false)

	-- Force-stop equip animation instantly if player unequips mid-animation
	if currentEquipTrack then
		currentEquipTrack:Stop(0)
		currentEquipTrack = nil
	end

	-- Force-stop inspect animation
	if currentInspectTrack then
		currentInspectTrack:Stop(0)
		currentInspectTrack = nil
	end

	disableBarrelFX()
	disableBarrelChargeFX()

	if zoomed then localcontrols.zoom() end
	if patrolling then localcontrols.patrol() end

	determineAnim('Idle','stop')
	determineAnim('Recoil', 'stop')
	if controls.sprinting then determineAnim('SprintHold','stop') end
	if reloading then
		determineAnim('Reload', 'stop')
		determineAnim('ReloadEmpty', 'stop')
	end

	mouseLegacy.Icon = ''
	UIS.MouseIconEnabled = true

	hideHud()

	-- Stop and clean up all animation tracks
	for name, track in pairs(animations) do
		if track then
			track:Stop(0)
			track:Destroy()
		end
		animations[name] = nil
	end

	animsLoaded = false
end

local function WindDown()
	if charging and equipped then
		--makePercCounter(config[currentMode].WindDownTime)
		shared.S.TREK_Remotes.GFX:FireServer('WindDown', currentMode, 'Main')
		determineAnim('WindDown','play')

		task.delay(config[currentMode].WindDownTime, function()
			charging = false
			chargecooldown = false
		end)

	end
end

local function switchModes()
	if reloading then return end
	if firing then return end
	if not equipped then return end
	if switchingModes then return end
	if equipping then return end
	if inspecting then return end

	if (currentMode == 1 and not config[currentMode + 1]) then return end

	-- BIPOD INTERCEPT: handle deploy/undeploy transitions before normal mode-switch flow.
	-- A "bipod transition" = exactly one of (current mode, next mode) has BipodMode = true.
	local nextMode = (config[currentMode + 1] and currentMode + 1) or 1
	local outgoingMode = currentMode
	local currentIsBipod = config[outgoingMode] and config[outgoingMode].BipodMode
	local nextIsBipod    = config[nextMode] and config[nextMode].BipodMode

	if (currentIsBipod and not nextIsBipod) or (nextIsBipod and not currentIsBipod) then

		if nextIsBipod then
			-- Check conditions FIRST before touching any animations or state.
			-- If deploy fails, NOTHING changes � no animations stop, no mode flags set.
			if patrolling or controls.crouching.Value then
				return
			end

			local deployed = BipodController.deploy(tool, chr, nextMode, config)
			if not deployed then
				return
			end

			-- Deploy succeeded. NOW commit state changes and stop animations.
			switchingModes = true
			canfire = false
			stopAllPersistentAnims(0.1)

			currentMode = nextMode
			currentBarrel = ((tool:FindFirstChild(tostring(currentMode)..'Barrel') and tool[tostring(currentMode)..'Barrel']) or tool.Barrel)
			updateAmmo()

			local deployTime = (config[nextMode].DeployTime or 1.0)
			task.delay(deployTime + 0.1, function()
				if not equipped then return end

				-- Check if the server actually completed the deploy. If not (server rejected
				-- during animation because player moved away from surface, or any other
				-- server-side validation failure), revert to mode 1 cleanly.
				if not chr:GetAttribute("BipodActive") and not chr:GetAttribute("BipodDeploying") then
					currentMode = 1
					currentBarrel = ((tool:FindFirstChild(tostring(currentMode)..'Barrel') and tool[tostring(currentMode)..'Barrel']) or tool.Barrel)
					updateAmmo()
					switchingModes = false
					canfire = true
					stopAllPersistentAnims(0)
					determineAnim('Idle', 'play')
					return
				end

				determineAnim('Idle', 'play')
				switchingModes = false
				canfire = true
			end)
		else
			-- UNDEPLOYING from bipod
			switchingModes = true
			canfire = false
			stopAllPersistentAnims(0.1)

			local undeployTime = (config[outgoingMode].UndeployTime or 0.8)
			BipodController.undeploy(tool, chr)
			currentMode = nextMode
			currentBarrel = ((tool:FindFirstChild(tostring(currentMode)..'Barrel') and tool[tostring(currentMode)..'Barrel']) or tool.Barrel)
			updateAmmo()

			task.delay(undeployTime + 0.1, function()
				if not equipped then return end
				stopAllPersistentAnims(0)
				if controls.sprinting.Value then
					determineAnim('SprintHold','play')
				else
					determineAnim('Idle','play')
				end
				switchingModes = false
				canfire = true
			end)
		end

		return
	end

	-- Force-stop ALL persistent animations from ANY mode to prevent stale tracks
	-- This catches edge cases where rapid switching leaves old mode idles playing
	stopAllPersistentAnims(0.1)

	-- Block firing during mode switch
	switchingModes = true
	canfire = false

	-- Play ModeSwitch animation if it exists (uses current mode prefix first)
	local switchTrack = determineAnim('ModeSwitch', 'play', true)

	-- Play Switch sound (existing behavior, plus check for ModeSwitch sound)
	local switchSound = module:FindFirstChild(tostring(currentMode)..'ModeSwitch') or module:FindFirstChild('ModeSwitch') or module:FindFirstChild('Switch')
	if switchSound and switchSound:IsA('Sound') then
		handleReloadSound(switchSound)
	end

	-- Wait for the animation to finish, or skip if no animation
	if switchTrack then
		task.spawn(function()
			switchTrack.Stopped:Wait()

			if not equipped then return end
			if not switchingModes then return end -- stale callback from rapid switching

			-- Now actually switch the mode number
			if not config[currentMode + 1] then
				currentMode = 1
			else
				currentMode += 1
			end

			if patrolling then localcontrols.patrol() end

			-- Clean slate before playing new mode's animations
			stopAllPersistentAnims(0)

			if controls.sprinting.Value then
				determineAnim('SprintHold','play')
			else
				determineAnim('Idle','play')
			end

			if zoomed then
				determineAnim('AimIn','play')
			end

			updateAmmo()
			currentBarrel = ((tool:FindFirstChild(tostring(currentMode)..'Barrel') and tool[tostring(currentMode)..'Barrel']) or tool.Barrel)

			switchingModes = false
			canfire = true
		end)
	else
		-- No ModeSwitch animation ? switch immediately
		if not config[currentMode + 1] then
			currentMode = 1
		else
			currentMode += 1
		end

		if patrolling then localcontrols.patrol() end

		-- Clean slate before playing new mode's animations
		stopAllPersistentAnims(0)

		if controls.sprinting.Value then
			determineAnim('SprintHold','play')
		else
			determineAnim('Idle','play')
		end

		if zoomed then
			determineAnim('AimIn','play')
		end

		updateAmmo()
		currentBarrel = ((tool:FindFirstChild(tostring(currentMode)..'Barrel') and tool[tostring(currentMode)..'Barrel']) or tool.Barrel)

		switchingModes = false
		canfire = true
	end
end

-- FUNCTIONS 2
local function classicZoom()
	currentZoomLevel = 1
	FOVToUse = (modeStuff[currentMode].zoomLevels and tonumber(modeStuff[currentMode].zoomLevels[1])) or config[currentMode].ZoomFov

	if zoomed then
		tween(workspace.CurrentCamera,{FieldOfView = FOVToUse},0.2,'Quint','Out'):Play()
	else
		tween(workspace.CurrentCamera,{FieldOfView = defaultFov},0.2,'Quint','Out'):Play()
	end

	UIS.MouseDeltaSensitivity = (zoomed and (workspace.CurrentCamera.FieldOfView/100) * 0.3) or 1
end

local function scopeZoom()
	if not scope:FindFirstChild(config[currentMode].ScopeType) then warn('Invalid scope!') return end
	currentZoomLevel = 1
	FOVToUse = (modeStuff[currentMode].zoomLevels and tonumber(modeStuff[currentMode].zoomLevels[1]) or config[currentMode].ZoomFov)

	UIS.MouseIconEnabled = true
	Viewmodel.Scoped = zoomed
	scope.Blackout.BackgroundTransparency = 0

	plr.CameraMaxZoomDistance = (zoomed and 0) or defaultZoomOut
	plr.CameraMinZoomDistance = (zoomed and 0) or defaultZoomIn
	workspace.CurrentCamera.FieldOfView = (zoomed and FOVToUse) or defaultFov

	scope[config[currentMode].ScopeType].Visible = zoomed
	UIS.MouseDeltaSensitivity = (zoomed and (workspace.CurrentCamera.FieldOfView/100) * 0.3) or 1

	tween(scope.Blackout,{BackgroundTransparency = 1},0.5,'Quint','Out'):Play()

	if zoomed then		
		for i,part in pairs(tool:GetDescendants()) do
			if not part:IsA('BasePart') then continue end
			transparencies[part] = part.Transparency
			part.Transparency = 1
		end
	else
		for part,value in pairs(transparencies) do
			part.Transparency = value
			part = nil
		end
	end
end

function localcontrols.zoom()
	if not config[currentMode].CanZoom then return end
	if patrolling then localcontrols.patrol() end

	zoomed = not zoomed

	if config[currentMode].Scope then
		scopeZoom()
	else
		classicZoom()
	end

	-- Aim animation: sustained hold while zoomed
	if zoomed then
		determineAnim('AimIn', 'play')
		-- Aim sound
		local aimSound = module:FindFirstChild(tostring(currentMode) .. 'AimIn') or module:FindFirstChild('AimIn')
		if aimSound and aimSound:IsA('Sound') then
			handleReloadSound(aimSound)
		end
	else
		determineAnim('AimIn', 'stop')
	end
end

function localcontrols.patrol()
	if reloading then return end
	if switchingModes then return end
	if chr:GetAttribute("BipodActive") or chr:GetAttribute("BipodDeploying") then return end
	if controls.sprinting.Value then controls.sprinting.Value = false end
	if zoomed then localcontrols.zoom() end

	-- Interrupt inspect if currently inspecting
	if inspecting then
		localcontrols.cancelInspect()
	end

	patrolling = not patrolling

	if patrolling then
		chr:SetAttribute("PatrolActive", true)
		shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", true)
		shiftLockToggle:Fire(false)
		chr:SetAttribute("YawLockActive", false)

		determineAnim('Patrol','play')
		determineAnim('Idle','stop')
	else
		chr:SetAttribute("PatrolActive", false)
		if equipped then
			shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", false)
			shiftLockToggle:Fire(true)
			chr:SetAttribute("YawLockActive", true)
		else
			shiftLockEditConfig:Fire("MANUALLY_TOGGLEABLE", true)
			shiftLockToggle:Fire(false)
		end

		determineAnim('Patrol','stop')
		if (not reloading and equipped) then
			determineAnim('Idle','play')
		end
	end
end

-- INSPECT

function localcontrols.cancelInspect()
	if not inspecting then return end
	if currentInspectTrack then
		currentInspectTrack:Stop(0.2)
		currentInspectTrack = nil
	end
	inspecting = false
	chr:SetAttribute("InspectActive", false)
end

function localcontrols.inspect()
	if not equipped then return end
	if not patrolling then return end
	if inspecting then return end
	if reloading then return end
	if switchingModes then return end

	-- Play Inspect animation if it exists
	local inspectTrack = determineAnim('Inspect', 'play', true)
	if not inspectTrack then return end

	inspecting = true
	currentInspectTrack = inspectTrack
	chr:SetAttribute("InspectActive", true)

	-- Play Inspect sound via GFX remote (plays on ALL clients including local)
	local inspectSound = module:FindFirstChild(tostring(currentMode)..'Inspect') or module:FindFirstChild('Inspect')
	if inspectSound and inspectSound:IsA('Sound') then
		shared.S.TREK_Remotes.GFX:FireServer('InspectSound', currentMode, 'Main')
	end

	-- Wait for animation to finish or get interrupted
	task.spawn(function()
		inspectTrack.Stopped:Wait()
		inspecting = false
		chr:SetAttribute("InspectActive", false)
		currentInspectTrack = nil
	end)
end

-- FUNCTIONS 3
local function handleFallOff(result, damage, distance)	
	local fostart = config[currentMode].fallOffStart
	local foend = config[currentMode].fallOffEnd

	if distance < fostart then
		result = damage
	elseif distance > foend then
		result = 0
	else
		distance -= fostart
		local Middle = damage / (foend - fostart)
		result = math.round(damage - (Middle * distance))
	end

	return result
end

local function setDamage(Origin, Target, ArmorDamage)	
	local distance = (Origin - Target.Position).Magnitude
	local damage = (ArmorDamage and config[currentMode].ArmourDamage) or config[currentMode].Damage
	local result

	result = handleFallOff(result, damage, distance)

	if (ArmorDamage and Target:FindFirstChild('RequiredArmourDamage')) then
		if result < Target.RequiredArmourDamage.Value then return 0 end
	end

	if (ArmorDamage and Target:FindFirstChild('ArmourDamageResist')) then
		result = math.clamp(0, (result - Target.ArmourDamageResist.Value), math.huge)
	end

	if (Target.Name == 'Head' or Target:FindFirstAncestor('Head')) then
		result *= config[currentMode].headShotMultiplier
	end

	return result
end

local function getSpread(part)
	local pos = getFreshAimPosition()
	local inter = (part.Position - pos).Magnitude

	local spread = config[currentMode].baseSpread

	if (controls.crouching.Value and chr:WaitForChild('Humanoid'):GetState() ~= Enum.HumanoidStateType.Freefall) then
		spread += config[currentMode].crouchSpreadAddition
	end
	if chr:WaitForChild('Humanoid'):GetState() == Enum.HumanoidStateType.Freefall then
		spread += config[currentMode].jumpSpreadAddition
	end
	if ((shared.S.globalConfig.EnableMedical) and (not chr:FindFirstChild('Left Arm'))) then 
		spread += config[currentMode].oneHandedSpreadAddition
	end
	if zoomed then 
		spread += config[currentMode].zoomSpreadAddition
	end

	spread = math.clamp(spread,0,math.huge)

	local min = -(spread/100)*inter
	local max = (spread/100)*inter

	local aim = Vector3.new(
		pos.X + math.random(min,max),
		pos.Y + math.random(min,max),
		pos.Z + math.random(min,max)
	)

	return aim
end

local function handleDamaging(part)
	if not part then return end

	local isPlayer = false
	local mat = part.Color

	local enplr, enchr = findPlrAndChar(part)
	local isTHealth = part:FindFirstChild('THealth')
	local isTVehicle = part:FindFirstAncestor('TVehicle')

	if enplr and enchr then
		shared.S.TREK_Remotes.Damage:FireServer(currentBarrel.Position, part, part.Size, currentMode)
		isPlayer = true

		if (enplr.Team ~= plr.Team) or (plr.Team == nil) or (config[currentMode].TeamKill) then
			local dmg = setDamage(currentBarrel.Position, part, false)
			if dmg <= 0 then return end

			damageIndicator(dmg, part, 'plr')
			hitmarker('plr')
		end

	elseif isTHealth then
		shared.S.TREK_Remotes.Damage:FireServer(currentBarrel.Position, part, part.Size, currentMode)

		local dmg = setDamage(currentBarrel.Position, part, true)
		if dmg <= 0 then return end

		if part:FindFirstChild('Team') then
			if (part.Team.Value ~= plr.Team) or (plr.Team == nil) or (config[currentMode].TeamKill) then
				damageIndicator(dmg, part, 'armr')
				hitmarker('armr')
			end
		else
			damageIndicator(dmg, part, 'armr')
			hitmarker('armr')
		end

	elseif (isTVehicle and not isTHealth) then
		shared.S.TREK_Remotes.Damage:FireServer(currentBarrel.Position, part, part.Size, currentMode)

		local dmg = setDamage(currentBarrel.Position, part, true)
		if dmg <= 0 then return end

		if not isTVehicle:FindFirstChild('Stats') then return end

		if (isTVehicle.Stats.Team.Value ~= plr.Team) or (plr.Team == nil) or (config[currentMode].TeamKill) then
			damageIndicator(dmg, part, 'armr')
			hitmarker('armr')
		else
			damageIndicator(dmg, part, 'armr')
			hitmarker('armr')
		end	
	end
end

local function rayFunctions(ray, spread)
	local isplayer = false
	local mat

	if not ray then return isplayer,mat,spread end

	handleDamaging(ray.Instance)

	local plr, chr = findPlrAndChar(ray.Instance)
	if plr then isplayer = true end
	mat = ray.Instance.Color

	return isplayer,mat,ray.Position
end

local function renderHit(caster, rayresult, veloccity, bullet, normal)
	local modeToUse = caster.UserData.ModeOverride or currentMode

	if config[modeToUse].CanSuppress then effects.Suppress.DrawEffect(plr,chr,bullet,config[modeToUse].ExtraSuppression) end

	if not rayresult then return end
	if not rayresult.Instance then return end

	local particleType = config[modeToUse].ImpactEffect
	if not particleType then return end
	if not impactEffects[particleType] then return end

	impactEffects[particleType].DrawEffect(rayresult.Position, rayresult.Instance.Color)
end

local function onRayHit(cast, raycastResult, segmentVelocity, cosmeticBulletObject)
	local obj = raycastResult.Instance
	local pos = raycastResult.Position
	local normal = raycastResult.Normal

	if not obj then return end

	--renderHit(cast, raycastResult, segmentVelocity, cosmeticBulletObject, normal)

	if config[currentMode].explosiveRays then
		local mode = currentMode
		if cast.UserData.ModeOverride then mode = cast.UserData.ModeOverride end
		shared.S.TREK_Remotes.Explosion:FireServer(pos, mode)
	end

	if cast.UserData.NoDamage then return end
	handleDamaging(obj)
end

local function castEnded(caster)

end

local function lengthChanged(thecaster, lastpoint, direction, displacement, velocity, bulletobj)

end

local function checkForWall(barrel, spread)	
	local origin = chr.Head.Position
	local ending = spread
	local direction = (ending - origin).Unit * math.huge
	-- (origin - ending).Magnitude

	local ray = workspace:Raycast(origin, direction, modeStuff[currentMode].rayParams)
	if ray then return true, ray.Position end

	return false
end

local function projectileMethod()
	for i, barrel in pairs(tool:GetChildren()) do
		if barrel.Name ~= currentBarrel.Name then continue end

		local spread = getSpread(barrel)	
		local dir
		local visualOrigin = Viewmodel.getBarrelPosition(barrel.Name) or barrel.Position
		local blocked, blockingPosition = checkForWall(barrel, spread)

		if blocked then
			dir = (blockingPosition - barrel.Position).Unit * config[currentMode].Distance
		else
			dir = (spread - barrel.Position).Unit * config[currentMode].Distance
		end

		local cast = caster:Fire(visualOrigin, dir, config[currentMode].ProjectileVelocity, modeStuff[currentMode].fastCastBehavior)

		shared.S.TREK_Remotes.ProjectileRemote:FireServer(tool.Name, barrel.Position, dir, config[currentMode].ProjectileVelocity, modeStuff[currentMode].fastCastBehavior, currentMode)
		shared.S.TREK_Remotes.ProjectileBind:Fire(tool.Name, barrel.Position, dir, config[currentMode].ProjectileVelocity, modeStuff[currentMode].fastCastBehavior, config[currentMode].CanSuppress, config[currentMode].ExtraSuppression, config[currentMode].ImpactEffect)
		--(name, pos, dir, vel, behavior, cansuppress, extrasuppression, impacteffect)

		if cast.RayInfo.CosmeticBulletObject then
			cast.RayInfo.CosmeticBulletObject:Destroy()
		end
	end
end

local function createRayInfoTable(start, dest, TargetSurface)
	local rayInfo = {}
	local customInfo = config[currentMode].CustomRayInfo

	rayInfo.Start = start
	rayInfo.Destination = dest
	rayInfo.Color = config[currentMode].CustomRayColour
	rayInfo.ProjectileType = config[currentMode].ProjectileName
	rayInfo.CanSuppress = config[currentMode].CanSuppress
	rayInfo.ImpactEffect = config[currentMode].ImpactEffect
	rayInfo.TargetSurface = TargetSurface
	rayInfo.RayType = config[currentMode].RayType
	rayInfo.Distance = config[currentMode].Distance

	if customInfo then
		for name, value in pairs(customInfo) do
			rayInfo[name] = value
		end
	end

	return rayInfo
end

local function hitScanMethod()
	for i, barrel in pairs(tool:GetChildren()) do		
		if barrel.Name ~= currentBarrel.Name then continue end

		local spread = getSpread(barrel)

		local visualOrigin = Viewmodel.getBarrelPosition(barrel.Name) or barrel.Position
		local origin = chr.Head.Position
		local direction = (spread - origin).Unit * config[currentMode].Distance

		local ray = workspace:Raycast(origin, direction, modeStuff[currentMode].rayParams)

		local isplayer,mat,hitpos = rayFunctions(ray, spread)

		if config[currentMode].explosiveRays then 
			shared.S.TREK_Remotes.Explosion:FireServer(hitpos, currentMode)
		end

		local localInfo = createRayInfoTable(visualOrigin, hitpos, mat)

		shared.S.TREK_Remotes.RayBind:Fire(localInfo)
		shared.S.TREK_Remotes.RayRemote:FireServer(visualOrigin, hitpos, mat, currentMode)
	end
end

local function handleRays()
	if config[currentMode].BulletType == 2 then
		projectileMethod()
	else
		hitScanMethod()
	end
end

local function handleAmmo()
	local mode = (config[currentMode].useSharedClip and 1) or currentMode

	if config[mode].ReservedAmmo == math.huge then return config[mode].MagCapacity end

	local difference = (config[mode].MagCapacity - tool.LocalTAmmo[mode].Ammo.Value)
	local possible

	local possible = (difference > tool.LocalTAmmo[mode].Stored.Value) and tool.LocalTAmmo[mode].Stored.Value or difference

	return possible,mode
end

local function makePercCounter(thetime)
	task.spawn(function()
		local c = ammobar:WaitForChild('OGBar'):Clone()
		c.Name = 'Bar'
		c.LayoutOrder = 0

		c.Parent = ammobar
		c.Visible = true

		activeProgressBars[c] = true

		tween(c,{BackgroundTransparency = 0.3, Size = UDim2.new(1,0,0,12)},0.5,'Quint','Out'):Play()
		tween(c.Perc,{Size = UDim2.new(1,0,1,0)},thetime,'Linear','Out'):Play()
		task.delay(thetime, function()
			tween(c,{BackgroundTransparency = 1},0.5,'Quint','Out'):Play()
			tween(c.Perc,{BackgroundTransparency = 1},0.5,'Quint','Out'):Play()
		end)

		universalFuncs.DestroyDelayed(c,thetime+0.5)
	end)
end

local function reloadTypeTwo()
	canfire = false
	reloading = true

	if boltLockedBack then
		determineAnim('EmptyIdle', 'stop')
		boltLockedBack = false
	end

	local mode = (config[currentMode].useSharedClip and 1) or currentMode

	task.wait(.2)

	local isEmpty = (tool.LocalTAmmo[mode].Ammo.Value <= 0)
	local useEmptyBranch = isEmpty
		and config[currentMode].ReloadEmptyAmount
		and (animations[tostring(currentMode)..'ReloadEmpty'] or animations['ReloadEmpty'])

	local reload

	if useEmptyBranch then
		local emptyAnim = determineAnim('ReloadEmpty', 'play', true)

		local emptySound = module:FindFirstChild(tostring(currentMode)..'ReloadEmpty')
			or module:FindFirstChild('ReloadEmpty')
			or module:FindFirstChild(tostring(currentMode)..'Recharge')
			or module:FindFirstChild('Recharge')
		if emptySound then handleReloadSound(emptySound) end

		local capacity = config[mode].MagCapacity
		local amount = config[currentMode].ReloadEmptyAmount or 1
		local available = math.min(amount, tool.LocalTAmmo[mode].Stored.Value, capacity - tool.LocalTAmmo[mode].Ammo.Value)

		tool.LocalTAmmo[mode].Stored.Value -= available
		tool.LocalTAmmo[mode].Ammo.Value += available
		updateAmmo()

		task.wait(config[currentMode].ReloadEmptySpeed or (emptyAnim and emptyAnim.Length) or config[currentMode].ReloadSpeed)
	else
		local startanim:AnimationTrack = determineAnim('RechargeStart', 'play', true)
		if startanim then task.wait(startanim.Length) end
	end

	repeat
		if tool.LocalTAmmo[mode].Ammo.Value >= config[mode].MagCapacity then break end

		handleReloadSound((module:FindFirstChild(tostring(currentMode)..'Recharge') and module[(tostring(currentMode)..'Recharge')]) or module.Recharge)
		reload = determineAnim('Reload','play', true)

		if tool.LocalTAmmo[mode].Stored.Value <= 0 then break end

		tool.LocalTAmmo[mode].Stored.Value -= 1
		tool.LocalTAmmo[mode].Ammo.Value += 1
		updateAmmo()

		if tool.LocalTAmmo[mode].Ammo.Value >= config[mode].MagCapacity then break end

		task.wait(config[currentMode].ReloadSpeed)

	until tool.LocalTAmmo[mode].Ammo.Value == config[mode].MagCapacity

	task.wait((reload and reload.Length) or config[currentMode].ReloadSpeed)

	determineAnim('RechargeEnd', 'play')

	canfire = true
	reloading = false
end

local function reloadTypeOne()
	canfire = false
	reloading = true

	if boltLockedBack then
		determineAnim('EmptyIdle', 'stop')
		boltLockedBack = false
	end

	local number = handleAmmo()
	local mode = (config[currentMode].useSharedClip and 1) or currentMode

	-- Determine if the magazine is completely empty or still has rounds
	local isEmpty = (tool.LocalTAmmo[mode].Ammo.Value <= 0)

	-- Pick animation: use ReloadEmpty for empty mag if it exists, otherwise fall back to Reload
	local reloadAnimName = 'Reload'
	if isEmpty then
		local hasEmptyAnim = animations[tostring(currentMode)..'ReloadEmpty'] or animations['ReloadEmpty']
		if hasEmptyAnim then
			reloadAnimName = 'ReloadEmpty'
		end
	end

	-- Pick reload timing: use ReloadEmptySpeed for empty mag if defined, otherwise ReloadSpeed
	local reloadTime = config[currentMode].ReloadSpeed
	if isEmpty and config[currentMode].ReloadEmptySpeed then
		reloadTime = config[currentMode].ReloadEmptySpeed
	end

	-- Pick GFX type: 'ReloadEmpty' for empty mag, 'Reload' for partial
	local gfxType = isEmpty and 'ReloadEmpty' or 'Reload'

	-- Play the appropriate animation
	if (controls.sprinting.Value and animations['SprintReload']) then
		determineAnim('SprintReload','play')
	else
		determineAnim(reloadAnimName,'play')
	end

	makePercCounter(reloadTime)
	shared.S.TREK_Remotes.GFX:FireServer(gfxType, currentMode, 'Main')

	task.wait(reloadTime)

	if config[mode].ReservedAmmo == math.huge then 
		tool.LocalTAmmo[mode].Ammo.Value = number
	else
		tool.LocalTAmmo[mode].Stored.Value -= number
		tool.LocalTAmmo[mode].Ammo.Value += number
	end	

	updateAmmo()

	canfire = true
	reloading = false
end

local function reloadSecurityChecks()
	local mode = (config[currentMode].useSharedClip and 1) or currentMode

	if (chr.Humanoid.RigType == Enum.HumanoidRigType.R6 and not chr:FindFirstChild('Left Arm')) then
		return
	end
	if (chr.Humanoid.RigType == Enum.HumanoidRigType.R15 and not chr:FindFirstChild('LeftHand')) then
		return
	end

	if not config[currentMode].CanReload then return end
	if equipping then return end
	if switchingModes then return end
	if inspecting then return end
	if tool.LocalTAmmo[mode].Stored.Value <= 0 then return end
	if tool.TAmmo[mode].Stored.Value <= 0 then return end
	if reloading then return end

	return true
end

local function Reload()
	if not reloadSecurityChecks() then return end

	-- Fire voice trigger at the START of the reload, before the reload animation
	-- yields. Firing from the client directly so the voiceline starts immediately
	-- on the button press, not after the reload animation completes.
	pcall(function()
		shared.S.TREK_Remotes.VoicePlayRequest:FireServer("Reload")
	end)

	disableBarrelFX()
	local mode = (config[currentMode].useSharedClip and 1) or currentMode

	if config[mode].ReloadOnlyWithEmptyMag then
		if tool.LocalTAmmo[mode].Ammo.Value > 0 then warn('local tammo check') return end
		if tool.TAmmo[mode].Ammo.Value > 0 then warn('tammo check') return end
	end

	if tool.LocalTAmmo[mode].Ammo.Value >= config[mode].MagCapacity then return end

	if config[currentMode].ReloadType == 1 then
		reloadTypeOne()
	elseif config[currentMode].ReloadType == 2 then
		reloadTypeTwo()
	end

	shared.S.TREK_Remotes.Reload:FireServer(currentMode)
end

local function handleFireRate()
	task.wait(60/config[currentMode].RoundsPerMinute)
	firing = false
	canfire = true
end

local function findNearestAlly()
	for i,player in pairs(plr.Team:GetPlayers()) do
		local char = player.Character

		if player == plr then return end
		if not char then return end
		if not char:FindFirstChild('HumanoidRootPart') then return end

		if char.Humanoid.Health > 0 and (char.HumanoidRootPart.Position - plr.Character.HumanoidRootPart.Position).Magnitude<=config.Range then
			return player, char
		end

	end
end

local function windUp()
	if chargecooldown then return end

	if ((config[currentMode].useSharedClip and tool.LocalTAmmo[1].Ammo.Value) or tool.LocalTAmmo[currentMode].Ammo.Value) <= 0 then Reload() return end

	enableBarrelChargeFX()

	shared.S.TREK_Remotes.GFX:FireServer('WindUp', currentMode, 'Main')

	determineAnim('WindUp','play')

	chargecooldown = true
	charging = true
	task.wait(config[currentMode].ChargeTime)

	disableBarrelChargeFX()

	if not equipped then return end
end

local function CameraShakeFunction()
	--[[
		if (controls.crouching.Value and chr:WaitForChild('Humanoid'):GetState() ~= Enum.HumanoidStateType.Freefall) then
		spread += config[currentMode].crouchSpreadAddition
	end
	if chr:WaitForChild('Humanoid'):GetState() == Enum.HumanoidStateType.Freefall then
		spread += config[currentMode].jumpSpreadAddition
	end
	if ((shared.S.globalConfig.EnableMedical) and (not chr:FindFirstChild('Left Arm'))) then 
		spread += config[currentMode].oneHandedSpreadAddition
	end
	if zoomed then 
		spread += config[currentMode].zoomSpreadAddition
	end
	]]
	local crouchMultiplier = (controls.crouching.Value and config[currentMode].CameraShakeCrouchMultiplier) or 1
	local zoomMultiplier = (zoomed and config[currentMode].CameraShakeZoomMultiplier) or 1

	local m = config[currentMode].CameraShakeMagnitude * crouchMultiplier * zoomMultiplier
	local r = config[currentMode].CameraShakeRoughness * crouchMultiplier * zoomMultiplier
	local fi = config[currentMode].CameraShakeFadeInTime
	local fo = config[currentMode].CameraShakeFadeOutTime

	camShake:ShakeOnce(m,r,fi,fo)
end

local function CamRecoilFunction()    
	local X,Y,Z = config[currentMode].RecoilX, config[currentMode].RecoilY, config[currentMode].RecoilZ
	local crouchMultiplier = (controls.crouching.Value and config[currentMode].RecoilCrouchMultiplier) or 1
	local zoomMultiplier = (zoomed and config[currentMode].RecoilZoomMultiplier) or 1

	if typeof(X) == 'table' then
		local rnd = math.random(X[1],X[2])

		X = rnd
	end
	if typeof(Y) == 'table' then
		local rnd = math.random(Y[1],Y[2])

		Y = rnd
	end
	if typeof(Z) == 'table' then
		local rnd = math.random(Z[1],Z[2])

		Z = rnd 
	end

	X = math.rad(X * crouchMultiplier * zoomMultiplier)
	Y = math.rad(Y * crouchMultiplier * zoomMultiplier)
	Z = math.rad(Z * crouchMultiplier * zoomMultiplier)

	RecoilSpring:Impulse(Vector3.new(X, Y, Z))
end

local function shoot()
	firing = true
	canfire = false

	if controls.sprinting.Value then
		plrconfig.SprintEnabled.Value = false
	end

	-- Skip per-shot muzzle flash and sound for continuous fire weapons (flamethrowers)
	-- Their visuals and audio are handled by ContinuousBarrelFX and ContinuousFireSound
	if not config[currentMode].ContinuousFireSound then
		shared.S.TREK_Remotes.GFX:FireServer('GunFire', currentMode, currentBarrel.Name)
	end

	for i = 1,config[currentMode].RaysPerShot do
		handleRays()
		if config[currentMode].FiringShakesCamera then CameraShakeFunction() end
		if config[currentMode].CameraRecoil then CamRecoilFunction() end
	end

	-- Viewmodel spring recoil
	if Viewmodel.Rig then
		local intensity = config[currentMode].ViewRecoilIntensity or 1
		local vX = config[currentMode].ViewRecoilUp or config[currentMode].RecoilX or 3
		local vY = config[currentMode].ViewRecoilSide or config[currentMode].RecoilY or 0
		local vZ = config[currentMode].ViewRecoilTilt or 0
		local vBack = config[currentMode].ViewRecoilBack or 1.5
		local vUp = config[currentMode].ViewRecoilLift or 0.15

		if typeof(vX) == 'table' then vX = math.random(vX[1], vX[2]) end
		if typeof(vY) == 'table' then vY = math.random(vY[1], vY[2]) end
		if typeof(vZ) == 'table' then vZ = math.random(vZ[1], vZ[2]) end

		local crouchMult = (controls.crouching.Value and (config[currentMode].RecoilCrouchMultiplier or 1)) or 1
		local zoomMult = (zoomed and (config[currentMode].RecoilZoomMultiplier or 1)) or 1
		local totalMult = intensity * crouchMult * zoomMult

		local ROTATION_SCALE = 0.5
		local rotImpulse = Vector3.new(
			vX * ROTATION_SCALE * totalMult,
			vY * ROTATION_SCALE * totalMult,
			vZ * ROTATION_SCALE * totalMult
		)
		local posImpulse = Vector3.new(0, vUp * totalMult, vBack * totalMult)

		Viewmodel.applyRecoil(rotImpulse, posImpulse)
	end

	local mode = (config[currentMode].useSharedClip and 1) or currentMode
	tool.LocalTAmmo[mode].Ammo.Value -= 1

	shared.S.TREK_Remotes.AmmoRemote:FireServer(currentMode)

	-- Play recoil animation: use AimRecoil when zoomed if it exists, otherwise fall back to Recoil
	local recoilAnimName = 'Recoil'
	if zoomed then
		local hasAimRecoil = animations[tostring(currentMode)..'AimRecoil'] or animations['AimRecoil']
		if hasAimRecoil then
			recoilAnimName = 'AimRecoil'
		end
	end

	local recoilTrack = determineAnim(recoilAnimName, nil, true)
	if recoilTrack then
		recoilTrack.Looped = false
		recoilTrack:Stop(0)
		recoilTrack.TimePosition = 0
		recoilTrack:Play(0)
	end

	updateAmmo()

	-- Bolt lock back: if last round fired and config has BoltLockBack enabled
	if config[currentMode].BoltLockBack then
		local mode = (config[currentMode].useSharedClip and 1) or currentMode
		if tool.LocalTAmmo[mode].Ammo.Value <= 0 then
			boltLockedBack = true

			-- Play bolt lock sound
			local boltSound = module:FindFirstChild(tostring(currentMode)..'BoltLock') or module:FindFirstChild('BoltLock')
			if boltSound and boltSound:IsA('Sound') then
				shared.S.TREK_Remotes.GFX:FireServer('ExplosiveSound', currentMode, 'BoltLock')
			end

			-- Play EmptyIdle animation
			determineAnim('EmptyIdle', 'play')
		end
	end

	handleFireRate()
	--determineAnim('Idle'):Play()
end

local function Burst()
	local number
	local sharedClip = tool.LocalTAmmo[1].Ammo
	local modeClip = tool.LocalTAmmo[currentMode].Ammo.Value

	if config[currentMode].useSharedClip then
		number = ((sharedClip.Value - config[currentMode].BurstAmount > 0 and config[currentMode].BurstAmount) or sharedClip.Value)
	else
		number = (modeClip.Value - config[currentMode].BurstAmount > 0 and config[currentMode].BurstAmount or modeClip.Value)
	end

	if config[currentMode].Charged then windUp() end
	enableBarrelFX()

	for i = 1, number do
		shoot()
	end

	-- Stop the last Recoil/AimRecoil track
	determineAnim('Recoil', 'stop')
	determineAnim('AimRecoil', 'stop')

	disableBarrelFX()
	if config[currentMode].Charged then WindDown() end
end

local function Auto()
	if config[currentMode].Charged then windUp() end
	enableBarrelFX()

	local ranOutOfAmmo = false

	while mouseClick and equipped and not reloading and canfire do
		if not equipped then break end
		if not mouseClick then break end
		if not canfire then break end

		if config[currentMode].useSharedClip then
			if tool.LocalTAmmo[1].Ammo.Value <= 0 then
				ranOutOfAmmo = true
				if not config[currentMode].BoltLockBack then Reload() end
				break
			end
		else
			if tool.LocalTAmmo[currentMode].Ammo.Value <= 0 then
				ranOutOfAmmo = true
				if not config[currentMode].BoltLockBack then Reload() end
				break
			end
		end

		shoot()
	end

	-- Stop the last Recoil/AimRecoil track so it doesn't lock the character in firing pose
	determineAnim('Recoil', 'stop')
	determineAnim('AimRecoil', 'stop')

	disableBarrelFX()

	-- Only play WindDown if we didn't run out of ammo (reload handles its own flow)
	if config[currentMode].Charged and not ranOutOfAmmo then
		WindDown()
	elseif config[currentMode].Charged and ranOutOfAmmo then
		-- Still need to reset charging state so firing works after reload
		charging = false
		chargecooldown = false
	end
end

local function Semi()
	if config[currentMode].Charged then windUp() end
	enableBarrelFX()
	shoot()

	-- Stop the last Recoil/AimRecoil track
	determineAnim('Recoil', 'stop')
	determineAnim('AimRecoil', 'stop')

	disableBarrelFX()

	if config[currentMode].Charged then WindDown() end
end

local function mousePress()
	if not equipped then return end
	if equipping then return end
	if switchingModes then return end
	if inspecting then return end
	if tool:GetAttribute("DynamicDisabled") then return end -- Destructible part broke, tool disabled
	if ((config[currentMode].useSharedClip and tool.LocalTAmmo[1].Ammo.Value) or tool.LocalTAmmo[currentMode].Ammo.Value) <= 0 then Reload() return end
	if not canfire then return end
	if reloading then return end
	if charging then return end
	if chargecooldown then return end
	if chr:WaitForChild('Humanoid').Health <= 0 then return end

	mouseClick = true

	if patrolling then localcontrols.patrol() end

	local types = {
		[1] = Auto;
		[2] = Semi;
		[3] = Burst;
	}
	local func = types[config[currentMode].GunType]
	func()

	disableBarrelFX()
	disableBarrelChargeFX()
end

local function mouseRelease()
	if not equipped then return end

	mouseClick = false
	disableBarrelFX()
	disableBarrelChargeFX()
end

--zoomLevels
--currentZoomLevel
--table[index]
local function zoomIncrease()
	if not zoomed then return end
	if typeof(config[currentMode].ZoomFov) == 'number' then return end

	if modeStuff[currentMode].zoomLevels[currentZoomLevel + 1] then
		currentZoomLevel += 1
	else
		currentZoomLevel = #modeStuff[currentMode].zoomLevels
	end

	FOVToUse = tonumber((currentZoomLevel and modeStuff[currentMode].zoomLevels[currentZoomLevel]) or config[currentMode].ZoomFov)

	if config[currentMode].Scope then
		UIS.MouseDeltaSensitivity = workspace.CurrentCamera.FieldOfView/100 * 0.5
	end

	workspace.CurrentCamera.FieldOfView = FOVToUse
end

local function zoomDecrease()
	if not zoomed then return end
	if typeof(config[currentMode].ZoomFov) == 'number' then return end

	if modeStuff[currentMode].zoomLevels[currentZoomLevel - 1] then
		currentZoomLevel -= 1
	else
		currentZoomLevel = 1
	end

	FOVToUse = tonumber((currentZoomLevel and modeStuff[currentMode].zoomLevels[currentZoomLevel]) or config[currentMode].ZoomFov)	

	if config[currentMode].Scope then
		UIS.MouseDeltaSensitivity = workspace.CurrentCamera.FieldOfView/100 * 0.5
	end

	workspace.CurrentCamera.FieldOfView = FOVToUse
end

local function TurnToTarget()
	if not chr then return end
	if chr.Humanoid.SeatPart then return end
	if controls.sprinting.Value then return end
	if patrolling then return end
	if reloading then return end
	if chr:GetAttribute("BipodActive") or chr:GetAttribute("BipodDeploying") then return end

	local corePart:BasePart = chr:FindFirstChild('HumanoidRootPart')
	if not corePart then return end

	local aimPos = getFreshAimPosition()
	local lookAt = Vector3.new(aimPos.X, corePart.Position.Y, aimPos.Z)
	local cf = CFrame.new(corePart.Position, lookAt)

	--corePart.CFrame = cf
	corePart:PivotTo(cf)
end

local function CameraRecoilLoop()
	workspace.CurrentCamera.CFrame *= CFrame.Angles(RecoilSpring.Position.X,RecoilSpring.Position.Y,RecoilSpring.Position.Z)
end

local function mouseMoved()
	local t = mouse.Target
	marker.Position = UDim2.new(0, mouse.X, 0, mouse.Y) + UDim2.new(0,0,0,9)
	ammobar.Position = UDim2.new(0, mouse.X, 0, mouse.Y) + UDim2.new(0,0,0,64)

	if t ~= nil then
		if t.Parent:FindFirstChild('Humanoid') or t.Parent.Parent:FindFirstChild('Humanoid') then
			local player = (t.Parent:FindFirstChild('Humanoid') and game.Players:GetPlayerFromCharacter(t.Parent) or game.Players:GetPlayerFromCharacter(t.Parent.Parent))
			if player then
				if (player.Team == plr.Team and not config[currentMode].TeamKill) then
					mouseLegacy.Icon = 'rbxassetid://'..shared.Cursors.Friendly
					return
				else
					mouseLegacy.Icon = 'rbxassetid://'..shared.Cursors.Enemy
					return
				end
			end
		end
	end
	mouseLegacy.Icon = 'rbxassetid://'..shared.Cursors.Main
end

local function input(input, done)
	if equipped and not done then
		local inputs = {
			[shared.S.globalConfig.ReloadKey] = Reload;
			[shared.S.globalConfig.PatrolKey] = localcontrols.patrol;
			[shared.S.globalConfig.modeKey] = switchModes;
			[shared.S.globalConfig.zoomIncrease] = zoomIncrease;
			[shared.S.globalConfig.zoomDecrease] = zoomDecrease;

			-- Inspect weapon (only works in patrol mode)
			[shared.S.globalConfig.InspectKey or Enum.KeyCode.F] = localcontrols.inspect;

			-- ADD THIS LINE:
			[Enum.UserInputType.MouseButton2] = function()
				if patrolling then return end
				if not zoomed then
					localcontrols.zoom()
				end
			end;
		}

		-- CHANGE THIS LINE:
		local func = inputs[input.KeyCode] or inputs[input.UserInputType]
		if func then
			func()
		end
	end
end

-- EXECUTION
tool.Equipped:Connect(onEquip)
tool.Unequipped:Connect(onUnEquip)

mouse.Button1Down:Connect(mousePress)
mouse.Button1Up:Connect(mouseRelease)

mouse.Move:Connect(function()
	if equipped then
		mouseMoved()
	end
end)

RUNSERV.RenderStepped:Connect(function()
	if not equipped then
		return
	end

	if config[currentMode].TurnToTarget then
		TurnToTarget()
	end

	CameraRecoilLoop()
end)

caster.RayHit:Connect(onRayHit)
--caster.LengthChanged:Connect(lengthChanged)
caster.CastTerminating:Connect(castEnded)

UIS.InputBegan:Connect(input)

UIS.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		if patrolling then return end
		if zoomed then
			localcontrols.zoom()
		end
	end
end)

chr.ChildRemoved:Connect(function(child)
	if (chr.Humanoid.RigType == Enum.HumanoidRigType.R6 and child.Name == 'Right Arm') then
		tool.Parent = plr.Backpack
		tool:Destroy()
	end
	if (chr.Humanoid.RigType == Enum.HumanoidRigType.R15 and child.Name == 'RightHand') then
		tool.Parent = plr.Backpack
		tool:Destroy()
	end
end)

chr:WaitForChild('Humanoid').Died:Connect(function()
	if BipodController.isDeployed() or BipodController.isDeploying() then
		BipodController.cancel()
	end

	onUnEquip()
	Viewmodel.unequip()

	canfire	= false
	--reloading = true

	for bar, _ in pairs(activeProgressBars) do
		if bar then bar:Destroy() end
		bar = nil
	end

	-- Direct camera reset (no tweens - survives script destruction)
	zoomed = false
	workspace.CurrentCamera.FieldOfView = defaultFov
	plr.CameraMaxZoomDistance = defaultZoomOut
	plr.CameraMinZoomDistance = defaultZoomIn
	UIS.MouseDeltaSensitivity = 1

	if controls.sprinting.Value then controls.sprint() end
	if patrolling then localcontrols.patrol() end
end)

shared.S.TREK_Remotes.Reload.OnClientEvent:Connect(function()
	local mode = (config[currentMode].useSharedClip and 1) or currentMode

	if tool.LocalTAmmo[mode].Stored.MaxValue ~= math.huge then
		tool.LocalTAmmo[mode].Stored.Value = tool.LocalTAmmo[mode].Stored.MaxValue
		Reload()
	end
end)

controls.sprinting:GetPropertyChangedSignal('Value'):Connect(function()
	-- Bipod deploy/deployed: sprint state must not trigger animation swaps or yaw lock changes.
	-- The server's weld assembly holds the player in place; sprinting is meaningless in this state.
	if chr:GetAttribute("BipodActive") or chr:GetAttribute("BipodDeploying") then return end

	if equipped then
		if controls.sprinting.Value then
			chr:SetAttribute("YawLockActive", false)
			if patrolling then localcontrols.patrol() end
			determineAnim('Idle','stop')
			determineAnim('SprintHold','play')
		else
			if not patrolling then
				chr:SetAttribute("YawLockActive", true)
			end
			determineAnim('Idle','play')
			determineAnim('SprintHold','stop')
		end
	end
end)

task.spawn(function()
	if config[currentMode].ReloadType == 3 then
		while true do
			local mode = (config[currentMode].useSharedClip and 1) or currentMode

			if tool.LocalTAmmo[mode].Ammo.Value < config[mode].MagCapacity and not firing then
				if tool.LocalTAmmo[mode].Stored.Value <= 0 then continue end		

				tool.LocalTAmmo[mode].Ammo.Value += 1
				if config[mode].ReservedAmmo ~= math.huge then tool.LocalTAmmo[mode].Stored.Value -= 1 end
				updateAmmo()

				if tool.LocalTAmmo[mode].Ammo.Value >= config[mode].MagCapacity then continue end
			end

			task.wait(config[currentMode].ReloadSpeed)
		end
	end
end)