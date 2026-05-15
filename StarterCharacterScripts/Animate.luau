-- Animate.luau — with directional movement support
-- Original Roblox Animate script + directional walk/sprint when shiftlock or FP active

local Figure = script.Parent
local Torso = Figure:WaitForChild("Torso")
local RightShoulder = Torso:WaitForChild("Right Shoulder")
local LeftShoulder = Torso:WaitForChild("Left Shoulder")
local RightHip = Torso:WaitForChild("Right Hip")
local LeftHip = Torso:WaitForChild("Left Hip")
local Neck = Torso:WaitForChild("Neck")
local Humanoid = Figure:WaitForChild("Humanoid")
local HRP = Figure:WaitForChild("HumanoidRootPart")
local pose = "Standing"

local Players = game:GetService("Players")

-- Shiftlock detection (same approach as Dash/Roll script)
local smoothShiftLock = require(
	Players.LocalPlayer:WaitForChild("PlayerScripts")
		:WaitForChild("CustomShiftLock")
		:WaitForChild("SmoothShiftLock")
)

local EMOTE_TRANSITION_TIME = 0.1

local userAnimateScaleRunSuccess, userAnimateScaleRunValue = pcall(function() return UserSettings():IsUserFeatureEnabled("UserAnimateScaleRun") end)
local userAnimateScaleRun = userAnimateScaleRunSuccess and userAnimateScaleRunValue

local function getRigScale()
	if userAnimateScaleRun then
		return Figure:GetScale()
	else
		return 1
	end
end

local currentAnim = ""
local currentAnimInstance = nil
local currentAnimTrack = nil
local currentAnimKeyframeHandler = nil
local currentAnimSpeed = 1.0
local animTable = {}
local animNames = { 
	idle = 	{	
		{ id = "http://www.roblox.com/asset/?id=88725449760715", weight = 9 },
		{ id = "http://www.roblox.com/asset/?id=88725449760715", weight = 1 }
	},
	walk = 	{ 	
		{ id = "http://www.roblox.com/asset/?id=76055569360937", weight = 10 } 
	}, 
	run = 	{
		{ id = "run.xml", weight = 10 } 
	}, 
	jump = 	{
		{ id = "http://www.roblox.com/asset/?id=134249560551463", weight = 10 } 
	}, 
	fall = 	{
		{ id = "http://www.roblox.com/asset/?id=103860286390339", weight = 10 } 
	}, 
	climb = {
		{ id = "http://www.roblox.com/asset/?id=180436334", weight = 10 } 
	}, 
	sit = 	{
		{ id = "http://www.roblox.com/asset/?id=178130996", weight = 10 } 
	},	
	toolnone = {
		{ id = "http://www.roblox.com/asset/?id=182393478", weight = 10 } 
	},
	toolslash = {
		{ id = "http://www.roblox.com/asset/?id=129967390", weight = 10 } 
	},
	toollunge = {
		{ id = "http://www.roblox.com/asset/?id=129967478", weight = 10 } 
	},
	wave = {
		{ id = "http://www.roblox.com/asset/?id=128777973", weight = 10 } 
	},
	point = {
		{ id = "http://www.roblox.com/asset/?id=128853357", weight = 10 } 
	},
	dance1 = {
		{ id = "http://www.roblox.com/asset/?id=182435998", weight = 10 }, 
		{ id = "http://www.roblox.com/asset/?id=182491037", weight = 10 }, 
		{ id = "http://www.roblox.com/asset/?id=182491065", weight = 10 } 
	},
	dance2 = {
		{ id = "http://www.roblox.com/asset/?id=182436842", weight = 10 }, 
		{ id = "http://www.roblox.com/asset/?id=182491248", weight = 10 }, 
		{ id = "http://www.roblox.com/asset/?id=182491277", weight = 10 } 
	},
	dance3 = {
		{ id = "http://www.roblox.com/asset/?id=182436935", weight = 10 }, 
		{ id = "http://www.roblox.com/asset/?id=182491368", weight = 10 }, 
		{ id = "http://www.roblox.com/asset/?id=182491423", weight = 10 } 
	},
	laugh = {
		{ id = "http://www.roblox.com/asset/?id=129423131", weight = 10 } 
	},
	cheer = {
		{ id = "http://www.roblox.com/asset/?id=129423030", weight = 10 } 
	},
}

