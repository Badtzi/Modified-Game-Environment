local SmoothShiftLock = {}
SmoothShiftLock.__index = SmoothShiftLock;

-- [[ Variables ]]:

--// Services and requires
local Players = game:GetService("Players");
local WorkspaceService = game:GetService("Workspace");
local RunService = game:GetService("RunService");
local UserInputService = game:GetService("UserInputService");
local TweenService = game:GetService("TweenService");
local Maid = require(script.Utils:WaitForChild("Maid"));
local Spring = require(script.Utils:WaitForChild("Spring"));

--// Instances
local LocalPlayer = Players.LocalPlayer;

--// Bindables
local ToggleEvent = script:WaitForChild("ToggleShiftLock");
local EditConfig = script:WaitForChild("EditConfig");

--// Configuration
local config = {
	["CHARACTER_SMOOTH_ROTATION"]   = true,                       --// If your character should rotate smoothly or not
	["MANUALLY_TOGGLEABLE"]         = true,                       --// If the shift lock an be toggled manually by player
	["CHARACTER_ROTATION_SPEED"]    = 3,                          --// How quickly character rotates smoothly
	["TRANSITION_SPRING_DAMPER"]    = 0.7,                        --// Camera transition spring damper, test it out to see what works for you
	["CAMERA_TRANSITION_IN_SPEED"]  = 10,                         --// How quickly locked camera moves to offset position
	["CAMERA_TRANSITION_OUT_SPEED"] = 14,                         --// How quickly locked camera moves back from offset position
	["LOCKED_CAMERA_OFFSET"]        = Vector3.new(3, 0, 0), --// Locked camera offset
	--["LOCKED_CAMERA_OFFSET"]        = Vector3.new(1.75, 0.25, 0), --// Locked camera offset
	["LOCKED_MOUSE_ICON"]           =                             --// Locked mouse icon
		"",
	["SHIFT_LOCK_KEYBINDS"]         =                             --// Shift lock keybinds
		{Enum.KeyCode.LeftControl},
	["SHOULDER_SWAP_KEY"]           = Enum.KeyCode.E,             --// Key to swap camera shoulder
}

local ENABLED = false;
local RIGHT_SHOULDER = true; --// true = right shoulder (positive X), false = left shoulder

-- Create SwapShoulder bindable if it doesn't exist
local SwapShoulderEvent = script:FindFirstChild("SwapShoulder")
if not SwapShoulderEvent then
	SwapShoulderEvent = Instance.new("BindableEvent")
	SwapShoulderEvent.Name = "SwapShoulder"
	SwapShoulderEvent.Parent = script
end

--// Setup
local maid = Maid.new();

-- [[ Functions ]]:

--// Setup smooth shift lock on client (Run once and on a LocalScript)
function SmoothShiftLock:Init()
	local managerMaid = Maid.new();

	managerMaid:GiveTask(LocalPlayer.CharacterAdded:Connect(function()
		self:CharacterAdded();
	end));
end;

--// Character added event function
function SmoothShiftLock:CharacterAdded()
	local self = setmetatable({}, SmoothShiftLock);
	--// Instances
	self.Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait();
	self.RootPart = self.Character:WaitForChild("HumanoidRootPart");
	self.Humanoid = self.Character:WaitForChild("Humanoid");
	self.Head = self.Character:WaitForChild("Head");
	--// Other
	self.Camera = WorkspaceService.CurrentCamera;
	--// Setup
	self.connectionsMaid = Maid.new();
	self.camOffsetSpring = Spring.new(Vector3.new(0, 0, 0));
	self.camOffsetSpring.Damper = config.TRANSITION_SPRING_DAMPER;

	--// Bind keybinds
	self.connectionsMaid:GiveTask(UserInputService.InputBegan:Connect(function(input, gpe)
		if (gpe) then return end;

		--// Shoulder swap (works anytime, even when manual toggle is disabled)
		if (input.KeyCode == config.SHOULDER_SWAP_KEY) and ENABLED and (self.Humanoid and self.Humanoid.Health ~= 0) then
			self:SwapShoulder();
			return;
		end;

		--// Shiftlock toggle
		if not config.MANUALLY_TOGGLEABLE then return end;
		for _, keyBind in pairs(config.SHIFT_LOCK_KEYBINDS) do
			if (input.KeyCode == keyBind) and (self.Humanoid and self.Humanoid.Health ~= 0) then
				self:ToggleShiftLock(not ENABLED);
			end;
		end;
	end));

	--// Update camera offset
	self.connectionsMaid:GiveTask(RunService.RenderStepped:Connect(function()
		if self.Head.LocalTransparencyModifier > 0.6 then return end;

		local camCF = self.Camera.CFrame; 
		local distance = (self.Head.Position - camCF.Position).magnitude;

		--// Camera offset
		if (distance > 1) then	
			self.Camera.CFrame = (self.Camera.CFrame * CFrame.new(self.camOffsetSpring.Position)); 

			if (ENABLED) and (UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter) then
				self:SetMouseState(ENABLED);
			end;
		end;
	end));

	--// Bindables
	self.connectionsMaid:GiveTask(ToggleEvent.Event:Connect(function(toggle: boolean)
		if (self.Humanoid and self.Humanoid.Health ~= 0) then
			self:ToggleShiftLock(toggle);
		end;
	end));

	self.connectionsMaid:GiveTask(EditConfig.Event:Connect(function(toChange, value)
		if config[toChange] ~= nil then
			config[toChange] = value;
		end;
	end));

	--// Shoulder swap bindable (for external scripts to trigger)
	self.connectionsMaid:GiveTask(SwapShoulderEvent.Event:Connect(function()
		if ENABLED and (self.Humanoid and self.Humanoid.Health ~= 0) then
			self:SwapShoulder();
		end;
	end));

	--// On death
	self.connectionsMaid:GiveTask(self.Humanoid.Died:Connect(function()
		self:CharacterDiedOrRemoved();
		return;
	end));

	--// On character removing
	self.connectionsMaid:GiveTask(LocalPlayer.CharacterRemoving:Connect(function()
		self:CharacterDiedOrRemoved();
		return;
	end));

	return self;
