--!strict
-- Pruebas de la lógica pura (sin Roblox). Ejecutar con: luau tests/run.luau

local ArenaLayout = require("../src/shared/ArenaLayout")
local ChaseRules = require("../src/shared/ChaseRules")
local Config = require("../src/shared/Config")
local Creature = require("../src/shared/Creature")
local Decorations = require("../src/shared/Decorations")
local Economy = require("../src/shared/Economy")
local Election = require("../src/shared/Election")
local Events = require("../src/shared/Events")
local Genes = require("../src/shared/Genes")
local Leaderboard = require("../src/shared/Leaderboard")
local MapLayout = require("../src/shared/MapLayout")
local MovementRules = require("../src/shared/MovementRules")
local RateLimiter = require("../src/shared/RateLimiter")
local PlayerData = require("../src/shared/PlayerData")
local Quests = require("../src/shared/Quests")
local Sounds = require("../src/shared/Sounds")
local Rarity = require("../src/shared/Rarity")
local Rewards = require("../src/shared/Rewards")
local Trade = require("../src/shared/Trade")

local passed, failed = 0, 0

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FALLA: " .. name .. "\n  " .. tostring(err))
	end
end

local function expect(condition: boolean, message: string?)
	if not condition then
		error(message or "se esperaba verdadero", 2)
	end
end

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-9)
end

-- Generador determinista para pruebas reproducibles.
local function seeded(seed: number): () -> number
	local state = seed
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

