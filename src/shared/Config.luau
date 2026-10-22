--!strict
-- Todos los valores ajustables del juego en un solo sitio (GDD secciones 4-9).
-- Cambiar números aquí no debería requerir tocar la lógica.

local Config = {}

Config.Round = {
	IncubationTime = 480, -- fase de recoger Calor (s); el huevo eclosiona antes si la barra llega al 100 %
	HatchTime = 30, -- espectáculo de eclosión y Elección
	ChaseTime = 180, -- persecución
	BloodMoonChaseTime = 300,
	ResultsTime = 15,
	IntermissionTime = 15,
	MinPlayers = 1, -- en producción, 4+; con 1 se puede probar en Studio
	MaxPlayers = 16,
	BarGoalPerPlayer = 600, -- Calor necesario por jugador para llenar la barra
	BarGoalMin = 1200,
}

-- Umbrales de la barra del servidor: rareza mínima garantizada y suerte.
Config.Thresholds = {
	{ Fraction = 0.25, MinRarity = "Rare", Luck = 1.25 },
	{ Fraction = 0.5, MinRarity = "Rare", Luck = 1.5 },
	{ Fraction = 0.75, MinRarity = "Epic", Luck = 1.75 },
	{ Fraction = 1.0, MinRarity = "Epic", Luck = 2.0 },
}

Config.Heat = {
	BagBaseCapacity = 100,
	BagCapacityPerLevel = 100, -- nivel 10 = 1.000
	BagMaxLevel = 10,
	BagGamePassMultiplier = 1.5,
	DepositRadius = 20,
	BumpDropFraction = 0.25, -- empujar a alguien con la bolsa llena le hace soltar un 25 %
	BumpCooldown = 6,
	BumpRange = 9,
	Ember = { Amount = 5, Respawn = 8, Count = 60 },
	Firefly = { Amount = 8, Respawn = 12, Count = 20 },
	LuckyBlock = { Min = 1, Max = 50, Respawn = 30, Count = 10 },
	Geyser = { Amount = 40, Cooldown = 45, PlayersNeeded = 2, Window = 4, Count = 4 },
}

Config.Election = {
	MinChance = 0.02, -- cualquiera puede ser elegido
}

Config.Chase = {
	StealHoldTime = 1.5,
	StealRange = 9,
	ImmunityAfterSteal = 3,
	CarrierSpeedMultiplier = 0.9,
	SprintMultiplier = 1.4,
	SprintDuration = 2,
	SprintCooldown = 8,
	PassRange = 12,
	DoorCloseTime = 10,
	ShieldsPerRound = 1,
}

Config.Movement = {
	BaseWalkSpeed = 16,
	BootsPerLevel = 0.01,
	BootsMaxLevel = 10,
}

Config.Deal = {
	DustShare = 0.3, -- el aliado recibe el 30 % del polvo del ganador
	OfferRange = 12,
}

Config.Consolation = {
	Base = 10,
	PerAffinity = 1 / 20,
	PerStealAttempt = 15,
	MaxStealAttempts = 5,
	WinnerBonusDust = 25,
}

Config.Nest = {
	BaseSlots = 6,
	SlotsPerLevel = 2,
	MaxSlots = 40,
	VipExtraSlots = 10,
	OfflineCapHours = 8,
	Count = 16,
}

Config.Incubator = {
	BaseSlots = 1,
	ExtraSlotPass = 1,
	SpeedPerLevel = 0.05,
	MaxLevel = 5,
	FastPassMultiplier = 0.5,
	PersonalEggCostDust = 100,
	PersonalEggSeconds = 300,
}

-- Tiempo de cría (s) según la rareza más alta de los padres.
Config.BreedSeconds = {
	Common = 600,
	Rare = 1200,
	Epic = 2700,
	Legendary = 5400,
	Mythic = 10800,
	Secret = 14400,
}

Config.Upgrades = {
	Bag = { BaseCost = 150, Growth = 1.7, MaxLevel = 9 }, -- 100 a 1.000 de Calor en 10 niveles (0-9)
	Boots = { BaseCost = 200, Growth = 1.75, MaxLevel = 10 },
	Sniffer = { BaseCost = 2500, Growth = 1, MaxLevel = 1 },
	Nest = { BaseCost = 300, Growth = 1.55, MaxLevel = 17 }, -- 6 + 17*2 = 40 ranuras
	Incubator = { BaseCost = 1000, Growth = 2, MaxLevel = 5 },
}

Config.Rebirth = {
	CreaturesNeeded = 40,
	BaseCoins = 1_000_000,
	MultiplierPerGeneration = 0.5,
}

Config.Quests = {
	PerDay = 3,
	RewardDust = 50,
	StreakDays = 7,
}

Config.Events = {
	-- Luna de Sangre: sábados de 20:00 a 21:00 UTC.
	BloodMoon = { WeekDay = 7, StartHour = 20, Hours = 1, MinRarity = "Epic" },
}

-- IDs reales de Roblox: sustituir los 0 tras crear los pases y productos en el Creator Hub.
Config.GamePasses = {
	BigBag = 0,
	VipNest = 0,
	AutoDeposit = 0,
	DoubleCoins = 0,
	FastIncubator = 0,
	ExtraBreedSlot = 0,
} :: { [string]: number }

Config.DevProducts = {
	ServerLuck = 0,
	GoldenOffering = 0,
	ShellShield = 0,
	BreedReroll = 0,
	SeasonEgg = 0,
	CoinsSmall = 0,
	CoinsLarge = 0,
} :: { [string]: number }

-- Suscripción "Club del Nido" (id tipo "EXP-..." del Creator Hub; vacío = desactivada).
Config.ClubSubscriptionId = ""

-- Rangos de rareza de los huevos que no salen de una ronda.
Config.EggRanges = {
	Personal = { Min = "Common", Max = "Epic" },
	Streak = { Min = "Rare", Max = "Legendary" },
	Season = { Min = "Rare", Max = "Legendary" },
}

Config.ServerLuck = { Seconds = 15 * 60, Luck = 2 }
Config.CoinPacks = { CoinsSmall = 5_000, CoinsLarge = 120_000 } :: { [string]: number }

Config.Data = {
	StoreName = "PlayerData_v1",
	AutosaveSeconds = 60,
	LockTimeoutSeconds = 1800,
}

return Config
