--!strict
-- Persecución y robo (GDD 5.4, revisado en el GDD v2). Puede haber varias criaturas a la vez:
-- cada una es una "persecución" con su portador, su modelo y su cuenta para asegurarla.
-- Robar: con Config.Chase.TapSteal, un toque empieza un tira y afloja que el servidor cuenta
-- mientras el ladrón siga cerca (se rompe si el portador se aleja); sin él, hay que mantener
-- el botón como antes. Escudos de Afinidad, inmunidad, esprint, relevo, puerta, tratos y
-- traiciones. Los zorros del bosque (ForestService) usan foxGrab. Todo se valida aquí.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ChaseRules = require(Shared.ChaseRules)
local Config = require(Shared.Config)
local Creature = require(Shared.Creature)
local CreatureModel = require(Shared.CreatureModel)
local Economy = require(Shared.Economy)
local Genes = require(Shared.Genes)
local Remotes = require(Shared.Remotes)
local RoundState = require(Shared.RoundState)

local AnnouncementService = require(script.Parent.AnnouncementService)
local DataService = require(script.Parent.DataService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local NestService = require(script.Parent.NestService)
local QuestService = require(script.Parent.QuestService)

-- Lo que pasó con una criatura (RoundService reparte los premios con esto).
export type Outcome = {
	Winner: Player?,
	Genes: Genes.GeneSet,
	Partners: { Player },
	Chosen: Player,
}

export type Start = { Chosen: Player, Genes: Genes.GeneSet }

type Chase = {
	Index: number,
	Genes: Genes.GeneSet,
	Chosen: Player,
	Carrier: Player?,
	Model: Model?,
	ImmuneUntil: number,
	StealPrompt: ProximityPrompt?,
	PickupPrompt: ProximityPrompt?,
	Fx: { Instance },
	Connections: { RBXScriptConnection },
	HomeStreak: number,
	Secured: boolean,
	Overtime: boolean,
	Done: boolean,
	Winner: Player?,
}

type Tug = { Chase: Chase, Carrier: Player, StartedAt: number }

local ChaseService = {}

local active = false
local chases: { Chase } = {}
local carrying: { [Player]: Chase } = {}
local wonThisRound: { [Player]: boolean } = {}

local stealAttempts: { [Player]: number } = {}
local lastAttemptAt: { [Player]: number } = {}
local holdStart: { [Player]: { Chase: Chase, At: number } } = {} -- modo "mantener el botón"
local tugs: { [Player]: Tug } = {} -- modo "toque": tira y afloja en curso
local shields: { [Player]: number } = {}
local deals: { [Player]: { [Player]: boolean } } = {}
local pendingOffers: { [Player]: { From: Player, At: number } } = {}
local sprintUntil: { [Player]: number } = {}
local sprintReadyAt: { [Player]: number } = {}
local stunnedUntil: { [Player]: number } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function distance(a: Player, b: Player): number
	local ra, rb = rootOf(a), rootOf(b)
	if not ra or not rb then
		return math.huge
	end
	return (ra.Position - rb.Position).Magnitude
end

function ChaseService.allied(a: Player, b: Player): boolean
	return deals[a] ~= nil and deals[a][b] == true
end

function ChaseService.partnersOf(player: Player): { Player }
	local list = {}
	for other, value in deals[player] or {} do
		if value and other.Parent then
			table.insert(list, other)
		end
	end
	return list
end

function ChaseService.stealAttempts(player: Player): number
	return stealAttempts[player] or 0
end

function ChaseService.isActive(): boolean
	return active
end

function ChaseService.isCarrier(player: Player): boolean
	return carrying[player] ~= nil
end

-- Réplica para los clientes: lista de portadores ("123,456") y el primero (compatibilidad).
local function publishCarriers()
	local ids: { string } = {}
	for _, chase in chases do
		if not chase.Done and chase.Carrier then
			table.insert(ids, tostring(chase.Carrier.UserId))
		end
	end
	RoundState.set("Carriers", table.concat(ids, ","))
	RoundState.set("CarrierUserId", tonumber(ids[1]) or 0)
end

-- Velocidad ------------------------------------------------------------------------------

local function updateSpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local profile = DataService.get(player)
	local boots = if profile then profile.Upgrades.Boots else 0
	local now = os.clock()
	local sprinting = (sprintUntil[player] or 0) > now
	local stunned = active and (stunnedUntil[player] or 0) > now
	-- Territorio: solo cuenta durante la persecución.
	local atHome, intruding = false, false
	local root = rootOf(player)
	if active and root then
		local here = NestService.nestIndexAt(root.Position)
		local own = player:GetAttribute("NestIndex")
		atHome = here ~= nil and here == own
		intruding = here ~= nil and here ~= own
	end
	humanoid.WalkSpeed = if stunned then 0 else Economy.walkSpeed(boots, carrying[player] ~= nil, sprinting, atHome, intruding)
	player:SetAttribute("Sprinting", sprinting)
	player:SetAttribute("Stunned", stunned)
	player:SetAttribute("Intruding", intruding)
end

-- Portador -------------------------------------------------------------------------------

local function clearFx(chase: Chase)
	for _, instance in chase.Fx do
		instance:Destroy()
	end
	table.clear(chase.Fx)
	for _, connection in chase.Connections do
		connection:Disconnect()
	end
	table.clear(chase.Connections)
	if chase.StealPrompt then
		chase.StealPrompt:Destroy()
		chase.StealPrompt = nil
	end
	if chase.PickupPrompt then
		chase.PickupPrompt:Destroy()
		chase.PickupPrompt = nil
	end
end

local function cancelTug(thief: Player, reason: string?)
	if tugs[thief] then
		tugs[thief] = nil
		if thief.Parent then
			thief:SetAttribute("TugEndsAt", nil)
			if reason then
				AnnouncementService.player(thief, reason)
			end
		end
	end
end

-- Quita todos los tira y afloja sobre esta persecución (cambió el portador o terminó).
local function cancelTugsOn(chase: Chase)
	for thief, tug in tugs do
		if tug.Chase == chase then
			cancelTug(thief, nil)
		end
	end
	for thief, hold in holdStart do
		if hold.Chase == chase then
			holdStart[thief] = nil
		end
	end
end

local function updateTugWarning(carrier: Player?)
	if not carrier or not carrier.Parent then
		return
	end
	local count = 0
	for _, tug in tugs do
		if tug.Carrier == carrier then
			count += 1
		end
	end
	carrier:SetAttribute("BeingTugged", count > 0)
end

local setCarrier: (chase: Chase, player: Player) -> ()
local drop: (chase: Chase, position: Vector3?) -> ()

-- Un robo que ya ha pasado todas las comprobaciones: escudo o cambio de portador.
local function completeSteal(chase: Chase, thief: Player)
	local current = chase.Carrier
	if not current then
		return
	end
	local now = os.clock()
	-- Escudo de Afinidad: se rompe y el robo no ocurre.
	if (shields[current] or 0) > 0 then
		shields[current] -= 1
		current:SetAttribute("Shields", shields[current])
		chase.ImmuneUntil = now + Config.Chase.ImmunityAfterSteal
		cancelTugsOn(chase)
		updateTugWarning(current)
		AnnouncementService.server(string.format("🛡️ ¡El escudo de %s ha bloqueado a %s!", current.DisplayName, thief.DisplayName), "info")
		return
	end
	if ChaseService.allied(current, thief) then
		deals[current][thief] = nil
		if deals[thief] then
			deals[thief][current] = nil
		end
		DataService.addStat(thief, "PactsBroken", 1)
		AnnouncementService.server(string.format("💔 ¡%s ha traicionado a %s!", thief.DisplayName, current.DisplayName), "rare")
	else
		AnnouncementService.server(string.format("¡%s le ha robado la criatura a %s!", thief.DisplayName, current.DisplayName), "info")
	end
	DataService.addStat(thief, "Steals", 1)
	LeaderboardService.addSteal(thief)
	QuestService.progress(thief, "Steal", 1)
	if Config.Chase.StunSeconds > 0 then
		stunnedUntil[current] = now + Config.Chase.StunSeconds
		AnnouncementService.player(current, string.format("¡Te la han robado! Aturdido %d s", Config.Chase.StunSeconds))
	end
	setCarrier(chase, thief)
end

-- ¿Puede este jugador intentar robar o recoger ahora? (no lleva otra, no ganó ya, no está aturdido)
local function canAct(player: Player): boolean
	return active and carrying[player] == nil and not wonThisRound[player] and (stunnedUntil[player] or 0) <= os.clock()
end

local function countAttempt(thief: Player)
	local now = os.clock()
	if now - (lastAttemptAt[thief] or 0) > 2 then
		lastAttemptAt[thief] = now
		stealAttempts[thief] = (stealAttempts[thief] or 0) + 1
		DataService.addStat(thief, "StealAttempts", 1)
	end
end

local function onStealTriggered(chase: Chase, thief: Player)
	local current = chase.Carrier
	if chase.Done or not current or thief == current or not canAct(thief) then
		return
	end
	local now = os.clock()
	local atHome = NestService.isInsideOwnNest(current)
	if Config.Chase.TapSteal then
		-- Un toque empieza el tira y afloja; el Heartbeat lo termina o lo rompe.
		if tugs[thief] then
			return
		end
		if now < chase.ImmuneUntil then
			AnnouncementService.player(thief, "¡El portador es inmune unos segundos!")
			return
		end
		if distance(thief, current) > Config.Chase.StealRange + ChaseRules.DistanceTolerance then
			return
		end
		countAttempt(thief)
		tugs[thief] = { Chase = chase, Carrier = current, StartedAt = now }
		thief:SetAttribute("TugEndsAt", workspace:GetServerTimeNow() + ChaseRules.holdTime(atHome))
		updateTugWarning(current)
		return
	end
	-- Modo clásico: el tiempo de pulsación lo mide el servidor.
	local hold = holdStart[thief]
	holdStart[thief] = nil
	local began = if hold and hold.Chase == chase then hold.At else nil
	local check = ChaseRules.canSteal(now, began, chase.ImmuneUntil, distance(thief, current), atHome)
	if check == "immune" then
		AnnouncementService.player(thief, "¡El portador es inmune unos segundos!")
	end
	if check == "ok" then
		completeSteal(chase, thief)
	end
end

setCarrier = function(chase: Chase, player: Player)
	local previous = chase.Carrier
	clearFx(chase)
	cancelTugsOn(chase)
	if previous then
		carrying[previous] = nil
		if previous.Parent then
			previous:SetAttribute("IsCarrier", false)
			previous:SetAttribute("SecureProgress", nil)
			previous:SetAttribute("BeingTugged", false)
			updateSpeed(previous)
		end
	end

	chase.Carrier = player
	carrying[player] = chase
	chase.ImmuneUntil = os.clock() + Config.Chase.ImmunityAfterSteal
	chase.HomeStreak = 0
	player:SetAttribute("IsCarrier", true)
	player:SetAttribute("ImmuneUntil", workspace:GetServerTimeNow() + Config.Chase.ImmunityAfterSteal)
	player:SetAttribute("SecureProgress", 0)
	publishCarriers()
	updateSpeed(player)

	local character = player.Character
	local root = rootOf(player)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid then
		drop(chase, nil)
		return
	end

	-- Aura dorada.
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(255, 200, 40)
	highlight.OutlineColor = Color3.fromRGB(255, 240, 150)
	highlight.FillTransparency = 0.6
	highlight.Parent = character
	table.insert(chase.Fx, highlight)

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 210, 60))
	sparkles.LightEmission = 1
	sparkles.Rate = 25
	sparkles.Lifetime = NumberRange.new(0.6, 1)
	sparkles.Speed = NumberRange.new(2, 4)
	sparkles.Size = NumberSequence.new(0.4, 0)
	sparkles.Parent = root
	table.insert(chase.Fx, sparkles)

	-- Correa visual entre el portador y la criatura.
	local model = chase.Model
	if model and model.PrimaryPart then
		local a0 = Instance.new("Attachment")
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Parent = model.PrimaryPart
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90))
		beam.Width0 = 0.3
		beam.Width1 = 0.3
		beam.LightEmission = 1
		beam.FaceCamera = true
		beam.Parent = root
		table.insert(chase.Fx, a0)
		table.insert(chase.Fx, a1)
		table.insert(chase.Fx, beam)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StealPrompt"
	prompt.ActionText = "Robar"
	prompt.ObjectText = "Criatura"
	-- Con robo por toque, el prompt es instantáneo: el tiempo lo cuenta el servidor.
	prompt.HoldDuration = if Config.Chase.TapSteal then 0 else Config.Chase.StealHoldTime
	prompt.MaxActivationDistance = Config.Chase.StealRange
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = root
	chase.StealPrompt = prompt

	if not Config.Chase.TapSteal then
		prompt.PromptButtonHoldBegan:Connect(function(thief)
			holdStart[thief] = { Chase = chase, At = os.clock() }
			countAttempt(thief)
		end)
		prompt.PromptButtonHoldEnded:Connect(function(thief)
			-- Soltar antes de tiempo anula el intento; si se completó, Triggered lo valida.
			local hold = holdStart[thief]
			if hold and os.clock() - hold.At < Config.Chase.StealHoldTime - 0.15 then
				holdStart[thief] = nil
			end
		end)
	end
	prompt.Triggered:Connect(function(thief)
		onStealTriggered(chase, thief)
	end)

	table.insert(chase.Connections, humanoid.Died:Connect(function()
		if chase.Carrier == player then
			drop(chase, root.Position)
		end
	end))
