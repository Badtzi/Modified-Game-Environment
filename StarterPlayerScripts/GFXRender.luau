-- VARIABLES
repeat wait() until game.Players.LocalPlayer.Character

local plr = game.Players.LocalPlayer
local chr = plr.Character

local tween = function(object,goal,tt,es,ed)
	return game:GetService("TweenService"):Create(object,TweenInfo.new(tt,Enum.EasingStyle[es],Enum.EasingDirection[ed],0,false,0),goal)
end

local shakeModule = require(shared.S.TREK_Modules.CameraShaker)
local camShake = shakeModule.new(Enum.RenderPriority.Camera.Value, function(shakeCf)
	workspace.CurrentCamera.CFrame = workspace.CurrentCamera.CFrame * shakeCf
end)
camShake:Start()

local effects = require(shared.S.TREK_Modules.EffectsModule)
local impactEffects = require(shared.S.TREK_Modules.ImpactParticlesModule)
local universalFuncs = require(shared.S.TREK_Modules:WaitForChild('TREKUniversalFunctions'))

-- Viewmodel reference for first-person barrel resolution
local Viewmodel = require(shared.S.TREK_Modules:WaitForChild("TREKViewmodel"))

-- HELPER: Resolve the correct barrel part based on first-person state.
-- In first person, the real tool is hidden and positioned at the third-person location,
-- so we use the viewmodel's cloned barrel instead for accurate effect placement.
local function resolveBarrel(tool, source, player)
	-- Only redirect for the local player when in first person with viewmodel active
	if player == plr and Viewmodel.IsFirstPerson and Viewmodel.ViewmodelTool then
		local vmBarrel = Viewmodel.ViewmodelTool:FindFirstChild(source, true)
		if vmBarrel then
			return vmBarrel
		end
	end

	-- Default: use the real tool's barrel
	local barrel = tool:FindFirstChild(source, true)

	-- Check if the tool has a TVehicleAsset
	local vehicleAsset = tool:FindFirstChild('TVehicleAsset')
	if not barrel and vehicleAsset and vehicleAsset.Value then
		local v = vehicleAsset.Value:FindFirstAncestor('TVehicle')
		if v then
			barrel = v:FindFirstChild(source, true)
		end
	end

	return barrel
end

-- FUNCTIONS
local function emitLight(light,cooldown)
	spawn(function()
		light.Enabled = true
		wait(cooldown ~= nil and cooldown or 0.1)
		light.Enabled = false
	end)
end

local function seatCheck(hum:Humanoid)
	if not hum.SeatPart then return true end
	if not hum.SeatPart:FindFirstAncestor('TVehicle') then return true end
	if hum.SeatPart:FindFirstChild('UnarmoredSeat') then return true end

	return false	
end

local function playSound(sound, origin, randomPitch)
	local clone = sound:Clone()

	clone.Parent = origin

	if randomPitch then
		local BasePlayback = clone.PlaybackSpeed * 100
		clone.PlaybackSpeed = math.random(BasePlayback - 10, BasePlayback + 10)/100
	end

	clone:Play()

	universalFuncs.DestroyDelayed(clone, clone.TimeLength + 0.1)
end

local function GunFire(tool, module, reqmod, currentMode, player, source)	
	local barrel = resolveBarrel(tool, source, player)

	if not barrel then
		warn('Invalid origin: ' .. tostring(source))
		return
	end

	-- Draw the muzzle flash effect
	effects.MuzzleFlash.DrawEffect(barrel)

	-- Play the appropriate sound
	local sound = (module:FindFirstChild(tostring(currentMode) .. 'Fire') and module[tostring(currentMode) .. 'Fire']) or module.Fire
	playSound(sound, barrel, true)
end

local function WindDown(tool,module,reqmod,currentMode,player,source)
	local barrel = resolveBarrel(tool, source, player)
	if not barrel then warn('no barrel!') return end

	local sound = ((module:FindFirstChild(tostring(currentMode)..'WindDown') and module[tostring(currentMode)..'WindDown']) or module.WindDown)

	playSound(sound, barrel, false)	
