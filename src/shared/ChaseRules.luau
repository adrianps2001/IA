--!strict
-- Reglas de la persecución (GDD 5.4, v3) sin dependencias de Roblox: las usan ChaseService y el
-- simulador de bots, así ambos aplican exactamente las mismas condiciones.
-- v3: ya no hay que llevar la criatura al nido. Gana quien la tenga al acabar el tiempo, y el
-- portador solo se ve a distancia cuando "da la señal" (cada pocos segundos y al final).

local Config = require("./Config")

export type StealCheck = "ok" | "noHold" | "tooShort" | "immune" | "tooFar"

local ChaseRules = {}

-- Margen por latencia: el servidor acepta la pulsación un poco antes de 1,5 s.
ChaseRules.HoldTolerance = 0.15
-- Margen de distancia sobre el alcance del prompt (el portador se sigue moviendo).
ChaseRules.DistanceTolerance = 3

-- Segundos que el ladrón tiene que aguantar cerca del portador.
function ChaseRules.holdTime(): number
	return Config.Chase.StealHoldTime
end

-- ¿Es válido un robo? holdStartedAt es cuándo empezó el tira y afloja (medido por el
-- servidor), immuneUntil hasta cuándo es inmune el portador y distance la separación actual.
function ChaseRules.canSteal(now: number, holdStartedAt: number?, immuneUntil: number, distance: number): StealCheck
	if not holdStartedAt then
		return "noHold"
	end
	if now - holdStartedAt < ChaseRules.holdTime() - ChaseRules.HoldTolerance then
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

-- Señal del portador: cada RevealEvery segundos, durante RevealSeconds, todos ven dónde está
-- (a través de los árboles). En los últimos FinalRevealSeconds se le ve todo el rato.
-- elapsed = segundos desde que empezó la persecución; remaining = segundos que quedan.
function ChaseRules.isRevealed(elapsed: number, remaining: number): boolean
	local c = Config.Chase
	if remaining <= c.FinalRevealSeconds then
		return true
	end
	if c.RevealEvery <= 0 then
		return true
	end
	return elapsed % c.RevealEvery >= c.RevealEvery - c.RevealSeconds
end

-- Segundos hasta la próxima señal (0 si ya se le ve).
function ChaseRules.nextReveal(elapsed: number, remaining: number): number
	if ChaseRules.isRevealed(elapsed, remaining) then
		return 0
	end
	local c = Config.Chase
	local untilCycle = c.RevealEvery - c.RevealSeconds - elapsed % c.RevealEvery
	return math.min(untilCycle, remaining - c.FinalRevealSeconds)
end

return ChaseRules
