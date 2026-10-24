--!strict
-- Punto de entrada del simulador de bots. Se ejecuta con el luau de la terminal:
--
--   luau sim/run.luau -a partida [semilla] [jugadores]   -- una partida de prueba narrada
--   luau sim/run.luau -a repeticion [semilla] [jugadores] -- la misma partida en JSON (para la web)
--   luau sim/run.luau -a meta [semilla] [días] [población] -- semanas de juego en JSON
--
-- Añade --codegen antes del archivo para que vaya más rápido.

local ArenaLayout = require("../src/shared/ArenaLayout")
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
			Upgrades = { Bag = Rng.int(rng, 0, 4), Boots = Rng.int(rng, 0, 4), Nest = 0, Incubator = 0 },
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
				Won = #r.Won > 0,
				Chosen = r.Chosen,
			})
		end
		-- Árboles del parkour para dibujarlos en la repetición.
		local trees = {}
		for _, tree in ArenaLayout.get().Trees do
			table.insert(trees, { X = math.floor(tree.X), Z = math.floor(tree.Z), R = math.floor(tree.Radius) })
		end
		print(Json.encode({ Seed = seed, Overrides = overrides, Summary = summary, Bots = botList, Log = extra.Log, Frames = extra.Frames, Nests = extra.Nests, Trees = trees }))
	else
		print(string.format("=== Partida de prueba · semilla %d · %d bots · ajustes: %s ===\n", seed, players, overridesText))
		for _, entry in extra.Log do
			print(string.format("[%-11s %3d s] %s", entry.Phase, entry.T, entry.Text))
		end
		print("\n--- Resumen ---")
		print(string.format("Incubación: %d s (barra al %d %%%s) · %d criatura%s%s", summary.IncubationSeconds, math.floor(summary.BarFraction * 100), if summary.EarlyFull then ", llena antes de tiempo" else "", summary.Creatures, if summary.Creatures == 1 then "" else "s", if summary.Foxes > 0 then string.format(" · %d zorros", summary.Foxes) else ""))
		print(string.format("Persecución: %d robos, %d escudos rotos, %d relevos, %d traiciones, %d portadores distintos, señal %d s", summary.Steals, summary.ShieldBlocks, summary.Passes, summary.Betrayals, summary.Carriers, summary.RevealedSeconds))
		local chaseList: { any } = summary.Chases
		for index = 1, #chaseList do
			local c = chaseList[index]
			local rarityName: string = tostring((Rarity.Info :: any)[c.Rarity].DisplayName)
			local result: string = if c.Escaped
				then "escapó"
				else "ganó " .. tostring(bots[c.WinnerId :: number].Name) .. (if c.WinnerIsChosen then " (el elegido)" else "")
			local rank: number = c.ChosenRank
			local chance: number = c.ChosenChance * 100
			print(string.format("Criatura %d (%s): elegido puesto %d de Afinidad con %.1f %% · %s", index, rarityName, rank, chance, result))
		end
		print("\n--- Jugadores ---")
		print(string.format("%-24s %9s %8s %6s %6s %6s", "Bot", "Depositó", "Probab.", "Robos", "Polvo", ""))
		for _, bot in bots do
			local r = perBot[bot.Id]
			print(string.format("%-24s %9d %7.1f%% %6d %6d %s", bot.Name, r.Deposited, r.Chance * 100, r.Steals, r.Dust, if #r.Won > 0 then "🏆" elseif r.Chosen then "🥚" else ""))
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
	-- Las estadísticas de la persecución son por criatura (puede haber varias por ronda).
	local chasesList = {}
	for _, s in list do
		for _, c in s.Chases do
			table.insert(chasesList, c)
		end
	end
	local function chaseShare(test: (any) -> boolean): number
		local n: number = 0
		for _, c in chasesList do
			if test(c) then
				n += 1
			end
		end
		return n / math.max(#chasesList, 1)
	end
	local function chaseAvg(field: string): number
		local total: number = 0
		for _, c in chasesList do
			total += (c :: any)[field] or 0
		end
		return total / math.max(#chasesList, 1)
	end
	print(string.format("%d partidas de %d bots (semilla %d) · ajustes: %s", count, players, seed, overridesText))
	print(string.format("  Incubación media: %.0f s · barra llena antes de tiempo: %.0f %% · ronda completa: %.1f min", avg("IncubationSeconds"), share(function(s) return s.EarlyFull end) * 100, avg("DurationSeconds") / 60))
	print(string.format("  Criaturas por ronda: %.2f · zorros: %.1f · robos por criatura: %.1f · escudos rotos por ronda: %.1f · tiradas al suelo: %.2f", avg("Creatures"), avg("Foxes"), chaseAvg("Steals"), avg("ShieldBlocks"), avg("FoxDrops")))
	print(string.format("  La criatura escapa: %.0f %% · gana el elegido: %.0f %% · cambió de manos en los últimos 10 s: %.0f %% · persecución media: %.0f s", chaseShare(function(c) return c.Escaped end) * 100, chaseShare(function(c) return c.WinnerIsChosen end) * 100, chaseShare(function(c) return c.LastChangeAgo <= 10 end) * 100, avg("ChaseSeconds")))
	print(string.format("  Barra media al eclosionar: %.0f %% · rareza mínima Épica: %.0f %% · relevos: %.2f", avg("BarFraction") * 100, share(function(s) return s.MinRarity == "Epic" end) * 100, avg("Passes")))
	print(string.format("  Empujones: %.1f · géiseres: %.1f · tratos: %.1f · traiciones: %.2f", avg("Bumps"), avg("Geysers"), avg("Deals"), avg("Betrayals")))
	-- Victorias por ronda de cada tipo de jugador (sobre las rondas jugadas por ese tipo).
	local winners: { [string]: number } = {}
	for _, c in chasesList do
		if c.WinnerArch then
			winners[c.WinnerArch] = (winners[c.WinnerArch] or 0) + 1
		end
	end
	local keys = {}
	for key in winners do
		table.insert(keys, key)
	end
	table.sort(keys)
	local parts = {}
	for _, key in keys do
		table.insert(parts, string.format("%s %.1f %%", key, winners[key] / math.max(#chasesList, 1) * 100))
	end
	print("  Ganadores (por criatura): " .. table.concat(parts, " · "))
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
