--!strict
-- HUD mínimo (GDD 8): bolsa, barra del servidor, temporizador de fase y flecha de objetivo.
-- También muestra avisos del servidor y notificaciones personales.
-- GDD v3: en el lobby cambia a la cola de partidas (botón Jugar y "seguir jugando"); en la
-- persecución, la flecha apunta a donde se vio a los portadores en la última señal.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Rarity = require(Shared.Rarity)
local Remotes = require(Shared.Remotes)
local RoundState = require(Shared.RoundState)

local UI = require(script.Parent.Parent.UI)

local player = Players.LocalPlayer

local HUDController = {}

local STYLE_COLORS: { [string]: Color3 } = {
	info = UI.Colors.Text,
	threshold = UI.Colors.Accent,
	rare = UI.Colors.Gold,
	global = Color3.fromRGB(255, 120, 255),
	quest = UI.Colors.Good,
}

local gui: ScreenGui
local phaseLabel: TextLabel
local timerLabel: TextLabel
local communityLabel: TextLabel
local barFill: Frame
local barLabel: TextLabel
local bagFill: Frame
local bagLabel: TextLabel
local affinityLabel: TextLabel
local coinsLabel: TextLabel
local dustLabel: TextLabel
local bannerLabel: TextLabel
local secureLabel: TextLabel
local toastList: Frame
local beam: Beam
local targetAttachment: Attachment
local topFrame: Frame
local bagFrame: Frame
local lobbyFrame: Frame
local lobbyLabel: TextLabel
local playButton: TextButton
local requeueButton: TextButton
local markerFolder: Folder
local markers: { BillboardGui } = {}
local lastSeen: { Vector3 } = {}
local lastSeenAt = 0

local function buildTop()
	local top = UI.frame({
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.5, 0, 0, 74),
	}, gui)
	UI.round(top, 14)
	topFrame = top
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(300, 74)
	constraint.MaxSize = Vector2.new(560, 74)
	constraint.Parent = top

	phaseLabel = UI.label({ Position = UDim2.new(0, 12, 0, 4), Size = UDim2.new(0.7, -12, 0, 28), TextXAlignment = Enum.TextXAlignment.Left }, top)
	timerLabel = UI.label({ Position = UDim2.new(0.7, 0, 0, 4), Size = UDim2.new(0.3, -12, 0, 28), TextXAlignment = Enum.TextXAlignment.Right }, top)

	local bar = UI.frame({ Position = UDim2.new(0, 12, 0, 38), Size = UDim2.new(1, -24, 0, 26), BackgroundColor3 = UI.Colors.PanelLight }, top)
	UI.round(bar, 10)
	barFill = UI.frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = UI.Colors.Accent, BackgroundTransparency = 0 }, bar)
	UI.round(barFill, 10)
	-- Marcas de los umbrales 25/50/75 %.
	for _, threshold in Config.Thresholds do
		if threshold.Fraction < 1 then
			UI.frame({
				Position = UDim2.new(threshold.Fraction, -1, 0, 0),
				Size = UDim2.new(0, 2, 1, 0),
				BackgroundColor3 = UI.Colors.Text,
				BackgroundTransparency = 0.4,
				ZIndex = 3,
			}, bar)
		end
	end
	barLabel = UI.label({ Size = UDim2.fromScale(1, 1), ZIndex = 4 }, bar)

	-- Persecución: señal, tira y afloja, escudos.
	secureLabel = UI.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 6),
		Size = UDim2.new(1, 0, 0, 26),
		TextColor3 = UI.Colors.Gold,
		Visible = false,
	}, top)
end

