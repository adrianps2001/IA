--!strict
-- Geometría del parkour de la arena (GDD v3), sin dependencias de Roblox. El claro del huevo
-- no cambia; alrededor hay árboles gigantes con plataformas a tres alturas, rampas en espiral,
-- escaleras, puentes, vigas estrechas, caminos de piedras flotantes, tirolinas, toboganes,
-- setas trampolín, cabañas y arbustos para esconderse.
-- Siempre sale igual (semilla Config.Arena.Seed): el servidor lo construye y la forma se
-- puede probar sin Roblox. MapService lo convierte en piezas.

local Config = require("./Config")
local MapLayout = require("./MapLayout")

export type Vec = { X: number, Y: number, Z: number }

export type Tree = {
	Index: number,
	X: number,
	Z: number,
	Radius: number,
	Height: number,
	Decks: { number }, -- alturas de las plataformas (la de arriba es la más alta)
	Ramp: boolean, -- rampa en espiral desde el suelo hasta la plataforma más alta
	RampStart: number, -- ángulo (rad) donde empieza la rampa
	Ladder: boolean, -- escalera de mano (TrussPart) por el tronco
	Hut: number?, -- altura de la plataforma con cabaña (escondite)
	HutAngle: number,
}

export type LinkKind = "Bridge" | "Beam" | "Stones"

-- Une la plataforma de A con la de B a la misma altura.
export type Link = { A: number, B: number, Level: number, Kind: LinkKind }

-- Tirolina o tobogán: se recorre de Points[1] al último punto.
export type Ride = { Kind: "Zipline" | "Slide", From: Vec, To: Vec }

export type Trampoline = { X: number, Y: number, Z: number, Power: number }
export type Block = { X: number, Y: number, Z: number, Size: number }
export type Log = { X: number, Z: number, Angle: number, Length: number }

export type Arena = {
	Trees: { Tree },
	Links: { Link },
	Rides: { Ride },
	Trampolines: { Trampoline },
	Blocks: { Block },
	Bushes: { Vec },
	Logs: { Log },
}

local ArenaLayout = {}

ArenaLayout.DeckWidth = 6 -- ancho de las plataformas alrededor del tronco
ArenaLayout.RampWidth = 5
ArenaLayout.RampGap = 0.5 -- separación entre la plataforma y la rampa
ArenaLayout.RampStep = math.rad(15) -- ángulo de cada tablón de la rampa
ArenaLayout.RampSlope = math.rad(24) -- pendiente (los personajes y el pathfinding la suben andando)
ArenaLayout.Levels = { 24, 46, 68 }
ArenaLayout.InnerRadius = 64 -- anillo de árboles junto al claro
ArenaLayout.OuterRadius = 100 -- anillo de árboles junto a los nidos

-- Generador con semilla (xorshift32), igual que sim/Rng.luau.
local function newRng(seed: number): () -> number
	local state = bit32.bor(math.floor(math.abs(seed)) % 4294967296, 1)
	local function nextValue(): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		return state / 4294967296
	end
	for _ = 1, 16 do
		nextValue()
	end
	return nextValue
end

local function range(rng: () -> number, low: number, high: number): number
	return low + rng() * (high - low)
end

function ArenaLayout.deckHalf(tree: Tree): number
	return tree.Radius + ArenaLayout.DeckWidth
end

function ArenaLayout.rampRadius(tree: Tree): number
	return ArenaLayout.deckHalf(tree) + ArenaLayout.RampGap + ArenaLayout.RampWidth / 2
end

