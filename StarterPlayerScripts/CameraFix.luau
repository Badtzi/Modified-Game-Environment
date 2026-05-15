-- CameraReset.luau
-- Place in: StarterPlayerScripts
-- Resets camera FOV and zoom on every respawn BEFORE Gun.luau initializes
-- Fixes: camera stuck at zoomed FOV after dying while aiming

local Players = game:GetService("Players")
local plr = Players.LocalPlayer

local DEFAULT_FOV = 70 -- Roblox default FOV

plr.CharacterAdded:Connect(function(character)
	-- Reset camera immediately on respawn
	workspace.CurrentCamera.FieldOfView = DEFAULT_FOV
	game:GetService("UserInputService").MouseDeltaSensitivity = 1

	-- Also reset after a short delay (catches any scripts that set FOV during init)
	task.delay(0.5, function()
		-- Only reset if no weapon is currently zoomed (check if FOV was set intentionally)
		-- At 0.5s after spawn, no weapon should be zoomed yet
		if workspace.CurrentCamera.FieldOfView ~= DEFAULT_FOV then
			workspace.CurrentCamera.FieldOfView = DEFAULT_FOV
		end
	end)
end)

-- Also reset right now (first spawn)
workspace.CurrentCamera.FieldOfView = DEFAULT_FOV
