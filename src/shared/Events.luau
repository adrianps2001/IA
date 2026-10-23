--!strict
-- Eventos con horario (GDD 7): Luna de Sangre, Noche de Saqueo y Huevo Comunitario.
-- Lógica pura (sin Roblox): la usan RoundService, LootService, CommunityService y el
-- simulador. Las horas son UTC.

local Config = require("./Config")
local Genes = require("./Genes")
local Rarity = require("./Rarity")

export type Window = { WeekDays: { number }, StartHour: number, Hours: number }

local Events = {}

-- Día de la semana (1 = domingo, como os.date) y hora UTC de un instante en segundos.
function Events.weekDayAndHour(t: number): (number, number)
	local days = math.floor(t / 86400)
	local wday = ((days + 4) % 7) + 1 -- el 1/1/1970 fue jueves
	local hour = math.floor((t % 86400) / 3600)
	return wday, hour
end

-- ¿Está t dentro de la ventana? Admite ventanas que pasan de medianoche.
function Events.inWindow(window: Window, t: number): boolean
	for offset = 0, 1 do
		local start = t - offset * 86400
		local wday, hour = Events.weekDayAndHour(start)
		if table.find(window.WeekDays, wday) then
			local fromStart = hour + offset * 24 - window.StartHour
			if fromStart >= 0 and fromStart < window.Hours then
				return true
			end
		end
	end
	return false
end

function Events.isBloodMoon(t: number): boolean
	local def = Config.Events.BloodMoon
	for _, hour in def.StartHours do
		if Events.inWindow({ WeekDays = { def.WeekDay }, StartHour = hour, Hours = def.Hours }, t) then
			return true
		end
	end
	return false
end

function Events.isLootNight(t: number): boolean
	return Config.Events.LootNight.Enabled and Events.inWindow(Config.Events.LootNight :: any, t)
end

-- Clave del mes del Huevo Comunitario, p. ej. "2026-10".
function Events.monthKey(t: number): string
	local date = os.date("!*t", math.floor(t)) :: any
	return string.format("%04d-%02d", date.year, date.month)
end

-- Genes de la criatura conmemorativa del mes: la misma para todo el mundo.
function Events.communityGenes(monthKey: string): Genes.GeneSet
	local state = 0
	for i = 1, #monthKey do
		state = (state * 31 + string.byte(monthKey, i)) % 2147483647
	end
	local function rng(): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
	return Genes.rollSet(rng, Config.Events.Community.Rarity :: Rarity.RarityName)
end

export type LootCheck = {
	Now: number,
	HoldStartedAt: number?, -- cuándo empezó a mantener el botón (medido por el servidor)
	Distance: number,
	IsOwner: boolean,
	OwnerHome: boolean, -- el dueño está dentro de su nido: defensas activas
	Rarity: Rarity.RarityName,
	LootsThisRound: number,
	NestCooldownUntil: number,
}

-- ¿Es válido un saqueo? Devuelve el motivo si no lo es (para avisar al jugador).
function Events.canLoot(c: LootCheck): (boolean, string?)
	local def = Config.Events.LootNight
	if c.IsOwner then
		return false, "Es tu propio nido."
	end
	if c.Rarity == "Secret" then
		return false, "Las criaturas Secretas son inmunes al saqueo."
	end
	if c.OwnerHome then
		return false, "El dueño está en su nido: las defensas están activas."
	end
	if c.LootsThisRound >= def.PerRound then
		return false, "Ya has saqueado en esta ronda."
	end
	if c.Now < c.NestCooldownUntil then
		return false, "Este nido acaba de ser saqueado."
	end
	if c.Distance > def.MaxDistance then
		return false, nil
	end
	if not c.HoldStartedAt or c.Now - c.HoldStartedAt < def.HoldSeconds - 0.25 then
		return false, nil
	end
	return true, nil
end

-- El Huevo Comunitario: ¿le toca la criatura a este jugador?
function Events.communityEligible(contributed: number, claimed: boolean, total: number): boolean
	local def = Config.Events.Community
	return not claimed and total >= def.Goal and contributed >= def.MinContribution
end

return Events
