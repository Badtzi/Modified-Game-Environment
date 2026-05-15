local module = {}

local tween = function(object,goal,tt,es,ed)
	return game:GetService("TweenService"):Create(object,TweenInfo.new(tt,Enum.EasingStyle[es],Enum.EasingDirection[ed],0,false,0),goal)
end

local universalFuncs = require(shared.S.TREK_Modules:WaitForChild('TREKUniversalFunctions'))

function module.DrawEffect(plr, type)
	local hud = plr.PlayerGui:WaitForChild('GunHud')
	local marker,box = hud.Hitmarker.Marker:Clone(), hud.Hitmarker.Box:Clone()
	
	if type then
		if type == 'armr' then
			box.UIStroke.Color = Color3.fromRGB(21, 0, 255)
		elseif type == 'plr' then
			box.UIStroke.Color = Color3.fromRGB(255, 32, 32)
		end
	end
	
	marker.Parent = hud.Hitmarker
	box.Parent = hud.Hitmarker

	marker.Visible = true
	box.Visible = true

	tween(box,{Size = UDim2.new(0,80,0,80)},0.25,"Cubic","Out"):Play()
	tween(box.UIStroke,{Transparency = 1},0.25,"Linear","Out"):Play()
	tween(marker,{Size = UDim2.new(0,50,0,50)},0.2,"Quint","Out"):Play()
	tween(marker,{ImageTransparency = 1},0.2,"Linear","Out"):Play()

	universalFuncs.DestroyDelayed(box,0.5)
	universalFuncs.DestroyDelayed(marker,0.5)
end

return module