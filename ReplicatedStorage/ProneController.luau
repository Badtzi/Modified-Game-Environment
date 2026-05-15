--[[
	ProneController.luau
	Location: ReplicatedStorage > TREK_SERVICES > TREK_Modules

	Client-side prone system:
	  - Yaw scrubbing of 360° rotation animation based on camera direction
	  - CFrame-driven crawl movement (humanoid WalkSpeed is 0 during prone)
	  - 4-way crawl animation selection (stomach, supine, left, right)
	  - Ground snap via spherecast each frame to prevent floor clipping
	  - Leg/torso collision disabled during prone
	  - Entry yaw realignment during movement

	ANIMATION FOLDER (ProneAnimations in TREK_SERVICES):
	  RotationCycle  — 360° prone rotation (required)
	  CrawlStomach   — forward crawl loop (optional)
	  CrawlSupine    — backward crawl loop (optional)
	  CrawlLeft      — left side crawl loop (optional)
	  CrawlRight     — right side crawl loop (optional)
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local ProneController = {}

-- ============================================================
-- CONFIG
-- ============================================================

local REALIGN_SPEED = 1.5
local PRONE_CRAWL_SPEED = 4
local GROUND_SNAP_SPHERE_RADIUS = 1
local GROUND_SNAP_CAST_DISTANCE = 15
local PRONE_HRP_HEIGHT_ABOVE_SURFACE = 1  -- studs above floor for R6 at HipHeight -2

-- ============================================================
-- STATE
-- ============================================================

local active = false
local entryYaw = 0
local currentYawOffset = 0

local rotationTrack = nil
local crawlStomachTrack = nil
local crawlSupineTrack = nil
local crawlLeftTrack = nil
local crawlRightTrack = nil
local activeCrawlTrack = nil

local character = nil
local humanoid = nil
local animator = nil

local renderConnection = nil
local steppedConnection = nil

local savedCollisions = {}

-- ============================================================
-- HELPERS
-- ============================================================

local function normalizeAngle(deg)
	return ((deg % 360) + 360) % 360
end

local function deltaAngle(from, to)
	local diff = (to - from) % 360
	if diff > 180 then diff -= 360 end
	return diff
end

local function getCameraYawDeg()
	local camLook = workspace.CurrentCamera.CFrame.LookVector
	return math.deg(math.atan2(-camLook.X, -camLook.Z))
end

-- ============================================================
-- COLLISION MANAGEMENT
-- ============================================================

local function disableBodyCollisions(chr)
	savedCollisions = {}
	local partsToDisable = {"Left Leg", "Right Leg", "Torso"}
	for _, partName in ipairs(partsToDisable) do
		local part = chr:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			savedCollisions[partName] = part.CanCollide
			part.CanCollide = false
		end
	end
end

local function restoreBodyCollisions(chr)
	for partName, wasCollidable in pairs(savedCollisions) do
		local part = chr:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.CanCollide = wasCollidable
		end
	end
	savedCollisions = {}
end

-- ============================================================
-- GROUND SNAP
-- Spherecast down from above HRP each frame to keep character
-- at correct height. Prevents floor clipping after falling off
-- ledges or landing from dives.
-- ============================================================

local function snapToGround()
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {character, workspace:FindFirstChild("IgnoreList")}
	rayParams.IgnoreWater = true

	local origin = hrp.Position + Vector3.new(0, 3, 0)
	local result = workspace:Spherecast(origin, GROUND_SNAP_SPHERE_RADIUS, Vector3.new(0, -GROUND_SNAP_CAST_DISTANCE, 0), rayParams)

	if result then
		local targetY = result.Position.Y + PRONE_HRP_HEIGHT_ABOVE_SURFACE
		local currentY = hrp.Position.Y

		-- Only snap if we're below the target (clipping into floor) or significantly
		-- above it (fell off a ledge and need to settle). Small differences are
		-- ignored to prevent jitter.
		local diff = currentY - targetY
		if diff < -0.1 or diff > 0.5 then
			local pos = hrp.Position
			hrp.CFrame = CFrame.new(pos.X, targetY, pos.Z) * hrp.CFrame.Rotation
			-- Kill vertical velocity to prevent bouncing
			hrp.AssemblyLinearVelocity = Vector3.new(
				hrp.AssemblyLinearVelocity.X,
				0,
				hrp.AssemblyLinearVelocity.Z
			)
		end
	end
end

-- ============================================================
-- ANIMATION LOADING
-- ============================================================

local function loadAnimations()
	if not humanoid then
		warn("[ProneController] No humanoid")
		return false
	end

	animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local proneAnims = shared.S.ProneAnimations
	if not proneAnims then
		local trekServices = game:GetService("ReplicatedStorage"):FindFirstChild("TREK_SERVICES")
		if trekServices then
			proneAnims = trekServices:FindFirstChild("ProneAnimations")
		end
	end
	if not proneAnims then
		warn("[ProneController] ProneAnimations not found")
		return false
	end

	print("[ProneController] Found ProneAnimations folder:", proneAnims:GetFullName())

	-- Load rotation cycle (required)
	local rotAnim = proneAnims:FindFirstChild("RotationCycle")
	if not rotAnim or not rotAnim:IsA("Animation") then
		warn("[ProneController] RotationCycle animation instance not found")
		return false
	end

	print("[ProneController] Loading RotationCycle, AnimationId:", rotAnim.AnimationId)

	local ok, track = pcall(function()
		return animator:LoadAnimation(rotAnim)
	end)

	if not ok or not track then
		warn("[ProneController] Failed to load RotationCycle:", track)
		return false
	end

	rotationTrack = track
	rotationTrack.Priority = Enum.AnimationPriority.Movement
	rotationTrack.Looped = false

	if rotationTrack.Length == 0 then
		print("[ProneController] Track length is 0, waiting for load...")
		local waited = 0
		while rotationTrack.Length == 0 and waited < 3 do
			task.wait(0.1)
			waited += 0.1
		end
	end

	print("[ProneController] RotationCycle loaded, Length:", rotationTrack.Length)

	-- Load crawl animations (all optional — prone works without them)
	local function loadCrawl(name)
		local anim = proneAnims:FindFirstChild(name)
		if anim and anim:IsA("Animation") then
			local success, t = pcall(function() return animator:LoadAnimation(anim) end)
			if success and t then
				t.Priority = Enum.AnimationPriority.Movement
				t.Looped = true
				return t
			end
		end
		return nil
	end

	crawlStomachTrack = loadCrawl("CrawlStomach")
	crawlSupineTrack  = loadCrawl("CrawlSupine")
	crawlLeftTrack    = loadCrawl("CrawlLeft")
	crawlRightTrack   = loadCrawl("CrawlRight")

	return true
end

local function unloadAnimations()
	local function safeStop(track)
		if track then
			pcall(function() track:Stop(0.2) end)
			pcall(function() track:Destroy() end)
		end
	end

	safeStop(rotationTrack); rotationTrack = nil
	safeStop(crawlStomachTrack); crawlStomachTrack = nil
	safeStop(crawlSupineTrack); crawlSupineTrack = nil
	safeStop(crawlLeftTrack); crawlLeftTrack = nil
	safeStop(crawlRightTrack); crawlRightTrack = nil
	activeCrawlTrack = nil
	animator = nil
end

-- ============================================================
-- 4-WAY CRAWL ANIMATION SELECTION
-- Determines which crawl to play based on yaw offset AND
-- movement direction relative to camera.
-- ============================================================

local function updateCrawlAnimation(isMoving, yawOffsetDeg, moveDir)
	if not isMoving then
		if activeCrawlTrack and activeCrawlTrack.IsPlaying then
			activeCrawlTrack:Stop(0.2)
			activeCrawlTrack = nil
		end
		return
	end

	-- Determine movement direction relative to camera
	local cam = workspace.CurrentCamera
	if not cam then return end

	local camForward = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
	if camForward.Magnitude < 0.01 then return end
	camForward = camForward.Unit
	local camRight = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z).Unit

	local forwardDot = moveDir:Dot(camForward)
	local rightDot = moveDir:Dot(camRight)

	-- Pick crawl based on dominant movement direction
	local desiredTrack = nil
	if math.abs(forwardDot) >= math.abs(rightDot) then
		-- Moving forward or backward
		local absOffset = normalizeAngle(yawOffsetDeg)
		local isFacingForward = (absOffset <= 90) or (absOffset >= 270)

		if forwardDot > 0.1 then
			-- Moving forward: stomach crawl if facing forward, supine if facing back
			desiredTrack = isFacingForward and crawlStomachTrack or crawlSupineTrack
		else
			-- Moving backward: supine if facing forward, stomach if facing back
			desiredTrack = isFacingForward and crawlSupineTrack or crawlStomachTrack
		end
	else
		-- Moving sideways
		if rightDot > 0.1 then
			desiredTrack = crawlRightTrack or crawlStomachTrack
		else
			desiredTrack = crawlLeftTrack or crawlStomachTrack
		end
	end

	-- Fall back to stomach if desired track doesn't exist
	if not desiredTrack then
		desiredTrack = crawlStomachTrack
	end

	if desiredTrack and desiredTrack ~= activeCrawlTrack then
		if activeCrawlTrack and activeCrawlTrack.IsPlaying then
			activeCrawlTrack:Stop(0.2)
		end
		desiredTrack:Play(0.2)
		activeCrawlTrack = desiredTrack
	end
end

-- ============================================================
-- INPUT-BASED MOVEMENT DIRECTION
-- ============================================================

local function getInputMoveDirection()
	local cam = workspace.CurrentCamera
	if not cam then return Vector3.zero end

	local forward = 0
	local right = 0

	if UserInputService:IsKeyDown(Enum.KeyCode.W) then forward += 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then forward -= 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then right += 1 end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then right -= 1 end

	if forward == 0 and right == 0 then return Vector3.zero end

	local camCF = cam.CFrame
	local camForward = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
	if camForward.Magnitude < 0.01 then return Vector3.zero end
	camForward = camForward.Unit

	local camRight = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z)
	if camRight.Magnitude < 0.01 then return Vector3.zero end
	camRight = camRight.Unit

	return (camForward * forward + camRight * right).Unit
