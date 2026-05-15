-- VARIABLES
shared.S = {}

do
	for i,service in pairs(game.ReplicatedStorage:WaitForChild('TREK_SERVICES'):GetChildren()) do
		shared.S[service.Name] = service
	end

	shared.S['globalConfig'] = require(shared.S.TREK_Globals.GlobalConfigs)
	shared.S['trekFuncs'] = require(shared.S.TREK_Modules.TREKUniversalFunctions)
	shared.S['trekServerFuncs'] = require(game.ServerStorage.TREKServerFunctions)
	shared.S['trekGibs'] = require(game.ServerStorage.TREKGibsModule)
end

local lbmodule = require(shared.S.TREK_Modules.LeaderBoardModule)
local expmod = require(game.ServerStorage.TREKExplosionModule)
local PService = game:GetService("PhysicsService")

-- Create melee remotes if they don't exist
local function createMeleeRemotes()
	local remotes = shared.S.TREK_Remotes

	local meleeRemoteNames = {'MeleeDamage', 'TakedownRequest', 'TakedownSync', 'TakedownCancel', 'MeleeGFX', 'ReplicateAim'}
	for _, name in ipairs(meleeRemoteNames) do
		if not remotes:FindFirstChild(name) then
			local remote = Instance.new('RemoteEvent')
			remote.Name = name
			remote.Parent = remotes
		end
	end
end

-- FUNCTIONS
local function createMotor(chr)
	local M6D = Instance.new("Motor6D")
	M6D.Name = "toolAnim"

	if chr.Humanoid.RigType == Enum.HumanoidRigType.R6 then
		M6D.Parent = chr.Torso
	end
	if chr.Humanoid.RigType == Enum.HumanoidRigType.R15 then
		M6D.Parent = chr:WaitForChild('UpperTorso')
	end
end

local function updateMotor(chr, tool)
	if not tool:FindFirstChild('AnimPart') then return end	

	if chr.Humanoid.RigType == Enum.HumanoidRigType.R6 then
		if not chr:FindFirstChild('Torso') then return end
		if not chr.Torso:FindFirstChild('toolAnim') then return end

		chr.Torso.toolAnim.Part0 = chr.Torso
		chr.Torso.toolAnim.Part1 = tool.AnimPart
	elseif chr.Humanoid.RigType == Enum.HumanoidRigType.R15 then
		if not chr:FindFirstChild('UpperTorso') then return end
		if not chr.UpperTorso:FindFirstChild('toolAnim') then return end

		chr.UpperTorso.toolAnim.Part0 = chr.UpperTorso
		chr.UpperTorso.toolAnim.Part1 = tool.AnimPart
	end
end

local function updateMeleeMotor(chr, tool)
	if not tool:FindFirstChild('AnimPart') then return end

	local motorParent

	if chr.Humanoid.RigType == Enum.HumanoidRigType.R6 then
		motorParent = chr:FindFirstChild('Right Arm')
	elseif chr.Humanoid.RigType == Enum.HumanoidRigType.R15 then
		motorParent = chr:FindFirstChild('RightHand')
	end

	if not motorParent then return end

	-- Create or reuse the melee Motor6D on the right hand
	local motor = motorParent:FindFirstChild('meleeToolAnim')
	if not motor then
		motor = Instance.new('Motor6D')
		motor.Name = 'meleeToolAnim'
		motor.Parent = motorParent
	end

	motor.Part0 = motorParent
	motor.Part1 = tool.AnimPart
end

local function createAmmoStore(tool)
	local reqmod, mod = shared.S.trekServerFuncs.checkForModule(tool)
	if not reqmod then return end

	local f = Instance.new('Folder')
	f.Parent = tool
	f.Name = 'TAmmo'

	for name, config in pairs(reqmod) do
		if not config then continue end
		if not (typeof(config) == 'table') then continue end
		if not config['MagCapacity'] then continue end

		local w = Instance.new('Folder')
		w.Parent = f
		w.Name = name

		local v1,v2 = Instance.new('DoubleConstrainedValue'),Instance.new('DoubleConstrainedValue')
		v1.Parent = w
		v1.Name = 'Ammo'
		v1.MaxValue = config.MagCapacity
		v1.MinValue = 0
		v1.Value = config.MagCapacity

		v2.Parent = w
		v2.Name = 'Stored'
		v2.MaxValue = (config.ReservedAmmo == 'INF' and math.huge) or config.ReservedAmmo
		v2.MinValue = 0
		v2.Value = (config.ReservedAmmo == 'INF' and math.huge) or config.ReservedAmmo
	end
end

local function createCollGroups(config)	
	PService:RegisterCollisionGroup('TMouseCollGroup')

	for groupName, groupsToIgnore in pairs(shared.S.globalConfig.collisionGroupConfigs) do
		if PService:IsCollisionGroupRegistered(groupName) then continue end

		PService:RegisterCollisionGroup(groupName)
	end
