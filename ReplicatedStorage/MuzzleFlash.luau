local module = {}

function module.DrawEffect(barrel)
	if not barrel then warn('No Bareel!') return end
	--if not barrel:FindFirstChild('Flash') then warn('No Flash!') return end
	--if not barrel.Flash:IsA('ParticleEmitter') then warn('Flash isn\'t a particle emitter!') return end
	
	for i,v in pairs(barrel:GetDescendants()) do
		if not v:IsA('ParticleEmitter') then continue end
		
		local amount = 1
		if v:FindFirstChild('Amount') then
			amount = v.Amount.Value
		elseif v:FindFirstChild('EmitSize') then
			amount = v.EmitSize.Value
		end
		
		v:Emit(amount)
	end
	
	local light = barrel:FindFirstChildWhichIsA("PointLight")
	if light ~= nil then
		light.Enabled = true
		task.delay(0.1,function()
			if light then light.Enabled = false end
		end)
	end
	
end

return module