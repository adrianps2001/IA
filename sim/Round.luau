--!strict
-- Simula una ronda completa (GDD 4-5) con bots en el plano del mapa:
-- Incubación (Calor, géiseres, empujones, depósitos, lluvia dorada) -> Eclosión (Elección de
-- uno o varios elegidos) -> Persecución (una por criatura: robos por toque, escudos,
-- inmunidad, esprint, relevo, puerta, zorros del bosque) -> Premios.
-- Usa los módulos reales del juego (Config, Economy, Election, Genes, Rarity, ChaseRules,
-- Rewards, MapLayout) para que las reglas sean idénticas a las del servidor.
-- Simplificaciones: sin física ni árboles; las paredes solo cuentan en la entrada del nido.

local Config = require("../src/shared/Config")
local ChaseRules = require("../src/shared/ChaseRules")
local Economy = require("../src/shared/Economy")
local Election = require("../src/shared/Election")
local Genes = require("../src/shared/Genes")
local MapLayout = require("../src/shared/MapLayout")
local Rarity = require("../src/shared/Rarity")
local Rewards = require("../src/shared/Rewards")

local Archetypes = require("./Archetypes")
local Rng = require("./Rng")

type Point = MapLayout.Point
type Rng = Rng.Rng

-- Bot persistente (vive entre rondas; lo crea Meta o run.luau).
export type Bot = {
	Id: number,
	Name: string,
	Arch: Archetypes.Archetype,
	Upgrades: { [string]: number },
	Payer: boolean,
	RoundsSinceChosen: number?,
	RoundsPlayed: number?, -- nil = veterano
	Party: number?, -- Bandada (bots con el mismo número)
}

type Chase = {
	Index: number,
	Rarity: Rarity.RarityName,
	Genes: Genes.GeneSet,
	Chosen: Agent,
	ChosenChance: number,
	ChosenRank: number,
	Carrier: Agent?, -- nil = la criatura está suelta en LoosePos
	LoosePos: Point,
	ImmuneUntil: number,
	HomeStreak: number,
	Done: boolean,
	Secured: boolean,
	Overtime: boolean,
	Winner: Agent?,
	Steals: number,
	Carriers: { [string]: boolean },
	FirstHome: number?,
	LastChange: number,
	Drops: number, -- veces que un zorro la tiró al suelo
}

-- Estado del bot dentro de una ronda.
type Agent = {
	Bot: Bot,
	Key: string,
	Nest: number, -- 0 = zorro del bosque (sin nido)
	IsFox: boolean,
	Pos: Point,
	Heat: number,
	Capacity: number,
	Affinity: number,
	Attempts: number,
	LastAttemptAt: number,
	HoldStart: number?, -- empezó a robar (o a recoger la criatura suelta)
	Target: Point?,
	TargetKind: string,
	TargetRef: any,
	DecideAt: number,
	IdleUntil: number,
	BumpedAt: number,
	BumpedTargets: { [string]: number },
	WaitUntil: number,
	Pursue: boolean,
	PursueChase: Chase?,
	SeenCarrierPos: Point?,
	SeenAt: number,
	SprintUntil: number,
	StunnedUntil: number,
	SprintReadyAt: number,
	DoorUsed: boolean,
	Partners: { [string]: boolean },
	Carrying: Chase?,
	WonThisRound: boolean,
	Shields: number,
	-- contadores
	Collected: { [string]: number },
	Deposited: number,
	Steals: number,
	Bumps: number,
	LuckyBlocks: number,
	PactsBroken: number,
}

type Source = {
	Kind: string,
	Pos: Point,
	Available: boolean,
	RespawnAt: number,
	Expires: number?,
	Amount: number?,
	Place: () -> Point,
}

export type BotResult = {
	Dust: number,
	Won: { Genes.GeneSet }, -- criaturas que se lleva
	Copies: { Genes.GeneSet }, -- copias comunes (aliado de un ganador)
	ChosenEgg: boolean,
	Deposited: number,
	Affinity: number,
	LuckyBlocks: number,
	Steals: number,
	Attempts: number,
	Bumps: number,
	PactsBroken: number,
	PactKept: boolean,
	Collected: { [string]: number },
	Chosen: boolean,
	Chance: number,
}

export type Options = {
	Record: boolean?, -- guardar posiciones para la repetición
	Log: boolean?, -- guardar eventos narrados
	BloodMoon: boolean?,
	Overrides: { [string]: any }?,
}

local Round = {}

-- Forma Bandadas de hasta Config.Party.MaxSize con los bots sociables (cada bot entra con
-- probabilidad Arch.Social). Los demás juegan solos.
function Round.formParties(bots: { Bot }, rng: Rng)
	local next: number = 0
	local size: number = Config.Party.MaxSize
	for _, bot in bots do
		bot.Party = nil
		if rng() < bot.Arch.Social then
			if size >= Config.Party.MaxSize then
				next += 1
				size = 0
			end
			bot.Party = next
			size += 1
		end
	end
	-- Una Bandada de uno no existe.
	local counts: { [number]: number } = {}
	for _, bot in bots do
		if bot.Party then
			counts[bot.Party] = (counts[bot.Party] or 0) + 1
		end
	end
	for _, bot in bots do
		if bot.Party and counts[bot.Party] < 2 then
			bot.Party = nil
		end
	end
end

local EGG: Point = { X = 0, Z = 0 }
local DEPOSIT_REACH = Config.Heat.DepositRadius - 2
local TOUCH = 2.5
local PICKUP_HOLD = 1 -- segundos para recoger una criatura suelta (como el prompt del juego)

