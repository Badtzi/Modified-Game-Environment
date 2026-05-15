local configs = {
	-- ABILITIES
	canCrouch = true, -- If true, the player will be able to crouch
	canSprint = true, -- If true, the player will be able to sprint
	
	-- CONTROLS
		-- The last letter of each option is the key the player must press to activate the corresponding ability
	SprintKey = Enum.KeyCode.LeftShift; -- Sprinting Key
	CrouchKey = Enum.KeyCode.C; -- Crouching Key
	ReloadKey = Enum.KeyCode.R; -- Reloading Key
	ZoomKey = Enum.KeyCode.MouseRightButton; -- Zooming key Key
	PatrolKey = Enum.KeyCode.T; -- Patrolling Key
	CursorKey = Enum.KeyCode.N; -- Cursor selection Key
	modeKey = Enum.KeyCode.V; -- Weapon mode Key
	zoomIncrease = Enum.KeyCode.LeftShift; -- Zoom increase key
	zoomDecrease = Enum.KeyCode.LeftControl; -- Zoom decrease key
	
	-- R6 MOUSE ARM AIM
	r6MouseArmAimEnabled = true;
	r6MouseArmAimDisableWhilePatrol = true;
	r6MouseArmAimDisableWhileSprint = true;
	r6MouseArmAimDisableWhileReload = false;
	
	-- WALKSPEEDS
	Default = 16; -- Default walking speed of your game, the ROBLOX default is 16
	Sprint = 24; -- Sprinting speed of your game
	Crouch = 6; -- Crouching speed of your game
	
	-- MISC
	usesLeaderboard = true; -- If true, TREK will be counting kills and damage of each player
	explosionShakeEnabled = true; -- If true, explosions will shake your screen
	ScreenBloodWhenWounded = true; -- If true, images of blood will appear for a little when you're wounded.
	enableTeamEsp = true; -- if true, your teammates' names will be visible through walls from any distance.

	-- SECURITY
		--WARNING: ServerRays MAY be slow and unstable, DO NOT USE IF YOUR MAP HAS TOO MUCH POPSHOTS
	AntiHBE = true; -- If true, the game will kick players when their local target sizes mismatch server target sizes
	ServerRays = true; -- If true, the server will test whether the shot you've taken is possible on the server
	
	-- MEDICAL
		--[[
		TREK MEDICAL SYSTEM FEATURES:
		  -Paralysis upon losing both of your legs
		  -Inaccuracy and inability to reload upon losing your left arm
		  -Bleeding upon losing any limnb
		]]
	EnableMedical = true; -- If true, TREK medical system will be enabled
	
	        --[[
        YOU CAN MAKE THE CAMERA RECOIL PICK A NUMBER IN A CERTAIN RANGE BY CHANGING AN OPTION FROM A NUMBER
        TO A TABLE OF 2 NUMBERS LIKE {-1,1}
        ]]
	CameraRecoil = true; -- If true, your camera will recoil on each shot
	RecoilX = 7; -- Vertical (Despite being X, yes.) recoil
	RecoilY = {-14,14}; -- Horizontal (Despite being Y, yes.) recoil
	RecoilZ = {-14,14}; -- Diagonal recoil i think.

	RecoilZoomMultiplier = 0.7; -- The number to multiply all the recoil options by when zooming
	RecoilCrouchMultiplier = 0.5; -- The number to multiply all the recoil options by when crouching
	
	-- COLLISION GROUPS
		-- TEMPLATE:
		--[[
			['CollisionGroup'] = {
				['AnotherCollisionGroup'] = canCollide (true / false);
			}
			['AnotherCollisionGroup'] = {
				['CollisionGroup'] = canCollide (true / false);
			}
		]]

	collisionGroupConfigs = {
		['TMouseCollGroup'] = { -- This is the collision group used by your cursor. Make sure that it doesn't collide with anything that you wish to shoot through.
			["Default"] = true;
			["AP_Positive"] = false;
			["AP_Negative"] = true;
		};
	};
	
	Prone = 4,              -- Prone crawl walk speed
	UncrouchKey = Enum.KeyCode.X,  -- Key to go up a stance
	
	-- CURSORS
		-- PLEASE USE THE ASSET IDS INSTEAD OF DECAL IDS WHEN INPUTTING YOUR CURSORS
	cursors = {
		[1] = {
			['Main'] = 8229322464,
			['Enemy'] = 8229324840,
			['Friendly'] = 8229324000
		};
		[2] = {
			['Main'] = 11637362159,
			['Enemy'] = 11637363343,
			['Friendly'] = 11637365328
		};
		[3] = {
			['Main'] = 11637367551,
			['Enemy'] = 11637369116,
			['Friendly'] = 11637369756
		};
		[4] = {
			['Main'] = 11637386373,
			['Enemy'] = 11637387483,
			['Friendly'] = 11637388280
		};
	};
}

return configs
