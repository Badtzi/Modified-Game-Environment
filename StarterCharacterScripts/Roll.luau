local Character = script.Parent
local Humanoid = Character:WaitForChild("Humanoid")
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local TweenService = game:GetService("TweenService")

local PlrConfig = Character:WaitForChild("TREK_PlrConfig")
local Crouching = PlrConfig:WaitForChild("Crouching")

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local smoothShiftLock = require(
	player:WaitForChild("PlayerScripts")
		:WaitForChild("CustomShiftLock")
		:WaitForChild("SmoothShiftLock")
)

local controls = require(script.Parent:WaitForChild("OneLifeScripts"):WaitForChild("ControlsModule"))

-- AnimEventHandler for camera shake events on dive animations
local AnimEvents
pcall(function()
	AnimEvents = require(shared.S.TREK_Modules:WaitForChild("AnimEventHandler", 5))
end)

local SideGyro = Instance.new("BodyGyro")
SideGyro.MaxTorque = Vector3.new(3e5, 0, 3e5)
SideGyro.P = 5e5
SideGyro.Parent = HumanoidRootPart

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Dashing = false
local DashSpeed = 15

local DashCooldown = 1.5
local LastDashTime = -math.huge

local HeldMoveKeys = {
	[Enum.KeyCode.W] = false,
	[Enum.KeyCode.A] = false,
	[Enum.KeyCode.S] = false,
	[Enum.KeyCode.D] = false,
}
local LastMoveKey = nil

local DashSoundId = "rbxassetid://135583829075949"

local Animations = {
	["DashRight"] = "rbxassetid://74015622139906",
	["DashLeft"] = "rbxassetid://75228870780207",
	["DashFront"] = "rbxassetid://125300830602008",
	["DashBack"] = "rbxassetid://101939088931071",
}

for i, v in pairs(Animations) do
	local animObj = Instance.new("Animation")
	animObj.AnimationId = v

	local track = Humanoid:LoadAnimation(animObj)
	track.Priority = Enum.AnimationPriority.Movement
	track.Looped = false
	track:AdjustWeight(0.35, 0)

	-- Hook animation events (camera shakes on landing frame, etc.)
	if AnimEvents then
		pcall(function() AnimEvents.hook(track) end)
	end

	Animations[i] = track
end

local DASH_TO_PRONE_OFFSET = {
	Front = 0,
	Back  = 180,
	Left  = 270,
	Right = 90,
}

local GROUND_SNAP_SPHERE_RADIUS = 1
local GROUND_SNAP_CAST_DISTANCE = 15
local SETTLE_FRAMES = 3

-- Prone HipHeight target (must match ControlsModule.startProne)
local PRONE_HIP_HEIGHT = -2

local function GetHeldDirectionKey()
	if LastMoveKey and HeldMoveKeys[LastMoveKey] then
		return LastMoveKey
	end

	if HeldMoveKeys[Enum.KeyCode.W] then return Enum.KeyCode.W end
	if HeldMoveKeys[Enum.KeyCode.A] then return Enum.KeyCode.A end
	if HeldMoveKeys[Enum.KeyCode.S] then return Enum.KeyCode.S end
	if HeldMoveKeys[Enum.KeyCode.D] then return Enum.KeyCode.D end

	return nil
end

local function PlayDashSound()
	local DashSound = Instance.new("Sound")
	DashSound.SoundId = DashSoundId
	DashSound.Volume = 1
	DashSound.PlayOnRemove = false
	DashSound.Parent = HumanoidRootPart
	DashSound:Play()

	game.Debris:AddItem(DashSound, 2)
end

local function SpawnDashEffect(DashAnim)
	task.wait(.1)

	local DashEffect = game.ReplicatedStorage.DustTrail:Clone()
	DashEffect.Parent = workspace

	if DashAnim == "Left" then
		if DashEffect:FindFirstChild("DustRight") then
			DashEffect.DustRight:Destroy()
		end
		DashEffect.CFrame = Character["Right Leg"].CFrame * CFrame.new(-1, 0, -2)
	elseif DashAnim == "Right" then
		if DashEffect:FindFirstChild("DustLeft") then
			DashEffect.DustLeft:Destroy()
		end
		DashEffect.CFrame = Character["Left Leg"].CFrame * CFrame.new(3, 2, 5)
	elseif DashAnim == "Front" then
		if DashEffect:FindFirstChild("DustLeft") then
			DashEffect.DustLeft:Destroy()
		end
		DashEffect.CFrame = Character.HumanoidRootPart.CFrame * CFrame.new(0, -1, 3)
	else
		if DashEffect:FindFirstChild("DustLeft") then
			DashEffect.DustLeft:Destroy()
		end
		DashEffect.CFrame = Character.HumanoidRootPart.CFrame * CFrame.new(0, -1, -.5)
	end

	for _, v in pairs(DashEffect:GetDescendants()) do
		if v:IsA("ParticleEmitter") then
			v:Emit(5)
		end
	end

	game.Debris:AddItem(DashEffect, .5)
end

-- Smoothly tween HipHeight over the full duration of the dive animation
local function tweenHipHeight(animTrack)
	local duration = (animTrack and animTrack.Length > 0) and animTrack.Length or 0.5
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(Humanoid, tweenInfo, {HipHeight = PRONE_HIP_HEIGHT})
	tween:Play()
end