end

-- Sin portador (murió, se fue o un zorro se la tiró): la criatura queda en el suelo y
-- cualquiera que no lleve otra puede cogerla.
drop = function(chase: Chase, position: Vector3?)
	clearFx(chase)
	cancelTugsOn(chase)
	local previous = chase.Carrier
	if previous then
		carrying[previous] = nil
		if previous.Parent then
			previous:SetAttribute("IsCarrier", false)
			previous:SetAttribute("SecureProgress", nil)
			previous:SetAttribute("BeingTugged", false)
			updateSpeed(previous)
		end
	end
	chase.Carrier = nil
	publishCarriers()
	local model = chase.Model
	if not model or not model.PrimaryPart then
		return
	end
	if position then
		model:PivotTo(CFrame.new(position + Vector3.new(0, 1, 0)))
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ActionText = "Coger criatura"
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart
	chase.PickupPrompt = prompt
	prompt.Triggered:Connect(function(player)
		if not chase.Done and not chase.Carrier and canAct(player) then
			AnnouncementService.server(string.format("¡%s ha recogido la criatura!", player.DisplayName), "info")
			setCarrier(chase, player)
		end
	end)
	AnnouncementService.server("¡Una criatura está suelta! Corre a por ella.", "threshold")
end

-- Termina una persecución (asegurada, ganada en la prórroga o al acabar el tiempo).
local function settle(chase: Chase, winner: Player?)
	if chase.Done then
		return
	end
	chase.Done = true
	chase.Winner = winner
	clearFx(chase)
	cancelTugsOn(chase)
	local carrier = chase.Carrier
	if carrier then
		carrying[carrier] = nil
		if carrier.Parent then
			carrier:SetAttribute("IsCarrier", false)
			carrier:SetAttribute("SecureProgress", nil)
			carrier:SetAttribute("BeingTugged", false)
			updateSpeed(carrier)
		end
	end
	if winner then
		wonThisRound[winner] = true
	end
	if chase.Model then
		chase.Model:Destroy()
		chase.Model = nil
	end
	publishCarriers()
