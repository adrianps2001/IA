--!strict
-- Piloto automático para probar en Roblox Studio (docs/PRUEBAS.md). Con Test → Clients and
-- Servers y varios jugadores, cada ventana juega sola: recoge Calor, deposita, persigue,
-- roba con el prompt real, defiende su nido y usa la tienda del nido. Como son jugadores de
-- verdad, recorre exactamente el mismo código que una persona (remotos, prompts y
-- validaciones del servidor). F8 activa o desactiva el piloto en esa ventana.
-- Solo funciona dentro de Studio (Testing.enabled("Autopilot")).

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local RoundState = require(Shared.RoundState)
local Testing = require(Shared.Testing)

local UI = require(script.Parent.Parent.UI)

local player = Players.LocalPlayer

local AutopilotController = {}

local enabled = false
local label: TextLabel
local blacklist: { [Instance]: number } = {} -- objetivos a los que no se pudo llegar
local target: BasePart? = nil
local lastPosition = Vector3.zero
local stuckSince = 0
local holding: ProximityPrompt? = nil
local holdUntil = 0
local doorUsedRound = -1
local shopRound = -1
local lootPlanRound = -1 -- Noche de Saqueo: en qué ronda decidió si saquea
local wantsLoot = false

local function rootOf(p: Player): BasePart?
	local character = p.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function humanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function mapChild(name: string): Instance?
	local map = workspace:FindFirstChild("Map")
	return map and map:FindFirstChild(name)
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function moveTo(position: Vector3)
	local h = humanoid()
	if h then
		h:MoveTo(position)
	end
end

-- Mantiene pulsado un prompt real durante unos segundos (como una persona con la tecla E).
local function hold(prompt: ProximityPrompt, seconds: number)
	if holding == prompt then
		return
	end
	if holding then
		holding:InputHoldEnd()
	end
	holding = prompt
	holdUntil = os.clock() + seconds
	prompt:InputHoldBegin()
end

local function release()
	if holding then
		holding:InputHoldEnd()
		holding = nil
	end
end

local function nearestSource(root: BasePart): BasePart?
	local folder = mapChild("HeatSources")
	if not folder then
		return nil
	end
	local best: BasePart? = nil
	local bestScore = math.huge
	local now = os.clock()
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") and part.Transparency < 1 and part.Name ~= "Geyser" and (blacklist[part] or 0) < now then
			local value = if part.Name == "LuckyBlock" then 4 else 1
			local score = flat(part.Position, root.Position) / value
			if score < bestScore then
				best, bestScore = part, score
			end
		end
	end
	return best
end

-- Noche de Saqueo: una vez por ronda, ir a por una criatura de un nido ajeno.
local function tryLoot(root: BasePart): boolean
	local round = tonumber(RoundState.get("Round")) or 0
	if lootPlanRound ~= round then
		lootPlanRound = round
		wantsLoot = math.random() < 0.4
	end
	if not RoundState.get("LootNight") or not wantsLoot then
		return false
	end
	local best: ProximityPrompt? = nil
	local bestDistance = math.huge
	for _, prompt in CollectionService:GetTagged("LootPrompt") do
		local model = prompt:FindFirstAncestorOfClass("Model")
		if prompt:IsA("ProximityPrompt") and prompt.Enabled and model and model:GetAttribute("OwnerUserId") ~= player.UserId then
			local d = flat(model:GetPivot().Position, root.Position)
			if d < bestDistance then
				best, bestDistance = prompt, d
			end
		end
	end
	if not best then
		return false
	end
	local model = best:FindFirstAncestorOfClass("Model") :: Model
	moveTo(model:GetPivot().Position)
	if bestDistance < Config.Events.LootNight.MaxDistance - 4 then
		hold(best, best.HoldDuration + 0.3)
		wantsLoot = false -- un intento por ronda, salga bien o no
	end
	return true
end

