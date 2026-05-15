-- VARIABLES
local plr = game.Players.LocalPlayer

local tween = function(object,goal,tt,es,ed)
	return game:GetService("TweenService"):Create(object,TweenInfo.new(tt,Enum.EasingStyle[es],Enum.EasingDirection[ed],0,false,0),goal)
end

local effects = require(shared.S.TREK_Modules.EffectsModule)
local impactEffects = require(shared.S.TREK_Modules.ImpactParticlesModule)

-- FUNCTIONS
local function particles(bullet, rayInfo)	
	local particleType = rayInfo.ImpactEffect
	
	if not particleType then return end
	if not impactEffects[particleType] then return end
	
	impactEffects[particleType].DrawEffect(rayInfo.Destination, rayInfo.TargetSurface)
end

local function createBullet(rayInfo)
	local colour = rayInfo.Color or Color3.fromRGB(247, 198, 112)
	
	local type = rayInfo.ProjectileType or "Bullet"
	local bullet:Instance = shared.S.TREK_EffectsStorage.ProjectileTypes:FindFirstChild(type):Clone()

	bullet.Color = colour

	if bullet:FindFirstChildOfClass('Trail') then
		bullet:FindFirstChildOfClass('Trail').Color = ColorSequence.new(colour)
	end
	
	if bullet:FindFirstChildOfClass('Beam') then
		bullet:FindFirstChildOfClass('Beam').Color = ColorSequence.new(colour)
	end
	
	if bullet:FindFirstChild('BulletGlow') then
		bullet.BulletGlow.ImageLabel.ImageColor3 = colour
	end
	
	return bullet
end

local function destinationReached(bullet, rayInfo)
	bullet.Transparency = 1
	particles(bullet, rayInfo)

	if rayInfo.CanSuppress then effects.Suppress.DrawEffect(plr, plr.Character, bullet) end

	for i,v in pairs(bullet:GetChildren()) do
		if v:IsA('Attachment') then continue end
		if v:IsA('Trail') then continue end
		if v:IsA('Beam') then continue end

		v:Destroy()
	end

	task.delay(3, function()
		if bullet then bullet:Destroy() end
	end)
end

local function Run(player, rayInfo)
	local bullet:BasePart = createBullet(rayInfo)
	
	bullet.CFrame = CFrame.new(rayInfo.Start, rayInfo.Destination)
	
	local distance = (rayInfo.Start - rayInfo.Destination).Magnitude
	local speed = 3500
	local traveltime = distance/speed

	bullet.Parent = workspace.IgnoreList
	
	task.delay(20, function()
		if bullet then bullet:Destroy() end
	end)

	spawn(function()
		local tween = tween(bullet, {Position = rayInfo.Destination}, traveltime, "Linear", "Out")
		tween:Play()

		local IsBulletGlow = false

		if bullet:FindFirstChild('BulletGlow') then
			IsBulletGlow = true
			bullet.BulletGlow.Enabled = true
			bullet.Transparency = 0
		end

		tween.Completed:Connect(function() destinationReached(bullet, rayInfo) end)
	end)
end

-- EXECUTION
return Run
