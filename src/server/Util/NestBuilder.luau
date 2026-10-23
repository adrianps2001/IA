--!strict
-- Construye los nidos (GDD v3). Hay dos tipos:
-- * Lobby: la parcela grande y bonita donde se lucen las criaturas en pedestales con su
--   placa, valla, farolillos, arco de entrada con cartel, cuenco con la incubadora y sitio
--   para la decoración comprada. Aquí se hace todo: tienda, mejoras, cría, intercambios.
-- * Arena: el campamento de salida en la partida. Plataforma redonda con tus 3 criaturas
--   favoritas a la vista (y saqueables en la Noche de Saqueo).
-- En los dos, Origin es el centro del suelo a ras de tierra y -Z mira al centro del mapa.
-- El suelo mide 1 de alto: lo que se pone encima va a Y = 1 (como espera la decoración).

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local NestBuilder = {}

export type Nest = {
	Index: number,
	Kind: "Lobby" | "Arena",
	Origin: CFrame,
	Size: number,
	Model: Model,
	Spawn: SpawnLocation,
	Sign: TextLabel,
	-- Dónde se pone cada criatura (de pie sobre el pedestal, mirando a la entrada).
	Pedestals: { CFrame },
	Rims: { BasePart }, -- aro de cada pedestal (se colorea con la rareza)
	Plates: { TextLabel }, -- placa con el nombre de cada pedestal
	Incubator: BasePart?, -- huevo del cuenco (brilla cuando hay huevos listos)
}

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

local function cylinder(cf: CFrame, height: number, diameter: number, props: { [string]: any }, parent: Instance): Part
	local p = block({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = cf * CFrame.Angles(0, 0, math.rad(90)),
	}, parent)
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function surfaceText(part: BasePart, face: Enum.NormalId, canvas: Vector2, text: string, color: Color3): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.CanvasSize = canvas
	gui.LightInfluence = 0.3
	gui.MaxDistance = 160
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = gui
	return label
end

local function spawnAt(cf: CFrame, parent: Instance): SpawnLocation
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = cf
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Enabled = false -- solo sirve de referencia: NestService coloca al dueño
	spawn.Duration = 0
	spawn.Parent = parent
	return spawn
end

-- Posiciones de los pedestales del lobby: gradas de 4 en 3 filas, de delante a atrás y del
-- centro hacia fuera (las mejores criaturas, en el centro de la primera fila).
local PEDESTAL_X = { -2.3, 2.3, -6.9, 6.9 }
local PEDESTAL_ROWS = { { Z = -1.5, H = 1.4 }, { Z = 4, H = 2.6 }, { Z = 9.5, H = 3.8 } }

