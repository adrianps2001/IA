--!strict
-- ¿Qué es este servidor? (GDD v3) El juego tiene dos lugares con el mismo código:
-- * "Lobby": nidos, tienda, intercambios, Bandada y la cola para jugar.
-- * "Match": la arena con el huevo; una partida y vuelta al lobby.
-- * "Combined": los dos en el mismo mundo (en Studio o si Config.Places no está rellenado).
--   El lobby y la arena están lejos el uno del otro y "teletransportar" es mover al jugador.

local Config = require(script.Parent.Config)

export type Kind = "Lobby" | "Match" | "Combined"

local Place = {}

function Place.kind(): Kind
	local id = game.PlaceId
	if Config.Places.Match ~= 0 and id == Config.Places.Match then
		return "Match"
	end
	if Config.Places.Lobby ~= 0 and Config.Places.Match ~= 0 and id == Config.Places.Lobby then
		return "Lobby"
	end
	return "Combined"
end

-- ¿Hay lobby (nidos completos, tienda, cola) en este servidor?
function Place.hasLobby(): boolean
	return Place.kind() ~= "Match"
end

-- ¿Hay arena (huevo, persecución) en este servidor?
function Place.hasArena(): boolean
	return Place.kind() ~= "Lobby"
end

return Place
