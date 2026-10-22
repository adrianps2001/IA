--!strict
-- Tipos de jugador que imitan los bots. Cada número es una probabilidad o un umbral que
-- decide su comportamiento en la ronda y en la gestión del nido.

export type Archetype = {
	Key: string,
	Label: string,
	DepositAt: number, -- deposita al llenar esta fracción de la bolsa
	ChaseDesire: number, -- probabilidad de perseguir al portador
	BumpDesire: number, -- probabilidad de ir a empujar a alguien con la bolsa llena
	GeyserCoop: number, -- probabilidad de ir a un géiser cercano
	Social: number, -- probabilidad de ofrecer/aceptar tratos y pasar el relevo
	Betray: number, -- probabilidad de traicionar a un aliado portador
	HoldSkill: number, -- probabilidad por segundo de NO soltar el botón al robar
	Idle: number, -- probabilidad por segundo de quedarse parado un rato
	Reaction: number, -- segundos que tarda en reaccionar a dónde está el portador
	SessionsPerDay: number, -- sesiones de juego al día (de media)
	RoundsPerSession: number,
	Reserve: number, -- fracción de Monedas que se guarda en vez de gastar
	Payer: boolean, -- tiene los pases x2 Monedas, Nido VIP y Bolsa Grande
}

local Archetypes = {}

Archetypes.List = {
	{
		Key = "Collector",
		Label = "Recolector",
		DepositAt = 0.9,
		ChaseDesire = 0.45,
		BumpDesire = 0.05,
		GeyserCoop = 0.7,
		Social = 0.4,
		Betray = 0.05,
		HoldSkill = 0.95,
		Idle = 0.01,
		Reaction = 0.6,
		SessionsPerDay = 2,
		RoundsPerSession = 3,
		Reserve = 0.1,
		Payer = false,
	},
	{
		Key = "Thief",
		Label = "Ladrón",
		DepositAt = 0.6,
		ChaseDesire = 0.95,
		BumpDesire = 0.6,
		GeyserCoop = 0.3,
		Social = 0.3,
		Betray = 0.35,
		HoldSkill = 0.93,
		Idle = 0.01,
		Reaction = 0.35,
		SessionsPerDay = 2,
		RoundsPerSession = 3,
		Reserve = 0.1,
		Payer = false,
	},
	{
		Key = "Casual",
		Label = "Casual",
		DepositAt = 0.55,
		ChaseDesire = 0.5,
		BumpDesire = 0.15,
		GeyserCoop = 0.4,
		Social = 0.5,
		Betray = 0.1,
		HoldSkill = 0.8,
		Idle = 0.06,
		Reaction = 0.9,
		SessionsPerDay = 1,
		RoundsPerSession = 2,
		Reserve = 0.3,
		Payer = false,
	},
	{
		Key = "Newbie",
		Label = "Novato",
		DepositAt = 0.35,
		ChaseDesire = 0.35,
		BumpDesire = 0.05,
		GeyserCoop = 0.2,
		Social = 0.3,
		Betray = 0.05,
		HoldSkill = 0.65,
		Idle = 0.12,
		Reaction = 1.4,
		SessionsPerDay = 0.7,
		RoundsPerSession = 2,
		Reserve = 0.5,
		Payer = false,
	},
	{
		Key = "Grinder",
		Label = "Fiel",
		DepositAt = 0.85,
		ChaseDesire = 0.8,
		BumpDesire = 0.3,
		GeyserCoop = 0.6,
		Social = 0.5,
		Betray = 0.15,
		HoldSkill = 0.95,
		Idle = 0.01,
		Reaction = 0.4,
		SessionsPerDay = 4,
		RoundsPerSession = 3,
		Reserve = 0.05,
		Payer = false,
	},
	{
		Key = "Payer",
		Label = "Con pases",
		DepositAt = 0.8,
		ChaseDesire = 0.6,
		BumpDesire = 0.2,
		GeyserCoop = 0.5,
		Social = 0.4,
		Betray = 0.1,
		HoldSkill = 0.9,
		Idle = 0.02,
		Reaction = 0.6,
		SessionsPerDay = 2,
		RoundsPerSession = 3,
		Reserve = 0.05,
		Payer = true,
	},
} :: { Archetype }

Archetypes.ByKey = {} :: { [string]: Archetype }
for _, archetype in Archetypes.List do
	Archetypes.ByKey[archetype.Key] = archetype
end

-- Mezcla de población por defecto (proporciones).
Archetypes.DefaultMix = {
	Collector = 0.2,
	Thief = 0.15,
	Casual = 0.3,
	Newbie = 0.15,
	Grinder = 0.1,
	Payer = 0.1,
} :: { [string]: number }

return Archetypes
