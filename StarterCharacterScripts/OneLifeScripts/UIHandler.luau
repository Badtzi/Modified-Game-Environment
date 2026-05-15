-- print('one life ui handler loaded')

-- GLOBALS
repeat wait() until game.Players.LocalPlayer.Character
repeat wait() until game.Players.LocalPlayer.CharacterAppearanceLoaded

local plr = game.Players.LocalPlayer
local chr = plr.Character

local hud = plr.PlayerGui:WaitForChild('GunHud')

game.Players.LocalPlayer.Character:WaitForChild('Humanoid')
game.Players.LocalPlayer.Character:WaitForChild('TREK_PlrConfig')
game.Players.LocalPlayer.PlayerGui:WaitForChild('GunHud')

local universalFuncs = require(shared.S.TREK_Modules:WaitForChild('TREKUniversalFunctions'))

-- LOCAL VALUES
local lasthealth = chr.Humanoid.Health

local tween = function(object,goal,tt,es,ed)
	return game:GetService("TweenService"):Create(object,TweenInfo.new(tt,Enum.EasingStyle[es],Enum.EasingDirection[ed],0,false,0),goal)
end

-- FUNCTIONS
local function createWoundImage()
	local images = {157619587,157416329,157416598,157416397}
	local image = Instance.new("ImageLabel")
	local selection = math.random(1,#images)
	local selectimage = images[selection]

	local sizeX, sizeY = math.random(15,65)/100, math.random(15,65)/100
	local posX, posY = math.random(5,55)/100, math.random(5,55)/100
	local rot = math.random(0,359)
	local transp = math.random(10,45)/100

	image.Size = UDim2.new(sizeX,0,sizeY,0)
	image.Position = UDim2.new(posX,0,posY,0)
	image.Rotation = rot
	image.ImageTransparency = math.random(25,75)/100
	image.Image = "rbxassetid://"..selectimage
	image.BackgroundTransparency = 1
	image.ImageTransparency = transp
	return image
end

local function onHealthChange()
	if lasthealth - chr.Humanoid.Health >= 3 then
		if not shared.S.globalConfig.ScreenBloodWhenWounded then return end
		
		local img = createWoundImage()
		img.Parent = hud.Blood
		
		tween(img,{ImageTransparency = 1},1-img.ImageTransparency,"Quad","In"):Play()
		universalFuncs.DestroyDelayed(img,1-img.ImageTransparency+0.25)
	end
	
	lasthealth = chr.Humanoid.Health
end


-- EXECUTION
chr:WaitForChild('Humanoid'):GetPropertyChangedSignal('Health'):Connect(onHealthChange)
