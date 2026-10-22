--!strict
-- Persecución y robo (GDD 5.4): el portador lleva la criatura con una correa; quien le toque
-- y mantenga el botón 1,5 s se la quita. Inmunidad tras robo, esprint, pase de relevo,
-- puerta del nido, tratos y traiciones. Todo se valida en el servidor.

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
local MonetizationService = require(script.Parent.MonetizationService)
local NestService = require(script.Parent.NestService)
local QuestService = require(script.Parent.QuestService)

export type ChaseResult = {
	Winner: Player?,
	Genes: Genes.GeneSet?,
	Partners: { Player },
}

local ChaseService = {}

local active = false
local carrier: Player? = nil
local genes: Genes.GeneSet? = nil
local model: Model? = nil
local immuneUntil = 0
local stealPrompt: ProximityPrompt? = nil
local pickupPrompt: ProximityPrompt? = nil
local carrierFx: { Instance } = {}
local carrierConnections: { RBXScriptConnection } = {}

local stealAttempts: { [Player]: number } = {}
local lastAttemptAt: { [Player]: number } = {}
local holdStart: { [Player]: number } = {}
local deals: { [Player]: { [Player]: boolean } } = {}
local pendingOffers: { [Player]: { From: Player, At: number } } = {}
local shieldCharges: { [Player]: number } = {}
local shieldsUsed: { [Player]: number } = {}
local sprintUntil: { [Player]: number } = {}
local sprintReadyAt: { [Player]: number } = {}
local stunnedUntil: { [Player]: number } = {}

-- Final de la persecución (ver Config.Chase y ChaseRules): asegurar y prórroga.
local homeStreak = 0
local secured = false
local overtime = false
local over = false

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

function ChaseService.carrier(): Player?
	return carrier
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
	humanoid.WalkSpeed = if stunned then 0 else Economy.walkSpeed(boots, player == carrier, sprinting, atHome, intruding)
	player:SetAttribute("Sprinting", sprinting)
	player:SetAttribute("Stunned", stunned)
	player:SetAttribute("Intruding", intruding)
end

-- Portador -------------------------------------------------------------------------------

local function clearCarrierFx()
	for _, instance in carrierFx do
		instance:Destroy()
	end
	table.clear(carrierFx)
	for _, connection in carrierConnections do
		connection:Disconnect()
	end
	table.clear(carrierConnections)
	if stealPrompt then
		stealPrompt:Destroy()
		stealPrompt = nil
	end
end

local drop: (position: Vector3?) -> ()

local function onStealTriggered(thief: Player)
	local current = carrier
	if not active or not current or thief == current then
		return
	end
	local now = os.clock()
	local began = holdStart[thief]
	holdStart[thief] = nil
	if (stunnedUntil[thief] or 0) > now then
		return -- aturdido o esperando la ventaja del elegido
	end
	-- El tiempo de pulsación lo mide el servidor: un cliente modificado no puede saltárselo.
	local atHome = NestService.isInsideOwnNest(current)
	local check = ChaseRules.canSteal(now, began, immuneUntil, distance(thief, current), atHome)
	if check == "immune" then
		AnnouncementService.player(thief, "¡El portador es inmune unos segundos!")
	end
	if check ~= "ok" then
		return
	end

	-- Escudo de Cáscara: bloquea un robo, como mucho uno por ronda.
	if (shieldCharges[current] or 0) > 0 and (shieldsUsed[current] or 0) < Config.Chase.ShieldsPerRound then
		shieldCharges[current] -= 1
		shieldsUsed[current] = (shieldsUsed[current] or 0) + 1
		immuneUntil = now + Config.Chase.ImmunityAfterSteal
		AnnouncementService.server(string.format("¡El Escudo de Cáscara de %s ha bloqueado un robo!", current.DisplayName), "info")
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
		updateSpeed(current)
	end
	ChaseService.setCarrier(thief)
end

