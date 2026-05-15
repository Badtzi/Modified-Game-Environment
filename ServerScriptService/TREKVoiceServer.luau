local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

repeat task.wait() until shared.S and shared.S.TREK_Remotes and shared.S.TREK_Modules

local VoiceConfig = require(shared.S.TREKVoiceConfig)

local Remotes = shared.S.TREK_Remotes

local VoicePlayBroadcast = Remotes:FindFirstChild("VoicePlayBroadcast")
if not VoicePlayBroadcast then
	VoicePlayBroadcast = Instance.new("RemoteEvent")
	VoicePlayBroadcast.Name = "VoicePlayBroadcast"
	VoicePlayBroadcast.Parent = Remotes
end

local VoicePlayRequest = Remotes:FindFirstChild("VoicePlayRequest")
if not VoicePlayRequest then
	VoicePlayRequest = Instance.new("RemoteEvent")
	VoicePlayRequest.Name = "VoicePlayRequest"
	VoicePlayRequest.Parent = Remotes
end

local VoicelinePackages = ReplicatedStorage:WaitForChild("VoicelinePackages")

local cooldowns = {}

local function getCooldownTable(player)
	if not cooldowns[player] then
		cooldowns[player] = {}
	end
	return cooldowns[player]
end

local function detectGender(character)
	if not character then return "Male" end

	local femaleId = VoiceConfig.FemaleMeshId

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("CharacterMesh") then
			if child.MeshId == femaleId then
				return "Female"
			end
		end
	end

	local torso = character:FindFirstChild("Torso")
	if torso then
		local femaleIdStr = tostring(femaleId)
		for _, child in ipairs(torso:GetChildren()) do
			if child:IsA("SpecialMesh") then
				if tostring(child.MeshId):find(femaleIdStr) then
					return "Female"
				end
			end
		end
	end

	return "Male"
end

local function resolvePackage(player)
	if player.Team and player.Team.Name then
		local pkg = VoicelinePackages:FindFirstChild(player.Team.Name)
		if pkg then return pkg end
	end
	return VoicelinePackages:FindFirstChild(VoiceConfig.DefaultPackage)
end

local function resolveReactionFolder(player, reactionName)
	local pkg = resolvePackage(player)
	if not pkg then return nil end

	local character = player.Character
	local gender = detectGender(character)

	local genderFolder = pkg:FindFirstChild(gender)
	if not genderFolder then
		local fallbackGender = gender == "Female" and "Male" or "Female"
		genderFolder = pkg:FindFirstChild(fallbackGender)
		if not genderFolder then return nil end
	end

	local reactionConfig = VoiceConfig.Reactions[reactionName]
	local folderName = (reactionConfig and reactionConfig.FolderName) or reactionName

	return genderFolder:FindFirstChild(folderName)
end

local function pickRandomSound(reactionFolder)
	local sounds = {}
	for _, child in ipairs(reactionFolder:GetChildren()) do
		if child:IsA("Sound") then
			table.insert(sounds, child)
		end
	end

	if #sounds == 0 then return nil end
	return sounds[math.random(1, #sounds)]
end

local function getSubtitleText(sound)
	if not sound then return "" end
	local subtitle = sound:FindFirstChild("Subtitle")
	if subtitle and subtitle:IsA("StringValue") then
		return subtitle.Value or ""
	end
	return ""
end

local function playVoiceline(player, reactionName)
	if not player or not reactionName then return end

	local character = player.Character
	if not character then return end

	local reactionConfig = VoiceConfig.Reactions[reactionName]
	local chance = (reactionConfig and reactionConfig.Chance) or 1.0
	local cooldown = (reactionConfig and reactionConfig.Cooldown) or 0.0

	-- Death-type reactions skip the alive check
	if reactionName ~= "Death" and reactionName ~= "BurnDeath"
		and reactionName ~= "VoicesOfTheDamned" and reactionName ~= "Kill" then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end
	end

	if chance < 1.0 and math.random() > chance then return end

	local now = os.clock()
	local playerCooldowns = getCooldownTable(player)
	local lastTime = playerCooldowns[reactionName]
	if lastTime and cooldown > 0 and (now - lastTime) < cooldown then return end

	local reactionFolder = resolveReactionFolder(player, reactionName)
	if not reactionFolder then return end

	local sound = pickRandomSound(reactionFolder)
	if not sound then return end

	playerCooldowns[reactionName] = now

	local duration = VoiceConfig.DefaultSubtitleDuration
	if sound.TimeLength and sound.TimeLength > 0 then
		duration = sound.TimeLength
	end

	local subtitleText = getSubtitleText(sound)

	VoicePlayBroadcast:FireAllClients(player, sound, subtitleText, duration)
end

shared.VoicePlay = function(player, reactionName)
	playVoiceline(player, reactionName)
end

VoicePlayRequest.OnServerEvent:Connect(function(player, reactionName)
	if typeof(reactionName) ~= "string" then return end
	if not VoiceConfig.Reactions[reactionName] then return end
	playVoiceline(player, reactionName)
end)

local function bindPlayerDeathHook(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()

			task.wait(0.1)


			playVoiceline(player, "Death")


			pcall(function()
				local weaponTag = humanoid:FindFirstChild("WeaponTag")
				if weaponTag and weaponTag:IsA("ObjectValue") and weaponTag.Value then
					local killer = weaponTag.Value
					if killer:IsA("Player") and killer ~= player then
						playVoiceline(killer, "Kill")
					end
				end
			end)
		end)
	end)
end


local function onPlayerAdded(player)
	bindPlayerDeathHook(player)
end

local function onPlayerRemoving(player)
	cooldowns[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