function NestBuilder.lobby(index: number, origin: CFrame, parent: Instance): Nest
	local size = Config.Lobby.NestSize
	local half = size / 2
	local model = Instance.new("Model")
	model.Name = "Nest_" .. index
	model.Parent = parent

	block({ Name = "Floor", Size = Vector3.new(size, 1, size), CFrame = origin * CFrame.new(0, 0.5, 0), Color = Color3.fromRGB(110, 165, 80), Material = Enum.Material.Grass }, model)
	block({ Name = "Border", Size = Vector3.new(size + 2, 0.8, size + 2), CFrame = origin * CFrame.new(0, 0.4, 0), Color = Color3.fromRGB(150, 120, 90), Material = Enum.Material.Cobblestone }, model)
	-- Camino de piedras de la entrada a las gradas.
	for k = 0, 3 do
		cylinder(origin * CFrame.new((k % 2 - 0.5) * 1.2, 1.02, -half + 2 + k * 2.6), 0.15, 2.2, { Name = "Stepstone", Color = Color3.fromRGB(205, 195, 175), Material = Enum.Material.Slate, CanCollide = false }, model)
	end

	-- Valla de madera con la entrada delante (10 de ancho).
	local wood = Color3.fromRGB(160, 110, 70)
	-- Las esquinas son de dos tramos de valla: el poste se pone una sola vez (dos piezas
	-- iguales en el mismo sitio parpadean).
	local posts: { [string]: boolean } = {}
	local function fence(from: Vector3, to: Vector3)
		local length = (to - from).Magnitude
		local cf = origin * CFrame.lookAt(from, to)
		for _, y in { 1.8, 3.2 } do
			-- Un poco más cortas: en las esquinas no se cruzan con las del otro lado.
			block({ Name = "FenceRail", Size = Vector3.new(0.3, 0.35, length - 0.6), CFrame = cf * CFrame.new(0, y, -length / 2), Color = wood, Material = Enum.Material.Wood }, model)
		end
		local count = math.max(1, math.floor(length / 4))
		for k = 0, count do
			local p = from:Lerp(to, k / count)
			local key = string.format("%.1f,%.1f", p.X, p.Z)
			-- Las esquinas llevan farola: ahí no hace falta poste.
			local corner = math.abs(math.abs(p.X) - half) < 0.01 and math.abs(math.abs(p.Z) - half) < 0.01
			if not posts[key] and not corner then
				posts[key] = true
				block({ Name = "FencePost", Size = Vector3.new(0.5, 3.4, 0.5), CFrame = origin * CFrame.new(p + Vector3.new(0, 2.2, 0)), Color = wood, Material = Enum.Material.Wood }, model)
			end
		end
	end
	local e = 5
	fence(Vector3.new(-half, 0, half), Vector3.new(half, 0, half))
	fence(Vector3.new(-half, 0, -half), Vector3.new(-half, 0, half))
	fence(Vector3.new(half, 0, -half), Vector3.new(half, 0, half))
	fence(Vector3.new(-half, 0, -half), Vector3.new(-e, 0, -half))
	fence(Vector3.new(e, 0, -half), Vector3.new(half, 0, -half))

	-- Farolillos en las esquinas.
	for _, corner in { Vector3.new(-half, 0, -half), Vector3.new(half, 0, -half), Vector3.new(-half, 0, half), Vector3.new(half, 0, half) } do
		block({ Name = "LampPost", Size = Vector3.new(0.6, 6, 0.6), CFrame = origin * CFrame.new(corner + Vector3.new(0, 3.5, 0)), Color = Color3.fromRGB(60, 50, 45), Material = Enum.Material.Metal }, model)
		local lamp = block({ Name = "Lamp", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), CFrame = origin * CFrame.new(corner + Vector3.new(0, 7, 0)), Color = Color3.fromRGB(255, 205, 120), Material = Enum.Material.Neon, CanCollide = false }, model)
		local light = Instance.new("PointLight")
		light.Range = 14
		light.Brightness = 1
		light.Color = lamp.Color
		light.Parent = lamp
	end

	-- Arco de entrada con el cartel del dueño (mira a la plaza).
	for _, side in { -1, 1 } do
		block({ Name = "ArchPost", Size = Vector3.new(1, 9, 1), CFrame = origin * CFrame.new(side * (e + 0.5), 5, -half), Color = wood, Material = Enum.Material.Wood }, model)
		block({ Name = "Flowers", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 1.6, 2), CFrame = origin * CFrame.new(side * (e + 2), 1.6, -half - 1.2), Color = if side < 0 then Color3.fromRGB(255, 120, 170) else Color3.fromRGB(255, 220, 90), Material = Enum.Material.Grass, CanCollide = false }, model)
	end
	local signBoard = block({ Name = "SignBoard", Size = Vector3.new(12, 3, 0.6), CFrame = origin * CFrame.new(0, 9.5, -half), Color = Color3.fromRGB(110, 75, 45), Material = Enum.Material.Wood }, model)
	local sign = surfaceText(signBoard, Enum.NormalId.Front, Vector2.new(480, 120), "Nido libre", Color3.fromRGB(255, 240, 210))
	-- El cartel también por dentro (desde las gradas se lee el mismo texto al revés si no).
	local signBack = surfaceText(signBoard, Enum.NormalId.Back, Vector2.new(480, 120), "", Color3.fromRGB(255, 240, 210))
	sign:GetPropertyChangedSignal("Text"):Connect(function()
		signBack.Text = sign.Text
	end)

	-- Gradas de pedestales.
	local pedestals: { CFrame } = {}
	local rims: { BasePart } = {}
	local plates: { TextLabel } = {}
	for _, rowInfo in PEDESTAL_ROWS do
		for _, x in PEDESTAL_X do
			local top = 1 + rowInfo.H
			cylinder(origin * CFrame.new(x, 1 + rowInfo.H / 2, rowInfo.Z), rowInfo.H, 3.6, { Name = "Pedestal", Color = Color3.fromRGB(235, 228, 215), Material = Enum.Material.Marble }, model)
			-- El aro queda un poco por debajo de la cara de arriba del podio: si quedan casi a la
			-- misma altura, las dos caras parpadean.
			local rim = cylinder(origin * CFrame.new(x, top - 0.3, rowInfo.Z), 0.4, 3.9, { Name = "Rim", Color = Color3.fromRGB(120, 120, 120), Material = Enum.Material.Neon, CanCollide = false }, model)
			local plate = block({
				Name = "Plate",
				Size = Vector3.new(3.4, 0.9, 0.2),
				CFrame = origin * CFrame.new(x, top - 0.9, rowInfo.Z - 1.95) * CFrame.Angles(math.rad(-12), 0, 0),
				Color = Color3.fromRGB(60, 45, 35),
				Material = Enum.Material.Wood,
				CanCollide = false,
			}, model)
			local label = surfaceText(plate, Enum.NormalId.Front, Vector2.new(340, 90), "", Color3.new(1, 1, 1))
			table.insert(pedestals, origin * CFrame.new(x, top, rowInfo.Z))
			table.insert(rims, rim)
			table.insert(plates, label)
		end
	end

	-- Cuenco del nido al fondo, con el huevo de la incubadora.
	local bowlCenter = Vector3.new(0, 1, half - 3.5)
	for k = 0, 13 do
		local angle = k * math.pi * 2 / 14
		local p = bowlCenter + Vector3.new(math.cos(angle) * 2.6, 0.9, math.sin(angle) * 2.6)
		block({
			Name = "Twig",
			Size = Vector3.new(0.6, 0.6, 2.4),
			CFrame = origin * CFrame.lookAt(p, bowlCenter + Vector3.new(0, 0.9, 0)) * CFrame.Angles(math.rad(35), math.rad(90), 0),
			Color = Color3.fromRGB(120 + (k % 3) * 15, 85, 55),
			Material = Enum.Material.Wood,
			CanCollide = false,
		}, model)
	end
	local egg = block({ Name = "IncubatorEgg", Size = Vector3.new(2.4, 3, 2.4), CFrame = origin * CFrame.new(bowlCenter + Vector3.new(0, 1.8, 0)), Color = Color3.fromRGB(250, 240, 220), CanCollide = false }, model)
	local eggMesh = Instance.new("SpecialMesh")
	eggMesh.MeshType = Enum.MeshType.Sphere
	eggMesh.Parent = egg
	local eggLight = Instance.new("PointLight")
	eggLight.Name = "ReadyLight"
	eggLight.Range = 10
	eggLight.Color = Color3.fromRGB(255, 220, 120)
	eggLight.Enabled = false
	eggLight.Parent = egg

	-- Apareces en la entrada mirando a tus criaturas.
	local spawn = spawnAt(origin * CFrame.new(0, 1.1, -half + 4) * CFrame.Angles(0, math.pi, 0), model)

	return {
		Index = index,
		Kind = "Lobby",
		Origin = origin,
		Size = size,
		Model = model,
		Spawn = spawn,
		Sign = sign,
		Pedestals = pedestals,
		Rims = rims,
		Plates = plates,
		Incubator = egg,
	}