local function snapToGround()
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {Character, workspace:FindFirstChild("IgnoreList")}
	rayParams.IgnoreWater = true

	local origin = HumanoidRootPart.Position + Vector3.new(0, 3, 0)
	local result = workspace:Spherecast(origin, GROUND_SNAP_SPHERE_RADIUS, Vector3.new(0, -GROUND_SNAP_CAST_DISTANCE, 0), rayParams)

	if result then
		local targetY = result.Position.Y + 1
		local pos = HumanoidRootPart.Position
		HumanoidRootPart.CFrame = CFrame.new(pos.X, targetY, pos.Z) * HumanoidRootPart.CFrame.Rotation
	end
end

local function enterProneAfterDive(dashDirection)
	-- Set IsProne immediately so Animate.luau stops playing idle/walk anims
	Character:SetAttribute("IsProne", true)

	-- Brief settle
	for i = 1, SETTLE_FRAMES do
		task.wait()
	end

	-- Kill all velocity
	HumanoidRootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	HumanoidRootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

	-- Set directional offset for ProneController
	Character:SetAttribute("ProneEntryOffset", DASH_TO_PRONE_OFFSET[dashDirection] or 0)
	controls.startProne()
	Character:SetAttribute("ProneEntryOffset", nil)

	-- Ground snap after prone activates
	task.wait()
	snapToGround()
end

function Dash(Key)
	if Crouching.Value then return end
	if Character:GetAttribute("IsProne") then return end

	if (tick() - LastDashTime) < DashCooldown then return end
	if Dashing then return end

	local DashAnim = "Back"
	local Front = -1
	local Side = 0

	if Key == Enum.KeyCode.A then
		Side = -1
		Front = 0
		DashAnim = "Left"
	end

	if Key == Enum.KeyCode.D then
		Side = 1
		Front = 0
		DashAnim = "Right"
	end

	if Key == Enum.KeyCode.W then
		Side = 0
		Front = 1
		DashAnim = "Front"
	end

	if Key == Enum.KeyCode.S then
		Side = 0
		Front = -1
		DashAnim = "Back"
	end

	PlayDashSound()

	Dashing = true
	LastDashTime = tick()
	Animations["Dash" .. DashAnim]:Play()

	-- Start smoothly lowering HipHeight over the dive animation's full duration
	tweenHipHeight(Animations["Dash" .. DashAnim])

	local DashVelocity = Instance.new("BodyVelocity")
	DashVelocity.MaxForce = Vector3.new(math.huge, 0, math.huge)
	DashVelocity.P = 9e9
	DashVelocity.Parent = HumanoidRootPart
	DashVelocity.Velocity =
		HumanoidRootPart.CFrame.LookVector * (Front * DashSpeed) +
		HumanoidRootPart.CFrame.RightVector * (Side * DashSpeed)

	coroutine.wrap(function()
		SpawnDashEffect(DashAnim)
	end)()

	repeat
		task.wait()
		DashVelocity.Velocity =
			HumanoidRootPart.CFrame.LookVector * (Front * DashSpeed) +
			HumanoidRootPart.CFrame.RightVector * (Side * DashSpeed)
	until not Animations["Dash" .. DashAnim].IsPlaying

	DashVelocity:Destroy()
	Dashing = false

	enterProneAfterDive(DashAnim)
end

function DashNoShiftLock(Key)
	if Crouching.Value then return end
	if Character:GetAttribute("IsProne") then return end

	if (tick() - LastDashTime) < DashCooldown then return end
	if Dashing then return end

	local DashAnim = "Front"
	local Front = 1
	local Side = 0

	if Key == Enum.KeyCode.W then
		Front = 1; Side = 0; DashAnim = "Front"
	end
	if Key == Enum.KeyCode.A then
		Front = 1; Side = 0; DashAnim = "Front"
	end
	if Key == Enum.KeyCode.S then
		Front = 1; Side = 0; DashAnim = "Front"
	end
	if Key == Enum.KeyCode.D then
		Front = 1; Side = 0; DashAnim = "Front"
	end

	PlayDashSound()

	Dashing = true
	LastDashTime = tick()
	Animations["Dash" .. DashAnim]:Play()

	-- Start smoothly lowering HipHeight over the dive animation's full duration
	tweenHipHeight(Animations["Dash" .. DashAnim])

	local DashVelocity = Instance.new("BodyVelocity")
	DashVelocity.MaxForce = Vector3.new(math.huge, 0, math.huge)
	DashVelocity.P = 9e9
	DashVelocity.Parent = HumanoidRootPart
	DashVelocity.Velocity =
		HumanoidRootPart.CFrame.LookVector * (Front * DashSpeed) +
		HumanoidRootPart.CFrame.RightVector * (Side * DashSpeed)

	coroutine.wrap(function()
		SpawnDashEffect(DashAnim)
	end)()

	repeat
		task.wait()
		DashVelocity.Velocity =
			HumanoidRootPart.CFrame.LookVector * (Front * DashSpeed) +
			HumanoidRootPart.CFrame.RightVector * (Side * DashSpeed)
	until not Animations["Dash" .. DashAnim].IsPlaying

	DashVelocity:Destroy()
	Dashing = false

	enterProneAfterDive(DashAnim)
end

UserInputService.InputBegan:Connect(function(input, Typing)
	if Typing then return end

	if HeldMoveKeys[input.KeyCode] ~= nil then
		HeldMoveKeys[input.KeyCode] = true
		LastMoveKey = input.KeyCode
		return
	end

	if input.KeyCode == Enum.KeyCode.LeftAlt then
		local dirKey = GetHeldDirectionKey()
		if dirKey then
			if smoothShiftLock:IsEnabled() then
				Dash(dirKey)
			else
				DashNoShiftLock(dirKey)
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, Typing)
	if HeldMoveKeys[input.KeyCode] ~= nil then
		HeldMoveKeys[input.KeyCode] = false
	end
end)
