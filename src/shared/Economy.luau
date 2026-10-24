--!strict
-- Fórmulas de economía y progresión (GDD 5 y 6). Funciones puras para poder probarlas.

local Config = require("./Config")
local Creature = require("./Creature")
local Rarity = require("./Rarity")

export type UpgradeName = "Bag" | "Boots" | "Nest" | "Incubator"

local Economy = {}

Economy.UpgradeNames = { "Bag", "Boots", "Nest", "Incubator" } :: { UpgradeName }

Economy.UpgradeDisplay = {
	Bag = "Bolsa",
	Boots = "Botas",
	Nest = "Nido",
	Incubator = "Incubadora",
} :: { [UpgradeName]: string }

-- Precio redondo (v3.1): dos cifras significativas (1.312 → 1.300; 56.273 → 56.000) y, por
-- debajo de 100, de 5 en 5. Así la tienda no enseña precios como 4.593.
function Economy.roundPrice(n: number): number
	if n <= 0 then
		return 0
	end
	if n < 100 then
		return math.max(5, math.floor(n / 5 + 0.5) * 5)
	end
	local step = 10 ^ (math.floor(math.log10(n)) - 1)
	return math.floor(n / step + 0.5) * step
end

-- Coste del siguiente nivel, o nil si ya está al máximo. El nivel 0 es el inicial.
function Economy.upgradeCost(name: UpgradeName, currentLevel: number): number?
	local def = (Config.Upgrades :: any)[name]
	if not def or currentLevel >= def.MaxLevel then
		return nil
	end
	return Economy.roundPrice(def.BaseCost * def.Growth ^ currentLevel * Config.PriceScale)
end

function Economy.bagCapacity(bagLevel: number, hasBigBagPass: boolean): number
	local level = math.clamp(bagLevel, 0, Config.Heat.BagMaxLevel - 1)
	local capacity = Config.Heat.BagBaseCapacity + level * Config.Heat.BagCapacityPerLevel
	if hasBigBagPass then
		capacity = math.floor(capacity * Config.Heat.BagGamePassMultiplier)
	end
	return capacity
end

-- atHome: el portador está dentro de su nido; intruding: está dentro de un nido ajeno
-- durante la persecución (ver Config.Chase).
function Economy.walkSpeed(bootsLevel: number, isCarrier: boolean, isSprinting: boolean): number
	-- GDD v3: llevar la criatura te da la velocidad de unas botas al máximo. Si no, un novato
	-- sin botas acababa siempre alcanzado por quien las tiene mejoradas.
	local level = if isCarrier and Config.Chase.CarrierMaxBoots then Config.Movement.BootsMaxLevel else bootsLevel
	local boots = math.clamp(level, 0, Config.Movement.BootsMaxLevel) * Config.Movement.BootsPerLevel
	local speed = Config.Movement.BaseWalkSpeed * (1 + boots)
	if isCarrier then
		speed *= Config.Chase.CarrierSpeedMultiplier
	end
	if isSprinting then
		speed *= Config.Chase.SprintMultiplier
	end
	return speed
end

-- Número corto para carteles en el mundo (12.5K, 3.1M), igual que UI.formatNumber.
function Economy.short(n: number): string
	local value = math.floor(n)
	if value >= 1e9 then
		return string.format("%.1fB", value / 1e9)
	elseif value >= 1e6 then
		return string.format("%.1fM", value / 1e6)
	elseif value >= 1e4 then
		return string.format("%.1fK", value / 1e3)
	end
	return tostring(value)
end

function Economy.nestSlots(nestLevel: number, hasVipPass: boolean): number
	local slots = Config.Nest.BaseSlots + math.max(nestLevel, 0) * Config.Nest.SlotsPerLevel
	slots = math.min(slots, Config.Nest.MaxSlots)
	if hasVipPass then
		slots += Config.Nest.VipExtraSlots
	end
	return slots
end

function Economy.incubatorSlots(hasExtraSlotPass: boolean): number
	return Config.Incubator.BaseSlots + (if hasExtraSlotPass then Config.Incubator.ExtraSlotPass else 0)
end

-- Segundos reales que tarda un huevo personal o una cría.
function Economy.incubationSeconds(baseSeconds: number, incubatorLevel: number, hasFastPass: boolean): number
	local level = math.clamp(incubatorLevel, 0, Config.Incubator.MaxLevel)
	local seconds = baseSeconds * (1 - level * Config.Incubator.SpeedPerLevel)
	if hasFastPass then
		seconds *= Config.Incubator.FastPassMultiplier
	end
	return math.max(math.floor(seconds), 1)
end

function Economy.breedSeconds(parentRarity: Rarity.RarityName): number
	return (Config.BreedSeconds :: any)[parentRarity] or Config.BreedSeconds.Common
end

function Economy.breedCost(parentRarity: Rarity.RarityName): number
	local tier = Rarity.tier(parentRarity)
	return Economy.roundPrice(Config.Breeding.CostPerTierSquared * tier * tier * Config.PriceScale)
end

function Economy.incomeMultiplier(generation: number, hasDoubleCoins: boolean, isClubMember: boolean): number
	local multiplier = 1 + math.max(generation, 0) * Config.Rebirth.MultiplierPerGeneration
	if hasDoubleCoins then
		multiplier *= 2
	end
	if isClubMember then
		multiplier *= 1.2
	end
	return multiplier
end

-- Producción acumulada sin conexión, con tope de horas (GDD 5.6).
function Economy.offlineEarnings(incomePerSecond: number, secondsAway: number): number
	local capped = math.clamp(secondsAway, 0, Config.Nest.OfflineCapHours * 3600)
	return math.floor(incomePerSecond * capped * Config.Nest.OfflineRate)
