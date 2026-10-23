--!strict
-- Genera los mapas en gris (GDD 8 y v3):
-- * Arena "Bosque de Brasas": mapa circular de ~300 studs, huevo en un claro central, zonas,
--   el parkour de árboles gigantes (ArenaBuilder) y 16 campamentos de salida en el borde.
-- * Lobby: plaza con el portal de partidas y los nidos bonitos de todos (LobbyBuilder).
-- Qué se construye depende del lugar (Place): el lobby, la arena o los dos (modo combinado).
-- Sustituible por mapas hechos a mano que mantengan los mismos nombres.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local MapLayout = require(Shared.MapLayout)
local Place = require(Shared.Place)
local RoundState = require(Shared.RoundState)

local ArenaBuilder = require(script.Parent.Parent.Util.ArenaBuilder)
local LobbyBuilder = require(script.Parent.Parent.Util.LobbyBuilder)
local NestBuilder = require(script.Parent.Parent.Util.NestBuilder)

export type Nest = NestBuilder.Nest

local MapService = {}

MapService.Radius = MapLayout.Radius
MapService.NestRadius = MapLayout.NestRadius
MapService.EggCenter = Vector3.new(0, 0, 0)
MapService.Nests = {} :: { Nest } -- campamentos de la arena
MapService.LobbyNests = {} :: { Nest } -- nidos del lobby
MapService.Zones = {} :: { [string]: Vector3 }
-- Se rellenan en init() (la arena solo si este lugar la tiene).
MapService.Egg = (nil :: any) :: Part
MapService.Folder = (nil :: any) :: Folder
MapService.SourcesFolder = (nil :: any) :: Folder
MapService.Lobby = nil :: LobbyBuilder.Lobby?

local rng = Random.new()
local mapFolder: Folder

local function block(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function polar(angle: number, radius: number, y: number?): Vector3
	return Vector3.new(math.cos(angle) * radius, y or 0, math.sin(angle) * radius)
end

local function toVector(point: MapLayout.Point): Vector3
	return Vector3.new(point.X, 0, point.Z)
end

local function rngFunction(): number
	return rng:NextNumber()
end

-- Punto aleatorio repartido uniformemente por la superficie del anillo (ver MapLayout).
function MapService.randomGroundPoint(minRadius: number, maxRadius: number): Vector3
	return toVector(MapLayout.randomInRing(rngFunction, minRadius, maxRadius))
end

-- Obstáculos (troncos, rocas, géiseres) como círculos en el plano: { centro, radio }.
local obstacles: { { Position: Vector3, Radius: number } } = {}

function MapService.addObstacle(position: Vector3, radius: number)
	table.insert(obstacles, { Position = Vector3.new(position.X, 0, position.Z), Radius = radius })
end

-- true si en ese punto no hay ningún obstáculo a menos de margin studs.
function MapService.isClear(point: Vector3, margin: number): boolean
	local flat = Vector3.new(point.X, 0, point.Z)
	for _, obstacle in obstacles do
		if (obstacle.Position - flat).Magnitude < obstacle.Radius + margin then
			return false
		end
	end
	return true
end

function MapService.randomPointNear(center: Vector3, spread: number): Vector3
	local offset = Vector3.new(rng:NextNumber(-spread, spread), 0, rng:NextNumber(-spread, spread))
	return Vector3.new(center.X + offset.X, 0, center.Z + offset.Z)
end

local function buildGround()
	block({
		Name = "Ground",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, MapService.Radius * 2 + 20, MapService.Radius * 2 + 20),
		CFrame = CFrame.new(0, -2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(74, 92, 58),
		Material = Enum.Material.Grass,
	}, mapFolder)

	-- Muro invisible que delimita el mapa.
	local segments = 36
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local pos = polar(angle, MapService.Radius + 8, 20)
		block({
			Name = "Boundary",
			Size = Vector3.new(4, 44, (2 * math.pi * (MapService.Radius + 8)) / segments + 2),
			CFrame = CFrame.lookAt(pos, Vector3.new(0, 20, 0)) * CFrame.Angles(0, math.rad(90), 0),
			Transparency = 1,
			CanQuery = false,
		}, mapFolder)
	end

	-- Claro central.
	block({
		Name = "Clearing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, MapLayout.ClearingRadius * 2, MapLayout.ClearingRadius * 2),
		CFrame = CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(120, 100, 70),
		Material = Enum.Material.Ground,
	}, mapFolder)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ArenaSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(0, 0.6, 32)
	spawn.Transparency = 0.6
	spawn.Neutral = true
	spawn.Enabled = not Place.hasLobby() -- en el modo combinado se aparece en el lobby
	spawn.Duration = 0
	spawn.Parent = mapFolder
end

local function buildEgg()
	block({
		Name = "EggPedestal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 22, 22),
		CFrame = CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(90, 70, 55),
		Material = Enum.Material.Rock,
	}, mapFolder)

	local egg = block({
		Name = "Egg",
		Size = Vector3.new(14, 18, 14),
		CFrame = CFrame.new(0, 12, 0),
		Color = Color3.fromRGB(255, 240, 210),
		Material = Enum.Material.SmoothPlastic,
	}, mapFolder)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = egg
	local light = Instance.new("PointLight")
	light.Range = 30
	light.Brightness = 1
	light.Color = Color3.fromRGB(255, 170, 80)
	light.Parent = egg

	MapService.Egg = egg
	MapService.EggCenter = egg.Position
end

local function buildZones()
	-- Ángulos de las zonas del GDD; los nidos quedan en el borde, las zonas en el anillo medio.
	for name in MapLayout.ZoneAngles do
		MapService.Zones[name] = toVector(MapLayout.zoneCenter(name))
	end

	block({
		Name = "Swamp",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 46, 46),
		CFrame = CFrame.new(MapService.Zones.Swamp + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(60, 90, 70),
		Material = Enum.Material.Mud,
	}, mapFolder)

	-- Cueva de cristales: rocas y cristales decorativos.
	for _ = 1, 10 do
		local pos = MapService.randomPointNear(MapService.Zones.CrystalCave, 18)
		MapService.addObstacle(pos, 1.5)
		block({
			Name = "Crystal",
			Size = Vector3.new(2, rng:NextNumber(4, 9), 2),
			CFrame = CFrame.new(pos + Vector3.new(0, 2, 0)) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)),
			Color = Color3.fromRGB(140, 220, 255),
			Material = Enum.Material.Glass,
			Transparency = 0.2,
		}, mapFolder)
	end

	-- Ruinas: columnas rotas.
	for i = 1, 8 do
		local pos = MapService.Zones.Ruins + polar(i * math.pi / 4, 16)
		MapService.addObstacle(pos, 2.2)
		block({
			Name = "Ruin",
			Size = Vector3.new(3, rng:NextNumber(3, 12), 3),
			CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)),
			Color = Color3.fromRGB(170, 165, 150),
			Material = Enum.Material.Cobblestone,
		}, mapFolder)
	end

	-- Puente colgante (atajo arriesgado): pasarela estrecha sin barandilla entre dos rocas.
	for _, offset in { -24, 24 } do
		MapService.addObstacle((CFrame.lookAt(MapService.Zones.Bridge, Vector3.zero) * CFrame.new(offset, 0, 0)).Position, 7)
		block({
			Name = "BridgeRock",
			Size = Vector3.new(14, 5, 10),
			CFrame = CFrame.lookAt(MapService.Zones.Bridge, Vector3.zero) * CFrame.new(offset, 2.5, 0),
			Color = Color3.fromRGB(100, 95, 90),
			Material = Enum.Material.Slate,
		}, mapFolder)
	end
	block({
		Name = "Bridge",
		Size = Vector3.new(34, 1, 4),
		CFrame = CFrame.lookAt(MapService.Zones.Bridge, Vector3.zero) * CFrame.new(0, 4.5, 0),
		Color = Color3.fromRGB(120, 90, 60),
		Material = Enum.Material.WoodPlanks,
	}, mapFolder)

	for _, geyser in MapLayout.geyserPositions() do
		MapService.addObstacle(toVector(geyser), 4.5)
	end