-- Movement state tracking
local landTrack = nil
local previousPose = "Standing"
local lastLandTime = 0
local LAND_COOLDOWN = 2 -- seconds before landing animation can play again
local extraAnimNames = {
	"WalkForward", "WalkBackward", "WalkLeft", "WalkRight",
	"SprintForward", "SprintBackward", "SprintLeft", "SprintRight",
	"WalkToSprintF", "SprintToWalkF",
	"CrouchIdle", "Crouch",
	"Land",
}

local dances = {"dance1", "dance2", "dance3"}

-- Existance in this list signifies that it is an emote, the value indicates if it is a looping emote
local emoteNames = { wave = false, point = false, dance1 = true, dance2 = true, dance3 = true, laugh = false, cheer = false}

function configureAnimationSet(name, fileList)
	if (animTable[name] ~= nil) then
		for _, connection in pairs(animTable[name].connections) do
			connection:disconnect()
		end
	end
	animTable[name] = {}
	animTable[name].count = 0
	animTable[name].totalWeight = 0	
	animTable[name].connections = {}

	-- check for config values
	local config = script:FindFirstChild(name)
	if (config ~= nil) then
		table.insert(animTable[name].connections, config.ChildAdded:connect(function(child) configureAnimationSet(name, fileList) end))
		table.insert(animTable[name].connections, config.ChildRemoved:connect(function(child) configureAnimationSet(name, fileList) end))
		local idx = 1
		for _, childPart in pairs(config:GetChildren()) do
			if (childPart:IsA("Animation")) then
				table.insert(animTable[name].connections, childPart.Changed:connect(function(property) configureAnimationSet(name, fileList) end))
				animTable[name][idx] = {}
				animTable[name][idx].anim = childPart
				local weightObject = childPart:FindFirstChild("Weight")
				if (weightObject == nil) then
					animTable[name][idx].weight = 1
				else
					animTable[name][idx].weight = weightObject.Value
				end
				animTable[name].count = animTable[name].count + 1
				animTable[name].totalWeight = animTable[name].totalWeight + animTable[name][idx].weight
				idx = idx + 1
			end
		end
	end

	-- fallback to defaults
	if (animTable[name].count <= 0) then
		if fileList then
			for idx, anim in pairs(fileList) do
				animTable[name][idx] = {}
				animTable[name][idx].anim = Instance.new("Animation")
				animTable[name][idx].anim.Name = name
				animTable[name][idx].anim.AnimationId = anim.id
				animTable[name][idx].weight = anim.weight
				animTable[name].count = animTable[name].count + 1
				animTable[name].totalWeight = animTable[name].totalWeight + anim.weight
			end
		end
	end
end

-- Setup animation objects
function scriptChildModified(child)
	local fileList = animNames[child.Name]
	if (fileList ~= nil) then
		configureAnimationSet(child.Name, fileList)
	else
		configureAnimationSet(child.Name, nil)
	end	
end

script.ChildAdded:connect(scriptChildModified)
script.ChildRemoved:connect(scriptChildModified)

-- Note: removed blanket track clearing on init
-- Animate manages its own tracks via currentAnimTrack in playAnimation()
-- Blanket clearing was killing server-side holster animations on script restart

-- Load standard animations
for name, fileList in pairs(animNames) do 
	configureAnimationSet(name, fileList)
end

-- Load extra animations from child folders
for _, name in ipairs(extraAnimNames) do
	configureAnimationSet(name, nil)
end

-- =====================================================
-- DIRECTIONAL MOVEMENT HELPERS
-- =====================================================

local function isDirectionalActive()
	if smoothShiftLock:IsEnabled() then return true end
	local camera = workspace.CurrentCamera
	if camera and HRP then
		if (camera.CFrame.Position - HRP.Position).Magnitude < 2 then return true end
	end
	return false
