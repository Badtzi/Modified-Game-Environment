local effects = {}

local effectsPath = shared.S.TREK_Modules:WaitForChild('ImpactTypes')

for i, module in pairs(effectsPath:GetChildren()) do
	if not module:IsA('ModuleScript') then continue end
	effects[module.Name] = require(module)
end

return effects