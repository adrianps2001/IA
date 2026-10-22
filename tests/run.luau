--!strict
-- Pruebas de la lógica pura (sin Roblox). Ejecutar con: luau tests/run.luau

local Config = require("../src/shared/Config")
local Creature = require("../src/shared/Creature")
local Economy = require("../src/shared/Economy")
local Election = require("../src/shared/Election")
local Genes = require("../src/shared/Genes")
local PlayerData = require("../src/shared/PlayerData")
local Quests = require("../src/shared/Quests")
local Rarity = require("../src/shared/Rarity")

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
	local entries = {
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
	local entries = {
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
	expect(Economy.bagCapacity(0, true) == 150)
	expect(Economy.upgradeCost("Bag", Config.Upgrades.Bag.MaxLevel) == nil)
end)

test("Economy: nido de 6 a 40 ranuras", function()
	expect(Economy.nestSlots(0, false) == 6)
	expect(Economy.nestSlots(Config.Upgrades.Nest.MaxLevel, false) == 40)
	expect(Economy.nestSlots(0, true) == 16)
end)

test("Economy: velocidades de persecución", function()
	expect(near(Economy.walkSpeed(0, false, false), 16))
	expect(near(Economy.walkSpeed(0, true, false), 16 * 0.9))
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
	expect(Economy.offlineEarnings(10, 60) == 600)
	expect(Economy.offlineEarnings(1, 24 * 3600) == 8 * 3600)
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

print(string.format("%d pruebas correctas, %d fallidas", passed, failed))
if failed > 0 then
	error("hay pruebas fallidas")
end