end

-- ============================================================
-- RENDER LOOP (animation scrubbing)
-- ============================================================

local function onRenderStepped(dt)
	if not active then return end
	if not character or not character.Parent then return end

	local cameraYawDeg = getCameraYawDeg()
	local entryYawDeg = math.deg(entryYaw)
	local yawOffsetDeg = normalizeAngle(cameraYawDeg - entryYawDeg)

	local moveDir = getInputMoveDirection()
	local isMoving = moveDir.Magnitude > 0.01

	-- During movement, slowly realign entry yaw toward camera yaw
	if isMoving then
		local delta = deltaAngle(entryYawDeg, cameraYawDeg)
		local maxStep = REALIGN_SPEED * dt * 60
		if math.abs(delta) > maxStep then
			entryYaw = math.rad(entryYawDeg + math.sign(delta) * maxStep)
		end
		yawOffsetDeg = normalizeAngle(getCameraYawDeg() - math.deg(entryYaw))
	end

	-- Scrub rotation cycle
	if rotationTrack and rotationTrack.Length > 0 then
		local normalizedTime = (yawOffsetDeg / 360) * rotationTrack.Length
		rotationTrack.TimePosition = normalizedTime
	end

	-- Update crawl animation (4-way: forward, backward, left, right)
	updateCrawlAnimation(isMoving, yawOffsetDeg, moveDir)

	-- Replicate
	character:SetAttribute("ProneYawOffset", yawOffsetDeg)
