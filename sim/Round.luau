--!strict
-- Simula una ronda completa (GDD 4-5) con bots en el plano del mapa:
-- Incubación (Calor, géiseres, empujones, depósitos) -> Eclosión (Elección) ->
-- Persecución (robos, inmunidad, esprint, relevo, puerta) -> Premios.
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
}

-- Estado del bot dentro de una ronda.
type Agent = {
	Bot: Bot,
	Key: string,
	Nest: number,
	Pos: Point,
	Heat: number,
	Capacity: number,
	Affinity: number,
	Attempts: number,
	LastAttemptAt: number,
	HoldStart: number?,
	Target: Point?,
	TargetKind: string,
	TargetRef: any,
	DecideAt: number,
	IdleUntil: number,
	BumpedAt: number,
	WaitUntil: number,
	Pursue: boolean,
	SeenCarrierPos: Point?,
	SeenAt: number,
	SprintUntil: number,
	StunnedUntil: number,
	SprintReadyAt: number,
	DoorUsed: boolean,
	Partners: { [string]: boolean },
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
	Genes: Genes.GeneSet?,
	Copy: Genes.GeneSet?,
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
	Won: boolean,
}

export type Options = {
	Record: boolean?, -- guardar posiciones para la repetición
	Log: boolean?, -- guardar eventos narrados
	BloodMoon: boolean?,
	Overrides: { [string]: any }?,
}

local Round = {}