end

local function getMovementDirection()
	local moveDir = HRP.CFrame:VectorToObjectSpace(Humanoid.MoveDirection)
	if moveDir.Magnitude < 0.1 then return nil end

	local absX = math.abs(moveDir.X)
	local absZ = math.abs(moveDir.Z)

	-- Check if diagonal (both axes significant)
	local isDiagonal = absX > 0.3 and absZ > 0.3

	if isDiagonal then
		-- Diagonals ONLY play Forward or Backward
		if moveDir.Z < 0 then
			return "Forward"
		else
			return "Backward"
		end
	end

	-- Pure cardinal direction
	if absZ >= absX then
		if moveDir.Z < 0 then
			return "Forward"
		else
			return "Backward"
		end
	else
		if moveDir.X < 0 then
			return "Left"
		else
			return "Right"
		end
	end
end

-- =====================================================
-- ANIMATION PLAYBACK (original structure preserved)
-- =====================================================

local toolAnim = "None"
local toolAnimTime = 0

local jumpAnimTime = 0
local jumpAnimDuration = 0.3

local toolTransitionTime = 0.1
local fallTransitionTime = 0.3
local jumpMaxLimbVelocity = 0.75

function stopAllAnimations()
	local oldAnim = currentAnim

	-- return to idle if finishing an emote
	if (emoteNames[oldAnim] ~= nil and emoteNames[oldAnim] == false) then
		oldAnim = "idle"
	end

	currentAnim = ""
	currentAnimInstance = nil
	if (currentAnimKeyframeHandler ~= nil) then
		currentAnimKeyframeHandler:disconnect()
	end

	if (currentAnimTrack ~= nil) then
		currentAnimTrack:Stop()
		currentAnimTrack:Destroy()
		currentAnimTrack = nil
	end
	return oldAnim
end

function setAnimationSpeed(speed)
	if speed ~= currentAnimSpeed then
		currentAnimSpeed = speed
		currentAnimTrack:AdjustSpeed(currentAnimSpeed)
	end
end

function keyFrameReachedFunc(frameName)
	if (frameName == "End") then

		local repeatAnim = currentAnim
		-- return to idle if finishing an emote
		if (emoteNames[repeatAnim] ~= nil and emoteNames[repeatAnim] == false) then
			repeatAnim = "idle"
		end

		local animSpeed = currentAnimSpeed
		playAnimation(repeatAnim, 0.0, Humanoid)
		setAnimationSpeed(animSpeed)
	end
end

-- Preload animations
function playAnimation(animName, transitionTime, humanoid) 
	if not animTable[animName] or animTable[animName].count <= 0 then return end

	local roll = math.random(1, animTable[animName].totalWeight) 
	local origRoll = roll
	local idx = 1
	while (roll > animTable[animName][idx].weight) do
		roll = roll - animTable[animName][idx].weight
		idx = idx + 1
	end
	local anim = animTable[animName][idx].anim

	-- switch animation		
	if (anim ~= currentAnimInstance) then

		if (currentAnimTrack ~= nil) then
			currentAnimTrack:Stop(transitionTime)
			currentAnimTrack:Destroy()
		end

		currentAnimSpeed = 1.0

		-- load it to the humanoid; get AnimationTrack
		currentAnimTrack = humanoid:LoadAnimation(anim)
		currentAnimTrack.Priority = Enum.AnimationPriority.Core

		-- play the animation
		currentAnimTrack:Play(transitionTime)
		currentAnim = animName
		currentAnimInstance = anim

		-- set up keyframe name triggers
		if (currentAnimKeyframeHandler ~= nil) then
			currentAnimKeyframeHandler:disconnect()
		end
		currentAnimKeyframeHandler = currentAnimTrack.KeyframeReached:connect(keyFrameReachedFunc)

	end

end

-------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------

local toolAnimName = ""
local toolAnimTrack = nil
local toolAnimInstance = nil
local currentToolAnimKeyframeHandler = nil

