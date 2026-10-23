--!strict
-- Ladrones del bosque (GDD v2): en servidores con menos de Config.ForestThieves.FillTo
-- jugadores, durante la persecución salen zorros del borde del mapa que persiguen a los
-- portadores. Si completan el tira y afloja (las mismas reglas que un jugador:
-- ChaseRules), la criatura cae al suelo; nunca se la quedan. Dan tensión a los servidores
-- pequeños, que es lo normal al lanzar un juego. Son claramente criaturas del juego, no
-- jugadores falsos.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ChaseRules = require(Shared.ChaseRules)
local Config = require(Shared.Config)
local MapLayout = require(Shared.MapLayout)
local RoundState = require(Shared.RoundState)

local ChaseService = require(script.Parent.ChaseService)
local NestService = require(script.Parent.NestService)

local ForestService = {}

type Fox = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	TargetIndex: number?,
	SeenAt: number,
	TugStartedAt: number?,
	RestUntil: number, -- tras tirar una criatura, vuelve al bosque un rato
	Home: Vector3,
	LastPosition: Vector3,
	StuckSince: number,
}

local foxes: { Fox } = {}
local folder: Folder? = nil

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.Massless = true
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

-- Un zorro sencillo: cuerpo, cabeza, orejas y cola sobre un HumanoidRootPart.
local function buildFox(position: Vector3, index: number): Fox
	local model = Instance.new("Model")
	model.Name = "Zorro" .. index
	local orange = Color3.fromRGB(230, 120, 40)
	local root = part({ Name = "HumanoidRootPart", Size = Vector3.new(2, 2, 3), Transparency = 1, CanCollide = true, Massless = false }, model)
	root.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
	local body = part({ Name = "Body", Size = Vector3.new(1.8, 1.4, 2.8), Color = orange }, model)
	body.CFrame = root.CFrame
	local head = part({ Name = "Head", Size = Vector3.new(1.4, 1.3, 1.3), Color = orange }, model)
	head.CFrame = root.CFrame * CFrame.new(0, 0.6, -1.9)
	local snout = part({ Name = "Snout", Size = Vector3.new(0.7, 0.6, 0.8), Color = Color3.fromRGB(250, 240, 230) }, model)
	snout.CFrame = head.CFrame * CFrame.new(0, -0.2, -0.9)
	for _, side in { -1, 1 } do
		local ear = part({ Name = "Ear", Shape = Enum.PartType.Block, Size = Vector3.new(0.4, 0.7, 0.3), Color = Color3.fromRGB(60, 40, 30) }, model)
		ear.CFrame = head.CFrame * CFrame.new(side * 0.45, 0.85, 0)
		weld(head, ear)
	end
	local tail = part({ Name = "Tail", Size = Vector3.new(0.7, 0.7, 2), Color = orange }, model)
	tail.CFrame = root.CFrame * CFrame.new(0, 0.5, 2.2) * CFrame.Angles(math.rad(25), 0, 0)
	local tip = part({ Name = "TailTip", Size = Vector3.new(0.72, 0.72, 0.6), Color = Color3.fromRGB(250, 240, 230) }, model)
	tip.CFrame = tail.CFrame * CFrame.new(0, 0, 1.2)
	for _, p in { body, head, snout, tail } do
		weld(root, p)
	end
	weld(tail, tip)

	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = 1.2
	humanoid.WalkSpeed = Config.Movement.BaseWalkSpeed * Config.ForestThieves.SpeedMultiplier
	humanoid.DisplayName = "🦊 Zorro del bosque"
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	model.PrimaryPart = root
	model.Parent = folder
	root:SetNetworkOwner(nil) -- lo mueve el servidor
	return {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		TargetIndex = nil,
		SeenAt = 0,
		TugStartedAt = nil,
		RestUntil = 0,
		Home = position,
		LastPosition = root.Position,
		StuckSince = os.clock(),
	}
end

