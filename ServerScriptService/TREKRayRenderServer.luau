-- VARIABLES
-- repeat wait() until shared.TREK_STATUS_INFO.Installed

-- FUNCTIONS
local function createRayInfoTable(start, dest, TargetSurface, config)
	local rayInfo = {}
	local customInfo = config.CustomRayInfo
	
	rayInfo.Start = start
	rayInfo.Destination = dest
	rayInfo.Color = config.CustomRayColour
	rayInfo.ProjectileType = config.ProjectileName
	rayInfo.CanSuppress = config.CanSuppress
	rayInfo.ImpactEffect = config.ImpactEffect
	rayInfo.TargetSurface = TargetSurface
	rayInfo.RayType = config.RayType
	rayInfo.Distance = config.Distance
	
	if customInfo then
		for name, value in pairs(customInfo) do
			rayInfo[name] = value
		end
	end
		
	return rayInfo
end

local function HandleRays(plr, OriginPos, HitPos, TargetSurface, CurrentMode)
	local chr = plr.Character
	if not chr then return end
	
	local tool = shared.S.trekServerFuncs.returnTool(plr,chr)
	if not tool then return end
	
	local reqmod, module = shared.S.trekServerFuncs.checkForModule(tool)
	if not reqmod[CurrentMode] then return end
	
	local rayInfo = createRayInfoTable( OriginPos, HitPos, TargetSurface, reqmod[CurrentMode])
	shared.S.TREK_Remotes:WaitForChild('RayRemote'):FireAllClients(plr, rayInfo)
end

-- EXECUTION
game.ReplicatedStorage.TREK_SERVICES.TREK_Remotes:WaitForChild('RayRemote').OnServerEvent:Connect(HandleRays)