-- Puntos de la rampa en espiral: uno por tablón, desde el suelo hasta la plataforma más alta.
function ArenaLayout.rampPoints(tree: Tree, start: number?): { Vec }
	local radius = ArenaLayout.rampRadius(tree)
	local top = tree.Decks[#tree.Decks]
	local segment = radius * ArenaLayout.RampStep
	local rise = segment * math.tan(ArenaLayout.RampSlope)
	local count = math.ceil(top / rise)
	rise = top / count -- termina justo a la altura de la plataforma
	local angle0 = start or tree.RampStart
	local points: { Vec } = {}
	for i = 0, count do
		local angle = angle0 + i * ArenaLayout.RampStep
		table.insert(points, { X = tree.X + math.cos(angle) * radius, Y = i * rise, Z = tree.Z + math.sin(angle) * radius })
	end
	return points
end

local function angleTo(a: Tree, b: Tree): number
	return math.atan2(b.Z - a.Z, b.X - a.X)
end

local function angleDiff(a: number, b: number): number
	local d = (a - b) % (2 * math.pi)
	return math.min(d, 2 * math.pi - d)
end

-- Extremos de un enlace: del borde de la plataforma de A al de B.
function ArenaLayout.linkEnds(arena: Arena, link: Link): (Vec, Vec)
	local a, b = arena.Trees[link.A], arena.Trees[link.B]
	local angle = angleTo(a, b)
	local ha, hb = ArenaLayout.deckHalf(a), ArenaLayout.deckHalf(b)
	-- Las plataformas son cuadradas (alineadas con los ejes): el borde está más lejos en diagonal.
	local function edge(half: number): number
		local c, s = math.abs(math.cos(angle)), math.abs(math.sin(angle))
		return half / math.max(c, s) - 0.5
	end
	local ea, eb = edge(ha), edge(hb)
	return { X = a.X + math.cos(angle) * ea, Y = link.Level, Z = a.Z + math.sin(angle) * ea },
		{ X = b.X - math.cos(angle) * eb, Y = link.Level, Z = b.Z - math.sin(angle) * eb }
end

-- Ángulo de inicio de la rampa que menos choca con los puentes (que la rampa no pase justo
-- por encima de la entrada de un puente, donde daría con la cabeza).
local function pickRampStart(tree: Tree, links: { { Angle: number, Level: number } }): number
	local best, bestScore = 0, math.huge
	for k = 0, 23 do
		local start = k * ArenaLayout.RampStep
		local score = 0
		for _, point in ArenaLayout.rampPoints(tree, start) do
			local angle = math.atan2(point.Z - tree.Z, point.X - tree.X)
			for _, link in links do
				if angleDiff(angle, link.Angle) < math.rad(25) then
					local dy = point.Y - link.Level
					if dy > 1 and dy < 9 then
						score += 2
					elseif dy < -1 and dy > -7 then
						score += 1
					end
				end
			end
		end
		if tree.Hut then
			-- La rampa tampoco debe atravesar la cabaña.
			for _, point in ArenaLayout.rampPoints(tree, start) do
				local angle = math.atan2(point.Z - tree.Z, point.X - tree.X)
				if angleDiff(angle, tree.HutAngle) < math.rad(30) and math.abs(point.Y - (tree.Hut :: number)) < 12 then
					score += 3
				end
			end
		end
		if score < bestScore then
			best, bestScore = start, score
		end
	end
	return best
end

local function build(): Arena
	local rng = newRng(Config.Arena.Seed)
	local trees: { Tree } = {}
	local function addTree(angle: number, radius: number, trunk: number, decks: { number }, ramp: boolean)
		local point = MapLayout.polar(angle, radius)
		table.insert(trees, {
			Index = #trees + 1,
			X = point.X,
			Z = point.Z,
			Radius = trunk,
			Height = decks[#decks] + range(rng, 18, 28),
			Decks = decks,
			Ramp = ramp,
			RampStart = 0,
			Ladder = not ramp,
			Hut = nil,
			HutAngle = angle, -- la cabaña mira hacia fuera
		})
	end
	local levels = ArenaLayout.Levels
	-- 4 árboles grandes junto al claro (0°, 90°, 180°, 270°), entre las zonas del mapa.
	for s = 0, 3 do
		addTree(math.rad(90 * s), ArenaLayout.InnerRadius, range(rng, 7.5, 9), { levels[1], levels[2], levels[3] }, true)
	end
	-- 8 árboles junto a los nidos, por parejas, en los huecos entre nidos (±11,25°).
	for s = 0, 3 do
		addTree(math.rad(90 * s - 11.25), ArenaLayout.OuterRadius, range(rng, 6, 7), { levels[1], levels[2] }, true)
		addTree(math.rad(90 * s + 11.25), ArenaLayout.OuterRadius, range(rng, 6, 7), { levels[1], levels[2], levels[3] }, false)
	end
	-- Cabañas (escondites) en la plataforma media de los árboles grandes.
	for s = 1, 4 do
		trees[s].Hut = levels[2]
	end

	local links: { Link } = {}
	local function link(a: number, b: number, level: number, kind: LinkKind)
		table.insert(links, { A = a, B = b, Level = level, Kind = kind })
	end
	for s = 0, 3 do
		local inner, minus, plus = s + 1, 5 + 2 * s, 6 + 2 * s
		local nextInner, nextMinus = (s + 1) % 4 + 1, 5 + 2 * ((s + 1) % 4)
		link(inner, minus, levels[1], "Bridge")
		link(inner, plus, levels[2], "Bridge")
		link(minus, plus, levels[2], "Beam") -- viga estrecha sin barandilla
		link(minus, plus, levels[1], if s % 2 == 0 then "Stones" else "Beam")
		link(inner, nextInner, levels[3], "Stones") -- atajo alto y arriesgado entre los grandes
		if s % 2 == 0 then
			link(plus, nextMinus, levels[1], "Stones")
		end
	end

	-- Rampas: el inicio que menos choca con los puentes de su árbol.
	for _, tree in trees do
		if tree.Ramp then
			local own = {}
			for _, l in links do
				if l.A == tree.Index or l.B == tree.Index then
					local other = trees[if l.A == tree.Index then l.B else l.A]
					table.insert(own, { Angle = angleTo(tree, other), Level = l.Level })
				end
			end
			tree.RampStart = pickRampStart(tree, own)
		end
	end

	local rides: { Ride } = {}
	for s = 0, 3 do
		local inner = trees[s + 1]
		local target = trees[5 + 2 * ((s + 1) % 4)] -- el árbol exterior del siguiente sector
		local angle = angleTo(inner, target)
		local from = ArenaLayout.deckHalf(inner) + 1
		local to = ArenaLayout.deckHalf(target) - 2
		-- Tirolina: de lo más alto de un árbol grande a la plataforma baja de otro.
		local zipline: Ride = {
			Kind = "Zipline",
			From = { X = inner.X + math.cos(angle) * from, Y = levels[3] + 7, Z = inner.Z + math.sin(angle) * from },
			To = { X = target.X - math.cos(angle) * to, Y = levels[1] + 2.5, Z = target.Z - math.sin(angle) * to },
		}
		table.insert(rides, zipline)
		-- Tobogán: de la plataforma baja de un árbol exterior al suelo, hacia el claro.
		local outer = trees[6 + 2 * s]
		local down = math.atan2(-outer.Z, -outer.X) + math.rad(if s % 2 == 0 then 35 else -35)
		local start = ArenaLayout.deckHalf(outer) + 0.5
		local length = levels[1] / math.tan(math.rad(32))
		local slide: Ride = {
			Kind = "Slide",
			From = { X = outer.X + math.cos(down) * start, Y = levels[1] + 0.5, Z = outer.Z + math.sin(down) * start },
			To = { X = outer.X + math.cos(down) * (start + length), Y = 0.5, Z = outer.Z + math.sin(down) * (start + length) },
		}
		table.insert(rides, slide)
	end

	-- Setas trampolín al pie de cada árbol (lanzan hasta la primera plataforma).
	local trampolines: { Trampoline } = {}
	for _, tree in trees do
		local angle = math.atan2(-tree.Z, -tree.X) + range(rng, -0.5, 0.5)
		local d = ArenaLayout.deckHalf(tree) + 4
		table.insert(trampolines, { X = tree.X + math.cos(angle) * d, Y = 0, Z = tree.Z + math.sin(angle) * d, Power = Config.Arena.TrampolinePower })
	end

	local function nearTree(x: number, z: number, margin: number): boolean
		for _, tree in trees do
			local dx, dz = x - tree.X, z - tree.Z
			if math.sqrt(dx * dx + dz * dz) < ArenaLayout.rampRadius(tree) + margin then
				return true
			end
		end
		return false
	end

	-- Bloques flotantes sueltos (no hace falta que tengan sentido).
	local blocks: { Block } = {}
	local tries = 0
	while #blocks < 22 and tries < 400 do
		tries += 1
		local p = MapLayout.randomInRing(rng, MapLayout.ClearingRadius + 12, MapLayout.NestRadius - 22)
		if not nearTree(p.X, p.Z, 4) then
			table.insert(blocks, { X = p.X, Y = range(rng, 9, 58), Z = p.Z, Size = range(rng, 4, 8) })
		end
	end

	-- Arbustos (escondites en el suelo) y troncos huecos (túneles).
	local bushes: { Vec } = {}
	tries = 0
	while #bushes < 36 and tries < 400 do
		tries += 1
		local p = MapLayout.randomInRing(rng, MapLayout.ClearingRadius + 6, MapLayout.NestRadius - 18)
		if not nearTree(p.X, p.Z, 2) then
			table.insert(bushes, { X = p.X, Y = 0, Z = p.Z })
		end
	end
	local logs: { Log } = {}
	tries = 0
	while #logs < 6 and tries < 200 do
		tries += 1
		local p = MapLayout.randomInRing(rng, 38, 95)
		if not nearTree(p.X, p.Z, 10) then
			table.insert(logs, { X = p.X, Z = p.Z, Angle = range(rng, 0, math.pi), Length = range(rng, 14, 20) })
		end
	end

	return { Trees = trees, Links = links, Rides = rides, Trampolines = trampolines, Blocks = blocks, Bushes = bushes, Logs = logs }
end

local cached: Arena? = nil

function ArenaLayout.get(): Arena
	if not cached then
		cached = build()
	end
	return cached :: Arena
end

-- Puntos sobre las plataformas (para poner brasas en lo alto): el centro de cada lado.
function ArenaLayout.deckSpots(): { Vec }
	local spots: { Vec } = {}
	for _, tree in ArenaLayout.get().Trees do
		local mid = tree.Radius + ArenaLayout.DeckWidth / 2
		for _, level in tree.Decks do
			for k = 0, 3 do
				local angle = k * math.pi / 2
				table.insert(spots, { X = tree.X + math.cos(angle) * mid, Y = level, Z = tree.Z + math.sin(angle) * mid })
			end
		end
	end
	return spots
end

-- Piedras de un camino de piedras: separadas para tener que saltar, subiendo y bajando un poco.
function ArenaLayout.stonePoints(arena: Arena, link: Link): { Vec }
	local a, b = ArenaLayout.linkEnds(arena, link)
	local dx, dz = b.X - a.X, b.Z - a.Z
	local length = math.sqrt(dx * dx + dz * dz)
	local count = math.max(2, math.ceil(length / 7))
	local px, pz = -dz / length, dx / length -- perpendicular: zigzag sin alargar los saltos
	local points: { Vec } = {}
	for i = 1, count - 1 do
		local t = i / count
		local wobble = math.sin(i * 1.3 + link.A) * 1.6 -- sube y baja sin pasar de lo que se salta
		local side = math.cos(i * 2.3) * 1.5
		table.insert(points, { X = a.X + dx * t + px * side, Y = link.Level + wobble, Z = a.Z + dz * t + pz * side })
	end
	return points
end

return ArenaLayout
