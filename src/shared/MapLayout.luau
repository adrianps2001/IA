--!strict
-- Geometría del mapa "Bosque de Brasas" (GDD 8) en el plano XZ, sin dependencias de Roblox.
-- La usan MapService (para construirlo), HeatService (fuentes y géiseres) y el simulador.
-- Los puntos son { X, Z } en studs; el huevo está en el origen.

local Config = require("./Config")

export type Point = { X: number, Z: number }

local MapLayout = {}

MapLayout.Radius = 150 -- radio jugable
MapLayout.ClearingRadius = 25 -- claro del huevo
MapLayout.NestRadius = 128 -- distancia del centro de cada nido al huevo
MapLayout.NestSize = 26
MapLayout.NestOpening = 9 -- ancho de la entrada (y de la puerta)
MapLayout.ZoneRadius = 82
MapLayout.ZoneSize = 23
MapLayout.GeyserRadius = 58
MapLayout.SourceRing = { Min = 28, Max = 110 } -- dónde aparecen brasas y bloques de suerte
MapLayout.TreeRing = { Min = 32, Max = 108 }

-- Ángulo en grados de cada zona del GDD.
MapLayout.ZoneAngles = {
	Swamp = 45,
	CrystalCave = 135,
	Ruins = 225,
	Bridge = 315,
} :: { [string]: number }

function MapLayout.polar(angle: number, radius: number): Point
	return { X = math.cos(angle) * radius, Z = math.sin(angle) * radius }
end

function MapLayout.distance(a: Point, b: Point): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

function MapLayout.nestAngle(index: number): number
	return (index / Config.Nest.Count) * math.pi * 2
end

function MapLayout.nestCenter(index: number): Point
	return MapLayout.polar(MapLayout.nestAngle(index), MapLayout.NestRadius)
end

-- Punto justo fuera de la entrada del nido (la entrada mira al huevo).
function MapLayout.nestEntrance(index: number): Point
	return MapLayout.polar(MapLayout.nestAngle(index), MapLayout.NestRadius - MapLayout.NestSize / 2 - 1)
end

-- ¿Está el punto dentro de la parcela del nido? (cuadrado girado hacia el huevo)
function MapLayout.insideNest(index: number, point: Point): boolean
	local center = MapLayout.nestCenter(index)
	local angle = MapLayout.nestAngle(index)
	local dx, dz = point.X - center.X, point.Z - center.Z
	-- Ejes locales: radial (hacia fuera) y tangencial.
	local radial = dx * math.cos(angle) + dz * math.sin(angle)
	local tangential = -dx * math.sin(angle) + dz * math.cos(angle)
	local half = MapLayout.NestSize / 2
	return math.abs(radial) <= half and math.abs(tangential) <= half
end

function MapLayout.zoneCenter(name: string): Point
	return MapLayout.polar(math.rad(MapLayout.ZoneAngles[name] or 0), MapLayout.ZoneRadius)
end

function MapLayout.geyserPositions(): { Point }
	local count = Config.Heat.Geyser.Count
	local list = {}
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.pi / count
		table.insert(list, MapLayout.polar(angle, MapLayout.GeyserRadius))
	end
	return list
end

-- Punto aleatorio repartido uniformemente por la superficie de un anillo.
function MapLayout.randomInRing(rng: () -> number, minRadius: number, maxRadius: number): Point
	local angle = rng() * math.pi * 2
	local r = math.sqrt(minRadius * minRadius + rng() * (maxRadius * maxRadius - minRadius * minRadius))
	return MapLayout.polar(angle, r)
end

function MapLayout.randomNear(rng: () -> number, center: Point, spread: number): Point
	return { X = center.X + (rng() * 2 - 1) * spread, Z = center.Z + (rng() * 2 - 1) * spread }
end

-- Distancia de los nidos del lobby al centro de la plaza. Los nidos son cuadrados en círculo, así
-- que donde más se acercan es en sus esquinas de dentro: se aleja el círculo hasta que entre dos
-- vecinos quede al menos Config.Lobby.NestGap (antes, con 24 nidos a 120 studs, se solapaban).
function MapLayout.lobbyNestRadius(): number
	local lobby = Config.Lobby
	local half = lobby.NestSize / 2 + 1 -- con el borde de piedra
	local step = math.pi / lobby.NestCount -- media separación angular entre dos nidos
	-- La esquina de dentro tiene que quedar a NestGap/2 de la bisectriz entre los dos nidos.
	local needed = half + (lobby.NestGap / 2 + half * math.cos(step)) / math.sin(step)
	return math.max(lobby.NestRadius, needed)
end

return MapLayout