local function buildCurrencies()
	local panel = UI.frame({
		Name = "Currencies",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(170, 96),
	}, gui)
	UI.round(panel, 14)
	coinsLabel = UI.label({ Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 30), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = UI.Colors.Gold }, panel)
	dustLabel = UI.label({ Position = UDim2.fromOffset(10, 38), Size = UDim2.new(1, -20, 0, 28), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = UI.Colors.Muted }, panel)
	-- Barra global del Huevo Comunitario (todos los servidores).
	communityLabel = UI.label({ Position = UDim2.fromOffset(10, 68), Size = UDim2.new(1, -20, 0, 20), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = UI.Colors.Muted }, panel)
	communityLabel.Visible = Config.Events.Community.Enabled
end

local function buildBag()
	local panel = UI.frame({
		Name = "Bag",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 8, 1, -8),
		Size = UDim2.fromOffset(220, 70),
	}, gui)
	UI.round(panel, 14)
	bagFrame = panel
	local bar = UI.frame({ Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 28), BackgroundColor3 = UI.Colors.PanelLight }, panel)
	UI.round(bar, 10)
	bagFill = UI.frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 110, 40), BackgroundTransparency = 0 }, bar)
	UI.round(bagFill, 10)
	bagLabel = UI.label({ Size = UDim2.fromScale(1, 1), ZIndex = 3 }, bar)
	affinityLabel = UI.label({ Position = UDim2.fromOffset(10, 40), Size = UDim2.new(1, -20, 0, 22), TextColor3 = UI.Colors.Muted }, panel)
end

-- Lobby: estado de la cola, botón Jugar y "seguir jugando" al acabar cada partida.
local function buildLobby()
	lobbyFrame = UI.frame({
		Name = "Lobby",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.5, 0, 0, 46),
		Visible = false,
	}, gui)
	UI.round(lobbyFrame, 14)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(300, 46)
	constraint.MaxSize = Vector2.new(560, 46)
	constraint.Parent = lobbyFrame
	lobbyLabel = UI.label({ Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 1, -12), Text = "🏡 Lobby" }, lobbyFrame)

	playButton = UI.button({
		Name = "Play",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(220, 62),
		Text = "⚔️ JUGAR",
		BackgroundColor3 = UI.Colors.Accent,
		Visible = false,
	}, gui, function()
		Remotes.event("RequestQueue"):FireServer(player:GetAttribute("Queued") ~= true)
	end)
	UI.stroke(playButton, UI.Colors.Gold, 3)
	requeueButton = UI.button({
		Name = "Requeue",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.fromOffset(220, 28),
		Text = "",
		BackgroundColor3 = UI.Colors.PanelLight,
		Visible = false,
	}, gui, function()
		Remotes.event("SetAutoRequeue"):FireServer(player:GetAttribute("AutoRequeue") == false)
	end)
end

local function inMatch(): boolean
	return player:GetAttribute("InMatch") == true
end

local function refreshMode()
	local match = inMatch()
	topFrame.Visible = match
	bagFrame.Visible = match
	lobbyFrame.Visible = not match
	playButton.Visible = not match
	requeueButton.Visible = true
	requeueButton.Text = if player:GetAttribute("AutoRequeue") == false then "🔁 Seguir jugando: no" else "🔁 Seguir jugando: sí"
	if match then
		playButton.Visible = false
	end
	local queued = player:GetAttribute("Queued") == true
	playButton.Text = if queued then "✕ Salir de la cola" else "⚔️ JUGAR"
	playButton.BackgroundColor3 = if queued then UI.Colors.Bad else UI.Colors.Accent
end

local function lobbyText(): string
	local count = tonumber(RoundState.get("QueueCount")) or 0
	local launchAt = tonumber(RoundState.get("QueueLaunchAt")) or 0
	local queued = player:GetAttribute("Queued") == true
	if queued and launchAt > 0 then
		return "🚀 ¡Partida encontrada! Saliendo…"
	elseif queued then
		return string.format("⚔️ En la cola: %d jugador%s · buscando partida…", count, if count == 1 then "" else "es")
	end
	local luckEnds = tonumber(RoundState.get("ServerLuckEndsAt")) or 0
	local luckLeft = luckEnds - workspace:GetServerTimeNow()
	if luckLeft > 0 then
		return string.format("🍀 Suerte del Lobby: %d:%02d · tus huevos del nido salen mejores", math.floor(luckLeft / 60), math.floor(luckLeft % 60))
	end
	return "🏡 Lobby · cuida tu nido y pulsa Jugar"
