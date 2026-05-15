-- Turns character into a ragdoll upon death.

CORPSE_LIFETIME = 120 -- How many seconds a ragdoll stays around for before despawning.

-------------------------------------------------------------------------------------------------------------------------------------

function HandleCharacterDeath(Player, Character, Humanoid)
	Humanoid.Died:connect(function()
		-- First setup the character in preparation for the ragdoll.
		Character.Archivable = true
		local Corpse = Character:Clone()
		Corpse.Name = Player.Name.." Corpse"

		-- Setup the corpse's Humanoid.
		if Corpse:FindFirstChild("Humanoid") then
			local Humanoid = Corpse.Humanoid
			Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			Humanoid.Health = 0
			Humanoid.MaxHealth = 0
			Humanoid.PlatformStand = true
		end

		-- Iterate through all of the children, changing them as appropriate.
		for _,Child in pairs(Corpse:GetChildren()) do
			local head = Child.Parent:FindFirstChild("Head")
			if head then
				local billboardGui = head:FindFirstChildOfClass("BillboardGui")
				if billboardGui then
					billboardGui:Destroy()
				end
			end
			if Child:IsA("Script") or Child:IsA("LocalScript") or Child:IsA("Hat") then
				Child:Destroy()
			elseif Child:IsA("BasePart") and (Child.Name == "TorsoArm" or Child.Name == "ToolArm" or Child.Name == "HumanoidRootPart") then
				Child:Destroy()
			elseif Child:IsA("ForceField") then
				Child:Destroy()
			elseif Child:IsA("BasePart") then
				Child.CanCollide = true
				for _,Grandchild in pairs(Child:GetChildren()) do
					if Grandchild:IsA("JointInstance") then
						Grandchild:Destroy()
					end
				end
			elseif Child:IsA("Model") then
				Child:Destroy()
			end
		end

		-- Parent the Corpse to Workspace, and remove our old Character.
		Player.Character.Parent = nil
		Corpse.Parent = workspace

		-- Play a death sound, parented to the Corpse's Head.
		if Corpse:FindFirstChild("Head") then
			local DeathSoundIDs = {607569415,610709726,607686675}
			local DeathSound = Instance.new("Sound",Corpse.Head)
			DeathSound.Pitch = math.random(90,110)/100
			DeathSound.Volume = 1
			DeathSound.RollOffMaxDistance = 50
			DeathSound.RollOffMinDistance = 10
			DeathSound.SoundId = "rbxassetid://"..DeathSoundIDs[math.random(1,#DeathSoundIDs)]
			DeathSound:Play()
		end

		-- Finally, turn the Corpse into a ragdoll.	
		TurnCharacterIntoRagdoll(Corpse)
		game:GetService("Debris"):AddItem(Corpse, CORPSE_LIFETIME)
	end)
end

function TurnCharacterIntoRagdoll(Character)
	local Torso = Character:FindFirstChild("Torso")
	if not Torso then return end -- Edited by AoSI_Blackbird to prevent errors when limbs are missing (due to gibs).
	Torso:SetNetworkOwner(nil)

	local bodyParts = {
		["Left Arm"] = { Transparency = 0, Size = Vector3.new(0.9, 0.9, 0.9) },
		["Right Arm"] = { Transparency = 0, Size = Vector3.new(0.9, 0.9, 0.9) },
		["Head"] = {},
		["Left Leg"] = {},
		["Right Leg"] = {}
	}

	local AttactmentData = {
		["Right Arm"] = {
			PartAttachment = CFrame.new(0, 0.5, 0),
			TorsoAttachment = CFrame.new(1.5, 0.5, 0),
			Offset = CFrame.new(1.5, 0, 0)
		},
		["Left Arm"] = {
			PartAttachment = CFrame.new(0, 0.5, 0),
			TorsoAttachment = CFrame.new(-1.5, 0.5, 0),
			Offset = CFrame.new(-1.5, 0, 0)
		},
		["Right Leg"] = {
			PartAttachment = CFrame.new(0, 0.5, 0),
			TorsoAttachment = CFrame.new(0.5, -1.5, 0),
			Offset = CFrame.new(0.5, -2, 0)
		},
		["Left Leg"] = {
			PartAttachment = CFrame.new(0, 0.5, 0),
			TorsoAttachment = CFrame.new(-0.5, -1.5, 0),
			Offset = CFrame.new(-0.5, -2, 0)
		},
		["Head"] = {
			PartAttachment = CFrame.new(0, -0.5, 0),
			TorsoAttachment = CFrame.new(0, 1, 0),
			Offset = CFrame.new(0, 1.5, 0)
		}
	}

	local CollisionPartTemplate = Instance.new("Part")
	CollisionPartTemplate.Size = Vector3.new(1, 1.5, 1)
	CollisionPartTemplate.Transparency = 1

	for LimbName, Data in pairs(AttactmentData) do
		local Limb = Character:FindFirstChild(LimbName)
		if Limb then
			local Attachment1 = Instance.new("Attachment")
			Attachment1.CFrame = Data.PartAttachment
			Attachment1.Parent = Limb

			local Attachment2 = Instance.new("Attachment")
			Attachment2.CFrame = Data.TorsoAttachment
			Attachment2.Parent = Torso

			local Socket = Instance.new("BallSocketConstraint")
			Socket.Attachment0 = Attachment2
			Socket.Attachment1 = Attachment1
			Socket.Radius = 0
			Socket.Parent = Torso

			Limb.CanCollide = false

			local CollisionPart = CollisionPartTemplate:Clone()
			local CollisionPartWeld = Instance.new("Weld")
			CollisionPartWeld.C0 = CFrame.new(0, -0.25, 0)
			CollisionPartWeld.Part0 = Limb
			CollisionPartWeld.Part1 = CollisionPart
			CollisionPartWeld.Parent = CollisionPart
			CollisionPart.Parent = Character
		end
	end

	-- Head stays attached via BallSocket (added to AttactmentData above)
	-- No velocity impulse — head stays with the body for proper gib display
end

-------------------------------------------------------------------------------------------------------------------------------------

game.Players.PlayerAdded:connect(function(Player)
	Player.CharacterAdded:connect(function(Character)
		HandleCharacterDeath(Player, Character, Character:WaitForChild("Humanoid", 10))
	end)
end)
