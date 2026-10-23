--!strict
-- Todos los valores ajustables del juego en un solo sitio (GDD secciones 4-9).
-- Cambiar números aquí no debería requerir tocar la lógica.

local Config = {}

-- GDD v2: rondas de ~6 minutos (antes ~12) para que una sesión tenga el doble de rondas.
Config.Round = {
	IncubationTime = 210, -- fase de recoger Calor (s); el huevo eclosiona antes si la barra llega al 100 %
	HatchTime = 10, -- eclosión y Elección: el foco salta entre los favoritos y se para (antes 30 s)
	ChaseTime = 120, -- persecución
	BloodMoonChaseTime = 160,
	ResultsTime = 8, -- los resultados siguen en pantalla mientras empieza la siguiente ronda
	IntermissionTime = 6,
	-- Varias criaturas por ronda: una más por cada PlayersPerCreature perseguidores, hasta
	-- MaxCreatures (2-6 jugadores: 1; 7-11: 2; 12 o más: 3). Con una sola criatura para 12
	-- jugadores, el elegido solo la conservaba el 10 % de las veces.
	PlayersPerCreature = 5,
	MaxCreatures = 3,
	-- Evento a mitad de la incubación: lluvia de brasas doradas (más Calor durante un rato).
	GoldenRainAt = 0.5, -- fracción de la incubación en la que empieza
	GoldenRainSeconds = 25,
	GoldenRainMultiplier = 2, -- las brasas valen el doble
	MinPlayers = 1, -- en producción, 4+; con 1 se puede probar en Studio
	MaxPlayers = 16,
	-- Calor para llenar la barra = BarGoalBase + BarGoalPerPlayer × jugadores. Las fuentes
	-- son fijas, así que cada jugador extra aporta menos: por eso hay una parte fija.
	-- Ajustado con el simulador (sim/): la barra acaba de media entre el 55 y el 70 %.
	BarGoalBase = 1800, -- GDD v2: incubación de 3,5 min (antes 6000 + 1150 para 8 min)
	BarGoalPerPlayer = 650,
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
	BagGamePassMultiplier = 1, -- GDD v2: ningún pase da más Calor (antes la Bolsa Grande daba 1,5)
	DepositRadius = 20,
	BumpDropFraction = 0.25, -- empujar a alguien con la bolsa llena le hace soltar un 25 %
	BumpCooldown = 6, -- segundos de protección tras recibir un empujón
	BumpSameTargetCooldown = 30, -- el mismo jugador no puede empujar a la misma víctima más a menudo
	NewPlayerProtectionRounds = 5, -- en sus primeras rondas, a un novato no se le puede empujar
	BumpRange = 9,
	Ember = { Amount = 5, Respawn = 8, Count = 70 },
	Firefly = { Amount = 8, Respawn = 12, Count = 20 },
	LuckyBlock = { Min = 1, Max = 50, Respawn = 30, Count = 12 },
	Geyser = { Amount = 40, Cooldown = 45, PlayersNeeded = 2, Window = 4, Count = 4 },
}

Config.Election = {
	MinChance = 0.02, -- cualquiera puede ser elegido
	-- Suerte acumulada: cada ronda sin ser elegido sube tu mínimo, hasta PityMaxChance.
	PityPerRound = 0.02,
	PityMaxChance = 0.12,
	-- Jugadores inactivos: solo pueden ser elegidos (y cobrar consuelo) quienes depositaron
	-- algo o se movieron en los últimos ActivitySeconds. Evita que un AFK arruine la ronda.
	RequireActivity = true,
	ActivitySeconds = 60,
	-- En sus primeras NewPlayerRounds rondas, el novato tiene el mínimo máximo (PityMaxChance).
	NewPlayerRounds = 1,
}

