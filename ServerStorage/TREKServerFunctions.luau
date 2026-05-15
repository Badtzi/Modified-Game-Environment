--[[
	TREKServerFunctions
	Location: ServerStorage
	
	Server-side utility module for weapon config lookups and tool validation.
	Caches required config modules for performance.
	
	API:
	  SetUpGuns()                    -- Pre-caches all gun configs
	  SetUpMelee()                   -- Pre-caches all melee configs
	  SetUpExplosives()              -- Pre-caches all explosive configs
	  checkForModule(tool)           -- Returns reqmod, moduleInstance for gun tools
	  checkForMeleeModule(tool)      -- Returns reqmod, moduleInstance for melee tools
	  checkForExplosiveModule(tool)  -- Returns reqmod, moduleInstance for explosive tools
	  checkForAnyModule(tool)        -- Tries gun, then melee, then explosive
	  returnTool(plr, chr)           -- Returns the equipped tool if it has a valid config
	
	Required by: TREKServerDamage, TREKServerGeneral, TREKServerMelee,
	             TREKDynamicWeapons, TREKHolsterService, TREKServerExplosive
]]

local module = {}

local gunconfigs = {}
local meleeconfigs = {}
local explosiveconfigs = {}

------------------------------------------------------------------------
-- INITIALIZATION
------------------------------------------------------------------------

function module:SetUpGuns()
	for _, v in ipairs(shared.S.GunConfigs:GetDescendants()) do
		if v:IsA("ModuleScript") then
			gunconfigs[v.Name] = require(v)
		end
	end
end

function module:SetUpMelee()
	if not shared.S.MeleeConfigs then return end
	for _, v in ipairs(shared.S.MeleeConfigs:GetDescendants()) do
		if v:IsA("ModuleScript") then
			meleeconfigs[v.Name] = require(v)
		end
	end
end

function module:SetUpExplosives()
	if not shared.S.ExplosiveConfigs then return end
	for _, v in ipairs(shared.S.ExplosiveConfigs:GetDescendants()) do
		if v:IsA("ModuleScript") then
			explosiveconfigs[v.Name] = require(v)
		end
	end
end

------------------------------------------------------------------------
-- CONFIG LOOKUP
------------------------------------------------------------------------

function module.checkForModule(tool)
	local mod

	if tool:GetAttribute("TConfigToUse") then
		mod = shared.S.GunConfigs:FindFirstChild(tool:GetAttribute("TConfigToUse"), true)
	else
		mod = shared.S.GunConfigs:FindFirstChild(tool.Name, true)
	end

	if not mod then return end

	local reqmod = gunconfigs[mod]
	if not reqmod then
		reqmod = require(mod)
		gunconfigs[mod] = reqmod
	end

	return reqmod, mod
end

function module.checkForMeleeModule(tool)
	if not shared.S.MeleeConfigs then return end

	local mod

	if tool:GetAttribute("TConfigToUse") then
		mod = shared.S.MeleeConfigs:FindFirstChild(tool:GetAttribute("TConfigToUse"), true)
	else
		mod = shared.S.MeleeConfigs:FindFirstChild(tool.Name, true)
	end

	if not mod then return end

	local reqmod = meleeconfigs[mod]
	if not reqmod then
		reqmod = require(mod)
		meleeconfigs[mod] = reqmod
	end

	return reqmod, mod
end

function module.checkForExplosiveModule(tool)
	if not shared.S.ExplosiveConfigs then return end

	local mod

	if tool:GetAttribute("TConfigToUse") then
		mod = shared.S.ExplosiveConfigs:FindFirstChild(tool:GetAttribute("TConfigToUse"), true)
	else
		mod = shared.S.ExplosiveConfigs:FindFirstChild(tool.Name, true)
	end

	if not mod then return end

	local reqmod = explosiveconfigs[mod]
	if not reqmod then
		reqmod = require(mod)
		explosiveconfigs[mod] = reqmod
	end

	return reqmod, mod
end

function module.checkForAnyModule(tool)
	local reqmod, mod = module.checkForModule(tool)
	if reqmod then return reqmod, mod end

	reqmod, mod = module.checkForMeleeModule(tool)
	if reqmod then return reqmod, mod end

	reqmod, mod = module.checkForExplosiveModule(tool)
	if reqmod then return reqmod, mod end

	return nil
end

------------------------------------------------------------------------
-- TOOL VALIDATION
------------------------------------------------------------------------

function module.returnTool(plr, chr)
	local tool = chr:FindFirstChildOfClass("Tool")
	if not tool then return end

	local configName = tool:GetAttribute("TConfigToUse") or tool.Name

	if gunconfigs[configName] or meleeconfigs[configName] or explosiveconfigs[configName] then
		return tool
	end
end

return module