end

local function WindUp(tool,module,reqmod,currentMode,player,source)
	local barrel = resolveBarrel(tool, source, player)
	if not barrel then warn('no barrel!') return end

	local sound = ((module:FindFirstChild(tostring(currentMode)..'WindUp') and module[tostring(currentMode)..'WindUp']) or module.WindUp)

	playSound(sound, barrel, false)	
end

local function Reload(tool,module,reqmod,currentMode,player,source)
	local sound = ((module:FindFirstChild(tostring(currentMode)..'Reload') and module[(tostring(currentMode)..'Reload')]) or module.Reload)

	local origin = resolveBarrel(tool, source, player)
	if not origin then
		if tool:FindFirstChild('TVehicleAsset') then
			local v = tool.TVehicleAsset.Value:FindFirstAncestor('TVehicle')
			origin = v.Gun:FindFirstChild('GunBase')
		else
			origin = tool:FindFirstChild('Main')		
		end
	end
	if not origin then warn('Invalid origin: '..source) return end

	playSound(sound, origin, false)
end

local function ReloadEmpty(tool,module,reqmod,currentMode,player,source)
	local sound = ((module:FindFirstChild(tostring(currentMode)..'ReloadEmpty') and module[(tostring(currentMode)..'ReloadEmpty')]) or module:FindFirstChild('ReloadEmpty') or module.Reload)

	local origin = resolveBarrel(tool, source, player)
	if not origin then
		if tool:FindFirstChild('TVehicleAsset') then
			local v = tool.TVehicleAsset.Value:FindFirstAncestor('TVehicle')
			origin = v.Gun:FindFirstChild('GunBase')
		else
			origin = tool:FindFirstChild('Main')		
		end
	end
	if not origin then warn('Invalid origin: '..source) return end

	playSound(sound, origin, false)
end

local function SwitchReload(tool,module,reqmod,currentMode,player,source)
	local sound = ((module:FindFirstChild(tostring(currentMode)..'SwitchReload') and module[(tostring(currentMode)..'SwitchReload')]) or module.SwitchReload)

	local origin = resolveBarrel(tool, source, player)

	if not origin then
		if tool:FindFirstChild('TVehicleAsset') then
			local v = tool.TVehicleAsset.Value:FindFirstAncestor('TVehicle')
			origin = v.Gun:FindFirstChild('GunBase')
		else
			origin = tool:FindFirstChild('Main')		
		end
	end
	if not origin then warn('Invalid origin: '..source) return end

	playSound(sound, origin, false)
end

local function StopUsage(tool,module,reqmod,currentMode,player)
	if not tool.Main:FindFirstChild('Use') then return end
	tool.Main.Use:Destroy()
end

local function StartUsage(tool,module,reqmod,currentMode,player)
	if not module:FindFirstChild('Use') then warn('No usage sound found!') return end
	local sound = module.Use:Clone()
	sound.Parent = tool.Main
	sound:Play()
end

local function MeleeSwing(tool,module,reqmod,currentMode,player,source)
	local origin = tool:FindFirstChild('Main') or tool:FindFirstChild('Handle') or tool:FindFirstChildWhichIsA('BasePart')
	if not origin then return end

	-- source contains the swing name (e.g. 'Swing1', 'Swing2') for combo-specific sounds
	local sound = module:FindFirstChild(tostring(currentMode) .. source)
		or module:FindFirstChild(source)
		or module:FindFirstChild(tostring(currentMode) .. 'Swing')
		or module:FindFirstChild('Swing')
	if sound and sound:IsA('Sound') then
		playSound(sound, origin, true)
	end
end

