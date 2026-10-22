--!strict
-- Genera el mapa de lanzamiento "Bosque de Brasas" en gris (GDD 8): mapa circular de ~300 studs,
-- huevo en un claro central y 16 nidos en el borde. Sustituible por un mapa hecho a mano
-- que mantenga los mismos nombres (Map/Egg, Map/Nests/Nest_N con Floor, Door, Spawn, Sign).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

export type Nest = {
	Index: number,
	Origin: CFrame, -- centro del suelo; -Z mira al huevo
	Size: number,
	Model: Model,
	Floor: BasePart,
	Door: BasePart,
	Spawn: SpawnLocation,
	Sign: TextLabel,
}

local MapService = {}

MapService.Radius = 150
MapService.NestRadius = 128
MapService.NestSize = 26
MapService.EggCenter = Vector3.new(0, 0, 0)
MapService.Nests = {} :: { Nest }
MapService.Zones = {} :: { [string]: Vector3 }
-- Se rellenan en init().
MapService.Egg = (nil :: any) :: Part
MapService.Folder = (nil :: any) :: Folder
MapService.SourcesFolder = (nil :: any) :: Folder

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

function MapService.randomGroundPoint(minRadius: number, maxRadius: number): Vector3
	local angle = rng:NextNumber(0, math.pi * 2)
	-- raíz cuadrada para repartir uniformemente por área
	local r = math.sqrt(rng:NextNumber(minRadius * minRadius, maxRadius * maxRadius))
	return polar(angle, r, 0)
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
		Size = Vector3.new(1, 50, 50),
		CFrame = CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(120, 100, 70),
		Material = Enum.Material.Ground,
	}, mapFolder)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(0, 0.6, 32)
	spawn.Transparency = 0.6
	spawn.Neutral = true
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

local function buildNest(index: number): Nest
	local angle = (index / Config.Nest.Count) * math.pi * 2
	local center = polar(angle, MapService.NestRadius, 0)
	local origin = CFrame.lookAt(center, Vector3.new(0, 0, 0))
	local size = MapService.NestSize
	local half = size / 2
	local wallHeight = 9
	local opening = 9

	local model = Instance.new("Model")
	model.Name = "Nest_" .. index
	model.Parent = mapFolder:FindFirstChild("Nests")

	local floor = block({
		Name = "Floor",
		Size = Vector3.new(size, 1, size),
		CFrame = origin * CFrame.new(0, 0.5, 0),
		Color = Color3.fromRGB(150, 120, 85),
		Material = Enum.Material.WoodPlanks,
	}, model)

	local wallColor = Color3.fromRGB(110, 85, 60)
	local function wall(name: string, cf: CFrame, sz: Vector3)
		block({ Name = name, CFrame = origin * cf, Size = sz, Color = wallColor, Material = Enum.Material.Wood }, model)
	end
	wall("BackWall", CFrame.new(0, wallHeight / 2 + 1, half), Vector3.new(size, wallHeight, 1))
	wall("LeftWall", CFrame.new(-half, wallHeight / 2 + 1, 0), Vector3.new(1, wallHeight, size))
	wall("RightWall", CFrame.new(half, wallHeight / 2 + 1, 0), Vector3.new(1, wallHeight, size))
	local side = (size - opening) / 2
	wall("FrontLeft", CFrame.new(-(opening / 2 + side / 2), wallHeight / 2 + 1, -half), Vector3.new(side, wallHeight, 1))
	wall("FrontRight", CFrame.new(opening / 2 + side / 2, wallHeight / 2 + 1, -half), Vector3.new(side, wallHeight, 1))

	local door = block({
		Name = "Door",
		CFrame = origin * CFrame.new(0, wallHeight / 2 + 1, -half),
		Size = Vector3.new(opening, wallHeight, 1),
		Color = Color3.fromRGB(255, 200, 80),
		Material = Enum.Material.ForceField,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	}, model)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = origin * CFrame.new(0, 1.1, half - 5)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Enabled = false -- solo sirve como RespawnLocation del dueño
	spawn.Duration = 0
	spawn.Parent = model

	local signPart = block({
		Name = "SignPost",
		CFrame = origin * CFrame.new(0, wallHeight + 4, -half),
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	}, model)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 60)
	billboard.MaxDistance = 140
	billboard.Parent = signPart
	local sign = Instance.new("TextLabel")
	sign.Size = UDim2.fromScale(1, 1)
	sign.BackgroundTransparency = 1
	sign.Font = Enum.Font.FredokaOne
	sign.TextScaled = true
	sign.TextColor3 = Color3.new(1, 1, 1)
	sign.TextStrokeTransparency = 0.2
	sign.Text = "Nido libre"
	sign.Parent = billboard

	return {
		Index = index,
		Origin = origin,
		Size = size,
		Model = model,
		Floor = floor,
		Door = door,
		Spawn = spawn,
		Sign = sign,
	}
end

local function buildZones()
	-- Ángulos de las zonas del GDD; los nidos quedan en el borde, las zonas en el anillo medio.
	MapService.Zones = {
		Swamp = polar(math.rad(45), 82),
		CrystalCave = polar(math.rad(135), 82),
		Ruins = polar(math.rad(225), 82),
		Bridge = polar(math.rad(315), 82),
	}

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

	-- Árboles repartidos (obstáculos y cobertura en la persecución).
	for _ = 1, 70 do
		local pos = MapService.randomGroundPoint(32, MapService.NestRadius - 20)
		local tooClose = false
		for _, zone in MapService.Zones do
			if (zone - pos).Magnitude < 24 then
				tooClose = true
				break
			end
		end
		if not tooClose then
			local height = rng:NextNumber(10, 20)
			block({
				Name = "Trunk",
				Size = Vector3.new(2.5, height, 2.5),
				CFrame = CFrame.new(pos + Vector3.new(0, height / 2, 0)),
				Color = Color3.fromRGB(90, 60, 40),
				Material = Enum.Material.Wood,
			}, mapFolder)
			block({
				Name = "Leaves",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(10, 10, 10),
				CFrame = CFrame.new(pos + Vector3.new(0, height + 3, 0)),
				Color = Color3.fromRGB(200, 90, 40), -- bosque de brasas: hojas rojizas
				Material = Enum.Material.Grass,
				CanCollide = false,
			}, mapFolder)
		end
	end
end

function MapService.init()
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
		table.insert(MapService.Nests, buildNest(index))
	end
	buildZones()

	MapService.Folder = mapFolder
	MapService.SourcesFolder = sources
end

function MapService.start() end

return MapService
