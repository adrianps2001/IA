--!strict
-- Estado de la ronda replicado como atributos de una carpeta en ReplicatedStorage.
-- El servidor escribe; los clientes leen y escuchan cambios.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type Phase = "Waiting" | "Intermission" | "Incubation" | "Hatch" | "Chase" | "Results"

local RoundState = {}

RoundState.PhaseNames = {
	Waiting = "Esperando jugadores",
	Intermission = "Preparados",
	Incubation = "Incubación",
	Hatch = "¡Eclosión!",
	Chase = "Persecución",
	Results = "Resultados",
} :: { [Phase]: string }

-- Atributos: Phase, PhaseEndsAt (GetServerTimeNow), Bar, BarGoal, MinRarity, Luck,
-- CarrierUserId, ChosenUserId, CreatureName, CreatureRarity, BloodMoon, ServerLuckEndsAt, Round
local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("RoundState")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "RoundState"
		folder.Parent = ReplicatedStorage
	end
else
	folder = ReplicatedStorage:WaitForChild("RoundState") :: Folder
end

RoundState.Folder = folder

function RoundState.get(name: string): any
	return folder:GetAttribute(name)
end

function RoundState.set(name: string, value: any)
	folder:SetAttribute(name, value)
end

function RoundState.phase(): Phase
	return (folder:GetAttribute("Phase") or "Waiting") :: Phase
end

function RoundState.timeLeft(): number
	local endsAt = folder:GetAttribute("PhaseEndsAt")
	if type(endsAt) ~= "number" then
		return 0
	end
	return math.max(0, endsAt - workspace:GetServerTimeNow())
end

function RoundState.changed(name: string): RBXScriptSignal
	return folder:GetAttributeChangedSignal(name)
end

return RoundState