end

-- Ciclo de persecución -------------------------------------------------------------------

-- Empieza una persecución por cada criatura. shieldsOf da los escudos de cada jugador
-- (los calcula RoundService con la Afinidad de la ronda).
function ChaseService.begin(starts: { Start }, shieldsOf: (Player) -> number)
	active = true
	table.clear(chases)
	table.clear(carrying)
	table.clear(wonThisRound)
	table.clear(stunnedUntil)
	table.clear(tugs)
	table.clear(holdStart)
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		shields[player] = shieldsOf(player)
		player:SetAttribute("Shields", shields[player])
	end
	for index, start in starts do
		local preview = Creature.new("round" .. index, start.Genes, "Hatch", os.time())
		local built = CreatureModel.build(preview, 1)
		built.Name = "RoundCreature"
		built:SetAttribute("ChaseIndex", index)
		CollectionService:AddTag(built, "RoundCreature")
		built.Parent = workspace
		local root = rootOf(start.Chosen)
		if root then
			built:PivotTo(root.CFrame * CFrame.new(0, 1, 5))
		end
		local chase: Chase = {
			Index = index,
			Genes = start.Genes,
			Chosen = start.Chosen,
			Carrier = nil,
			Model = built,
			ImmuneUntil = 0,
			StealPrompt = nil,
			PickupPrompt = nil,
			Fx = {},
			Connections = {},
			HomeStreak = 0,
			Secured = false,
			Overtime = false,
			Done = false,
			Winner = nil,
		}
		table.insert(chases, chase)
		setCarrier(chase, start.Chosen)
		-- Los elegidos empiezan con más inmunidad.
		chase.ImmuneUntil = now + Config.Chase.StartImmunitySeconds
		start.Chosen:SetAttribute("ImmuneUntil", workspace:GetServerTimeNow() + Config.Chase.StartImmunitySeconds)
	end
	-- Los demás tardan unos segundos en poder moverse (ventaja de los elegidos).
	for _, player in Players:GetPlayers() do
		if not carrying[player] then
			stunnedUntil[player] = now + Config.Chase.HeadStartSeconds
			updateSpeed(player)
		end
	end
