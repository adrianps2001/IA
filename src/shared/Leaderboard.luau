--!strict
-- Ranking semanal de robos y salón de la fama de nidos (GDD 9 y 11), sin Roblox.
-- LeaderboardService guarda los totales en un OrderedDataStore por semana; aquí están la
-- clave de la semana, las reglas de los "me gusta" y cómo se combinan los datos.

local Config = require("./Config")

export type Entry = { UserId: number, Value: number }
export type LikeState = { Week: string, Given: { number } } -- a quién diste "me gusta" esta semana

local Leaderboard = {}

-- Número de semana: empieza el lunes a las 00:00 UTC (el 1/1/1970 fue jueves).
function Leaderboard.weekIndex(t: number): number
	return math.floor((math.floor(t / 86400) + 3) / 7)
end

function Leaderboard.weekKey(t: number): string
	return "W" .. Leaderboard.weekIndex(t)
end

function Leaderboard.previousWeekKey(t: number): string
	return "W" .. (Leaderboard.weekIndex(t) - 1)
end

-- Segundos que faltan para el cambio de semana (para el cartel).
function Leaderboard.secondsToReset(t: number): number
	local nextStart = ((Leaderboard.weekIndex(t) + 1) * 7 - 3) * 86400
	return math.max(nextStart - t, 0)
end

-- Si cambió la semana, empieza de cero.
function Leaderboard.rollLikes(state: LikeState, week: string): LikeState
	if state.Week ~= week then
		return { Week = week, Given = {} }
	end
	return state
end

function Leaderboard.canLike(state: LikeState, likerId: number, ownerId: number): (boolean, string?)
	if likerId == ownerId then
		return false, "No puedes darte \"me gusta\" a ti mismo."
	end
	if table.find(state.Given, ownerId) then
		return false, "Ya le diste \"me gusta\" a este nido esta semana."
	end
	if #state.Given >= Config.Leaderboard.LikesPerWeek then
		return false, string.format("Ya has dado %d \"me gusta\" esta semana.", Config.Leaderboard.LikesPerWeek)
	end
	return true, nil
end

-- Combina el top guardado con lo sumado en este servidor que aún no se ha enviado, y
-- devuelve los `size` primeros ordenados (empates: menor UserId primero, para que sea estable).
function Leaderboard.merge(stored: { Entry }, pending: { [number]: number }, size: number): { Entry }
	local totals: { [number]: number } = {}
	for _, entry in stored do
		totals[entry.UserId] = math.max(totals[entry.UserId] or 0, entry.Value)
	end
	for userId, delta in pending do
		totals[userId] = (totals[userId] or 0) + delta
	end
	local list: { Entry } = {}
	for userId, value in totals do
		if value > 0 then
			table.insert(list, { UserId = userId, Value = value })
		end
	end
	table.sort(list, function(a: Entry, b: Entry)
		if a.Value ~= b.Value then
			return a.Value > b.Value
		end
		return a.UserId < b.UserId
	end)
	while #list > size do
		table.remove(list)
	end
	return list
end

return Leaderboard
