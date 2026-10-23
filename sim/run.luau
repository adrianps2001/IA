--!strict
-- Punto de entrada del simulador de bots. Se ejecuta con el luau de la terminal:
--
--   luau sim/run.luau -a partida [semilla] [jugadores]   -- una partida de prueba narrada
--   luau sim/run.luau -a repeticion [semilla] [jugadores] -- la misma partida en JSON (para la web)
--   luau sim/run.luau -a meta [semilla] [días] [población] -- semanas de juego en JSON
--
-- Añade --codegen antes del archivo para que vaya más rápido.

local Config = require("../src/shared/Config")
local Rarity = require("../src/shared/Rarity")
local Json = require("../tools/Json")

local Archetypes = require("./Archetypes")
local Meta = require("./Meta")
local Rng = require("./Rng")
local Round = require("./Round")

-- Los argumentos con "=" cambian Config solo para esta ejecución, p. ej. Chase.StealHoldTime=2.
local args = {}
local overrides = {}
for _, arg in { ... } do
	local path, value = string.match(arg, "^([%w%.]+)=(.+)$")
	if path then
		local target: any = Config
		local keys = string.split(path, ".")
		for i = 1, #keys - 1 do
			target = target[keys[i]]
			assert(type(target) == "table", "Ajuste desconocido: " .. path)
		end
		local last = keys[#keys]
		assert(target[last] ~= nil, "Ajuste desconocido: " .. path)
		target[last] = tonumber(value) or (if value == "true" then true elseif value == "false" then false else value)
		table.insert(overrides, arg)
	else
		table.insert(args, arg)
	end
end
local mode = args[1] or "partida"
local seed = tonumber(args[2]) or 1
-- (luau CLI no tiene io: los ajustes se muestran en la salida de cada modo)
local overridesText = if #overrides > 0 then table.concat(overrides, " ") else "ninguno"

-- Bots para una sola partida, con la mezcla de arquetipos por defecto.
local function makeBots(count: number, rng: Rng.Rng): { Round.Bot }
	local pool = {}
	for key, share in Archetypes.DefaultMix do
		for _ = 1, math.max(1, math.floor(share * 20 + 0.5)) do
			table.insert(pool, key)
		end
	end
	table.sort(pool)
	Rng.shuffle(rng, pool)
	local bots = {}
	for i = 1, count do
		local arch = Archetypes.ByKey[pool[(i - 1) % #pool + 1]]
		table.insert(bots, {
			Id = i,
			Name = string.format("%s %d", arch.Label, i),
			Arch = arch,
			Upgrades = { Bag = Rng.int(rng, 0, 4), Boots = Rng.int(rng, 0, 4), Sniffer = 0, Nest = 0, Incubator = 0 },
			Payer = arch.Payer,
		})
	end
	Round.formParties(bots, rng)
	return bots
end

if mode == "partida" or mode == "repeticion" then
	local players = math.clamp(tonumber(args[3]) or 12, 2, Config.Round.MaxPlayers)
	local rng = Rng.new(seed)
	local bots = makeBots(players, rng)
	local summary, perBot, extra = Round.run(bots, rng, { Log = true, Record = mode == "repeticion" })

	if mode == "repeticion" then
		local botList = {}
		for _, bot in bots do
			local r = perBot[bot.Id]
			table.insert(botList, {
				Id = bot.Id,
				Name = bot.Name,
				Arch = bot.Arch.Key,
				Deposited = r.Deposited,
				Affinity = r.Affinity,
				Steals = r.Steals,
				Dust = r.Dust,
				Won = r.Won,
				Chosen = r.Chosen,
			})
		end
		print(Json.encode({ Seed = seed, Overrides = overrides, Summary = summary, Bots = botList, Log = extra.Log, Frames = extra.Frames, Nests = extra.Nests }))
	else
		print(string.format("=== Partida de prueba · semilla %d · %d bots · ajustes: %s ===\n", seed, players, overridesText))
		for _, entry in extra.Log do
			print(string.format("[%-11s %3d s] %s", entry.Phase, entry.T, entry.Text))
		end
		print("\n--- Resumen ---")
		print(string.format("Incubación: %d s (barra al %d %%%s)", summary.IncubationSeconds, math.floor(summary.BarFraction * 100), if summary.EarlyFull then ", llena antes de tiempo" else ""))
		print(string.format("Criatura: %s · elegido puesto %d de Afinidad con %.1f %% de probabilidad", Rarity.Info[summary.Rarity].DisplayName, summary.ChosenRank, summary.ChosenChance * 100))
		print(string.format("Persecución: %d robos, %d relevos, %d puertas, %d traiciones, %d portadores distintos", summary.Steals, summary.Passes, summary.Doors, summary.Betrayals, summary.Carriers))
		print(string.format("Resultado: %s", if summary.Escaped then "la criatura escapó" else "ganó " .. (bots[summary.WinnerId :: number].Name) .. (if summary.WinnerIsChosen then " (el elegido)" else "")))
		print("\n--- Jugadores ---")
		print(string.format("%-24s %9s %8s %6s %6s %6s", "Bot", "Depositó", "Probab.", "Robos", "Polvo", ""))
		for _, bot in bots do
			local r = perBot[bot.Id]
			print(string.format("%-24s %9d %7.1f%% %6d %6d %s", bot.Name, r.Deposited, r.Chance * 100, r.Steals, r.Dust, if r.Won then "🏆" elseif r.Chosen then "🥚" else ""))
		end
	end
elseif mode == "lote-json" then
	-- Igual que "lote" pero devuelve cada partida en JSON (lo usa tools/sim_report.py).
	local count = tonumber(args[3]) or 200
	local players = math.clamp(tonumber(args[4]) or 12, 2, Config.Round.MaxPlayers)
	local rng = Rng.new(seed)
	local list = {}
	for _ = 1, count do
		local summary = Round.run(makeBots(players, rng), rng, {})
		table.insert(list, summary)
	end
	print(Json.encode({ Seed = seed, Players = players, Overrides = overrides, Rounds = list }))
elseif mode == "lote" then
	-- Muchas partidas sueltas para medir la persecución: luau sim/run.luau -a lote [semilla] [partidas] [jugadores]
	local count = tonumber(args[3]) or 300
	local players = math.clamp(tonumber(args[4]) or 12, 2, Config.Round.MaxPlayers)
	local rng = Rng.new(seed)
	local list = {}
	for _ = 1, count do
		local summary = Round.run(makeBots(players, rng), rng, {})
		table.insert(list, summary)
	end
	local function avg(field: string): number
		local total: number = 0
		for _, s in list do
			total += (s :: any)[field] or 0
		end
		return total / #list
	end
	local function share(test: (any) -> boolean): number
		local n: number = 0
		for _, s in list do
			if test(s) then
				n += 1
			end
		end
		return n / #list
	end
	print(string.format("%d partidas de %d bots (semilla %d) · ajustes: %s", count, players, seed, overridesText))
	print(string.format("  Incubación media: %.0f s · barra llena antes de tiempo: %.0f %%", avg("IncubationSeconds"), share(function(s) return s.EarlyFull end) * 100))
	print(string.format("  Robos por partida: %.1f · portadores distintos: %.1f · relevos: %.2f · puertas: %.2f", avg("Steals"), avg("Carriers"), avg("Passes"), avg("Doors")))
	print(string.format("  La criatura escapa: %.0f %% · gana el elegido: %.0f %% · asegurada: %.0f %% · persecución media: %.0f s", share(function(s) return s.Escaped end) * 100, share(function(s) return s.WinnerIsChosen end) * 100, share(function(s) return s.Secured end) * 100, avg("ChaseSeconds")))
	print(string.format("  Prórroga: %.0f %% de las partidas", share(function(s) return s.Overtime end) * 100))
	print(string.format("  Barra media al eclosionar: %.0f %% · rareza mínima Épica: %.0f %%", avg("BarFraction") * 100, share(function(s) return s.MinRarity == "Epic" end) * 100))
	print(string.format("  Primera llegada del portador a su nido: %.0f %% de las partidas", share(function(s) return s.FirstHomeSeconds ~= nil end) * 100))
	print(string.format("  Empujones: %.1f · géiseres: %.1f · tratos: %.1f · traiciones: %.2f", avg("Bumps"), avg("Geysers"), avg("Deals"), avg("Betrayals")))
	-- Diagnóstico de las fugas: dónde estaba el portador y cuánto hacía que la tenía.
	local escapes, farSum, agoSum, recent = 0, 0, 0, 0
	for _, s in list do
		if s.Escaped then
			escapes += 1
			farSum += s.FinalDistanceToNest
			agoSum += s.LastChangeAgo
			if s.LastChangeAgo < 15 then
				recent += 1
			end
		end
	end
	if escapes > 0 then
		print(string.format("  Fugas: el portador estaba a %.0f studs de su nido y la tenía desde hacía %.0f s (%.0f %% robadas en los últimos 15 s)", farSum / escapes, agoSum / escapes, recent / escapes * 100))
	end
	local winners: { [string]: number } = {}
	for _, s in list do
		if s.WinnerArch then
			winners[s.WinnerArch] = (winners[s.WinnerArch] or 0) + 1
		end
	end
	for key, n in winners do
		print(string.format("  Ganador %-10s %5.1f %%", key, n / #list * 100))
	end
elseif mode == "meta" then
	local params = table.clone(Meta.Defaults)
	params.Seed = seed
	params.Days = tonumber(args[3]) or params.Days
	params.Population = tonumber(args[4]) or params.Population
	local started = os.clock()
	local result: { [string]: any } = table.clone(Meta.run(params)) :: any
	result.ElapsedSeconds = os.clock() - started
	result.Overrides = overrides
	print(Json.encode(result))
else
	error("Modo desconocido: " .. tostring(mode) .. " (usa partida, repeticion o meta)")
end
