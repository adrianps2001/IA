--!strict
-- Construye el lobby (GDD v3): una plaza con el portal de partidas (pisar el círculo te mete
-- en la cola), el cartel del ranking, la estatua del Huevo Comunitario y los nidos alrededor,
-- unidos a la plaza por caminos. Origin es el centro de la plaza.

local Lighting = game:GetService("Lighting")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local MapLayout = require(Shared.MapLayout)
local Place = require(Shared.Place)

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

-- ------------------------------------------------------------------ decoración (v3.1)
-- Todo por código, sin construir a mano: colinas y un estanque con el Terrain de Roblox fuera
-- del muro, árboles variados, flores y farolillos en los caminos y un ambiente cálido. Nada de
-- esto colisiona dentro de la zona jugable salvo los troncos. Siempre sale igual (semilla fija).

local LEAVES = {
	{ Color3.fromRGB(86, 160, 70), Color3.fromRGB(110, 180, 80), Color3.fromRGB(70, 140, 60) }, -- verde
	{ Color3.fromRGB(235, 150, 60), Color3.fromRGB(245, 185, 85), Color3.fromRGB(215, 110, 50) }, -- otoño
	{ Color3.fromRGB(255, 180, 205), Color3.fromRGB(255, 205, 225), Color3.fromRGB(240, 150, 185) }, -- cerezo
}
local FLOWERS = {
	Color3.fromRGB(255, 120, 170),
	Color3.fromRGB(255, 220, 90),
	Color3.fromRGB(160, 120, 255),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 140, 80),
}

