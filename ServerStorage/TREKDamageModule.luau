--[[
	TREKDamageModule
	Location: ServerStorage
	
	Core damage calculation and application for all TREK weapon systems.
	Handles player damage, vehicle damage, part (THealth) damage, and
	damage falloff. Also provides incendiary (fire DOT) support.
	
	Required by: TREKServerDamage, TREKExplosionModule, TREKDynamicWeapons
]]

local module = {}

local lbmodule = require(game.ReplicatedStorage.TREK_SERVICES.TREK_Modules.LeaderBoardModule)

local TAG = Instance.new("ObjectValue")

------------------------------------------------------------------------
-- DAMAGE CALCULATION
------------------------------------------------------------------------

local function handleFallOff(config, damage, distance)
	local fostart = config.fallOffStart
	local foend = config.fallOffEnd

	if distance < fostart then
		return damage
	elseif distance > foend then
		return 0
	end

	distance -= fostart
	local middle = damage / (foend - fostart)
	return math.round(damage - (middle * distance))
end

local function AddWeaponTag(src, plr, duration)
	if src:FindFirstChild("WeaponTag") then
		src.WeaponTag:Destroy()
	end

	local tag = TAG:Clone()
	tag.Name = "WeaponTag"
	tag.Value = plr
	tag.Parent = src

	task.delay(duration or 0.4, function()
		if tag then tag:Destroy() end
	end)
end

------------------------------------------------------------------------
-- PUBLIC API
------------------------------------------------------------------------

function module.setDamage(config, Target: BasePart, Origin, ArmorDamage)
	local distance = (Origin - Target.Position).Magnitude
	local damage = (ArmorDamage and config.ArmourDamage) or config.Damage
	local result = handleFallOff(config, damage, distance)

	if ArmorDamage and Target:FindFirstChild("RequiredArmourDamage") then
		if result < Target.RequiredArmourDamage.Value then return 0 end
	end

	if ArmorDamage and Target:FindFirstChild("ArmourDamageResist") then
		result = math.clamp(0, (result - Target.ArmourDamageResist.Value), math.huge)
	end

	if Target.Name == "Head" or Target:FindFirstAncestor("Head") then
		result *= config.headShotMultiplier
	end

	return result
end

function module.DamageVehicle(player, target, damage)
	if not target:FindFirstChild("Stats") then return end

	target.Stats.Health.Value -= damage
	AddWeaponTag(target, player, 1)
end

function module.DamagePart(player, target, damage)
	if not target:FindFirstChild("THealth") then return end

	target.THealth.Value -= damage
	AddWeaponTag(target, player, 1)

	if target.THealth.Value <= target.THealth.MinValue then
		if target:FindFirstChild("THealthKill") then target.THealthKill:Fire(player) end
	end
end

function module.DamagePlayer(player, target, damage)
	if not target:FindFirstChild("Humanoid") then return end

	target.Humanoid:TakeDamage(damage)
	lbmodule.tagPlr(target.Humanoid, player)
	lbmodule.UpdateStat(player, "Damage", damage)
end

------------------------------------------------------------------------
-- INCENDIARY
-- Clones TBurning (disabled Script in ServerStorage) onto the target.
-- Stores attacker as ObjectValue for kill credit. No-op if already burning.
------------------------------------------------------------------------

function module.ApplyIncendiary(player, target)
	if not target then return end
	if not target:FindFirstChild("Humanoid") then return end
	if target.Humanoid.Health <= 0 then return end
	if target:GetAttribute("TBurningActive") then return end
	if target:FindFirstChild("TBurning") then return end

	local template = game.ServerStorage:FindFirstChild("TBurning")
	if not template then
		warn("[TREKDamageModule] TBurning not found in ServerStorage!")
		return
	end

	local burning = template:Clone()

	if player then
		local attackerTag = Instance.new("ObjectValue")
		attackerTag.Name = "Attacker"
		attackerTag.Value = player
		attackerTag.Parent = burning
	end

	burning.Parent = target
	burning.Disabled = false
end

return module
