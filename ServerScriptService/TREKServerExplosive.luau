--[[
	TREKServerExplosive
	Location: ServerScriptService
	
	Server handler for TREK Explosives. Handles grenade spawning,
	physics, detonation, damage, and effects.
	
	Remotes:
	  ExplosiveThrow    (Client -> Server)
	  ExplosivePinPull  (Client -> Server)
	  ExplosiveAmmo     (Client -> Server)
	  ExplosiveGFX      (Server -> All Clients)
	  ExplosiveConcuss  (Server -> Specific Client)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

repeat task.wait() until shared.S

local TREK_Remotes = shared.S.TREK_Remotes
local explosionModule = require(game.ServerStorage:WaitForChild("TREKExplosionModule"))
local damageModule = require(game.ServerStorage:WaitForChild("TREKDamageModule"))

------------------------------------------------------------------------
-- REMOTES
------------------------------------------------------------------------

local function getOrCreateRemote(name)
	local remote = TREK_Remotes:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = TREK_Remotes
	end
	return remote
end

local ThrowRemote = getOrCreateRemote("ExplosiveThrow")
local DropRemote = getOrCreateRemote("ExplosiveDrop")
local PinPullRemote = getOrCreateRemote("ExplosivePinPull")
local AmmoRemote = getOrCreateRemote("ExplosiveAmmo")
local GFXRemote = getOrCreateRemote("ExplosiveGFX")
local ConcussRemote = getOrCreateRemote("ExplosiveConcuss")

------------------------------------------------------------------------
-- COLLISION GROUP (grenade + spoon don't collide with each other)
------------------------------------------------------------------------

local PService = game:GetService("PhysicsService")
local GRENADE_COLLISION_GROUP = "TGrenadeProjectile"

if not PService:IsCollisionGroupRegistered(GRENADE_COLLISION_GROUP) then
	PService:RegisterCollisionGroup(GRENADE_COLLISION_GROUP)
	PService:CollisionGroupSetCollidable(GRENADE_COLLISION_GROUP, GRENADE_COLLISION_GROUP, false)
end

local function setCollisionGroup(instance)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = GRENADE_COLLISION_GROUP
	end
	if instance:IsA("Model") then
		for _, desc in ipairs(instance:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.CollisionGroup = GRENADE_COLLISION_GROUP
			end
		end
	end
end

------------------------------------------------------------------------
-- CONFIG LOOKUP
------------------------------------------------------------------------

local configCache = {}

local function getExplosiveConfig(tool)
	local configFolder = shared.S.ExplosiveConfigs
	if not configFolder then return nil, nil end

	local configName = tool:GetAttribute("TConfigToUse") or tool.Name
	local mod = configFolder:FindFirstChild(configName, true)
	if not mod then return nil, nil end

	if not configCache[mod] then
		configCache[mod] = require(mod)
	end

	return configCache[mod], mod
end

------------------------------------------------------------------------
-- AMMO
------------------------------------------------------------------------

local playerAmmo = {}

local function getAmmo(player, toolName, config)
	if not playerAmmo[player] then playerAmmo[player] = {} end
	if not playerAmmo[player][toolName] then
		playerAmmo[player][toolName] = {
			current = config.MagCapacity or 1,
			stored = config.ReservedAmmo or 3,
		}
	end
	return playerAmmo[player][toolName]
end

local function consumeAmmo(player, toolName, config)
	local ammo = getAmmo(player, toolName, config)
	if ammo.current <= 0 then return false end
	ammo.current -= 1
	return true
end

local function reloadAmmo(player, toolName, config)
	local ammo = getAmmo(player, toolName, config)
	if ammo.stored <= 0 then return false end
	if ammo.current >= (config.MagCapacity or 1) then return false end

	local needed = (config.MagCapacity or 1) - ammo.current
	local available = math.min(needed, ammo.stored)
	ammo.current += available

	if config.ReservedAmmo ~= math.huge then
		ammo.stored -= available
	end

	return true
end

------------------------------------------------------------------------
-- ACTIVE GRENADES
------------------------------------------------------------------------

local activeGrenades = {}

------------------------------------------------------------------------
-- GRENADE SPAWNING
------------------------------------------------------------------------

local function spawnGrenade(player, config, configModule, origin, direction, skipImpulse)
	local projectileTemplate = configModule:FindFirstChild("GrenadeProjectile")
	if not projectileTemplate then
		warn("[TREKServerExplosive] No GrenadeProjectile in config:", configModule.Name)
		return nil
	end

	local grenade = projectileTemplate:Clone()

	-- Resolve root part
	local rootPart
	if grenade:IsA("BasePart") then
		rootPart = grenade
	elseif grenade:IsA("Model") then
		if not grenade.PrimaryPart then
			for _, desc in ipairs(grenade:GetDescendants()) do
				if desc:IsA("BasePart") then
					grenade.PrimaryPart = desc
					break
				end
			end
		end
		rootPart = grenade.PrimaryPart
	end

	if not rootPart then
		grenade:Destroy()
		return nil
	end

	-- Physics from config
	rootPart.CustomPhysicalProperties = PhysicalProperties.new(
		config.Weight or 1,
		config.Friction or 0.6,
		config.Bounce or 0.3,
		1, 1
	)

	rootPart.Anchored = false
	rootPart.CanCollide = true
	rootPart.CanQuery = true

	-- Weld model parts to root
	if grenade:IsA("Model") then
		for _, desc in ipairs(grenade:GetDescendants()) do
			if desc:IsA("BasePart") and desc ~= rootPart then
				desc.Anchored = false
				desc.CanCollide = false
				desc.CanQuery = false
				local w = Instance.new("WeldConstraint")
				w.Part0 = rootPart
				w.Part1 = desc
				w.Parent = desc
			end
		end
	end

	-- Reparent model-level emitters and sounds to rootPart
	if grenade:IsA("Model") then
		for _, child in ipairs(grenade:GetChildren()) do
			if child:IsA("ParticleEmitter") or child:IsA("Sound") then
				child.Parent = rootPart
			end
		end
	end

	-- Position
	if grenade:IsA("BasePart") then
		grenade.CFrame = CFrame.new(origin, origin + direction)
	else
		grenade:PivotTo(CFrame.new(origin, origin + direction))
	end

	grenade.Parent = workspace

	-- Collision group (grenade won't collide with spoon)
	setCollisionGroup(grenade)

	-- NoCollisionConstraint with player's body so grenade passes through thrower
	-- but still collides with walls, floors, and other objects
	local chr = player.Character
	if chr then
		for _, part in ipairs(chr:GetChildren()) do
			if part:IsA("BasePart") then
				local ncc = Instance.new("NoCollisionConstraint")
				ncc.Part0 = rootPart
				ncc.Part1 = part
				ncc.Parent = rootPart
				Debris:AddItem(ncc, 1.0)
			end
		end
	end

	-- Throw force (skipped for death drops)
	if not skipImpulse then
		local throwForceHigh = config.ThrowForce or 80
		local throwForceLow = config.ThrowForceLow or (throwForceHigh * 0.4)
		local upAngle = math.rad(config.UpAngle or 25)

		local camPitchY = direction.Y
		local throwForce
		if camPitchY >= 0 then
			throwForce = throwForceHigh
		else
			local downFactor = math.clamp(math.abs(camPitchY), 0, 1)
			throwForce = throwForceHigh + (throwForceLow - throwForceHigh) * downFactor
		end

		local flatDir = Vector3.new(direction.X, 0, direction.Z).Unit
		local throwDir = (flatDir * math.cos(upAngle) + Vector3.new(0, math.sin(upAngle), 0)).Unit

		local pitchBlend = camPitchY * 0.5
		throwDir = (throwDir + Vector3.new(0, pitchBlend, 0)).Unit

		local impulse = throwDir * throwForce * rootPart.AssemblyMass
		rootPart:ApplyImpulse(impulse)
	end

	return grenade, rootPart
end

------------------------------------------------------------------------
-- DETONATION
------------------------------------------------------------------------

local function detonate(grenade, rootPart, config, player)
	warn("[TREKServerExplosive] detonate() called | grenade:", grenade, "| rootPart:", rootPart, "| player:", player)
	local data = activeGrenades[grenade]
	if not data then warn("[TREKServerExplosive] No active grenade data!") return end
	if data.detonated then return end
	data.detonated = true

	for _, conn in ipairs(data.connections) do
		if typeof(conn) == "RBXScriptConnection" then conn:Disconnect() end
	end

	local position = rootPart.Position + Vector3.new(0, 1, 0) -- Offset up so wall rays clear the ground

	-- Stop live effects server-side
	for _, desc in ipairs(grenade:GetDescendants()) do
		if desc:IsA("ParticleEmitter") then desc.Enabled = false end
		if desc:IsA("Sound") then desc:Stop() end
	end

	GFXRemote:FireAllClients("Detonate", grenade, position, config.explosionName)

	-- Explosion damage
	warn("[TREKServerExplosive] Detonating at:", position, "| Radius:", config.explosionRadius, "| Damage:", config.Damage)
	local ok, err = pcall(function()
		explosionModule.handleExplosion(player, nil, {
			explosionRadius = config.explosionRadius or 20,
			explosionFullDamageRadius = config.explosionFullDamageRadius or 8,
			explosionName = config.explosionName or "Explosion",
			TeamKill = config.TeamKill or false,
			explosionsIgnoreWalls = config.explosionsIgnoreWalls or false,
			Damage = config.Damage or 100,
			ArmourDamage = config.ArmourDamage or 50,
			Incendiary = config.Incendiary or false,
			headShotMultiplier = config.headShotMultiplier or 1,
			limbRemovalChance = config.CanGib and (config.limbRemovalChance or 50) or 0,
			fallOffStart = config.fallOffStart or config.explosionRadius or 20,
			fallOffEnd = config.fallOffEnd or config.explosionRadius or 20,
			Distance = config.Distance or 100,
		}, position)
	end)
	if not ok then
		warn("[TREKServerExplosive] Explosion error:", err)
	else
		warn("[TREKServerExplosive] Explosion completed successfully")
	end

	-- Bleed
	if config.ApplyBleed then
		local par = OverlapParams.new()
		par.FilterDescendantsInstances = {workspace:FindFirstChild("IgnoreList") or workspace}
		par.FilterType = Enum.RaycastFilterType.Exclude

		local parts = workspace:GetPartBoundsInRadius(position, config.explosionRadius or 20, par)
		local targets = {}

		for _, part in ipairs(parts) do
			local plr2, chr2 = shared.S.trekFuncs.findPlrAndChar(part)
			if chr2 and not targets[chr2] then
				targets[chr2] = true
				local gibsModule = game.ServerStorage:FindFirstChild("TREKGibsModule")
				if gibsModule then
					local tBleeding = gibsModule:FindFirstChild("TBleeding")
					if tBleeding and not chr2:FindFirstChild("TBleeding") then
						local b = tBleeding:Clone()
						b.Parent = chr2
						b.Disabled = false
						local hum = chr2:FindFirstChild("Humanoid")
						if hum and not hum:FindFirstChild("TBleedCondition") then
							local v = Instance.new("BoolValue")
							v.Parent = hum
							v.Name = "TBleedCondition"
							v.Value = true
						end
					end
				end
			end
		end
	end

	-- Concussion
	if config.ConcussionEffect and config.ConcussionType ~= "None" then
		local radius = config.ConcussionRadius or config.explosionRadius or 20
		local par = OverlapParams.new()
		par.FilterDescendantsInstances = {workspace:FindFirstChild("IgnoreList") or workspace}
		par.FilterType = Enum.RaycastFilterType.Exclude

		local parts = workspace:GetPartBoundsInRadius(position, radius, par)
		local targets = {}

		for _, part in ipairs(parts) do
			local plr2, chr2 = shared.S.trekFuncs.findPlrAndChar(part)
			if plr2 and chr2 and not targets[plr2] then
				targets[plr2] = true
				ConcussRemote:FireClient(plr2, {
					Type = config.ConcussionType,
					Duration = config.ConcussionDuration or 3,
					Position = position,
				})
			end
		end
	end

	-- Destroy grenade
	task.delay(0.1, function()
		if grenade and grenade.Parent then grenade:Destroy() end
	end)

	activeGrenades[grenade] = nil
end

------------------------------------------------------------------------
-- GRENADE TRACKING
------------------------------------------------------------------------

local function trackGrenade(grenade, rootPart, config, player)
	local connections = {}

	local data = {
		config = config,
		player = player,
		connections = connections,
		detonated = false,
	}
	activeGrenades[grenade] = data

	-- Reparent sounds to rootPart (sounds only get 3D spatial audio on a BasePart)
	if grenade:IsA("Model") then
		for _, desc in ipairs(grenade:GetChildren()) do
			if desc:IsA("Sound") then
				desc.Parent = rootPart
			end
		end
	end

	-- Enable live particles and sounds (server-side replicates)
	if config.LiveParticles or config.LiveSound then
		for _, desc in ipairs(rootPart:GetDescendants()) do
			if desc:IsA("ParticleEmitter") and config.LiveParticles then
				desc.Enabled = true
			elseif desc:IsA("Sound") and desc.Name == "LiveSound" and config.LiveSound then
				desc.Looped = true
				desc:Play()
			end
		end
		GFXRemote:FireAllClients("GoLive", grenade)
	end

	-- FUSE
	if config.ExplosiveType == "Fuse" then
		task.delay(config.FuseTime or 4, function()
			if grenade and grenade.Parent and not data.detonated then
				detonate(grenade, rootPart, config, player)
			end
		end)
	end

	-- IMPACT
	if config.ExplosiveType == "Impact" then
		local touchConn = rootPart.Touched:Connect(function(hit)
			if data.detonated then return end
			if player.Character and hit:IsDescendantOf(player.Character) then return end
			if activeGrenades[hit] or activeGrenades[hit and hit.Parent] then return end
			detonate(grenade, rootPart, config, player)
		end)
		table.insert(connections, touchConn)
	end

	-- BOUNCE SOUND (on every surface contact with cooldown)
	local lastBounceTime = 0

	local bounceConn = rootPart.Touched:Connect(function(hit)
		if data.detonated then return end
		if player.Character and hit:IsDescendantOf(player.Character) then return end

		local now = tick()
		if (now - lastBounceTime) > 0.15 then
			lastBounceTime = now
			local snd = grenade:FindFirstChild("Bounce", true)
			if snd and snd:IsA("Sound") then
				local s = snd:Clone()
				s.Parent = rootPart
				s:Play()
				Debris:AddItem(s, s.TimeLength + 0.5)
			end
		end
	end)
	table.insert(connections, bounceConn)

	-- PROXIMITY
	if config.ExplosiveType == "Proximity" then
		local proxRadius = config.ProximityRadius or 10
		local armed = false

		task.delay(config.ProximityDelay or 1, function() armed = true end)

		local proxConn = RunService.Heartbeat:Connect(function()
			if data.detonated or not armed then return end
			if not grenade or not grenade.Parent then return end

			local par = OverlapParams.new()
			par.FilterDescendantsInstances = {workspace:FindFirstChild("IgnoreList") or workspace, grenade}
			par.FilterType = Enum.RaycastFilterType.Exclude

			local parts = workspace:GetPartBoundsInRadius(rootPart.Position, proxRadius, par)
			for _, part in ipairs(parts) do
				local plr2, chr2 = shared.S.trekFuncs.findPlrAndChar(part)
				if plr2 and chr2 then
					if config.ProximityTeamCheck and player.Team and plr2.Team == player.Team then
						continue
					end
					local hum = chr2:FindFirstChild("Humanoid")
					if hum and hum.Health > 0 then
						detonate(grenade, rootPart, config, player)
						return
					end
				end
			end
		end)
		table.insert(connections, proxConn)
	end

	-- Safety auto-detonate
	task.delay(30, function()
		if grenade and grenade.Parent and not data.detonated then
			detonate(grenade, rootPart, config, player)
		end
	end)
end

------------------------------------------------------------------------
-- FUSE-ON-PULL TRACKING
------------------------------------------------------------------------

local pinPullTimestamps = {}

PinPullRemote.OnServerEvent:Connect(function(player, toolName)
	if not pinPullTimestamps[player] then pinPullTimestamps[player] = {} end
	pinPullTimestamps[player][toolName] = tick()
end)

------------------------------------------------------------------------
-- THROW HANDLER
------------------------------------------------------------------------

ThrowRemote.OnServerEvent:Connect(function(player, toolName, origin, direction)
	warn("[TREKServerExplosive] Throw received from:", player.Name, "| tool:", toolName)
	local chr = player.Character
	if not chr then return end
	local hum = chr:FindFirstChild("Humanoid")
	if not hum or hum.Health <= 0 then return end

	local tool = chr:FindFirstChild(toolName)
	if not tool then return end

	local config, configModule = getExplosiveConfig(tool)
	if not config or not configModule then return end

	if not consumeAmmo(player, toolName, config) then return end

	if typeof(direction) ~= "Vector3" then return end
	if direction.Magnitude < 0.01 then direction = chr.HumanoidRootPart.CFrame.LookVector end
	direction = direction.Unit

	if typeof(origin) ~= "Vector3" then origin = chr.HumanoidRootPart.Position end
	local distFromChar = (origin - chr.HumanoidRootPart.Position).Magnitude
	if distFromChar > 20 then origin = chr.HumanoidRootPart.Position + Vector3.new(0, 2, 0) end

	local grenade, rootPart = spawnGrenade(player, config, configModule, origin, direction)
	if not grenade or not rootPart then return end

	-- Spoon drop (server-side for consistent physics across all clients)
	if config.HasSpoon then
		local spoonTemplate = tool:FindFirstChild("Spoon", true)
		if spoonTemplate then
			local spoon = spoonTemplate:Clone()
			local spoonRoot

			if spoon:IsA("BasePart") then
				spoonRoot = spoon
			elseif spoon:IsA("Model") then
				spoonRoot = spoon.PrimaryPart or spoon:FindFirstChildWhichIsA("BasePart")
				if spoonRoot then
					for _, desc in ipairs(spoon:GetDescendants()) do
						if desc:IsA("BasePart") and desc ~= spoonRoot then
							desc.Anchored = false
							desc.CanCollide = false
							local w = Instance.new("WeldConstraint")
							w.Part0 = spoonRoot
							w.Part1 = desc
							w.Parent = desc
						end
					end
				end
			end

			if spoonRoot then
				spoonRoot.Anchored = false
				spoonRoot.CanCollide = true
				spoonRoot.CanQuery = false

				-- Heavy so it drops quickly near the player
				spoonRoot.CustomPhysicalProperties = PhysicalProperties.new(
					5,    -- density (heavy — drops fast)
					1.5,  -- friction (stops on contact)
					0.05, -- elasticity (dead drop, no bounce)
					1, 1
				)

				if spoon:IsA("BasePart") then
					spoon.CFrame = CFrame.new(origin)
				else
					spoon:PivotTo(CFrame.new(origin))
				end

				spoon.Parent = workspace:FindFirstChild("IgnoreList") or workspace

				-- Same collision group as grenade (won't collide with each other)
				setCollisionGroup(spoon)

				-- NoCollisionConstraint with player's body so spoon doesn't push thrower
				local throwChr = player.Character
				if throwChr then
					for _, bodyPart in ipairs(throwChr:GetChildren()) do
						if bodyPart:IsA("BasePart") then
							local ncc = Instance.new("NoCollisionConstraint")
							ncc.Part0 = spoonRoot
							ncc.Part1 = bodyPart
							ncc.Parent = spoonRoot
							Debris:AddItem(ncc, 2)
						end
					end
				end

				-- Small pop upward + slight forward drift — falls near the player
				local spoonForce = (config.ThrowForce or 80) * 0.08
				local throwDir = rootPart.AssemblyLinearVelocity.Unit
				local smallDrift = Vector3.new(
					throwDir.X * 0.3 + (math.random() - 0.5) * 0.1,
					1,  -- mostly upward
					throwDir.Z * 0.3 + (math.random() - 0.5) * 0.1
				).Unit
				local spoonImpulse = smallDrift * spoonForce * spoonRoot.AssemblyMass
				spoonRoot:ApplyImpulse(spoonImpulse)

				-- Gentle tumble
				spoonRoot:ApplyAngularImpulse(Vector3.new(
					(math.random() - 0.5) * 0.5,
					(math.random() - 0.5) * 0.5,
					(math.random() - 0.5) * 0.5
					))

				Debris:AddItem(spoon, 15)
			end
		end
	end

	-- Fuse-on-pull: subtract elapsed time
	if config.ExplosiveType == "Fuse" and config.FuseStartsOnPull then
		local pullTime = pinPullTimestamps[player] and pinPullTimestamps[player][toolName]
		if pullTime then
			local elapsed = tick() - pullTime
			local remaining = math.max(0.1, (config.FuseTime or 4) - elapsed)
			local modConfig = {}
			for k, v in pairs(config) do modConfig[k] = v end
			modConfig.FuseTime = remaining
			trackGrenade(grenade, rootPart, modConfig, player)
			pinPullTimestamps[player][toolName] = nil
			return
		end
	end

	-- Clear pin pull timestamp on throw (grenade was thrown, not dropped on death)
	if pinPullTimestamps[player] then
		pinPullTimestamps[player][toolName] = nil
	end

	trackGrenade(grenade, rootPart, config, player)
end)

------------------------------------------------------------------------
-- DEATH DROP (grenade drops from player's hands on death with pin pulled)
------------------------------------------------------------------------

DropRemote.OnServerEvent:Connect(function(player, toolName)
	if typeof(toolName) ~= "string" then return end

	local chr = player.Character
	if not chr then return end

	-- Find tool (may still be on character or in backpack during death)
	local tool = chr:FindFirstChild(toolName) or (player.Backpack and player.Backpack:FindFirstChild(toolName))
	if not tool then return end

	local config, configModule = getExplosiveConfig(tool)
	if not config or not configModule then return end

	-- Consume ammo
	if not consumeAmmo(player, toolName, config) then return end

	-- Spawn at player's hand position, no impulse â€” gravity drops it
	local hrp = chr:FindFirstChild("HumanoidRootPart")
	local origin = hrp and (hrp.Position + Vector3.new(0, 1, 0)) or Vector3.zero

	local grenade, rootPart = spawnGrenade(player, config, configModule, origin, Vector3.new(0, -1, 0), true)
	if not grenade or not rootPart then return end

	-- Fuse-on-pull: subtract elapsed time since pin pull
	if config.ExplosiveType == "Fuse" and config.FuseStartsOnPull then
		local pullTime = pinPullTimestamps[player] and pinPullTimestamps[player][toolName]
		if pullTime then
			local elapsed = tick() - pullTime
			local remaining = math.max(0.1, (config.FuseTime or 4) - elapsed)
			local modConfig = {}
			for k, v in pairs(config) do modConfig[k] = v end
			modConfig.FuseTime = remaining
			trackGrenade(grenade, rootPart, modConfig, player)
			pinPullTimestamps[player][toolName] = nil
			return
		end
	end

	trackGrenade(grenade, rootPart, config, player)
end)

------------------------------------------------------------------------
-- AMMO SYNC
------------------------------------------------------------------------

AmmoRemote.OnServerEvent:Connect(function(player, toolName, action)
	local chr = player.Character
	if not chr then return end

	local tool = chr:FindFirstChild(toolName) or (player.Backpack and player.Backpack:FindFirstChild(toolName))
	if not tool then return end

	local config = getExplosiveConfig(tool)
	if not config then return end

	if action == "Reload" then
		reloadAmmo(player, toolName, config)
		local ammo = getAmmo(player, toolName, config)
		AmmoRemote:FireClient(player, toolName, ammo.current, ammo.stored)
	elseif action == "Query" then
		local ammo = getAmmo(player, toolName, config)
		AmmoRemote:FireClient(player, toolName, ammo.current, ammo.stored)
	end
end)

------------------------------------------------------------------------
-- CLEANUP (reset ammo on respawn + player leaving)
------------------------------------------------------------------------

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		playerAmmo[player] = nil
		pinPullTimestamps[player] = nil

		-- SERVER-SIDE DEATH DROP: if the player dies while holding a pin-pulled
		-- grenade, drop it immediately. The client-side Died handler races with
		-- character destruction and often loses â€” this server-side hook runs
		-- before the death handler removes the character.
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Connect(function()
				local pulls = pinPullTimestamps[player]
				if not pulls then return end

				for toolName, pullTime in pairs(pulls) do
					-- Find the tool (still on character at this point)
					local tool = character:FindFirstChild(toolName)
						or (player.Backpack and player.Backpack:FindFirstChild(toolName))
					if not tool then continue end

					local config, configModule = getExplosiveConfig(tool)
					if not config or not configModule then continue end

					-- Consume ammo
					if not consumeAmmo(player, toolName, config) then continue end

					-- Spawn grenade at player position, drop straight down
					local hrp = character:FindFirstChild("HumanoidRootPart")
					local origin = hrp and (hrp.Position + Vector3.new(0, 1, 0)) or Vector3.zero

					local grenade, rootPart = spawnGrenade(player, config, configModule, origin, Vector3.new(0, -1, 0), true)
					if not grenade or not rootPart then continue end

					-- Fuse-on-pull: subtract elapsed time
					if config.ExplosiveType == "Fuse" and config.FuseStartsOnPull then
						local elapsed = tick() - pullTime
						local remaining = math.max(0.1, (config.FuseTime or 4) - elapsed)
						local modConfig = {}
						for k, v in pairs(config) do modConfig[k] = v end
						modConfig.FuseTime = remaining
						trackGrenade(grenade, rootPart, modConfig, player)
					else
						trackGrenade(grenade, rootPart, config, player)
					end
				end

				-- Clear all pin pulls for this player
				pinPullTimestamps[player] = nil
			end)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	playerAmmo[player] = nil
	pinPullTimestamps[player] = nil
end)
