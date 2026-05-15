local module = {}

local SnS = game:GetService('SoundService')
local plrs = game:GetService('Players')
local LGHT = game:GetService('Lighting')
local shakeModule = require(shared.S.TREK_Modules.CameraShaker)

local CameraShakeInstance = require(shared.S.TREK_Modules.CameraShaker.CameraShakeInstance)
local camShake = shakeModule.new(Enum.RenderPriority.Camera.Value, function(shakeCf)
	workspace.CurrentCamera.CFrame = workspace.CurrentCamera.CFrame * shakeCf
end)

camShake:Start()

local tween = function(object,goal,tt,es,ed)
	return game:GetService("TweenService"):Create(object,TweenInfo.new(tt,Enum.EasingStyle[es],Enum.EasingDirection[ed],0,false,0),goal)
end

local function extraEffects(multiplier)
	local plr = plrs.LocalPlayer
	local blurClone = game.Lighting.TExplosionBlur:Clone()
	local uiClone = plr.PlayerGui:WaitForChild('GunHud'):WaitForChild('ExplosionBlind'):Clone()

	if not SnS:FindFirstChild('Tinnitus') then
		local earRinging = shared.S.TREK_EffectsStorage.Sounds.Tinnitus:Clone()
		earRinging.Parent = SnS

		earRinging.Volume = 2 * multiplier
		earRinging:Play()

		local t = tween(earRinging, {Volume = 0}, 5 * multiplier,  'Linear', 'Out')
		t:Play()

		task.delay(t.TweenInfo.Time, function()
			if earRinging then earRinging:Destroy() end
		end)
	end

	if SnS:FindFirstChild('Muffle') then
		local clone = SnS.Muffle.Concussion:Clone()
		local gaintween = tween(clone, {HighGain = 0, MidGain = 0}, 5 * multiplier, 'Exponential', 'Out')

		clone.HighGain = -50 * multiplier
		clone.MidGain = -50 * multiplier

		clone.Parent = SnS.Muffle
		clone.Enabled = true

		gaintween:Play()

		task.delay((1 * multiplier) + 1, function()
			if clone then clone:Destroy() end
		end)
	end

	uiClone.BackgroundTransparency = 1 - multiplier
	blurClone.Size = 100 * multiplier

	blurClone.Enabled = true
	blurClone.Parent = LGHT
	uiClone.Parent = plr.PlayerGui:WaitForChild('GunHud')

	tween(blurClone, {Size = 0}, 5 * multiplier, 'Exponential', 'Out'):Play()
	tween(uiClone, {BackgroundTransparency = 1}, 5 * multiplier, 'Exponential', 'Out'):Play()

	task.delay(2, function()
		if blurClone then blurClone:Destroy() end
		if uiClone then uiClone:Destroy() end
	end)
end

function module.DrawEffect(plr:Player, chr:Model, pos:Vector3, newdistance, range)
	if newdistance >= range * 2 then return end
	if newdistance >= range * 1.25 then
		if shared.S.globalConfig.explosionShakeEnabled then
			camShake:Shake(camShake.Presets.tinyExplosion)
		end
	elseif newdistance >= range * 1.05 then
		if shared.S.globalConfig.explosionShakeEnabled then
			camShake:Shake(camShake.Presets.smallExplosion)
		end
		if shared.S.globalConfig.explosionFlashingEnabled then
			extraEffects(0.15)
		end
	--[[elseif newdistance >= range then
		if shared.S.globalConfig.explosionShakeEnabled then
			camShake:Shake(camShake.Presets.mediumExplosion)
		end
		if shared.S.globalConfig.explosionFlashingEnabled then
			extraEffects(0.5)
		end]]
	elseif newdistance <= range then
		if shared.S.globalConfig.explosionShakeEnabled then
			camShake:Shake(camShake.Presets.mediumExplosion)
		end
		if shared.S.globalConfig.explosionFlashingEnabled then
			extraEffects(0.25)
		end
	end
end

return module