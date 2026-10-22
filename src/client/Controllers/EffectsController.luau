--!strict
-- Efectos locales: el latido del huevo que se acelera al llenarse la barra (GDD 8, la firma
-- del juego) y el color animado de las criaturas Secretas.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local RoundState = require(Shared.RoundState)

local EffectsController = {}

local BASE_SIZE = Vector3.new(14, 18, 14)

local function eggPart(): BasePart?
	local map = workspace:FindFirstChild("Map")
	local egg = map and map:FindFirstChild("Egg")
	return if egg and egg:IsA("BasePart") then egg else nil
end

local function tagRainbow(instance: Instance)
	if instance:IsA("Model") and instance:GetAttribute("Rainbow") then
		CollectionService:AddTag(instance, "RainbowCreature")
	end
end

function EffectsController.start()
	workspace.DescendantAdded:Connect(tagRainbow)
	for _, descendant in workspace:GetDescendants() do
		tagRainbow(descendant)
	end

	local phaseTime = 0
	RunService.RenderStepped:Connect(function(dt)
		local egg = eggPart()
		local phase = RoundState.phase()
		if egg and (phase == "Incubation" or phase == "Intermission") then
			local bar = tonumber(RoundState.get("Bar")) or 0
			local goal = tonumber(RoundState.get("BarGoal")) or 1
			local fraction = math.clamp(bar / math.max(goal, 1), 0, 1)
			-- De 50 a 150 latidos por minuto.
			local bpm = 50 + 100 * fraction
			phaseTime += dt * bpm / 60
			local beat = math.max(0, math.sin(phaseTime * math.pi * 2)) ^ 6
			egg.Size = BASE_SIZE * (1 + beat * (0.03 + 0.05 * fraction))
		elseif egg and egg.Size ~= BASE_SIZE then
			egg.Size = BASE_SIZE
		end

		local hue = (os.clock() * 0.25) % 1
		for _, model in CollectionService:GetTagged("RainbowCreature") do
			local primary = if model:IsA("Model") then model.PrimaryPart else nil
			if primary then
				primary.Color = Color3.fromHSV(hue, 0.8, 1)
			end
		end
	end)
end

return EffectsController
