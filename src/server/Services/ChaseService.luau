--!strict
-- Persecución y robo (GDD 5.4): el portador lleva la criatura con una correa; quien le toque
-- y mantenga el botón 1,5 s se la quita. Inmunidad tras robo, esprint, pase de relevo,
-- puerta del nido, tratos y traiciones. Todo se valida en el servidor.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Creature = require(Shared.Creature)
local CreatureModel = require(Shared.CreatureModel)
local Economy = require(Shared.Economy)
local Genes = require(Shared.Genes)
local Remotes = require(Shared.Remotes)
local RoundState = require(Shared.RoundState)

local AnnouncementService = require(script.Parent.AnnouncementService)
local DataService = require(script.Parent.DataService)
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
	local sprinting = (sprintUntil[player] or 0) > os.clock()
	humanoid.WalkSpeed = Economy.walkSpeed(boots, player == carrier, sprinting)
	player:SetAttribute("Sprinting", sprinting)
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
	-- El tiempo de pulsación lo mide el servidor: un cliente modificado no puede saltárselo.
	if not began or now - began < Config.Chase.StealHoldTime - 0.15 then
		return
	end
	if now < immuneUntil then
		AnnouncementService.player(thief, "¡El portador es inmune unos segundos!")
		return
	end
	if distance(thief, current) > Config.Chase.StealRange + 3 then
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
	QuestService.progress(thief, "Steal", 1)
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
	ChaseService.setCarrier(chosen)
end

function ChaseService.finish(): ChaseResult
	active = false
	local winner: Player? = nil
	if carrier and carrier.Parent and NestService.isInsideOwnNest(carrier) then
		winner = carrier
	end
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
		if phase ~= "Incubation" and phase ~= "Chase" and phase ~= "Hatch" then
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
		accumulator = 0
		local current = carrier
		if model and current then
			local root = rootOf(current)
			if root then
				local target = root.CFrame * CFrame.new(0, 0.5, 5)
				model:PivotTo(model:GetPivot():Lerp(target, 0.35))
			end
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
