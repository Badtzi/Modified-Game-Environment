-- TREKHolsterServer.luau
-- Place in: ServerScriptService
-- Animation-based visible holstered weapons
-- Uses Motor6D + Holster animation from weapon config to position weapons on character

-- Wait for TREK to initialize
repeat task.wait() until shared.S and shared.S.trekServerFuncs

-- TRACKING
-- holsterData[player][tool] = { model, track, motor }
local holsterData = {}

-- HELPER: Get the weapon config module
local function getWeaponConfig(tool)
	local reqmod, mod = nil, nil

	-- Try MeleeConfigs first
	pcall(function()
		reqmod, mod = shared.S.trekServerFuncs.checkForMeleeModule(tool)
	end)
	if reqmod then return reqmod, mod end

	-- Try GunConfigs
	pcall(function()
		reqmod, mod = shared.S.trekServerFuncs.checkForModule(tool)
	end)

	return reqmod, mod
end

-- HELPER: Get which body part to holster to
local function getHolsterParent(reqmod, character)
	local partName = "Torso" -- default

	if reqmod.HolsterPart then
		partName = reqmod.HolsterPart
	end

	return character:FindFirstChild(partName)
end

-- HELPER: Find the Holster animation in the config module
local function getHolsterAnimation(mod)
	if not mod then return nil end

	local anims = mod:FindFirstChild("Animations")
	if not anims then return nil end

	local holsterAnim = anims:FindFirstChild("Holster")
	if holsterAnim and holsterAnim:IsA("Animation") and holsterAnim.AnimationId ~= "" then
		return holsterAnim
	end

	return nil
end