end

-- Campamento de salida en la arena: plataforma redonda, cuenco y 3 pedestales.
function NestBuilder.arena(index: number, origin: CFrame, parent: Instance): Nest
	local size = 20
	local model = Instance.new("Model")
	model.Name = "Nest_" .. index
	model.Parent = parent

	cylinder(origin * CFrame.new(0, 0.5, 0), 1, size, { Name = "Floor", Color = Color3.fromRGB(150, 120, 85), Material = Enum.Material.WoodPlanks }, model)
	cylinder(origin * CFrame.new(0, 0.45, 0), 0.9, size + 1.6, { Name = "Rim", Color = Color3.fromRGB(110, 85, 60), Material = Enum.Material.Wood }, model)
	-- Ramitas alrededor (forma de nido), con hueco delante.
	for k = 0, 17 do
		local angle = k * math.pi * 2 / 18
		if math.abs(math.sin(angle) + 1) > 0.25 then -- deja libre el frente (-Z)
			local p = Vector3.new(math.cos(angle) * (size / 2 - 0.4), 1.2, math.sin(angle) * (size / 2 - 0.4))
			block({
				Name = "Twig",
				Size = Vector3.new(0.8, 1.6, 3.6),
				CFrame = origin * CFrame.lookAt(p, Vector3.new(0, 1.2, 0)) * CFrame.Angles(math.rad(20), math.rad(90), 0),
				Color = Color3.fromRGB(115 + (k % 3) * 15, 80, 50),
				Material = Enum.Material.Wood,
			}, model)
		end
	end

	local pedestals: { CFrame } = {}
	local rims: { BasePart } = {}
	local plates: { TextLabel } = {}
	for k, x in { 0, -4.5, 4.5 } do
		local z = if k == 1 then 5.5 else 4.5
		local h = if k == 1 then 2.4 else 1.6
		cylinder(origin * CFrame.new(x, 1 + h / 2, z), h, 3, { Name = "Pedestal", Color = Color3.fromRGB(235, 228, 215), Material = Enum.Material.Marble }, model)
		local rim = cylinder(origin * CFrame.new(x, 1 + h - 0.3, z), 0.4, 3.3, { Name = "Rim", Color = Color3.fromRGB(120, 120, 120), Material = Enum.Material.Neon, CanCollide = false }, model)
		table.insert(pedestals, origin * CFrame.new(x, 1 + h, z))
		table.insert(rims, rim)
	end

	local signPart = block({ Name = "SignPost", Size = Vector3.new(1, 1, 1), CFrame = origin * CFrame.new(0, 9, 0), Transparency = 1, CanCollide = false, CanQuery = false }, model)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 50)
	billboard.MaxDistance = 140
	billboard.Parent = signPart
	local sign = Instance.new("TextLabel")
	sign.Size = UDim2.fromScale(1, 1)
	sign.BackgroundTransparency = 1
	sign.Font = Enum.Font.FredokaOne
	sign.TextScaled = true
	sign.TextColor3 = Color3.new(1, 1, 1)
	sign.TextStrokeTransparency = 0.2
	sign.Text = ""
	sign.Parent = billboard

	local spawn = spawnAt(origin * CFrame.new(0, 1.1, -2), model)

	return {
		Index = index,
		Kind = "Arena",
		Origin = origin,
		Size = size,
		Model = model,
		Spawn = spawn,
		Sign = sign,
		Pedestals = pedestals,
		Rims = rims,
		Plates = plates,
		Incubator = nil,
	}
end

return NestBuilder