local function incubation(root: BasePart)
	local heat = tonumber(player:GetAttribute("Heat")) or 0
	local capacity = tonumber(player:GetAttribute("BagCapacity")) or 100
	local offering = player:GetAttribute("Offering")
	local egg = mapChild("Egg")
	if not egg or not egg:IsA("BasePart") then
		return
	end
	local toEgg = flat(egg.Position, root.Position)
	local timeLeft = RoundState.timeLeft()
	local wantsDeposit = heat >= capacity * 0.7
		or (heat > 0 and timeLeft < toEgg / 16 + 6)
		or (type(offering) == "string" and offering ~= "")
	if wantsDeposit then
		target = nil
		moveTo(egg.Position)
		local prompt = egg:FindFirstChild("DepositPrompt")
		if toEgg < Config.Heat.DepositRadius - 4 and prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
			prompt:InputHoldBegin()
			task.delay(0.1, function()
				prompt:InputHoldEnd()
			end)
		end
		return
	end
	-- Si hay un géiser al lado, probar a activarlo (hace falta otro jugador).
	local sources = mapChild("HeatSources")
	if sources then
		for _, geyser in sources:GetChildren() do
			if geyser.Name == "Geyser" and geyser:IsA("BasePart") and flat(geyser.Position, root.Position) < 9 then
				local prompt = geyser:FindFirstChildOfClass("ProximityPrompt")
				if prompt and math.random() < 0.2 then
					hold(prompt, prompt.HoldDuration + 0.1)
				end
			end
		end
	end
	if not target or not target.Parent or target.Transparency >= 1 then
		target = nearestSource(root)
	end
	if target then
		moveTo(target.Position)
	end
end

local function chase(root: BasePart)
	if player:GetAttribute("IsCarrier") then
		release()
		local nest = player:GetAttribute("NestPosition")
		if typeof(nest) ~= "Vector3" then
			return
		end
		-- ¿Hay ladrones cerca?
		local nearest = math.huge
		for _, other in Players:GetPlayers() do
			local r = if other ~= player then rootOf(other) else nil
			if r then
				nearest = math.min(nearest, flat(r.Position, root.Position))
			end
		end
		if nearest < 15 then
			Remotes.event("RequestSprint"):FireServer()
		end
		local atHome = flat(nest, root.Position) < Config.Nest.Count -- ~dentro de la parcela (26 studs)
		if atHome then
			local round = tonumber(RoundState.get("Round")) or 0
			if nearest < 22 and doorUsedRound ~= round then
				doorUsedRound = round
				Remotes.event("RequestCloseDoor"):FireServer()
			end
			-- Moverse dentro del nido para esquivar.
			moveTo(nest + Vector3.new(math.random(-8, 8), 0, math.random(-8, 8)))
		else
			moveTo(nest)
		end
		return
	end

	-- Puede haber varias criaturas: una suelta cerca es lo primero; si no, el portador más cercano.
	for _, creature in CollectionService:GetTagged("RoundCreature") do
		local body = if creature:IsA("Model") then creature.PrimaryPart else nil
		local pickup = body and body:FindFirstChild("PickupPrompt")
		if body and pickup and pickup:IsA("ProximityPrompt") and flat(body.Position, root.Position) < 60 then
			moveTo(body.Position)
			if flat(body.Position, root.Position) < 8 then
				hold(pickup, pickup.HoldDuration + 0.2)
			end
			return
		end
	end
	local carrierRoot: BasePart? = nil
	local best = math.huge
	for _, id in string.split(tostring(RoundState.get("Carriers") or ""), ",") do
		local carrier = Players:GetPlayerByUserId(tonumber(id) or 0)
		local r = if carrier and carrier ~= player then rootOf(carrier) else nil
		if r and flat(r.Position, root.Position) < best then
			carrierRoot, best = r, flat(r.Position, root.Position)
		end
	end
	if not carrierRoot then
		return
	end
	moveTo(carrierRoot.Position)
	local distance = flat(carrierRoot.Position, root.Position)
	local prompt = carrierRoot:FindFirstChild("StealPrompt")
	-- Con robo por toque basta un toque; luego hay que quedarse cerca (el servidor cuenta).
	if prompt and prompt:IsA("ProximityPrompt") and distance < Config.Chase.StealRange - 1 and not player:GetAttribute("TugEndsAt") then
		hold(prompt, prompt.HoldDuration + 0.2)
	elseif holding and distance > Config.Chase.StealRange then
		release()
	end
end