end

-- ¿Ya están decididas todas? (aseguradas, o ganadas en la prórroga)
function ChaseService.isOver(): boolean
	for _, chase in chases do
		if not chase.Done then
			return false
		end
	end
	return true
end

-- Se acaba el tiempo: gana quien tenga la criatura en su nido; las demás pasan a la
-- prórroga (gol de oro). Devuelve si hay prórroga.
function ChaseService.startOvertime(): boolean
	local any = false
	for _, chase in chases do
		if not chase.Done then
			local carrier = chase.Carrier
			if carrier and NestService.isInsideOwnNest(carrier) then
				settle(chase, carrier)
			elseif Config.Chase.OvertimeSeconds > 0 then
				chase.Overtime = true
				any = true
			end
		end
	end
	return any
end

function ChaseService.finish(): { Outcome }
	active = false
	local outcomes: { Outcome } = {}
	for _, chase in chases do
		if not chase.Done then
			local carrier = chase.Carrier
			local winner = if carrier and carrier.Parent and ChaseRules.carrierWins(NestService.isInsideOwnNest(carrier)) then carrier else nil
			settle(chase, winner)
		end
		local winner: Player? = if chase.Winner and chase.Winner.Parent then chase.Winner else nil
		local outcome: Outcome = {
			Winner = winner,
			Genes = chase.Genes,
			Partners = if winner then ChaseService.partnersOf(winner) else {},
			Chosen = chase.Chosen,
		}
		table.insert(outcomes, outcome)
	end
	table.clear(chases)
	table.clear(carrying)
	table.clear(stunnedUntil)
	table.clear(tugs)
	publishCarriers()
	for _, player in Players:GetPlayers() do
		sprintUntil[player] = nil
		player:SetAttribute("Shields", nil)
		player:SetAttribute("TugEndsAt", nil)
		updateSpeed(player)
	end
	return outcomes
