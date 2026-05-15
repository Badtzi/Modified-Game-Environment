-- VARIABLES
-- repeat wait() until shared.TREK_STATUS_INFO.Installed

-- FUNCTIONS
local function HandleVehicleAmmo(plr, mode, CurrentMode, reqmod, module)
	local chr = plr.Character
	local vehicle = chr.Humanoid.SeatPart:FindFirstAncestor('TVehicle')
	local ammo = vehicle:FindFirstChild('TAmmo')
end

local function HandleAmmo(plr, CurrentMode)
	local chr = plr.Character
	if not chr then return end

	local tool = shared.S.trekServerFuncs.returnTool(plr,chr)
	if not tool then return end
	
	local reqmod, module = shared.S.trekServerFuncs.checkForModule(tool)
	if not reqmod[CurrentMode] then return end
	
	if chr.Humanoid.SeatPart then
		if chr.Humanoid.SeatPart:IsA('VehicleSeat') and chr.Humanoid.SeatPart:FindFirstAncestor('TVehicle') then
			tool = chr.Humanoid.SeatPart:FindFirstAncestor('TVehicle')
		end
	end
	
	local mode = (reqmod[CurrentMode].useSharedClip and 1) or CurrentMode

	local ammo = tool:FindFirstChild('TAmmo')
	
	if not ammo then return end
	if not ammo:FindFirstChild(CurrentMode) then return end
	if ammo[mode].Ammo.Value <= 0 then return end

	ammo[mode].Ammo.Value -= 1
end

-- EXECUTION
game.ReplicatedStorage.TREK_SERVICES.TREK_Remotes:WaitForChild('AmmoRemote').OnServerEvent:Connect(HandleAmmo)