-- CORE: Create a holster visual for a tool
local function createHolsterVisual(player, tool)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end

	local reqmod, mod = getWeaponConfig(tool)
	if not reqmod then return end

	-- Check if holstering is enabled for this weapon
	-- ShowIfHolstered = false explicitly disables it
	-- If not set, defaults to showing (as long as a Holster animation exists)
	if reqmod.ShowIfHolstered == false then return end

	-- Check if this weapon has a Holster animation
	local holsterAnim = getHolsterAnimation(mod)
	if not holsterAnim then return end -- No holster animation = no visible holster

	local parentPart = getHolsterParent(reqmod, character)
	if not parentPart then return end

	-- Clone only visual parts of the weapon
	local holsterModel = Instance.new("Model")
	holsterModel.Name = "Holster_" .. tool.Name

	-- Find the primary part based on weapon type
	-- Guns weld via Main (TREK's toolAnim Motor6D), Melee welds via AnimPart (meleeToolAnim)
	local primaryPartName = nil
	if reqmod.ToolType == 'Melee' then
		-- Melee: AnimPart first
		if tool:FindFirstChild("AnimPart") then
			primaryPartName = "AnimPart"
		elseif tool:FindFirstChild("Main") then
			primaryPartName = "Main"
		elseif tool:FindFirstChild("Handle") then
			primaryPartName = "Handle"
		end
	else
		-- Gun: Main first (same part TREK uses for toolAnim Motor6D)
		if tool:FindFirstChild("Main") then
			primaryPartName = "Main"
		elseif tool:FindFirstChild("Handle") then
			primaryPartName = "Handle"
		elseif tool:FindFirstChild("AnimPart") then
			primaryPartName = "AnimPart"
		end
	end

	if not primaryPartName then
		if tool.PrimaryPart then
			primaryPartName = tool.PrimaryPart.Name
		else
			holsterModel:Destroy()
			return
		end
	end

	local clonedPrimary = nil

	for _, child in ipairs(tool:GetDescendants()) do
		if child:IsA("BasePart") then
			local clone = child:Clone()
			-- Remove scripts, tools, welds, motors from clone
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("BaseScript") or desc:IsA("Tool") or desc:IsA("JointInstance") then
					desc:Destroy()
				end
			end
			clone.CanCollide = false
			clone.CanTouch = false
			clone.CanQuery = false
			clone.Massless = true
			clone.Anchored = false

			-- Rename primary part to tool name so each weapon's holster animation targets a unique joint
			-- This means: when creating holster animations in Moon Animator, name the part = tool name
			if child.Name == primaryPartName then
				clone.Name = tool.Name
				clonedPrimary = clone
			end

			clone.Parent = holsterModel
		end
	end

	if not clonedPrimary then
		holsterModel:Destroy()
		return
	end

	holsterModel.PrimaryPart = clonedPrimary

	-- Weld all parts in holster model to the primary part (preserve relative positions)
	for _, part in ipairs(holsterModel:GetChildren()) do
		if part:IsA("BasePart") and part ~= clonedPrimary then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = clonedPrimary
			weld.Part1 = part
			weld.Parent = clonedPrimary
		end
	end

	-- Create Motor6D connecting body part to weapon (animation controls this)
	local motor = Instance.new("Motor6D")
	motor.Name = "Holster_" .. tool.Name
	motor.Part0 = parentPart
	motor.Part1 = clonedPrimary
	motor.Parent = parentPart

	holsterModel.Parent = character

	-- Play the Holster animation (server-side, replicates to all clients)
	local currentTrack = humanoid:LoadAnimation(holsterAnim)
	currentTrack.Priority = Enum.AnimationPriority.Idle
	currentTrack.Looped = true
	currentTrack:Play()

	-- Self-healing: if the animation gets stopped externally (e.g. takedown stops all tracks),
	-- re-play it as long as the holster model still exists
	-- Uses a recursive approach so each new track also gets a Stopped listener
	local stoppedConnection

	local function onTrackStopped()
		if holsterModel and holsterModel.Parent and humanoid and humanoid.Parent then
			task.defer(function()
				if holsterModel and holsterModel.Parent and humanoid and humanoid.Parent then
					-- Disconnect old listener
					if stoppedConnection then stoppedConnection:Disconnect() end
					-- Load and play new track
					currentTrack = humanoid:LoadAnimation(holsterAnim)
					currentTrack.Priority = Enum.AnimationPriority.Idle
					currentTrack.Looped = true
					currentTrack:Play()
					-- Reconnect Stopped on the NEW track
					stoppedConnection = currentTrack.Stopped:Connect(onTrackStopped)
					-- Update tracking data so removal can stop the correct track
					if holsterData[player] and holsterData[player][tool] then
						holsterData[player][tool].track = currentTrack
						holsterData[player][tool].stoppedConnection = stoppedConnection
					end
				end
			end)
		else
			if stoppedConnection then stoppedConnection:Disconnect() end
		end
	end

	stoppedConnection = currentTrack.Stopped:Connect(onTrackStopped)

	-- Store tracking data
	if not holsterData[player] then
		holsterData[player] = {}
	end
	holsterData[player][tool] = {
		model = holsterModel,
		track = currentTrack,
		motor = motor,
		stoppedConnection = stoppedConnection,
	}
end

-- CORE: Remove a holster visual for a tool
local function removeHolsterVisual(player, tool)
	if not holsterData[player] then return end

	local data = holsterData[player][tool]
	if not data then return end

	if data.stoppedConnection then
		data.stoppedConnection:Disconnect()
	end
	if data.track then
		data.track:Stop(0)
		data.track:Destroy()
	end
	if data.model and data.model.Parent then
		data.model:Destroy()
	end
	-- Motor6D is inside the model or on the parent part, gets cleaned up with model
	-- But also clean it explicitly in case it was parented to the body part
	if data.motor and data.motor.Parent then
		data.motor:Destroy()
	end

	holsterData[player][tool] = nil
end

-- CORE: Remove all holster visuals for a player
local function removeAllHolsterVisuals(player)
	if not holsterData[player] then return end

	for tool, data in pairs(holsterData[player]) do
		if data.stoppedConnection then data.stoppedConnection:Disconnect() end
		if data.track then data.track:Stop(0); data.track:Destroy() end
		if data.model and data.model.Parent then data.model:Destroy() end
		if data.motor and data.motor.Parent then data.motor:Destroy() end
	end

	holsterData[player] = nil
end

-- PLAYER SETUP
local function setupPlayer(player)
	player.CharacterAdded:Connect(function(character)
		task.wait(0.5) -- Let tools replicate to backpack

		removeAllHolsterVisuals(player)

		local backpack = player:WaitForChild("Backpack")

		-- Create holsters for existing backpack tools
		for _, tool in ipairs(backpack:GetChildren()) do
			if tool:IsA("Tool") then
				createHolsterVisual(player, tool)
			end
		end

		-- Tool added to backpack (unequipped or picked up)
		backpack.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				task.wait(0.1)
				createHolsterVisual(player, child)
			end
		end)

		-- Tool removed from backpack (equipped or dropped)
		backpack.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then
				removeHolsterVisual(player, child)
			end
		end)

		-- Clean up on death
		character:WaitForChild("Humanoid").Died:Connect(function()
			task.delay(3, function()
				removeAllHolsterVisuals(player)
			end)
		end)
	end)
end

-- CLEANUP
local function onPlayerRemoving(player)
	removeAllHolsterVisuals(player)
end

-- EXECUTION
for _, player in ipairs(game.Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end

game.Players.PlayerAdded:Connect(setupPlayer)
game.Players.PlayerRemoving:Connect(onPlayerRemoving)