end

-- Los tratos se cumplen al ganar: el aliado recibe su parte (GDD 5.4).
function ChaseService.keepPacts(winner: Player)
	for _, partner in ChaseService.partnersOf(winner) do
		DataService.addStat(partner, "PactsKept", 1)
		DataService.addStat(winner, "PactsKept", 1)
	end
end

function ChaseService.resetRound()
	table.clear(stealAttempts)
	table.clear(lastAttemptAt)
	table.clear(holdStart)
	table.clear(deals)
	table.clear(pendingOffers)
	NestService.resetRound()
end

-- Para los zorros del bosque y la depuración ---------------------------------------------

export type Target = { Index: number, Carrier: Player, Position: Vector3 }

-- Criaturas que alguien lleva ahora mismo (a por ellas van los zorros).
function ChaseService.targets(): { Target }
	local list: { Target } = {}
	for _, chase in chases do
		local carrier = chase.Carrier
		local root = carrier and rootOf(carrier)
		if not chase.Done and carrier and root then
			table.insert(list, { Index = chase.Index, Carrier = carrier, Position = root.Position })
		end
	end
	return list
end

local function chaseByIndex(index: number): Chase?
	for _, chase in chases do
		if chase.Index == index then
			return chase
		end
	end
	return nil
end

-- Un zorro completa su tira y afloja (ForestService mide el tiempo con ChaseRules). La
-- criatura cae al suelo; nunca se la queda. Devuelve "dropped", "shield" o "no".
function ChaseService.foxGrab(index: number, foxPosition: Vector3, startedAt: number): string
	local chase = chaseByIndex(index)
	local carrier = chase and chase.Carrier
	local root = carrier and rootOf(carrier)
	if not chase or chase.Done or not carrier or not root then
		return "no"
	end
	local now = os.clock()
	local atHome = NestService.isInsideOwnNest(carrier)
	local check = ChaseRules.canSteal(now, startedAt, chase.ImmuneUntil, (root.Position - foxPosition).Magnitude, atHome)
	if check ~= "ok" then
		return "no"
	end
	if (shields[carrier] or 0) > 0 then
		shields[carrier] -= 1
		carrier:SetAttribute("Shields", shields[carrier])
		chase.ImmuneUntil = now + Config.Chase.ImmunityAfterSteal
		AnnouncementService.server(string.format("🛡️ ¡El escudo de %s ha espantado a un zorro!", carrier.DisplayName), "info")
		return "shield"
	end
	stunnedUntil[carrier] = now + Config.Chase.StunSeconds
	AnnouncementService.server(string.format("🦊 ¡Un zorro le ha tirado la criatura al suelo a %s!", carrier.DisplayName), "threshold")
	drop(chase, root.Position)
	return "dropped"
