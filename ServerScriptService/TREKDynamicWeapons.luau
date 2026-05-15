local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")

repeat task.wait() until shared.S

local TREK_Remotes = shared.S.TREK_Remotes

local DestroyedRemote = TREK_Remotes:FindFirstChild("DynamicWeaponDestroyed")
if not DestroyedRemote then
	DestroyedRemote = Instance.new("RemoteEvent")
	DestroyedRemote.Name = "DynamicWeaponDestroyed"
	DestroyedRemote.Parent = TREK_Remotes
end

local DestructionFXRemote = TREK_Remotes:FindFirstChild("DestructionFX")
if not DestructionFXRemote then
	DestructionFXRemote = Instance.new("RemoteEvent")
	DestructionFXRemote.Name = "DestructionFX"
	DestructionFXRemote.Parent = TREK_Remotes
end


local explosionModule = nil
pcall(function()
	explosionModule = require(ServerStorage:WaitForChild("TREKExplosionModule", 5))
end)


local function findDestructibleParts(parent: Instance): { BasePart }
	local parts = {}
	for _, desc in ipairs(parent:GetDescendants()) do
		if desc:IsA("BasePart") and desc:FindFirstChild("THealth") then
			table.insert(parts, desc)
		end
	end
	return parts
end

local function setTeam(part: BasePart, player: Player)
	local teamVal = part:FindFirstChild("Team")
	if not teamVal then
		teamVal = Instance.new("ObjectValue")
		teamVal.Name = "Team"
		teamVal.Parent = part
	end
	teamVal.Value = player.Team
end

-- Get CFrame from either a BasePart or Model (uses PrimaryPart or GetPivot)
local function getCFrame(instance: Instance): CFrame
	if instance:IsA("BasePart") then
		return instance.CFrame
	elseif instance:IsA("Model") then
		if instance.PrimaryPart then
			return instance.PrimaryPart.CFrame
		end
		return instance:GetPivot()
	end
	return CFrame.new()
end

local function emitDestructionEffects(sourcePart: Instance)
	if not sourcePart then return end
	local effectPart = sourcePart:FindFirstChild("DESTRUCTIONEFFECT")
	if not effectPart or not effectPart:IsA("BasePart") then return end

	local clone = effectPart:Clone()
	clone.Anchored = true
	clone.CanCollide = false
	clone.CanQuery = false
	clone.Transparency = 1
	clone.CFrame = effectPart.CFrame
	clone.Parent = workspace:FindFirstChild("IgnoreList") or workspace

	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("ParticleEmitter") then
			desc.Enabled = true
			desc:Emit(desc:GetAttribute("EmitCount") or math.random(15, 50))
		elseif desc:IsA("Sound") then
			desc:Play()
		end
	end

	Debris:AddItem(clone, 10)
end

local function playDestructionSounds(sourcePart: Instance)
	if not sourcePart then return end
	for _, child in ipairs(sourcePart:GetChildren()) do
		if child:IsA("Sound") and child.Name:match("^[Dd]estruct") then
			local s = child:Clone()
			s.Parent = workspace:FindFirstChild("IgnoreList") or workspace
			s:Play()
			Debris:AddItem(s, s.TimeLength + 1)
		end
	end
end

local function handleRemove(targetModel: Instance, thealthPart: BasePart)
	if targetModel and targetModel.Parent then targetModel:Destroy() end
	if targetModel ~= thealthPart and thealthPart and thealthPart.Parent then thealthPart:Destroy() end
end

