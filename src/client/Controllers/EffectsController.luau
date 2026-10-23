--!strict
-- Efectos locales: el latido del huevo que se acelera al llenarse la barra (GDD 8, la firma
-- del juego; ahora también suena), el color animado de las criaturas Secretas y el saltito
-- de las criaturas de los nidos (GDD v3: atributo Idle), que así parecen vivas.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local RoundState = require(Shared.RoundState)

local SoundController = require(script.Parent.SoundController)

local EffectsController = {}

local BASE_SIZE = Vector3.new(14, 18, 14)

local function eggPart(): BasePart?
	local map = workspace:FindFirstChild("Map")
	local egg = map and map:FindFirstChild("Egg")
	return if egg and egg:IsA("BasePart") then egg else nil
end

type Idle = { Base: CFrame, Phase: number }
local idle: { [Model]: Idle } = {}

local function tagRainbow(instance: Instance)
	if instance:IsA("Model") and instance:GetAttribute("Rainbow") then
		CollectionService:AddTag(instance, "RainbowCreature")
	end
	if instance:IsA("Model") and instance:GetAttribute("Idle") then
		idle[instance] = { Base = instance:GetPivot(), Phase = math.random() * 6 }
	end
end

-- Saltito y vaivén de las criaturas expuestas cercanas (solo en este cliente).
local idleAccumulator = 0
local function animateIdle(dt: number)
	idleAccumulator += dt
	if idleAccumulator < 1 / 30 then
		return
	end
	idleAccumulator = 0
	local camera = workspace.CurrentCamera
	local from = if camera then camera.CFrame.Position else Vector3.zero
	local now = os.clock()
	for model, info in idle do
		if not model.Parent then
			idle[model] = nil
		elseif (info.Base.Position - from).Magnitude < 90 then
			local t = now + info.Phase
			local hop = math.abs(math.sin(t * 2.2)) * 0.25
			model:PivotTo(info.Base * CFrame.new(0, hop, 0) * CFrame.Angles(0, math.sin(t * 0.6) * 0.3, 0))
		end
	end
end

function EffectsController.start()
	workspace.DescendantAdded:Connect(tagRainbow)
	for _, descendant in workspace:GetDescendants() do
		tagRainbow(descendant)
	end

	local phaseTime = 0
	local beatPlayed = false
	local player = Players.LocalPlayer
	RunService.RenderStepped:Connect(function(dt)
		animateIdle(dt)
		local egg = eggPart()
		local phase = RoundState.phase()
		if egg and (phase == "Incubation" or phase == "Intermission" or phase == "Hatch") then
			local bar = tonumber(RoundState.get("Bar")) or 0
			local goal = tonumber(RoundState.get("BarGoal")) or 1
			local fraction = if phase == "Hatch" then 1 else math.clamp(bar / math.max(goal, 1), 0, 1)
			-- De 50 a 150 latidos por minuto.
			local bpm = 50 + 100 * fraction
			phaseTime += dt * bpm / 60
			local wave = math.sin(phaseTime * math.pi * 2)
			local beat = math.max(0, wave) ^ 6
			-- El latido suena en cada pico (solo para quien está en la partida).
			if wave > 0.95 and not beatPlayed then
				beatPlayed = true
				if player:GetAttribute("InMatch") then
					SoundController.play("Heartbeat", egg)
				end
			elseif wave < 0.5 then
				beatPlayed = false
			end
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