end

-- Depuración (solo Studio): quedarse la primera criatura activa.
function ChaseService.debugTake(player: Player)
	for _, chase in chases do
		if not chase.Done and chase.Carrier ~= player and not carrying[player] then
			setCarrier(chase, player)
			return
		end
	end
end

-- Tratos ---------------------------------------------------------------------------------

local function setupDealPrompt(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DealPrompt"
	prompt.ActionText = "Ofrecer trato"
	prompt.ObjectText = player.DisplayName
	prompt.KeyboardKeyCode = Enum.KeyCode.T
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = Config.Deal.OfferRange
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, 60)
	prompt.Parent = root

	prompt.Triggered:Connect(function(offerer)
		if offerer == player or ChaseService.allied(offerer, player) then
			return
		end
		local phase = RoundState.phase()
		if phase ~= "Incubation" and phase ~= "Chase" and phase ~= "Overtime" and phase ~= "Hatch" then
			return
		end
		pendingOffers[player] = { From = offerer, At = os.clock() }
		Remotes.event("DealOffered"):FireClient(player, offerer.UserId, offerer.DisplayName)
		AnnouncementService.player(offerer, "Trato ofrecido a " .. player.DisplayName)
	end)
end

local function respondDeal(player: Player, fromUserId: any, accept: any)
	local offer = pendingOffers[player]
	if not offer or offer.From.UserId ~= fromUserId or os.clock() - offer.At > 20 then
		return
	end
	pendingOffers[player] = nil
	local from = offer.From
	if accept ~= true or not from.Parent then
		AnnouncementService.player(from, player.DisplayName .. " ha rechazado el trato.")
		return
	end
	deals[player] = deals[player] or {}
	deals[from] = deals[from] or {}
	deals[player][from] = true
	deals[from][player] = true
	local text = "🤝 Trato hecho con %s: si uno gana, el otro se lleva el 30 %% del polvo y una copia."
	AnnouncementService.player(player, string.format(text, from.DisplayName), "quest")
	AnnouncementService.player(from, string.format(text, player.DisplayName), "quest")
end

-- Bucle: criaturas que siguen al portador, tira y afloja, asegurar y prórroga --------------

