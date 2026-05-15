local module = {}

function module.DrawEffect(position, mat)
	local theparticles = script.Particle:Clone()
	theparticles.Position = position
	theparticles.Parent = workspace:WaitForChild('IgnoreList')

	local random = math.random(1,2)
	theparticles:FindFirstChild('impact'..tostring(random)):Play()

	for i,v in pairs(theparticles:GetChildren()) do
		if not v:IsA("ParticleEmitter") then continue end
		if mat then v.Color = ColorSequence.new(mat) end

		v:Emit((v:FindFirstChild('EmitSize') and v.EmitSize.Value))
	end
	
	task.delay(10, function()
		if theparticles then theparticles:Destroy() end
	end)
end

return module