end

function Economy.rebirthCoins(generation: number): number
	return Economy.roundPrice(Config.Rebirth.BaseCoins * (generation + 1) * Config.PriceScale)
end

function Economy.canRebirth(creatureCount: number, coins: number, generation: number): boolean
	return creatureCount >= Config.Rebirth.CreaturesNeeded and coins >= Economy.rebirthCoins(generation)
end

-- Polvo que da liberar una criatura, o nil si esa rareza no se puede liberar.
function Economy.releaseDust(rarity: Rarity.RarityName): number?
	if not Config.Sinks.Release then
		return nil
	end
	return Config.Release.Dust[rarity]
end

-- Criaturas que libera "liberar guardadas": las que no producen (fuera de las `slots`
-- mejores) de rareza baja, empezando por las peores y sin bajar de KeepAtLeast en total.
-- Las favoritas nunca se liberan.
function Economy.bulkReleaseIds(creatures: { Creature.Creature }, slots: number, favorites: { string }?): { string }
	local sorted = Creature.sortByIncome(creatures)
	local maxTier = Rarity.tier(Config.Release.BulkMaxRarity :: Rarity.RarityName)
	local allowed = math.max(#sorted - Config.Release.KeepAtLeast, 0)
	local ids = {}
	for index = #sorted, slots + 1, -1 do
		if #ids >= allowed then
			break
		end
		local creature = sorted[index]
		local favorite = favorites ~= nil and table.find(favorites, creature.Id) ~= nil
		if not favorite and Rarity.tier(creature.Rarity) <= maxTier and Economy.releaseDust(creature.Rarity) then
			table.insert(ids, creature.Id)
		end
	end
	return ids
end

-- Nueva generación (GDD v2): las favoritas sobreviven; el resto del nido se vacía.
function Economy.keptOnRebirth(creatures: { Creature.Creature }, favorites: { string }): { Creature.Creature }
	local kept = {}
	for _, creature in creatures do
		if table.find(favorites, creature.Id) and #kept < Config.Favorites.Max then
			table.insert(kept, creature)
		end
	end
	return kept
end

export type Decoration = { Id: string, Name: string, Currency: string, Cost: number, Beauty: number }

function Economy.decoration(id: any): Decoration?
	for _, def in Config.Decorations do
		if def.Id == id then
			return def
		end
	end
	return nil
end

-- Precio real (las de Monedas escalan con PriceScale; las de Polvo no).
function Economy.decorationCost(def: Decoration): number
	return Economy.roundPrice(if def.Currency == "Coins" then def.Cost * Config.PriceScale else def.Cost)
end

function Economy.beauty(owned: { string }): number
	local total = 0
	for _, id in owned do
		local def = Economy.decoration(id)
		if def then
			total += def.Beauty
		end
	end
	return total
end

-- Bandada: de un depósito, cuánto se queda quien deposita y cuánto recibe cada uno de los
-- otros `others` miembros conectados.
function Economy.partyShare(amount: number, others: number): (number, number)
	if others <= 0 then
		return amount, 0
	end
	local each = math.floor(amount * Config.Party.HeatShare / others)
	return amount - each * others, each
end

-- Criaturas que salen en una ronda con `players` jugadores (GDD v2). Lo que cuenta es
-- cuántos persiguen a cada portador: se añade una criatura por cada PlayersPerCreature
-- perseguidores, entre 1 y MaxCreatures.
function Economy.creatureCount(players: number): number
	local r = Config.Round
	return math.clamp(math.ceil((players - 1) / r.PlayersPerCreature), 1, r.MaxCreatures)
end

-- Escudos de Afinidad con los que empieza la persecución quien depositó `affinity` de Calor.
function Economy.shields(affinity: number): number
	local s = Config.Shields
	if not s.Enabled or s.HeatPerShield <= 0 then
		return 0
	end
	return math.clamp(math.floor(affinity / s.HeatPerShield), 0, s.Max)
end

-- Escudos al empezar la persecución (GDD v3): los de Afinidad más los extra del elegido y
-- de los novatos (roundsPlayed = rondas jugadas antes de esta).
function Economy.startShields(affinity: number, isChosen: boolean, roundsPlayed: number): number
	if not Config.Shields.Enabled then
		return 0
	end
	local extra = (if isChosen then Config.Shields.ChosenBonus else 0)
		+ (if roundsPlayed < Config.Shields.NewPlayerRounds then Config.Shields.NewPlayerBonus else 0)
	return Economy.shields(affinity) + extra
end

-- Polvo de cáscara de consolación según Afinidad e intentos de robo (GDD 5.5).
function Economy.consolationDust(affinity: number, stealAttempts: number): number
	local c = Config.Consolation
	local attempts = math.clamp(stealAttempts, 0, c.MaxStealAttempts)
	return math.floor(c.Base + math.max(affinity, 0) * c.PerAffinity + attempts * c.PerStealAttempt)
end

function Economy.barGoal(playerCount: number): number
	return math.max(Config.Round.BarGoalMin, Config.Round.BarGoalBase + playerCount * Config.Round.BarGoalPerPlayer)
end

-- Rareza mínima y suerte según el llenado de la barra del servidor.
function Economy.thresholdFor(fraction: number): (Rarity.RarityName, number, number)
	local minRarity: Rarity.RarityName = "Common"
	local luck = 1
	local reached = 0
	for index, threshold in Config.Thresholds do
		if fraction >= threshold.Fraction then
			minRarity = threshold.MinRarity :: Rarity.RarityName
			luck = threshold.Luck
			reached = index
		end
	end
	return minRarity, luck, reached
end

return Economy
