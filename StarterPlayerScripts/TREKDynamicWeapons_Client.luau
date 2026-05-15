--[[
	TREKDynamicWeapons_Client
	Place in: StarterPlayer > StarterPlayerScripts

	Listens for destruction events from the server and handles:
	- Playing the destruction transition animation (e.g., shield breaking)
	- Swapping the weapon's animation set to Post-prefixed versions
	- Playing kill animations (like the takedown system)

	ANIMATION NAMING CONVENTION:
	In your weapon config's Animations folder, add Post-prefixed versions
	of any animations that should change after destruction:

		Animations (Folder)
		+-- Idle              - pre-destruction (one-hand pistol + shield)
		+-- AimIn             - pre-destruction aim
		+-- Recoil            - pre-destruction fire
		+-- Reload            - pre-destruction reload
		+-- ShieldBreak       - one-shot destruction transition anim
		+-- PostIdle          - post-destruction (two-hand pistol)
		+-- PostAimIn         - post-destruction aim
		+-- PostRecoil        - post-destruction fire
		+-- PostReload        - post-destruction reload
		+-- FuelTankDeath     - kill animation (staggers, catches fire)

	Mode prefixes work too: 2PostIdle, 2PostRecoil, etc.

	The system sets tool:SetAttribute("PostDestructionMode", true) which
	Gun.luau's determineAnim checks to resolve "Idle" -> "PostIdle".
]]

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer

-- Wait for TREK
repeat task.wait() until shared.S

local TREK_Remotes = shared.S.TREK_Remotes
local DestroyedRemote = TREK_Remotes:WaitForChild("DynamicWeaponDestroyed", 15)
if not DestroyedRemote then
	warn("[TREKDynamicWeapons_Client] DynamicWeaponDestroyed remote not found, exiting.")
	return
end

------------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------------

local function findWeaponConfig(toolName: string)
	local configs = shared.S.GunConfigs
	if not configs then return nil end
	return configs:FindFirstChild(toolName)
end

local function findAnimation(configModule, animName: string): Animation?
	if not configModule then return nil end
	local animFolder = configModule:FindFirstChild("Animations")
	if not animFolder then return nil end
	return animFolder:FindFirstChild(animName)
end

local function stopWeaponTracks(humanoid: Humanoid)
	-- Stop all Action+ priority tracks (weapon animations)
	for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
		if track.Priority.Value >= Enum.AnimationPriority.Action.Value then
			track:Stop(0.1)
		end
	end
end

------------------------------------------------------------------------
-- DESTRUCTION EVENT HANDLER
------------------------------------------------------------------------

local function onDestructionEvent(data)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	-- Find config module by tool name (works regardless of equip state)
	local configModule = findWeaponConfig(data.ToolName)

	-- Try to find the tool (may be equipped or in backpack)
	local tool = character:FindFirstChild(data.ToolName)
	if not tool then
		local backpack = player:FindFirstChild("Backpack")
		if backpack then tool = backpack:FindFirstChild(data.ToolName) end
	end

	------------------------------------------------------------------------
	-- KILL ANIMATION SEQUENCE (like takedown system)
	------------------------------------------------------------------------

	if data.KillOwner and data.KillAnimation then
		-- Freeze aim replication
		character:SetAttribute("TakedownActive", true)

		-- Unequip tools
		humanoid:UnequipTools()

		-- Disable Animate script to prevent interference
		local animateScript = character:FindFirstChild("Animate")
		if animateScript then animateScript.Disabled = true end

		-- Disable movement scripts (same as takedown)
		local scriptsToPause = {
			"Directional Walking Script",
			"MovementLean",
			"Realistic Head Movement",
			"CameraBobbing",
		}
		for _, scriptName in ipairs(scriptsToPause) do
			local s = character:FindFirstChild(scriptName, true)
			if s and s:IsA("LocalScript") then s.Disabled = true end
		end

		-- Stop all current tracks EXCEPT holster animations (Idle + Looped)
		for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
			if track.Priority == Enum.AnimationPriority.Idle and track.Looped then
				continue
			end
			track:Stop(0)
		end

		-- Play kill animation
		local killAnim = findAnimation(configModule, data.KillAnimation)
		if killAnim then
			local track = humanoid:LoadAnimation(killAnim)
			track.Priority = Enum.AnimationPriority.Action4
			track.Looped = false
			track:Play(0)
		end

		-- Server handles the actual death after KillAnimationDuration
		-- No need for client cleanup -- death/respawn handles that
		return
	end

	------------------------------------------------------------------------
	-- NON-LETHAL DESTRUCTION (shield break, armor loss, etc.)
	------------------------------------------------------------------------

	if not tool or not tool.Parent then return end

	-- 1. Set PostDestructionMode so determineAnim remaps animations
	tool:SetAttribute("PostDestructionMode", true)

	-- 2. Stop all current weapon animations
	stopWeaponTracks(humanoid)

	-- 3. Play the one-shot destruction transition animation (e.g., "ShieldBreak")
	if data.DestructionAnimation then
		local destructAnim = findAnimation(configModule, data.DestructionAnimation)
		if destructAnim then
			local track = humanoid:LoadAnimation(destructAnim)
			track.Priority = Enum.AnimationPriority.Action4
			track.Looped = false
			track:Play(0)

			task.spawn(function()
				track.Stopped:Wait()
				if not tool or not tool.Parent then return end
				if not humanoid or humanoid.Health <= 0 then return end

				local postIdle = findAnimation(configModule, "PostIdle")
				if postIdle then
					local idleTrack = humanoid:LoadAnimation(postIdle)
					idleTrack.Priority = Enum.AnimationPriority.Action
					idleTrack.Looped = true
					idleTrack:Play(0.15)
				end
			end)
			return
		end
	end

	-- 4. No transition animation -- go straight to PostIdle
	task.wait(0.1)
	if not tool or not tool.Parent then return end

	local postIdle = findAnimation(configModule, "PostIdle")
	if postIdle then
		local idleTrack = humanoid:LoadAnimation(postIdle)
		idleTrack.Priority = Enum.AnimationPriority.Action
		idleTrack.Looped = true
		idleTrack:Play(0.15)
	end
end

------------------------------------------------------------------------
-- CONNECT
------------------------------------------------------------------------

DestroyedRemote.OnClientEvent:Connect(onDestructionEvent)

------------------------------------------------------------------------
-- DESTRUCTION FX (client-side density boost)
-- Server enables emitters on the part (replicates Enabled state),
-- but we also do a local Emit() burst for maximum particle density.
------------------------------------------------------------------------

local DestructionFXRemote = TREK_Remotes:WaitForChild("DestructionFX", 10)
if DestructionFXRemote then
	DestructionFXRemote.OnClientEvent:Connect(function(action, effectPart)
		if not effectPart or not effectPart:IsA("BasePart") then return end

		if action == "Start" then
			for _, desc in ipairs(effectPart:GetDescendants()) do
				if desc:IsA("ParticleEmitter") then
					desc:Emit(desc:GetAttribute("EmitCount") or math.random(15, 50))
				end
			end
		end
		-- "Stop" is handled by server setting Enabled = false (replicates automatically)
	end)
end
