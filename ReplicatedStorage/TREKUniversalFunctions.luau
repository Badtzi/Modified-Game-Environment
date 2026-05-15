-- VARIABLES
local universal = {}

-- FUNCTIONS
function universal.findPlrAndChar(part)
	local plr2
	local start = part
	local current = start.Parent
	
	repeat
		if not current then return end
		if current:FindFirstChild('Humanoid') then
			plr2 = game.Players:GetPlayerFromCharacter(current)
			if not plr2 then return end
		else
			current = current.Parent
		end
	until plr2 ~= nil

	return plr2, current
end

function universal.getChildrenOfClass(inst,c)
	local res = {}
	for _,v in pairs(inst:GetChildren()) do
		if v:IsA(c) then
			table.insert(res,1,v)
		end
	end
	return res
end

function universal.new(className)
	--new "Part" {Parent = workspace, Size = Vector3.new(100, 100, 100)}
	return function(properties)
		local instance = Instance.new(className)
		for i, v in next, properties do
			instance[i] = v
		end
		return instance
	end
end

function universal.DestroyDelayed(obj,t)
	task.delay(t, function()
		if obj then obj:Destroy() end
	end)
end

-- EXECUTION
return universal