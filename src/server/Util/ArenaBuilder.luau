--!strict
-- Construye en piezas el parkour de la arena descrito en ArenaLayout (GDD v3): árboles
-- gigantes, plataformas, rampas con barandilla (la ruta segura), puentes, vigas estrechas y
-- piedras flotantes (atajos arriesgados), escaleras, cabañas, copas y arbustos (escondites),
-- tirolinas, toboganes y setas trampolín. Las tirolinas, los toboganes y las setas los mueve
-- el cliente (ArenaController); aquí solo se colocan y se etiquetan.

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ArenaLayout = require(Shared.ArenaLayout)
local Config = require(Shared.Config)

local ArenaBuilder = {}

local WOOD = Color3.fromRGB(150, 105, 70)
local DARK_WOOD = Color3.fromRGB(95, 62, 40)
local BARK = Color3.fromRGB(88, 58, 40)
local ROPE = Color3.fromRGB(205, 180, 130)
local LEAVES = {
	Color3.fromRGB(205, 95, 45),
	Color3.fromRGB(225, 130, 50),
	Color3.fromRGB(175, 70, 40),
	Color3.fromRGB(235, 165, 70),
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

local function vec(v: ArenaLayout.Vec): Vector3
	return Vector3.new(v.X, v.Y, v.Z)
end

-- Tablón entre dos puntos con la cara de arriba a la altura de los puntos.
local function plank(a: Vector3, b: Vector3, width: number, props: { [string]: any }, parent: Instance): Part
	local length = (b - a).Magnitude
	local cf = CFrame.lookAt(a, b) * CFrame.new(0, -0.5, -length / 2)
	local p = block({ Size = Vector3.new(width, 1, length + 0.8), CFrame = cf, Color = WOOD, Material = Enum.Material.WoodPlanks }, parent)
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

-- Cuerda/barandilla fina entre dos puntos.
local function rope(a: Vector3, b: Vector3, thickness: number, parent: Instance, collide: boolean?): Part
	local length = (b - a).Magnitude
	return block({
		Name = "Rope",
		Size = Vector3.new(thickness, thickness, length),
		CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -length / 2),
		Color = ROPE,
		Material = Enum.Material.Fabric,
		CanCollide = collide == true,
		CastShadow = false,
	}, parent)
end

local function leafBall(position: Vector3, size: number, color: Color3, parent: Instance): Part
	local leaf = block({
		Name = "Leaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size, size),
		CFrame = CFrame.new(position),
		Color = color,
		Material = Enum.Material.Grass,
		CanCollide = false,
		CanQuery = false,
	}, parent)
	CollectionService:AddTag(leaf, "HidingSpot")
	return leaf
end

