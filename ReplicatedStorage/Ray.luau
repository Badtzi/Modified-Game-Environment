-- VARIABLES
local plr = game.Players.LocalPlayer

local tween = function(object,goal,tt,es,ed)
	return game:GetService("TweenService"):Create(object,TweenInfo.new(tt,Enum.EasingStyle[es],Enum.EasingDirection[ed],0,false,0),goal)
end

local at1 = Instance.new('Attachment')
local at2 = Instance.new('Attachment')

local beam = Instance.new('Beam')

do
	beam.Width0 = 0.25
	beam.Width1 = 0.25
	beam.FaceCamera = true
	beam.Brightness = 1
	beam.LightInfluence = 0
	beam.LightEmission = 1
	beam.Attachment0 = at1
	beam.Attachment1 = at2
	beam.Transparency = NumberSequence.new(0.3)
	beam.Parent = at1
end

local effects = require(shared.S.TREK_Modules.EffectsModule)
local impactEffects = require(shared.S.TREK_Modules.ImpactParticlesModule)

-- FUNCTIONS
local function particles(rayInfo)	
	local particleType = rayInfo.ImpactEffect

	if not particleType then return end
	if not impactEffects[particleType] then return end

	impactEffects[particleType].DrawEffect(rayInfo.Destination)
end

local function Run(player, rayInfo)
	local colour = rayInfo.Color or Color3.fromRGB(255, 0, 0)

	local c1, c2 = at1:Clone(), at2:Clone()

	c1.WorldPosition = rayInfo.Start
	c2.WorldPosition = rayInfo.Destination

	c1.Beam.Attachment0 = c1
	c1.Beam.Attachment1 = c2
	c1.Beam.Color = ColorSequence.new(colour)

	c1.Parent = workspace.Terrain
	c2.Parent = workspace.Terrain

	particles(rayInfo)

	shared.S.trekFuncs.DestroyDelayed(c1, 0.04)
	shared.S.trekFuncs.DestroyDelayed(c2, 0.04)
end

-- EXECUTION
return Run