function ChaseService.setCarrier(player: Player)
	local previous = carrier
	clearCarrierFx()
	if pickupPrompt then
		pickupPrompt:Destroy()
		pickupPrompt = nil
	end
	if previous and previous.Parent then
		previous:SetAttribute("IsCarrier", false)
		updateSpeed(previous)
	end

	carrier = player
	immuneUntil = os.clock() + Config.Chase.ImmunityAfterSteal
	-- Las pulsaciones empezadas sobre el portador anterior no cuentan para el nuevo.
	table.clear(holdStart)
	homeStreak = 0
	RoundState.set("SecureProgress", 0)
	player:SetAttribute("IsCarrier", true)
	RoundState.set("CarrierUserId", player.UserId)
	RoundState.set("ImmuneUntil", workspace:GetServerTimeNow() + Config.Chase.ImmunityAfterSteal)
	updateSpeed(player)

	local character = player.Character
	local root = rootOf(player)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid then
		drop(nil)
		return
	end

	-- Aura dorada.
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(255, 200, 40)
	highlight.OutlineColor = Color3.fromRGB(255, 240, 150)
	highlight.FillTransparency = 0.6
	highlight.Parent = character
	table.insert(carrierFx, highlight)

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 210, 60))
	sparkles.LightEmission = 1
	sparkles.Rate = 25
	sparkles.Lifetime = NumberRange.new(0.6, 1)
	sparkles.Speed = NumberRange.new(2, 4)
	sparkles.Size = NumberSequence.new(0.4, 0)
	sparkles.Parent = root
	table.insert(carrierFx, sparkles)

	-- Correa visual entre el portador y la criatura.
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
		table.insert(carrierFx, a0)
		table.insert(carrierFx, a1)
		table.insert(carrierFx, beam)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StealPrompt"
	prompt.ActionText = "Robar"
	prompt.ObjectText = "Criatura"
	prompt.HoldDuration = Config.Chase.StealHoldTime
	prompt.MaxActivationDistance = Config.Chase.StealRange
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = root
	stealPrompt = prompt

	prompt.PromptButtonHoldBegan:Connect(function(thief)
		holdStart[thief] = os.clock()
		local last = lastAttemptAt[thief] or 0
		if os.clock() - last > 2 then
			lastAttemptAt[thief] = os.clock()
			stealAttempts[thief] = (stealAttempts[thief] or 0) + 1
			DataService.addStat(thief, "StealAttempts", 1)
		end
	end)
	prompt.PromptButtonHoldEnded:Connect(function(thief)
		-- Soltar antes de tiempo anula el intento; si se completó, Triggered lo valida.
		local began = holdStart[thief]
		if began and os.clock() - began < Config.Chase.StealHoldTime - 0.15 then
			holdStart[thief] = nil
		end
	end)
	prompt.Triggered:Connect(onStealTriggered)

	table.insert(carrierConnections, humanoid.Died:Connect(function()
		if carrier == player then
			drop(root.Position)
		end
	end))
end

-- Si el portador muere o se va, la criatura queda en el suelo y cualquiera puede cogerla.
drop = function(position: Vector3?)
	clearCarrierFx()
	table.clear(holdStart)
	if carrier and carrier.Parent then
		carrier:SetAttribute("IsCarrier", false)
		updateSpeed(carrier)
	end
	carrier = nil
	RoundState.set("CarrierUserId", 0)
	if not model or not model.PrimaryPart then
		return
	end
	if position then
		model:PivotTo(CFrame.new(position + Vector3.new(0, 1, 0)))
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Coger criatura"
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart
	pickupPrompt = prompt
	prompt.Triggered:Connect(function(player)
		if active and not carrier then
			AnnouncementService.server(string.format("¡%s ha recogido la criatura!", player.DisplayName), "info")
			ChaseService.setCarrier(player)
		end
	end)
	AnnouncementService.server("¡La criatura está suelta! Corre a por ella.", "threshold")
end

-- Ciclo de persecución -------------------------------------------------------------------

function ChaseService.begin(chosen: Player, creatureGenes: Genes.GeneSet)
	active = true
	genes = creatureGenes
	local preview = Creature.new("round", creatureGenes, "Hatch", os.time())
	local built = CreatureModel.build(preview, 1)
	built.Name = "RoundCreature"
	built.Parent = workspace
	model = built
	local root = rootOf(chosen)
	if root then
		built:PivotTo(root.CFrame * CFrame.new(0, 1, 5))
	end
	homeStreak, secured, overtime, over = 0, false, false, false
	table.clear(stunnedUntil)
	ChaseService.setCarrier(chosen)
	-- El elegido empieza con más inmunidad y los demás tardan unos segundos en poder moverse.
	local now = os.clock()
	immuneUntil = now + Config.Chase.StartImmunitySeconds
	RoundState.set("ImmuneUntil", workspace:GetServerTimeNow() + Config.Chase.StartImmunitySeconds)
	for _, player in Players:GetPlayers() do
		if player ~= chosen then
			stunnedUntil[player] = now + Config.Chase.HeadStartSeconds
			updateSpeed(player)
		end
	end
end

-- ¿Ya está decidida? (asegurada, o alguien llegó a su nido en la prórroga)
function ChaseService.isOver(): boolean
	return over
end

-- Empieza la prórroga si hace falta: el portador no está en su nido. Devuelve si empezó.
function ChaseService.startOvertime(): boolean
	local current = carrier
	if over or Config.Chase.OvertimeSeconds <= 0 then
		return false
	end
	if current and NestService.isInsideOwnNest(current) then
		return false
	end
	overtime = true
	return true
