--!strict
-- Ayudas para probar en Roblox Studio (ver Config.Testing y docs/PRUEBAS.md).
-- Todo lo de este módulo solo tiene efecto en Studio: en un servidor publicado devuelve los
-- valores normales, así que no hay forma de activarlo desde fuera.

local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)

export type Flag = "Autopilot" | "DebugTools" | "ForceLootNight"

local Testing = {}

function Testing.inStudio(): boolean
	return RunService:IsStudio()
end

function Testing.enabled(flag: Flag): boolean
	return RunService:IsStudio() and (Config.Testing :: any)[flag] == true
end

-- Duración de una fase: en Studio se acorta con Config.Testing.TimeScale para probar rápido.
function Testing.duration(seconds: number): number
	if RunService:IsStudio() then
		return math.max(seconds * Config.Testing.TimeScale, 5)
	end
	return seconds
end

return Testing
