
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local enum = {
	playertype 	=	{
		this		=	0,
		teammate	=	1,
		enemy		=	2,
	}
}

--

local function configureHumanoid(humanoid, playerType)
	if playerType == enum.playertype.teammate then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
		humanoid.NameDisplayDistance = math.huge
		humanoid.HealthDisplayDistance = math.huge
		
	elseif playerType == enum.playertype.this then
		--	For whatever reason Roblox controls humanoid occlusion from 
		--	the client's own humanoid instead of the subject humanoid.
		humanoid.NameOcclusion = Enum.NameOcclusion.EnemyOcclusion
		
	elseif playerType == enum.playertype.enemy then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
		humanoid.NameDisplayDistance = 100
		humanoid.HealthDisplayDistance = 100
	end
end

local function areTeamMates(player1, player2)
	return player1.Team == player2.Team	--	perhaps want to add other logic for extra teams
end

local function getPlayerType(player)
	local playerType
	
	if player == localPlayer then
		playerType = enum.playertype.this
	elseif areTeamMates(localPlayer, player) then
		playerType = enum.playertype.teammate
	else
		playerType = enum.playertype.enemy
	end
	
	return playerType
end

local function initCharacter(character)
	local characterPlayer = Players:GetPlayerFromCharacter(character)
	local humanoid = character:WaitForChild("Humanoid")
	configureHumanoid(humanoid, getPlayerType(characterPlayer))
end

local function initAllCharacters()
	for _, player in next, Players:GetPlayers() do
		if player.Character then
			initCharacter(player.Character)
		end
	end	
end

local function connectPlayer(player)
	if not shared.S.globalConfig.enableTeamEsp then return end
		
	if player.Character then
		initCharacter(player.Character)
	end
	
	player.CharacterAdded:Connect(initCharacter)

	player:GetPropertyChangedSignal("Team"):Connect(function()
		if player == localPlayer then
			--	When the client's team changes, we need to reinitialize
			--	all other characters in order to set their properties right.
			initAllCharacters()
		else
			--	When another client's team changes, we only need to
			--	reinitialize their character.
			if player.Character then
				initCharacter(player.Character)
			end
		end
	end)
end

--

for _, player in next, Players:GetPlayers() do
	connectPlayer(player)
end

Players.PlayerAdded:Connect(connectPlayer)
