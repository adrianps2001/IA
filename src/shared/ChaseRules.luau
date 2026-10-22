--!strict
-- Reglas de la persecución (GDD 5.4) sin dependencias de Roblox: las usan ChaseService y el
-- simulador de bots, así ambos aplican exactamente las mismas condiciones.

local Config = require("./Config")

export type StealCheck = "ok" | "noHold" | "tooShort" | "immune" | "tooFar"

local ChaseRules = {}

-- Margen por latencia: el servidor acepta la pulsación un poco antes de 1,5 s.
ChaseRules.HoldTolerance = 0.15
-- Margen de distancia sobre el alcance del prompt (el portador se sigue moviendo).
ChaseRules.DistanceTolerance = 3

-- Segundos que hay que mantener el botón; más si el portador está dentro de su nido.
function ChaseRules.holdTime(carrierAtHome: boolean): number
	return Config.Chase.StealHoldTime * (if carrierAtHome then Config.Chase.HomeHoldMultiplier else 1)
end

-- ¿Es válido un robo? holdStartedAt es cuándo empezó a mantener el botón (medido por el
-- servidor), immuneUntil hasta cuándo es inmune el portador y distance la separación actual.
function ChaseRules.canSteal(
	now: number,
	holdStartedAt: number?,
	immuneUntil: number,
	distance: number,
	carrierAtHome: boolean?
): StealCheck
	if not holdStartedAt then
		return "noHold"
	end
	if now - holdStartedAt < ChaseRules.holdTime(carrierAtHome == true) - ChaseRules.HoldTolerance then
		return "tooShort"
	end
	if now < immuneUntil then
		return "immune"
	end
	if distance > Config.Chase.StealRange + ChaseRules.DistanceTolerance then
		return "tooFar"
	end
	return "ok"
end

-- El portador gana solo si al acabar el tiempo está dentro de su propio nido.
function ChaseRules.carrierWins(insideOwnNest: boolean): boolean
	return insideOwnNest
end

-- Durante la prórroga, entrar en el propio nido con la criatura da la victoria al instante.
function ChaseRules.overtimeWin(inOvertime: boolean, insideOwnNest: boolean): boolean
	return inOvertime and insideOwnNest
end

-- ¿Ha asegurado ya la criatura? homeSeconds = segundos seguidos dentro de su nido.
function ChaseRules.isSecured(homeSeconds: number): boolean
	return Config.Chase.SecureSeconds > 0 and homeSeconds >= Config.Chase.SecureSeconds
end

return ChaseRules
