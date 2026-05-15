--[[
	AnimEventHandler
	Place in: ReplicatedStorage > TREK_SERVICES > TREK_Modules
	
	Listens for named animation events (set in Moon Animator 2's event keyframes)
	and triggers camera shakes or mag drops at the exact frame.
	
	USAGE:
		local AnimEvents = require(shared.S.TREK_Modules:WaitForChild("AnimEventHandler"))
		
		local track = humanoid:LoadAnimation(anim)
		AnimEvents.hook(track, tool)  -- tool is optional, only needed for MagDrop
		track:Play()
	
	EVENT NAMES TO TYPE IN MOON ANIMATOR'S "Edit Events" FIELD:
	
	Camera Shakes:
		Shake_Light          Gentle bump (mag 1, rough 3)
		Shake_Medium         Standard bump (mag 2.5, rough 4)
		Shake_Heavy          Hard slam (mag 5, rough 6)
		Shake_GunRecoil      Uses existing GunRecoil preset
		Shake_Bump           Uses existing Bump preset
		Shake_2.5_4_0.1_0.3 Custom: magnitude_roughness_fadeIn_fadeOut
	
	Magazine Drop:
		MagDrop              Clones "Magazine" part from tool with physics
		MagDrop_CustomName   Clones a part named "CustomName" instead
]]

local Debris = game:GetService("Debris")

local CameraShaker = require(script.Parent:WaitForChild("CameraShaker"))

-- Dedicated shaker instance for animation events
local camShake = CameraShaker.new(Enum.RenderPriority.Camera.Value, function(shakeCf)
	workspace.CurrentCamera.CFrame = workspace.CurrentCamera.CFrame * shakeCf
end)
camShake:Start()

local AnimEventHandler = {}

------------------------------------------------------------------------
-- SHAKE PRESETS
------------------------------------------------------------------------

local SHAKE_PRESETS = {
	Light  = { Magnitude = 1,   Roughness = 3, FadeIn = 0.05, FadeOut = 0.15 },
	Medium = { Magnitude = 2.5, Roughness = 4, FadeIn = 0.05, FadeOut = 0.2  },
	Heavy  = { Magnitude = 5,   Roughness = 6, FadeIn = 0.02, FadeOut = 0.25 },
}

-- Named presets from CameraShakePresets module
local NAMED_PRESETS = {
	GunRecoil = true,
	Bump = true,
	smallExplosion = true,
	mediumExplosion = true,
	bigExplosion = true,
}

local function handleShake(eventParam: string)
	-- Simple presets (Light, Medium, Heavy)
	if SHAKE_PRESETS[eventParam] then
		local p = SHAKE_PRESETS[eventParam]
		camShake:ShakeOnce(p.Magnitude, p.Roughness, p.FadeIn, p.FadeOut)
		return
	end

	-- Named CameraShakePresets
	if NAMED_PRESETS[eventParam] then
		local presetInstance = CameraShaker.Presets[eventParam]
		if presetInstance then
			camShake:Shake(presetInstance)
		end
		return
	end

	-- Custom numbers: magnitude_roughness_fadeIn_fadeOut
	local parts = string.split(eventParam, "_")
	if #parts >= 2 then
		local mag = tonumber(parts[1])
		local rough = tonumber(parts[2])
		local fadeIn = tonumber(parts[3]) or 0.05
		local fadeOut = tonumber(parts[4]) or 0.2
		if mag and rough then
			camShake:ShakeOnce(mag, rough, fadeIn, fadeOut)
			return
		end
	end

	warn("[AnimEventHandler] Unknown shake preset: " .. eventParam)
end

------------------------------------------------------------------------
-- MAG DROP
------------------------------------------------------------------------

local function handleMagDrop(tool: Tool?, partName: string?)
	if not tool then
		warn("[AnimEventHandler] MagDrop requires a tool reference")
		return
	end

	local magName = partName or "Magazine"
	local originalMag = tool:FindFirstChild(magName, true)
	if not originalMag or not originalMag:IsA("BasePart") then
		warn("[AnimEventHandler] MagDrop: Could not find part '" .. magName .. "' in tool")
		return
	end

	-- Clone the magazine at its current world position
	local clone = originalMag:Clone()

	-- Remove any joints so it's free
	for _, child in ipairs(clone:GetDescendants()) do
		if child:IsA("JointInstance") or child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end

	-- Configure physics
	clone.CanCollide = true
	clone.CanQuery = false
	clone.CanTouch = false
	clone.Anchored = false
	clone.CFrame = originalMag.CFrame
	clone.Name = "DroppedMag"

	-- Parent to IgnoreList so it doesn't block bullets
	local ignoreList = workspace:FindFirstChild("IgnoreList")
	clone.Parent = ignoreList or workspace

	-- Slight downward + random sideways impulse
	clone:ApplyImpulse(Vector3.new(
		math.random(-20, 20) / 10,
		-2,
		math.random(-20, 20) / 10
		))

	-- Random spin
	clone:ApplyAngularImpulse(Vector3.new(
		math.random(-5, 5),
		math.random(-5, 5),
		math.random(-5, 5)
		))

	-- Clean up after a few seconds
	Debris:AddItem(clone, 8)
end

------------------------------------------------------------------------
-- EVENT ROUTER
-- Moon Animator fires events through KeyframeReached, not
-- GetMarkerReachedSignal. This function parses the keyframe
-- name and routes to the correct handler.
------------------------------------------------------------------------

local function onEventFired(eventName: string, tool: Tool?)
	-- Check for exact "MagDrop" (no underscore)
	if eventName == "MagDrop" then
		handleMagDrop(tool, nil)
		return
	end

	-- Skip the standard "End" keyframe
	if eventName == "End" then return end

	-- Parse "Prefix_Param" format
	local prefix, param = string.match(eventName, "^(%w+)_(.+)$")
	if not prefix then return end

	if prefix == "Shake" then
		handleShake(param)
	elseif prefix == "MagDrop" then
		handleMagDrop(tool, param)
	end
end

------------------------------------------------------------------------
-- PUBLIC API
------------------------------------------------------------------------

--[[
	AnimEventHandler.hook(track: AnimationTrack, tool: Tool?)
	
	Connects to the track's KeyframeReached signal (used by Moon Animator
	for animation events). Routes events to shake/magdrop handlers.
	
	Returns a cleanup function that disconnects the listener.
]]

function AnimEventHandler.hook(track: AnimationTrack, tool: Tool?): () -> ()
	local connection = track.KeyframeReached:Connect(function(frameName)
		onEventFired(frameName, tool)
	end)

	return function()
		if connection then
			connection:Disconnect()
		end
	end
end

return AnimEventHandler