local function step(elapsed: number)
	local now = os.clock()
	-- Las criaturas siguen a su portador.
	for _, chase in chases do
		local carrier = chase.Carrier
		local model = chase.Model
		local root = carrier and rootOf(carrier)
		if model and root then
			local target = root.CFrame * CFrame.new(0, 0.5, 5)
			model:PivotTo(model:GetPivot():Lerp(target, 0.35))
		end
	end
	if not active then
		return
	end

	-- Tira y afloja (robo por toque): se rompe si el portador se aleja.
	for thief, tug in tugs do
		local chase = tug.Chase
		local carrier = chase.Carrier
		if chase.Done or carrier ~= tug.Carrier or not carrier or not thief.Parent then
			cancelTug(thief, nil)
			continue
		end
		local d = distance(thief, carrier)
		if d > Config.Chase.StealRange + ChaseRules.DistanceTolerance or (stunnedUntil[thief] or 0) > now then
			cancelTug(thief, "¡Se te ha escapado!")
			updateTugWarning(carrier)
			continue
		end
		local atHome = NestService.isInsideOwnNest(carrier)
		if now - tug.StartedAt >= ChaseRules.holdTime(atHome) then
			local check = ChaseRules.canSteal(now, tug.StartedAt, chase.ImmuneUntil, d, atHome)
			cancelTug(thief, nil)
			updateTugWarning(carrier)
			if check == "ok" then
				completeSteal(chase, thief)
			end
		end
	end

	for _, chase in chases do
		local carrier = chase.Carrier
		if chase.Done or not carrier then
			continue
		end
		-- Defensa en casa: el prompt clásico tarda más dentro del nido.
		local atHome = NestService.isInsideOwnNest(carrier)
		local prompt = chase.StealPrompt
		if prompt and not Config.Chase.TapSteal then
			local hold = ChaseRules.holdTime(atHome)
			if prompt.HoldDuration ~= hold then
				prompt.HoldDuration = hold
			end
		end
		if chase.Overtime and ChaseRules.overtimeWin(true, atHome) then
			AnnouncementService.server(string.format("⚡ ¡%s mete la criatura en su nido y gana la prórroga!", carrier.DisplayName), "rare")
			settle(chase, carrier)
			continue
		end
		chase.HomeStreak = if atHome then chase.HomeStreak + elapsed else 0
		if Config.Chase.SecureSeconds > 0 then
			-- Solo se replica cuando cambia de forma visible (no 20 veces por segundo).
			local progress = math.clamp(chase.HomeStreak / Config.Chase.SecureSeconds, 0, 1)
			local sent = tonumber(carrier:GetAttribute("SecureProgress")) or 0
			if math.abs(progress - sent) >= 0.02 or (progress == 0 and sent ~= 0) then
				carrier:SetAttribute("SecureProgress", progress)
			end
		end
		if ChaseRules.isSecured(chase.HomeStreak) then
			chase.Secured = true
			AnnouncementService.server(string.format("🔒 ¡%s ha asegurado la criatura en su nido!", carrier.DisplayName), "rare")
			settle(chase, carrier)
		end
	end
end

function ChaseService.init() end

function ChaseService.start()
	Remotes.event("RespondDeal").OnServerEvent:Connect(respondDeal)

	Remotes.event("RequestSprint").OnServerEvent:Connect(function(player)
		if not active or not carrying[player] then
			return
		end
		local now = os.clock()
		if now < (sprintReadyAt[player] or 0) then
			return
		end
		sprintUntil[player] = now + Config.Chase.SprintDuration
		sprintReadyAt[player] = now + Config.Chase.SprintCooldown
		player:SetAttribute("SprintReadyAt", workspace:GetServerTimeNow() + Config.Chase.SprintCooldown)
		updateSpeed(player)
	end)

	-- Pase de relevo al aliado más cercano que no lleve ya otra criatura.
	Remotes.event("RequestPass").OnServerEvent:Connect(function(player)
		local chase = carrying[player]
		if not active or not chase then
			return
		end
		local best: Player? = nil
		local bestDistance = Config.Chase.PassRange
		for _, partner in ChaseService.partnersOf(player) do
			local d = distance(player, partner)
			if d <= bestDistance and canAct(partner) then
				best, bestDistance = partner, d
			end
		end
		if best then
			AnnouncementService.server(string.format("¡%s le pasa el relevo a %s!", player.DisplayName, best.DisplayName), "info")
			setCarrier(chase, best)
		else
			AnnouncementService.player(player, "No hay ningún aliado libre cerca para pasarle el relevo.")
		end
	end)

	Remotes.event("RequestCloseDoor").OnServerEvent:Connect(function(player)
		if not active then
			return
		end
		if NestService.closeDoor(player) then
			AnnouncementService.player(player, "Puerta del nido cerrada 10 segundos.")
		else
			AnnouncementService.player(player, "Ya usaste la puerta en esta ronda.")
		end
	end)

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			setupDealPrompt(player, character)
			task.defer(updateSpeed, player)
		end)
		if player.Character then
			task.spawn(setupDealPrompt, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local chase = carrying[player]
		if chase then
			local root = rootOf(player)
			drop(chase, if root then root.Position else nil)
		end
		cancelTug(player, nil)
		stealAttempts[player] = nil
		lastAttemptAt[player] = nil
		holdStart[player] = nil
		pendingOffers[player] = nil
		shields[player] = nil
		sprintUntil[player] = nil
		sprintReadyAt[player] = nil
		stunnedUntil[player] = nil
		wonThisRound[player] = nil
		deals[player] = nil
		for _, set in deals do
			set[player] = nil
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 1 / 20 then
			return
		end
		local elapsed = accumulator
		accumulator = 0
		step(elapsed)
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, player in Players:GetPlayers() do
				updateSpeed(player)
			end
		end
	end)
end

return ChaseService