-- El "arquetipo" de los zorros del bosque: siempre persiguen y nunca sueltan.
local FOX_ARCH: Archetypes.Archetype = table.clone(Archetypes.ByKey.Thief)
FOX_ARCH.Key = "Fox"
FOX_ARCH.Label = "Zorro"
FOX_ARCH.ChaseDesire = 1
FOX_ARCH.HoldSkill = 1
FOX_ARCH.Social = 0
FOX_ARCH.Betray = 0
FOX_ARCH.Reaction = Config.ForestThieves.Reaction

local function dist(a: Point, b: Point): number
	return MapLayout.distance(a, b)
end

local function step(from: Point, to: Point, maxDistance: number): Point
	local d = dist(from, to)
	if d <= maxDistance or d == 0 then
		return { X = to.X, Z = to.Z }
	end
	local f = maxDistance / d
	return { X = from.X + (to.X - from.X) * f, Z = from.Z + (to.Z - from.Z) * f }
end

local function nestInner(index: number): Point
	return MapLayout.polar(MapLayout.nestAngle(index), MapLayout.NestRadius - MapLayout.NestSize / 2 + 2.5)
end

local function nestOf(agents: { Agent }, point: Point): number?
	for _, a in agents do
		if a.Nest > 0 and MapLayout.insideNest(a.Nest, point) then
			return a.Nest
		end
	end
	return nil
end

-- Siguiente punto del camino: a un nido solo se entra y se sale por la entrada.
local function waypoint(agent: Agent, agents: { Agent }, target: Point, doorClosed: { [number]: number }, t: number): Point?
	local here = nestOf(agents, agent.Pos)
	local there = nestOf(agents, target)
	if here and here ~= there then
		-- salir por la entrada
		if (doorClosed[here] or 0) > t then
			return nil
		end
		local inner = nestInner(here)
		if dist(agent.Pos, inner) > 1.5 then
			return inner
		end
		return MapLayout.nestEntrance(here)
	end
	if there and here ~= there then
		local entrance = MapLayout.nestEntrance(there)
		if dist(agent.Pos, entrance) > 1.5 then
			return entrance
		end
		if (doorClosed[there] or 0) > t then
			return nil -- puerta cerrada: esperar fuera
		end
		return nestInner(there)
	end
	return target
end

local function speedOf(agent: Agent, isCarrier: boolean, t: number, agents: { Agent }?): number
	local atHome, intruding = false, false
	if agents then -- solo durante la persecución
		local here = nestOf(agents, agent.Pos)
		atHome = here ~= nil and here == agent.Nest
		intruding = here ~= nil and here ~= agent.Nest
	end
	if agent.IsFox then
		local speed = Config.Movement.BaseWalkSpeed * Config.ForestThieves.SpeedMultiplier
		return if intruding then speed * Config.Chase.IntruderSpeedMultiplier else speed
	end
	return Economy.walkSpeed(agent.Bot.Upgrades.Boots or 0, isCarrier, agent.SprintUntil > t, atHome, intruding)
end

local function newAgent(bot: Bot, nest: number, pos: Point, isFox: boolean): Agent
	return {
		Bot = bot,
		Key = if isFox then "fox" .. bot.Id else tostring(bot.Id),
		Nest = nest,
		IsFox = isFox,
		Pos = pos,
		Heat = 0,
		Capacity = Economy.bagCapacity(bot.Upgrades.Bag or 0, bot.Payer),
		Affinity = 0,
		Attempts = 0,
		LastAttemptAt = -100,
		HoldStart = nil,
		Target = nil,
		TargetKind = "",
		TargetRef = nil,
		DecideAt = 0,
		IdleUntil = 0,
		BumpedAt = -100,
		BumpedTargets = {},
		WaitUntil = 0,
		Pursue = false,
		PursueChase = nil,
		SeenCarrierPos = nil,
		SeenAt = -100,
		SprintUntil = -100,
		StunnedUntil = -100,
		SprintReadyAt = 0,
		DoorUsed = false,
		Partners = {},
		Carrying = nil,
		WonThisRound = false,
		Shields = 0,
		Collected = { Ember = 0, Firefly = 0, LuckyBlock = 0, Geyser = 0, Dropped = 0 },
		Deposited = 0,
		Steals = 0,
		Bumps = 0,
		LuckyBlocks = 0,
		PactsBroken = 0,
	}
end