function toolKeyFrameReachedFunc(frameName)
	if (frameName == "End") then
		playToolAnimation(toolAnimName, 0.0, Humanoid)
	end
end

function playToolAnimation(animName, transitionTime, humanoid, priority)
	if not animTable[animName] or animTable[animName].count <= 0 then return end

	local roll = math.random(1, animTable[animName].totalWeight) 
	local origRoll = roll
	local idx = 1
	while (roll > animTable[animName][idx].weight) do
		roll = roll - animTable[animName][idx].weight
		idx = idx + 1
	end
	local anim = animTable[animName][idx].anim

	if (toolAnimInstance ~= anim) then

		if (toolAnimTrack ~= nil) then
			toolAnimTrack:Stop()
			toolAnimTrack:Destroy()
			transitionTime = 0
		end

		-- load it to the humanoid; get AnimationTrack
		toolAnimTrack = humanoid:LoadAnimation(anim)
		if priority then
			toolAnimTrack.Priority = priority
		end

		-- play the animation
		toolAnimTrack:Play(transitionTime)
		toolAnimName = animName
		toolAnimInstance = anim

		currentToolAnimKeyframeHandler = toolAnimTrack.KeyframeReached:connect(toolKeyFrameReachedFunc)
	end
end

function stopToolAnimations()
	local oldAnim = toolAnimName

	if (currentToolAnimKeyframeHandler ~= nil) then
		currentToolAnimKeyframeHandler:disconnect()
	end

	toolAnimName = ""
	toolAnimInstance = nil
	if (toolAnimTrack ~= nil) then
		toolAnimTrack:Stop()
		toolAnimTrack:Destroy()
		toolAnimTrack = nil
	end


	return oldAnim
end

-------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------

-- =====================================================
-- MOVEMENT STATE HANDLERS (modified for directional)
-- =====================================================