end;

--// Stop shiftlock upon character death or removal
function SmoothShiftLock:CharacterDiedOrRemoved()
	config.MANUALLY_TOGGLEABLE = true
	ENABLED = false
	self:ToggleShiftLock(false);

	if self.connectionsMaid ~= nil then
		self.connectionsMaid:Destroy();
	end;

	maid:DoCleaning();
end;

--// Return shiftlock enabled state
function SmoothShiftLock:IsEnabled(): boolean
	return ENABLED;
end;

--// Set Enum.MouseBehavior to LockCenter or Default depending on shiftlock enabled
function SmoothShiftLock:SetMouseState(enable : boolean)
	UserInputService.MouseBehavior = (enable and Enum.MouseBehavior.LockCenter) or (Enum.MouseBehavior.Default);
end;

--// Change mouse icon depending on shiftlock enabled
function SmoothShiftLock:SetMouseIcon(enable : boolean)
	-- Do nothing here. TREK handles the crosshair.
end;

--// Tween locked camera offset position
function SmoothShiftLock:TransitionLockOffset(enable : boolean)
	if (enable) then
		self.camOffsetSpring.Speed = config.CAMERA_TRANSITION_IN_SPEED;
		self.camOffsetSpring.Target = config.LOCKED_CAMERA_OFFSET;
	else
		self.camOffsetSpring.Speed = config.CAMERA_TRANSITION_OUT_SPEED;
		self.camOffsetSpring.Target = Vector3.new(0, 0, 0);
	end;
end;

--// Swap camera to opposite shoulder
function SmoothShiftLock:SwapShoulder()
	RIGHT_SHOULDER = not RIGHT_SHOULDER;

	-- Flip the X component of the offset
	local current = config.LOCKED_CAMERA_OFFSET;
	config.LOCKED_CAMERA_OFFSET = Vector3.new(-current.X, current.Y, current.Z);

	-- Update the spring target if shiftlock is active
	if ENABLED then
		self.camOffsetSpring.Speed = config.CAMERA_TRANSITION_IN_SPEED;
		self.camOffsetSpring.Target = config.LOCKED_CAMERA_OFFSET;
	end;
end;

--// Toggle shift lock
function SmoothShiftLock:ToggleShiftLock(enable : boolean)
	assert(typeof(enable) == typeof(false), "Enable value is not a boolean.");
	ENABLED = enable;

	self:SetMouseState(ENABLED);
	self:TransitionLockOffset(ENABLED);

	--// Start
	if (ENABLED) then
		maid:GiveTask(RunService.RenderStepped:Connect(function(delta)
			if (self.Humanoid and self.RootPart) then 
				self.Humanoid.AutoRotate = not ENABLED;
			end;

			--// Rotate character
			if (ENABLED) and not self.Character:GetAttribute("Stunned") then
				if not (self.Humanoid.Sit) and (config.CHARACTER_SMOOTH_ROTATION) then
					local x, y, z = self.Camera.CFrame:ToOrientation();
					self.RootPart.CFrame = self.RootPart.CFrame:Lerp(CFrame.new(self.RootPart.Position) * CFrame.Angles(0, y, 0), delta * 5 * config.CHARACTER_ROTATION_SPEED);
				elseif not (self.Humanoid.Sit) then
					local x, y, z = self.Camera.CFrame:ToOrientation();
					self.RootPart.CFrame = CFrame.new(self.RootPart.Position) * CFrame.Angles(0, y, 0);
				end;
			end;

			--// Stop
			if not (ENABLED) then 
				maid:Destroy() end;
		end));
	end;

	return self;
end;

return SmoothShiftLock;