local function MeleeHit(tool,module,reqmod,currentMode,player,source)
	local origin = tool:FindFirstChild('Main') or tool:FindFirstChild('Handle') or tool:FindFirstChildWhichIsA('BasePart')
	if not origin then return end

	local sound = module:FindFirstChild(tostring(currentMode)..'Hit') or module:FindFirstChild('Hit')
	if sound then
		playSound(sound, origin, false)
	end
end

local function InspectSound(tool, module, reqmod, currentMode, player, source)
	local origin = resolveBarrel(tool, source, player) or tool:FindFirstChild('Main')
	if not origin then return end

	local sound = module:FindFirstChild(tostring(currentMode)..'Inspect') or module:FindFirstChild('Inspect')
	if sound and sound:IsA('Sound') then
		playSound(sound, origin, false)
	end
end

-- Generic explosive sound handler.
-- The source parameter carries the sound name (Equip, PinPull, Throw, Reload).
-- Looks for a Sound child of that name in the config module.
local function ExplosiveSound(tool, module, reqmod, currentMode, player, source)
	local origin = tool:FindFirstChild('Main') or tool:FindFirstChild('AnimPart') or tool:FindFirstChildWhichIsA('BasePart')
	if not origin then return end

	local sound = module:FindFirstChild(source)
	if sound and sound:IsA('Sound') then
		playSound(sound, origin, false)
	end
end

-- Continuous fire sound for weapons like flamethrowers.
-- Plays a looping Fire sound that persists until FireSoundStop is called.
local activeContinuousSounds = {} -- [tool] = Sound instance

local function FireSoundStart(tool, module, reqmod, currentMode, player, source)
	local barrel = resolveBarrel(tool, source, player)
	if not barrel then return end

	-- Stop existing continuous sound on this tool
	if activeContinuousSounds[tool] then
		activeContinuousSounds[tool]:Stop()
		activeContinuousSounds[tool]:Destroy()
		activeContinuousSounds[tool] = nil
	end

	-- Find fire sound (same lookup as GunFire)
	local sound = (module:FindFirstChild(tostring(currentMode) .. 'Fire') and module[tostring(currentMode) .. 'Fire']) or module.Fire
	if not sound then return end

	local clone = sound:Clone()
	clone.Looped = true
	clone.Parent = barrel
	clone:Play()

	activeContinuousSounds[tool] = clone

	-- Auto-cleanup: if the tool gets unequipped (reparented out of character),
	-- stop the looping sound automatically. This prevents the sound from
	-- persisting when the server can't relay FireSoundStop after unequip.
	local cleanupConn
	cleanupConn = tool.AncestryChanged:Connect(function()
		if activeContinuousSounds[tool] then
			activeContinuousSounds[tool]:Stop()
			activeContinuousSounds[tool]:Destroy()
			activeContinuousSounds[tool] = nil
		end
		if cleanupConn then cleanupConn:Disconnect(); cleanupConn = nil end
	end)
end

local function FireSoundStop(tool, module, reqmod, currentMode, player, source)
	if activeContinuousSounds[tool] then
		activeContinuousSounds[tool]:Stop()
		activeContinuousSounds[tool]:Destroy()
		activeContinuousSounds[tool] = nil
	end
end

-- Barrel FX replication: enable/disable ParticleEmitters and Lights on the
-- tool's barrel for ALL clients. Gun.luau fires these via the GFX remote.
local function BarrelFXStart(tool, module, reqmod, currentMode, player, source)
	local barrel = resolveBarrel(tool, source, player)
	if not barrel then return end

	-- For the local player in first person: also disable the REAL tool's barrel
	-- particles so they don't float in viewport center while viewmodel barrel plays.
	if player == plr and Viewmodel.IsFirstPerson and Viewmodel.ViewmodelTool then
		local realBarrel = tool:FindFirstChild(source, true)
		if realBarrel and realBarrel ~= barrel then
			for _, child in ipairs(realBarrel:GetDescendants()) do
				if child:IsA("ParticleEmitter") then child.Enabled = false end
				if child:IsA("PointLight") or child:IsA("SpotLight") then child.Enabled = false end
			end
		end
	end

	for _, child in ipairs(barrel:GetDescendants()) do
		if child:IsA("ParticleEmitter") then child.Enabled = true end
		if child:IsA("PointLight") or child:IsA("SpotLight") then child.Enabled = true end
	end