function onRunning(speed)
	-- BIPOD/TAKEDOWN/etc: short-circuit walk/run/sprint anims when physically locked.
	-- The locking system (e.g. bipod controller) sets MovementAnimsLocked = true
	-- on deploy and clears it on undeploy. Idle stays available; movement anims do not.
	if Figure:GetAttribute("MovementAnimsLocked") then
		if currentAnim ~= "idle" then
			playAnimation("idle", 0.1, Humanoid)
		end
		previousPose = pose
		pose = "Standing"
		return
	end

	speed /= getRigScale()

	local isSprinting = Figure:GetAttribute("IsSprinting") or false
	local isCrouching = Figure:GetAttribute("IsCrouching") or false
	local isProne = Figure:GetAttribute("IsProne") or false
	local wasInAir = (previousPose == "FreeFall" or previousPose == "Jumping")

	-- Prone: ProneController handles all animations via yaw scrubbing.
	-- Stop any active movement animation and return early.
	if isProne then
		if currentAnimTrack and currentAnimTrack.IsPlaying then
			currentAnimTrack:Stop(0.2)
			currentAnimTrack:Destroy()
			currentAnimTrack = nil
			currentAnim = ""
			currentAnimInstance = nil
		end
		previousPose = pose
		pose = "Standing"
		return
	end

	if speed > 0.01 then
		-- PLAYER IS MOVING

		-- Landing: if we were in the air, play Land one-shot (with cooldown)
		if wasInAir and animTable["Land"] and animTable["Land"].count > 0 and (tick() - lastLandTime) >= LAND_COOLDOWN then
			lastLandTime = tick()
			-- Stop any current anim
			if currentAnimTrack then
				currentAnimTrack:Stop(0.1)
				currentAnimTrack:Destroy()
				currentAnimTrack = nil
				currentAnim = ""
				currentAnimInstance = nil
			end

			local roll = math.random(1, animTable["Land"].totalWeight)
			local idx = 1
			while roll > animTable["Land"][idx].weight do
				roll = roll - animTable["Land"][idx].weight
				idx = idx + 1
			end
			landTrack = Humanoid:LoadAnimation(animTable["Land"][idx].anim)
			landTrack.Priority = Enum.AnimationPriority.Movement
			landTrack.Looped = false
			landTrack:Play(0.05)

			task.spawn(function()
				landTrack.Stopped:Wait()
				if landTrack then landTrack:Destroy(); landTrack = nil end
				-- After landing, re-evaluate movement state
				if Humanoid.MoveDirection.Magnitude > 0.1 then
					onRunning(Humanoid.WalkSpeed)
				end
			end)

			previousPose = pose
			pose = "Running"
			return
		end

		-- If land animation is still playing, don't override it
		if landTrack and landTrack.IsPlaying then
			previousPose = pose
			pose = "Running"
			return
		end

		-- Crouch check FIRST (works regardless of shiftlock)
		if isCrouching then
			if animTable["Crouch"] and animTable["Crouch"].count > 0 then
				if currentAnim ~= "Crouch" then
					playAnimation("Crouch", 0.15, Humanoid)
				end
			else
				playAnimation("walk", 0.1, Humanoid)
			end
			previousPose = pose
			pose = "Running"
			return
		end

		if isDirectionalActive() then
			-- DIRECTIONAL MODE: pick animation based on direction + sprint state
			local direction = getMovementDirection()
			if not direction then direction = "Forward" end

			local targetAnim
			if isSprinting then
				targetAnim = "Sprint" .. direction
			else
				targetAnim = "Walk" .. direction
			end

			if animTable[targetAnim] and animTable[targetAnim].count > 0 then
				if currentAnim ~= targetAnim then
					playAnimation(targetAnim, 0.15, Humanoid)
				end
			else
				playAnimation("walk", 0.1, Humanoid)
			end
		else
			-- STANDARD MODE: no shiftlock, character auto-rotates to face movement
			if isSprinting then
				if animTable["SprintForward"] and animTable["SprintForward"].count > 0 then
					if currentAnim ~= "SprintForward" then
						playAnimation("SprintForward", 0.15, Humanoid)
					end
				else
					playAnimation("walk", 0.1, Humanoid)
				end
			else
				playAnimation("walk", 0.1, Humanoid)
				if currentAnimInstance and currentAnimInstance.AnimationId == "http://www.roblox.com/asset/?id=180426354" then
					setAnimationSpeed(speed / 14.5)
				end
			end
		end
		previousPose = pose
		pose = "Running"
	else
		-- PLAYER STOPPED

		-- Landing while stopped (with cooldown)
		if wasInAir and animTable["Land"] and animTable["Land"].count > 0 and (tick() - lastLandTime) >= LAND_COOLDOWN then
			lastLandTime = tick()
			if currentAnimTrack then
				currentAnimTrack:Stop(0.1)
				currentAnimTrack:Destroy()
				currentAnimTrack = nil
				currentAnim = ""
				currentAnimInstance = nil
			end

			local roll = math.random(1, animTable["Land"].totalWeight)
			local idx = 1
			while roll > animTable["Land"][idx].weight do
				roll = roll - animTable["Land"][idx].weight
				idx = idx + 1
			end
			landTrack = Humanoid:LoadAnimation(animTable["Land"][idx].anim)
			landTrack.Priority = Enum.AnimationPriority.Movement
			landTrack.Looped = false
			landTrack:Play(0.05)

			task.spawn(function()
				landTrack.Stopped:Wait()
				if landTrack then landTrack:Destroy(); landTrack = nil end
				if Humanoid.MoveDirection.Magnitude < 0.1 then
					if isCrouching and animTable["CrouchIdle"] and animTable["CrouchIdle"].count > 0 then
						playAnimation("CrouchIdle", 0.15, Humanoid)
					else
						playAnimation("idle", 0.15, Humanoid)
					end
				end
			end)

			previousPose = pose
			pose = "Standing"
			return
		end

		-- If land animation is still playing, don't override it
		if landTrack and landTrack.IsPlaying then
			previousPose = pose
			pose = "Standing"
			return
		end

		if emoteNames[currentAnim] == nil then
			if isCrouching and animTable["CrouchIdle"] and animTable["CrouchIdle"].count > 0 then
				if currentAnim ~= "CrouchIdle" then
					playAnimation("CrouchIdle", 0.2, Humanoid)
				end
			else
				playAnimation("idle", 0.1, Humanoid)
			end
			previousPose = pose
			pose = "Standing"
		end
	end
