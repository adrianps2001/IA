--!strict
-- La Elección (GDD 5.3): probabilidad = Afinidad / Afinidad total, con un mínimo garantizado
-- para todos. Quien queda por debajo de su mínimo recibe exactamente ese mínimo y el resto
-- se reparte la probabilidad restante en proporción a su Afinidad.
-- Cada entrada puede traer su propio mínimo (Min): así funciona la "suerte acumulada" de
-- quien lleva muchas rondas sin ser elegido (ver Election.pityMin).

local Config = require("./Config")

local Election = {}

export type Entry = { Key: string, Affinity: number, Min: number? }

-- Mínimo de un jugador que lleva roundsSinceChosen rondas sin ser elegido.
function Election.pityMin(roundsSinceChosen: number): number
	local e = Config.Election
	return math.min(e.MinChance + e.PityPerRound * math.max(roundsSinceChosen, 0), math.max(e.PityMaxChance, e.MinChance))
end

function Election.chances(entries: { Entry }, minChance: number): { [string]: number }
	local result: { [string]: number } = {}
	local count = #entries
	if count == 0 then
		return result
	end

	local function minOf(entry: Entry): number
		return entry.Min or minChance
	end

	-- Si los mínimos no caben, se reparte en proporción a ellos.
	local totalMin = 0
	for _, entry in entries do
		totalMin += minOf(entry)
	end
	if totalMin >= 1 then
		for _, entry in entries do
			result[entry.Key] = if totalMin > 0 then minOf(entry) / totalMin else 1 / count
		end
		return result
	end

	local pinned: { [string]: boolean } = {}
	while true do
		local freeMass = 1
		local freeAffinity = 0
		local freeCount = 0
		for _, entry in entries do
			if pinned[entry.Key] then
				freeMass -= minOf(entry)
			else
				freeAffinity += math.max(entry.Affinity, 0)
				freeCount += 1
			end
		end

		local changed = false
		for _, entry in entries do
			if not pinned[entry.Key] then
				local share = if freeAffinity > 0
					then freeMass * math.max(entry.Affinity, 0) / freeAffinity
					else freeMass / freeCount
				if share < minOf(entry) then
					pinned[entry.Key] = true
					changed = true
				else
					result[entry.Key] = share
				end
			end
		end

		if not changed then
			break
		end
	end

	for key in pinned do
		for _, entry in entries do
			if entry.Key == key then
				result[key] = minOf(entry)
			end
		end
	end
	return result
end

-- Elige una clave con las probabilidades anteriores. Devuelve también las probabilidades
-- para que los clientes puedan mostrarlas en la ruleta.
function Election.pick(entries: { Entry }, minChance: number, rng: () -> number): (string?, { [string]: number })
	local chances = Election.chances(entries, minChance)
	if #entries == 0 then
		return nil, chances
	end
	local roll = rng()
	for _, entry in entries do
		roll -= chances[entry.Key]
		if roll < 0 then
			return entry.Key, chances
		end
	end
	return entries[#entries].Key, chances
end

return Election