end

local function configureCollisionGroups()
	if not shared.S.globalConfig['collisionGroupConfigs'] then warn('NO COLLISION GROUPS CONFIGU!') return end

	createCollGroups()

	for groupName, groupsToIgnore in pairs(shared.S.globalConfig.collisionGroupConfigs) do
		for groupFromList, collisionStatus in pairs(groupsToIgnore) do
			if not PService:IsCollisionGroupRegistered(groupFromList) then continue end
			PService:CollisionGroupSetCollidable(groupName, groupFromList, collisionStatus)
		end
	end

	local groups = PService:GetRegisteredCollisionGroups()
end

local function checkForGun(child)
	local chr = child.Parent

	-- Check GunConfigs first
	local module
	if child:GetAttribute('TConfigToUse') then
		module = shared.S.GunConfigs:FindFirstChild(child:GetAttribute('TConfigToUse'), true)
	else
		module = shared.S.GunConfigs:FindFirstChild(child.Name, true)
	end

	if module then
		if child:FindFirstChild('AnimPart') then updateMotor(chr,child) end

		local reqmod, module = shared.S.trekServerFuncs.checkForModule(child)
		if not reqmod then return end

		if not child:FindFirstChild(reqmod.ToolType) then
			local thehandler = game.ServerStorage:WaitForChild('TREKToolHandlers'):FindFirstChild(reqmod.ToolType)
			if not thehandler then return end

			thehandler:Clone().Parent = child
		end

		if not child:FindFirstChild('TAmmo') then createAmmoStore(child) end
		return
	end

	-- Check MeleeConfigs if not found in GunConfigs
	if shared.S.MeleeConfigs then
		local meleeModule
		if child:GetAttribute('TConfigToUse') then
			meleeModule = shared.S.MeleeConfigs:FindFirstChild(child:GetAttribute('TConfigToUse'), true)
		else
			meleeModule = shared.S.MeleeConfigs:FindFirstChild(child.Name, true)
		end

		if meleeModule then
			-- Server welds melee AnimPart to right hand (not torso)
			if child:FindFirstChild('AnimPart') then updateMeleeMotor(chr, child) end

			local reqmod, mod = shared.S.trekServerFuncs.checkForMeleeModule(child)
			if not reqmod then return end

			if not child:FindFirstChild(reqmod.ToolType) then
				local thehandler = game.ServerStorage:WaitForChild('TREKToolHandlers'):FindFirstChild(reqmod.ToolType)
				if not thehandler then return end

				thehandler:Clone().Parent = child
			end
		end
	end

	-- Check ExplosiveConfigs
	if shared.S.ExplosiveConfigs then
		local explosiveModule
		if child:GetAttribute('TConfigToUse') then
			explosiveModule = shared.S.ExplosiveConfigs:FindFirstChild(child:GetAttribute('TConfigToUse'), true)
		else
			explosiveModule = shared.S.ExplosiveConfigs:FindFirstChild(child.Name, true)
		end

		if explosiveModule then
			if child:FindFirstChild('AnimPart') then updateMotor(chr, child) end

			local reqmod, mod = shared.S.trekServerFuncs.checkForExplosiveModule(child)
			if not reqmod then return end

			if not child:FindFirstChild(reqmod.ToolType) then
				local thehandler = game.ServerStorage:WaitForChild('TREKToolHandlers'):FindFirstChild(reqmod.ToolType)
				if not thehandler then return end

				thehandler:Clone().Parent = child
			end
		end
	end
end

local function unWeldGun(child,chr)	
	if chr.Humanoid.RigType == Enum.HumanoidRigType.R6 then
		if not chr:FindFirstChild('Torso') then return end

		if child:FindFirstChild('Gun') or child:FindFirstChild('Explosive') then
			if not chr.Torso:FindFirstChild('toolAnim') then return end
			if not child:FindFirstChild('AnimPart') then return end
			chr.Torso.toolAnim.Part1 = nil
		end

		if child:FindFirstChild('Melee') then
			local rightArm = chr:FindFirstChild('Right Arm')
			if rightArm and rightArm:FindFirstChild('meleeToolAnim') then
				rightArm.meleeToolAnim.Part1 = nil
			end
		end
	elseif chr.Humanoid.RigType == Enum.HumanoidRigType.R15 then
		if not chr:FindFirstChild('UpperTorso') then return end

		if child:FindFirstChild('Gun') or child:FindFirstChild('Explosive') then
			if not chr.UpperTorso:FindFirstChild('toolAnim') then return end
			if not child:FindFirstChild('AnimPart') then return end
			chr.UpperTorso.toolAnim.Part1 = nil
		end

		if child:FindFirstChild('Melee') then
			local rightHand = chr:FindFirstChild('RightHand')
			if rightHand and rightHand:FindFirstChild('meleeToolAnim') then
				rightHand.meleeToolAnim.Part1 = nil
			end
		end
	end

