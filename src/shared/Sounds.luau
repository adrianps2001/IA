--!strict
-- Catálogo de sonidos (GDD v3). Todos los sonidos del juego salen de aquí: para cambiar uno,
-- cambia su Id por el de otro audio y no hay que tocar nada más.
--
-- Por defecto se usan los sonidos que vienen dentro de Roblox ("rbxasset://sounds/..."), que
-- funcionan sin subir nada, con distinto tono para que no suenen todos igual. Para algo mejor:
-- en Studio, Caja de herramientas → Audio, busca un sonido (los de Roblox son gratis y se
-- pueden usar), clic derecho → Copiar ID del recurso, y pon aquí "rbxassetid://<número>".
--
-- Volume: 0 a 1. Pitch: velocidad de reproducción (1 = normal; menos = más grave).
-- Vary: variación aleatoria del tono (0,1 = ±10 %) para que repetirlo no canse.

export type Sound = { Id: string, Volume: number, Pitch: number, Vary: number? }

local PING = "rbxasset://sounds/electronicpingshort.wav"
local CLICK = "rbxasset://sounds/clickfast.wav"
local BUTTON = "rbxasset://sounds/button.wav"
local SWOOSH = "rbxasset://sounds/swoosh.wav"
local SNAP = "rbxasset://sounds/snap.wav"
local COLLIDE = "rbxasset://sounds/collide.wav"
local JUMP = "rbxasset://sounds/action_jump.mp3"
local LAND = "rbxasset://sounds/action_jump_land.mp3"

local Sounds = {}

Sounds.Catalog = {
	-- Pasos (sustituyen a los de Roblox, que chirriaban): un golpecito suave por zancada.
	StepSoft = { Id = LAND, Volume = 0.1, Pitch = 1.7, Vary = 0.12 },
	StepGrass = { Id = LAND, Volume = 0.08, Pitch = 1.45, Vary = 0.12 },
	StepWood = { Id = LAND, Volume = 0.13, Pitch = 2, Vary = 0.1 },
	Jump = { Id = JUMP, Volume = 0.22, Pitch = 1.05, Vary = 0.05 },
	Land = { Id = LAND, Volume = 0.28, Pitch = 1, Vary = 0.05 },

	-- Calor.
	Pickup = { Id = PING, Volume = 0.3, Pitch = 1.5 }, -- sube de tono si coges varias seguidas
	Deposit = { Id = SWOOSH, Volume = 0.5, Pitch = 0.8 },
	BagFull = { Id = BUTTON, Volume = 0.45, Pitch = 0.6 },
	Lucky = { Id = PING, Volume = 0.6, Pitch = 1.15 },
	Bump = { Id = COLLIDE, Volume = 0.6, Pitch = 0.9, Vary = 0.1 },
	Geyser = { Id = SWOOSH, Volume = 0.8, Pitch = 0.4 },

	-- Huevo y ronda.
	Heartbeat = { Id = LAND, Volume = 0.6, Pitch = 0.45 }, -- el latido del huevo: la firma del juego
	RoundStart = { Id = SWOOSH, Volume = 0.6, Pitch = 1.2 },
	Hatch = { Id = SNAP, Volume = 0.8, Pitch = 0.6 },
	Chosen = { Id = PING, Volume = 0.8, Pitch = 0.75 },
	ChaseStart = { Id = SWOOSH, Volume = 0.8, Pitch = 0.6 },
	Tick = { Id = CLICK, Volume = 0.35, Pitch = 1.2 },
	Results = { Id = PING, Volume = 0.6, Pitch = 1 },
	Win = { Id = PING, Volume = 0.9, Pitch = 1.3 },

	-- Persecución.
	GotCreature = { Id = PING, Volume = 0.7, Pitch = 0.8 },
	TugStart = { Id = CLICK, Volume = 0.5, Pitch = 0.9 },
	Alarm = { Id = BUTTON, Volume = 0.5, Pitch = 1.4 },
	Steal = { Id = SNAP, Volume = 0.8, Pitch = 1.1, Vary = 0.08 },
	Lost = { Id = COLLIDE, Volume = 0.6, Pitch = 0.7 },
	ShieldBreak = { Id = COLLIDE, Volume = 0.8, Pitch = 1.6 },
	Drop = { Id = SNAP, Volume = 0.6, Pitch = 0.7 },
	Reveal = { Id = PING, Volume = 0.4, Pitch = 0.6 },

	-- Parkour.
	Boing = { Id = JUMP, Volume = 0.8, Pitch = 0.55, Vary = 0.08 },
	Zipline = { Id = SWOOSH, Volume = 0.6, Pitch = 0.5 },
	Slide = { Id = SWOOSH, Volume = 0.6, Pitch = 0.9 },

	-- Interfaz, nido y lobby.
	Click = { Id = CLICK, Volume = 0.25, Pitch = 1, Vary = 0.05 },
	Purchase = { Id = PING, Volume = 0.5, Pitch = 1.6 },
	Queue = { Id = BUTTON, Volume = 0.5, Pitch = 1 },
	MatchFound = { Id = SWOOSH, Volume = 0.7, Pitch = 1.4 },
	Alert = { Id = PING, Volume = 0.45, Pitch = 0.9 },
	Fanfare = { Id = PING, Volume = 0.7, Pitch = 1.25 },
	Quest = { Id = PING, Volume = 0.45, Pitch = 1.8 },
} :: { [string]: Sound }

function Sounds.get(name: string): Sound?
	return Sounds.Catalog[name]
end

return Sounds