end

-- ============================================================
-- STEPPED LOOP (physics: movement + collision + ground snap)
-- ============================================================

local function onStepped(dt)
	if not active then return end
	if not character or not character.Parent then return end

	-- Re-enforce collision disable (Roblox resets CanCollide on humanoid parts)
	for partName, _ in pairs(savedCollisions) do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.CanCollide = false
		end
	end

	-- Ground snap: only when the character has landed (vertical velocity near zero).
	-- While falling, let physics handle the descent naturally. Once landed, snap
	-- to correct height to fix any floor clipping from the landing.
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		local verticalSpeed = math.abs(hrp.AssemblyLinearVelocity.Y)
		if verticalSpeed < 2 then
			snapToGround()
		end
	end

	-- CFrame-driven movement
	local moveDir = getInputMoveDirection()
	if moveDir.Magnitude > 0.01 then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.CFrame = hrp.CFrame + moveDir * PRONE_CRAWL_SPEED * dt
		end
	end
end

-- ============================================================
-- PUBLIC API
-- ============================================================

function ProneController.enter(chr, hum)
	if active then return end

	character = chr
	humanoid = hum

	print("[ProneController] Entering prone")

	if not loadAnimations() then
		warn("[ProneController] Failed to load animations, prone visual disabled")
	end

	disableBodyCollisions(chr)

	local camLook = workspace.CurrentCamera.CFrame.LookVector
	local cameraYaw = math.atan2(-camLook.X, -camLook.Z)

	local startOffset = 0
	local forcedOffset = chr:GetAttribute("ProneEntryOffset")
	local moveDir = getInputMoveDirection()

	if forcedOffset ~= nil then
		startOffset = forcedOffset
	elseif moveDir.Magnitude > 0.01 then
		local cam = workspace.CurrentCamera
		local camForward = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
		if camForward.Magnitude > 0.01 then
			camForward = camForward.Unit
			local camRight = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z).Unit

			local forwardDot = moveDir:Dot(camForward)
			local rightDot = moveDir:Dot(camRight)

			if math.abs(forwardDot) >= math.abs(rightDot) then
				if forwardDot < -0.1 then
					startOffset = 180
				end
			else
				if rightDot > 0.1 then
					startOffset = 90
				else
					startOffset = 270
				end
			end
		end
	end

	entryYaw = cameraYaw - math.rad(startOffset)
	currentYawOffset = startOffset

	if rotationTrack then
		rotationTrack:Play(0.2)
		rotationTrack:AdjustSpeed(0)
		if rotationTrack.Length > 0 then
			rotationTrack.TimePosition = (startOffset / 360) * rotationTrack.Length
		end
		print("[ProneController] RotationCycle playing at offset:", startOffset, "degrees, Length:", rotationTrack.Length)
	end

	character:SetAttribute("ProneActive", true)
	character:SetAttribute("ProneYawOffset", startOffset)

	active = true

	if renderConnection then renderConnection:Disconnect() end
	renderConnection = RunService.RenderStepped:Connect(onRenderStepped)

	if steppedConnection then steppedConnection:Disconnect() end
	steppedConnection = RunService.Stepped:Connect(function(_, dt)
		onStepped(dt)
	end)
end

function ProneController.exit(chr, hum)
	if not active then return end

	print("[ProneController] Exiting prone")

	active = false

	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	if steppedConnection then
		steppedConnection:Disconnect()
		steppedConnection = nil
	end

	unloadAnimations()

	if character then
		restoreBodyCollisions(character)
	end

	if character then
		character:SetAttribute("ProneActive", false)
		character:SetAttribute("ProneYawOffset", nil)
	end

	character = nil
	humanoid = nil
end

function ProneController.isActive()
	return active
end

function ProneController.applyRemoteYaw(remoteCharacter, yawOffsetDeg)
end

return ProneController
