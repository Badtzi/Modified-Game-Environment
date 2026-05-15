local chr = script.Parent
local hum = chr:FindFirstChild('Humanoid')
if not hum then return end

local Players = game:GetService("Players")

local TICK_DAMAGE    = 15
local TICK_INTERVAL  = 1

local attackerTag = script:FindFirstChild("Attacker")
local attacker = attackerTag and attackerTag.Value or nil

local lbmodule = nil
pcall(function()
	local TREK_SERVICES = game.ReplicatedStorage:FindFirstChild("TREK_SERVICES")
	if TREK_SERVICES then
		local modules = TREK_SERVICES:FindFirstChild("TREK_Modules")
		if modules then
			local lb = modules:FindFirstChild("LeaderBoardModule")
			if lb then
				lbmodule = require(lb)
			end
		end
	end
end)


chr:SetAttribute("TBurningActive", true)

-- Voice: character is burning
pcall(function()
	local plr = Players:GetPlayerFromCharacter(chr)
	if plr and shared.VoicePlay then
		shared.VoicePlay(plr, "Burning")
	end
end)


pcall(function()
	local plr = Players:GetPlayerFromCharacter(chr)
	if plr then
		hum:UnequipTools()
	end
end)


local torso = chr:FindFirstChild("Torso") or chr:FindFirstChild("HumanoidRootPart")

pcall(function()
	local fireEffectTemplate = script:FindFirstChild("FireEffect")

	if fireEffectTemplate and torso then
		local activeFireEffect = fireEffectTemplate:Clone()

		if activeFireEffect:IsA("BasePart") then
			activeFireEffect.CFrame = torso.CFrame
			activeFireEffect.Anchored = false
			activeFireEffect.CanCollide = false
			activeFireEffect.CanQuery = false
			activeFireEffect.Transparency = 1

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = torso
			weld.Part1 = activeFireEffect
			weld.Parent = activeFireEffect

			activeFireEffect.Parent = chr
		elseif activeFireEffect:IsA("Model") then
			activeFireEffect:PivotTo(torso.CFrame)
			activeFireEffect.Parent = chr

			for _, desc in ipairs(activeFireEffect:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.Anchored = false
					desc.CanCollide = false
					desc.CanQuery = false
					local w = Instance.new("WeldConstraint")
					w.Part0 = torso
					w.Part1 = desc
					w.Parent = desc
				end
			end
		end

		for _, desc in ipairs(activeFireEffect:GetDescendants()) do
			if desc:IsA("ParticleEmitter") then
				desc.Enabled = true
			end
		end

	elseif torso then
		local fire = Instance.new("Fire")
		fire.Size = 5
		fire.Heat = 10
		fire.Parent = torso
	end
end)


pcall(function()
	local burningSound = script:FindFirstChild("Burning")
	if burningSound and burningSound:IsA("Sound") and torso then
		local s = burningSound:Clone()
		s.Looped = true
		s.Parent = torso
		s:Play()
	end
end)


local burningTrack = nil

pcall(function()
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end

	local TREK_SERVICES = game.ReplicatedStorage:FindFirstChild("TREK_SERVICES")
	if not TREK_SERVICES then return end
	local animFolder = TREK_SERVICES:FindFirstChild("Animations")
	if not animFolder then return end
	local burningAnim = animFolder:FindFirstChild("Burning")
	if not burningAnim or not burningAnim:IsA("Animation") then return end

	burningTrack = animator:LoadAnimation(burningAnim)
	burningTrack.Priority = Enum.AnimationPriority.Action4
	burningTrack.Looped = true
	burningTrack:Play()
end)

local function onFireDeath()
	-- Voice: dying from fire
	pcall(function()
		local plr = Players:GetPlayerFromCharacter(chr)
		if plr and shared.VoicePlay then
			shared.VoicePlay(plr, "BurnDeath")
		end
	end)

	-- Stop burning animation
	pcall(function()
		if burningTrack and burningTrack.IsPlaying then
			burningTrack:Stop(0)
		end
	end)

	-- Tell AimReplication to stop rotating arms (it checks TakedownActive and resets joints)
	chr:SetAttribute("TakedownActive", true)

	-- Lock all movement to prevent running during death animation
	chr:SetAttribute("MovementAnimsLocked", true)

	pcall(function()
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.AutoRotate = false
		hum:UnequipTools()
		hum:SetStateEnabled(Enum.HumanoidStateType.Running, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)

		local ff = Instance.new("ForceField")
		ff.Name = "FireDeathForceField"
		ff.Visible = false
		ff.Parent = chr
	end)

	-- Stop ALL playing animation tracks so nothing conflicts with the death animation
	pcall(function()
		local animator = hum:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				track:Stop(0)
			end
		end
	end)

	-- Play death animation
	local deathTrack = nil
	pcall(function()
		local TREK_SERVICES = game.ReplicatedStorage:FindFirstChild("TREK_SERVICES")
		if not TREK_SERVICES then return end
		local fireDeathFolder = TREK_SERVICES:FindFirstChild("FireDeathAnims")
		if not fireDeathFolder then return end

		local variants = fireDeathFolder:GetChildren()
		if #variants == 0 then return end

		local chosen = variants[math.random(1, #variants)]
		if not chosen:IsA("Animation") then return end

		local animator = hum:FindFirstChildOfClass("Animator")
		if not animator then return end

		deathTrack = animator:LoadAnimation(chosen)
		deathTrack.Priority = Enum.AnimationPriority.Action4
		deathTrack.Looped = false
		deathTrack:Play()
	end)

	-- Play death sound
	local deathSound = nil
	pcall(function()
		local fireDeathSound = script:FindFirstChild("FireDeathSound")
		if fireDeathSound and torso then
			deathSound = fireDeathSound:Clone()
			deathSound.Parent = torso
			deathSound:Play()
		end
	end)

	-- Wait for animation to finish (sound may finish earlier or later)
	if deathTrack then
		deathTrack.Stopped:Wait()
	end

	-- If sound is still playing, wait for it too
	if deathSound and deathSound.IsPlaying then
		deathSound.Ended:Wait()
	end
end

while hum and hum.Health > 0 do
	-- Tag attacker for kill credit before each tick
	if attacker and lbmodule then
		pcall(function()
			lbmodule.tagPlr(hum, attacker)
		end)
	end

	-- Check if this tick will kill the player
	if hum.Health <= TICK_DAMAGE then
		-- Award kill credit before death
		if attacker and lbmodule then
			pcall(function()
				lbmodule.UpdateStat(attacker, 'Kills', 1)
			end)
		end

		-- Play full fire death sequence (locks movement, waits for animation + sound)
		onFireDeath()

		-- Remove protection and kill after animation completes
		local ff = chr:FindFirstChild("FireDeathForceField")
		if ff then ff:Destroy() end
		hum:TakeDamage(hum.Health)
		break
	end

	hum:TakeDamage(TICK_DAMAGE)

	task.wait(TICK_INTERVAL)
end
