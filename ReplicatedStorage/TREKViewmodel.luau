--!strict
--[[
	TREKViewmodel — First-person viewmodel with procedural spring recoil.
	DEBUG VERSION — contains diagnostic prints for troubleshooting recoil.
	Remove lines marked "-- DEBUG" once working.
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Spring = require(script.Parent:WaitForChild("Spring"))

local DEFAULT_FOV = workspace.CurrentCamera.FieldOfView
local HIP_OFFSET = CFrame.new(0, -1.55, -0.2)
local AIM_OFFSET_FALLBACK = CFrame.new(-0.85, -1.2, 0.2)
local SWAY_SMOOTH_SPEED = 8
local BOB_SMOOTH_SPEED = 10

local currentOffset = HIP_OFFSET
local swayOffset = CFrame.new()
local bobOffset = CFrame.new()
local aimAlpha = 0
local tiltAngle = 0
local smoothedRotation: CFrame? = nil
local wasFirstPerson = false

local RecoilRotation = Spring.New(Vector3.new())
RecoilRotation.Speed = 6
RecoilRotation.Damper = 0.45

local RecoilPosition = Spring.New(Vector3.new())
RecoilPosition.Speed = 8
RecoilPosition.Damper = 0.5

local function resetSpring(spring)
	spring.Position = Vector3.new()
	spring.Velocity = 0 * Vector3.new()
end

local Viewmodel = {}
Viewmodel.IsFirstPerson = false
Viewmodel.Scoped = false
Viewmodel.LastReplicate = 0
Viewmodel.MotorCache = {}
Viewmodel.RigVisibleParts = {}
Viewmodel.RealToolParts = {}
Viewmodel.VmToolParts = {}
Viewmodel.PhysicsParts = {}

Viewmodel.checkFirstPerson = function(): boolean
	local cam = workspace.CurrentCamera
	if not cam then return false end
	return (cam.CFrame.Position - cam.Focus.Position).Magnitude < 1.5
end

Viewmodel.applyRecoil = function(rotationImpulse: Vector3, positionImpulse: Vector3?)
	print("[RECOIL] applyRecoil called! rotation:", rotationImpulse, "position:", positionImpulse) -- DEBUG
	RecoilRotation:Impulse(rotationImpulse)
	if positionImpulse then
		RecoilPosition:Impulse(positionImpulse)
	end
end

------------------------------------------------------------------------
-- EQUIP
------------------------------------------------------------------------

Viewmodel.equip = function(tool: Tool, character: Model)
	Viewmodel.unequip()
	Viewmodel.RealTool = tool
	local cam = workspace.CurrentCamera

	local savedArchivable = character.Archivable
	character.Archivable = true
	local rig = character:Clone()
	character.Archivable = savedArchivable
	rig.Name = "TREK_Viewmodel"

	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		for _, state in ipairs(Enum.HumanoidStateType:GetEnumItems()) do
			if state ~= Enum.HumanoidStateType.None and state ~= Enum.HumanoidStateType.Dead then
				pcall(function() humanoid:SetStateEnabled(state, false) end)
			end
		end
	end

	local hrp = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	if hrp then
		hrp.Anchored = true
		Viewmodel.VmHRP = hrp
		if not hrp:FindFirstChild("RootJoint") then
			local rootJoint = Instance.new("Motor6D")
			rootJoint.Name = "RootJoint"
			rootJoint.Part0 = hrp
			local torso = rig:FindFirstChild("Torso") :: BasePart
			local upperTorso = rig:FindFirstChild("UpperTorso") :: BasePart
			rootJoint.Part1 = torso or upperTorso
			rootJoint.Parent = hrp
		end
	end

	for _, child in ipairs(rig:GetChildren()) do
		if child:IsA("Model") and string.find(child.Name, "Holster") then child:Destroy() end
		if child:IsA("Model") and string.sub(child.Name, 1, 9) == "Backpack_" then child:Destroy() end
	end

	for _, descendant in ipairs(rig:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			descendant.Massless = true
			if descendant.Name ~= "HumanoidRootPart" then descendant.Anchored = false end
			table.insert(Viewmodel.PhysicsParts, descendant)
			local isCorePart = descendant.Name == "Head" or string.match(descendant.Name, "Leg") or string.match(descendant.Name, "Torso") or descendant.Name == "HumanoidRootPart"
			if isCorePart then
				descendant.Transparency = 1
				descendant.LocalTransparencyModifier = 1
			else
				table.insert(Viewmodel.RigVisibleParts, descendant)
			end
		elseif descendant:IsA("Decal") or descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("Accessory") or descendant:IsA("Tool") then
			descendant:Destroy()
		end
	end

	local vmTool = tool:Clone()
	local realDescendants = tool:GetDescendants()
	local vmDescendants = vmTool:GetDescendants()
	for i, vmDesc in ipairs(vmDescendants) do
		if vmDesc:IsA("Motor6D") then
			local realMotor = realDescendants[i]
			if realMotor and realMotor:IsA("Motor6D") then
				table.insert(Viewmodel.MotorCache, { Real = realMotor, VM = vmDesc, ExcludeC0 = false })
				if realMotor.Part0 then
					if realMotor.Part0:IsDescendantOf(tool) then
						local idx = table.find(realDescendants, realMotor.Part0)
						if idx then vmDesc.Part0 = vmDescendants[idx] :: BasePart end
					else vmDesc.Part0 = rig:FindFirstChild(realMotor.Part0.Name, true) :: BasePart end
				end
				if realMotor.Part1 then
					if realMotor.Part1:IsDescendantOf(tool) then
						local idx = table.find(realDescendants, realMotor.Part1)
						if idx then vmDesc.Part1 = vmDescendants[idx] :: BasePart end
					else vmDesc.Part1 = rig:FindFirstChild(realMotor.Part1.Name, true) :: BasePart end
				end
			end
		end
	end

	for _, vmDesc in ipairs(vmTool:GetDescendants()) do
		if vmDesc:IsA("Script") or vmDesc:IsA("LocalScript") then vmDesc:Destroy()
		elseif vmDesc:IsA("BasePart") then
			vmDesc.CanCollide = false; vmDesc.CanQuery = false; vmDesc.Massless = true; vmDesc.Anchored = false
			table.insert(Viewmodel.VmToolParts, vmDesc)
			table.insert(Viewmodel.PhysicsParts, vmDesc)
		end
	end

	for _, realDesc in ipairs(tool:GetDescendants()) do
		if realDesc:IsA("BasePart") then table.insert(Viewmodel.RealToolParts, realDesc) end
	end

	vmTool.Parent = rig
	Viewmodel.ViewmodelTool = vmTool
	Viewmodel.RealToolAddedConn = tool.DescendantAdded:Connect(function(desc) if desc:IsA("BasePart") then table.insert(Viewmodel.RealToolParts, desc) end end)
	Viewmodel.RigAddedConn = rig.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") then
			desc.CanCollide = false; desc.CanTouch = false; desc.Massless = true; desc.Anchored = false
			table.insert(Viewmodel.PhysicsParts, desc)
			local isCorePart = desc.Name == "Head" or string.match(desc.Name, "Leg") or string.match(desc.Name, "Torso") or desc.Name == "HumanoidRootPart"
			if not isCorePart then table.insert(Viewmodel.RigVisibleParts, desc) end
		end
	end)

	local realTorso = character:FindFirstChild("Torso") :: BasePart or character:FindFirstChild("UpperTorso") :: BasePart
	local realToolMotor = realTorso and realTorso:FindFirstChild("toolAnim") :: Motor6D
	local vmTorso = rig:FindFirstChild("Torso") :: BasePart or rig:FindFirstChild("UpperTorso") :: BasePart
	if vmTorso then local old = vmTorso:FindFirstChild("toolAnim"); if old then old:Destroy() end end
	local vmAnimPart = vmTool:FindFirstChild("AnimPart") :: BasePart
	if vmTorso and vmAnimPart and realToolMotor then
		local m = Instance.new("Motor6D"); m.Name = "toolAnim"; m.Part0 = vmTorso; m.Part1 = vmAnimPart; m.C0 = realToolMotor.C0; m.C1 = realToolMotor.C1; m.Parent = vmTorso
	end

	for _, realDesc in ipairs(character:GetDescendants()) do
		if realDesc:IsA("Motor6D") and not realDesc:IsDescendantOf(tool) then
			local vmMotor = rig:FindFirstChild(realDesc.Name, true) :: Motor6D
			if vmMotor and vmMotor:IsA("Motor6D") then
				local excludeC0 = (realDesc.Name == "RootJoint" or realDesc.Name == "Waist" or realDesc.Name == "Neck")
				table.insert(Viewmodel.MotorCache, { Real = realDesc, VM = vmMotor, ExcludeC0 = excludeC0 })
			end
		end
	end

	rig.Parent = cam
	Viewmodel.Rig = rig
	wasFirstPerson = false
	smoothedRotation = nil
	currentOffset = HIP_OFFSET
	swayOffset = CFrame.new()
	bobOffset = CFrame.new()
	aimAlpha = 0
	tiltAngle = 0
	resetSpring(RecoilRotation)
	resetSpring(RecoilPosition)

	Viewmodel.PhysicsConnection = RunService.Stepped:Connect(function()
		for _, part in ipairs(Viewmodel.PhysicsParts) do part.CanCollide = false; part.CanTouch = false end
	end)
	Viewmodel.Connection = RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(Viewmodel.update, character, dt)
		if not ok then warn("[TREKViewmodel] Update error: " .. tostring(err)) end
	end)
end

------------------------------------------------------------------------
-- UPDATE
------------------------------------------------------------------------

Viewmodel.update = function(character: Model, dt: number)
	if not Viewmodel.Rig or not Viewmodel.Rig.Parent then return end
	if not character or not character.Parent then return end
	dt = dt or (1 / 60)

	local cam = workspace.CurrentCamera
	if not cam then return end
	if Viewmodel.Rig.Parent ~= cam then Viewmodel.Rig.Parent = cam end

	if tick() - Viewmodel.LastReplicate > 0.05 then
		Viewmodel.LastReplicate = tick()
		local rs = game:GetService("ReplicatedStorage")
		local ts = rs:FindFirstChild("TREK_SERVICES")
		local tr = ts and ts:FindFirstChild("TREK_Remotes")
		local ra = tr and tr:FindFirstChild("ReplicateAim")
		if ra and ra:IsA("RemoteEvent") then ra:FireServer(math.asin(cam.CFrame.LookVector.Y)) end
	end

	local baseCFrame = cam.CFrame
	Viewmodel.IsFirstPerson = Viewmodel.checkFirstPerson()
	local isFirstPerson = Viewmodel.IsFirstPerson
	local vmT = isFirstPerson and 0 or 1
	local rtT = isFirstPerson and 1 or 0

	for _, p in ipairs(Viewmodel.RigVisibleParts) do if p and p.Parent then p.LocalTransparencyModifier = vmT end end
	for _, p in ipairs(Viewmodel.VmToolParts) do if p and p.Parent then p.LocalTransparencyModifier = vmT end end
	for _, p in ipairs(Viewmodel.RealToolParts) do if p and p.Parent then p.LocalTransparencyModifier = rtT end end

	-- Hide ALL BackpackModels welded to Torso in first person (fuel tanks, ammo packs, etc.)
	-- They all clip into the viewport since the Torso leans forward during sprint.
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Model") and string.sub(child.Name, 1, 9) == "Backpack_" then
			for _, desc in ipairs(child:GetDescendants()) do
				if desc:IsA("BasePart") then
					if isFirstPerson then
						if desc:GetAttribute("_vmOrigT") == nil then
							desc:SetAttribute("_vmOrigT", desc.Transparency)
						end
						desc.Transparency = 1
						desc.LocalTransparencyModifier = 1
					else
						local orig = desc:GetAttribute("_vmOrigT")
						if orig ~= nil then
							desc.Transparency = orig
							desc:SetAttribute("_vmOrigT", nil)
						end
						desc.LocalTransparencyModifier = 0
					end
				end
			end
		end
	end

	if not isFirstPerson then wasFirstPerson = false; return end
	if not wasFirstPerson then smoothedRotation = nil; wasFirstPerson = true end
	if not Viewmodel.VmHRP or not Viewmodel.VmHRP.Parent then return end

	local currentTime = tick()
	local isAiming = Viewmodel.Scoped or (cam.FieldOfView < DEFAULT_FOV - 2)
	UserInputService.MouseIconEnabled = not isAiming

	for _, link in ipairs(Viewmodel.MotorCache) do
		if not link.Real or not link.Real.Parent then continue end
		if not link.VM or not link.VM.Parent then continue end
		link.VM.Transform = link.Real.Transform
		if not link.ExcludeC0 then link.VM.C0 = link.Real.C0; link.VM.C1 = link.Real.C1 end
		if not link.Real.Part0 and link.VM.Part0 then link.VM.Part0 = nil
		elseif link.Real.Part0 and (not link.VM.Part0 or link.VM.Part0.Name ~= link.Real.Part0.Name) then
			local m = Viewmodel.ViewmodelTool and Viewmodel.ViewmodelTool:FindFirstChild(link.Real.Part0.Name, true) :: BasePart
			if not m then m = Viewmodel.Rig:FindFirstChild(link.Real.Part0.Name, true) :: BasePart end
			if m then link.VM.Part0 = m end
		end
		if not link.Real.Part1 and link.VM.Part1 then link.VM.Part1 = nil
		elseif link.Real.Part1 and (not link.VM.Part1 or link.VM.Part1.Name ~= link.Real.Part1.Name) then
			local m = Viewmodel.ViewmodelTool and Viewmodel.ViewmodelTool:FindFirstChild(link.Real.Part1.Name, true) :: BasePart
			if not m then m = Viewmodel.Rig:FindFirstChild(link.Real.Part1.Name, true) :: BasePart end
			if m then link.VM.Part1 = m end
		end
	end

	local targetOffset = HIP_OFFSET
	if isAiming then
		local ap = Viewmodel.ViewmodelTool and Viewmodel.ViewmodelTool:FindFirstChild("AimPart", true) :: BasePart
		if ap then targetOffset = Viewmodel.VmHRP.CFrame:ToObjectSpace(ap.CFrame):Inverse() else targetOffset = AIM_OFFSET_FALLBACK end
	end
	currentOffset = currentOffset:Lerp(targetOffset, 1 - math.exp(-dt * 20))
	local tav = isAiming and 1 or 0
	aimAlpha = aimAlpha + (tav - aimAlpha) * (1 - math.exp(-dt * 20))
	local hm = 1 - aimAlpha

	local realHRP = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local strafeAmount = 0
	if realHRP then
		local vel = realHRP.AssemblyLinearVelocity
		local lv = realHRP.CFrame:VectorToObjectSpace(vel)
		local fs = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local ns = math.clamp(fs, 0, 25) / 16
		local bs = 11
		local bx = math.sin(currentTime * bs) * 0.015 * ns * hm
		local by = math.abs(math.cos(currentTime * bs)) * 0.02 * ns * hm
		local fe = math.clamp(lv.Y * -0.015, -0.3, 0.3) * hm
		strafeAmount = math.clamp(-lv.X * 0.015, -0.1, 0.1)
		local tb = CFrame.new(bx, by + fe, 0) * CFrame.Angles(by, bx, bx * 0.6)
		bobOffset = bobOffset:Lerp(tb, 1 - math.exp(-dt * BOB_SMOOTH_SPEED))
	end

	local md = UserInputService:GetMouseDelta()
	local dx = (math.abs(md.X) > 0.8) and md.X or 0
	local dy = (math.abs(md.Y) > 0.8) and md.Y or 0
	local rsx = math.clamp(-dx * 0.002, -0.15, 0.15)
	local sx = rsx * hm
	local sy = math.clamp(dy * 0.002, -0.15, 0.15) * hm
	local ts = CFrame.new(sx * 1.5, sy * 1.5, 0) * CFrame.Angles(sy * 1.5, sx * 0.8, sx * 2.5)
	swayOffset = swayOffset:Lerp(ts, 1 - math.exp(-dt * SWAY_SMOOTH_SPEED))

	local tt = (strafeAmount * 0.7) + (rsx * 0.5)
	tiltAngle = tiltAngle + (tt - tiltAngle) * (1 - math.exp(-dt * 12))
	cam.CFrame = cam.CFrame * CFrame.Angles(0, 0, tiltAngle)

	local cp = cam.CFrame.Position
	local cr = cam.CFrame.Rotation
	if not smoothedRotation then smoothedRotation = cr end
	local ds = 16 + (30 * (1 - hm))
	if smoothedRotation then
		smoothedRotation = smoothedRotation:Lerp(cr, 1 - math.exp(-dt * ds))
		baseCFrame = CFrame.new(cp) * smoothedRotation
	end

	-- Spring recoil output
	local rr = RecoilRotation.Position
	local rp = RecoilPosition.Position
	if rr.Magnitude > 0.001 then -- DEBUG
		print("[RECOIL] Spring rotation output:", rr, "magnitude:", rr.Magnitude) -- DEBUG
	end -- DEBUG
	local recoilCF = CFrame.new(rp.X, rp.Y, rp.Z) * CFrame.Angles(rr.X, rr.Y, rr.Z)

	Viewmodel.VmHRP.CFrame = baseCFrame * currentOffset * bobOffset * swayOffset * recoilCF
end

------------------------------------------------------------------------
-- BARREL HELPERS
------------------------------------------------------------------------

Viewmodel.getBarrelPosition = function(barrelName: string): Vector3?
	if Viewmodel.IsFirstPerson and Viewmodel.ViewmodelTool then
		local b = Viewmodel.ViewmodelTool:FindFirstChild(barrelName) :: BasePart
		if b then return b.Position end
	end
	return nil
end

Viewmodel.getBarrel = function(barrelName: string): BasePart?
	if Viewmodel.IsFirstPerson and Viewmodel.ViewmodelTool then
		local b = Viewmodel.ViewmodelTool:FindFirstChild(barrelName) :: BasePart
		if b then return b end
	end
	return nil
end

------------------------------------------------------------------------
-- UNEQUIP
------------------------------------------------------------------------

Viewmodel.unequip = function()
	if Viewmodel.PhysicsConnection then Viewmodel.PhysicsConnection:Disconnect(); Viewmodel.PhysicsConnection = nil end
	if Viewmodel.Connection then Viewmodel.Connection:Disconnect(); Viewmodel.Connection = nil end
	if Viewmodel.RealToolAddedConn then Viewmodel.RealToolAddedConn:Disconnect(); Viewmodel.RealToolAddedConn = nil end
	if Viewmodel.RigAddedConn then Viewmodel.RigAddedConn:Disconnect(); Viewmodel.RigAddedConn = nil end

	pcall(function()
		for _, p in ipairs(Viewmodel.RigVisibleParts) do if p and p.Parent then p.LocalTransparencyModifier = 1; p.Transparency = 1 end end
		for _, p in ipairs(Viewmodel.VmToolParts) do if p and p.Parent then p.LocalTransparencyModifier = 1; p.Transparency = 1 end end
		for _, p in ipairs(Viewmodel.RealToolParts) do if p and p.Parent then p.LocalTransparencyModifier = 0 end end
	end)

	-- Restore all backpack model transparencies
	pcall(function()
		local character = game:GetService("Players").LocalPlayer.Character
		if character then
			for _, child in ipairs(character:GetChildren()) do
				if child:IsA("Model") and string.sub(child.Name, 1, 9) == "Backpack_" then
					for _, desc in ipairs(child:GetDescendants()) do
						if desc:IsA("BasePart") then
							local orig = desc:GetAttribute("_vmOrigT")
							if orig ~= nil then
								desc.Transparency = orig
								desc:SetAttribute("_vmOrigT", nil)
							end
							desc.LocalTransparencyModifier = 0
						end
					end
				end
			end
		end
	end)

	if Viewmodel.Rig then Viewmodel.Rig:Destroy(); Viewmodel.Rig = nil end
	table.clear(Viewmodel.MotorCache)
	table.clear(Viewmodel.RigVisibleParts)
	table.clear(Viewmodel.VmToolParts)
	table.clear(Viewmodel.RealToolParts)
	table.clear(Viewmodel.PhysicsParts)
	Viewmodel.VmHRP = nil; Viewmodel.RealTool = nil; Viewmodel.ViewmodelTool = nil
	aimAlpha = 0; tiltAngle = 0; smoothedRotation = nil; wasFirstPerson = false
	currentOffset = HIP_OFFSET; swayOffset = CFrame.new(); bobOffset = CFrame.new()
	UserInputService.MouseIconEnabled = true
	resetSpring(RecoilRotation)
	resetSpring(RecoilPosition)
end

return Viewmodel