local function tree(position: Vector3, scale: number, palette: number, rng: Random, parent: Instance)
	local height = (8 + rng:NextNumber() * 4) * scale
	local trunk = block({
		Name = "TreeTrunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, 1.6 * scale, 1.6 * scale),
		CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, rng:NextNumber() * math.pi, math.rad(90 + rng:NextNumber(-4, 4))),
		Color = Color3.fromRGB(110, 75, 50),
		Material = Enum.Material.Wood,
	}, parent)
	trunk.CanQuery = false
	local colors = LEAVES[palette]
	for k = 1, 4 do
		local size = (5 + rng:NextNumber() * 3) * scale
		local offset = if k == 1 then Vector3.zero else Vector3.new(rng:NextNumber(-2.5, 2.5), rng:NextNumber(-1.5, 1), rng:NextNumber(-2.5, 2.5)) * scale
		block({
			Name = "TreeLeaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size * 0.85, size),
			CFrame = CFrame.new(position + Vector3.new(0, height + 1 * scale, 0) + offset),
			Color = colors[(k - 1) % #colors + 1],
			Material = Enum.Material.Grass,
			CanCollide = false,
			CanQuery = false,
		}, parent)
	end
end

local function pine(position: Vector3, scale: number, rng: Random, parent: Instance)
	block({ Name = "PineTrunk", Size = Vector3.new(1.2, 4, 1.2) * scale, CFrame = CFrame.new(position + Vector3.new(0, 2 * scale, 0)), Color = Color3.fromRGB(95, 65, 45), Material = Enum.Material.Wood, CanQuery = false }, parent)
	local green = Color3.fromRGB(50 + rng:NextInteger(0, 20), 110 + rng:NextInteger(0, 25), 65)
	for k = 0, 3 do
		local w = (7 - k * 1.6) * scale
		block({
			Name = "PineLeaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(w, 3.4 * scale, w),
			CFrame = CFrame.new(position + Vector3.new(0, (4 + k * 2.6) * scale, 0)),
			Color = green,
			Material = Enum.Material.Grass,
			CanCollide = false,
			CanQuery = false,
		}, parent)
	end
end

local function flower(position: Vector3, rng: Random, parent: Instance)
	block({ Name = "FlowerStem", Size = Vector3.new(0.2, 0.9, 0.2), CFrame = CFrame.new(position + Vector3.new(0, 0.45, 0)), Color = Color3.fromRGB(70, 140, 60), CanCollide = false, CanQuery = false }, parent)
	block({
		Name = "Flower",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.8, 0.6, 0.8),
		CFrame = CFrame.new(position + Vector3.new(0, 1, 0)),
		Color = FLOWERS[rng:NextInteger(1, #FLOWERS)],
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
	}, parent)
end

local function bush(position: Vector3, rng: Random, parent: Instance)
	local size = 2.4 + rng:NextNumber() * 1.4
	block({
		Name = "Bush",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size * 1.3, size, size * 1.3),
		CFrame = CFrame.new(position + Vector3.new(0, size * 0.35, 0)),
		Color = Color3.fromRGB(70 + rng:NextInteger(0, 25), 135 + rng:NextInteger(0, 25), 60),
		Material = Enum.Material.Grass,
		CanCollide = false,
		CanQuery = false,
	}, parent)
end

local function lantern(position: Vector3, parent: Instance)
	block({ Name = "LanternPost", Size = Vector3.new(0.4, 4, 0.4), CFrame = CFrame.new(position + Vector3.new(0, 2, 0)), Color = Color3.fromRGB(80, 60, 45), Material = Enum.Material.Wood, CanQuery = false }, parent)
	local lamp = block({ Name = "Lantern", Size = Vector3.new(1, 1.2, 1), CFrame = CFrame.new(position + Vector3.new(0, 4.4, 0)), Color = Color3.fromRGB(255, 200, 120), Material = Enum.Material.Neon, CanCollide = false, CanQuery = false }, parent)
	local light = Instance.new("PointLight")
	light.Range = 12
	light.Brightness = 0.8
	light.Color = lamp.Color
	light.Parent = lamp
end

-- Colinas y estanque fuera del muro: el lobby queda en un valle en vez de flotar en la nada.
local function terrain(origin: Vector3, radius: number)
	local t = workspace.Terrain
	local rng = Random.new(Config.Arena.Seed + 11)
	t:FillCylinder(CFrame.new(origin + Vector3.new(0, -6, 0)), 8, radius + 80, Enum.Material.Grass)
	local hills = 36
	for k = 1, hills do
		local angle = (k / hills) * math.pi * 2 + rng:NextNumber(-0.05, 0.05)
		local r = radius + 40 + rng:NextNumber(0, 30)
		local size = 26 + rng:NextNumber() * 26
		local center = origin + Vector3.new(math.cos(angle) * r, -size * 0.45, math.sin(angle) * r)
		t:FillBall(center, size, if k % 7 == 0 then Enum.Material.Rock else Enum.Material.Grass)
	end
	-- Un estanque detrás de los nidos, que se ve desde las gradas.
	local pond = origin + Vector3.new(radius + 26, 0, 0)
	t:FillCylinder(CFrame.new(pond + Vector3.new(0, -2, 0)), 4, 16, Enum.Material.Water)
	t:FillCylinder(CFrame.new(pond + Vector3.new(0, -1, 0)), 2, 19, Enum.Material.Sand)
	t:FillCylinder(CFrame.new(pond + Vector3.new(0, -1, 0)), 2.2, 16, Enum.Material.Water)
end

-- Ambiente del lobby (solo en el lugar del lobby: en el modo combinado la luz la lleva la ronda).
local function atmosphere()
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.2
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 140, 130)
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmo.Density = 0.28
	atmo.Offset = 0.15
	atmo.Color = Color3.fromRGB(230, 215, 190)
	atmo.Decay = Color3.fromRGB(150, 170, 200)
	atmo.Glare = 0.2
	atmo.Haze = 1.4
	atmo.Parent = Lighting
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.4
	bloom.Size = 20
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
end