end

function onDied()
	pose = "Dead"
end

function onJumping()
	playAnimation("jump", 0.1, Humanoid)
	jumpAnimTime = jumpAnimDuration
	previousPose = pose
	pose = "Jumping"
end

function onClimbing(speed)
	speed /= getRigScale()

	playAnimation("climb", 0.1, Humanoid)
	setAnimationSpeed(speed / 12.0)
	previousPose = pose
	pose = "Climbing"
end

function onGettingUp()
	previousPose = pose
	pose = "GettingUp"
end

function onFreeFall()
	if (jumpAnimTime <= 0) then
		playAnimation("fall", fallTransitionTime, Humanoid)
	end
	previousPose = pose
	pose = "FreeFall"
end

function onFallingDown()
	previousPose = pose
	pose = "FallingDown"
end

function onSeated()
	previousPose = pose
	pose = "Seated"
end

function onPlatformStanding()
	previousPose = pose
	pose = "PlatformStanding"
end

function onSwimming(speed)
	if speed > 0 then
		pose = "Running"
	else
		pose = "Standing"
	end
end

function getTool()	
	for _, kid in ipairs(Figure:GetChildren()) do
		if kid.className == "Tool" then return kid end
	end
	return nil
end

function getToolAnim(tool)
	for _, c in ipairs(tool:GetChildren()) do
		if c.Name == "toolanim" and c.className == "StringValue" then
			return c
		end
	end
	return nil
end

function animateTool()

	if (toolAnim == "None") then
		playToolAnimation("toolnone", toolTransitionTime, Humanoid, Enum.AnimationPriority.Idle)
		return
	end

	if (toolAnim == "Slash") then
		playToolAnimation("toolslash", 0, Humanoid, Enum.AnimationPriority.Action)
		return
	end

	if (toolAnim == "Lunge") then
		playToolAnimation("toollunge", 0, Humanoid, Enum.AnimationPriority.Action)
		return
	end
end

function moveSit()
	RightShoulder.MaxVelocity = 0.15
	LeftShoulder.MaxVelocity = 0.15
	RightShoulder:SetDesiredAngle(3.14 /2)
	LeftShoulder:SetDesiredAngle(-3.14 /2)
	RightHip:SetDesiredAngle(3.14 /2)
	LeftHip:SetDesiredAngle(-3.14 /2)
end

local lastTick = 0

function move(time)
	local amplitude = 1
	local frequency = 1
	local deltaTime = time - lastTick
	lastTick = time

	local climbFudge = 0
	local setAngles = false

	if (jumpAnimTime > 0) then
		jumpAnimTime = jumpAnimTime - deltaTime
	end

	if (pose == "FreeFall" and jumpAnimTime <= 0) then
		playAnimation("fall", fallTransitionTime, Humanoid)
	elseif (pose == "Seated") then
		playAnimation("sit", 0.5, Humanoid)
		return
	elseif (pose == "Running") then
		-- Handled by onRunning
	elseif (pose == "Dead" or pose == "GettingUp" or pose == "FallingDown" or pose == "Seated" or pose == "PlatformStanding") then
		stopAllAnimations()
		amplitude = 0.1
		frequency = 1
		setAngles = true
	end

	if (setAngles) then
		local desiredAngle = amplitude * math.sin(time * frequency)

		RightShoulder:SetDesiredAngle(desiredAngle + climbFudge)
		LeftShoulder:SetDesiredAngle(desiredAngle - climbFudge)
		RightHip:SetDesiredAngle(-desiredAngle)
		LeftHip:SetDesiredAngle(-desiredAngle)
	end

	-- Tool Animation handling
	local tool = getTool()
	if tool and tool:FindFirstChild("Handle") then

		local animStringValueObject = getToolAnim(tool)

		if animStringValueObject then
			toolAnim = animStringValueObject.Value
			-- message recieved, delete StringValue
			animStringValueObject.Parent = nil
			toolAnimTime = time + .3
		end

		if time > toolAnimTime then
			toolAnimTime = 0
			toolAnim = "None"
		end

		animateTool()		
	else
		stopToolAnimations()
		toolAnim = "None"
		toolAnimInstance = nil
		toolAnimTime = 0
	end
