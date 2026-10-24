--!strict
-- Torre de la plaza (v3.2): las plataformas del minijuego de parkour del lobby, sin Roblox para
-- poder comprobar en las pruebas que todos los saltos se pueden hacer. ParkourService las
-- construye y cronometra; las posiciones son relativas al centro de la plaza.

local Config = require("./Config")

local LobbyParkour = {}

export type Vec = { X: number, Y: number, Z: number }
export type Kind = "Start" | "Step" | "Small" | "Beam" | "Checkpoint" | "Finish"
-- Angle: hacia dónde mira la plataforma (las vigas van a lo largo del recorrido).
export type Platform = { Index: number, Kind: Kind, Position: Vec, Size: Vec, Angle: number }

-- Altura de salto de Roblox por defecto (Humanoid.JumpHeight) y velocidad al andar.
LobbyParkour.JumpHeight = 7.2
LobbyParkour.WalkSpeed = 16

function LobbyParkour.platforms(): { Platform }
	local c = Config.LobbyParkour
	local list: { Platform } = {}
	local step = math.rad(c.AngleStep)
	for k = 0, c.Steps do
		local angle = k * step
		-- Radio alternado (un poco hacia dentro y hacia fuera) para que no sea una escalera recta.
		local r = c.Radius + (if k % 2 == 0 then -1.5 else 1.5)
		local kind: Kind = "Step"
		local size = { X = 5, Y = 1, Z = 5 }
		if k == 0 then
			kind = "Start"
			size = { X = 8, Y = 0.6, Z = 8 }
			r = c.Radius
		elseif k == c.Steps then
			kind = "Finish"
			size = { X = 8, Y = 1, Z = 8 }
		elseif table.find(c.Checkpoints, k) then
			kind = "Checkpoint"
			size = { X = 6, Y = 1, Z = 6 }
		elseif k % 7 == 3 then
			kind = "Beam"
			size = { X = 2, Y = 1, Z = 8 } -- larga a lo largo del recorrido
		elseif k % 4 == 2 then
			kind = "Small"
			size = { X = 3.5, Y = 1, Z = 3.5 }
		end
		table.insert(list, {
			Index = k,
			Kind = kind,
			Position = { X = math.cos(angle) * r, Y = if k == 0 then 0.3 else k * c.Rise, Z = math.sin(angle) * r },
			Size = size,
			Angle = angle,
		})
	end
	return list
end

-- Distancia aproximada del recorrido (de centro a centro), para el tiempo mínimo creíble.
function LobbyParkour.pathLength(): number
	local list = LobbyParkour.platforms()
	local total = 0
	for i = 2, #list do
		local a, b = list[i - 1].Position, list[i].Position
		total += math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
	end
	return total
end

-- Tiempo por debajo del cual un recorrido no es creíble (ir siempre al doble de velocidad).
function LobbyParkour.minSeconds(): number
	return LobbyParkour.pathLength() / (LobbyParkour.WalkSpeed * 2)
end

-- Índices de los puntos de control en orden (la meta exige haberlos pisado todos).
function LobbyParkour.checkpoints(): { number }
	return table.clone(Config.LobbyParkour.Checkpoints)
end

return LobbyParkour