test("el catálogo tiene 60 genes, 12 por ranura", function()
	local total = 0
	for _, slot in Genes.Slots do
		expect(#Genes.BySlot[slot] == 12, slot)
		total += #Genes.BySlot[slot]
	end
	expect(total == 60)
end)

test("los pesos de rareza suman 1.000.000", function()
	local total = 0
	for _, name in Rarity.Order do
		total += Rarity.Info[name].Weight
	end
	expect(total == 1_000_000)
end)

test("Rarity.chances suma 1 y coincide con las tiradas", function()
	local chances = Rarity.chances(1, "Rare", "Legendary")
	local total = 0
	for _, value in chances do
		total += value
	end
	expect(near(total, 1))
	expect(chances.Common == 0 and chances.Mythic == 0)
	local rng = seeded(4)
	local rare = 0
	for _ = 1, 20000 do
		if Rarity.roll(rng, 1, "Rare", "Legendary") == "Rare" then
			rare += 1
		end
	end
	expect(math.abs(rare / 20000 - chances.Rare) < 0.02, tostring(rare / 20000))
end)

test("Rarity.roll respeta mínimo y máximo", function()
	local rng = seeded(1)
	for _ = 1, 2000 do
		local r = Rarity.roll(rng, 3, "Epic", "Legendary")
		expect(r == "Epic" or r == "Legendary", r)
	end
end)

test("Rarity.roll con suerte da más rarezas altas", function()
	local function countRare(luck: number): number
		local rng = seeded(7)
		local n = 0
		for _ = 1, 20000 do
			if Rarity.roll(rng, luck) ~= "Common" then
				n += 1
			end
		end
		return n
	end
	expect(countRare(2) > countRare(1))
end)

test("Genes.rollSet produce exactamente la rareza pedida", function()
	local rng = seeded(3)
	for _, rarity in Rarity.Order do
		for _ = 1, 200 do
			local set = Genes.rollSet(rng, rarity)
			expect(Genes.isValidSet(set))
			expect(Genes.rarityOf(set) == rarity, rarity)
		end
	end
end)

test("las Secretas llevan el gen Arcoíris en Mutación", function()
	local set = Genes.rollSet(seeded(9), "Secret")
	expect(set.Mutation == "mut_rainbow")
end)

test("una ofrenda sesga su gen", function()
	local function count(biases: Genes.Biases?): number
		local rng = seeded(11)
		local n = 0
		for _ = 1, 3000 do
			if Genes.rollSet(rng, "Rare", biases).Body == "body_crystal" then
				n += 1
			end
		end
		return n
	end
	expect(count({ Body = "body_crystal" }) > count(nil) * 2)
end)

test("Genes.inherit hereda genes válidos y limita la mutación", function()
	local rng = seeded(5)
	local a = Genes.rollSet(rng, "Common")
	local b = Genes.rollSet(rng, "Rare")
	for _ = 1, 500 do
		local child = Genes.inherit(a, b, rng, 0.1)
		expect(Genes.isValidSet(child))
		expect(Rarity.tier(Genes.rarityOf(child)) <= Rarity.tier("Epic"))
	end
	local clone = Genes.inherit(a, a, rng, 0)
	for _, slot in Genes.Slots do
		expect((clone :: any)[slot] == (a :: any)[slot])
	end
end)

test("Creature calcula rareza, nombre e ingresos", function()
	local genes: Genes.GeneSet = {
		Body = "body_crystal",
		Head = "head_beak",
		Pattern = "pattern_spots",
		Aura = "aura_none",
		Mutation = "mut_none",
	}
	local c = Creature.new("a", genes, "Hatch", 0)
	expect(c.Rarity == "Rare")
	expect(Creature.name(c) == "Cristalino Moteado", Creature.name(c))
	-- Rara = 4/s, un gen de nivel 2 suma 5 %
	expect(near(Creature.baseIncome(c), 4 * 1.05))
	expect(Creature.isValid(c))
end)

test("solo producen las criaturas que caben en el nido", function()
	local rng = seeded(21)
	local list = {}
	for i = 1, 10 do
		table.insert(list, Creature.new(tostring(i), Genes.rollSet(rng, "Common"), "Hatch", 0))
	end
	local all = Creature.activeIncome(list, 10)
	local six = Creature.activeIncome(list, 6)
	expect(six < all and six > 0)
end)

test("Election: proporcional cuando nadie baja del mínimo", function()
	local chances = Election.chances({
		{ Key = "a", Affinity = 300 },
		{ Key = "b", Affinity = 100 },
	}, 0.02)
	expect(near(chances.a, 0.75) and near(chances.b, 0.25))
end)

test("Election: mínimo del 2 % y suma 1", function()
	local entries: { Election.Entry } = {
		{ Key = "rico", Affinity = 10000 },
		{ Key = "medio", Affinity = 500 },
		{ Key = "cero1", Affinity = 0 },
		{ Key = "cero2", Affinity = 0 },
	}
	local chances = Election.chances(entries, 0.02)
	local total = 0
	for _, value in chances do
		total += value
	end
	expect(near(total, 1), tostring(total))
	expect(near(chances.cero1, 0.02) and near(chances.cero2, 0.02))
	expect(chances.rico > chances.medio and chances.medio >= 0.02)
end)

test("Election: sin Afinidad todos iguales", function()
	local chances = Election.chances({
		{ Key = "a", Affinity = 0 },
		{ Key = "b", Affinity = 0 },
		{ Key = "c", Affinity = 0 },
		{ Key = "d", Affinity = 0 },
	}, 0.02)
	for _, value in chances do
		expect(near(value, 0.25))
	end
end)

test("Election: con 60 jugadores el mínimo no cabe y se reparte igual", function()
	local entries = {}
	for i = 1, 60 do
		table.insert(entries, { Key = tostring(i), Affinity = i })
	end
	local chances = Election.chances(entries, 0.02)
	expect(near(chances["1"], 1 / 60))
end)

test("Election.pick devuelve a alguien y respeta las frecuencias", function()
	local rng = seeded(99)
	local entries: { Election.Entry } = {
		{ Key = "a", Affinity = 900 },
		{ Key = "b", Affinity = 100 },
	}
	local wins = 0
	for _ = 1, 10000 do
		local key = Election.pick(entries, 0.02, rng)
		if key == "a" then
			wins += 1
		end
	end
	expect(wins > 8700 and wins < 9300, tostring(wins))
	expect(Election.pick({}, 0.02, rng) == nil)
end)

test("Economy: bolsa de 100 a 1.000", function()
	expect(Economy.bagCapacity(0, false) == 100)
	expect(Economy.bagCapacity(Config.Upgrades.Bag.MaxLevel, false) == 1000)
	-- GDD v2: ningún pase da más Calor.
	expect(Economy.bagCapacity(0, true) == math.floor(100 * Config.Heat.BagGamePassMultiplier))
	expect(Config.Heat.BagGamePassMultiplier == 1)
	expect(Economy.upgradeCost("Bag", Config.Upgrades.Bag.MaxLevel) == nil)
end)

test("Economy: nido de 6 a 40 ranuras", function()
	expect(Economy.nestSlots(0, false) == 6)
	expect(Economy.nestSlots(Config.Upgrades.Nest.MaxLevel, false) == 40)
	expect(Economy.nestSlots(0, true) == 16)
end)

test("Economy: velocidades de persecución", function()
	expect(near(Economy.walkSpeed(0, false, false), 16))
	if not Config.Chase.CarrierMaxBoots then
		expect(near(Economy.walkSpeed(0, true, false), 16 * Config.Chase.CarrierSpeedMultiplier))
	end
	expect(near(Economy.walkSpeed(10, false, false), 16 * 1.1))
	expect(near(Economy.walkSpeed(99, false, false), 16 * 1.1))
end)

test("Economy: consolación crece con Afinidad e intentos y tiene tope", function()
	local base = Economy.consolationDust(0, 0)
	expect(base == Config.Consolation.Base)
	expect(Economy.consolationDust(200, 0) > base)
	expect(Economy.consolationDust(0, 99) == Economy.consolationDust(0, Config.Consolation.MaxStealAttempts))
end)

test("Economy: ganancias sin conexión con tope de 8 h", function()
	local rate = Config.Nest.OfflineRate
	expect(Economy.offlineEarnings(10, 60) == math.floor(600 * rate))
	expect(Economy.offlineEarnings(1, 24 * 3600) == math.floor(8 * 3600 * rate))
	expect(Economy.offlineEarnings(1, -50) == 0)
end)

test("Economy: umbrales de la barra", function()
	local minRarity, luck, reached = Economy.thresholdFor(0.1)
	expect(minRarity == "Common" and luck == 1 and reached == 0)
	minRarity, luck, reached = Economy.thresholdFor(0.8)
	expect(minRarity == "Epic" and reached == 3 and luck > 1)
end)

test("Economy: incubación más rápida con mejoras y pase", function()
	local base = Economy.incubationSeconds(600, 0, false)
	expect(base == 600)
	expect(Economy.incubationSeconds(600, 5, false) < base)
	expect(Economy.incubationSeconds(600, 0, true) == 300)
end)

test("Quests: tres misiones distintas por día y deterministas", function()
	local a = Quests.forDay(20000)
	local b = Quests.forDay(20000)
	expect(#a == 3)
	for i = 1, 3 do
		expect(a[i].Kind == b[i].Kind)
		for j = i + 1, 3 do
			expect(a[i].Kind ~= a[j].Kind)
		end
	end
end)

test("Quests: progreso y racha de 7 días", function()
	local state = Quests.newState(100)
	state.List = { { Kind = "Steal", Goal = 1, Progress = 0, Claimed = false } }
	expect(Quests.progress(state, "Steal", 1) == 1)
	expect(Quests.progress(state, "Steal", 1) == 0)

	local s = Quests.newState(100)
	local rewarded = false
	for day = 100, 106 do
		rewarded = Quests.rollover(s, day)
	end
	expect(rewarded, "la racha del día 7 da premio")
	expect(Quests.rollover(s, 108) == false and s.Streak == 1, "saltarse un día reinicia")
end)

test("PlayerData.reconcile repara datos corruptos", function()
	local p = PlayerData.reconcile({
		Coins = "mucho",
		Dust = 50,
		Upgrades = { Bag = 3, Fake = 9 },
		Creatures = {
			{ Id = "ok", Genes = Genes.rollSet(seeded(1), "Epic"), Rarity = "Common", Origin = "Hatch", Born = 0 },
			{ Id = "malo", Genes = { Body = "nada" }, Rarity = "Rare" },
		},
	}, 1000)
	expect(p.Coins == 0 and p.Dust == 50)
	expect(p.Upgrades.Bag == 3 and (p.Upgrades :: any).Fake == nil)
	expect(#p.Creatures == 1 and p.Creatures[1].Rarity == "Epic")
	expect(p.Quests.Day == Quests.dayNumber(1000))
end)

test("PlayerData: recibos acotados", function()
	local p = PlayerData.default(0)
	for i = 1, 60 do
		PlayerData.addReceipt(p, tostring(i))
	end
	expect(#p.Receipts == PlayerData.MaxReceipts)
	expect(PlayerData.hasReceipt(p, "60") and not PlayerData.hasReceipt(p, "1"))
end)

test("Genes.commonCopy solo deja genes comunes y conserva los que ya lo eran", function()
	local rng = seeded(31)
	local source = Genes.rollSet(rng, "Legendary")
	local copy = Genes.commonCopy(source, rng)
	expect(Genes.isValidSet(copy) and Genes.rarityOf(copy) == "Common")
	for _, slot in Genes.Slots do
		local original = Genes.get((source :: any)[slot])
		if original and original.Rarity == "Common" then
			expect((copy :: any)[slot] == original.Id)
		end
	end
end)

test("ChaseRules.canSteal valida pulsación, inmunidad y distancia", function()
	local hold = Config.Chase.StealHoldTime
	expect(ChaseRules.canSteal(10, nil, 0, 1) == "noHold")
	expect(ChaseRules.canSteal(10, 10 - hold * 0.5, 0, 1) == "tooShort")
	expect(ChaseRules.canSteal(10, 10 - hold, 11, 1) == "immune")
	expect(ChaseRules.canSteal(10, 10 - hold, 0, Config.Chase.StealRange + 10) == "tooFar")
	expect(ChaseRules.canSteal(10, 10 - hold, 0, 2) == "ok")
end)

test("ChaseRules: señal del portador cada pocos segundos y al final", function()
	local c = Config.Chase
	local total = 120
	local revealedTime, transitions = 0, 0
	local previous = false
	local step = 0.1
	for i = 0, total / step - 1 do
		local elapsed = i * step
		local value = ChaseRules.isRevealed(elapsed, total - elapsed)
		if value then
			revealedTime += step
		end
		if value ~= previous then
			transitions += 1
		end
		previous = value
		if not value then
			local wait = ChaseRules.nextReveal(elapsed, total - elapsed)
			expect(wait > 0 and wait <= c.RevealEvery, "la próxima señal llega dentro de un ciclo")
			expect(ChaseRules.isRevealed(elapsed + wait + 0.01, total - elapsed - wait - 0.01), "y llega cuando dice")
		else
			expect(ChaseRules.nextReveal(elapsed, total - elapsed) == 0)
		end
	end
	-- Se le ve una parte del tiempo (RevealSeconds de cada RevealEvery) más el final entero.
	local expected = (total - c.FinalRevealSeconds) * c.RevealSeconds / c.RevealEvery + c.FinalRevealSeconds
	expect(math.abs(revealedTime - expected) < c.RevealEvery, string.format("visible %.1f s (esperado ~%.1f)", revealedTime, expected))
	expect(transitions >= 2 * math.floor((total - c.FinalRevealSeconds) / c.RevealEvery), "parpadea muchas veces")
	expect(ChaseRules.isRevealed(total - 1, 1), "al final se le ve siempre")
	expect(not ChaseRules.isRevealed(0, total), "al empezar está escondido")
	expect(near(ChaseRules.holdTime(), c.StealHoldTime))
end)

test("Economy: escudos al empezar la persecución (Afinidad, elegido y novato)", function()
	local sh = Config.Shields
	local base = Economy.shields(sh.HeatPerShield * 5)
	expect(base == sh.Max, "la Afinidad da como mucho Max escudos")
	expect(Economy.startShields(0, false, 999) == 0)
	expect(Economy.startShields(0, true, 999) == sh.ChosenBonus, "el elegido recibe su escudo extra")
	expect(Economy.startShields(0, false, 0) == sh.NewPlayerBonus, "el novato recibe el suyo")
	expect(Economy.startShields(sh.HeatPerShield, true, 0) == 1 + sh.ChosenBonus + sh.NewPlayerBonus, "se suman")
	expect(Economy.startShields(0, false, sh.NewPlayerRounds) == 0, "solo las primeras rondas")
	-- Llevar la criatura: con CarrierMaxBoots, como unas botas al máximo.
	local carrier = Economy.walkSpeed(0, true, false)
	local expected = Config.Movement.BaseWalkSpeed * Config.Chase.CarrierSpeedMultiplier * (if Config.Chase.CarrierMaxBoots then 1 + Config.Movement.BootsMaxLevel * Config.Movement.BootsPerLevel else 1)
	expect(near(carrier, expected))
end)

test("Economy: meta de la barra", function()
	expect(Economy.barGoal(12) == math.max(Config.Round.BarGoalMin, Config.Round.BarGoalBase + 12 * Config.Round.BarGoalPerPlayer))
	expect(Economy.barGoal(16) > Economy.barGoal(4))
end)

test("ArenaLayout: árboles sin solaparse, rampas que llegan arriba y enlaces cortos de saltar", function()
	local arena = ArenaLayout.get()
	expect(#arena.Trees == 12 and #arena.Links > 20 and #arena.Rides == 12)
	-- El doble de alto que la primera versión (68 studs).
	expect(ArenaLayout.Levels[#ArenaLayout.Levels] >= 2 * 68 - 4)
	for i, a in arena.Trees do
		-- Lejos del claro del huevo y de los nidos.
		local d = math.sqrt(a.X * a.X + a.Z * a.Z)
		expect(d - ArenaLayout.rampRadius(a) > MapLayout.ClearingRadius + 10, "el claro del huevo sigue igual")
		expect(d + ArenaLayout.rampRadius(a) < MapLayout.NestRadius - 6, "no pisa los nidos")
		for j, b in arena.Trees do
			if i < j then
				local dist = math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
				local edges = ArenaLayout.rampRadius(a) + ArenaLayout.rampRadius(b) + ArenaLayout.RampWidth
				expect(dist > edges, string.format("las rampas de %d y %d no se tocan (%.1f > %.1f)", i, j, dist, edges))
			end
		end
		-- La plataforma (octógono) no llega a la rampa ni a la escalera en ninguna dirección.
		for k = 0, 71 do
			local angle = k * math.pi / 36
			local edge = ArenaLayout.deckEdge(a, angle)
			expect(edge >= ArenaLayout.deckHalf(a) - 1e-6 and edge <= ArenaLayout.deckOuter(a) + 1e-6)
		end
		expect(ArenaLayout.rampRadius(a) - ArenaLayout.RampWidth / 2 > ArenaLayout.deckOuter(a), "la rampa va por fuera de las esquinas")
		expect(near(ArenaLayout.deckEdge(a, ArenaLayout.faceAngle(1.234)), ArenaLayout.deckHalf(a), 1e-6), "la escalera queda pegada a una cara")
		if a.Ramp then
			local points = ArenaLayout.rampPoints(a)
			expect(near(points[#points].Y, a.Decks[#a.Decks], 1e-6), "la rampa acaba en la plataforma de arriba")
			for k = 2, #points do
				local p, q = points[k - 1], points[k]
				local run = math.sqrt((p.X - q.X) ^ 2 + (p.Z - q.Z) ^ 2)
				expect((q.Y - p.Y) / run < math.tan(math.rad(30)), "pendiente que se sube andando")
			end
		else
			expect(a.Ladder, "si no hay rampa, hay escalera")
		end
	end
	for _, link in arena.Links do
		if link.Kind == "Stones" then
			local a, b = ArenaLayout.linkEnds(arena, link)
			local points = ArenaLayout.stonePoints(arena, link)
			local previous = a
			table.insert(points, b)
			for _, p in points do
				-- Un salto normal (JumpPower 50, 16 studs/s) cubre ~8 studs y sube ~7.
				local gap = math.sqrt((p.X - previous.X) ^ 2 + (p.Z - previous.Z) ^ 2) - 4
				expect(gap < 6, "piedras a distancia de salto")
				expect(p.Y - previous.Y < 4, "sin escalones imposibles")
				previous = p
			end
		end
	end
	expect(#ArenaLayout.deckSpots() > 0)
	for _, ride in arena.Rides do
		local run = math.sqrt((ride.From.X - ride.To.X) ^ 2 + (ride.From.Z - ride.To.Z) ^ 2)
		local slope = math.deg(math.atan2(ride.From.Y - ride.To.Y, run))
		expect(slope > 15 and slope < 45, string.format("%s con pendiente razonable (%.0f°)", ride.Kind, slope))
	end
end)

test("Rewards: ganador, aliado y consolación", function()
	local participants: { Rewards.Participant } = {
		{ Key = "gana", Affinity = 400, StealAttempts = 1 },
		{ Key = "aliado", Affinity = 100, StealAttempts = 0 },
		{ Key = "otro", Affinity = 0, StealAttempts = 3 },
	}
	local r = Rewards.compute(participants, { { Winner = "gana", Partners = { "aliado" } } })
	local winnerDust = Config.Consolation.WinnerBonusDust + Economy.consolationDust(400, 1)
	expect(r.gana.Won[1] == 1 and r.gana.Dust == winnerDust)
	expect(r.aliado.Copies[1] == 1 and r.aliado.Dust == Economy.consolationDust(100, 0) + math.floor(winnerDust * Config.Deal.DustShare))
	expect(#r.otro.Copies == 0 and #r.otro.Won == 0 and r.otro.Dust == Economy.consolationDust(0, 3))
	local escaped = Rewards.compute(participants, { { Winner = nil, Partners = { "aliado" } } })
	expect(#escaped.aliado.Copies == 0 and #escaped.gana.Won == 0)
end)

test("Rewards: varias criaturas e inactivos", function()
	local participants: { Rewards.Participant } = {
		{ Key = "a", Affinity = 300, StealAttempts = 0 },
		{ Key = "b", Affinity = 300, StealAttempts = 0 },
		{ Key = "c", Affinity = 300, StealAttempts = 0 },
		{ Key = "afk", Affinity = 0, StealAttempts = 0, Active = false },
	}
	local r = Rewards.compute(participants, {
		{ Winner = "a", Partners = {}, Chosen = "a" },
		{ Winner = "b", Partners = {}, Chosen = "c" },
	})
	expect(r.a.Won[1] == 1 and r.b.Won[1] == 2 and #r.c.Won == 0)
	expect(r.c.ChosenEgg and not r.a.ChosenEgg, "el elegido de la segunda criatura la perdió")
	expect(r.afk.Dust == 0, "un AFK no cobra consuelo")
end)

test("MapLayout: nidos, entradas y géiseres", function()
	for index = 1, Config.Nest.Count do
		local center = MapLayout.nestCenter(index)
		expect(near(MapLayout.distance(center, { X = 0, Z = 0 }), MapLayout.NestRadius, 1e-6))
		expect(MapLayout.insideNest(index, center))
		expect(not MapLayout.insideNest(index, MapLayout.nestEntrance(index)))
		expect(not MapLayout.insideNest(index, { X = 0, Z = 0 }))
	end
	expect(#MapLayout.geyserPositions() == Config.Heat.Geyser.Count)
	local rng = seeded(8)
	for _ = 1, 500 do
		local p = MapLayout.randomInRing(rng, MapLayout.SourceRing.Min, MapLayout.SourceRing.Max)
		local d = MapLayout.distance(p, { X = 0, Z = 0 })
		expect(d >= MapLayout.SourceRing.Min - 1e-6 and d <= MapLayout.SourceRing.Max + 1e-6)
	end
end)

test("Economy: liberar criaturas", function()
	expect(Economy.releaseDust("Common") == Config.Release.Dust.Common)
	expect(Economy.releaseDust("Secret") == nil, "las Secretas no se liberan")
	local rng = seeded(21)
	local creatures = {}
	for i = 1, 60 do
		local rarity: Rarity.RarityName = if i <= 5 then "Epic" elseif i == 6 then "Secret" else "Common"
		table.insert(creatures, Creature.new("c" .. i, Genes.rollSet(rng, rarity), "Test", 0))
	end
	local slots = 10
	local ids = Economy.bulkReleaseIds(creatures, slots)
	-- Nunca baja del mínimo, nunca toca las que producen y solo libera Comunes.
	expect(#ids == #creatures - Config.Release.KeepAtLeast, tostring(#ids))
	local top = Creature.sortByIncome(creatures)
	local active = {}
	for i = 1, slots do
		active[top[i].Id] = true
	end
	local byId = {}
	for _, c in creatures do
		byId[c.Id] = c
	end
	for _, id in ids do
		expect(not active[id], "liberó una criatura del nido")
		expect(byId[id].Rarity == "Common")
	end
	-- Con pocas criaturas no libera nada.
	local few = table.move(creatures, 1, 30, 1, {})
	expect(#Economy.bulkReleaseIds(few, 5) == 0)
end)

test("Decoraciones: catálogo, aspecto y datos guardados", function()
	local seen = {}
	for _, def in Config.Decorations do
		expect(not seen[def.Id], "id repetido " .. def.Id)
		seen[def.Id] = true
		expect(def.Currency == "Coins" or def.Currency == "Dust")
		expect(Decorations.Pieces[def.Id] ~= nil, "sin aspecto: " .. def.Id)
		expect(Economy.decoration(def.Id) == def)
		expect(Economy.decorationCost(def) > 0)
	end
	expect(Economy.decoration("nope") == nil)
	expect(Economy.beauty({ "lanterns", "flowers", "desconocida" }) == 3)
	local profile = PlayerData.reconcile({ Decorations = { "lanterns", "lanterns", 5, "rug" } }, 0)
	expect(#profile.Decorations == 2)
	expect(#PlayerData.reconcile({}, 0).Decorations == 0)
end)

test("Rewards: premio al elegido que pierde", function()
	local participants: { Rewards.Participant } = {
		{ Key = "gana", Affinity = 500, StealAttempts = 2 },
		{ Key = "elegido", Affinity = 800, StealAttempts = 0 },
		{ Key = "otro", Affinity = 800, StealAttempts = 0 },
	}
	local r = Rewards.compute(participants, { { Winner = "gana", Partners = {}, Chosen = "elegido" } })
	expect(r.elegido.ChosenEgg and not r.otro.ChosenEgg and not r.gana.ChosenEgg)
	expect(r.elegido.Dust == r.otro.Dust + Config.Consolation.ChosenBonusDust)
	-- Si el elegido gana, no hay premio extra: ya tiene la criatura.
	local own = Rewards.compute(participants, { { Winner = "elegido", Partners = {}, Chosen = "elegido" } })
	expect(own.elegido.Won[1] == 1 and not own.elegido.ChosenEgg)
	-- Si la criatura escapa, el elegido también recibe su huevo.
	expect(Rewards.compute(participants, { { Winner = nil, Partners = {}, Chosen = "elegido" } }).elegido.ChosenEgg)
end)

test("Events: ventanas horarias y Huevo Comunitario", function()
	-- 2026-10-24 es sábado. 20:30 UTC: Luna de Sangre; 21:30: Noche de Saqueo.
	local saturday = 1792800000 - (1792800000 % 86400) -- medianoche UTC del 2026-10-24
	expect(os.date("!*t", saturday).wday == 7, "la fecha base debería ser sábado")
	expect(Events.isBloodMoon(saturday + 20.5 * 3600))
	expect(not Events.isBloodMoon(saturday + 21.5 * 3600))
	expect(Events.isLootNight(saturday + 21.5 * 3600))
	expect(not Events.isLootNight(saturday + 23.5 * 3600))
	expect(not Events.isLootNight(saturday - 86400 + 21.5 * 3600), "el viernes no hay saqueo")
	-- Ventana que cruza la medianoche.
	local late = { WeekDays = { 7 }, StartHour = 23, Hours = 2 }
	expect(Events.inWindow(late, saturday + 86400 + 0.5 * 3600))
	expect(not Events.inWindow(late, saturday + 86400 + 1.5 * 3600))
	expect(Events.monthKey(saturday) == "2026-10")
	local a = Events.communityGenes("2026-10")
	local b = Events.communityGenes("2026-10")
	expect(a.Body == b.Body and a.Pattern == b.Pattern and a.Mutation == b.Mutation, "misma criatura para todos")
	expect(Genes.rarityOf(a) == Config.Events.Community.Rarity)
	local goal = Config.Events.Community.Goal
	expect(Events.communityEligible(Config.Events.Community.MinContribution, false, goal))
	expect(not Events.communityEligible(Config.Events.Community.MinContribution, true, goal))
	expect(not Events.communityEligible(Config.Events.Community.MinContribution - 1, false, goal))
	expect(not Events.communityEligible(10 ^ 6, false, goal - 1))
end)

test("Events.canLoot: defensas, Secretas, límites y pulsación", function()
	local hold = Config.Events.LootNight.HoldSeconds
	local base: Events.LootCheck = {
		Now = 100,
		HoldStartedAt = 100 - hold,
		Distance = 5,
		IsOwner = false,
		OwnerHome = false,
		Rarity = "Rare",
		LootsThisRound = 0,
		NestCooldownUntil = 0,
	}
	local function with(changes: { [string]: any }): Events.LootCheck
		local c = table.clone(base) :: any
		for k, v in changes do
			c[k] = v
		end
		return c
	end
	expect((Events.canLoot(base)))
	expect(not Events.canLoot(with({ OwnerHome = true })), "dueño en casa")
	expect(not Events.canLoot(with({ Rarity = "Secret" })), "Secreta")
	expect(not Events.canLoot(with({ IsOwner = true })))
	expect(not Events.canLoot(with({ LootsThisRound = Config.Events.LootNight.PerRound })))
	expect(not Events.canLoot(with({ NestCooldownUntil = 101 })))
	expect(not Events.canLoot(with({ Distance = Config.Events.LootNight.MaxDistance + 1 })))
	expect(not Events.canLoot(with({ HoldStartedAt = 100 - hold / 2 })), "pulsación corta")
end)

test("Economy.partyShare: la Bandada reparte el 10 % del depósito", function()
	local keep, each = Economy.partyShare(1000, 3)
	expect(each == math.floor(1000 * Config.Party.HeatShare / 3))
	expect(keep + each * 3 == 1000, "no se crea ni se pierde Calor")
	local solo, none = Economy.partyShare(1000, 0)
	expect(solo == 1000 and none == 0)
end)

test("Trade: doble confirmación y cambio atómico", function()
	local rng = seeded(31)
	local function make(prefix: string, n: number): { Creature.Creature }
		local list = {}
		for i = 1, n do
			table.insert(list, Creature.new(prefix .. i, Genes.rollSet(rng, "Rare"), "Test", 0))
		end
		return list
	end
	local a, b = make("a", 5), make("b", 5)
	local function owns(list: { Creature.Creature }): (string) -> boolean
		return function(id)
			for _, c in list do
				if c.Id == id then
					return true
				end
			end
			return false
		end
	end
	local t = Trade.new("1", "2")
	expect(Trade.sideOf(t, "2") == "B" and Trade.sideOf(t, "3") == nil)
	expect(not Trade.setReady(t, "A", 0), "no se puede estar listo sin ofertas")
	expect(not Trade.setOffer(t, "A", { "b1" }, owns(a)), "no puedes ofrecer lo que no tienes")
	expect(not Trade.setOffer(t, "A", { "a1", "a1" }, owns(a)), "sin repetidos")
	expect(not Trade.setOffer(t, "A", { "a1", "a2", "a3", "a4", "a5" }, owns(a)), "máximo por lado")
	expect(Trade.setOffer(t, "A", { "a1", "a2" }, owns(a)))
	expect(Trade.setOffer(t, "B", { "b3" }, owns(b)))
	expect(Trade.setReady(t, "A", 10) and Trade.setReady(t, "B", 11))
	expect(t.ReadyAt == 11)
	-- Antes de la espera no se puede confirmar.
	expect(not Trade.confirm(t, "A", 11 + Config.Trade.ConfirmDelay - 1) and not t.Confirmed.A)
	-- Un cambio de oferta quita el "Listo" de los dos.
	expect(Trade.setOffer(t, "B", { "b3", "b4" }, owns(b)))
	expect(not t.Ready.A and not t.Ready.B and t.ReadyAt == nil)
	Trade.setReady(t, "A", 20)
	Trade.setReady(t, "B", 20)
	local later = 20 + Config.Trade.ConfirmDelay
	expect(not Trade.confirm(t, "A", later), "falta el otro")
	expect(Trade.confirm(t, "B", later), "los dos han confirmado")
	local ok, newA, newB = Trade.apply(t, a, b)
	expect(ok and #newA == 5 and #newB == 5)
	expect(owns(newA)("b3") and owns(newA)("b4") and not owns(newA)("a1"))
	expect(owns(newB)("a1") and owns(newB)("a2") and not owns(newB)("b3"))
	-- Si una criatura ya no está (liberada, saqueada…), no cambia nada.
	local gone = table.move(a, 2, 5, 1, {})
	local ok2, sameA, sameB = Trade.apply(t, gone, b)
	expect(not ok2 and sameA == gone and sameB == b)
	expect(Trade.value({ a[1] }) == Creature.baseIncome(a[1]))
end)

test("Leaderboard: semanas, \"me gusta\" y combinación del top", function()
	-- La semana empieza el lunes 00:00 UTC.
	local monday = 1792800000 - (1792800000 % 86400) + 2 * 86400 -- lunes 2026-10-26
	expect(os.date("!*t", monday).wday == 2, "debería ser lunes")
	expect(Leaderboard.weekKey(monday) ~= Leaderboard.weekKey(monday - 1))
	expect(Leaderboard.weekKey(monday) == Leaderboard.weekKey(monday + 6 * 86400 + 86399))
	expect(Leaderboard.previousWeekKey(monday) == Leaderboard.weekKey(monday - 1))
	expect(Leaderboard.secondsToReset(monday) == 7 * 86400)
	expect(Leaderboard.secondsToReset(monday - 10) == 10)

	local state = Leaderboard.rollLikes({ Week = "viejo", Given = { 5 } }, "W1")
	expect(state.Week == "W1" and #state.Given == 0, "la semana nueva empieza de cero")
	expect(not Leaderboard.canLike(state, 1, 1), "a uno mismo no")
	expect((Leaderboard.canLike(state, 1, 2)))
	table.insert(state.Given, 2)
	expect(not Leaderboard.canLike(state, 1, 2), "una vez por nido y semana")
	for i = 1, Config.Leaderboard.LikesPerWeek do
		table.insert(state.Given, 100 + i)
	end
	expect(not Leaderboard.canLike(state, 1, 3), "tope semanal")

	local top = Leaderboard.merge({ { UserId = 1, Value = 10 }, { UserId = 2, Value = 8 }, { UserId = 3, Value = 8 } }, { [3] = 5, [4] = 1 }, 3)
	expect(#top == 3)
	expect(top[1].UserId == 3 and top[1].Value == 13, "suma lo pendiente")
	expect(top[2].UserId == 1 and top[3].UserId == 2, "orden estable en empates")
end)

test("GDD v2: criaturas por ronda, escudos, novatos y Elección múltiple", function()
	expect(Economy.creatureCount(2) == 1 and Economy.creatureCount(6) == 1)
	expect(Economy.creatureCount(7) == 2 and Economy.creatureCount(11) == 2)
	expect(Economy.creatureCount(12) == 3 and Economy.creatureCount(16) == 3)
	expect(Economy.creatureCount(100) == Config.Round.MaxCreatures)
	expect(Economy.shields(0) == 0)
	expect(Economy.shields(Config.Shields.HeatPerShield) == 1)
	expect(Economy.shields(10 ^ 6) == Config.Shields.Max)
	expect(Election.minFor(0, 0) == Config.Election.PityMaxChance, "primera ronda: mínimo alto")
	expect(Election.minFor(0, 50) == Config.Election.MinChance)
	local entries: { Election.Entry } = {
		{ Key = "a", Affinity = 100 },
		{ Key = "b", Affinity = 50 },
		{ Key = "c", Affinity = 0 },
	}
	local rng = seeded(4)
	for _ = 1, 50 do
		local picked = Election.pickMany(entries, 0.02, 2, rng)
		expect(#picked == 2 and picked[1] ~= picked[2], "sin repetir")
	end
	expect(#Election.pickMany(entries, 0.02, 5, rng) == 3, "no más elegidos que jugadores")
	-- La Secreta es rara pero alcanzable (1 entre 50 000).
	expect(near(Rarity.Info.Secret.Weight / 1_000_000, 1 / 50_000))
end)

test("GDD v2: favoritas, Luna de Sangre en varias franjas y liberación", function()
	local rng = seeded(77)
	local creatures = {}
	for i = 1, 50 do
		table.insert(creatures, Creature.new("f" .. i, Genes.rollSet(rng, if i <= 3 then "Epic" else "Common"), "Test", 0))
	end
	local favorites = { "f10", "f20", "f30", "f40" }
	local kept = Economy.keptOnRebirth(creatures, favorites)
	expect(#kept == Config.Favorites.Max, "como mucho Config.Favorites.Max sobreviven")
	for _, id in Economy.bulkReleaseIds(creatures, 3, favorites) do
		expect(not table.find(favorites, id), "las favoritas no se liberan")
	end
	-- Los datos guardados solo conservan favoritas que existen.
	local profile = PlayerData.reconcile({
		Creatures = { creatures[1], creatures[2] },
		Favorites = { "f1", "no-existe", "f1", "f2" },
	}, 0)
	expect(#profile.Favorites == 2 and profile.Favorites[1] == "f1" and profile.Favorites[2] == "f2")
	-- Luna de Sangre: sábado a las 02:30, 12:30 y 20:30 UTC.
	local saturday = 1792800000 - (1792800000 % 86400)
	for _, hour in Config.Events.BloodMoon.StartHours do
		expect(Events.isBloodMoon(saturday + (hour + 0.5) * 3600))
	end
	expect(not Events.isBloodMoon(saturday + 6 * 3600))
end)

test("brasas por niveles: naranjas abajo, azules desde la mitad y moradas en la cima", function()
	local tiers = ArenaLayout.deckSpotsByTier()
	expect(#tiers.Low > 0 and #tiers.Mid > 0 and #tiers.Top > 0)
	for _, spot in tiers.Low do
		expect(spot.Y < ArenaLayout.MidHeight)
	end
	for _, spot in tiers.Mid do
		expect(spot.Y >= ArenaLayout.MidHeight)
	end
	expect(#tiers.Top == #ArenaLayout.get().Trees * ArenaLayout.DeckSides, "una plataforma de cima por árbol")
	expect(#ArenaLayout.deckSpots() == #tiers.Low + #tiers.Mid + #tiers.Top)
	-- Cada nivel vale el doble que el anterior.
	expect(Config.Heat.BlueEmber.Amount == Config.Heat.Ember.Amount * 2)
	expect(Config.Heat.PurpleEmber.Amount == Config.Heat.BlueEmber.Amount * 2)
end)

test("los sonidos están equilibrados (ninguno satura ni desaparece)", function()
	for name, sound in Sounds.Catalog do
		expect(sound.Volume > 0.03 and sound.Volume <= Sounds.MaxVolume, name)
		expect(Sounds.Gain[sound.Id] ~= nil, name .. " usa un audio sin Gain")
	end
	-- Los momentos clave suenan más que lo que se repite mucho.
	expect(Sounds.Catalog.Win.Volume > Sounds.Catalog.Pickup.Volume)
	expect(Sounds.Catalog.Steal.Volume > Sounds.Catalog.StepSoft.Volume * 3)
end)

test("los nidos del lobby no se solapan con sus vecinos", function()
	local lobby = Config.Lobby
	local radius = MapLayout.lobbyNestRadius()
	local half = lobby.NestSize / 2 + 1
	-- Esquinas de un nido (cuadrado mirando a la plaza) en el ángulo dado.
	local function corners(angle: number): { { number } }
		local cx, cz = math.cos(angle) * radius, math.sin(angle) * radius
		local fx, fz = -math.cos(angle), -math.sin(angle) -- hacia la plaza
		local rx, rz = -fz, fx
		local out = {}
		for _, s in { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } } do
			table.insert(out, { cx + (fx * s[1] + rx * s[2]) * half, cz + (fz * s[1] + rz * s[2]) * half })
		end
		return out
	end
	-- Distancia mínima entre los bordes de dos cuadrados (que no se cruzan): la menor distancia
	-- de una esquina de uno a un lado del otro.
	local function pointSegment(p: { number }, a: { number }, b: { number }): number
		local abx, abz = b[1] - a[1], b[2] - a[2]
		local t = math.clamp(((p[1] - a[1]) * abx + (p[2] - a[2]) * abz) / (abx * abx + abz * abz), 0, 1)
		local dx, dz = p[1] - (a[1] + abx * t), p[2] - (a[2] + abz * t)
		return math.sqrt(dx * dx + dz * dz)
	end
	local function gap(a: { { number } }, b: { { number } }): number
		local best = math.huge
		for _, pair in { { a, b }, { b, a } } do
			for _, p in pair[1] do
				for i = 1, 4 do
					best = math.min(best, pointSegment(p, pair[2][i], pair[2][i % 4 + 1]))
				end
			end
		end
		return best
	end
	local step = 2 * math.pi / lobby.NestCount
	expect(gap(corners(step), corners(2 * step)) >= lobby.NestGap - 0.01, "los nidos vecinos se tocan")
end)

test("los precios de la tienda son redondos en todos los niveles", function()
	local function isRound(n: number): boolean
		if n < 100 then
			return n % 5 == 0
		end
		local step = 10 ^ (math.floor(math.log10(n)) - 1)
		return n % step == 0
	end
	expect(Economy.roundPrice(1312) == 1300 and Economy.roundPrice(56273) == 56000 and Economy.roundPrice(375) == 380)
	for _, name in Economy.UpgradeNames do
		local last = 0
		for level = 0, 30 do
			local cost = Economy.upgradeCost(name, level)
			if not cost then
				break
			end
			expect(isRound(cost), name .. " nivel " .. level .. ": " .. cost)
			expect(cost > last, name .. " no sube de precio en el nivel " .. level)
			last = cost
		end
	end
	for _, rarity in Rarity.Order do
		expect(isRound(Economy.breedCost(rarity)), "cría " .. rarity)
	end
	for generation = 0, 10 do
		expect(isRound(Economy.rebirthCoins(generation)))
	end
	for _, def in Config.Decorations do
		expect(isRound(Economy.decorationCost(def)), def.Name)
	end
end)

test("anti-trampas: lo legal pasa y lo imposible no", function()
	local dt = Config.AntiCheat.CheckEvery
	-- Andar, esprintar con la criatura, tirolina, tobogán, seta trampolín y caer: legal.
	expect(MovementRules.check(16 * dt, 0, 0, dt) == "ok")
	expect(MovementRules.check(16 * 1.1 * Config.Chase.SprintMultiplier * dt, 0, 0, dt) == "ok")
	expect(MovementRules.check(Config.Arena.ZiplineSpeed * dt, -20 * dt, 0, dt) == "ok")
	expect(MovementRules.check(0, Config.Arena.TrampolinePower * dt, 0, dt) == "ok")
	expect(MovementRules.check(0, -200 * dt, 0, dt) == "ok")
	-- Un tirón por lag (2 s de tirolina de golpe) tampoco debería castigarse.
	expect(MovementRules.check(Config.Arena.ZiplineSpeed * 2, 0, 0, 2) == "ok")
	-- Teletransportarse 200 studs o subir 150 de golpe: no.
	expect(MovementRules.check(200, 0, 0, dt) == "tooFast")
	expect(MovementRules.check(0, 150, 0, dt) == "tooHigh")
	expect(#MovementRules.recentStrikes({ 0, 50, 100 }, 120) == 1, "solo cuentan los del último minuto")
end)

test("límite de remotos: cubo de fichas", function()
	local limiter = RateLimiter.new(3, 2)
	for _ = 1, 3 do
		expect(limiter:allow("a", 0))
	end
	expect(not limiter:allow("a", 0), "la cuarta llamada seguida se ignora")
	expect(limiter:allow("b", 0), "cada clave tiene su cubo")
	expect(limiter:allow("a", 0.5), "medio segundo después hay una ficha más")
	expect(not limiter:allow("a", 0.5))
	limiter:forget("a")
	expect(limiter:allow("a", 0.5), "al olvidar, se empieza de cero")
	-- Pulsar un botón a mano (5 veces por segundo) nunca llega al límite real.
	local real = RateLimiter.new(Config.AntiCheat.RemoteCapacity, Config.AntiCheat.RemoteRefillPerSecond)
	local ok = true
	for i = 0, 50 do
		ok = ok and real:allow("p", i * 0.2)
	end
	expect(ok)
end)

test("límites de intercambio: tope diario y Secretas bloqueadas unos días", function()
	local now = 1_800_000_000
	local day = 86400
	local secret = Creature.new("s1", Genes.rollSet(seeded(5), "Secret"), "Hatch", now - day)
	local epic = Creature.new("e1", Genes.rollSet(seeded(6), "Epic"), "Hatch", now)
	expect(Trade.isLocked(secret, now), "Secreta de hace 1 día: bloqueada")
	expect(not Trade.isLocked(secret, now + Config.Trade.SecretLockDays * day), "a los días, libre")
	expect(not Trade.isLocked(epic, now), "las demás rarezas no se bloquean")
	-- Al llegar por intercambio, vuelve a contar desde ese momento.
	local state = Trade.new("a", "b")
	state.Offers.A = { "s1" }
	local later = now + Config.Trade.SecretLockDays * day + 1
	local ok, _, newB = Trade.apply(state, { secret }, {}, later)
	expect(ok and newB[1].Received == later and Trade.isLocked(newB[1], later + 1))
	local records = {}
	for i = 1, Config.Trade.MaxPerDay do
		table.insert(records, { At = now - i * 60 })
	end
	table.insert(records, { At = now - 2 * day })
	expect(Trade.tradesToday(records, now) == Config.Trade.MaxPerDay, "los de hace 2 días no cuentan")
end)

print(string.format("%d pruebas correctas, %d fallidas", passed, failed))
if failed > 0 then
	error("hay pruebas fallidas")
end
