-- VARIABLES
-- repeat wait() until shared.TREK_STATUS_INFO.Installed

local raypar = RaycastParams.new()
raypar.FilterType = Enum.RaycastFilterType.Exclude
raypar.IgnoreWater = true

local damagemodule = require(game.ServerStorage:WaitForChild('TREKDamageModule'))
local universalFuncs = require(game.ReplicatedStorage.TREK_SERVICES.TREK_Modules:WaitForChild('TREKUniversalFunctions'))

local vehicleEffects
if game.ReplicatedStorage.TREK_SERVICES.TREK_Modules:WaitForChild('TREKVehicleEffects', 6) then
	vehicleEffects = require(game.ReplicatedStorage.TREK_SERVICES.TREK_Modules.TREKVehicleEffects)
end

-- FUNCTIONS
local function CheckIfDamageAllowed(player:Player, target:Player, teamkill:boolean)
	if not player then return true end
	if player == target then return true end
	if teamkill then return true end

	if player ~= target then
		if target.Team ~= player.Team then return true end
	end

	return false
end

local function checkIfArmourDamageAllowed(player:Player, target, teamkill:boolean)
	if not player then return true end
	if teamkill then return true end

	if target:FindFirstChild('Team') then
		if player.Team ~= target.Team.Value then return true end
	end

	return false
end

local function Security(plr,part,partSize,chr,chr2,config)
	if shared.S.globalConfig.ServerRays then
		if not chr:FindFirstChild('Head') then return true end
		if not chr2:FindFirstChild('Head') then return true end

		local origin = chr.Head.Position
		local destination = chr2.Head.Position
		local direction = (destination - origin).Unit * config.Distance

		raypar.FilterDescendantsInstances = {workspace:WaitForChild('IgnoreList'), chr}
		local ray = workspace:Raycast(origin,direction,raypar)

		if ray then
			if ray.Instance then	
				local theplr,thechr = shared.S.trekFuncs.findPlrAndChar(ray.Instance)
				if not (thechr == chr2) then return true end
			end
		end
	end

	if shared.S.globalConfig.AntiHBE then
		if not part then return end
		if not part:IsA("BasePart") then return end

		if part.Size ~= partSize then 
			plr:Kick('HBE POSITIVE')
			shared.S.TREK_Remotes.SystemMessage:FireAllClients(tostring(plr.Name..' HAS TRIGGERED ANTI-HBE, CLIENT: '..part.Size..' | SERVER: '..partSize))    
			return true    
		end
	end

end

local function TVehicleDamage(plr, part, vehicle, module, config, tool, currentMode, OriginPos)
	if not vehicle:FindFirstChild('Stats') then return end

	if vehicle.Stats:FindFirstChild('Team') then
		if not checkIfArmourDamageAllowed(plr, vehicle.Stats, config.TeamKill) then return end	
	end

	local dmg = damagemodule.setDamage(config, part, OriginPos, true)
	damagemodule.DamageVehicle(plr, vehicle, dmg)

	if not vehicleEffects then return end
	if not part:FindFirstChild('RicochetChance') then return end

	vehicleEffects.Ricochet(part.Position, config.ProjectileName, part.RicochetChance.Value)
end

local function TPartDamage(plr, part, module, config, tool, currentMode, OriginPos)
	if part:FindFirstChild('Team') then
		if not checkIfArmourDamageAllowed(plr, part, config.TeamKill) then return end	
	end

	local dmg = damagemodule.setDamage(config, part, OriginPos, true)
	damagemodule.DamagePart(plr, part, dmg)
end

local function plrDamage(plr, chr2, OriginPos, part, config)
	local dmg = damagemodule.setDamage(config, part, OriginPos, false)
	if not dmg then warn('NO DAMAGE!') return end

	damagemodule.DamagePlayer(plr, chr2, dmg)
	shared.S.trekGibs.handleGibs(part, config, chr2, OriginPos)

	-- Incendiary: apply burning DOT if the weapon config has Incendiary = true
	if config.Incendiary and dmg > 0 then
		damagemodule.ApplyIncendiary(plr, chr2)
	end
