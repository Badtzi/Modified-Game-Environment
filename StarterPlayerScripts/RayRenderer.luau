repeat wait() until game.Players.LocalPlayer.Character

-- VARIABLES
local plr = game.Players.LocalPlayer
local raysPath = shared.S.TREK_Modules:WaitForChild('RayTypes')

local modules = {}

for i,module in pairs(raysPath:GetChildren()) do
	modules[module.Name] = require(module)
end

-- FUNCTIONS
local function handleRaysRemote(player, rayInfo)
	if plr == player then return end
	
	if modules[rayInfo.RayType] then
		local func = modules[rayInfo.RayType]
		func(player, rayInfo)
	end
end

local function handleRaysBind(rayInfo)
	if modules[rayInfo.RayType] then
		local func = modules[rayInfo.RayType]
		func(plr, rayInfo)
	end
end

--[[
function(player, pos, mat, currentMode, RayType, origin)
	local char = player.Character
	local pass, tool, module = security(char)
	
	if plr == player then return end
	if not pass then return end
	
	if modules[RayType] then
		local func = modules[RayType]
		func(player,pos,module,char,mat,currentMode,origin)
	end
]]

-- EXECUTION
shared.S.TREK_Remotes.RayRemote.OnClientEvent:Connect(handleRaysRemote)
shared.S.TREK_Remotes.RayBind.Event:Connect(handleRaysBind)
