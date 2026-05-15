-- VARIABLES
local Player = game:GetService("Players").LocalPlayer

local AffectedParts = {
	['Left Arm'] = true;
	['Right Arm'] = true;
	['Left Leg'] = true;
	['Right Leg'] = true;
}

-- FUNCTIONS
local function isViewmodelFirstPerson()
	-- Check if viewmodel rig exists (weapon equipped with viewmodel)
	local vmRig = workspace.CurrentCamera:FindFirstChild("TREK_Viewmodel")
	if not vmRig then return false end

	-- Check if camera is close enough for first person
	local cam = workspace.CurrentCamera
	return (cam.CFrame.Position - cam.Focus.Position).Magnitude < 2
end

local function DoTheTurnShaker()
	if not Player.Character then return end

	-- When viewmodel is in first person, let it handle arm visibility
	-- Don't force real arms visible (viewmodel shows its own arms instead)
	if isViewmodelFirstPerson() then return end

	for i, part in pairs(Player.Character:GetChildren()) do
		if not part:IsA('BasePart') then continue end
		if not AffectedParts[part.Name] then continue end

		part.LocalTransparencyModifier = 0
	end
end

-- EXECUTION
game:GetService("RunService").RenderStepped:Connect(DoTheTurnShaker)
