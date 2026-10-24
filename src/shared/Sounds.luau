--!strict
-- Catálogo de sonidos (GDD v3). Todos los sonidos del juego salen de aquí: para cambiar uno,
-- cambia su Id por el de otro audio y no hay que tocar nada más.
--
-- Por defecto se usan los sonidos que vienen dentro de Roblox ("rbxasset://sounds/..."), que
-- funcionan sin subir nada, con distinto tono para que no suenen todos igual. Para algo mejor:
-- en Studio, Caja de herramientas → Audio, busca un sonido (los de Roblox son gratis y se
-- pueden usar), clic derecho → Copiar ID del recurso, y pon aquí "rbxassetid://<número>".
--
-- Equilibrado (v3.1): los audios de Roblox no suenan igual de fuertes (el "ping" electrónico y
-- el "snap" son muy fuertes; el "swoosh" y el clic, muy flojos), y bajar el tono también hace
-- que un sonido parezca más flojo. Por eso aquí no se escribe el volumen final, sino:
--   Level: lo importante que es el sonido (0 a 1; 1 = momentos clave como ganar o robar);
--   Group: su grupo (pasos, calor, ronda, persecución, parkour, interfaz), con su volumen;
--   y Sounds.Gain[audio] iguala lo fuerte que suena cada archivo.
-- Volume final = Level × Group × Gain × compensación de tono (calculado abajo, no tocar).
-- Para subir o bajar uno: cambia su Level. Para todo un grupo: Sounds.Groups. Si cambias un
-- audio por otro, ajusta (o añade) su Gain.
-- Pitch: velocidad de reproducción (1 = normal; menos = más grave).
-- Vary: variación aleatoria del tono (0,1 = ±10 %) para que repetirlo no canse.

export type Sound = { Id: string, Volume: number, Pitch: number, Vary: number? }
export type Group = "Steps" | "Heat" | "Round" | "Chase" | "Parkour" | "UI"
type Def = { Id: string, Level: number, Pitch: number, Vary: number?, Group: Group }

local PING = "rbxasset://sounds/electronicpingshort.wav"
local CLICK = "rbxasset://sounds/clickfast.wav"
local BUTTON = "rbxasset://sounds/button.wav"
local SWOOSH = "rbxasset://sounds/swoosh.wav"
local SNAP = "rbxasset://sounds/snap.wav"
local COLLIDE = "rbxasset://sounds/collide.wav"
local JUMP = "rbxasset://sounds/action_jump.mp3"
local LAND = "rbxasset://sounds/action_jump_land.mp3"

local Sounds = {}

-- Lo fuerte que suena cada archivo, para igualarlos (1 = normal, menos = el archivo ya es fuerte).
Sounds.Gain = {
	[PING] = 0.55,
	[SNAP] = 0.6,
	[COLLIDE] = 0.7,
	[BUTTON] = 0.85,
	[JUMP] = 0.9,
	[LAND] = 1,
	[CLICK] = 1.3,
	[SWOOSH] = 1.6,
} :: { [string]: number }

-- Volumen de cada grupo.
Sounds.Groups = {
	Steps = 0.35, -- los pasos suenan a cada zancada: muy bajitos
	Heat = 0.6,
	Round = 0.85,
	Chase = 0.85,
	Parkour = 0.6,
	UI = 0.5,
} :: { [Group]: number }

-- Ningún sonido pasa de aquí (Roblox permite hasta 10, pero por encima de 1 satura).
Sounds.MaxVolume = 0.9