end

local function buildMessages()
	bannerLabel = UI.label({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.new(0.8, 0, 0, 40),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}, gui)

	toastList = UI.frame({
		Name = "Toasts",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -8, 1, -90),
		Size = UDim2.fromOffset(300, 220),
		BackgroundTransparency = 1,
	}, gui)
	local layout = UI.list(toastList, 4)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
end

function HUDController.banner(text: string, style: string?)
	bannerLabel.Text = text
	bannerLabel.TextColor3 = STYLE_COLORS[style or "info"] or UI.Colors.Text
	bannerLabel.TextTransparency = 0
	bannerLabel.TextStrokeTransparency = 0.3
	local token = os.clock()
	bannerLabel:SetAttribute("Token", token)
	task.delay(4, function()
		if bannerLabel:GetAttribute("Token") == token then
			TweenService:Create(bannerLabel, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

function HUDController.toast(text: string, style: string?)
	local frame = UI.frame({ Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 0.25 }, toastList)
	UI.round(frame, 10)
	UI.label({
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -16, 1, -8),
		Text = text,
		TextColor3 = STYLE_COLORS[style or "info"] or UI.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, frame)
	task.delay(5, function()
		frame:Destroy()
	end)
	local toasts: { Instance } = {}
	for _, child in toastList:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts > 5 then
		toasts[1]:Destroy()
	end
end

local function refreshCurrencies()
	coinsLabel.Text = "🪙 " .. UI.formatNumber(tonumber(player:GetAttribute("Coins")) or 0)
	dustLabel.Text = "✨ " .. UI.formatNumber(tonumber(player:GetAttribute("Dust")) or 0) .. " polvo"
end

local function refreshBag()
	local heat = tonumber(player:GetAttribute("Heat")) or 0
	local capacity = tonumber(player:GetAttribute("BagCapacity")) or 100
	bagFill.Size = UDim2.fromScale(math.clamp(heat / math.max(capacity, 1), 0, 1), 1)
	local offering = player:GetAttribute("Offering")
	local suffix = if type(offering) == "string" and offering ~= "" then " + ofrenda" else ""
	bagLabel.Text = string.format("🔥 %d / %d%s", heat, capacity, suffix)
	affinityLabel.Text = string.format("Afinidad con el huevo: %d", tonumber(player:GetAttribute("Affinity")) or 0)
end

local function refreshBar()
	local bar = tonumber(RoundState.get("Bar")) or 0
	local goal = tonumber(RoundState.get("BarGoal")) or 1
	local fraction = math.clamp(bar / math.max(goal, 1), 0, 1)
	TweenService:Create(barFill, TweenInfo.new(0.3), { Size = UDim2.fromScale(fraction, 1) }):Play()
	local minRarity = RoundState.get("MinRarity")
	local rarityText = if type(minRarity) == "string" and Rarity.isValid(minRarity)
		then Rarity.Info[minRarity :: Rarity.RarityName].DisplayName
		else "Común"
	barLabel.Text = string.format("Huevo %d %% · mínimo %s", math.floor(fraction * 100), rarityText)
end

local function mapChild(name: string): Instance?
	local map = workspace:FindFirstChild("Map")
	return map and map:FindFirstChild(name)
end

-- Flecha de objetivo: un haz desde el jugador hasta lo que le toca hacer ahora.
local function currentTarget(): Vector3?
	if player:GetAttribute("InMatch") ~= true then
		return nil
	end
	local phase = RoundState.phase()
	if phase == "Incubation" then
		local heat = tonumber(player:GetAttribute("Heat")) or 0
		local capacity = tonumber(player:GetAttribute("BagCapacity")) or 100
		local offering = player:GetAttribute("Offering")
		if heat >= capacity * 0.5 or (type(offering) == "string" and offering ~= "") then
			local egg = mapChild("Egg")
			return if egg and egg:IsA("BasePart") then egg.Position else nil
		end
	elseif phase == "Chase" then
		if player:GetAttribute("IsCarrier") then
			return nil -- el portador no necesita flecha: tiene que esconderse
		end
		-- Puede haber varias criaturas: donde se vio al portador más cercano en la última
		-- señal (GDD v3: entre señales no se sabe dónde está), o una criatura suelta.
		local own = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local from = if own and own:IsA("BasePart") then own.Position else Vector3.zero
		local best: Vector3? = nil
		local bestDistance = math.huge
		local function consider(position: Vector3)
			local d = (position - from).Magnitude
			if d < bestDistance then
				best, bestDistance = position, d
			end
		end
		for _, position in lastSeen do
			consider(position)
		end
		for _, creature in CollectionService:GetTagged("RoundCreature") do
			local body = if creature:IsA("Model") then creature.PrimaryPart else nil
			if body and body:FindFirstChild("PickupPrompt") then
				consider(body.Position)
			end
		end
		return best
	end
	return nil
end

-- Marcas "📍 visto aquí" en las posiciones de la última señal.
local function parsePositions(text: string): { Vector3 }
	local list = {}
	for _, chunk in string.split(text, ";") do
		local parts = string.split(chunk, ",")
		local x, y, z = tonumber(parts[1]), tonumber(parts[2]), tonumber(parts[3])
		if x and y and z then
			table.insert(list, Vector3.new(x, y, z))
		end
	end
	return list
end

local function refreshMarkers()
	local chasing = RoundState.phase() == "Chase" and inMatch()
	for index, gui in markers do
		local position = lastSeen[index]
		gui.Enabled = chasing and position ~= nil
		local anchor = gui.Adornee
		if position and anchor and anchor:IsA("BasePart") then
			anchor.Position = position + Vector3.new(0, 4, 0)
		end
	end
	while #markers < #lastSeen do
		local anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.Parent = markerFolder
		local gui = Instance.new("BillboardGui")
		gui.Adornee = anchor
		gui.AlwaysOnTop = true
		gui.Size = UDim2.fromOffset(46, 46)
		gui.Parent = markerFolder
		UI.label({ Size = UDim2.fromScale(1, 1), Text = "📍", TextColor3 = UI.Colors.Gold }, gui)
		table.insert(markers, gui)
		anchor.Position = lastSeen[#markers] + Vector3.new(0, 4, 0)
		gui.Enabled = chasing
	end
end

local function updateBeam()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local target = currentTarget()
	if not root or not target then
		beam.Enabled = false
		return
	end
	local attachment = root:FindFirstChild("TargetFrom") :: Attachment?
	if not attachment then
		local a = Instance.new("Attachment")
		a.Name = "TargetFrom"
		a.Position = Vector3.new(0, -2, 0)
		a.Parent = root
		attachment = a
	end
	beam.Attachment0 = attachment
	targetAttachment.WorldPosition = target
	beam.Enabled = true
end

function HUDController.start()
	gui = UI.screen("HUD", 1)
	buildTop()
	buildCurrencies()
	buildBag()
	buildMessages()

	local anchor = Instance.new("Part")
	anchor.Name = "TargetAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Parent = workspace.CurrentCamera
	targetAttachment = Instance.new("Attachment")
	targetAttachment.Parent = anchor
	beam = Instance.new("Beam")
	beam.Attachment1 = targetAttachment
	beam.Color = ColorSequence.new(UI.Colors.Gold)
	beam.Transparency = NumberSequence.new(0.2, 0.9)
	beam.Width0 = 1.2
	beam.Width1 = 0.2
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureSpeed = 2
	beam.Enabled = false
	beam.Parent = anchor

	markerFolder = Instance.new("Folder")
	markerFolder.Name = "SeenMarkers"
	markerFolder.Parent = workspace.CurrentCamera
	buildLobby()
	for _, attribute in { "InMatch", "Queued", "AutoRequeue" } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshMode)
	end
	RoundState.changed("RevealPositions"):Connect(function()
		lastSeen = parsePositions(tostring(RoundState.get("RevealPositions") or ""))
		lastSeenAt = os.clock()
		refreshMarkers()
	end)
	RoundState.changed("Phase"):Connect(function()
		if RoundState.phase() ~= "Chase" then
			lastSeen = {}
		end
		refreshMarkers()
	end)

	for _, attribute in { "Coins", "Dust" } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshCurrencies)
	end
	for _, attribute in { "Heat", "BagCapacity", "Affinity", "Offering" } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshBag)
	end
	for _, attribute in { "Bar", "BarGoal", "MinRarity" } do
		RoundState.changed(attribute):Connect(refreshBar)
	end

	Remotes.event("Announcement").OnClientEvent:Connect(function(text: string, style: string?)
		HUDController.banner(text, style)
	end)
	Remotes.event("Notify").OnClientEvent:Connect(function(text: string, style: string?)
		HUDController.toast(text, style)
	end)

	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		accumulator = 0
		local phase = RoundState.phase()
		local name = RoundState.PhaseNames[phase] or phase
		if RoundState.get("BloodMoon") then
			name = "🌕 " .. name
		end
		if RoundState.get("LootNight") then
			name = "🌙 " .. name .. " · Noche de Saqueo"
		end
		local community = tonumber(RoundState.get("CommunityProgress")) or 0
		communityLabel.Text = if community >= 1 then "🌍 Huevo Comunitario ¡lleno!" else string.format("🌍 Huevo Comunitario %d %%", math.floor(community * 100))
		phaseLabel.Text = name
		timerLabel.Text = if phase == "Waiting" then "" else UI.formatTime(RoundState.timeLeft())
		if not inMatch() then
			lobbyLabel.Text = lobbyText()
		end
		-- Persecución: señal, tira y afloja, escudos y aviso de robo (GDD v2 y v3).
		local chasing = phase == "Chase" and inMatch()
		local tugEndsAt = tonumber(player:GetAttribute("TugEndsAt"))
		local shields = tonumber(player:GetAttribute("Shields")) or 0
		local revealed = RoundState.get("Revealed") == true
		local nextReveal = math.max(0, (tonumber(RoundState.get("NextRevealAt")) or 0) - workspace:GetServerTimeNow())
		local final = RoundState.timeLeft() <= Config.Chase.FinalRevealSeconds
		local carrier = player:GetAttribute("IsCarrier") == true
		local status = ""
		if chasing and player:GetAttribute("BeingTugged") then
			status = "⚠️ ¡Te están robando! ¡Aléjate!"
		elseif chasing and tugEndsAt then
			local left = math.max(0, tugEndsAt - workspace:GetServerTimeNow())
			status = string.format("💪 ¡Robando! Quédate cerca %.1f s", left)
		elseif chasing and final then
			status = if carrier then "⏰ ¡Aguanta! Todos te ven" else "⏰ ¡Últimos segundos: todos a la vista!"
		elseif chasing and revealed then
			status = if carrier then "📍 ¡Te están viendo! Escóndete" else "📍 ¡Señal! Mira dónde están"
		elseif chasing then
			status = string.format(if carrier then "🙈 Escondido · te verán en %d s" else "🔎 Próxima señal en %d s", math.ceil(nextReveal))
		end
		if chasing and shields > 0 then
			status = (if status ~= "" then status .. " · " else "") .. string.rep("🛡️", shields)
		end
		secureLabel.Visible = status ~= ""
		secureLabel.Text = status
		if chasing and os.clock() - lastSeenAt > 0.5 then
			refreshMarkers()
		end
		updateBeam()
	end)

	refreshCurrencies()
	refreshBag()
	refreshBar()
	refreshMode()
end

return HUDController
