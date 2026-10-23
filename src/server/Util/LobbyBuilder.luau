--!strict
-- Construye el lobby (GDD v3): una plaza con el portal de partidas (pisar el círculo te mete
-- en la cola), el cartel del ranking, la estatua del Huevo Comunitario y los nidos alrededor,
-- unidos a la plaza por caminos. Origin es el centro de la plaza.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local NestBuilder = require(script.Parent.NestBuilder)

local LobbyBuilder = {}

export type Lobby = {
	Origin: Vector3,
	Folder: Folder,
	Nests: { NestBuilder.Nest },
	QueuePad: BasePart, -- pisarlo te apunta a la cola
	QueueLabel: TextLabel, -- texto sobre el portal
	BoardCFrame: CFrame, -- dónde va el cartel del ranking
	CommunityLabel: TextLabel,
	Spawn: SpawnLocation,
}

local PLAZA_RADIUS = 46

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

local function disc(center: Vector3, height: number, diameter: number, props: { [string]: any }, parent: Instance): Part
	local p = block({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
	}, parent)
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function billboard(parent: BasePart, size: UDim2, offset: Vector3, color: Color3): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffsetWorldSpace = offset
	gui.MaxDistance = 250
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = ""
	label.Parent = gui
	return label
end

function LobbyBuilder.build(parent: Instance): Lobby
	local origin = Vector3.new(Config.Lobby.OriginX, 0, Config.Lobby.OriginZ)
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = parent

	local radius = Config.Lobby.NestRadius + Config.Lobby.NestSize
	disc(origin + Vector3.new(0, -2, 0), 4, radius * 2 + 30, { Name = "Ground", Color = Color3.fromRGB(96, 150, 72), Material = Enum.Material.Grass }, folder)
	-- Muro invisible alrededor.
	local segments = 40
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local pos = origin + Vector3.new(math.cos(angle) * (radius + 12), 20, math.sin(angle) * (radius + 12))
		block({
			Name = "Boundary",
			Size = Vector3.new(4, 44, (2 * math.pi * (radius + 12)) / segments + 2),
			CFrame = CFrame.lookAt(pos, origin + Vector3.new(0, 20, 0)) * CFrame.Angles(0, math.rad(90), 0),
			Transparency = 1,
			CanQuery = false,
		}, folder)
	end

	-- Plaza y fuente-portal.
	disc(origin + Vector3.new(0, 0.1, 0), 1, PLAZA_RADIUS * 2, { Name = "Plaza", Color = Color3.fromRGB(190, 175, 150), Material = Enum.Material.Cobblestone }, folder)
	disc(origin + Vector3.new(0, 0.2, 0), 1, PLAZA_RADIUS * 2 - 6, { Name = "PlazaInner", Color = Color3.fromRGB(215, 200, 175), Material = Enum.Material.Pavement }, folder)
	local pad = disc(origin + Vector3.new(0, 0.75, 0), 0.5, 22, { Name = "QueuePad", Color = Color3.fromRGB(255, 150, 60), Material = Enum.Material.Neon, Transparency = 0.25 }, folder)
	disc(origin + Vector3.new(0, 0.7, 0), 0.4, 24, { Name = "QueuePadRim", Color = Color3.fromRGB(120, 80, 50), Material = Enum.Material.Wood }, folder)
	-- Arco de piedra del portal.
	local arcSegments = 14
	for k = 0, arcSegments do
		local a = math.pi * k / arcSegments
		local p = origin + Vector3.new(math.cos(a) * 8, 1 + math.sin(a) * 11, 0)
		block({
			Name = "PortalStone",
			Size = Vector3.new(2.4, 2.6, 2.4),
			CFrame = CFrame.new(p) * CFrame.Angles(0, 0, a),
			Color = Color3.fromRGB(150, 140, 130),
			Material = Enum.Material.Slate,
		}, folder)
	end
	local swirl = block({
		Name = "PortalSwirl",
		Size = Vector3.new(14, 20, 0.4),
		CFrame = CFrame.new(origin + Vector3.new(0, 7.5, 0)),
		Color = Color3.fromRGB(255, 120, 40),
		Material = Enum.Material.Neon,
		Transparency = 0.45,
		CanCollide = false,
	}, folder)
	local swirlMesh = Instance.new("SpecialMesh")
	swirlMesh.MeshType = Enum.MeshType.Sphere
	swirlMesh.Parent = swirl
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 90, 30))
	sparks.LightEmission = 1
	sparks.Rate = 20
	sparks.Lifetime = NumberRange.new(1, 2)
	sparks.Speed = NumberRange.new(2, 5)
	sparks.Size = NumberSequence.new(0.5, 0)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Parent = swirl
	local light = Instance.new("PointLight")
	light.Range = 30
	light.Color = Color3.fromRGB(255, 150, 70)
	light.Brightness = 2
	light.Parent = swirl
	local queueLabel = billboard(swirl, UDim2.fromOffset(360, 110), Vector3.new(0, 15, 0), Color3.fromRGB(255, 235, 200))
	queueLabel.Text = "⚔️ ¡A jugar!\nPisa el círculo"

	-- Cartel del ranking en el borde de la plaza (mirando al portal).
	local boardPosition = origin + Vector3.new(0, 11, PLAZA_RADIUS - 6)
	local boardCFrame = CFrame.lookAt(boardPosition, origin + Vector3.new(0, 11, 0))

	-- Estatua del Huevo Comunitario enfrente.
	local statueBase = origin + Vector3.new(0, 0, -(PLAZA_RADIUS - 8))
	disc(statueBase + Vector3.new(0, 1.5, 0), 3, 12, { Name = "StatueBase", Color = Color3.fromRGB(170, 160, 150), Material = Enum.Material.Marble }, folder)
	local statue = block({ Name = "CommunityEgg", Size = Vector3.new(7, 9, 7), CFrame = CFrame.new(statueBase + Vector3.new(0, 7.5, 0)), Color = Color3.fromRGB(255, 205, 90), Material = Enum.Material.Metal, Reflectance = 0.2 }, folder)
	local statueMesh = Instance.new("SpecialMesh")
	statueMesh.MeshType = Enum.MeshType.Sphere
	statueMesh.Parent = statue
	local communityLabel = billboard(statue, UDim2.fromOffset(300, 70), Vector3.new(0, 7, 0), Color3.fromRGB(255, 230, 150))
	communityLabel.Text = "🌍 Huevo Comunitario"

	-- Bancos y farolas por la plaza.
	for k = 0, 7 do
		local angle = (k + 0.5) * math.pi / 4
		local p = origin + Vector3.new(math.cos(angle) * (PLAZA_RADIUS - 4), 0, math.sin(angle) * (PLAZA_RADIUS - 4))
		block({ Name = "LampPost", Size = Vector3.new(0.6, 9, 0.6), CFrame = CFrame.new(p + Vector3.new(0, 4.5, 0)), Color = Color3.fromRGB(55, 50, 50), Material = Enum.Material.Metal }, folder)
		local lamp = block({ Name = "Lamp", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), CFrame = CFrame.new(p + Vector3.new(0, 9.5, 0)), Color = Color3.fromRGB(255, 215, 140), Material = Enum.Material.Neon, CanCollide = false }, folder)
		local l = Instance.new("PointLight")
		l.Range = 18
		l.Color = lamp.Color
		l.Parent = lamp
	end

	-- Nidos alrededor y caminos hasta la plaza.
	local nestsFolder = Instance.new("Folder")
	nestsFolder.Name = "Nests"
	nestsFolder.Parent = folder
	local nests: { NestBuilder.Nest } = {}
	local count = Config.Lobby.NestCount
	for index = 1, count do
		local angle = (index / count) * math.pi * 2
		local center = origin + Vector3.new(math.cos(angle) * Config.Lobby.NestRadius, 0, math.sin(angle) * Config.Lobby.NestRadius)
		local nestOrigin = CFrame.lookAt(center, origin)
		table.insert(nests, NestBuilder.lobby(index, nestOrigin, nestsFolder))
		-- Camino de la plaza a la entrada.
		local from = origin + Vector3.new(math.cos(angle) * (PLAZA_RADIUS - 1), 0, math.sin(angle) * (PLAZA_RADIUS - 1))
		local to = center - (center - origin).Unit * (Config.Lobby.NestSize / 2 + 1)
		local length = (to - from).Magnitude
		block({
			Name = "Path",
			Size = Vector3.new(6, 0.4, length),
			CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0.2, -length / 2),
			Color = Color3.fromRGB(200, 185, 155),
			Material = Enum.Material.Pavement,
			CanCollide = false,
		}, folder)
		-- Un arbolito entre cada dos nidos.
		local between = angle + math.pi / count
		local treePos = origin + Vector3.new(math.cos(between) * (Config.Lobby.NestRadius + 4), 0, math.sin(between) * (Config.Lobby.NestRadius + 4))
		block({ Name = "Trunk", Size = Vector3.new(1.6, 9, 1.6), CFrame = CFrame.new(treePos + Vector3.new(0, 4.5, 0)), Color = Color3.fromRGB(95, 65, 45), Material = Enum.Material.Wood }, folder)
		block({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(8, 7, 8),
			CFrame = CFrame.new(treePos + Vector3.new(0, 10.5, 0)),
			Color = if index % 2 == 0 then Color3.fromRGB(220, 120, 60) else Color3.fromRGB(240, 170, 80),
			Material = Enum.Material.Grass,
			CanCollide = false,
		}, folder)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(origin + Vector3.new(0, 0.8, 22))
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder

	return {
		Origin = origin,
		Folder = folder,
		Nests = nests,
		QueuePad = pad,
		QueueLabel = queueLabel,
		BoardCFrame = boardCFrame,
		CommunityLabel = communityLabel,
		Spawn = spawn,
	}
end

return LobbyBuilder
