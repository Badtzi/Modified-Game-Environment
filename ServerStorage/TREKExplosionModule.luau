--[[
	TREKExplosionModule
	Location: ServerStorage
	
	Handles explosion damage, wall checks, and visual effects for all
	TREK explosive weapons. Supports player, vehicle, and THealth targets.
	Incendiary explosions apply burning DOT via TREKDamageModule.
	
	Required by: TREKServerGeneral (explosive rays), TREKDynamicWeapons (destruction explosions)
]]

local module = {}

local lbmod = require(shared.S.TREK_Modules.LeaderBoardModule)
local effects = require(shared.S.TREK_Modules.EffectsModule)
local damagemodule = require(game.ServerStorage:WaitForChild("TREKDamageModule"))

local par = OverlapParams.new()
par.FilterDescendantsInstances = {workspace:WaitForChild("IgnoreList"), workspace:WaitForChild("Explosions")}
par.FilterType = Enum.RaycastFilterType.Exclude

local raypar = RaycastParams.new()
raypar.FilterType = Enum.RaycastFilterType.Exclude
raypar.IgnoreWater = true

------------------------------------------------------------------------
-- DAMAGE CALCULATION
------------------------------------------------------------------------

local function handleExplosionFallOff(config, damage, distance)
	local fostart = config.explosionFullDamageRadius or 10
	local foend = config.explosionRadius

	if distance < fostart then
		return damage
	elseif distance > foend then
		return 0
	end

	distance -= fostart
	local middle = damage / (foend - fostart)
	return math.round(damage - (middle * distance))
end

local function calcDamage(config, usearmour, part, exppos)
	local damage = (usearmour and config.ArmourDamage) or config.Damage
	local distance = (exppos - part.Position).Magnitude
	local result = handleExplosionFallOff(config, damage, distance)

	if usearmour and part:FindFirstChild("RequiredArmourDamage") then
		if result < part.RequiredArmourDamage.Value then return 0 end
	end

	if usearmour and part:FindFirstChild("ArmourDamageResist") then
		result = math.clamp(0, (result - part.ArmourDamageResist.Value), math.huge)
	end

	return result
end

------------------------------------------------------------------------
-- PERMISSION CHECKS
------------------------------------------------------------------------

local function wallSecurity(player, part, pos, config, chr2)
	local destination = (part.Position - pos)

	if player and player.Character then
		raypar.FilterDescendantsInstances = {workspace:WaitForChild("IgnoreList"), player.Character, chr2}
	else
		raypar.FilterDescendantsInstances = {workspace:WaitForChild("IgnoreList"), chr2}
	end

	-- Filter out the explosion source character (e.g. backpack wearer)
	if config.explosionSourceCharacter then
		local current = raypar.FilterDescendantsInstances
		table.insert(current, config.explosionSourceCharacter)
		raypar.FilterDescendantsInstances = current
	end

	local ray = workspace:Raycast(pos, destination, raypar)
	if ray then return false end

	return true
end

local function CheckIfDamageAllowed(player: Player, target: Player, teamkill: boolean)
	if not player then return true end
	if player == target then return true end
	if teamkill then return true end
	if target.Team ~= player.Team then return true end

	return false
end

local function checkIfArmourDamageAllowed(player: Player, target, teamkill: boolean)
	if not player then return true end
	if teamkill then return true end

	if target:FindFirstChild("Team") then
		if player.Team ~= target.Team.Value then return true end
	end

	return false
end

------------------------------------------------------------------------
-- TARGET-SPECIFIC DAMAGE HANDLERS
------------------------------------------------------------------------

local function plrDamage(player, plr2, chr2, part, config, pos)
	if not CheckIfDamageAllowed(player, plr2, config.TeamKill) then return end

	if chr2.Humanoid.SeatPart then
		if chr2.Humanoid.SeatPart:IsA("VehicleSeat") then return end
	end

	if not config.explosionsIgnoreWalls then
		if not wallSecurity(player, part, pos, config, chr2) then return end
	end

	local damage = calcDamage(config, false, part, pos)
	chr2.Humanoid:TakeDamage(damage)

	shared.S.trekGibs.handleGibs(part, config, chr2, pos)

	if config.Incendiary and damage > 0 then
		damagemodule.ApplyIncendiary(player, chr2)
	end

	if player then
		lbmod.tagPlr(chr2.Humanoid, player)
		if damage <= 0 then return end
		effects.Hitmark.DrawEffect(player, "plr")
	end
end

local function TVehicleDamage(player, part, config, pos, vehicle)
	if not vehicle:FindFirstChild("Stats") then return end
	if not checkIfArmourDamageAllowed(player, vehicle.Stats, config.TeamKill) then return end

	if vehicle.Stats:FindFirstChild("ResistIndirectDamage") and not config.superExplosion then
		if vehicle.Stats.ResistIndirectDamage.Value then return end
	end

	local damage = calcDamage(config, true, part, pos)

	if vehicle.Stats.Health.Value > vehicle.Stats.Health.MinValue then
		vehicle.Stats.Health.Value -= damage
	end
end

local function TPartDamage(player, part, config, pos)
	if part:FindFirstChild("ResistIndirectDamage") then
		if part.ResistIndirectDamage.Value then return end
	end
	if not checkIfArmourDamageAllowed(player, part, config.TeamKill) then return end

	local damage = calcDamage(config, true, part, pos)
	part.THealth.Value -= damage

	if player then
		if damage <= 0 then return end
		effects.Hitmark.DrawEffect(player, "armr")
	end
end

------------------------------------------------------------------------
-- PUBLIC API
------------------------------------------------------------------------

function module.handleExplosion(player, moduleInstance, config, position)
	if not config.explosionRadius then warn("[TREKExplosionModule] No explosionRadius in config!") end

	shared.S.TREK_Remotes.Explosion:FireAllClients(position, (config.explosionRadius or config.fallOffEnd), config.explosionName)

	local parts = workspace:GetPartBoundsInRadius(position, (config.explosionRadius or config.fallOffEnd), par)

	for _, part in ipairs(parts) do
		local isTHealth = part:FindFirstChild("THealth")
		local isTVehicle = part:FindFirstAncestor("TVehicle")
		local isPlr, chr = shared.S.trekFuncs.findPlrAndChar(part)

		if isTHealth then
			TPartDamage(player, part, config, position)
		elseif isTVehicle then
			TVehicleDamage(player, part, config, position, isTVehicle)
		elseif isPlr then
			plrDamage(player, isPlr, chr, part, config, position)
		end
	end
end

return module