Config.Chase = {
	StealHoldTime = 1.5,
	StealRange = 9,
	ImmunityAfterSteal = 3,
	-- GDD v3: el portador va a la misma velocidad que los demás. Sin nido al que llegar, si
	-- fuera más lento le alcanzarían siempre (simulador: el elegido solo la conservaba el 16 %).
	CarrierSpeedMultiplier = 1,
	CarrierMaxBoots = false, -- el portador corre como con las botas al máximo
	SprintMultiplier = 1.4,
	SprintDuration = 2,
	SprintCooldown = 8,
	PassRange = 12,
	-- Robo por toque (GDD v2): un toque empieza un tira y afloja de StealHoldTime segundos que
	-- el servidor cuenta mientras el ladrón siga a menos de StealRange. Con false, como antes:
	-- hay que mantener el botón (incómodo en móvil y con todos moviéndose).
	TapSteal = true,
	-- Aturdimiento: quien sufre un robo no puede moverse ni robar durante estos segundos.
	StunSeconds = 2,
	-- Ventaja del elegido: segundos que los demás tardan en poder moverse al empezar.
	HeadStartSeconds = 4,
	-- Inmunidad del elegido al empezar la persecución (después, la normal tras cada robo).
	StartImmunitySeconds = 10,
	-- GDD v3: gana quien tenga la criatura al acabar el tiempo (ya no se lleva al nido).
	-- Señal: cada RevealEvery s, durante RevealSeconds, todos ven a los portadores a través
	-- de los árboles; entre señales hay que buscarlos. En los últimos FinalRevealSeconds se
	-- les ve todo el rato (final con todos a la vista).
	RevealEvery = 8,
	RevealSeconds = 2,
	FinalRevealSeconds = 10,
}

-- Escudos de Afinidad (GDD v2): cada HeatPerShield de Calor depositado en la ronda da un
-- escudo (hasta Max). Si te quitan la criatura teniendo un escudo, el escudo se rompe y el
-- robo no ocurre. Así recoger Calor también ayuda en la persecución. Sustituye al Escudo
-- de Cáscara de pago.
Config.Shields = {
	Enabled = true,
	HeatPerShield = 800,
	Max = 1,
	-- GDD v3: escudos extra al empezar la persecución (aparte del máximo). Sin nido donde
	-- asegurar, los que menos persiguen casi nunca conservaban la criatura.
	ChosenBonus = 1, -- para cada elegido
	NewPlayerBonus = 1, -- para quien lleva menos de NewPlayerRounds rondas
	NewPlayerRounds = 10,
}

-- Ladrones del bosque (GDD v2): en servidores con menos de FillTo jugadores aparecen zorros
-- que persiguen a los portadores. Si completan el tira y afloja, la criatura cae al suelo
-- (nunca se la quedan). Dan tensión a los servidores pequeños.
Config.ForestThieves = {
	Enabled = true,
	FillTo = 6,
	MaxCount = 3,
	SpeedMultiplier = 0.95,
	Reaction = 0.8, -- segundos que tardan en reaccionar a dónde va el portador
}

-- Favoritas: hasta Max criaturas marcadas con ⭐. No se pueden liberar, sobreviven a la Nueva
-- generación y la primera te acompaña en la ronda (solo estética).
Config.Favorites = { Max = 3 }

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
	-- El elegido que pierde la criatura: polvo extra y un Huevo del Elegido en la incubadora.
	ChosenBonusDust = 50,
	ChosenEgg = true,
}

Config.Nest = {
	BaseSlots = 6,
	SlotsPerLevel = 2,
	MaxSlots = 40,
	VipExtraSlots = 10,
	OfflineCapHours = 8,
	-- Fracción de la producción que se cobra sin conexión (1 = igual que jugando).
	OfflineRate = 0.25,
	Count = 16, -- nidos de salida en la arena (uno por jugador de la partida)
}