local function decorate(origin: Vector3, nestRadius: number, radius: number, parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Decoration"
	folder.Parent = parent
	local rng = Random.new(Config.Arena.Seed + 7)
	local count = Config.Lobby.NestCount
	local nestOuter = nestRadius + Config.Lobby.NestSize / 2 + 3
	-- Bosque entre los nidos y el muro: árboles de hoja y pinos alternados.
	local forest = math.floor(2 * math.pi * (nestOuter + 12) / 9)
	for k = 1, forest do
		local angle = (k / forest) * math.pi * 2 + rng:NextNumber(-0.03, 0.03)
		local r = nestOuter + 9 + rng:NextNumber(0, math.max(radius + 8 - nestOuter - 9, 1))
		local pos = origin + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		if k % 3 == 0 then
			pine(pos, 1 + rng:NextNumber() * 0.5, rng, folder)
		else
			tree(pos, 1 + rng:NextNumber() * 0.4, if k % 5 == 0 then 3 elseif k % 2 == 0 then 2 else 1, rng, folder)
		end
		if k % 2 == 0 then
			bush(pos + Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4)), rng, folder)
		end
	end
	for index = 1, count do
		local angle = (index / count) * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local side = Vector3.new(-dir.Z, 0, dir.X)
		-- Flores y farolillos a los lados del camino.
		local from, to = PLAZA_RADIUS + 3, nestRadius - Config.Lobby.NestSize / 2 - 4
		local d = from
		local step = 0
		while d < to do
			for _, s in { -1, 1 } do
				local p = origin + dir * d + side * s * (4.2 + rng:NextNumber() * 0.8)
				if step % 6 == 3 then
					lantern(p, folder)
				elseif rng:NextNumber() < 0.6 then
					flower(p, rng, folder)
				end
			end
			if step % 4 == 1 then
				bush(origin + dir * d + side * (if step % 8 == 1 then 7 else -7), rng, folder)
			end
			d += 4.5
			step += 1
		end
	end
	-- Entre camino y camino: un pequeño rincón en cada cuña del césped (árboles, prado de flores,
	-- rocas o un banco con farolillo), para que el paseo de la plaza a los nidos no esté vacío.
	local inner = PLAZA_RADIUS + 10
	local outer = nestRadius - Config.Lobby.NestSize / 2 - 12
	for index = 1, count do
		local angle = (index + 0.5) / count * math.pi * 2
		for k, f in { 0.3, 0.72 } do
			local r = inner + (outer - inner) * f
			local c = origin + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
			local kind = (index + k) % 4
			if kind == 0 then
				tree(c, 1.1, if index % 3 == 0 then 3 else 1, rng, folder)
				bush(c + Vector3.new(3, 0, 2), rng, folder)
			elseif kind == 1 then
				for _ = 1, 9 do
					local a2, d2 = rng:NextNumber() * math.pi * 2, rng:NextNumber() * 4.5
					flower(c + Vector3.new(math.cos(a2) * d2, 0, math.sin(a2) * d2), rng, folder)
				end
			elseif kind == 2 then
				for j = 1, 3 do
					local size = 1.5 + rng:NextNumber() * 2
					block({
						Name = "Rock",
						Size = Vector3.new(size * 1.3, size, size),
						CFrame = CFrame.new(c + Vector3.new(j * 1.8 - 3.6, size / 2 - 0.3, rng:NextNumber(-1.5, 1.5))) * CFrame.Angles(0, rng:NextNumber() * math.pi, 0),
						Color = Color3.fromRGB(140, 135, 128),
						Material = Enum.Material.Slate,
						CanQuery = false,
					}, folder)
				end
				bush(c + Vector3.new(0, 0, 3), rng, folder)
			else
				local facing = CFrame.lookAt(c, origin)
				block({ Name = "BenchSeat", Size = Vector3.new(5, 0.4, 1.4), CFrame = facing * CFrame.new(0, 1.2, 0), Color = Color3.fromRGB(150, 105, 70), Material = Enum.Material.WoodPlanks }, folder)
				block({ Name = "BenchBack", Size = Vector3.new(5, 1.2, 0.3), CFrame = facing * CFrame.new(0, 2, 0.6), Color = Color3.fromRGB(150, 105, 70), Material = Enum.Material.WoodPlanks }, folder)
				for _, x in { -2, 2 } do
					block({ Name = "BenchLeg", Size = Vector3.new(0.3, 1.1, 1.2), CFrame = facing * CFrame.new(x, 0.55, 0), Color = Color3.fromRGB(70, 60, 55), Material = Enum.Material.Metal }, folder)
				end
				lantern(c + (facing.RightVector * 3.6), folder)
			end
		end
	end
	-- Parterres de flores alrededor de la plaza, entre camino y camino.
	for index = 1, count do
		local angle = (index + 0.5) / count * math.pi * 2
		for k = 0, 2 do
			local r = PLAZA_RADIUS + 2 + k * 1.4
			flower(origin + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r), rng, folder)
		end
	end
	terrain(origin, radius)
	if Place.kind() == "Lobby" then
		atmosphere()
	end
end

function LobbyBuilder.build(parent: Instance): Lobby
	local origin = Vector3.new(Config.Lobby.OriginX, 0, Config.Lobby.OriginZ)
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = parent

	local nestRadius = MapLayout.lobbyNestRadius()
	local radius = nestRadius + Config.Lobby.NestSize
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
		local center = origin + Vector3.new(math.cos(angle) * nestRadius, 0, math.sin(angle) * nestRadius)
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
	end

	decorate(origin, nestRadius, radius, folder)

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
