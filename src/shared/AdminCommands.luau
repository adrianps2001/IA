--!strict
-- Comandos de soporte y moderación (v3.1), sin Roblox para poder probarlos. AdminService los
-- escucha en el chat. Empiezan por "!" (o "/"), por ejemplo: !ver Ana, !dar monedas Ana 5000,
-- !ban Ana 24 insultos. Solo funcionan para los administradores (Config.Admins y el dueño).

local Config = require("./Config")

local AdminCommands = {}

export type Command = { Name: string, Args: { string } }

AdminCommands.Help = {
	"!ver <jugador> · resumen de su perfil",
	"!dar monedas|polvo <jugador> <cantidad>",
	"!dar criatura <jugador> <rareza> (Common, Rare, Epic, Legendary, Mythic, Secret)",
	"!echar <jugador> <motivo>",
	"!ban <jugador> <horas> <motivo> (horas 0 = para siempre)",
	"!desban <UserId>",
	"!anuncio <texto> · aviso para todo el servidor",
}

-- Lee un mensaje del chat. nil si no es un comando.
function AdminCommands.parse(text: string): Command?
	local trimmed = string.match(text, "^%s*(.-)%s*$") or ""
	local first = string.sub(trimmed, 1, 1)
	if first ~= "!" and first ~= "/" then
		return nil
	end
	local words = {}
	for word in string.gmatch(string.sub(trimmed, 2), "%S+") do
		table.insert(words, word)
	end
	if #words == 0 then
		return nil
	end
	local name = string.lower(table.remove(words, 1) :: string)
	-- Los de Roblox (/e, /w, /me…) no son nuestros.
	if first == "/" and (name == "e" or name == "w" or name == "me" or name == "emote" or name == "whisper" or name == "team" or name == "t" or name == "mute" or name == "unmute" or name == "help" or name == "console") then
		return nil
	end
	return { Name = name, Args = words }
end

-- ¿Puede usar los comandos? creatorUserId es el dueño de la experiencia (0 si es un grupo).
function AdminCommands.isAdmin(userId: number, creatorUserId: number): boolean
	if userId > 0 and userId == creatorUserId then
		return true
	end
	return table.find(Config.Admins, userId) ~= nil
end

-- Une los argumentos desde `from` (para motivos y textos con espacios).
function AdminCommands.rest(args: { string }, from: number): string
	return table.concat(args, " ", from)
end

return AdminCommands
