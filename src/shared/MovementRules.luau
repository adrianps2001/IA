--!strict
-- Reglas de movimiento del anti-trampas (v3.1), sin Roblox para poder probarlas.
-- En tirolinas, toboganes y setas el cliente mueve a su propio personaje, así que el servidor
-- comprueba que nadie vaya más rápido de lo que permite el juego.

local Config = require("./Config")

local MovementRules = {}

export type Verdict = "ok" | "tooFast" | "tooHigh"

-- Movimiento entre dos comprobaciones separadas `dt` segundos: dx y dz en horizontal, dy en
-- vertical (positivo = sube). Caer muy rápido no cuenta: caerse es legal.
function MovementRules.check(dx: number, dy: number, dz: number, dt: number): Verdict
	if dt <= 0 then
		return "ok"
	end
	local ac = Config.AntiCheat
	if math.sqrt(dx * dx + dz * dz) > ac.MaxHorizontalSpeed * dt + ac.Slack then
		return "tooFast"
	end
	if dy > ac.MaxRiseSpeed * dt + ac.Slack then
		return "tooHigh"
	end
	return "ok"
end

-- Avisos que siguen contando: los de los últimos StrikeWindow segundos.
function MovementRules.recentStrikes(strikes: { number }, now: number): { number }
	local recent = {}
	for _, at in strikes do
		if now - at <= Config.AntiCheat.StrikeWindow then
			table.insert(recent, at)
		end
	end
	return recent
end

return MovementRules
