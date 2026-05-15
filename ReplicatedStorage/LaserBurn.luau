local module = {}

local ball = Instance.new('Part')
ball.Shape = Enum.PartType.Ball
ball.Material = Enum.Material.Neon
ball.Size = Vector3.new(0.2, 0.2, 0.2)
ball.Anchored = true
ball.CanCollide = false
ball.CanQuery = false

local tween = function(object,goal,tt,es,ed)
	return game:GetService("TweenService"):Create(object,TweenInfo.new(tt,Enum.EasingStyle[es],Enum.EasingDirection[ed],0,false,0),goal)
end

function module.DrawEffect(position)
	spawn(function()
		local h = ball:Clone()

		h.Color = Color3.fromRGB(206, 111, 55)
		h.Position = position
		h.Parent = workspace.IgnoreList

		shared.S.trekFuncs.DestroyDelayed(h,3)

		wait(0.5)
		tween(h,{Color = Color3.fromRGB(0,0,0)},0.5,'Sine','Out'):Play()
		wait(1.5)
		tween(h,{Transparency = 1},0.5,'Sine','Out'):Play()
	end)
end

return module
