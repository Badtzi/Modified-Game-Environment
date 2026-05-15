-- VARIABLES
-- repeat wait() until shared.TREK_STATUS_INFO.Installed

-- FUNCTIONS
local function render(plr, name, pos, dir, vel, behavior, currentMode)
	local chr = plr.Character
	if not chr then return end
	
	local tool = shared.S.trekServerFuncs.returnTool(plr,chr)
	if not tool then return end

	local reqmod, module = shared.S.trekServerFuncs.checkForModule(tool)
	if not reqmod then return end
	
	local type = reqmod[currentMode].ImpactEffect
			
	shared.S.TREK_Remotes:WaitForChild('ProjectileRemote'):FireAllClients(plr,name,pos, dir, vel, behavior, reqmod[currentMode].CanSuppress, reqmod[currentMode].ExtraSuppression, type)
end

-- EXECUTION
game.ReplicatedStorage.TREK_SERVICES.TREK_Remotes:WaitForChild('ProjectileRemote').OnServerEvent:Connect(render)