end

local function buildArena()
	local existing = workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end
	mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"
	mapFolder.Parent = workspace

	local nests = Instance.new("Folder")
	nests.Name = "Nests"
	nests.Parent = mapFolder

	local sources = Instance.new("Folder")
	sources.Name = "HeatSources"
	sources.Parent = mapFolder

	buildGround()
	buildEgg()
	for index = 1, Config.Nest.Count do
		local center = toVector(MapLayout.nestCenter(index))
		table.insert(MapService.Nests, NestBuilder.arena(index, CFrame.lookAt(center, Vector3.zero), nests))
	end
	buildZones()
	-- Parkour: árboles gigantes con plataformas, puentes y atajos (GDD v3).
	ArenaBuilder.build(mapFolder, MapService.addObstacle)

	MapService.Folder = mapFolder
	MapService.SourcesFolder = sources
end

local function buildLobby()
	local existing = workspace:FindFirstChild("Lobby")
	if existing then
		existing:Destroy()
	end
	local lobby = LobbyBuilder.build(workspace)
	MapService.Lobby = lobby
	MapService.LobbyNests = lobby.Nests
	-- Estatua del Huevo Comunitario: el progreso global.
	local function refresh()
		local progress = tonumber(RoundState.get("CommunityProgress")) or 0
		lobby.CommunityLabel.Text = if progress >= 1
			then "🌍 Huevo Comunitario\n¡lleno!"
			else string.format("🌍 Huevo Comunitario\n%d %%", math.floor(progress * 100))
	end
	RoundState.changed("CommunityProgress"):Connect(refresh)
	refresh()
end

function MapService.init()
	if Place.hasArena() then
		buildArena()
	end
	if Place.hasLobby() then
		buildLobby()
	end
end

function MapService.start() end

return MapService
