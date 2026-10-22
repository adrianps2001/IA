--!strict
-- Fórmulas de economía y progresión (GDD 5 y 6). Funciones puras para poder probarlas.

local Config = require("./Config")
local Rarity = require("./Rarity")

export type UpgradeName = "Bag" | "Boots" | "Sniffer" | "Nest" | "Incubator"

local Economy = {}

Economy.UpgradeNames = { "Bag", "Boots", "Sniffer", "Nest", "Incubator" } :: { UpgradeName }

Economy.UpgradeDisplay = {
	Bag = "Bolsa",
	Boots = "Botas",
	Sniffer = "Olfato",
	Nest = "Nido",
	Incubator = "Incubadora",
} :: { [UpgradeName]: string }

-- Coste del siguiente nivel, o nil si ya está al máximo. El nivel 0 es el inicial.
function Economy.upgradeCost(name: UpgradeName, currentLevel: number): number?
	local def = (Config.Upgrades :: any)[name]
	if not def or currentLevel >= def.MaxLevel then
		return nil
	end
	return math.floor(def.BaseCost * def.Growth ^ currentLevel)
end

function Economy.bagCapacity(bagLevel: number, hasBigBagPass: boolean): number
	local level = math.clamp(bagLevel, 0, Config.Heat.BagMaxLevel - 1)
	local capacity = Config.Heat.BagBaseCapacity + level * Config.Heat.BagCapacityPerLevel
	if hasBigBagPass then
		capacity = math.floor(capacity * Config.Heat.BagGamePassMultiplier)
	end
	return capacity
end

function Economy.walkSpeed(bootsLevel: number, isCarrier: boolean, isSprinting: boolean): number
	local boots = math.clamp(bootsLevel, 0, Config.Movement.BootsMaxLevel) * Config.Movement.BootsPerLevel
	local speed = Config.Movement.BaseWalkSpeed * (1 + boots)
	if isCarrier then
		speed *= Config.Chase.CarrierSpeedMultiplier
	end
	if isSprinting then
		speed *= Config.Chase.SprintMultiplier
	end
	return speed
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
	return 100 * tier * tier
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
	return math.floor(incomePerSecond * capped)
end

function Economy.rebirthCoins(generation: number): number
	return Config.Rebirth.BaseCoins * (generation + 1)
end

function Economy.canRebirth(creatureCount: number, coins: number, generation: number): boolean
	return creatureCount >= Config.Rebirth.CreaturesNeeded and coins >= Economy.rebirthCoins(generation)
end

-- Polvo de cáscara de consolación según Afinidad e intentos de robo (GDD 5.5).
function Economy.consolationDust(affinity: number, stealAttempts: number): number
	local c = Config.Consolation
	local attempts = math.clamp(stealAttempts, 0, c.MaxStealAttempts)
	return math.floor(c.Base + math.max(affinity, 0) * c.PerAffinity + attempts * c.PerStealAttempt)
end

function Economy.barGoal(playerCount: number): number
	return math.max(Config.Round.BarGoalMin, playerCount * Config.Round.BarGoalPerPlayer)
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
