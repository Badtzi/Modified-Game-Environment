local chr = script.Parent
local hum = chr:FindFirstChild("Humanoid")

if not hum then return end

while true do
	hum.Health -= script.Rate.Value
	task.wait(0.2)
end
