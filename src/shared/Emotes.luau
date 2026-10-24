--!strict
-- Emotes con la criatura al hombro (v3.2). Cada emote mueve la criatura respecto a su sitio
-- en el hombro durante unos segundos; aquí solo están las cuentas (sin Roblox, se prueban en
-- tests/run.luau). CosmeticsController las aplica en cada cliente, así que todos lo ven.

local Emotes = {}

export type Emote = { Id: string, Name: string, Icon: string, Duration: number }
-- Desplazamiento respecto al hombro: posición (studs, en el espacio del personaje), giro sobre sí
-- misma (Spin), inclinación (Tilt, radianes) y tamaño (Scale, 1 = normal).
export type Pose = { X: number, Y: number, Z: number, Spin: number, Tilt: number, Scale: number }

Emotes.List = {
	{ Id = "wave", Name = "Saludar", Icon = "👋", Duration = 1.6 },
	{ Id = "dance", Name = "Bailar", Icon = "💃", Duration = 3 },
	{ Id = "toss", Name = "Lanzar y coger", Icon = "🤹", Duration = 1.8 },
	{ Id = "cuddle", Name = "Mimos", Icon = "🤗", Duration = 2.2 },
} :: { Emote }

local byId: { [string]: Emote } = {}
for _, emote in Emotes.List do
	byId[emote.Id] = emote
end

function Emotes.get(id: any): Emote?
	return if type(id) == "string" then byId[id] else nil
end

-- Segundos mínimos entre dos emotes del mismo jugador.
Emotes.Cooldown = 1

local REST: Pose = { X = 0, Y = 0, Z = 0, Spin = 0, Tilt = 0, Scale = 1 }

-- Pose de un emote a los t segundos de empezar (fuera de su duración, la de reposo). Todas
-- empiezan y acaban en reposo para que no haya saltos.
function Emotes.pose(id: string, t: number): Pose
	local emote = byId[id]
	if not emote or t < 0 or t >= emote.Duration then
		return REST
	end
	local f = t / emote.Duration -- 0 → 1
	local ease = math.sin(f * math.pi) -- 0 → 1 → 0
	if id == "wave" then
		-- Dos saltitos y se balancea de lado a lado.
		return { X = 0, Y = math.abs(math.sin(f * math.pi * 2)) * 0.8, Z = 0, Spin = 0, Tilt = math.sin(f * math.pi * 4) * 0.45 * ease, Scale = 1 }
	elseif id == "dance" then
		-- Dos vueltas completas botando al ritmo.
		return { X = 0, Y = math.abs(math.sin(f * math.pi * 6)) * 0.5 * ease, Z = 0, Spin = f * math.pi * 4, Tilt = math.sin(f * math.pi * 6) * 0.2 * ease, Scale = 1 }
	elseif id == "toss" then
		-- Sube por encima de la cabeza dando una voltereta y vuelve al hombro.
		return { X = -0.6 * ease, Y = 4 * math.sin(f * math.pi), Z = 0, Spin = 0, Tilt = f * math.pi * 2, Scale = 1 }
	elseif id == "cuddle" then
		-- Se pone delante de la cara, crece un poco y se acurruca.
		return { X = -1.25 * ease, Y = 0.1 * ease, Z = -1.2 * ease, Spin = math.pi * ease, Tilt = math.sin(f * math.pi * 5) * 0.12 * ease, Scale = 1 + 0.15 * ease }
	end
	return REST
end

return Emotes