local function buildTree(tree: ArenaLayout.Tree, folder: Folder, addObstacle: (Vector3, number) -> ())
	local model = Instance.new("Model")
	model.Name = "GiantTree_" .. tree.Index
	model.Parent = folder
	local center = Vector3.new(tree.X, 0, tree.Z)
	addObstacle(center, tree.Radius + 1.5)

	-- Tronco y raíces.
	block({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(tree.Height, tree.Radius * 2, tree.Radius * 2),
		CFrame = CFrame.new(center + Vector3.new(0, tree.Height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = BARK,
		Material = Enum.Material.Wood,
	}, model)
	for k = 0, 4 do
		local angle = k * math.pi * 2 / 5 + tree.Index
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		block({
			Name = "Root",
			Size = Vector3.new(3, 10, 7),
			CFrame = CFrame.lookAt(center + out * (tree.Radius + 1), center + out * (tree.Radius + 10)) * CFrame.new(0, 2, -1) * CFrame.Angles(math.rad(-55), 0, 0),
			Color = BARK,
			Material = Enum.Material.Wood,
			CanCollide = false,
		}, model)
	end

	-- Plataformas: anillo cuadrado alrededor del tronco (4 tablas que entran en el tronco
	-- para que no queden huecos en las esquinas).
	local half = ArenaLayout.deckHalf(tree)
	local inner = tree.Radius * 0.7
	for _, level in tree.Decks do
		local y = level - 0.5
		local depth = half - inner
		for _, side in { -1, 1 } do
			block({ Name = "Deck", Size = Vector3.new(half * 2, 1, depth), CFrame = CFrame.new(center + Vector3.new(0, y, side * (inner + depth / 2))), Color = WOOD, Material = Enum.Material.WoodPlanks }, model)
			block({ Name = "Deck", Size = Vector3.new(depth, 1, inner * 2), CFrame = CFrame.new(center + Vector3.new(side * (inner + depth / 2), y, 0)), Color = WOOD, Material = Enum.Material.WoodPlanks }, model)
		end
		-- Borde oscuro para que se vea el contorno desde lejos.
		for _, side in { -1, 1 } do
			block({ Name = "Trim", Size = Vector3.new(half * 2 + 0.4, 0.6, 0.4), CFrame = CFrame.new(center + Vector3.new(0, y - 0.2, side * half)), Color = DARK_WOOD, Material = Enum.Material.Wood, CanCollide = false }, model)
			block({ Name = "Trim", Size = Vector3.new(0.4, 0.6, half * 2 + 0.4), CFrame = CFrame.new(center + Vector3.new(side * half, y - 0.2, 0)), Color = DARK_WOOD, Material = Enum.Material.Wood, CanCollide = false }, model)
		end
		-- Farolillo en una esquina de cada plataforma.
		local lamp = block({
			Name = "Lantern",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.2, 1.2, 1.2),
			CFrame = CFrame.new(center + Vector3.new(half - 0.8, level + 3, half - 0.8)),
			Color = Color3.fromRGB(255, 200, 110),
			Material = Enum.Material.Neon,
			CanCollide = false,
		}, model)
		local light = Instance.new("PointLight")
		light.Range = 16
		light.Brightness = 1.2
		light.Color = lamp.Color
		light.Parent = lamp
		block({ Name = "LanternPost", Size = Vector3.new(0.3, 3, 0.3), CFrame = CFrame.new(center + Vector3.new(half - 0.8, level + 1.5, half - 0.8)), Color = DARK_WOOD, CanCollide = false }, model)
	end

	-- Rampa en espiral con barandilla exterior: la ruta lenta pero segura.
	if tree.Ramp then
		local points = ArenaLayout.rampPoints(tree)
		local outer = ArenaLayout.rampRadius(tree) + ArenaLayout.RampWidth / 2 - 0.2
		for i = 1, #points - 1 do
			local a, b = vec(points[i]), vec(points[i + 1])
			plank(a, b, ArenaLayout.RampWidth, { Name = "Ramp" }, model)
			-- Barandilla: del borde exterior de un punto al del siguiente.
			local function edge(p: Vector3): Vector3
				local dir = Vector3.new(p.X - tree.X, 0, p.Z - tree.Z).Unit
				return Vector3.new(tree.X, p.Y, tree.Z) + dir * outer
			end
			local ea, eb = edge(a), edge(b)
			rope(ea + Vector3.new(0, 2.6, 0), eb + Vector3.new(0, 2.6, 0), 0.35, model, true)
			if i % 2 == 1 then
				block({ Name = "Post", Size = Vector3.new(0.4, 2.8, 0.4), CFrame = CFrame.new(ea + Vector3.new(0, 1.2, 0)), Color = DARK_WOOD, Material = Enum.Material.Wood }, model)
			end
		end
	end

	-- Escalera de mano pegada al borde de las plataformas (trepar es rápido).
	if tree.Ladder then
		local top = tree.Decks[#tree.Decks] + 2
		local height = math.ceil(top / 2) * 2
		local angle = math.atan2(-tree.Z, -tree.X) -- mirando al claro
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local truss = Instance.new("TrussPart")
		truss.Name = "Ladder"
		truss.Anchored = true
		truss.Size = Vector3.new(2, height, 2)
		truss.CFrame = CFrame.lookAt(center + dir * (half + 1) + Vector3.new(0, height / 2, 0), center + Vector3.new(0, height / 2, 0))
		truss.Color = DARK_WOOD
		truss.Material = Enum.Material.Wood
		truss.Parent = model
	end

	-- Cabaña: plataforma que sobresale con una casita (escondite).
	local hutLevel = tree.Hut
	if hutLevel then
		local dir = Vector3.new(math.cos(tree.HutAngle), 0, math.sin(tree.HutAngle))
		local base = center + dir * (half + 5) + Vector3.new(0, hutLevel, 0)
		local cf = CFrame.lookAt(base, base - dir) -- la puerta mira al tronco
		block({ Name = "HutFloor", Size = Vector3.new(11, 1, 11), CFrame = cf * CFrame.new(0, -0.5, 0), Color = WOOD, Material = Enum.Material.WoodPlanks }, model)
		local wall = Color3.fromRGB(170, 120, 80)
		block({ Name = "HutWall", Size = Vector3.new(9, 7, 0.6), CFrame = cf * CFrame.new(0, 3.5, 4.2), Color = wall, Material = Enum.Material.Wood }, model)
		for _, side in { -1, 1 } do
			block({ Name = "HutWall", Size = Vector3.new(0.6, 7, 9), CFrame = cf * CFrame.new(side * 4.2, 3.5, 0), Color = wall, Material = Enum.Material.Wood }, model)
			block({ Name = "HutFront", Size = Vector3.new(2.8, 7, 0.6), CFrame = cf * CFrame.new(side * 3.1, 3.5, -4.2), Color = wall, Material = Enum.Material.Wood }, model)
			block({
				Name = "HutRoof",
				Size = Vector3.new(6.6, 0.6, 11),
				CFrame = cf * CFrame.new(side * 2.6, 8.2, 0) * CFrame.Angles(0, 0, math.rad(side * -32)),
				Color = Color3.fromRGB(190, 70, 50),
				Material = Enum.Material.Wood,
			}, model)
		end
		block({ Name = "HutLintel", Size = Vector3.new(3.4, 2, 0.6), CFrame = cf * CFrame.new(0, 6, -4.2), Color = wall, Material = Enum.Material.Wood }, model)
		local glow = block({ Name = "HutLamp", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8), CFrame = cf * CFrame.new(0, 5.6, 2), Color = Color3.fromRGB(255, 190, 110), Material = Enum.Material.Neon, CanCollide = false }, model)
		local light = Instance.new("PointLight")
		light.Range = 8
		light.Brightness = 0.6
		light.Color = glow.Color
		light.Parent = glow
		local zone = block({ Name = "HutInside", Size = Vector3.new(7.6, 6, 7.6), CFrame = cf * CFrame.new(0, 3, 0), Transparency = 1, CanCollide = false, CanQuery = false }, model)
		CollectionService:AddTag(zone, "HidingSpot")
	end

	-- Copa: varias bolas de hojas por encima de la plataforma más alta (se puede esconder dentro).
	local top = tree.Decks[#tree.Decks]
	for k = 1, 6 do
		local angle = k * math.pi * 2 / 6 + tree.Index * 0.7
		local spread = tree.Radius + 4 + (k % 2) * 4
		local position = center + Vector3.new(math.cos(angle) * spread, top + 7 + (k % 3) * 5, math.sin(angle) * spread)
		leafBall(position, 18 + (k % 3) * 4, LEAVES[(k + tree.Index) % #LEAVES + 1], model)
	end
	leafBall(center + Vector3.new(0, tree.Height - 2, 0), 26, LEAVES[tree.Index % #LEAVES + 1], model)
	-- Matas de hojas en las plataformas intermedias.
	for i, level in tree.Decks do
		if i < #tree.Decks then
			local angle = tree.Index * 1.3 + i * 2
			local spot = center + Vector3.new(math.cos(angle) * (half - 2), level + 2.5, math.sin(angle) * (half - 2))
			leafBall(spot, 7, LEAVES[(i + tree.Index) % #LEAVES + 1], model)
		end
	end
end

local function buildLink(arena: ArenaLayout.Arena, link: ArenaLayout.Link, folder: Instance)
	local a, b = ArenaLayout.linkEnds(arena, link)
	local va, vb = vec(a), vec(b)
	if link.Kind == "Bridge" then
		local bridge = plank(va, vb, 5, { Name = "Bridge" }, folder)
		local right = bridge.CFrame.RightVector
		for _, side in { -1, 1 } do
			local offset = right * side * 2.4
			rope(va + offset + Vector3.new(0, 2.6, 0), vb + offset + Vector3.new(0, 2.6, 0), 0.3, folder, true)
			for _, p in { va, vb } do
				block({ Name = "BridgePost", Size = Vector3.new(0.5, 3.2, 0.5), CFrame = CFrame.new(p + offset + Vector3.new(0, 1.3, 0)), Color = DARK_WOOD, Material = Enum.Material.Wood }, folder)
			end
		end
	elseif link.Kind == "Beam" then
		-- Viga estrecha sin barandilla: atajo donde no te pueden rodear.
		plank(va, vb, 1.6, { Name = "Beam", Color = DARK_WOOD, Material = Enum.Material.Wood }, folder)
	else
		for i, point in ArenaLayout.stonePoints(arena, link) do
			block({
				Name = "Stone",
				Size = Vector3.new(4, 1.4, 4),
				CFrame = CFrame.new(vec(point) - Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, i * 0.9, 0),
				Color = if i % 2 == 0 then Color3.fromRGB(120, 125, 115) else Color3.fromRGB(95, 120, 85),
				Material = if i % 2 == 0 then Enum.Material.Slate else Enum.Material.Grass,
			}, folder)
		end
	end
end

local function buildRide(ride: ArenaLayout.Ride, index: number, folder: Instance)
	local from, to = vec(ride.From), vec(ride.To)
	if ride.Kind == "Zipline" then
		-- Postes en los extremos y cable. El prompt está en el poste de salida.
		local startPost = block({ Name = "ZiplinePost", Size = Vector3.new(0.8, 9, 0.8), CFrame = CFrame.new(from - Vector3.new(0, 4.5, 0)), Color = DARK_WOOD, Material = Enum.Material.Wood }, folder)
		block({ Name = "ZiplinePost", Size = Vector3.new(0.8, 5, 0.8), CFrame = CFrame.new(to), Color = DARK_WOOD, Material = Enum.Material.Wood, CanCollide = false }, folder)
		rope(from, to + Vector3.new(0, 4, 0), 0.25, folder, false).Color = Color3.fromRGB(80, 80, 85)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RidePrompt"
		prompt.ActionText = "Tirolina"
		prompt.ObjectText = "¡Abajo!"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt:SetAttribute("RideFrom", from - Vector3.new(0, 3.2, 0))
		prompt:SetAttribute("RideTo", to + Vector3.new(0, 0.8, 0))
		prompt:SetAttribute("RideSpeed", Config.Arena.ZiplineSpeed)
		prompt:SetAttribute("RideKind", "Zipline")
		prompt.Parent = startPost
		CollectionService:AddTag(prompt, "RidePrompt")
	else
		-- Tobogán: canal inclinado con paredes; al pisar la entrada te deslizas hasta abajo.
		local length = (to - from).Magnitude
		local cf = CFrame.lookAt(from, to)
		local chute = block({
			Name = "Slide",
			Size = Vector3.new(4, 0.6, length + 1),
			CFrame = cf * CFrame.new(0, -0.3, -length / 2),
			Color = Color3.fromRGB(80, 170, 220),
			Material = Enum.Material.SmoothPlastic,
		}, folder)
		chute.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0.3, 100, 1)
		for _, side in { -1, 1 } do
			block({ Name = "SlideWall", Size = Vector3.new(0.5, 1.8, length + 1), CFrame = cf * CFrame.new(side * 2.2, 0.6, -length / 2), Color = Color3.fromRGB(255, 220, 90), Material = Enum.Material.SmoothPlastic }, folder)
		end
		local entry = block({
			Name = "SlideEntry",
			Size = Vector3.new(4, 3, 2),
			CFrame = cf * CFrame.new(0, 1.5, -1.5),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		}, folder)
		entry:SetAttribute("RideFrom", from + Vector3.new(0, 2.6, 0))
		entry:SetAttribute("RideTo", to + Vector3.new(0, 2.6, 0))
		entry:SetAttribute("RideSpeed", Config.Arena.ZiplineSpeed * 0.8)
		entry:SetAttribute("RideKind", "Slide")
		entry:SetAttribute("RideIndex", index)
		CollectionService:AddTag(entry, "SlideEntry")
	end
end

local function buildTrampoline(t: ArenaLayout.Trampoline, folder: Instance)
	local base = Vector3.new(t.X, t.Y, t.Z)
	block({ Name = "MushroomStem", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, 2.4, 2.4), CFrame = CFrame.new(base + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(245, 235, 215) }, folder)
	local cap = block({ Name = "Trampoline", Size = Vector3.new(7, 2, 7), CFrame = CFrame.new(base + Vector3.new(0, 3.2, 0)), Color = Color3.fromRGB(225, 60, 60) }, folder)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = cap
	for k = 0, 4 do
		local angle = k * math.pi * 2 / 5
		block({ Name = "Dot", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 0.6, 1), CFrame = CFrame.new(base + Vector3.new(math.cos(angle) * 2, 4, math.sin(angle) * 2)), Color = Color3.new(1, 1, 1), CanCollide = false, CanQuery = false }, folder)
	end
	cap:SetAttribute("Power", t.Power)
	CollectionService:AddTag(cap, "Trampoline")
end

function ArenaBuilder.build(folder: Folder, addObstacle: (Vector3, number) -> ())
	local arena = ArenaLayout.get()
	local treesFolder = Instance.new("Folder")
	treesFolder.Name = "Parkour"
	treesFolder.Parent = folder
	for _, tree in arena.Trees do
		buildTree(tree, treesFolder, addObstacle)
	end
	for _, link in arena.Links do
		buildLink(arena, link, treesFolder)
	end
	for index, ride in arena.Rides do
		buildRide(ride, index, treesFolder)
	end
	for _, t in arena.Trampolines do
		buildTrampoline(t, treesFolder)
		addObstacle(Vector3.new(t.X, 0, t.Z), 4)
	end
	for i, b in arena.Blocks do
		block({
			Name = "FloatingBlock",
			Size = Vector3.new(b.Size, b.Size * 0.5, b.Size),
			CFrame = CFrame.new(b.X, b.Y, b.Z) * CFrame.Angles(0, i, 0),
			Color = if i % 3 == 0 then Color3.fromRGB(110, 150, 90) else Color3.fromRGB(130, 115, 100),
			Material = if i % 3 == 0 then Enum.Material.Grass else Enum.Material.Slate,
		}, treesFolder)
	end
	for i, bush in arena.Bushes do
		local base = Vector3.new(bush.X, 0, bush.Z)
		for k = 0, 2 do
			local angle = k * 2.1 + i
			leafBall(base + Vector3.new(math.cos(angle) * 1.8, 2.6 + (k % 2), math.sin(angle) * 1.8), 6 + (k % 2) * 2, Color3.fromRGB(80 + (i % 4) * 20, 120 + (k * 15), 50), treesFolder)
		end
	end
	for _, log in arena.Logs do
		local cf = CFrame.new(log.X, 0, log.Z) * CFrame.Angles(0, log.Angle, 0)
		addObstacle(Vector3.new(log.X, 0, log.Z), 4)
		for _, side in { -1, 1 } do
			block({ Name = "LogWall", Size = Vector3.new(1.2, 6, log.Length), CFrame = cf * CFrame.new(side * 3.6, 3, 0), Color = BARK, Material = Enum.Material.Wood }, treesFolder)
		end
		local roof = block({ Name = "LogRoof", Size = Vector3.new(8.4, 1.4, log.Length), CFrame = cf * CFrame.new(0, 6.6, 0), Color = BARK, Material = Enum.Material.Wood }, treesFolder)
		local inside = block({ Name = "LogInside", Size = Vector3.new(6, 5.5, log.Length), CFrame = cf * CFrame.new(0, 2.8, 0), Transparency = 1, CanCollide = false, CanQuery = false }, roof)
		CollectionService:AddTag(inside, "HidingSpot")
	end
end

return ArenaBuilder