Config.Incubator = {
	BaseSlots = 1,
	ExtraSlotPass = 1,
	SpeedPerLevel = 0.05,
	MaxLevel = 5,
	FastPassMultiplier = 0.5,
	PersonalEggCostDust = 100,
	PersonalEggSeconds = 300,
	-- GDD v2: al entrar por primera vez, además de la criatura de regalo, un huevo que nace
	-- enseguida para que el novato vea pronto el ciclo del nido.
	WelcomeEggSeconds = 120,
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

Config.Breeding = {
	MutationChance = 0.1, -- probabilidad por ranura de que el gen del hijo mute
	CostPerTierSquared = 2000, -- coste = esto × nivel de rareza² del mejor padre
}

-- Escala global de precios en Monedas (mejoras, cría y Nueva generación). Es el mando
-- principal para frenar o acelerar la progresión; se ajusta con el simulador (sim/).
-- GDD v2: con rondas más cortas y varias criaturas por ronda se gana unas 2,5 veces más
-- producción por hora; con 2,5 la progresión vuelve al ritmo de antes (Nueva generación en semanas).
Config.PriceScale = 2.5

Config.Upgrades = {
	-- Primeros niveles baratos (se compran en la primera sesión) y últimos muy caros (metas
	-- de semanas). Curvas ajustadas con el simulador: ver docs/simulacion.html.
	Bag = { BaseCost = 150, Growth = 3.5, MaxLevel = 9 }, -- 100 a 1.000 de Calor en 10 niveles (0-9)
	Boots = { BaseCost = 200, Growth = 3.1, MaxLevel = 10 },
	Sniffer = { BaseCost = 100_000, Growth = 1, MaxLevel = 1 },
	Nest = { BaseCost = 300, Growth = 2.05, MaxLevel = 17 }, -- 6 + 17*2 = 40 ranuras
	Incubator = { BaseCost = 1000, Growth = 7, MaxLevel = 5 },
}

Config.Rebirth = {
	CreaturesNeeded = 40,
	BaseCoins = 100_000_000,
	MultiplierPerGeneration = 0.5,
}

-- Interruptores de los sumideros (el informe del simulador los apaga para comparar).
Config.Sinks = { Release = true, Decorations = true }

-- Liberar criaturas a cambio de Polvo de cáscara (sumidero de criaturas sobrantes).
Config.Release = {
	Dust = { Common = 2, Rare = 8, Epic = 30, Legendary = 120, Mythic = 500 } :: { [string]: number }, -- las Secretas no se liberan
	BulkMaxRarity = "Rare", -- "liberar guardadas" solo toca esta rareza o menos (v2: casi no salen Comunes)
	KeepAtLeast = 40, -- la liberación en bloque nunca baja de aquí (lo que pide la Nueva generación)
}

-- Decoración del nido: sumidero de Monedas y de Polvo. Solo estética (+ "Belleza" en el
-- cartel). El aspecto de cada pieza está en Decorations.luau.
Config.Decorations = {
	{ Id = "lanterns", Name = "Farolillos", Currency = "Coins", Cost = 25_000, Beauty = 1 },
	{ Id = "flowers", Name = "Macetas de flores", Currency = "Coins", Cost = 120_000, Beauty = 2 },
	{ Id = "rug", Name = "Alfombra mullida", Currency = "Coins", Cost = 600_000, Beauty = 3 },
	{ Id = "fountain", Name = "Fuente de piedra", Currency = "Coins", Cost = 3_000_000, Beauty = 5 },
	{ Id = "crystals", Name = "Cristales de luz", Currency = "Coins", Cost = 12_000_000, Beauty = 8 },
	{ Id = "banner", Name = "Estandarte", Currency = "Coins", Cost = 40_000_000, Beauty = 12 },
	{ Id = "statue", Name = "Estatua del huevo", Currency = "Coins", Cost = 150_000_000, Beauty = 20 },
	{ Id = "aurora", Name = "Aurora del nido", Currency = "Coins", Cost = 500_000_000, Beauty = 35 },
	{ Id = "shells", Name = "Guirnalda de cáscaras", Currency = "Dust", Cost = 400, Beauty = 2 },
	{ Id = "dustlamp", Name = "Lámpara de polvo", Currency = "Dust", Cost = 1_500, Beauty = 4 },
	{ Id = "gemtree", Name = "Árbol de gemas", Currency = "Dust", Cost = 5_000, Beauty = 8 },
	{ Id = "throne", Name = "Trono de cáscara", Currency = "Dust", Cost = 15_000, Beauty = 15 },
}

-- Bandada (GDD 9): grupos de hasta 4 que duran entre rondas. Comparten una parte del Calor
-- depositado (Afinidad), se ven a través de las paredes y, si hay un amigo de Roblox en el
-- grupo, ganan más Polvo de cáscara. No son aliados automáticos en la persecución: para
-- eso están los tratos.
Config.Party = {
	MaxSize = 4,
	HeatShare = 0.10, -- parte de cada depósito que se reparte entre el resto del grupo
	FriendDustBonus = 0.10,
	InviteTimeout = 30,
}

-- Intercambio de criaturas (ver Trade.luau).
Config.Trade = {
	MaxItems = 4, -- criaturas por lado
	ConfirmDelay = 3, -- segundos entre "Listo" de los dos y poder confirmar
	RequestTimeout = 30,
	HistorySize = 20,
}

-- Ranking semanal de robos y salón de la fama (nidos con más "me gusta" de la semana).
Config.Leaderboard = {
	Size = 10, -- puestos que se muestran en el cartel
	FlushSeconds = 60, -- cada cuánto se envían los totales y se lee el top
	LikesPerWeek = 20, -- "me gusta" que puede dar cada jugador por semana (1 por nido)
}

Config.Quests = {
	PerDay = 3,
	RewardDust = 50,
	StreakDays = 7,
}

Config.Events = {
	-- Luna de Sangre: sábados de 20:00 a 21:00 UTC.
	-- Luna de Sangre: sábados en tres franjas (02:00, 12:00 y 20:00 UTC) para que llegue a
	-- jugadores de todas las zonas horarias.
	BloodMoon = { WeekDay = 7, StartHours = { 2, 12, 20 }, Hours = 1, MinRarity = "Epic" },
	-- Noche de Saqueo: sábados y domingos de 21:00 a 23:00 UTC. Durante la Incubación se
	-- puede saquear una criatura expuesta en un nido ajeno si su dueño no está dentro.
	-- Con OwnerLoses = false (versión prudente) el dueño no pierde nada: el ladrón se lleva
	-- una copia común. Con true, la criatura cambia de dueño (las Secretas nunca).
	LootNight = {
		Enabled = true,
		WeekDays = { 7, 1 },
		StartHour = 21,
		Hours = 2,
		HoldSeconds = 4,
		MaxDistance = 12,
		PerRound = 1, -- saqueos por jugador y ronda
		NestCooldown = 90, -- segundos que un nido queda protegido tras un saqueo
		OwnerLoses = false,
		-- GDD v2: el saqueo es una fase propia de PhaseSeconds tras los resultados, en vez de
		-- competir con la incubación (antes había que elegir entre recoger Calor o vigilar).
		PhaseSeconds = 60,
	},
	-- Huevo Comunitario: todos los servidores llenan una barra global cada mes. Al llenarse,
	-- quien haya aportado al menos MinContribution recibe la criatura conmemorativa del mes
	-- (la misma para todo el mundo).
	Community = {
		Enabled = true,
		Goal = 25_000_000,
		MinContribution = 500,
		Rarity = "Epic",
		FlushSeconds = 30, -- cada cuánto se envía lo aportado a la barra global
	},
}

-- IDs reales de Roblox: sustituir los 0 tras crear los pases y productos en el Creator Hub.
Config.GamePasses = {
	EmberTrail = 0, -- estela de brasas (estética). Sustituye a la Bolsa Grande (+50 % de Calor)
	VipNest = 0,
	AutoDeposit = 0,
	DoubleCoins = 0,
	FastIncubator = 0,
	ExtraBreedSlot = 0,
} :: { [string]: number }

Config.DevProducts = {
	ServerLuck = 0,
	GoldenOffering = 0,
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
	Chosen = { Min = "Rare", Max = "Epic" }, -- premio al elegido que pierde
	Welcome = { Min = "Common", Max = "Rare" }, -- huevo de bienvenida
}

Config.ServerLuck = { Seconds = 15 * 60, Luck = 2 }
Config.CoinPacks = { CoinsSmall = 5_000, CoinsLarge = 120_000 } :: { [string]: number }

-- Lugares (GDD v3): el lobby (nidos, tienda, intercambios, emparejamiento) y las partidas
-- son dos lugares del mismo juego. Se publica el mismo archivo en los dos y cada servidor
-- sabe qué es por su PlaceId. Con los dos a 0 (o en Studio) todo funciona en un solo
-- servidor: el lobby y la arena están en el mismo mundo y "teletransportar" es mover al
-- jugador (modo combinado, para probar).
Config.Places = {
	Lobby = 0, -- PlaceId del lugar de inicio (lobby)
	Match = 0, -- PlaceId del lugar de las partidas
}

Config.Lobby = {
	-- El lobby se construye lejos de la arena (en el modo combinado comparten mundo).
	OriginX = 0,
	OriginZ = 1000,
	NestCount = 24, -- parcelas de nido en el lobby (el lobby admite más jugadores)
	NestRadius = 120, -- distancia de cada nido al centro de la plaza
	NestSize = 34,
	DisplaySlots = 12, -- criaturas que se lucen en los pedestales del nido
}

-- Emparejamiento en el lobby: se forma una partida con los que están en la cola.
Config.Matchmaking = {
	MaxPlayers = 12, -- por partida
	TargetPlayers = 8, -- con estos se sale enseguida
	MinPlayers = 4, -- con estos se sale tras FillSeconds esperando a más
	FillSeconds = 20,
	SoloSeconds = 45, -- con menos de MinPlayers se sale igualmente tras esto (zorros de relleno)
	Countdown = 5, -- cuenta atrás antes de teletransportar
	ArrivalTimeout = 25, -- la partida espera a los que faltan hasta este máximo
	RoundsPerMatch = 1, -- rondas por partida antes de volver al lobby
	TeleportRetries = 3,
}

-- Arena (GDD v3): árboles gigantes con rampas, puentes y atajos alrededor del claro.
-- La forma se genera siempre igual con esta semilla (MapLayout.arena).
Config.Arena = {
	Seed = 7,
	TrampolinePower = 95, -- velocidad vertical al pisar una seta trampolín
	ZiplineSpeed = 55, -- studs por segundo en la tirolina
	EmbersOnTrees = 0.45, -- fracción de las brasas que aparecen en las plataformas de los árboles
	LuckyOnTrees = 0.25, -- fracción de las cajas sorpresa que aparecen en lo alto
}

-- Aspecto de las criaturas: "Chibi" (monas, por defecto) o "Classic" (las de la v1).
-- Para usar modelos de un artista, ver CreatureModel.luau (carpeta ReplicatedStorage.CreatureArt).
Config.Creatures = {
	Style = "Chibi",
}

-- Pruebas en Roblox Studio (docs/PRUEBAS.md). Solo tienen efecto dentro de Studio: en un
-- servidor publicado se ignoran siempre.
Config.Testing = {
	Autopilot = true, -- las ventanas de prueba juegan solas; F8 activa/desactiva en cada ventana
	AutopilotOnFirstPlayer = false, -- Player1 (tú) empieza controlando su personaje
	DebugTools = true, -- panel de depuración (F7): saltar fase, dar Monedas, llenar la barra...
	TimeScale = 0.35, -- duración de las fases en Studio (0,35 = rondas de unos 4 min; 1 = normal)
	ForceLootNight = false, -- en Studio, todas las rondas son Noche de Saqueo
}

Config.Data = {
	StoreName = "PlayerData_v1",
	AutosaveSeconds = 60,
	LockTimeoutSeconds = 1800,
}

return Config
