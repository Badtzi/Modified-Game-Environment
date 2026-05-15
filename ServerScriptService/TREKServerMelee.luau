-- TREKServerMelee.luau
-- Handles melee damage validation and takedown/execution sequences

-- Wait for TREK to initialize
repeat task.wait() until shared.S and shared.S.TREK_Remotes and shared.S.trekServerFuncs

-- VARIABLES
local RUNSERV = game:GetService('RunService')
local damagemodule = require(game.ServerStorage:WaitForChild('TREKDamageModule'))
local universalFuncs = require(game.ReplicatedStorage.TREK_SERVICES.TREK_Modules:WaitForChild('TREKUniversalFunctions'))

local activeTakedowns = {}

-- HELPER FUNCTIONS
local function getPlayerAndCharacter(plr)
	local chr = plr.Character
	if not chr then return end
	local hum = chr:FindFirstChild('Humanoid')
	if not hum or hum.Health <= 0 then return end
	return chr
end

local function getMeleeConfig(tool, currentMode)
	local reqmod, mod = shared.S.trekServerFuncs.checkForMeleeModule(tool)
	if not reqmod or not reqmod[currentMode] then return end
	return reqmod[currentMode], reqmod, mod
end

local function CheckIfDamageAllowed(attacker, target, teamkill)
	if not attacker then return true end
	if attacker == target then return false end
	if teamkill then return true end
	return target.Team ~= attacker.Team
end

-- Shared cleanup for victim death (used in both completion paths)
local function cleanupVictimDeath(takedownData, victimHum, victimHRP, victimPlr)
	if takedownData.victimTrack then
		takedownData.victimTrack:Stop(0)
		takedownData.victimTrack = nil
	end
	if victimHum then
		victimHum:ChangeState(Enum.HumanoidStateType.Physics)
	end
	task.delay(0.1, function()
		if victimHRP and victimHRP.Parent then
			victimHRP.Anchored = false
			pcall(function() victimHRP:SetNetworkOwner(victimPlr) end)
		end
	end)
end

-- MELEE DAMAGE HANDLER
local function handleMeleeDamage(plr, targetPart, currentMode)
	local chr = getPlayerAndCharacter(plr)
	if not chr then return end
	if chr:GetAttribute('InTakedown') then return end

	local tool = shared.S.trekServerFuncs.returnTool(plr, chr)
	if not tool then return end

	local cfg = getMeleeConfig(tool, currentMode)
	if not cfg then return end

	if not targetPart or not targetPart:IsA('BasePart') then return end

	local hrp = chr:FindFirstChild('HumanoidRootPart')
	if not hrp then return end

	-- THealth parts (destructible objects)
	if targetPart:FindFirstChild('THealth') then
		if targetPart:FindFirstChild('Team') then
			if targetPart.Team.Value == plr.Team and not cfg.TeamKill then return end
		end

		local distance = (hrp.Position - targetPart.Position).Magnitude
		if distance > (cfg.Range * 2) then return end

		damagemodule.DamagePart(plr, targetPart, cfg.ArmourDamage or cfg.Damage)
		return
	end

	-- Player targets
	local plr2, chr2 = universalFuncs.findPlrAndChar(targetPart)
	if not plr2 or not chr2 then return end

	local enemyHum = chr2:FindFirstChild('Humanoid')
	if not enemyHum or enemyHum.Health <= 0 then return end
	if not CheckIfDamageAllowed(plr, plr2, cfg.TeamKill) then return end
	if chr2:FindFirstChild('ForceField') then return end

	local distance = (hrp.Position - chr2.HumanoidRootPart.Position).Magnitude
	if distance > (cfg.Range * 2) then return end

	local dmg = damagemodule.setDamage(cfg, targetPart, hrp.Position, false)
	if not dmg then return end

	damagemodule.DamagePlayer(plr, chr2, dmg)
end

