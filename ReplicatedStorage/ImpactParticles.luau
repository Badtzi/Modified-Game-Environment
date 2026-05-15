local module = {}

function module.DrawEffect(theparticles,mat)
	theparticles.impact:Play()
	theparticles.impact2:Play()

	for i,v in pairs(theparticles:GetChildren()) do
		if not v:IsA("ParticleEmitter") then continue end
		
		if mat then v.Color = ColorSequence.new(mat) end
		v:Emit(math.random(1,15))
	end

	--[[
	theparticles.Artifact:Emit(15)
	theparticles.Dust:Emit(3)
	theparticles.AltDust:Emit(9)
	theparticles.Flash:Emit(1)
	theparticles.BigFlash:Emit(1)
	]]
end

return module