end

function ChaseService.finish(): ChaseResult
	active = false
	local winner: Player? = nil
	if carrier and carrier.Parent and (secured or ChaseRules.carrierWins(NestService.isInsideOwnNest(carrier))) then
		winner = carrier
	end
	overtime = false
	RoundState.set("SecureProgress", 0)
	table.clear(stunnedUntil)
	local partners = if winner then ChaseService.partnersOf(winner) else {}
	local result: ChaseResult = { Winner = winner, Genes = genes, Partners = partners }

	clearCarrierFx()
	if pickupPrompt then
		pickupPrompt:Destroy()
		pickupPrompt = nil
	end
	if carrier and carrier.Parent then
		carrier:SetAttribute("IsCarrier", false)
	end
	carrier = nil
	genes = nil
	RoundState.set("CarrierUserId", 0)
	if model then
		model:Destroy()
		model = nil
	end
	for _, player in Players:GetPlayers() do
		sprintUntil[player] = nil
		updateSpeed(player)
	end
	return result
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
	table.clear(shieldsUsed)
	NestService.resetRound()
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

function ChaseService.init()
	MonetizationService.registerProduct("ShellShield", function(player)
		shieldCharges[player] = (shieldCharges[player] or 0) + 1
		AnnouncementService.player(player, "Escudo de Cáscara listo: bloqueará un robo.", "quest")
		return true
	end)
end

function ChaseService.start()
	Remotes.event("RespondDeal").OnServerEvent:Connect(respondDeal)

	Remotes.event("RequestSprint").OnServerEvent:Connect(function(player)
		if not active or player ~= carrier then
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

	-- Pase de relevo al aliado más cercano.
	Remotes.event("RequestPass").OnServerEvent:Connect(function(player)
		if not active or player ~= carrier then
			return
		end
		local best: Player? = nil
		local bestDistance = Config.Chase.PassRange
		for _, partner in ChaseService.partnersOf(player) do
			local d = distance(player, partner)
			if d <= bestDistance then
				best, bestDistance = partner, d
			end
		end
		if best then
			AnnouncementService.server(string.format("¡%s le pasa el relevo a %s!", player.DisplayName, best.DisplayName), "info")
			ChaseService.setCarrier(best)
		else
			AnnouncementService.player(player, "No hay ningún aliado cerca para pasarle el relevo.")
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
		if player == carrier then
			local root = rootOf(player)
			drop(if root then root.Position else nil)
		end
		stealAttempts[player] = nil
		lastAttemptAt[player] = nil
		holdStart[player] = nil
		pendingOffers[player] = nil
		shieldCharges[player] = nil
		shieldsUsed[player] = nil
		sprintUntil[player] = nil
		sprintReadyAt[player] = nil
		stunnedUntil[player] = nil
		deals[player] = nil
		for _, set in deals do
			set[player] = nil
		end
	end)

	-- La criatura sigue al portador; las velocidades se recalculan (esprint, botas).
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 1 / 20 then
			return
		end
		local elapsed = accumulator
		accumulator = 0
		local current = carrier
		if model and current then
			local root = rootOf(current)
			if root then
				local target = root.CFrame * CFrame.new(0, 0.5, 5)
				model:PivotTo(model:GetPivot():Lerp(target, 0.35))
			end
		end
		if not active or not current or over then
			return
		end
		-- Defensa en casa, asegurar y prórroga.
		local atHome = NestService.isInsideOwnNest(current)
		local prompt = stealPrompt
		local hold = ChaseRules.holdTime(atHome)
		if prompt and prompt.HoldDuration ~= hold then
			prompt.HoldDuration = hold
		end
		if overtime and ChaseRules.overtimeWin(true, atHome) then
			over = true
			AnnouncementService.server(string.format("⚡ ¡%s mete la criatura en su nido y gana la prórroga!", current.DisplayName), "rare")
			return
		end
		homeStreak = if atHome then homeStreak + elapsed else 0
		if Config.Chase.SecureSeconds > 0 then
			-- Solo se replica cuando cambia de forma visible (no 20 veces por segundo).
			local progress = math.clamp(homeStreak / Config.Chase.SecureSeconds, 0, 1)
			local sent = tonumber(RoundState.get("SecureProgress")) or 0
			if math.abs(progress - sent) >= 0.02 or (progress == 0 and sent ~= 0) then
				RoundState.set("SecureProgress", progress)
			end
		end
		if ChaseRules.isSecured(homeStreak) then
			secured = true
			over = true
			AnnouncementService.server(string.format("🔒 ¡%s ha asegurado la criatura en su nido!", current.DisplayName), "rare")
		end
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
