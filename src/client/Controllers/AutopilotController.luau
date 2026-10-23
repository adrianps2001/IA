--!strict
-- Piloto automático para probar en Roblox Studio (docs/PRUEBAS.md). Con varios jugadores de
-- prueba, cada ventana juega sola: en el lobby usa la tienda del nido y se apunta a la cola;
-- en la partida recoge Calor (también en lo alto de los árboles), deposita, persigue a donde
-- se vio al portador en la última señal, roba con el prompt real y, si lleva la criatura,
-- huye por el parkour. Como son jugadores de verdad, recorre exactamente el mismo código que
-- una persona (remotos, prompts y validaciones del servidor). F8 lo activa o desactiva.
-- GDD v3: se mueve con PathfindingService (Navigator), así ya no se queda pegado a las
-- paredes y sube por las rampas. Solo funciona dentro de Studio (Testing.enabled("Autopilot")).

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ArenaLayout = require(Shared.ArenaLayout)
local Config = require(Shared.Config)
local Navigator = require(Shared.Navigator)
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
local targetSince = 0
local holding: ProximityPrompt? = nil
local holdUntil = 0
local shopDone = false -- ya usó la tienda en esta visita al lobby
local queueAt = 0 -- cuándo se apunta a la cola
local wanderAt = 0
local hideSpot: Vector3? = nil
local hideUntil = 0
local nav: Navigator.Navigator? = nil
local navRoot: BasePart? = nil
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

-- Va andando con un camino calculado (rodea paredes y troncos, sube rampas).
local function moveTo(position: Vector3)
	local h = humanoid()
	local root = rootOf(player)
	if not h or not root then
		return
	end
	if not nav or navRoot ~= root then
		nav = Navigator.new(h, root)
		navRoot = root
	end
	(nav :: Navigator.Navigator):moveTo(position)
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
		if part:IsA("BasePart") and not part:GetAttribute("Taken") and part.Transparency < 1 and part.Name ~= "Geyser" and (blacklist[part] or 0) < now then
			local value = if part.Name == "LuckyBlock" or part.Name == "PurpleEmber" then 4 elseif part.Name == "BlueEmber" then 2 else 1
			-- Lo que está en lo alto cuesta más de alcanzar (hay que subir la rampa).
			local climb = math.max(0, part.Position.Y - root.Position.Y) * 2
			local score = (flat(part.Position, root.Position) + climb) / value
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
	-- Si tarda demasiado en llegar a una fuente, la descarta un rato.
	if target and os.clock() - targetSince > 20 then
		blacklist[target] = os.clock() + 15
		target = nil
	end
	if not target or not target.Parent or target:GetAttribute("Taken") then
		target = nearestSource(root)
		targetSince = os.clock()
	end
	if target then
		moveTo(target.Position)
	end
end