end

local function BarrelFXStop(tool, module, reqmod, currentMode, player, source)
	local barrel = resolveBarrel(tool, source, player)
	if not barrel then return end

	for _, child in ipairs(barrel:GetDescendants()) do
		if child:IsA("ParticleEmitter") then child.Enabled = false end
		if child:IsA("PointLight") or child:IsA("SpotLight") then child.Enabled = false end
	end
end

local function handleGFX(type, tool, module, reqmod, currentMode, player, source)
	if not tool then warn('Failed to find the tool') return end
	if not module then warn('Failed to find the module') return end
	if not reqmod then warn('Failed to find the required module') return end
	if not currentMode then warn('Failed to determine current weapon mode') return end

	local actions = {
		['GunFire'] = GunFire;
		['WindDown'] = WindDown;
		['WindUp'] = WindUp;
		['Reload'] = Reload;
		['ReloadEmpty'] = ReloadEmpty;
		['SwitchReload'] = SwitchReload;
		['StartUsage'] = StartUsage;
		['StopUsage'] = StopUsage;
		['MeleeSwing'] = MeleeSwing;
		['MeleeHit'] = MeleeHit;
		['InspectSound'] = InspectSound;
		['FireSoundStart'] = FireSoundStart;
		['FireSoundStop'] = FireSoundStop;
		['BarrelFXStart'] = BarrelFXStart;
		['BarrelFXStop'] = BarrelFXStop;
		['BarrelChargeFXStart'] = BarrelFXStart;  -- reuses same handler, source='BarrelCharge'
		['BarrelChargeFXStop'] = BarrelFXStop;    -- reuses same handler, source='BarrelCharge'
		['ExplosiveSound'] = ExplosiveSound;      -- generic: source = sound name in config
	}

	local action = actions[type]
	if not action then warn('Failed to find the action'..tostring(type)) return end

	action(tool, module, reqmod, currentMode, player, source)
end

local function renderBoom(pos, range, type)
	if not range then range = 16 end
	if not type then type = 'Explosion' end
	if not impactEffects[type] then type = 'Explosion' end

	impactEffects[type].DrawEffect(pos)

	if not plr.Character:FindFirstChild('HumanoidRootPart') then return end
	local newdistance = (pos - plr.Character.HumanoidRootPart.Position).Magnitude

	if not plr.Character:FindFirstChild('Humanoid') then return end
	if not seatCheck(plr.Character.Humanoid) then return end

	-- Only run the generic Explosion shake/knockback for the default explosion type.
	-- Custom impact types (FuelTankExplosion, etc.) handle their own shake/sounds.
	if type == 'Explosion' then
		effects.Explosion.DrawEffect(plr, chr, pos, newdistance, range)
	end
end

-- EXECUTION
shared.S.TREK_Remotes.GFX.OnClientEvent:Connect(handleGFX)
shared.S.TREK_Remotes.Explosion.OnClientEvent:Connect(renderBoom)

-- TAKEDOWN VICTIM HANDLER
local RUNSERV = game:GetService('RunService')

local takedownScriptsToPause = {
	"Directional Walking Script",
	"MovementLean",
	"Realistic Head Movement",
	"CameraBobbing"
}

local R6_JOINT_DEFAULTS = {
	RootJoint = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
	Neck = CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
	['Right Shoulder'] = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	['Left Shoulder'] = CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
	['Right Hip'] = CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	['Left Hip'] = CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
}

local victimPositionEnforcer = nil
local victimDiedConnection = nil