-- TAKEDOWN HANDLER
local function handleTakedownRequest(plr, victimChr, currentMode)
	local chr = getPlayerAndCharacter(plr)
	if not chr then return end
	if chr:GetAttribute('InTakedown') or activeTakedowns[plr] then return end

	local tool = shared.S.trekServerFuncs.returnTool(plr, chr)
	if not tool then return end

	local cfg, reqmod, mod = getMeleeConfig(tool, currentMode)
	if not cfg or not cfg.TakedownEnabled then return end

	if not victimChr or not victimChr:IsA('Model') then return end
	local victimHum = victimChr:FindFirstChild('Humanoid')
	if not victimHum or victimHum.Health <= 0 then return end

	local victimPlr = game.Players:GetPlayerFromCharacter(victimChr)
	if not victimPlr then return end
	if victimChr:GetAttribute('InTakedown') then return end
	if not CheckIfDamageAllowed(plr, victimPlr, cfg.TeamKill) then return end

	local attackerHRP = chr:FindFirstChild('HumanoidRootPart')
	local victimHRP = victimChr:FindFirstChild('HumanoidRootPart')
	if not attackerHRP or not victimHRP then return end

	local distance = (attackerHRP.Position - victimHRP.Position).Magnitude
	if distance > (cfg.TakedownRange * 2) then return end

	-- Validate the damage would actually kill
	if victimHum.Health > cfg.Damage then
		damagemodule.DamagePlayer(plr, victimChr, cfg.Damage)
		return
	end

	-- ===================== BEGIN TAKEDOWN =====================

	chr:SetAttribute('InTakedown', true)
	victimChr:SetAttribute('InTakedown', true)

	-- ForceField on victim
	local forceField = Instance.new('ForceField')
	forceField.Name = 'TakedownForceField'
	forceField.Visible = false
	forceField.Parent = victimChr

	-- Lock movement
	local attackerWS = chr.Humanoid.WalkSpeed
	local victimWS = victimHum.WalkSpeed
	local attackerJP = chr.Humanoid.JumpPower
	local victimJP = victimHum.JumpPower

	chr.Humanoid.WalkSpeed = 0
	victimHum.WalkSpeed = 0
	chr.Humanoid.JumpPower = 0
	victimHum.JumpPower = 0

	-- Disable character controllers
	chr.Humanoid.PlatformStand = true
	victimHum.PlatformStand = true
	chr.Humanoid.AutoRotate = false
	victimHum.AutoRotate = false

	-- Take network ownership and anchor
	attackerHRP:SetNetworkOwner(nil)
	victimHRP:SetNetworkOwner(nil)

	-- Raycast down from attacker to find ground, snap to ground level before anchoring.
	-- Prevents floating if takedown triggers mid-air or during a jump.
	local HRP_HEIGHT = 3 -- R6 HRP sits ~3 studs above ground
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterDescendantsInstances = {chr, victimChr, workspace:FindFirstChild("IgnoreList")}

	local groundResult = workspace:Raycast(attackerHRP.Position, Vector3.new(0, -50, 0), groundParams)
	if groundResult then
		local groundY = groundResult.Position.Y + HRP_HEIGHT
		local pos = attackerHRP.Position
		local snappedPos = Vector3.new(pos.X, groundY, pos.Z)
		attackerHRP.CFrame = CFrame.new(snappedPos) * (attackerHRP.CFrame - attackerHRP.CFrame.Position)
	end

	attackerHRP.Anchored = true
	victimHRP.Anchored = true

	-- Position both characters (uses attacker's snapped position)
	local attackerStartCF = attackerHRP.CFrame
	local victimStartCF
	if cfg.TakedownOffset then
		victimStartCF = attackerStartCF * cfg.TakedownOffset * CFrame.Angles(0, math.rad(180), 0)
		victimHRP.CFrame = victimStartCF
	else
		-- Snap victim to ground level too
		local vicGroundResult = workspace:Raycast(victimHRP.Position, Vector3.new(0, -50, 0), groundParams)
		if vicGroundResult then
			local groundY = vicGroundResult.Position.Y + HRP_HEIGHT
			local pos = victimHRP.Position
			local snappedPos = Vector3.new(pos.X, groundY, pos.Z)
			victimHRP.CFrame = CFrame.new(snappedPos) * (victimHRP.CFrame - victimHRP.CFrame.Position)
		end
		victimStartCF = victimHRP.CFrame
	end

	-- Server-side position enforcement
	local positionEnforcer = RUNSERV.Heartbeat:Connect(function()
		if not attackerHRP or not attackerHRP.Parent or not attackerHRP.Anchored then return end
		if not victimHRP or not victimHRP.Parent then return end
		attackerHRP.CFrame = attackerStartCF
		if victimStartCF then victimHRP.CFrame = victimStartCF end
	end)

	-- Track takedown
	local takedownData = {
		attacker = plr,
		attackerChr = chr,
		victim = victimPlr,
		victimChr = victimChr,
		config = cfg,
		cancelled = false,
		attackerWS = attackerWS,
		victimWS = victimWS,
		attackerJP = attackerJP,
		victimJP = victimJP,
		forceField = forceField,
		positionEnforcer = positionEnforcer,
	}
	activeTakedowns[plr] = takedownData

	local duration = cfg.TakedownDuration or 3.0

	-- Play animations from server
	for _, track in ipairs(chr.Humanoid:GetPlayingAnimationTracks()) do track:Stop(0) end
	for _, track in ipairs(victimHum:GetPlayingAnimationTracks()) do track:Stop(0) end

	-- Unequip victim's tool AFTER stopping all animations
	-- Holster system will create visual + animation that won't be killed
	local victimTool = victimChr:FindFirstChildOfClass('Tool')
	if victimTool then
		victimTool.Parent = victimPlr.Backpack
	end

	if mod and mod:FindFirstChild('Animations') then
		local atkAnim = mod.Animations:FindFirstChild('TakedownAttacker')
		if atkAnim and atkAnim:IsA('Animation') and atkAnim.AnimationId ~= '' then
			local track = chr.Humanoid:LoadAnimation(atkAnim)
			track.Priority = Enum.AnimationPriority.Action4
			track:Play()
			takedownData.attackerTrack = track
		end

		local vicAnim = mod.Animations:FindFirstChild('TakedownVictim')
		if vicAnim and vicAnim:IsA('Animation') and vicAnim.AnimationId ~= '' then
			local track = victimHum:LoadAnimation(vicAnim)
			track.Priority = Enum.AnimationPriority.Action4
			track:Play()
			takedownData.victimTrack = track
		end
	end

	-- Play takedown sound (server-side, audible to all nearby players)
	-- Searches for: Takedown sound in config module
	if mod then
		local takedownSound = mod:FindFirstChild('Takedown')
		if takedownSound and takedownSound:IsA('Sound') then
			local soundParent = tool:FindFirstChild('Main') or tool:FindFirstChild('Handle') or tool:FindFirstChildWhichIsA('BasePart')
			if soundParent then
				local s = takedownSound:Clone()
				s.Parent = soundParent
				s:Play()
				task.delay(s.TimeLength + 1, function()
					if s then s:Destroy() end
				end)
			end
		end
	end

	-- Notify clients (send CFrame data for local position enforcement)
	shared.S.TREK_Remotes.TakedownSync:FireClient(plr, chr, victimChr, duration, attackerStartCF, victimStartCF)
	shared.S.TREK_Remotes.TakedownSync:FireClient(victimPlr, chr, victimChr, duration, attackerStartCF, victimStartCF)

	-- Listen for attacker damage (only actual damage, not regen)
	local attackerStartHealth = chr.Humanoid.Health
	local healthConnection
	healthConnection = chr.Humanoid.HealthChanged:Connect(function(newHealth)
		if takedownData.cancelled then return end
		if newHealth >= attackerStartHealth then
			attackerStartHealth = newHealth
			return
		end

		-- Cancel takedown
		takedownData.cancelled = true
		healthConnection:Disconnect()

		if takedownData.positionEnforcer then
			takedownData.positionEnforcer:Disconnect()
			takedownData.positionEnforcer = nil
		end

		chr:SetAttribute('InTakedown', false)
		victimChr:SetAttribute('InTakedown', false)

		if forceField and forceField.Parent then forceField:Destroy() end
		if takedownData.attackerTrack then takedownData.attackerTrack:Stop(0); takedownData.attackerTrack = nil end
		if takedownData.victimTrack then takedownData.victimTrack:Stop(0); takedownData.victimTrack = nil end

		-- Unanchor and restore ownership
		if attackerHRP then attackerHRP.Anchored = false; attackerHRP:SetNetworkOwner(plr) end
		if victimHRP then victimHRP.Anchored = false; victimHRP:SetNetworkOwner(victimPlr) end

		-- Restore character controllers
		if chr:FindFirstChild('Humanoid') then
			chr.Humanoid.PlatformStand = false
			chr.Humanoid.AutoRotate = true
			chr.Humanoid.WalkSpeed = takedownData.attackerWS
			chr.Humanoid.JumpPower = takedownData.attackerJP
		end
		if victimChr:FindFirstChild('Humanoid') then
			victimHum.PlatformStand = false
			victimHum.AutoRotate = true
			victimHum.WalkSpeed = takedownData.victimWS
			victimHum.JumpPower = takedownData.victimJP
		end

		shared.S.TREK_Remotes.TakedownCancel:FireClient(plr)
		shared.S.TREK_Remotes.TakedownCancel:FireClient(victimPlr)

		activeTakedowns[plr] = nil
	end)

	-- Takedown completion
	task.delay(duration, function()
		if takedownData.cancelled then return end

		healthConnection:Disconnect()
		if takedownData.positionEnforcer then
			takedownData.positionEnforcer:Disconnect()
			takedownData.positionEnforcer = nil
		end

		if forceField and forceField.Parent then forceField:Destroy() end
		if takedownData.attackerTrack then takedownData.attackerTrack:Stop(0.2); takedownData.attackerTrack = nil end

		-- Notify attacker client
		shared.S.TREK_Remotes.TakedownCancel:FireClient(plr)

		-- Kill victim while anchored
		local takedownDmg = cfg.TakedownDamage or 100
		if victimChr:FindFirstChild('Humanoid') and victimHum.Health > 0 then
			damagemodule.DamagePlayer(plr, victimChr, takedownDmg)
		end

		-- Clear attributes
		chr:SetAttribute('InTakedown', false)
		victimChr:SetAttribute('InTakedown', false)

		-- Restore attacker
		if attackerHRP then attackerHRP.Anchored = false; attackerHRP:SetNetworkOwner(plr) end
		if chr:FindFirstChild('Humanoid') then
			chr.Humanoid.PlatformStand = false
			chr.Humanoid.AutoRotate = true
			chr.Humanoid.WalkSpeed = takedownData.attackerWS
			chr.Humanoid.JumpPower = takedownData.attackerJP
		end

		-- Victim death cleanup
		if victimChr:FindFirstChild('Humanoid') then
			if victimHum.Health <= 0 then
				cleanupVictimDeath(takedownData, victimHum, victimHRP, victimPlr)
			else
				victimHum.Died:Once(function()
					cleanupVictimDeath(takedownData, victimHum, victimHRP, victimPlr)
				end)
			end
		end

		activeTakedowns[plr] = nil
	end)
end

-- CLEANUP on player leaving
local function onPlayerRemoving(plr)
	local takedown = activeTakedowns[plr]
	if not takedown then return end

	takedown.cancelled = true

	if takedown.positionEnforcer then takedown.positionEnforcer:Disconnect(); takedown.positionEnforcer = nil end
	if takedown.attackerTrack then takedown.attackerTrack:Stop(0); takedown.attackerTrack = nil end
	if takedown.victimTrack then takedown.victimTrack:Stop(0); takedown.victimTrack = nil end

	if takedown.victimChr then
		takedown.victimChr:SetAttribute('InTakedown', false)
		if takedown.forceField and takedown.forceField.Parent then takedown.forceField:Destroy() end
		if takedown.victimChr:FindFirstChild('Humanoid') then
			takedown.victimChr.Humanoid.PlatformStand = false
			takedown.victimChr.Humanoid.AutoRotate = true
			takedown.victimChr.Humanoid.WalkSpeed = takedown.victimWS
			takedown.victimChr.Humanoid.JumpPower = takedown.victimJP
		end
		local victimHRP = takedown.victimChr:FindFirstChild('HumanoidRootPart')
		if victimHRP then
			victimHRP.Anchored = false
			pcall(function() victimHRP:SetNetworkOwner(takedown.victim) end)
		end
		if takedown.victim then
			shared.S.TREK_Remotes.TakedownCancel:FireClient(takedown.victim)
		end
	end

	activeTakedowns[plr] = nil
end

-- EXECUTION
shared.S.TREK_Remotes:WaitForChild('MeleeDamage').OnServerEvent:Connect(handleMeleeDamage)
shared.S.TREK_Remotes:WaitForChild('TakedownRequest').OnServerEvent:Connect(handleTakedownRequest)
game.Players.PlayerRemoving:Connect(onPlayerRemoving)