-- Un buen escondite: una plataforma de un árbol lejos de los ladrones.
local function pickHideSpot(root: BasePart, threat: Vector3?): Vector3
	local spots = ArenaLayout.deckSpots()
	local best = spots[1]
	local bestScore = -math.huge
	for _ = 1, 12 do
		local spot = spots[math.random(1, #spots)]
		local p = Vector3.new(spot.X, spot.Y, spot.Z)
		local score = spot.Y * 0.5 - flat(p, root.Position) * 0.3
		if threat then
			score += flat(p, threat)
		end
		if score > bestScore then
			best, bestScore = spot, score
		end
	end
	return Vector3.new(best.X, best.Y + 3, best.Z)
end

-- Posiciones de la última señal ("x,y,z;x,y,z").
local function lastSeen(): { Vector3 }
	local list = {}
	for _, chunk in string.split(tostring(RoundState.get("RevealPositions") or ""), ";") do
		local parts = string.split(chunk, ",")
		local x, y, z = tonumber(parts[1]), tonumber(parts[2]), tonumber(parts[3])
		if x and y and z then
			table.insert(list, Vector3.new(x, y, z))
		end
	end
	return list
end

local function chase(root: BasePart)
	if player:GetAttribute("IsCarrier") then
		release()
		-- ¿Hay ladrones cerca?
		local nearest = math.huge
		local threat: Vector3? = nil
		for _, other in Players:GetPlayers() do
			local r = if other ~= player and other:GetAttribute("InMatch") then rootOf(other) else nil
			if r and (r.Position - root.Position).Magnitude < nearest then
				nearest = (r.Position - root.Position).Magnitude
				threat = r.Position
			end
		end
		if nearest < 15 then
			Remotes.event("RequestSprint"):FireServer()
		end
		-- Huir por el parkour: cambiar de escondite si se acercan o tras un rato.
		if not hideSpot or os.clock() > hideUntil or (nearest < 18 and math.random() < 0.15) then
			hideSpot = pickHideSpot(root, threat)
			hideUntil = os.clock() + math.random(10, 18)
		end
		moveTo(hideSpot :: Vector3)
		return
	end
	hideSpot = nil

	-- Puede haber varias criaturas: una suelta cerca es lo primero.
	for _, creature in CollectionService:GetTagged("RoundCreature") do
		local body = if creature:IsA("Model") then creature.PrimaryPart else nil
		local pickup = body and body:FindFirstChild("PickupPrompt")
		if body and pickup and pickup:IsA("ProximityPrompt") and flat(body.Position, root.Position) < 60 then
			moveTo(body.Position)
			if (body.Position - root.Position).Magnitude < 8 then
				hold(pickup, pickup.HoldDuration + 0.2)
			end
			return
		end
	end
	-- Un portador a la vista (cerca), o a donde se le vio en la última señal.
	local carrierRoot: BasePart? = nil
	local best = math.huge
	for _, id in string.split(tostring(RoundState.get("Carriers") or ""), ",") do
		local carrier = Players:GetPlayerByUserId(tonumber(id) or 0)
		local r = if carrier and carrier ~= player then rootOf(carrier) else nil
		local d = if r then (r.Position - root.Position).Magnitude else math.huge
		if r and d < best and (d < 40 or RoundState.get("Revealed")) then
			carrierRoot, best = r, d
		end
	end
	if not carrierRoot then
		local seen = lastSeen()
		local closest: Vector3? = nil
		local closestDistance = math.huge
		for _, p in seen do
			local d = (p - root.Position).Magnitude
			if d < closestDistance then
				closest, closestDistance = p, d
			end
		end
		if closest then
			moveTo(closest)
		end
		return
	end
	moveTo(carrierRoot.Position)
	local distance = (carrierRoot.Position - root.Position).Magnitude
	local prompt = carrierRoot:FindFirstChild("StealPrompt")
	-- Con robo por toque basta un toque; luego hay que quedarse cerca (el servidor cuenta).
	if prompt and prompt:IsA("ProximityPrompt") and distance < Config.Chase.StealRange - 1 and not player:GetAttribute("TugEndsAt") then
		hold(prompt, prompt.HoldDuration + 0.2)
	elseif holding and distance > Config.Chase.StealRange then
		release()
	end
end

-- En el lobby usa el nido como lo haría un jugador (mejoras, huevos, recoger) y se apunta
-- a la cola al cabo de unos segundos.
local function lobby()
	if not shopDone then
		shopDone = true
		queueAt = os.clock() + math.random(4, 10)
		Remotes.event("RequestCollectEggs"):FireServer()
		Remotes.event("RequestBuyEgg"):FireServer()
		local names = { "Bag", "Boots", "Nest", "Incubator" }
		Remotes.event("RequestUpgrade"):FireServer(names[math.random(1, #names)])
	end
	if not player:GetAttribute("Queued") and os.clock() >= queueAt then
		queueAt = os.clock() + 15
		Remotes.event("RequestQueue"):FireServer(true)
	end
	-- Pasea por su nido mientras espera.
	local nest = player:GetAttribute("NestPosition")
	if typeof(nest) == "Vector3" and os.clock() >= wanderAt then
		wanderAt = os.clock() + 6
		moveTo(nest + Vector3.new(math.random(-10, 10), 0, math.random(-10, 10)))
	elseif nav then
		nav:update()
	end
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
	if not player:GetAttribute("InMatch") then
		lobby()
		return
	end
	shopDone = false -- al volver al lobby, otra vuelta por la tienda

	local phase = RoundState.phase()
	if phase == "Incubation" then
		incubation(root)
	elseif phase == "Chase" then
		chase(root)
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
		if nav then
			nav:update()
		end
	end
end

local function setEnabled(value: boolean)
	enabled = value
	label.Text = if value then "🤖 Piloto automático ACTIVADO (F8)" else "🎮 Controlas tú (F8: piloto automático)"
	label.TextColor3 = if value then UI.Colors.Gold else UI.Colors.Muted
	if not value then
		release()
		if nav then
			nav:stop()
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