local function clear()
	for _, fox in foxes do
		fox.Model:Destroy()
	end
	table.clear(foxes)
end

local function spawnFoxes()
	clear()
	if not Config.ForestThieves.Enabled then
		return
	end
	local players = #Players:GetPlayers()
	local count = math.min(Config.ForestThieves.MaxCount, Config.ForestThieves.FillTo - players)
	if count <= 0 then
		return
	end
	for i = 1, count do
		local point = MapLayout.polar(math.random() * math.pi * 2, MapLayout.Radius - 8)
		table.insert(foxes, buildFox(Vector3.new(point.X, 2, point.Z), i))
	end
end

local function nearestTarget(fox: Fox): ChaseService.Target?
	local best: ChaseService.Target? = nil
	local bestDistance = math.huge
	for _, target in ChaseService.targets() do
		local d = (target.Position - fox.Root.Position).Magnitude
		if d < bestDistance then
			best, bestDistance = target, d
		end
	end
	return best
end

local function tick()
	local now = os.clock()
	local phase = RoundState.phase()
	if phase ~= "Chase" and phase ~= "Overtime" then
		return
	end
	for _, fox in foxes do
		local humanoid = fox.Humanoid
		-- Velocidad: como en los jugadores, en un nido ajeno se va más lento.
		local inNest = NestService.nestIndexAt(fox.Root.Position) ~= nil
		humanoid.WalkSpeed = Config.Movement.BaseWalkSpeed * Config.ForestThieves.SpeedMultiplier * (if inNest then Config.Chase.IntruderSpeedMultiplier else 1)
		if now < fox.RestUntil then
			humanoid:MoveTo(fox.Home)
			fox.TugStartedAt = nil
			continue
		end
		-- Reacciona con algo de retraso (como un jugador que mira a dónde va el portador).
		local target = nearestTarget(fox)
		if not target then
			fox.TugStartedAt = nil
			humanoid:MoveTo(fox.Home)
			continue
		end
		if target.Index ~= fox.TargetIndex then
			fox.TargetIndex = target.Index
			fox.TugStartedAt = nil
		end
		if now - fox.SeenAt >= Config.ForestThieves.Reaction then
			fox.SeenAt = now
			humanoid:MoveTo(target.Position)
		end
		-- Atascado (un árbol): saltar.
		if (fox.Root.Position - fox.LastPosition).Magnitude < 0.5 then
			if now - fox.StuckSince > 1.5 then
				humanoid.Jump = true
				fox.StuckSince = now
			end
		else
			fox.StuckSince = now
		end
		fox.LastPosition = fox.Root.Position

		-- Tira y afloja: tiene que seguir cerca durante el tiempo de robo.
		local d = (target.Position - fox.Root.Position).Magnitude
		if d <= Config.Chase.StealRange then
			if not fox.TugStartedAt then
				fox.TugStartedAt = now
			end
		elseif d > Config.Chase.StealRange + ChaseRules.DistanceTolerance then
			fox.TugStartedAt = nil
		end
		local started = fox.TugStartedAt
		if started and now - started >= ChaseRules.holdTime(NestService.isInsideOwnNest(target.Carrier)) then
			fox.TugStartedAt = nil
			local result = ChaseService.foxGrab(target.Index, fox.Root.Position, started)
			if result == "dropped" or result == "shield" then
				fox.RestUntil = now + 8 -- vuelve al bosque un rato
			end
		end
	end
end

function ForestService.init()
	local map = workspace:FindFirstChild("Map")
	local f = Instance.new("Folder")
	f.Name = "ForestThieves"
	f.Parent = map or workspace
	folder = f
end

function ForestService.start()
	RoundState.changed("Phase"):Connect(function()
		local phase = RoundState.phase()
		if phase == "Chase" then
			spawnFoxes()
		elseif phase ~= "Overtime" then
			clear()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.2)
			local ok, err = pcall(tick)
			if not ok then
				warn("[ForestService] " .. tostring(err))
			end
		end
	end)
end

return ForestService