end

local function handleExplosion(plr,pos,currentMode)
	local chr = plr.Character
	if not chr then return end

	local tool = shared.S.trekServerFuncs.returnTool(plr,chr)
	if not tool then return end

	if not shared.S.GunConfigs:FindFirstChild(tool.Name, true) then return end

	local module = shared.S.GunConfigs:FindFirstChild(tool.Name, true)
	local reqmod = shared.S.trekServerFuncs.checkForModule(tool)

	if not module then return end
	if not reqmod[currentMode] then return end
	local config = reqmod[currentMode]

	if not config.explosiveRays then return end

	expmod.handleExplosion(plr,module,config,pos)
end

local function handleGFX(plr,type,currentMode,source)
	local chr = plr.Character
	if not chr then return end

	local tool = shared.S.trekServerFuncs.returnTool(plr,chr)
	if not tool then return end

	-- Use checkForAnyModule to support both gun and melee tools
	local reqmod, module = shared.S.trekServerFuncs.checkForAnyModule(tool)
	if not reqmod then return end

	shared.S.TREK_Remotes:WaitForChild('GFX'):FireAllClients(type, tool, module, reqmod, currentMode, plr, source)
end

local function handleReload(plr,currentMode)
	local chr = plr.Character
	if not chr then return end

	local tool = shared.S.trekServerFuncs.returnTool(plr,chr)
	if not tool then return end

	local reqmod,module = shared.S.trekServerFuncs.checkForModule(tool)

	if not module then return end
	if not reqmod[currentMode] then return end
	local config = reqmod[currentMode]

	local mode = (reqmod[currentMode].useSharedClip and 1) or currentMode

	local ammo = tool:FindFirstChild('TAmmo')
	if not ammo then return end
	if not ammo:FindFirstChild(mode) then return end

	local stored = ammo[mode].Stored
	local loaded =  ammo[mode].Ammo

	if config.ReservedAmmo == 'INF' then loaded.Value = config.MagCapacity return end

	local difference = (config.MagCapacity - loaded.Value)
	local possible = (difference > stored.Value) and stored.Value or difference

	stored.Value -= possible
	loaded.Value += possible
end

local function chrAdded(chr,plr:Player)
	createMotor(chr)

	chr.ChildAdded:Connect(checkForGun)
	chr.ChildRemoved:Connect(function(child) unWeldGun(child,chr) end)

	repeat wait() until chr:FindFirstChild('Humanoid')

	chr.Humanoid.Died:Connect(function() lbmodule.plrDeath(chr,plr) end)

	plr.CharacterAppearanceLoaded:Connect(function()
		for i, acc:Accessory in pairs(plr.Character:GetChildren()) do
			if not acc:IsA('Accessory') then continue end
			if not acc:WaitForChild('Handle',10) then continue end

			local p = acc:WaitForChild('Handle',10)
			if not p then continue end

			p.CanCollide = false
			p.CanQuery = false
		end

	end)
end

local function plrAdded(plr)
	lbmodule.createStats(plr)

	if plr.Character then
		chrAdded(plr.Character, plr)
	end

	plr.CharacterAdded:Connect(function(chr) chrAdded(chr,plr) end)
end

local function plrLeaving(plr)
	if plr:FindFirstChild('leaderstats') then
		local f = plr.leaderstats:Clone()
		f.Parent = game.ServerStorage
		f.Name = plr.Name.."Stats"
	end
end

-- EXECUTION
configureCollisionGroups()
shared.S.trekServerFuncs:SetUpGuns()
shared.S.trekServerFuncs:SetUpMelee()
shared.S.trekServerFuncs:SetUpExplosives()
createMeleeRemotes()

game.Players.PlayerAdded:Connect(plrAdded)

-- Load existing players
for _, plr in game.Players:GetPlayers() do
	plrAdded(plr)
end

game.Players.PlayerRemoving:Connect(plrLeaving)
shared.S.TREK_Remotes:WaitForChild('Explosion').OnServerEvent:Connect(handleExplosion)
shared.S.TREK_Remotes:WaitForChild('GFX').OnServerEvent:Connect(handleGFX)
shared.S.TREK_Remotes:WaitForChild('Reload').OnServerEvent:Connect(handleReload)

-- Aim pitch replication (viewmodel sends camera pitch, server stores as attribute for other clients)
local replicateAim = shared.S.TREK_Remotes:FindFirstChild('ReplicateAim')
if replicateAim then
	replicateAim.OnServerEvent:Connect(function(plr, pitch)
		if type(pitch) == "number" and plr.Character then
			pitch = math.clamp(pitch, -1.5, 1.5)
			plr.Character:SetAttribute("AimPitch", pitch)
		end
	end)
end