-- Al final de la ronda usa el nido como lo haría un jugador: mejoras, huevos, recoger.
local function useShop()
	local round = tonumber(RoundState.get("Round")) or 0
	if shopRound == round then
		return
	end
	shopRound = round
	Remotes.event("RequestCollectEggs"):FireServer()
	Remotes.event("RequestBuyEgg"):FireServer()
	local names = { "Bag", "Boots", "Nest", "Incubator" }
	Remotes.event("RequestUpgrade"):FireServer(names[math.random(1, #names)])
end

local function tick()
	if holding and os.clock() >= holdUntil then
		release()
	end
	if not enabled then
		return
	end
	local root = rootOf(player)
	if not root then
		return
	end
	-- Atascado (un árbol, una pared): saltar y olvidar ese objetivo un rato.
	if (root.Position - lastPosition).Magnitude < 0.5 then
		if os.clock() - stuckSince > 2.5 then
			local h = humanoid()
			if h then
				h.Jump = true
			end
			if target then
				blacklist[target] = os.clock() + 8
				target = nil
			end
			stuckSince = os.clock()
		end
	else
		stuckSince = os.clock()
	end
	lastPosition = root.Position

	local phase = RoundState.phase()
	if phase == "Incubation" then
		incubation(root)
	elseif phase == "Chase" or phase == "Overtime" then
		chase(root)
	elseif phase == "Results" then
		release()
		useShop()
	elseif phase == "Loot" then
		-- Noche de Saqueo (fase propia): unos saquean, otros vuelven a defender su nido.
		if not tryLoot(root) then
			local nest = player:GetAttribute("NestPosition")
			if typeof(nest) == "Vector3" then
				moveTo(nest)
			end
		end
	else
		release()
	end
end

local function setEnabled(value: boolean)
	enabled = value
	label.Text = if value then "🤖 Piloto automático ACTIVADO (F8)" else "🎮 Controlas tú (F8: piloto automático)"
	label.TextColor3 = if value then UI.Colors.Gold else UI.Colors.Muted
	if not value then
		release()
		local root = rootOf(player)
		if root then
			moveTo(root.Position)
		end
	end
end

function AutopilotController.start()
	if not Testing.enabled("Autopilot") then
		return
	end
	local gui = UI.screen("Autopilot", 9)
	label = UI.label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.fromOffset(360, 26),
	}, gui)

	-- En Studio los jugadores de prueba se llaman Player1, Player2...: Player1 eres tú.
	local isFirst = player.Name == "Player1"
	setEnabled(not isFirst or Config.Testing.AutopilotOnFirstPlayer)

	ContextActionService:BindAction("Autopilot", function(_, state)
		if state == Enum.UserInputState.Begin then
			setEnabled(not enabled)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.F8)

	-- Bandada: acepta la mitad de las invitaciones.
	Remotes.event("PartyInvited").OnClientEvent:Connect(function(fromUserId: number)
		if enabled then
			task.delay(1, function()
				Remotes.event("PartyRespond"):FireServer(fromUserId, math.random() < 0.5)
			end)
		end
	end)

	-- Intercambio: acepta, ofrece su peor criatura y confirma en cuanto puede. Sirve para
	-- probar el intercambio entre tú y un bot.
	Remotes.event("TradeRequested").OnClientEvent:Connect(function(fromUserId: number)
		if enabled then
			task.delay(1, function()
				Remotes.event("TradeRespond"):FireServer(fromUserId, true)
			end)
		end
	end)
	Remotes.event("TradeUpdated").OnClientEvent:Connect(function(view)
		if not enabled or not view then
			return
		end
		task.delay(1, function()
			if #view.Mine == 0 then
				local ok, profile = pcall(function()
					return Remotes.func("GetProfile"):InvokeServer()
				end)
				local creatures = if ok and profile then profile.Creatures else {}
				if #creatures > 0 then
					Remotes.event("TradeSetOffer"):FireServer({ creatures[#creatures].Id })
				end
			elseif not view.Ready.Me and #view.Theirs > 0 then
				Remotes.event("TradeReady"):FireServer()
			elseif view.Ready.Me and view.Ready.Them and not view.Confirmed.Me and view.ConfirmAt then
				task.wait(math.max(0, view.ConfirmAt - workspace:GetServerTimeNow()) + 0.2)
				Remotes.event("TradeConfirm"):FireServer()
			end
		end)
	end)

	-- Acepta tratos al azar, como haría alguien sociable.
	Remotes.event("DealOffered").OnClientEvent:Connect(function(fromUserId: number)
		if enabled then
			task.delay(1.5, function()
				Remotes.event("RespondDeal"):FireServer(fromUserId, math.random() < 0.5)
			end)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(tick)
			if not ok then
				warn("[Autopilot] " .. tostring(err))
			end
		end
	end)
end

return AutopilotController
