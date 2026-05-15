-- VARIABLES
local module = {}
local universalFuncs = require(game.ReplicatedStorage.TREK_SERVICES.TREK_Modules:WaitForChild('TREKUniversalFunctions'))

local TAG = Instance.new('ObjectValue')

-- FUNCTIONS
function module.createStats(plr)
	if not shared.S.globalConfig.usesLeaderboard then return end

	if not game.ServerStorage:FindFirstChild(plr.Name.."Stats") then
		local f = Instance.new('Folder',plr)
		local v1, v2, v3 = Instance.new('NumberValue'), Instance.new('NumberValue'), Instance.new('NumberValue')	

		f.Name = 'leaderstats'

		v1.Name = 'Kills'
		v2.Name = 'Damage'
		v3.Name = 'Heals'

		v1.Parent = f
		v2.Parent = f
		v3.Parent = f
	else
		if game.ServerStorage:FindFirstChild(plr.Name..'Stats') then
			local c = game.ServerStorage:FindFirstChild(plr.Name..'Stats'):Clone()
			c.Parent = plr
			c.Name = 'leaderstats'
		end
	end
end

function module.UpdateStat(plr:Player, stat, value)
	if not shared.S.globalConfig.usesLeaderboard then return end
	if not plr then return end
	if not plr:FindFirstChild('leaderstats') then return end
	if not plr.leaderstats:FindFirstChild(stat) then return end
	
	plr.leaderstats[stat].Value += value
end

function module.tagPlr(hum, plr)
	if not plr then return end
	if not hum then return end
	
	if hum:FindFirstChild("WeaponTag") then
		hum.WeaponTag:Destroy()
	end

	local tag = TAG:Clone()
	tag.Name = "WeaponTag"
	tag.Value = plr
	tag.Parent = hum

	task.delay(1, function()
		if tag then tag:Destroy() end
	end)
end

function module.GiveKill(hum, chr)
	if not hum:FindFirstChild("WeaponTag") then return end

	local theplr = hum.WeaponTag.Value
	local theplr2 = game.Players:GetPlayerFromCharacter(chr)

	if not theplr then return end
	if not theplr2 then return end

	local sounds = shared.S.TREK_EffectsStorage.KillSounds:GetChildren()
	local sound = sounds[math.random(1,#sounds)]

	shared.S.TREK_Remotes.LocalSound:FireClient(hum.WeaponTag.Value, sound)
	shared.S.TREK_Remotes.Feed:FireClient(hum.WeaponTag.Value, chr.Name)

	if not shared.S.globalConfig.usesLeaderboard then return end
	
	theplr["leaderstats"].Kills.Value += 1
end

function module.plrDeath(chr,plr)
	local hum = chr:WaitForChild("Humanoid")

	module.GiveKill(hum,chr)
end

-- EXECUTION
return module