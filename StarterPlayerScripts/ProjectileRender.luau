-- VARIABLES
repeat wait() until game.Players.LocalPlayer.Character

local plr = game.Players.LocalPlayer
local chr = plr.Character

local tween = function(object,goal,tt,es,ed)
	return game:GetService("TweenService"):Create(object,TweenInfo.new(tt,Enum.EasingStyle[es],Enum.EasingDirection[ed],0,false,0),goal)
end

local FASTCAST = require(shared.S.TREK_Modules.FastCastRedux)

local casters = {}

local effects = require(shared.S.TREK_Modules.EffectsModule)
local impactEffects = require(shared.S.TREK_Modules.ImpactParticlesModule)

-- FUNCTIONS
local function castEnded(caster)
	local bullet = caster.RayInfo.CosmeticBulletObject
	if not bullet then return end
	
	bullet.Transparency = 1
	bullet.CanCollide = false
	bullet.Anchored = true
	
	for i,v in pairs(bullet:GetDescendants()) do
		if v:IsA("ParticleEmitter") then v.Enabled = false
		elseif v:IsA("Light") then tween(v,{Brightness = 0},0.25,"Quint","Out"):Play()
		elseif v:IsA('BillboardGui') then v:Destroy()
		elseif v:IsA('Sound') then tween(v, {Volume = 0}, 0.25, 'Quint', 'Out'):Play()
		end
	end
	
	shared.S.trekFuncs.DestroyDelayed(bullet,3)
end

local function lengthChanged(thecaster, lastpoint, direction, displacement, velocity, bulletobj)
	local pos = lastpoint + (direction * displacement)
	bulletobj.Position = pos
end

local function rayHit(caster, rayresult, veloccity, bullet)
	local obj = rayresult.Instance
	local pos = rayresult.Position
	local normal = rayresult.Normal

	if not obj then return end
	
	if caster.UserData['CanSuppress'] then
		effects.Suppress.DrawEffect(plr,plr.Character,bullet,caster.UserData['ExtraSuppression'])
	end
	
	if caster.UserData['ImpactEffect'] then
		if not impactEffects[caster.UserData['ImpactEffect']] then return end

		impactEffects[caster.UserData['ImpactEffect']].DrawEffect(bullet.Position, rayresult.Instance.Color)
	end
end

local function returnCaster(name)
	if not casters[name] then
		casters[name] = FASTCAST.new()

		casters[name].LengthChanged:Connect(lengthChanged)
		casters[name].CastTerminating:Connect(castEnded)
		casters[name].RayHit:Connect(rayHit)
	end
	return casters[name]
end

-- EXECUTION
shared.S.TREK_Remotes.ProjectileRemote.OnClientEvent:Connect(function(theplr, name, pos, dir, vel, behavior, cansuppress, extrasuppression, impacteffect)
	if plr == theplr then return end
	
	local caster = returnCaster(name)
	local active = caster:Fire(pos, dir, vel, behavior)
	
	active.UserData['CanSuppress'] = cansuppress
	active.UserData['ExtraSuppression'] = extrasuppression
	active.UserData['ImpactEffect'] = impacteffect
end)

--(tool.Name, barrel.Position, dir, config[currentMode].ProjectileVelocity, modeStuff[currentMode].fastCastBehavior, currentMode)
shared.S.TREK_Remotes.ProjectileBind.Event:Connect(function(name, pos, dir, vel, behavior, cansuppress, extrasuppression, impacteffect)
	
	local caster = returnCaster(name)
	local active = caster:Fire(pos, dir, vel, behavior)

	active.UserData['CanSuppress'] = cansuppress
	active.UserData['ExtraSuppression'] = extrasuppression
	active.UserData['ImpactEffect'] = impacteffect
end)