end

-- connect events
Humanoid.Died:connect(onDied)
Humanoid.Running:connect(onRunning)
Humanoid.Jumping:connect(onJumping)
Humanoid.Climbing:connect(onClimbing)
Humanoid.GettingUp:connect(onGettingUp)
Humanoid.FreeFalling:connect(onFreeFall)
Humanoid.FallingDown:connect(onFallingDown)
Humanoid.Seated:connect(onSeated)
Humanoid.PlatformStanding:connect(onPlatformStanding)
Humanoid.Swimming:connect(onSwimming)

---- setup emote chat hook
Players.LocalPlayer.Chatted:connect(function(msg)
	local emote = ""
	if msg == "/e dance" then
		emote = dances[math.random(1, #dances)]
	elseif (string.sub(msg, 1, 3) == "/e ") then
		emote = string.sub(msg, 4)
	elseif (string.sub(msg, 1, 7) == "/emote ") then
		emote = string.sub(msg, 8)
	end

	if (pose == "Standing" and emoteNames[emote] ~= nil) then
		playAnimation(emote, 0.1, Humanoid)
	end

end)

-- emote bindable hook
script:WaitForChild("PlayEmote").OnInvoke = function(emote)
	-- Only play emotes when idling
	if pose ~= "Standing" then
		return
	end
	if emoteNames[emote] ~= nil then
		-- Default emotes
		playAnimation(emote, EMOTE_TRANSITION_TIME, Humanoid)

		return true, currentAnimTrack
	end

	-- Return false to indicate that the emote could not be played
	return false
end
-- main program

-- Track last known direction and state for polling
local lastPolledDirection = nil
local lastPolledSprinting = false
local lastPolledCrouching = false
local lastPolledProne = false
local lastPolledDirectional = false -- tracks first-person / shiftlock state

-- initialize to idle
playAnimation("idle", 0.1, Humanoid)
pose = "Standing"

while Figure.Parent ~= nil do
	local _, time = wait(0.1)
	move(time)

	-- Poll for direction/state changes that don't trigger onRunning
	-- (onRunning only fires when SPEED changes, not direction or sprint/crouch state)
	if pose == "Running" or pose == "Standing" then
		local isSprinting = Figure:GetAttribute("IsSprinting") or false
		local isCrouching = Figure:GetAttribute("IsCrouching") or false
		local isProne = Figure:GetAttribute("IsProne") or false
		local currentDir = getMovementDirection()
		local currentDirectional = isDirectionalActive()

		local stateChanged = (isSprinting ~= lastPolledSprinting) or (isCrouching ~= lastPolledCrouching) or (isProne ~= lastPolledProne)
		local directionChanged = (currentDir ~= lastPolledDirection)
		local directionalChanged = (currentDirectional ~= lastPolledDirectional)

		if stateChanged or directionChanged or directionalChanged then
			-- Force re-evaluation by calling onRunning with current speed
			-- Skip if movement anims are locked (e.g. bipod deployed) — onRunning would
			-- short-circuit anyway, but skipping the call entirely is cheaper.
			if not Figure:GetAttribute("MovementAnimsLocked") then
				local speed = HRP.AssemblyLinearVelocity.Magnitude
				if Humanoid.MoveDirection.Magnitude > 0.1 then
					onRunning(math.max(speed, 0.1))
				else
					onRunning(0)
				end
			end
		end

		lastPolledDirection = currentDir
		lastPolledSprinting = isSprinting
		lastPolledCrouching = isCrouching
		lastPolledProne = isProne
		lastPolledDirectional = currentDirectional
	end
end
