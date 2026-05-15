local module = {}

local glb = require(shared.S.TREK_Globals.GlobalConfigs)
local universalFuncs = require(shared.S.TREK_Modules:WaitForChild("TREKUniversalFunctions"))

local function getGibModel(partName)
	local customFolder = script:FindFirstChild("CustomGibs")
	if customFolder then
		local possibleGibs = {}
		for _, obj in ipairs(customFolder:GetChildren()) do
			if (obj:IsA("Model") or obj:IsA("BasePart")) then
				if obj.Name == partName or obj.Name:match("^" .. partName .. "%d+$") then
					table.insert(possibleGibs, obj)
				end
			end
		end
		if #possibleGibs > 0 then
			return possibleGibs[math.random(1, #possibleGibs)], true
		end
	end

	local defaultModel = shared.S.TREK_EffectsStorage.Misc.bodyparts
	if defaultModel and defaultModel:FindFirstChild(partName) then
		return defaultModel[partName], false
	end

	return nil, false
end


local function getGibRoot(gib): BasePart?
	if gib:IsA("BasePart") then return gib end
	if gib:IsA("Model") then
		if gib.PrimaryPart and gib.PrimaryPart:IsA("BasePart") then return gib.PrimaryPart end
		for _, desc in ipairs(gib:GetDescendants()) do
			if desc:IsA("BasePart") then return desc end
		end
	end
	return nil
end

local function positionGib(gib, cf)
	if gib:IsA("BasePart") then
		gib.CFrame = cf
	elseif gib:IsA("Model") then
		gib:PivotTo(cf)
	end
end

local function setupGibPhysics(gib)
	if gib:IsA("BasePart") then
		gib.Anchored = false
		gib.CanCollide = false
	elseif gib:IsA("Model") then
		for _, desc in ipairs(gib:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Anchored = false
				desc.CanCollide = false
			end
		end
	end
end


local function applyCharacterAppearance(gib, chr, partName)
	if not chr then return end

	local bodyColors = chr:FindFirstChildOfClass("BodyColors")

	local colorMap = {
		["Head"]      = bodyColors and bodyColors.HeadColor3,
		["Left Arm"]  = bodyColors and bodyColors.LeftArmColor3,
		["Right Arm"] = bodyColors and bodyColors.RightArmColor3,
		["Left Leg"]  = bodyColors and bodyColors.LeftLegColor3,
		["Right Leg"] = bodyColors and bodyColors.RightLegColor3,
		["Torso"]     = bodyColors and bodyColors.TorsoColor3,
	}

	local bodyColor = colorMap[partName]

	local shirt = chr:FindFirstChildOfClass("Shirt")
	local pants = chr:FindFirstChildOfClass("Pants")

	local clothingTexture = nil
	if partName == "Left Arm" or partName == "Right Arm" or partName == "Torso" then
		if shirt then clothingTexture = shirt.ShirtTemplate end
	elseif partName == "Left Leg" or partName == "Right Leg" then
		if pants then clothingTexture = pants.PantsTemplate end
	end

	local partsToProcess = {}
	if gib:IsA("BasePart") then
		table.insert(partsToProcess, gib)
	elseif gib:IsA("Model") then
		for _, desc in ipairs(gib:GetDescendants()) do
			if desc:IsA("BasePart") then table.insert(partsToProcess, desc) end
		end
	end

	for _, gibPart in ipairs(partsToProcess) do
		if bodyColor then
			gibPart.Color = bodyColor
		end

		if clothingTexture then
			local mesh = gibPart:FindFirstChildOfClass("SpecialMesh")
			if mesh then
				mesh.TextureId = clothingTexture
			end
		end
	end
end


local function handleAdditionalParts(chr, partName, gibModel)
	local additionalParts = {
		["Left Arm"]  = "Left Shoulder",
		["Right Arm"] = "Right Shoulder",
		["Left Leg"]  = "Left Hip",
		["Right Leg"] = "Right Hip",
		["Head"]      = "Neck",
	}

	if not chr:FindFirstChild("HumanoidRootPart") then return end
	if not additionalParts[partName] then return end

	local additionalName = additionalParts[partName]

	local sourceModel = gibModel
	if not sourceModel:FindFirstChild("TorsoThings") then
		sourceModel = shared.S.TREK_EffectsStorage.Misc.bodyparts
	end
	if not sourceModel or not sourceModel:FindFirstChild("TorsoThings") then return end

	local torso = chr:FindFirstChild("Torso")
	if not torso then return end

	local torsothings = sourceModel.TorsoThings:Clone()
	torsothings:SetPrimaryPartCFrame(torso.CFrame)

	local additionalPart = torsothings:FindFirstChild(additionalName)
	if not additionalPart then torsothings:Destroy() return end

	local weld = additionalPart:FindFirstChild("WeldConstraint")
	if weld then weld.Part1 = torso end

	additionalPart.Anchored = false
	additionalPart.Parent = torso

	torsothings:Destroy()
end


local function rightArmLossFunction(chr)
	if not glb.EnableMedical then return end

	local plr = game.Players:GetPlayerFromCharacter(chr)
	if not plr then return end

	for _, tool in ipairs(plr.Backpack:GetChildren()) do
		if shared.S.GunConfigs:FindFirstChild(tool.Name, true) then tool:Destroy() end
	end

	local equippedTool = chr:FindFirstChildOfClass("Tool")
	if equippedTool and shared.S.GunConfigs:FindFirstChild(equippedTool.Name, true) then
		equippedTool:Destroy()
	end
end

local function leftArmLossFunction(chr)
	if not glb.EnableMedical then return end
	if not chr:FindFirstChild("Humanoid") then return end

	if not chr.Humanoid:FindFirstChild("TInacCondition") then
		local v = Instance.new("BoolValue")
		v.Parent = chr.Humanoid
		v.Name = "TInacCondition "
		v.Value = true
	end
end

local function legLossFunction(chr)
	if not glb.EnableMedical then return end
	if not chr:FindFirstChild("Humanoid") then return end

	if not chr.Humanoid:FindFirstChild("TParalCondition") then
		chr.Humanoid.PlatformStand = true

		local v = Instance.new("BoolValue")
		v.Parent = chr.Humanoid
		v.Name = "TParalCondition"
		v.Value = true
	end
end

local function bleedingFunction(chr)
	if not glb.EnableMedical then return end

	if not chr:FindFirstChild("TBleeding") then
		local b = script.TBleeding:Clone()

		b.Parent = chr
		b.Disabled = false

		local v = Instance.new("BoolValue")
		v.Parent = chr.Humanoid
		v.Name = "TBleedCondition"
		v.Value = true
	else
		chr.TBleeding.Rate.Value += 0.5
	end
end

local function scream(part: BasePart)
	if not part then return end
	if part:FindFirstChild("SCREAM") then return end

	local random = math.random(1, 13)
	local sound = shared.S.TREK_EffectsStorage.Sounds.TheDamned:FindFirstChild("scream" .. tostring(random))
	if not sound then return end

	local clone = sound:Clone()
	clone.Name = "SCREAM"
	clone.Parent = part
	clone:Play()

	task.delay(clone.TimeLength, function()
		if clone then clone:Destroy() end
	end)
end

local GIB_ATTACHMENT_DATA = {
	["Right Arm"] = { PartAttachment = CFrame.new(0, 0.5, 0),  TorsoAttachment = CFrame.new(1.5, 0.5, 0) },
	["Left Arm"]  = { PartAttachment = CFrame.new(0, 0.5, 0),  TorsoAttachment = CFrame.new(-1.5, 0.5, 0) },
	["Right Leg"] = { PartAttachment = CFrame.new(0, 0.5, 0),  TorsoAttachment = CFrame.new(0.5, -1.5, 0) },
	["Left Leg"]  = { PartAttachment = CFrame.new(0, 0.5, 0),  TorsoAttachment = CFrame.new(-0.5, -1.5, 0) },
	["Head"]      = { PartAttachment = CFrame.new(0, -0.5, 0), TorsoAttachment = CFrame.new(0, 1, 0) },
}

function module.handleGibs(part, mod, chr, source)
	if not part then return end

	local gibModel, isCustom = getGibModel(part.Name)
	if not gibModel then return end

	if math.random(1, 100) > mod.limbRemovalChance then return end

	local partName = part.Name
	local cf = part.CFrame

	part:Destroy()

	local limb = gibModel:Clone()
	setupGibPhysics(limb)
	positionGib(limb, cf)
	applyCharacterAppearance(limb, chr, partName)

	local gibRoot = getGibRoot(limb)
	local torso = chr:FindFirstChild("Torso")
	local attachData = GIB_ATTACHMENT_DATA[partName]

	if torso and attachData and gibRoot then
		limb.Parent = chr

		local att1 = Instance.new("Attachment")
		att1.CFrame = attachData.PartAttachment
		att1.Parent = gibRoot

		local att2 = Instance.new("Attachment")
		att2.Name = "GibAttach_" .. partName
		att2.CFrame = attachData.TorsoAttachment
		att2.Parent = torso

		local socket = Instance.new("BallSocketConstraint")
		socket.Attachment0 = att2
		socket.Attachment1 = att1
		socket.Radius = 0
		socket.Parent = torso
	else
		limb.Parent = workspace.IgnoreList
	end

	-- Play a random gib sound from the limb
	local gibSounds = {}
	for _, child in ipairs(limb:GetDescendants()) do
		if child:IsA("Sound") then
			table.insert(gibSounds, child)
		end
	end
	if #gibSounds > 0 then
		gibSounds[math.random(1, #gibSounds)]:Play()
	end

	-- Emit GIBEFFECT particles (one-shot burst from torso stump, not the flying gib)
	local gibEffect = limb:FindFirstChild("GIBEFFECT", true)
	if gibEffect and gibEffect:IsA("BasePart") and torso then
		-- Position at the torso stump where the limb was removed
		local stumpCF = torso.CFrame
		if attachData then
			stumpCF = torso.CFrame * attachData.TorsoAttachment
		end

		gibEffect.Anchored = false
		gibEffect.CanCollide = false
		gibEffect.CanQuery = false
		gibEffect.Transparency = 1
		gibEffect.CFrame = stumpCF

		-- Reparent to character and weld to torso so blood follows the body
		gibEffect.Parent = chr
		local effectWeld = Instance.new("WeldConstraint")
		effectWeld.Part0 = torso
		effectWeld.Part1 = gibEffect
		effectWeld.Parent = gibEffect

		for _, emitter in ipairs(gibEffect:GetDescendants()) do
			if emitter:IsA("ParticleEmitter") then
				emitter.Enabled = false
				emitter:Emit(emitter:GetAttribute("EmitCount") or math.random(10, 40))
			end
		end

		universalFuncs.DestroyDelayed(gibEffect, 10)
	end

	if gibRoot then
		pcall(function()
			gibRoot:ApplyImpulse((gibRoot.Position - source).Unit * 15)
		end)
	end

	universalFuncs.DestroyDelayed(limb, 30)

	if not isCustom then
		handleAdditionalParts(chr, partName, gibModel)
	end

	bleedingFunction(chr)
	scream(chr:FindFirstChild("Head"))

	-- Voice: gibbing reaction (team/gender-aware version of Voices of the Damned)
	pcall(function()
		if shared.VoicePlay then
			local gibPlr = game.Players:GetPlayerFromCharacter(chr)
			if gibPlr then
				shared.VoicePlay(gibPlr, "VoicesOfTheDamned")
			end
		end
	end)

	if partName == "Left Arm" then leftArmLossFunction(chr) end
	if partName == "Right Arm" then rightArmLossFunction(chr) end
	if not chr:FindFirstChild("Left Leg") and not chr:FindFirstChild("Right Leg") then
		legLossFunction(chr)
	end
end

return module