end

local function moduleChecks(tool, currentMode)
	local reqmod,module = shared.S.trekServerFuncs.checkForModule(tool)

	if not module then return end
	if not reqmod[currentMode] then return end
	local config = reqmod[currentMode]

	return true,module,config,reqmod
end

local function toolChecks(plr,chr)
	local tool = shared.S.trekServerFuncs.returnTool(plr,chr)
	if not tool then return end

	return true,tool
end

local function plrCharacterChecks(plr)
	local chr = plr.Character
	if not chr then return end
	if not chr:FindFirstChild('Humanoid') then return end

	return true,chr
end

local function ammoChecks(tool,reqmod,config,currentMode,chr)
	local mode = (reqmod[currentMode].useSharedClip and 1) or currentMode
	local ammo = tool:FindFirstChild('TAmmo')

	if chr.Humanoid.SeatPart then
		if chr.Humanoid.SeatPart:IsA('VehicleSeat') and chr.Humanoid.SeatPart:FindFirstAncestor('TVehicle') then
			local vehicle = chr.Humanoid.SeatPart:FindFirstAncestor('TVehicle')
			ammo = vehicle:FindFirstChild('TAmmo')
		end
	end

	if not ammo then return end
	if not ammo:FindFirstChild(currentMode) then return end
	if ammo[mode].Ammo.Value > (config.MagCapacity + 1) then warn('>MAX AMMO!') return end
	if ammo[mode].Ammo.Value < 0 then warn('<0 AMMO!') return end

	return true
end

local function enemyChecks(plr,part,config)	
	local plr2, chr2 = shared.S.trekFuncs.findPlrAndChar(part)
	if not plr2 then return end
	if not chr2 then return end

	local hrp = chr2:FindFirstChild('HumanoidRootPart')
	local head = chr2:FindFirstChild('Head')
	local hum = chr2:FindFirstChild('Humanoid')

	if not hrp then return end
	if not head then return end
	if not hum then return end

	if hum.Health <= 0 then return end

	if not CheckIfDamageAllowed(plr, plr2, config.TeamKill) then return end
	if chr2:FindFirstChild('ForceField') then return end

	return true,plr2,chr2,hrp,head,hum
end

local function handleDamage(plr:Player, OriginPos, Target:BasePart, TargetSize, currentMode)
	local chrStatus,chr = plrCharacterChecks(plr)
	if not chrStatus then warn('CHR CHECKS FAIL!') return end

	local ToolCheck, Tool = toolChecks(plr,chr)
	if not ToolCheck then warn('TOOL CHECKS FAIL!') return end

	local moduleStatus, module, config, reqmod = moduleChecks(Tool,currentMode)
	if not moduleStatus then warn('MODULE CHECKS FAIL!') return end

	if not ammoChecks(Tool,reqmod,config,currentMode,chr) then return end

	if Target:FindFirstChild('THealth') then
		TPartDamage(plr, Target, module, config, Tool, currentMode, OriginPos)
		return
	end

	if Target:FindFirstAncestor('TVehicle') then
		TVehicleDamage(plr, Target, Target:FindFirstAncestor('TVehicle'), module, config, Tool, currentMode, OriginPos)
		return
	end

	local enemyStatus, enemyPlr, enemyChr, enemHRP, enemyHead, enemyHum = enemyChecks(plr,Target, config)
	if not enemyStatus then return end

	local positive = Security(plr, Target, TargetSize, chr, enemyChr, config)
	if positive then return end

	plrDamage(plr, enemyChr, OriginPos, Target, config)

	-- Voice: victim got hit + attacker caused damage
	pcall(function()
		if shared.VoicePlay then
			shared.VoicePlay(enemyPlr, "Hit")
			shared.VoicePlay(plr, "CauseDamage")
		end
	end)
end

-- EXECUTION
shared.S.TREK_Remotes:WaitForChild('Damage').OnServerEvent:Connect(handleDamage)
