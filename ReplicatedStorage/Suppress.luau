local module = {}

local shakeModule = require(shared.S.TREK_Modules.CameraShaker)
local CameraShakeInstance = require(shared.S.TREK_Modules.CameraShaker.CameraShakeInstance)
local camShake = shakeModule.new(Enum.RenderPriority.Camera.Value, function(shakeCf)
	workspace.CurrentCamera.CFrame = workspace.CurrentCamera.CFrame * shakeCf
end)
camShake:Start()
local maxrange = 24

local tween = function(object,goal,tt,es,ed)
	return game:GetService("TweenService"):Create(object,TweenInfo.new(tt,Enum.EasingStyle[es],Enum.EasingDirection[ed],0,false,0),goal)
end

function module.DrawEffect(plr,chr,source,extra)
	if not chr then return end
	if not chr:FindFirstChild('HumanoidRootPart') then return end

	local distance = (chr.HumanoidRootPart.Position - source.Position).Magnitude
	if distance > maxrange then return end

	-- Voice: player is being suppressed
	pcall(function()
		local voiceRemote = shared.S.TREK_Remotes:FindFirstChild("VoicePlayRequest")
		if voiceRemote then
			voiceRemote:FireServer("Suppressed")
		end
	end)

	local linear = 1 - distance / maxrange
	local interpolation = linear^2
	--math.pow(2, 10 * linear - 10) --Exponential

	local hud = plr.PlayerGui:WaitForChild('GunHud')
	local vign = hud:WaitForChild('Tense'):FindFirstChild('Tense'):Clone()
	vign.Parent = hud.Tense
	vign.ImageTransparency = 1 - linear / 1.5
	tween(vign,{ImageTransparency = 1},interpolation,'Linear','Out'):Play()

	local cracks = shared.S.TREK_EffectsStorage.Sounds.BulletCracks:GetChildren()
	local sound = cracks[math.random(1,#cracks)]:Clone()
	sound.Parent = source
	sound:Play()

	--t1:Play()
	--t1.Completed:Connect(function()
	--t2:Play()
	--end)

	if extra then
		local c = CameraShakeInstance.new(interpolation * 2.5, 4, 0.1, 0.2 * (1 + interpolation))
		c.PositionInfluence = Vector3.new(0.15, 0.15, 0.15)
		c.RotationInfluence = Vector3.new(1, 1, 1)
		camShake:Shake(c)
	end
end

return module