local EGG: Point = { X = 0, Z = 0 }
local DEPOSIT_REACH = Config.Heat.DepositRadius - 2
local TOUCH = 2.5

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
		if MapLayout.insideNest(a.Nest, point) then
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
		atHome = here == agent.Nest
		intruding = here ~= nil and here ~= agent.Nest
	end
	return Economy.walkSpeed(agent.Bot.Upgrades.Boots or 0, isCarrier, agent.SprintUntil > t, atHome, intruding)
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
	local agents: { Agent } = {}
	local byKey: { [string]: Agent } = {}
	local nests = {}
	for i = 1, Config.Nest.Count do
		nests[i] = i
	end
	Rng.shuffle(rng, nests)
	for i, bot in bots do
		local nest = nests[i]
		local agent: Agent = {
			Bot = bot,
			Key = tostring(bot.Id),
			Nest = nest,
			Pos = nestInner(nest),
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
			WaitUntil = 0,
			Pursue = false,
			SeenCarrierPos = nil,
			SeenAt = -100,
			SprintUntil = -100,
			StunnedUntil = -100,
			SprintReadyAt = 0,
			DoorUsed = false,
			Partners = {},
			Collected = { Ember = 0, Firefly = 0, LuckyBlock = 0, Geyser = 0, Dropped = 0 },
			Deposited = 0,
			Steals = 0,
			Bumps = 0,
			LuckyBlocks = 0,
			PactsBroken = 0,
		}
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
	local doorClosed: { [number]: number } = {}

	local function record(phase: string, carrier: Agent?)
		if not opts.Record then
			return
		end
		local positions = {}
		for _, a in agents do
			table.insert(positions, { math.floor(a.Pos.X * 10) / 10, math.floor(a.Pos.Z * 10) / 10, a.Heat })
		end
		table.insert(frames, {
			T = math.floor(t * 10) / 10,
			Phase = phase,
			P = positions,
			C = if carrier then carrier.Key else nil,
			Bar = math.floor(bar),
		})
	end

	local function sourceValue(source: Source): number
		if source.Kind == "Ember" then
			return Config.Heat.Ember.Amount
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
		agent.Affinity += amount
		agent.Deposited += amount
		bar = math.min(goal, bar + amount)
		local minRarity, _, index = Economy.thresholdFor(bar / goal)
		if index > reached then
			reached = index
			event(t, string.format("El huevo llega al %d %% (mínimo %s)", math.floor(Config.Thresholds[index].Fraction * 100), Rarity.Info[minRarity].DisplayName))
		end
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
					and t - other.BumpedAt >= Config.Heat.BumpCooldown and dist(agent.Pos, other.Pos) < 35 then
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
	while t < incubationTime and bar < goal do
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
					local added = give(agent, if s.Kind == "LuckyBlock" then Rng.int(rng, Config.Heat.LuckyBlock.Min, Config.Heat.LuckyBlock.Max) else (s.Amount or sourceValue(s)))
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
				if victim.Heat < victim.Capacity or t - victim.BumpedAt < Config.Heat.BumpCooldown then
					agent.Target = nil
				elseif reach <= Config.Heat.BumpRange then
					victim.BumpedAt = t
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
			record("Incubation", nil)
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
	local rarity = Rarity.roll(rng, luck, minRarity)
	local genes = Genes.rollSet(rng, rarity)
	local entries = {}
	local totalAffinity: number = 0
	for _, a in agents do
		table.insert(entries, { Key = a.Key, Affinity = a.Affinity, Min = Election.pityMin(a.Bot.RoundsSinceChosen or 0) })
		totalAffinity += a.Affinity
	end
	local chosenKey, chances = Election.pick(entries, Config.Election.MinChance, rng)
	local chosen = byKey[chosenKey :: string]
	-- Puesto del elegido por Afinidad (1 = el que más aportó).
	local rank = 1
	for _, a in agents do
		if a.Affinity > chosen.Affinity then
			rank += 1
		end
	end
	phase = "Eclosión"
	local chanceText = string.gsub(string.format("%.1f", chances[chosen.Key] * 100), "%.", ",")
	event(0, string.format("¡Eclosión! Sale una criatura %s y el huevo elige a %s (%s %%)", Rarity.Info[rarity].DisplayName, chosen.Bot.Name, chanceText))
	for i = 1, Config.Round.HatchTime do
		t += 1
		if i % 2 == 0 then
			record("Hatch", nil)
		end
	end

	-- 3. PERSECUCIÓN -----------------------------------------------------------------
	local chaseTime = if opts.BloodMoon then Config.Round.BloodMoonChaseTime else Config.Round.ChaseTime
	local chaseStart = t
	local carrier = chosen
	local immuneUntil = t + Config.Chase.StartImmunitySeconds
	local steals, passes, doors, betrayals = 0, 0, 0, 0
	local carriers: { [string]: boolean } = { [carrier.Key] = true }
	local firstHome: number? = nil
	local timeInNest: number = 0
	local lastChange = t
	local homeStreak = 0 -- segundos seguidos del portador actual en su nido
	local secured = false

	local function choosePursuers()
		for _, a in agents do
			if a == carrier then
				a.Pursue = false
			elseif carrier.Partners[a.Key] then
				a.Pursue = rng() < a.Bot.Arch.Betray
			else
				a.Pursue = rng() < a.Bot.Arch.ChaseDesire
			end
			a.HoldStart = nil
		end
	end
	choosePursuers()
	phase = "Persecución"
	local nextReconsider = t + 10
	dt = 0.25
	nextFrame = t
	local chaseEnd = chaseStart + chaseTime
	local overtimeEnd = chaseEnd + Config.Chase.OvertimeSeconds
	local overtime = false
	local overtimeUsed = false
	-- Ventaja del elegido: los demás no se mueven hasta pasados unos segundos.
	for _, a in agents do
		if a ~= carrier then
			a.StunnedUntil = t + Config.Chase.HeadStartSeconds
		end
	end

	while t < chaseEnd or (overtime and t < overtimeEnd) do
		-- Reconsiderar quién persigue cada 10 s (alguien se anima, alguien se cansa).
		if t >= nextReconsider then
			nextReconsider = t + 10
			for _, a in agents do
				if a ~= carrier and not carrier.Partners[a.Key] and not a.Pursue and rng() < a.Bot.Arch.ChaseDesire * 0.3 then
					a.Pursue = true
				end
			end
		end

		-- Portador
		local inside = MapLayout.insideNest(carrier.Nest, carrier.Pos)
		local nearest, nearestDist = nil :: Agent?, math.huge
		for _, a in agents do
			if a.Pursue then
				local d = dist(a.Pos, carrier.Pos)
				if d < nearestDist then
					nearest, nearestDist = a, d
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
				if ally and dist(ally.Pos, carrier.Pos) <= Config.Chase.PassRange then
					event(t - chaseStart, string.format("%s pasa el relevo a %s", carrier.Bot.Name, ally.Bot.Name))
					lastChange = t
					carrier = ally
					carriers[ally.Key] = true
					immuneUntil = t + Config.Chase.ImmunityAfterSteal
					homeStreak = 0
					passes += 1
					choosePursuers()
					break
				end
			end
		end
		inside = MapLayout.insideNest(carrier.Nest, carrier.Pos)
		local carrierTarget: Point
		if inside then
			if not firstHome then
				firstHome = t - chaseStart
			end
			timeInNest += dt
			homeStreak += dt
			if ChaseRules.isSecured(homeStreak) then
				secured = true
				event(t - chaseStart, string.format("🔒 %s asegura la criatura en su nido", carrier.Bot.Name))
				break
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
				for _, a in agents do
					if a.Pursue then
						score = math.min(score, dist(a.Pos, candidate))
					end
				end
				if score > bestScore then
					best, bestScore = candidate, score
				end
			end
			carrierTarget = best
		else
			homeStreak = 0
			carrierTarget = MapLayout.nestCenter(carrier.Nest)
		end
		local way = waypoint(carrier, agents, carrierTarget, doorClosed, t)
		if way and carrier.StunnedUntil <= t then
			carrier.Pos = step(carrier.Pos, way, speedOf(carrier, true, t, agents) * dt)
		end

		-- Perseguidores
		for _, a in agents do
			if a == carrier or not a.Pursue or a.StunnedUntil > t then
				a.HoldStart = nil
				continue
			end
			if t - a.SeenAt >= a.Bot.Arch.Reaction or not a.SeenCarrierPos then
				a.SeenCarrierPos = { X = carrier.Pos.X, Z = carrier.Pos.Z }
				a.SeenAt = t
			end
			local target = a.SeenCarrierPos :: Point
			local d = dist(a.Pos, carrier.Pos)
			if d > Config.Chase.StealRange * 0.6 then
				local w = waypoint(a, agents, target, doorClosed, t)
				if w then
					a.Pos = step(a.Pos, w, speedOf(a, false, t, agents) * dt)
				end
				d = dist(a.Pos, carrier.Pos)
			end
			-- Mantener el botón de robar.
			if d <= Config.Chase.StealRange then
				if not a.HoldStart then
					a.HoldStart = t
					if t - a.LastAttemptAt > 2 then
						a.LastAttemptAt = t
						a.Attempts += 1
					end
				elseif rng() < (1 - a.Bot.Arch.HoldSkill) * dt then
					a.HoldStart = nil -- se le escapa el dedo
				elseif t - (a.HoldStart :: number) >= ChaseRules.holdTime(inside) then
					local check = ChaseRules.canSteal(t, a.HoldStart, immuneUntil, d, inside)
					a.HoldStart = nil
					if check == "ok" then
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
						steals += 1
						carrier.StunnedUntil = t + Config.Chase.StunSeconds
						lastChange = t
						carrier = a
						carriers[a.Key] = true
						immuneUntil = t + Config.Chase.ImmunityAfterSteal
						homeStreak = 0
						choosePursuers()
						break
					end
				end
			else
				a.HoldStart = nil
			end
		end

		if t >= nextFrame then
			record("Chase", carrier)
			nextFrame += 0.5
		end
		t += dt

		local home = MapLayout.insideNest(carrier.Nest, carrier.Pos)
		if overtime and ChaseRules.overtimeWin(true, home) then
			event(t - chaseStart, string.format("⚡ %s gana en la prórroga", carrier.Bot.Name))
			break
		end
		if not overtime and t >= chaseEnd and Config.Chase.OvertimeSeconds > 0 and not home then
			overtime = true
			overtimeUsed = true
			event(t - chaseStart, "¡Prórroga! Gana el primero que meta la criatura en su nido")
		end
	end

	-- 4. RESULTADOS -----------------------------------------------------------------
	local winner: Agent? = if secured or ChaseRules.carrierWins(MapLayout.insideNest(carrier.Nest, carrier.Pos)) then carrier else nil
	local participants = {}
	for _, a in agents do
		table.insert(participants, { Key = a.Key, Affinity = a.Affinity, StealAttempts = a.Attempts })
	end
	local partnerKeys = {}
	if winner then
		for key in winner.Partners do
			table.insert(partnerKeys, key)
		end
	end
	local rewards = Rewards.compute(participants, if winner then winner.Key else nil, partnerKeys, chosen.Key)
	if winner then
		event(t - chaseStart, string.format("🏆 %s se queda la criatura %s", winner.Bot.Name, Rarity.Info[rarity].DisplayName))
	else
		event(t - chaseStart, string.format("La criatura escapa: %s no estaba en su nido", carrier.Bot.Name))
	end
	record("Results", carrier)

	local perBot: { [number]: BotResult } = {}
	for _, a in agents do
		local reward = rewards[a.Key]
		perBot[a.Bot.Id] = {
			Dust = reward.Dust,
			Genes = if reward.Creature then genes else nil,
			Copy = if reward.Copy then Genes.commonCopy(genes, rng) else nil,
			ChosenEgg = reward.ChosenEgg,
			Deposited = a.Deposited,
			Affinity = a.Affinity,
			LuckyBlocks = a.LuckyBlocks,
			Steals = a.Steals,
			Attempts = a.Attempts,
			Bumps = a.Bumps,
			PactsBroken = a.PactsBroken,
			PactKept = winner ~= nil and table.find(partnerKeys, a.Key) ~= nil,
			Collected = a.Collected,
			Chosen = a == chosen,
			Chance = chances[a.Key],
			Won = a == winner,
		}
	end

	local summary: { [string]: any } = {
		Players = #agents,
		IncubationSeconds = incubationDuration,
		BarFraction = fraction,
		EarlyFull = bar >= goal,
		MinRarity = minRarity,
		Rarity = rarity,
		ChosenId = chosen.Bot.Id,
		ChosenArch = chosen.Bot.Arch.Key,
		ChosenRank = rank,
		ChosenShare = if totalAffinity > 0 then chosen.Affinity / totalAffinity else 0,
		ChosenChance = chances[chosen.Key],
		Steals = steals,
		Passes = passes,
		Doors = doors,
		Betrayals = betrayals,
		Deals = dealsFormed,
		Bumps = bumpsTotal,
		Geysers = geyserActivations,
		Carriers = 0,
		FirstHomeSeconds = firstHome,
		CarrierNestSeconds = timeInNest,
		WinnerId = if winner then winner.Bot.Id else nil,
		WinnerArch = if winner then winner.Bot.Arch.Key else nil,
		WinnerIsChosen = winner == chosen,
		Escaped = winner == nil,
		Secured = secured,
		Overtime = overtimeUsed,
		FinalDistanceToNest = MapLayout.distance(carrier.Pos, MapLayout.nestCenter(carrier.Nest)),
		LastChangeAgo = t - lastChange,
		ChaseSeconds = t - chaseStart,
		DurationSeconds = t + Config.Round.ResultsTime + Config.Round.IntermissionTime,
	}
	for _ in carriers do
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