local function handleGib(searchRoot: Instance, targetModel: Instance, thealthPart: BasePart, attacker: Player?)
	local gibFolder = searchRoot:FindFirstChild("DestructionGibs")
	local gibClone = nil

	if gibFolder then
		local baseName = targetModel and targetModel.Name or thealthPart.Name
		local possibleGibs = {}
		for _, obj in pairs(gibFolder:GetChildren()) do
			if obj:IsA("Model") or obj:IsA("BasePart") then
				if obj.Name == baseName or obj.Name:match("^" .. baseName .. "%d+$") then
					table.insert(possibleGibs, obj)
				end
			end
		end
		if #possibleGibs > 0 then
			gibClone = possibleGibs[math.random(1, #possibleGibs)]:Clone()
		end
	end

	if gibClone then
		if gibClone:IsA("BasePart") then
			gibClone.Anchored = false
			gibClone.CanCollide = true
			gibClone.CFrame = getCFrame(targetModel or thealthPart)
		elseif gibClone:IsA("Model") then
			gibClone:PivotTo(getCFrame(targetModel or thealthPart))
		end

		gibClone.Parent = workspace:FindFirstChild("IgnoreList") or workspace

		-- Emit DESTRUCTIONEFFECT on gib
		local gibEffect = gibClone:FindFirstChild("DESTRUCTIONEFFECT", true)
		if gibEffect and gibEffect:IsA("BasePart") then
			for _, emitter in ipairs(gibEffect:GetDescendants()) do
				if emitter:IsA("ParticleEmitter") then
					emitter:Emit(emitter:GetAttribute("EmitCount") or math.random(15, 50))
				end
			end
		end

		for _, child in ipairs(gibClone:GetChildren()) do
			if child:IsA("Sound") then child:Play() end
		end

		if attacker and attacker.Character and gibClone:IsA("BasePart") then
			local source = attacker.Character:FindFirstChild("HumanoidRootPart")
			if source then
				pcall(function()
					gibClone:ApplyImpulse((gibClone.Position - source.Position).Unit * 30)
				end)
			end
		end

		Debris:AddItem(gibClone, 30)
	end

	handleRemove(targetModel, thealthPart)
end

local function handleHide(targetModel: Instance, thealthPart: BasePart)
	local function hidepart(p)
		if p:IsA("BasePart") then
			p.Transparency = 1; p.CanCollide = false; p.CanQuery = false
		end
	end
	if targetModel then
		if targetModel:IsA("BasePart") then hidepart(targetModel)
		elseif targetModel:IsA("Model") then
			for _, p in ipairs(targetModel:GetDescendants()) do hidepart(p) end
		end
	end
	if thealthPart and thealthPart.Parent then hidepart(thealthPart) end
end

local function handleDetach(targetModel: Instance, thealthPart: BasePart, attacker: Player?)
	if not targetModel or not targetModel:IsA("BasePart") then
		handleRemove(targetModel, thealthPart); return
	end
	for _, child in ipairs(targetModel:GetDescendants()) do
		if child:IsA("JointInstance") or child:IsA("WeldConstraint") then child:Destroy() end
	end
	targetModel.CanCollide = true
	targetModel.Parent = workspace:FindFirstChild("IgnoreList") or workspace
	if attacker and attacker.Character then
		local source = attacker.Character:FindFirstChild("HumanoidRootPart")
		if source then
			pcall(function()
				targetModel:ApplyImpulse((targetModel.Position - source.Position).Unit * 20)
				targetModel:ApplyAngularImpulse(Vector3.new(math.random(-5,5), math.random(-5,5), math.random(-5,5)))
			end)
		end
	end
	Debris:AddItem(targetModel, 30)
	if thealthPart and thealthPart.Parent and thealthPart ~= targetModel then thealthPart:Destroy() end
end

local function onPartDestroyed(player: Player, character: Model, tool: Tool?, searchRoot: Instance, thealthPart: BasePart, attacker: Player?)
	if thealthPart:GetAttribute("_destroyed") then return end
	thealthPart:SetAttribute("_destroyed", true)

	local destroyBehavior = thealthPart:GetAttribute("DestroyBehavior") or "Remove"
	local destroyModelName = thealthPart:GetAttribute("DestroyModel")
	local killOwner = thealthPart:GetAttribute("KillOwnerOnDestroy") or false
	local killAnimation = thealthPart:GetAttribute("KillAnimation")
	local killAnimDuration = thealthPart:GetAttribute("KillAnimationDuration") or 2
	local explode = thealthPart:GetAttribute("ExplosionOnDestroy") or false
	local explosionRadius = thealthPart:GetAttribute("ExplosionRadius") or 16
	local explosionDamage = thealthPart:GetAttribute("ExplosionDamage") or 100
	local explosionName = thealthPart:GetAttribute("ExplosionName") or "Explosion"
	local incendiary = thealthPart:GetAttribute("Incendiary") or false
	local explosionTeamKill = thealthPart:GetAttribute("ExplosionTeamKill")
	if explosionTeamKill == nil then explosionTeamKill = true end -- default: affects everyone
	local disableTool = thealthPart:GetAttribute("DisableToolOnDestroy") or false
	local destructionAnimation = thealthPart:GetAttribute("DestructionAnimation")

	-- Resolve the visible model to act on (search the backpack model or tool)
	local targetModel = thealthPart
	if destroyModelName then
		targetModel = searchRoot:FindFirstChild(destroyModelName, true) or thealthPart
	end

	local humanoid = character:FindFirstChild("Humanoid")

	if killOwner and humanoid then
		-- Voice: backpack ignited (fuel tank explosion)
		pcall(function()
			if shared.VoicePlay then
				shared.VoicePlay(player, "BackpackIgnited")
			end
		end)

		-- Unequip tools and block re-equip
		humanoid:UnequipTools()
		character:SetAttribute("TakedownActive", true)

		-- Protect from external damage during death sequence
		local ff = Instance.new("ForceField")
		ff.Name = "DestructionForceField"
		ff.Visible = false
		ff.Parent = character

		-- Lock movement but allow gravity so player falls to ground if mid-air
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false

		-- Disable tool
		if disableTool and tool then
			tool:SetAttribute("DynamicDisabled", true)
		end
	elseif disableTool and tool then
		tool:SetAttribute("DynamicDisabled", true)
	end

	local toolName = tool and tool.Name or searchRoot:GetAttribute("_linkedToolName") or ""
	DestroyedRemote:FireClient(player, {
		ToolName = toolName,
		PartName = thealthPart.Name,
		DestroyBehavior = destroyBehavior,
		DestroyModelName = destroyModelName,
		KillOwner = killOwner,
		KillAnimation = killAnimation,
		KillAnimDuration = killAnimDuration,
		DisableTool = disableTool,
		DestructionAnimation = destructionAnimation,
	})

	task.wait(0.05) -- Let client receive remote

	local activeDestructionEffect = nil

	-- Find DESTRUCTIONEFFECT in searchRoot (the BackpackModel on the character)
	local effectPart = searchRoot and searchRoot:FindFirstChild("DESTRUCTIONEFFECT", true)
	if effectPart and effectPart:IsA("BasePart") then
		activeDestructionEffect = effectPart
		-- Enable emitters and play sounds directly on the existing part
		for _, desc in ipairs(effectPart:GetDescendants()) do
			if desc:IsA("ParticleEmitter") then
				desc.Enabled = true
			elseif desc:IsA("Sound") then
				desc:Play()
			end
		end
	end

	-- Fire client remote so all clients can also emit a burst locally (full density)
	if effectPart then
		DestructionFXRemote:FireAllClients("Start", effectPart)
	end

	playDestructionSounds(targetModel)
	playDestructionSounds(thealthPart)
	playDestructionSounds(searchRoot)

	if killOwner and killAnimation and killAnimDuration then
		task.wait(killAnimDuration)
	end

	if activeDestructionEffect then
		for _, desc in ipairs(activeDestructionEffect:GetDescendants()) do
			if desc:IsA("ParticleEmitter") then
				desc.Enabled = false
			elseif desc:IsA("Sound") then
				desc:Stop()
			end
		end
		DestructionFXRemote:FireAllClients("Stop", activeDestructionEffect)
	end

	if explode and explosionModule then
		local pos = getCFrame(targetModel or thealthPart).Position
		local ok, err = pcall(function()
			explosionModule.handleExplosion(attacker, nil, {
				explosionRadius = explosionRadius,
				explosionFullDamageRadius = math.floor(explosionRadius * 0.3),
				explosionName = explosionName,
				TeamKill = explosionTeamKill,
				explosionsIgnoreWalls = false,
				explosionSourceCharacter = character,
				Damage = explosionDamage,
				ArmourDamage = explosionDamage,
				Incendiary = incendiary,
				fallOffStart = explosionRadius,
				fallOffEnd = explosionRadius,
				headShotMultiplier = 1,
				limbRemovalChance = 0,
				Distance = explosionRadius,
			}, pos)
		end)
		if not ok then warn("[DynamicWeapons] Explosion error:", err) end
	end

	if destroyBehavior == "Remove" then
		handleRemove(targetModel, thealthPart)
	elseif destroyBehavior == "Gib" then
		handleGib(searchRoot, targetModel, thealthPart, attacker)
	elseif destroyBehavior == "Hide" then
		handleHide(targetModel, thealthPart)
	elseif destroyBehavior == "Detach" then
		handleDetach(targetModel, thealthPart, attacker)
	else
		handleRemove(targetModel, thealthPart)
	end

	if killOwner and humanoid and humanoid.Parent and humanoid.Health > 0 then
		-- Remove ForceField so death can proceed
		local ff = character:FindFirstChild("DestructionForceField")
		if ff then ff:Destroy() end

		humanoid.Health = 0
	end

	-- Cleanup
	character:SetAttribute("TakedownActive", false)
end


local function monitorDestructibles(player: Player, character: Model, tool: Tool?, searchRoot: Instance)
	local parts = findDestructibleParts(searchRoot)
	local connections = {}

	for _, part in ipairs(parts) do
		setTeam(part, player)

		local teamConn = player:GetPropertyChangedSignal("Team"):Connect(function()
			if part and part.Parent then setTeam(part, player) end
		end)
		table.insert(connections, teamConn)

		local killEvent = part:FindFirstChild("THealthKill")
		if not killEvent then
			killEvent = Instance.new("BindableEvent")
			killEvent.Name = "THealthKill"
			killEvent.Parent = part
		end

		local killConn = killEvent.Event:Connect(function(attackerPlayer)
			onPartDestroyed(player, character, tool, searchRoot, part, attackerPlayer)
		end)
		table.insert(connections, killConn)
	end

	return connections
end

local activeBackpacks = {} -- [Player] = { [toolName] = { Model = instance, Connections = {} } }

local function spawnBackpackModel(player: Player, character: Model, tool: Tool)
	-- BackpackModel lives in the gun config module (TREK strips unknown children from tools at runtime)
	-- Config location: ReplicatedStorage > TREK_SERVICES > GunConfigs > [ToolName] > BackpackModel
	local configModule = shared.S.GunConfigs and shared.S.GunConfigs:FindFirstChild(tool.Name)
	local templateModel = configModule and configModule:FindFirstChild("BackpackModel")

	if not templateModel or not templateModel:IsA("Model") then
		print("[DynamicWeapons] No BackpackModel found in config for:", tool.Name) -- DEBUG
		return
	end

	-- Don't double-spawn
	if not activeBackpacks[player] then activeBackpacks[player] = {} end
	if activeBackpacks[player][tool.Name] then
		print("[DynamicWeapons] Backpack already exists for:", tool.Name)
		return
	end

	local torso = character:FindFirstChild("Torso")
	if not torso then
		print("[DynamicWeapons] No Torso found on character")
		return
	end

	print("[DynamicWeapons] Spawning backpack model for:", tool.Name) -- DEBUG

	-- Clone the model
	local clone = templateModel:Clone()
	clone.Name = "Backpack_" .. tool.Name
	clone:SetAttribute("_linkedToolName", tool.Name)

	-- Set all parts to non-collide, unanchored
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.CanCollide = false
			desc.CanQuery = true
			desc.Anchored = false
		end
	end

	-- Find the part to weld to Torso
	local weldTarget = clone.PrimaryPart
	if not weldTarget or not weldTarget:IsA("BasePart") then
		-- PrimaryPart might be nil or a Model — find the first BasePart
		weldTarget = nil
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("BasePart") then weldTarget = desc; break end
		end
	end

	if not weldTarget then
		print("[DynamicWeapons] ERROR: No weld target found!") -- DEBUG
		clone:Destroy()
		return
	end

	local attachTorso = clone:FindFirstChild("AttachTorso")

	if attachTorso and attachTorso:IsA("BasePart") then
		-- Calculate where the model needs to go so AttachTorso lands on the real Torso
		local pivotToAttach = clone:GetPivot():ToObjectSpace(attachTorso.CFrame)
		clone:PivotTo(torso.CFrame * pivotToAttach:Inverse())

		-- Hide the reference torso part
		attachTorso.Transparency = 1
		attachTorso.CanCollide = false
		attachTorso.CanQuery = false

		-- Weld AttachTorso directly to the real Torso (they're now at the same CFrame)
		clone.Parent = character

		-- Internal welds: connect all parts to AttachTorso (the anchor point)
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("BasePart") and desc ~= attachTorso then
				local alreadyWelded = false
				for _, child in ipairs(desc:GetChildren()) do
					if child:IsA("WeldConstraint") or child:IsA("Weld") or child:IsA("Motor6D") then
						alreadyWelded = true; break
					end
				end
				if not alreadyWelded then
					local w = Instance.new("WeldConstraint")
					w.Part0 = attachTorso
					w.Part1 = desc
					w.Parent = desc
				end
			end
		end

		-- Weld AttachTorso to the real Torso
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = torso
		weld.Part1 = attachTorso
		weld.Parent = attachTorso

		print("[DynamicWeapons] Aligned AttachTorso to Torso for:", tool.Name) -- DEBUG
	else
		-- FALLBACK: No AttachTorso — use AttachOffset/AttachRotation attributes
		local offsetVec = templateModel:GetAttribute("AttachOffset") or Vector3.new(0, 0, 0.7)
		local rotVec = templateModel:GetAttribute("AttachRotation") or Vector3.new(0, 0, 0)
		local offset = CFrame.new(offsetVec) * CFrame.Angles(math.rad(rotVec.X), math.rad(rotVec.Y), math.rad(rotVec.Z))

		clone:PivotTo(torso.CFrame * offset)
		clone.Parent = character

		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("BasePart") and desc ~= weldTarget then
				local alreadyWelded = false
				for _, child in ipairs(desc:GetChildren()) do
					if child:IsA("WeldConstraint") or child:IsA("Weld") or child:IsA("Motor6D") then
						alreadyWelded = true; break
					end
				end
				if not alreadyWelded then
					local w = Instance.new("WeldConstraint")
					w.Part0 = weldTarget
					w.Part1 = desc
					w.Parent = desc
				end
			end
		end

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = torso
		weld.Part1 = weldTarget
		weld.Parent = weldTarget

		print("[DynamicWeapons] Fallback offset weld for:", tool.Name) -- DEBUG
	end

	-- Monitor THealth parts on the backpack model
	local connections = monitorDestructibles(player, character, tool, clone)

	activeBackpacks[player][tool.Name] = {
		Model = clone,
		Connections = connections,
	}
end

local function removeBackpackModel(player: Player, toolName: string)
	if not activeBackpacks[player] then return end
	local data = activeBackpacks[player][toolName]
	if not data then return end

	-- Disconnect THealth monitoring
	for _, conn in ipairs(data.Connections) do
		if typeof(conn) == "RBXScriptConnection" then conn:Disconnect() end
	end

	-- Destroy the cloned model
	if data.Model and data.Model.Parent then
		data.Model:Destroy()
	end

	activeBackpacks[player][toolName] = nil
end

-- Check if a tool is still in the player's possession (Backpack or Character)
local function playerHasTool(player: Player, toolName: string): boolean
	if player.Backpack and player.Backpack:FindFirstChild(toolName) then return true end
	if player.Character and player.Character:FindFirstChild(toolName) then return true end
	return false
end

local playerConnections = {} -- [Player] = { connections }

local function onToolAdded(player: Player, character: Model, tool: Tool)
	if not playerConnections[player] then playerConnections[player] = {} end
	print("[DynamicWeapons] Tool detected:", tool.Name, "| Parent:", tool.Parent and tool.Parent.Name) -- DEBUG
	-- DEBUG: List tool children to verify BackpackModel exists
	local childNames = {}
	for _, child in ipairs(tool:GetChildren()) do
		table.insert(childNames, child.Name .. " (" .. child.ClassName .. ")")
	end
	print("[DynamicWeapons] Tool children:", table.concat(childNames, ", ")) -- DEBUG

	-- SYSTEM 1: Monitor tool-attached destructibles (only when equipped)
	if tool.Parent == character then
		local conns = monitorDestructibles(player, character, tool, tool)
		for _, c in ipairs(conns) do
			table.insert(playerConnections[player], c)
		end
	end

	-- SYSTEM 2: Spawn backpack model (whenever tool is in inventory)
	-- BackpackModel is stored in the gun config, not the tool (TREK strips tool children)
	local configModule = shared.S.GunConfigs and shared.S.GunConfigs:FindFirstChild(tool.Name)
	local bpModel = configModule and configModule:FindFirstChild("BackpackModel")
	print("[DynamicWeapons] BackpackModel check for", tool.Name, ":", bpModel) -- DEBUG
	if bpModel then
		spawnBackpackModel(player, character, tool)
	end
end

local function onToolRemoved(player: Player, toolName: string)
	-- Small delay: tool might be moving between Backpack and Character
	task.wait(0.1)

	-- If tool is no longer anywhere in the player's possession, remove backpack
	if not playerHasTool(player, toolName) then
		removeBackpackModel(player, toolName)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	print("[DynamicWeapons] CharacterAdded for:", player.Name) -- DEBUG
	-- Clean up old connections
	if playerConnections[player] then
		for _, conn in ipairs(playerConnections[player]) do
			if typeof(conn) == "RBXScriptConnection" then conn:Disconnect() end
		end
	end
	playerConnections[player] = {}

	-- Clean up old backpack models
	if activeBackpacks[player] then
		for toolName, _ in pairs(activeBackpacks[player]) do
			removeBackpackModel(player, toolName)
		end
	end

	-- Monitor Character for tool equip/unequip
	local charAddConn = character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			task.wait(0.1)
			onToolAdded(player, character, child)
		end
	end)
	table.insert(playerConnections[player], charAddConn)

	local charRemoveConn = character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			onToolRemoved(player, child.Name)
		end
	end)
	table.insert(playerConnections[player], charRemoveConn)

	-- Monitor Backpack for tool additions/removals
	local backpack = player:WaitForChild("Backpack", 5)
	if backpack then
		local bpAddConn = backpack.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and character and character.Parent then
				task.wait(0.1)
				onToolAdded(player, character, child)
			end
		end)
		table.insert(playerConnections[player], bpAddConn)

		local bpRemoveConn = backpack.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then
				onToolRemoved(player, child.Name)
			end
		end)
		table.insert(playerConnections[player], bpRemoveConn)
	end

	-- Check tools already in Backpack
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") then
				onToolAdded(player, character, child)
			end
		end
	end

	-- Check tools already equipped
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			onToolAdded(player, character, child)
		end
	end
end


Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		task.wait(1)
		onCharacterAdded(player, character)
	end)
end)

for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		task.spawn(function()
			onCharacterAdded(player, player.Character)
		end)
	end
	player.CharacterAdded:Connect(function(character)
		task.wait(1)
		onCharacterAdded(player, character)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	if playerConnections[player] then
		for _, conn in ipairs(playerConnections[player]) do
			if typeof(conn) == "RBXScriptConnection" then conn:Disconnect() end
		end
		playerConnections[player] = nil
	end
	if activeBackpacks[player] then
		for toolName, _ in pairs(activeBackpacks[player]) do
			removeBackpackModel(player, toolName)
		end
		activeBackpacks[player] = nil
	end
end)