local function cleanupVictimTakedown()
	if victimPositionEnforcer then victimPositionEnforcer:Disconnect(); victimPositionEnforcer = nil end
	if victimDiedConnection then victimDiedConnection:Disconnect(); victimDiedConnection = nil end
end

local function onTakedownSync(attackerChr, victimChr, duration, attackerCF, victimCF)
	if not plr.Character or plr.Character ~= victimChr then return end

	plr.Character:SetAttribute("TakedownActive", true)

	-- Disable interfering scripts
	local animateScript = plr.Character:FindFirstChild('Animate')
	if animateScript then animateScript.Disabled = true end

	for _, scriptName in ipairs(takedownScriptsToPause) do
		local s = plr.Character:FindFirstChild(scriptName, true)
		if s and s:IsA("LocalScript") then s.Disabled = true end
	end

	-- Enforce positions on RenderStepped (self-terminating)
	if attackerCF and victimCF and attackerChr and victimChr then
		local atkHRP = attackerChr:FindFirstChild('HumanoidRootPart')
		local vicHRP = victimChr:FindFirstChild('HumanoidRootPart')
		if atkHRP and vicHRP then
			atkHRP.CFrame = attackerCF
			vicHRP.CFrame = victimCF

			victimPositionEnforcer = RUNSERV.RenderStepped:Connect(function()
				if not atkHRP or not atkHRP.Parent or not atkHRP.Anchored then
					cleanupVictimTakedown()
					return
				end
				if not vicHRP or not vicHRP.Parent then
					cleanupVictimTakedown()
					return
				end
				atkHRP.CFrame = attackerCF
				vicHRP.CFrame = victimCF
			end)
		end
	end

	-- Backup cleanup on death
	local humanoid = plr.Character:FindFirstChild('Humanoid')
	if humanoid then
		victimDiedConnection = humanoid.Died:Once(function()
			cleanupVictimTakedown()
		end)
	end
end

local function onTakedownCancel()
	if not plr.Character then return end

	plr.Character:SetAttribute("TakedownActive", false)
	cleanupVictimTakedown()

	-- Reset R6 joints
	local humanoid = plr.Character:FindFirstChild('Humanoid')
	if humanoid then
		-- Stop ALL playing animation tracks to kill orphans from disabled scripts
		-- Skip holster animations (Idle priority + Looped) — they're managed by the server
		for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
			if track.Priority == Enum.AnimationPriority.Idle and track.Looped then
				continue
			end
			track:Stop(0)
		end

		if humanoid.RigType == Enum.HumanoidRigType.R6 then
			local torso = plr.Character:FindFirstChild('Torso')
			if torso then
				for jointName, defaultC0 in pairs(R6_JOINT_DEFAULTS) do
					local joint = torso:FindFirstChild(jointName) or plr.Character.HumanoidRootPart:FindFirstChild(jointName)
					if joint then joint.C0 = defaultC0 end
				end
			end
		elseif humanoid.RigType == Enum.HumanoidRigType.R15 then
			local head = plr.Character:FindFirstChild('Head')
			if head then
				local neck = head:FindFirstChild('Neck')
				if neck then neck.C0 = CFrame.new(0, -0.5, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1) end
			end
		end
	end

	-- Re-enable scripts
	local animateScript = plr.Character:FindFirstChild('Animate')
	if animateScript then animateScript.Disabled = false end

	for _, scriptName in ipairs(takedownScriptsToPause) do
		local s = plr.Character:FindFirstChild(scriptName, true)
		if s and s:IsA("LocalScript") then s.Disabled = false end
	end
end

if shared.S.TREK_Remotes:FindFirstChild('TakedownSync') then
	shared.S.TREK_Remotes.TakedownSync.OnClientEvent:Connect(onTakedownSync)
end
if shared.S.TREK_Remotes:FindFirstChild('TakedownCancel') then
	shared.S.TREK_Remotes.TakedownCancel.OnClientEvent:Connect(onTakedownCancel)
end