-- Simula una ronda. bots: participantes; rng: dados; t0: hora de inicio (para eventos).
function Round.run(bots: { Bot }, rng: Rng, options: Options?)
	local opts: Options = options or {}
	local log: { any } = {}
	local frames: { any } = {}
	local phase = "Incubación"
	local function event(t: number, text: string)
		if opts.Log or opts.Record then
			table.insert(log, { T = math.floor(t), Phase = phase, Text = text })
		end
	end

	-- Preparación ---------------------------------------------------------------------
	local agents: { Agent } = {} -- solo jugadores (los zorros van aparte)
	local byKey: { [string]: Agent } = {}
	local nests = {}
	for i = 1, Config.Nest.Count do
		nests[i] = i
	end
	Rng.shuffle(rng, nests)
	for i, bot in bots do
		local nest = nests[i]
		local agent = newAgent(bot, nest, nestInner(nest), false)
		table.insert(agents, agent)
		byKey[agent.Key] = agent
	end

	-- Tratos: cada bot sociable ofrece uno a otro bot al azar.
	local dealsFormed: number = 0
	for _, a in agents do
		if rng() < a.Bot.Arch.Social * 0.5 and #agents > 1 then
			local b = agents[Rng.int(rng, 1, #agents)]
			if b ~= a and not a.Partners[b.Key] and rng() < b.Bot.Arch.Social then
				a.Partners[b.Key] = true
				b.Partners[a.Key] = true
				dealsFormed += 1
			end
		end
	end

	-- Fuentes de Calor
	local sources: { Source } = {}
	local function addSource(kind: string, count: number, place: () -> Point)
		for _ = 1, count do
			table.insert(sources, { Kind = kind, Pos = place(), Available = true, RespawnAt = 0, Place = place })
		end
	end
	local function ringPoint(): Point
		return MapLayout.randomInRing(rng, MapLayout.SourceRing.Min, MapLayout.SourceRing.Max)
	end
	local swamp = MapLayout.zoneCenter("Swamp")
	addSource("Ember", Config.Heat.Ember.Count, ringPoint)
	addSource("Firefly", Config.Heat.Firefly.Count, function()
		return MapLayout.randomNear(rng, swamp, 20)
	end)
	addSource("LuckyBlock", Config.Heat.LuckyBlock.Count, ringPoint)

	local geysers: { { Pos: Point, CooldownUntil: number, Presses: { [Agent]: number } } } = {}
	for _, p in MapLayout.geyserPositions() do
		table.insert(geysers, { Pos = p, CooldownUntil = 0, Presses = {} :: { [Agent]: number } })
	end

	local goal = Economy.barGoal(#agents)
	local bar: number = 0
	local reached: number = 0
	local t: number = 0
	local incubationTime = Config.Round.IncubationTime
	local rainStart = incubationTime * Config.Round.GoldenRainAt
	local rainEnd = rainStart + Config.Round.GoldenRainSeconds
	local doorClosed: { [number]: number } = {}
	local foxes: { Agent } = {}
	local chases: { Chase } = {}

	local function record(phaseName: string)
		if not opts.Record then
			return
		end
		local positions = {}
		for _, a in agents do
			table.insert(positions, { math.floor(a.Pos.X * 10) / 10, math.floor(a.Pos.Z * 10) / 10, a.Heat })
		end
		local carriers = {}
		local loose = {}
		for _, c in chases do
			if not c.Done then
				if c.Carrier then
					table.insert(carriers, c.Carrier.Key)
				else
					table.insert(loose, { math.floor(c.LoosePos.X), math.floor(c.LoosePos.Z) })
				end
			end
		end
		local foxPositions = {}
		for _, f in foxes do
			table.insert(foxPositions, { math.floor(f.Pos.X * 10) / 10, math.floor(f.Pos.Z * 10) / 10 })
		end
		table.insert(frames, {
			T = math.floor(t * 10) / 10,
			Phase = phaseName,
			P = positions,
			C = carriers,
			L = if #loose > 0 then loose else nil,
			F = if #foxPositions > 0 then foxPositions else nil,
			Bar = math.floor(bar),
		})
	end

	local function raining(): boolean
		return Config.Round.GoldenRainSeconds > 0 and t >= rainStart and t < rainEnd
	end

	local function sourceValue(source: Source): number
		if source.Kind == "Ember" then
			return Config.Heat.Ember.Amount * (if raining() then Config.Round.GoldenRainMultiplier else 1)
		elseif source.Kind == "Firefly" then
			return Config.Heat.Firefly.Amount
		elseif source.Kind == "LuckyBlock" then
			return (Config.Heat.LuckyBlock.Min + Config.Heat.LuckyBlock.Max) / 2
		end
		return source.Amount or 0
	end

	local function give(agent: Agent, amount: number): number
		local room = agent.Capacity - agent.Heat
		local added = math.clamp(math.floor(amount), 0, math.max(room, 0))
		agent.Heat += added
		return added
	end

	local function deposit(agent: Agent)
		if agent.Heat <= 0 then
			return
		end
		local amount = agent.Heat
		agent.Heat = 0
		-- Bandada: una parte de la Afinidad se reparte entre el resto del grupo (PartyService).
		local mates = {}
		if agent.Bot.Party then
			for _, other in agents do
				if other ~= agent and other.Bot.Party == agent.Bot.Party then
					table.insert(mates, other)
				end
			end
		end
		local keep, each = Economy.partyShare(amount, #mates)
		for _, mate in mates do
			mate.Affinity += each
		end
		agent.Affinity += keep
		agent.Deposited += amount
		bar = math.min(goal, bar + amount)
		local minRarity, _, index = Economy.thresholdFor(bar / goal)
		if index > reached then
			reached = index
			event(t, string.format("El huevo llega al %d %% (mínimo %s)", math.floor(Config.Thresholds[index].Fraction * 100), Rarity.Info[minRarity].DisplayName))
		end
	end

	-- ¿Se puede empujar a esta víctima? (protección tras un empujón, misma víctima y novatos)
	local function canBump(agent: Agent, victim: Agent): boolean
		if t - victim.BumpedAt < Config.Heat.BumpCooldown then
			return false
		end
		if t - (agent.BumpedTargets[victim.Key] or -1000) < Config.Heat.BumpSameTargetCooldown then
			return false
		end
		local played = victim.Bot.RoundsPlayed
		return not (played and played < Config.Heat.NewPlayerProtectionRounds)
	end

	-- Decide qué hacer en la incubación.
	local function decide(agent: Agent)
		local arch = agent.Bot.Arch
		agent.DecideAt = t + 1
		if rng() < arch.Idle * 3 then
			agent.IdleUntil = t + Rng.range(rng, 2, 6)
			agent.Target = nil
			return
		end
		local speed = speedOf(agent, false, t)
		local timeLeft = incubationTime - t
		local toEgg = dist(agent.Pos, EGG) / speed
		local fraction = agent.Heat / agent.Capacity
		if agent.Heat > 0 and (fraction >= arch.DepositAt or timeLeft < toEgg + 8 or (goal - bar) <= agent.Heat) then
			agent.Target, agent.TargetKind = EGG, "Egg"
			return
		end
		-- Empujar a alguien con la bolsa llena.
		if rng() < arch.BumpDesire then
			for _, other in agents do
				if other ~= agent and not agent.Partners[other.Key] and other.Heat >= other.Capacity
					and canBump(agent, other) and dist(agent.Pos, other.Pos) < 35 then
					agent.Target, agent.TargetKind, agent.TargetRef = other.Pos, "Bump", other
					return
				end
			end
		end
		-- Géiser cercano listo.
		if rng() < arch.GeyserCoop then
			for _, g in geysers do
				if g.CooldownUntil <= t and dist(agent.Pos, g.Pos) < 45 then
					agent.Target, agent.TargetKind, agent.TargetRef = g.Pos, "Geyser", g
					agent.WaitUntil = 0
					return
				end
			end
		end
		-- La fuente con mejor relación Calor/distancia.
		local best: Source? = nil
		local bestScore = -1
		local room = agent.Capacity - agent.Heat
		for _, s in sources do
			if s.Available then
				local value = math.min(sourceValue(s), room)
				local score = value / (dist(agent.Pos, s.Pos) + 8)
				if score > bestScore then
					best, bestScore = s, score
				end
			end
		end
		if best then
			agent.Target, agent.TargetKind, agent.TargetRef = best.Pos, "Source", best
		else
			agent.Target, agent.TargetKind = EGG, "Egg"
		end
	end

	-- 1. INCUBACIÓN -----------------------------------------------------------------
	event(0, string.format("Empieza la incubación con %d jugadores (meta de la barra: %d)", #agents, goal))
	local dt = 0.5
	local bumpsTotal, geyserActivations = 0, 0
	local nextFrame: number = 0
	local rainAnnounced = false
	while t < incubationTime and bar < goal do
		if raining() and not rainAnnounced then
			rainAnnounced = true
			event(t, "✨ ¡Lluvia de brasas doradas! Las brasas valen el doble un rato")
		end
		for _, s in sources do
			if not s.Available and s.RespawnAt <= t and not s.Expires then
				s.Available = true
				s.Pos = s.Place()
			end
		end
		for i = #sources, 1, -1 do
			local s = sources[i]
			if s.Expires and (not s.Available or s.Expires <= t) then
				table.remove(sources, i)
			end
		end

		for _, agent in agents do
			if agent.IdleUntil > t then
				continue
			end
			if agent.DecideAt <= t or not agent.Target then
				decide(agent)
			end
			local target = agent.Target
			if not target then
				continue
			end
			if agent.TargetKind == "Bump" then
				target = (agent.TargetRef :: Agent).Pos
			end
			local way = waypoint(agent, agents, target, doorClosed, t)
			if way then
				agent.Pos = step(agent.Pos, way, speedOf(agent, false, t) * dt)
			end

			local kind = agent.TargetKind
			local reach = dist(agent.Pos, target)
			if kind == "Egg" then
				local radius = if agent.Bot.Payer then Config.Heat.DepositRadius else DEPOSIT_REACH
				if reach <= radius then
					deposit(agent)
					agent.Target = nil
				end
			elseif kind == "Source" then
				local s = agent.TargetRef :: Source
				if not s.Available then
					agent.Target = nil
				elseif reach <= TOUCH then
					local amount = if s.Kind == "LuckyBlock" then Rng.int(rng, Config.Heat.LuckyBlock.Min, Config.Heat.LuckyBlock.Max) else (s.Amount or sourceValue(s))
					local added = give(agent, amount)
					if added > 0 then
						s.Available = false
						agent.Collected[s.Kind == "Dropped" and "Dropped" or s.Kind] += added
						if s.Kind == "LuckyBlock" then
							agent.LuckyBlocks += 1
						end
						local respawn = if s.Kind == "Ember" then Config.Heat.Ember.Respawn
							elseif s.Kind == "Firefly" then Config.Heat.Firefly.Respawn
							else Config.Heat.LuckyBlock.Respawn
						s.RespawnAt = t + respawn
					end
					agent.Target = nil
				end
			elseif kind == "Geyser" then
				local g = agent.TargetRef
				if g.CooldownUntil > t then
					agent.Target = nil
				elseif reach <= 10 then
					if agent.WaitUntil == 0 then
						agent.WaitUntil = t + 6
					end
					g.Presses[agent] = t
					local ready: { Agent } = {}
					for other, at in g.Presses do
						if t - at <= Config.Heat.Geyser.Window then
							table.insert(ready, other)
						end
					end
					if #ready >= Config.Heat.Geyser.PlayersNeeded then
						g.CooldownUntil = t + Config.Heat.Geyser.Cooldown
						g.Presses = {}
						geyserActivations += 1
						for _, other in ready do
							other.Collected.Geyser += give(other, Config.Heat.Geyser.Amount)
							other.Target = nil
						end
					elseif t >= agent.WaitUntil then
						agent.Target = nil -- nadie vino; probar otra cosa
					end
				end
			elseif kind == "Bump" then
				local victim = agent.TargetRef :: Agent
				if victim.Heat < victim.Capacity or not canBump(agent, victim) then
					agent.Target = nil
				elseif reach <= Config.Heat.BumpRange then
					victim.BumpedAt = t
					agent.BumpedTargets[victim.Key] = t
					local dropped = math.floor(victim.Heat * Config.Heat.BumpDropFraction)
					victim.Heat -= dropped
					agent.Bumps += 1
					bumpsTotal += 1
					local pieces = math.clamp(math.ceil(dropped / 10), 1, 6)
					for _ = 1, pieces do
						table.insert(sources, {
							Kind = "Dropped",
							Pos = MapLayout.randomNear(rng, victim.Pos, 6),
							Available = true,
							RespawnAt = 0,
							Expires = t + 20,
							Amount = math.floor(dropped / pieces),
							Place = function()
								return victim.Pos
							end,
						})
					end
					agent.Target = nil
				end
			end
		end
		if t >= nextFrame then
			record("Incubation")
			nextFrame += 1
		end
		t += dt
	end
	local incubationDuration = t
	local fraction = bar / goal
	local minRarity, luck = Economy.thresholdFor(fraction)
	if opts.BloodMoon then
		minRarity = Rarity.max(minRarity, Config.Events.BloodMoon.MinRarity :: Rarity.RarityName)
	end

	-- 2. ECLOSIÓN Y ELECCIÓN -----------------------------------------------------------
	local entries = {}
	local totalAffinity: number = 0
	for _, a in agents do
		table.insert(entries, {
			Key = a.Key,
			Affinity = a.Affinity,
			Min = Election.minFor(a.Bot.RoundsSinceChosen or 0, a.Bot.RoundsPlayed or math.huge),
		})
		totalAffinity += a.Affinity
	end
	local count = Economy.creatureCount(#agents)
	local chosenKeys, chances = Election.pickMany(entries, Config.Election.MinChance, count, rng)
	phase = "Eclosión"
	for index, key in chosenKeys do
		local chosen = byKey[key]
		local rarity = Rarity.roll(rng, luck, minRarity)
		-- Puesto del elegido por Afinidad (1 = el que más aportó).
		local rank = 1
		for _, a in agents do
			if a.Affinity > chosen.Affinity then
				rank += 1
			end
		end
		table.insert(chases, {
			Index = index,
			Rarity = rarity,
			Genes = Genes.rollSet(rng, rarity),
			Chosen = chosen,
			ChosenChance = chances[key],
			ChosenRank = rank,
			Carrier = chosen,
			LoosePos = chosen.Pos,
			ImmuneUntil = 0,
			HomeStreak = 0,
			Done = false,
			Secured = false,
			Overtime = false,
			Winner = nil,
			Steals = 0,
			Carriers = { [chosen.Key] = true },
			FirstHome = nil,
			LastChange = 0,
			Drops = 0,
		})
		chosen.Carrying = chases[#chases]
		local chanceText = string.gsub(string.format("%.1f", chances[key] * 100), "%.", ",")
		event(0, string.format("¡Eclosión! Criatura %s para %s (%s %%)", Rarity.Info[rarity].DisplayName, chosen.Bot.Name, chanceText))
	end
	for i = 1, Config.Round.HatchTime do
		t += 1
		if i % 2 == 0 then
			record("Hatch")
		end
	end

	-- 3. PERSECUCIÓN -----------------------------------------------------------------
	local chaseTime = if opts.BloodMoon then Config.Round.BloodMoonChaseTime else Config.Round.ChaseTime
	local chaseStart = t
	local passes, doors, betrayals, shieldBlocks, foxDrops = 0, 0, 0, 0, 0
	local allCarriers: { [string]: boolean } = {}
	local timeInNest: number = 0
	for _, c in chases do
		c.ImmuneUntil = t + Config.Chase.StartImmunitySeconds
		c.LastChange = t
		allCarriers[c.Chosen.Key] = true
	end
	-- Escudos de Afinidad: los da el Calor depositado en esta ronda.
	for _, a in agents do
		a.Shields = Economy.shields(a.Affinity)
	end

	-- Zorros del bosque en servidores pequeños: salen del borde del mapa.
	if Config.ForestThieves.Enabled and #agents < Config.ForestThieves.FillTo then
		local foxCount = math.min(Config.ForestThieves.MaxCount, Config.ForestThieves.FillTo - #agents)
		for i = 1, foxCount do
			local foxBot: Bot = { Id = 1000 + i, Name = "Zorro " .. i, Arch = FOX_ARCH, Upgrades = {}, Payer = false }
			local fox = newAgent(foxBot, 0, MapLayout.polar(rng() * math.pi * 2, MapLayout.Radius - 8), true)
			fox.Pursue = true
			table.insert(foxes, fox)
		end
		event(0, string.format("🦊 %d zorros salen del bosque a por las criaturas", foxCount))
	end

	local function activeChases(): { Chase }
		local list: { Chase } = {}
		for _, c in chases do
			if not c.Done then
				table.insert(list, c)
			end
		end
		return list
	end

	local function chasePos(c: Chase): Point
		return if c.Carrier then c.Carrier.Pos else c.LoosePos
	end

	-- A qué criatura va cada uno (la más cercana que le interese).
	local function choosePursuit(a: Agent)
		a.HoldStart = nil
		if a.IsFox then
			local best, bestDistance = nil :: Chase?, math.huge
			for _, c in activeChases() do
				if c.Carrier then -- los zorros solo van a por criaturas que alguien lleva
					local d = dist(a.Pos, c.Carrier.Pos)
					if d < bestDistance then
						best, bestDistance = c, d
					end
				end
			end
			a.PursueChase = best
			a.Pursue = best ~= nil
			return
		end
		if a.Carrying or a.WonThisRound then
			a.Pursue, a.PursueChase = false, nil
			return
		end
		local best, bestDistance = nil :: Chase?, math.huge
		for _, c in activeChases() do
			local carrier = c.Carrier
			local interested = if carrier == nil then true
				elseif carrier.Partners[a.Key] then rng() < a.Bot.Arch.Betray
				else true
			if interested then
				local d = dist(a.Pos, chasePos(c))
				if d < bestDistance then
					best, bestDistance = c, d
				end
			end
		end
		a.PursueChase = best
		-- Una criatura suelta cerca atrae a cualquiera; si no, según las ganas de perseguir.
		a.Pursue = best ~= nil and ((best.Carrier == nil and bestDistance < 60) or rng() < a.Bot.Arch.ChaseDesire)
	end
	local function reassignAll()
		for _, a in agents do
			choosePursuit(a)
		end
		for _, f in foxes do
			choosePursuit(f)
		end
	end

	local function setCarrier(c: Chase, agent: Agent)
		if c.Carrier then
			c.Carrier.Carrying = nil
		end
		c.Carrier = agent
		agent.Carrying = c
		c.Carriers[agent.Key] = true
		allCarriers[agent.Key] = true
		c.ImmuneUntil = t + Config.Chase.ImmunityAfterSteal
		c.HomeStreak = 0
		c.LastChange = t
		reassignAll()
	end

	local function finish(c: Chase, winner: Agent?)
		c.Done = true
		c.Winner = winner
		if winner then
			winner.WonThisRound = true
			winner.Carrying = nil
		elseif c.Carrier then
			c.Carrier.Carrying = nil
		end
		reassignAll()
	end

	reassignAll()
	phase = "Persecución"
	local nextReconsider = t + 10
	dt = 0.25
	nextFrame = t
	local chaseEnd = chaseStart + chaseTime
	local overtimeEnd = chaseEnd + Config.Chase.OvertimeSeconds
	local overtimeStarted = false
	-- Ventaja de los elegidos: los demás (y los zorros) no se mueven hasta pasados unos segundos.
	for _, a in agents do
		if not a.Carrying then
			a.StunnedUntil = t + Config.Chase.HeadStartSeconds
		end
	end
	for _, f in foxes do
		f.StunnedUntil = t + Config.Chase.HeadStartSeconds
	end

	-- Intento de robo (o de recoger la criatura suelta) del agente `a` sobre la persecución `c`.
	local function tryTake(a: Agent, c: Chase, d: number)
		local carrier = c.Carrier
		if not carrier then
			-- Criatura suelta: recogerla cuesta PICKUP_HOLD segundos al lado.
			if a.IsFox or d > TOUCH then
				a.HoldStart = nil
				return
			end
			if not a.HoldStart then
				a.HoldStart = t
			elseif t - (a.HoldStart :: number) >= PICKUP_HOLD then
				event(t - chaseStart, string.format("%s recoge la criatura del suelo", a.Bot.Name))
				setCarrier(c, a)
			end
			return
		end
		local inside = MapLayout.insideNest(carrier.Nest, carrier.Pos)
		local keepRange = Config.Chase.StealRange + (if Config.Chase.TapSteal then ChaseRules.DistanceTolerance else 0)
		if d > keepRange then
			a.HoldStart = nil -- se ha escapado del tira y afloja
			return
		end
		if not a.HoldStart then
			if d > Config.Chase.StealRange then
				return
			end
			a.HoldStart = t
			if t - a.LastAttemptAt > 2 then
				a.LastAttemptAt = t
				a.Attempts += 1
			end
			return
		end
		if not Config.Chase.TapSteal and rng() < (1 - a.Bot.Arch.HoldSkill) * dt then
			a.HoldStart = nil -- se le escapa el dedo (solo cuando hay que mantener el botón)
			return
		end
		if t - (a.HoldStart :: number) < ChaseRules.holdTime(inside) then
			return
		end
		local check = ChaseRules.canSteal(t, a.HoldStart, c.ImmuneUntil, d, inside)
		a.HoldStart = nil
		if check ~= "ok" then
			return
		end
		-- Escudo de Afinidad: se rompe y el robo no ocurre.
		if carrier.Shields > 0 then
			carrier.Shields -= 1
			c.ImmuneUntil = t + Config.Chase.ImmunityAfterSteal
			shieldBlocks += 1
			event(t - chaseStart, string.format("🛡️ El escudo de %s bloquea a %s", carrier.Bot.Name, a.Bot.Name))
			return
		end
		carrier.StunnedUntil = t + Config.Chase.StunSeconds
		if a.IsFox then
			-- El zorro la tira al suelo y vuelve al bosque un rato.
			event(t - chaseStart, string.format("🦊 Un zorro le tira la criatura al suelo a %s", carrier.Bot.Name))
			carrier.Carrying = nil
			c.Carrier = nil
			c.LoosePos = MapLayout.randomNear(rng, carrier.Pos, 4)
			c.Drops += 1
			c.LastChange = t
			foxDrops += 1
			a.StunnedUntil = t + 8
			reassignAll()
			return
		end
		if carrier.Partners[a.Key] then
			carrier.Partners[a.Key] = nil
			a.Partners[carrier.Key] = nil
			a.PactsBroken += 1
			betrayals += 1
			event(t - chaseStart, string.format("💔 %s traiciona a %s", a.Bot.Name, carrier.Bot.Name))
		else
			event(t - chaseStart, string.format("%s le roba la criatura a %s", a.Bot.Name, carrier.Bot.Name))
		end
		a.Steals += 1
		c.Steals += 1
		setCarrier(c, a)
	end

	while true do
		local active = activeChases()
		if #active == 0 then
			break
		end
		if t >= chaseEnd and not overtimeStarted then
			-- Se acaba el tiempo: gana quien esté en su nido; el resto va a la prórroga.
			overtimeStarted = true
			local anyOvertime = false
			for _, c in active do
				local carrier = c.Carrier
				if carrier and MapLayout.insideNest(carrier.Nest, carrier.Pos) then
					event(t - chaseStart, string.format("⏱️ %s tiene la criatura en su nido al acabar", carrier.Bot.Name))
					finish(c, carrier)
				elseif Config.Chase.OvertimeSeconds > 0 then
					c.Overtime = true
					anyOvertime = true
				else
					finish(c, nil)
				end
			end
			if anyOvertime then
				event(t - chaseStart, "¡Prórroga! Gana el primero que meta la criatura en su nido")
			end
			continue
		end
		if overtimeStarted and t >= overtimeEnd then
			for _, c in active do
				finish(c, nil)
			end
			break
		end

		-- Reconsiderar quién persigue cada 10 s (alguien se anima, alguien se cansa).
		if t >= nextReconsider then
			nextReconsider = t + 10
			reassignAll()
		end

		-- Portadores
		for _, c in active do
			local carrier = c.Carrier
			if not carrier then
				continue
			end
			local nearest, nearestDist = nil :: Agent?, math.huge
			for _, list in { agents, foxes } do
				for _, a in list do
					if a.Pursue and a.PursueChase == c then
						local d = dist(a.Pos, carrier.Pos)
						if d < nearestDist then
							nearest, nearestDist = a, d
						end
					end
				end
			end
			if nearestDist < 15 and t >= carrier.SprintReadyAt then
				carrier.SprintUntil = t + Config.Chase.SprintDuration
				carrier.SprintReadyAt = t + Config.Chase.SprintCooldown
			end
			-- Relevo a un aliado cuando un ladrón casi completa el robo.
			if nearest and nearest.HoldStart and t - nearest.HoldStart > 0.7 and rng() < carrier.Bot.Arch.Social * 0.5 then
				for key in carrier.Partners do
					local ally = byKey[key]
					if ally and not ally.Carrying and not ally.WonThisRound and dist(ally.Pos, carrier.Pos) <= Config.Chase.PassRange then
						event(t - chaseStart, string.format("%s pasa el relevo a %s", carrier.Bot.Name, ally.Bot.Name))
						passes += 1
						setCarrier(c, ally)
						break
					end
				end
				carrier = c.Carrier :: Agent
			end
			local inside = MapLayout.insideNest(carrier.Nest, carrier.Pos)
			local carrierTarget: Point
			if inside then
				if not c.FirstHome then
					c.FirstHome = t - chaseStart
				end
				timeInNest += dt
				c.HomeStreak += dt
				if ChaseRules.isSecured(c.HomeStreak) then
					c.Secured = true
					event(t - chaseStart, string.format("🔒 %s asegura la criatura en su nido", carrier.Bot.Name))
					finish(c, carrier)
					continue
				end
				if c.Overtime then
					event(t - chaseStart, string.format("⚡ %s gana en la prórroga", carrier.Bot.Name))
					finish(c, carrier)
					continue
				end
				-- Puerta: una vez por ronda cuando se acercan ladrones desde fuera.
				if not carrier.DoorUsed and nearest and nearestDist < 25 and not MapLayout.insideNest(carrier.Nest, nearest.Pos) then
					carrier.DoorUsed = true
					doorClosed[carrier.Nest] = t + Config.Chase.DoorCloseTime
					doors += 1
					event(t - chaseStart, string.format("%s cierra la puerta de su nido", carrier.Bot.Name))
				end
				-- Huir dentro del nido: el punto más alejado de los perseguidores.
				local center = MapLayout.nestCenter(carrier.Nest)
				local angle = MapLayout.nestAngle(carrier.Nest)
				local half = MapLayout.NestSize / 2 - 2
				local best, bestScore = center, -1
				for _, offset in { { 0, 0 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
					local r, tg = offset[1] * half, offset[2] * half
					local candidate = {
						X = center.X + r * math.cos(angle) - tg * math.sin(angle),
						Z = center.Z + r * math.sin(angle) + tg * math.cos(angle),
					}
					local score = math.huge
					for _, list in { agents, foxes } do
						for _, a in list do
							if a.Pursue and a.PursueChase == c then
								score = math.min(score, dist(a.Pos, candidate))
							end
						end
					end
					if score > bestScore then
						best, bestScore = candidate, score
					end
				end
				carrierTarget = best
			else
				c.HomeStreak = 0
				carrierTarget = MapLayout.nestCenter(carrier.Nest)
			end
			local way = waypoint(carrier, agents, carrierTarget, doorClosed, t)
			if way and carrier.StunnedUntil <= t then
				carrier.Pos = step(carrier.Pos, way, speedOf(carrier, true, t, agents) * dt)
			end
		end

		-- Perseguidores (jugadores y zorros)
		for _, list in { agents, foxes } do
			for _, a in list do
				local c = a.PursueChase
				if a.Carrying or not a.Pursue or not c or c.Done or a.StunnedUntil > t then
					a.HoldStart = nil
					continue
				end
				local targetNow = chasePos(c)
				if t - a.SeenAt >= a.Bot.Arch.Reaction or not a.SeenCarrierPos then
					a.SeenCarrierPos = { X = targetNow.X, Z = targetNow.Z }
					a.SeenAt = t
				end
				local target = a.SeenCarrierPos :: Point
				local d = dist(a.Pos, targetNow)
				local close = if c.Carrier then Config.Chase.StealRange * 0.6 else 1
				if d > close then
					local w = waypoint(a, agents, target, doorClosed, t)
					if w then
						a.Pos = step(a.Pos, w, speedOf(a, false, t, agents) * dt)
					end
					d = dist(a.Pos, chasePos(c))
				end
				tryTake(a, c, d)
				if c.Done or a.Carrying then
					continue
				end
			end
		end

		if t >= nextFrame then
			record(if overtimeStarted then "Overtime" else "Chase")
			nextFrame += 0.5
		end
		t += dt
	end

	-- 4. RESULTADOS -----------------------------------------------------------------
	local participants = {}
	for _, a in agents do
		table.insert(participants, { Key = a.Key, Affinity = a.Affinity, StealAttempts = a.Attempts })
	end
	local outcomes: { Rewards.Outcome } = {}
	for _, c in chases do
		local winner = c.Winner
		local partnerKeys = {}
		if winner then
			for key in winner.Partners do
				table.insert(partnerKeys, key)
			end
			event(t - chaseStart, string.format("🏆 %s se queda la criatura %s", winner.Bot.Name, Rarity.Info[c.Rarity].DisplayName))
		else
			event(t - chaseStart, string.format("La criatura %s escapa", Rarity.Info[c.Rarity].DisplayName))
		end
		table.insert(outcomes, { Winner = if winner then winner.Key else nil, Partners = partnerKeys, Chosen = c.Chosen.Key })
	end
	local rewards = Rewards.compute(participants, outcomes)
	record("Results")

	local perBot: { [number]: BotResult } = {}
	for _, a in agents do
		local reward = rewards[a.Key]
		local won, copies = {}, {}
		for _, index in reward.Won do
			table.insert(won, chases[index].Genes)
		end
		for _, index in reward.Copies do
			table.insert(copies, Genes.commonCopy(chases[index].Genes, rng))
		end
		local kept = false
		for _, o in outcomes do
			if o.Winner and table.find(o.Partners, a.Key) then
				kept = true
			end
		end
		local isChosen = false
		for _, c in chases do
			if c.Chosen == a then
				isChosen = true
			end
		end
		perBot[a.Bot.Id] = {
			Dust = reward.Dust,
			Won = won,
			Copies = copies,
			ChosenEgg = reward.ChosenEgg,
			Deposited = a.Deposited,
			Affinity = a.Affinity,
			LuckyBlocks = a.LuckyBlocks,
			Steals = a.Steals,
			Attempts = a.Attempts,
			Bumps = a.Bumps,
			PactsBroken = a.PactsBroken,
			PactKept = kept,
			Collected = a.Collected,
			Chosen = isChosen,
			Chance = chances[a.Key] or 0,
		}
	end

	-- Una línea por criatura (para las estadísticas de la persecución).
	local chaseList = {}
	local steals = 0
	for _, c in chases do
		steals += c.Steals
		local carrier = c.Winner or c.Carrier
		local carriersCount = 0
		for _ in c.Carriers do
			carriersCount += 1
		end
		table.insert(chaseList, {
			Rarity = c.Rarity,
			ChosenArch = c.Chosen.Bot.Arch.Key,
			ChosenRank = c.ChosenRank,
			ChosenChance = c.ChosenChance,
			ChosenShare = if totalAffinity > 0 then c.Chosen.Affinity / totalAffinity else 0,
			WinnerArch = if c.Winner then c.Winner.Bot.Arch.Key else nil,
			WinnerId = if c.Winner then c.Winner.Bot.Id else nil,
			WinnerIsChosen = c.Winner == c.Chosen,
			Escaped = c.Winner == nil,
			Secured = c.Secured,
			Overtime = c.Overtime,
			Steals = c.Steals,
			Carriers = carriersCount,
			Drops = c.Drops,
			FirstHomeSeconds = c.FirstHome,
			FinalDistanceToNest = if carrier then MapLayout.distance(carrier.Pos, MapLayout.nestCenter(carrier.Nest)) else 0,
			LastChangeAgo = t - c.LastChange,
		})
	end

	local summary: { [string]: any } = {
		Players = #agents,
		Creatures = #chases,
		Foxes = #foxes,
		IncubationSeconds = incubationDuration,
		BarFraction = fraction,
		EarlyFull = bar >= goal,
		MinRarity = minRarity,
		Chases = chaseList,
		Steals = steals,
		Passes = passes,
		Doors = doors,
		Betrayals = betrayals,
		ShieldBlocks = shieldBlocks,
		FoxDrops = foxDrops,
		Deals = dealsFormed,
		Bumps = bumpsTotal,
		Geysers = geyserActivations,
		Carriers = 0,
		CarrierNestSeconds = timeInNest,
		Overtime = overtimeStarted and t > chaseEnd,
		ChaseSeconds = t - chaseStart,
		DurationSeconds = t + Config.Round.ResultsTime + Config.Round.IntermissionTime,
	}
	for _ in allCarriers do
		summary.Carriers += 1
	end

	return summary, perBot, { Log = log, Frames = frames, Nests = (function()
		local list = {}
		for _, a in agents do
			table.insert(list, { Id = a.Bot.Id, Name = a.Bot.Name, Arch = a.Bot.Arch.Key, Nest = a.Nest })
		end
		return list
	end)() }
end

return Round