Sounds.Defs = {
	-- Pasos (sustituyen a los de Roblox, que chirriaban): un golpecito suave por zancada.
	StepSoft = { Id = LAND, Level = 0.3, Pitch = 1.7, Vary = 0.12, Group = "Steps" },
	StepGrass = { Id = LAND, Level = 0.25, Pitch = 1.45, Vary = 0.12, Group = "Steps" },
	StepWood = { Id = LAND, Level = 0.35, Pitch = 2, Vary = 0.1, Group = "Steps" },
	Jump = { Id = JUMP, Level = 0.6, Pitch = 1.05, Vary = 0.05, Group = "Steps" },
	Land = { Id = LAND, Level = 0.7, Pitch = 1, Vary = 0.05, Group = "Steps" },

	-- Calor.
	Pickup = { Id = PING, Level = 0.45, Pitch = 1.5, Group = "Heat" }, -- sube de tono si coges varias seguidas
	Deposit = { Id = SWOOSH, Level = 0.6, Pitch = 0.8, Group = "Heat" },
	BagFull = { Id = BUTTON, Level = 0.6, Pitch = 0.6, Group = "Heat" },
	Lucky = { Id = PING, Level = 0.75, Pitch = 1.15, Group = "Heat" },
	Bump = { Id = COLLIDE, Level = 0.7, Pitch = 0.9, Vary = 0.1, Group = "Heat" },
	Geyser = { Id = SWOOSH, Level = 0.8, Pitch = 0.4, Group = "Heat" },

	-- Huevo y ronda.
	Heartbeat = { Id = LAND, Level = 0.6, Pitch = 0.45, Group = "Round" }, -- el latido del huevo: la firma del juego
	RoundStart = { Id = SWOOSH, Level = 0.7, Pitch = 1.2, Group = "Round" },
	Hatch = { Id = SNAP, Level = 0.9, Pitch = 0.6, Group = "Round" },
	Chosen = { Id = PING, Level = 0.85, Pitch = 0.75, Group = "Round" },
	ChaseStart = { Id = SWOOSH, Level = 0.85, Pitch = 0.6, Group = "Round" },
	Tick = { Id = CLICK, Level = 0.45, Pitch = 1.2, Group = "Round" },
	Results = { Id = PING, Level = 0.7, Pitch = 1, Group = "Round" },
	Win = { Id = PING, Level = 1, Pitch = 1.3, Group = "Round" },

	-- Persecución.
	GotCreature = { Id = PING, Level = 0.85, Pitch = 0.8, Group = "Chase" },
	TugStart = { Id = CLICK, Level = 0.6, Pitch = 0.9, Group = "Chase" },
	Alarm = { Id = BUTTON, Level = 0.65, Pitch = 1.4, Group = "Chase" },
	Steal = { Id = SNAP, Level = 0.9, Pitch = 1.1, Vary = 0.08, Group = "Chase" },
	Lost = { Id = COLLIDE, Level = 0.75, Pitch = 0.7, Group = "Chase" },
	ShieldBreak = { Id = COLLIDE, Level = 0.8, Pitch = 1.6, Group = "Chase" },
	Drop = { Id = SNAP, Level = 0.7, Pitch = 0.7, Group = "Chase" },
	Reveal = { Id = PING, Level = 0.5, Pitch = 0.6, Group = "Chase" },

	-- Parkour.
	Boing = { Id = JUMP, Level = 0.8, Pitch = 0.55, Vary = 0.08, Group = "Parkour" },
	Zipline = { Id = SWOOSH, Level = 0.7, Pitch = 0.5, Group = "Parkour" },
	Slide = { Id = SWOOSH, Level = 0.7, Pitch = 0.9, Group = "Parkour" },

	-- Interfaz, nido y lobby.
	Click = { Id = CLICK, Level = 0.5, Pitch = 1, Vary = 0.05, Group = "UI" },
	Purchase = { Id = PING, Level = 0.8, Pitch = 1.6, Group = "UI" },
	Queue = { Id = BUTTON, Level = 0.7, Pitch = 1, Group = "UI" },
	MatchFound = { Id = SWOOSH, Level = 0.9, Pitch = 1.4, Group = "UI" },
	Alert = { Id = PING, Level = 0.7, Pitch = 0.9, Group = "UI" },
	Fanfare = { Id = PING, Level = 1, Pitch = 1.25, Group = "UI" },
	Firework = { Id = SNAP, Level = 0.8, Pitch = 0.45, Vary = 0.15, Group = "UI" }, -- (v3.3) cada estallido
	Quest = { Id = PING, Level = 0.7, Pitch = 1.8, Group = "UI" },
} :: { [string]: Def }

-- Volumen final de un sonido. Los tonos graves suenan más flojos y los agudos más fuertes, así
-- que se compensa un poco (pitch^-0,3: a medio tono, ~23 % más alto).
function Sounds.volume(def: Def): number
	local gain = Sounds.Gain[def.Id] or 1
	local pitch = math.pow(math.clamp(def.Pitch, 0.25, 4), -0.3)
	return math.min(def.Level * Sounds.Groups[def.Group] * gain * pitch, Sounds.MaxVolume)
end

-- El catálogo que usan los clientes, con el volumen ya calculado.
Sounds.Catalog = {} :: { [string]: Sound }
for name, def in Sounds.Defs do
	Sounds.Catalog[name] = { Id = def.Id, Volume = Sounds.volume(def), Pitch = def.Pitch, Vary = def.Vary }
end

function Sounds.get(name: string): Sound?
	return Sounds.Catalog[name]
end

return Sounds
