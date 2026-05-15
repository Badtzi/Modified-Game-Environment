-- VARIABLES
shared.S = {}

do
	for i,service in pairs(game.ReplicatedStorage:WaitForChild('TREK_SERVICES'):GetChildren()) do
		if service:IsA('Folder') then shared.S[service.Name] = service end
	end
	
	shared.S['globalConfig'] = require(shared.S.TREK_Globals.GlobalConfigs)
	shared.S['trekFuncs'] = require(shared.S.TREK_Modules.TREKUniversalFunctions)
end

local tween = function(object,goal,tt,es,ed)
	return game:GetService("TweenService"):Create(object,TweenInfo.new(tt,Enum.EasingStyle[es],Enum.EasingDirection[ed],0,false,0),goal)
end

local plr = game.Players.LocalPlayer
local hud = plr.PlayerGui:WaitForChild('GunHud')
local feed = plr.PlayerGui:WaitForChild('GunFeed'):WaitForChild('Feed')

local feedmsg = feed:WaitForChild('notifFrame'):Clone()
feed.notifFrame:Destroy()

local randomwords = {'ELIMINATED','HOSPITALISED','KILLED','TERMINATED','BLOXXED','PWNED','DESTROYED','TERMINATED','NEUTRALISED','VAPORISED','DEMOLISHED','NAENAED'}

-- FUNCTIONS
local function TypeWrite(text,gui)
	local t = tween(gui,{MaxVisibleGraphemes = #(text)},.2,'Linear','Out')

	gui.Text = text
	t:Play()
end

local function chat(message)
	game.StarterGui:SetCore('ChatMakeSystemMessage',{
		Text = "[LOCAL FROG]: "..message,
		Color = Color3.fromRGB(0, 255, 0),
		Font = Enum.Font.ArialBold,
		TextSize = 16,
	})
end

local function msg(plrname)
	local feed = plr.PlayerGui:WaitForChild('GunFeed'):WaitForChild('Feed')
	
	local clone = feedmsg:Clone()
	local random = randomwords[math.random(1,#randomwords)]
	
	shared.S.trekFuncs.DestroyDelayed(clone,3)
	
	task.spawn(function()
		clone.Parent = feed
		tween(clone.notif,{Position = UDim2.new(0,0,0,0)},0.4,'Sine','Out'):Play()

		TypeWrite(plrname,clone.notif.PlrName)
		TypeWrite(random,clone.notif.RandomWord)
		
		tween(clone.notif.Separator,{Size = UDim2.new(1,0,0.02,0), BackgroundTransparency = 0.2},0.5,'Sine','Out'):Play()
		tween(clone.notif.PlrName,{TextTransparency = 0.2},0.2,'Sine','Out'):Play()
		tween(clone.notif.RandomWord,{TextTransparency = 0.2},0.2,'Sine','Out'):Play()
		task.wait(2)
		tween(clone.notif.Separator,{BackgroundTransparency = 1},0.5,'Sine','Out'):Play()
		tween(clone.notif.PlrName,{TextTransparency = 1},0.2,'Sine','Out'):Play()
		tween(clone.notif.RandomWord,{TextTransparency = 1},0.2,'Sine','Out'):Play()
	end)
end

local function playSound(sound)
	local c = sound:Clone()
	
	c.Parent = script
	c:Play()
	
	shared.S.trekFuncs.DestroyDelayed(c, c.TimeLength)
end

local function chrAdded()
	local ammobar = plr.PlayerGui:WaitForChild('GunHud'):WaitForChild('AmmoBar')
	if not ammobar then return end

	for i, v in pairs(ammobar:GetChildren()) do
		if v.Name == 'OGBar' then continue end
		if v:IsA('UIListLayout') then continue end
		
		v:Destroy()
	end
end

-- EXECUTION
shared.S.TREK_Remotes.Feed.OnClientEvent:Connect(msg)
shared.S.TREK_Remotes.SystemMessage.OnClientEvent:Connect(chat)
shared.S.TREK_Remotes.LocalSound.OnClientEvent:Connect(playSound)

plr.CharacterAppearanceLoaded:Connect(chrAdded)