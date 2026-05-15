local module = {}

function module.DrawEffect(position)
	local theparticles = script.Particle:Clone()
	theparticles.Position = position
	theparticles.Parent = workspace:WaitForChild('IgnoreList')

	theparticles:FindFirstChildOfClass('Sound'):Play()

	for i,v in pairs(theparticles:GetChildren()) do
		if not v:IsA("ParticleEmitter") then continue end
		v:Emit((v:FindFirstChild('EmitSize') and v.EmitSize.Value))
	end

	task.delay(10, function()
		if theparticles then theparticles:Destroy() end
	end)
end

return module
