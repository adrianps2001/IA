--!strict
-- La Elección (GDD 5.3): probabilidad = Afinidad / Afinidad total, con un mínimo garantizado
-- para todos. Quien queda por debajo del mínimo recibe exactamente el mínimo y el resto
-- se reparte la probabilidad restante en proporción a su Afinidad.

local Election = {}

export type Entry = { Key: string, Affinity: number }

function Election.chances(entries: { Entry }, minChance: number): { [string]: number }
	local result: { [string]: number } = {}
	local count = #entries
	if count == 0 then
		return result
	end

	-- Si el mínimo no cabe para todos, todos reciben lo mismo.
	if minChance * count >= 1 then
		for _, entry in entries do
			result[entry.Key] = 1 / count
		end
		return result
	end

	local pinned: { [string]: boolean } = {}
	while true do
		local freeMass = 1
		local freeAffinity = 0
		for _, entry in entries do
			if pinned[entry.Key] then
				freeMass -= minChance
			else
				freeAffinity += math.max(entry.Affinity, 0)
			end
		end

		local changed = false
		for _, entry in entries do
			if not pinned[entry.Key] then
				local share
				if freeAffinity > 0 then
					share = freeMass * math.max(entry.Affinity, 0) / freeAffinity
				else
					local freeCount = 0
					for _, other in entries do
						if not pinned[other.Key] then
							freeCount += 1
						end
					end
					share = freeMass / freeCount
				end
				if share < minChance then
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
		result[key] = minChance
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
