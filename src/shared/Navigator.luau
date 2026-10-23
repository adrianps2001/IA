--!strict
-- Navegación con PathfindingService para los bots de prueba (piloto automático) y los zorros
-- del bosque. Antes iban en línea recta con Humanoid:MoveTo y se quedaban pegados a las
-- paredes de los nidos y a los troncos. Ahora:
-- * calculan un camino que rodea obstáculos, sube rampas y trepa escaleras (TrussPart);
-- * lo recalculan si el objetivo se mueve o cada pocos segundos;
-- * si no avanzan, saltan, se apartan a un lado y piden otro camino;
-- * si no hay camino posible, van en línea recta (y saltan) como último recurso.
-- Funciona igual en el cliente (bots) y en el servidor (zorros).

local PathfindingService = game:GetService("PathfindingService")

local Navigator = {}
Navigator.__index = Navigator

export type Navigator = typeof(setmetatable(
	{} :: {
		Humanoid: Humanoid,
		Root: BasePart,
		Path: Path,
		Target: Vector3?,
		Waypoints: { PathWaypoint },
		Index: number,
		Computing: boolean,
		ComputedAt: number,
		ComputedFor: Vector3?,
		Direct: boolean,
		LastPosition: Vector3,
		LastProgressAt: number,
		Unstucks: number,
	},
	Navigator
))

local REPATH_SECONDS = 2.5 -- recalcular aunque el objetivo no se mueva
local REPATH_DISTANCE = 6 -- o si se ha movido más de esto
local STUCK_SECONDS = 1.2
local ARRIVE_DISTANCE = 3

function Navigator.new(humanoid: Humanoid, root: BasePart, agentRadius: number?): Navigator
	local path = PathfindingService:CreatePath({
		AgentRadius = agentRadius or 2,
		AgentHeight = 5,
		AgentCanJump = true,
		AgentCanClimb = true,
		WaypointSpacing = 6,
		Costs = { Water = 20 },
	})
	local self = setmetatable({
		Humanoid = humanoid,
		Root = root,
		Path = path,
		Target = nil :: Vector3?,
		Waypoints = {} :: { PathWaypoint },
		Index = 1,
		Computing = false,
		ComputedAt = 0,
		ComputedFor = nil :: Vector3?,
		Direct = false,
		LastPosition = root.Position,
		LastProgressAt = os.clock(),
		Unstucks = 0,
	}, Navigator)
	return self
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

function Navigator.compute(self: Navigator, target: Vector3)
	if self.Computing then
		return
	end
	self.Computing = true
	self.ComputedAt = os.clock()
	self.ComputedFor = target
	task.spawn(function()
		local ok = pcall(function()
			self.Path:ComputeAsync(self.Root.Position, target)
		end)
		self.Computing = false
		if self.Target ~= target and self.Target and (self.Target - target).Magnitude > REPATH_DISTANCE then
			return -- el objetivo cambió mientras calculaba; el siguiente update pide otro
		end
		if ok and self.Path.Status == Enum.PathStatus.Success then
			self.Waypoints = self.Path:GetWaypoints()
			self.Index = math.min(2, #self.Waypoints) -- el primero es donde ya está
			self.Direct = false
		else
			self.Waypoints = {}
			self.Direct = true
		end
	end)
end

-- Fija el objetivo (se puede llamar en cada tick; solo recalcula cuando hace falta).
function Navigator.moveTo(self: Navigator, target: Vector3)
	local previous = self.Target
	self.Target = target
	local stale = os.clock() - self.ComputedAt > REPATH_SECONDS
	local moved = not self.ComputedFor or (self.ComputedFor - target).Magnitude > REPATH_DISTANCE
	if not previous or moved or stale then
		self:compute(target)
	end
	self:update()
end

function Navigator.stop(self: Navigator)
	self.Target = nil
	self.Waypoints = {}
	self.Humanoid:MoveTo(self.Root.Position)
end

function Navigator.arrived(self: Navigator, distance: number?): boolean
	local target = self.Target
	return target ~= nil and flatDistance(target, self.Root.Position) <= (distance or ARRIVE_DISTANCE)
end

-- Avanza por el camino. Llamar a menudo (cada 0,1-0,25 s).
function Navigator.update(self: Navigator)
	local target = self.Target
	if not target then
		return
	end
	local now = os.clock()
	local position = self.Root.Position

	-- ¿Avanza? Si no, primero salta; si sigue sin avanzar, se aparta y pide otro camino.
	if (position - self.LastPosition).Magnitude > 1 then
		self.LastPosition = position
		self.LastProgressAt = now
		self.Unstucks = 0
	elseif now - self.LastProgressAt > STUCK_SECONDS and flatDistance(target, position) > ARRIVE_DISTANCE then
		self.LastProgressAt = now
		self.Unstucks += 1
		self.Humanoid.Jump = true
		if self.Unstucks >= 2 then
			local side = self.Root.CFrame.RightVector * (if math.random() < 0.5 then -6 else 6)
			self.Humanoid:MoveTo(position + side - self.Root.CFrame.LookVector * 3)
			self.Waypoints = {}
			self.ComputedAt = 0 -- fuerza un camino nuevo en el siguiente moveTo
			return
		end
	end

	if self.Direct or #self.Waypoints == 0 then
		self.Humanoid:MoveTo(target)
		return
	end
	local waypoint = self.Waypoints[self.Index]
	if not waypoint then
		self.Humanoid:MoveTo(target)
		return
	end
	-- Pasa al siguiente punto al llegar (en altura basta con estar cerca en el plano).
	if flatDistance(waypoint.Position, position) < 2.5 and math.abs(waypoint.Position.Y - position.Y) < 6 then
		self.Index += 1
		waypoint = self.Waypoints[self.Index]
		if not waypoint then
			self.Humanoid:MoveTo(target)
			return
		end
	end
	if waypoint.Action == Enum.PathWaypointAction.Jump then
		self.Humanoid.Jump = true
	end
	self.Humanoid:MoveTo(waypoint.Position)
end

return Navigator
