--!strict
-- Bandada e intercambio (GDD 9): panel con los jugadores del servidor (invitar a la Bandada
-- o pedir un intercambio), ventanas de invitación y la ventana de intercambio con doble
-- confirmación. Los miembros de tu Bandada se ven a través de las paredes (Highlight).
-- Solo envía intenciones; el servidor (PartyService, TradeService) lo valida todo.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Rarity = require(Shared.Rarity)
local Remotes = require(Shared.Remotes)

local UI = require(script.Parent.Parent.UI)

local player = Players.LocalPlayer

local SocialController = {}

local gui: ScreenGui
local panel: Frame
local list: ScrollingFrame
local askPanel: Frame
local askText: TextLabel
local askAction: ((boolean) -> ())? = nil
local tradePanel: Frame
local tradeMine: ScrollingFrame
local tradeTheirs: ScrollingFrame
local tradeStatus: TextLabel
local readyButton: TextButton
local confirmButton: TextButton

local profile: any = nil
local trade: any = nil
local offer: { string } = {}

local function rarityColor(name: any): Color3
	if Rarity.isValid(name) then
		return UI.rgb(Rarity.Info[name :: Rarity.RarityName].Color)
	end
	return UI.Colors.Text
end

-- Ventana genérica de "¿Aceptas?" para invitaciones y peticiones de intercambio.
local function ask(text: string, action: (boolean) -> ())
	askText.Text = text
	askAction = action
	askPanel.Visible = true
end

-- Bandada: resaltar a los miembros ------------------------------------------------------

local function refreshHighlights()
	local myParty = player:GetAttribute("PartyId")
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if other ~= player and character then
			local highlight = character:FindFirstChild("PartyHighlight")
			local same = myParty ~= nil and other:GetAttribute("PartyId") == myParty
			if same and not highlight then
				local h = Instance.new("Highlight")
				h.Name = "PartyHighlight"
				h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				h.FillTransparency = 0.85
				h.OutlineColor = UI.Colors.Good
				h.Parent = character
			elseif not same and highlight then
				highlight:Destroy()
			end
		end
	end
end

-- Lista de jugadores ----------------------------------------------------------------------

local renderList: () -> ()

renderList = function()
	UI.clear(list)
	if not list:FindFirstChildOfClass("UIListLayout") then
		UI.list(list, 6)
	end
	local myParty = player:GetAttribute("PartyId")
	local members = 1
	for _, other in Players:GetPlayers() do
		if other ~= player and myParty ~= nil and other:GetAttribute("PartyId") == myParty then
			members += 1
		end
	end
	local header = UI.frame({ Size = UDim2.new(1, -8, 0, 44), BackgroundColor3 = UI.Colors.PanelLight, LayoutOrder = 0 }, list)
	UI.round(header, 10)
	UI.label({
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(0.62, -10, 1, -12),
		Text = if myParty then string.format("🐦 Tu Bandada: %d/%d", members, Config.Party.MaxSize) else "🐦 No estás en una Bandada",
		TextXAlignment = Enum.TextXAlignment.Left,
	}, header)
	if myParty then
		UI.button({ Position = UDim2.new(0.62, 0, 0, 6), Size = UDim2.new(0.38, -8, 1, -12), Text = "Salir", BackgroundColor3 = UI.Colors.Bad }, header, function()
			Remotes.event("PartyLeave"):FireServer()
		end)
	end
	local order = 1
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local same = myParty ~= nil and other:GetAttribute("PartyId") == myParty
			local r = UI.frame({ Size = UDim2.new(1, -8, 0, 44), BackgroundColor3 = UI.Colors.PanelLight, LayoutOrder = order }, list)
			UI.round(r, 10)
			UI.label({
				Position = UDim2.fromOffset(10, 6),
				Size = UDim2.new(0.4, -10, 1, -12),
				Text = (if same then "🐦 " else "") .. other.DisplayName,
				TextXAlignment = Enum.TextXAlignment.Left,
			}, r)
			local userId = other.UserId
			UI.button({ Position = UDim2.new(0.4, 0, 0, 6), Size = UDim2.new(0.3, -6, 1, -12), Text = if same then "En tu Bandada" else "Invitar", BackgroundColor3 = if same then UI.Colors.Panel else UI.Colors.Good }, r, function()
				if not same then
					Remotes.event("PartyInvite"):FireServer(userId)
				end
			end)
			UI.button({ Position = UDim2.new(0.7, 0, 0, 6), Size = UDim2.new(0.3, -8, 1, -12), Text = "Intercambiar", BackgroundColor3 = UI.Colors.Accent }, r, function()
				Remotes.event("TradeRequest"):FireServer(userId)
			end)
			order += 1
		end
	end
	if order == 1 then
		UI.label({ Size = UDim2.new(1, 0, 0, 40), Text = "No hay nadie más en el servidor.", TextColor3 = UI.Colors.Muted, LayoutOrder = 1 }, list)
		order += 1
	end
	-- Historial: los últimos intercambios, del más reciente al más antiguo.
	local trades = if profile and profile.Trades then profile.Trades else {}
	if #trades > 0 then
		UI.label({ Size = UDim2.new(1, 0, 0, 28), Text = "Últimos intercambios", LayoutOrder = order }, list)
		for i = #trades, 1, -1 do
			local record: any = trades[i]
			order += 1
			UI.label({
				Size = UDim2.new(1, -8, 0, 36),
				Text = string.format("Con %s: diste %s · recibiste %s", record.WithName, table.concat(record.Gave, ", "), table.concat(record.Got, ", ")),
				TextColor3 = UI.Colors.Muted,
				TextWrapped = true,
				LayoutOrder = order,
			}, list)
		end
	end
end

-- Ventana de intercambio ------------------------------------------------------------------

local function creatureRow(parent: Instance, creature: any, order: number, selected: boolean, onClick: (() -> ())?)
	local r = UI.frame({ Size = UDim2.new(1, -6, 0, 40), BackgroundColor3 = UI.Colors.PanelLight, LayoutOrder = order }, parent)
	UI.round(r, 8)
	if selected then
		UI.stroke(r, UI.Colors.Gold, 3)
	end
	UI.label({ Position = UDim2.fromOffset(8, 2), Size = UDim2.new(1, -16, 0, 20), Text = creature.Name, TextXAlignment = Enum.TextXAlignment.Left }, r)
	UI.label({
		Position = UDim2.fromOffset(8, 20),
		Size = UDim2.new(1, -16, 0, 16),
		Text = string.format("%s · %s/s", creature.RarityName, UI.formatNumber(creature.Income)),
		TextColor3 = rarityColor(creature.Rarity),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, r)
	if onClick then
		local hit = Instance.new("TextButton")
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.Size = UDim2.fromScale(1, 1)
		hit.Parent = r
		hit.Activated:Connect(function()
			onClick()
		end)
	end
end

local function renderTrade()
	tradePanel.Visible = trade ~= nil
	if not trade then
		return
	end
	UI.clear(tradeMine)
	UI.clear(tradeTheirs)
	for _, scroll in { tradeMine, tradeTheirs } do
		if not scroll:FindFirstChildOfClass("UIListLayout") then
			UI.list(scroll, 4)
		end
	end
	-- Tu lado: tus criaturas (las 100 mejores de la vista); pulsa para ofrecer o quitar.
	offer = {}
	for _, item in trade.Mine do
		table.insert(offer, item.Id)
	end
	local creatures = if profile then profile.Creatures else {}
	for index, creature in creatures do
		local isOffered = table.find(offer, creature.Id) ~= nil
		creatureRow(tradeMine, creature, index, isOffered, function()
			local next = table.clone(offer)
			local at = table.find(next, creature.Id)
			if at then
				table.remove(next, at)
			elseif #next < trade.MaxItems then
				table.insert(next, creature.Id)
			end
			Remotes.event("TradeSetOffer"):FireServer(next)
		end)
	end
	for index, creature in trade.Theirs do
		creatureRow(tradeTheirs, creature, index, true, nil)
	end
	if #trade.Theirs == 0 then
		UI.label({ Size = UDim2.new(1, 0, 0, 30), Text = "Todavía no ofrece nada", TextColor3 = UI.Colors.Muted }, tradeTheirs)
	end
end

local function updateTradeStatus()
	if not trade then
		return
	end
	local waiting = if trade.ConfirmAt then math.max(0, math.ceil(trade.ConfirmAt - workspace:GetServerTimeNow())) else nil
	tradeStatus.Text = string.format(
		"Das %d (%s/s) · Recibes %d (%s/s)\n%s · %s",
		#trade.Mine,
		UI.formatNumber(trade.MyValue),
		#trade.Theirs,
		UI.formatNumber(trade.TheirValue),
		if trade.Ready.Me then "Tú: listo ✔" else "Tú: eligiendo",
		if trade.Ready.Them then trade.Partner .. ": listo ✔" else trade.Partner .. ": eligiendo"
	)
	readyButton.Text = if trade.Ready.Me then "Listo ✔" else "1. Listo"
	readyButton.BackgroundColor3 = if trade.Ready.Me then UI.Colors.Panel else UI.Colors.Good
	local bothReady = trade.Ready.Me and trade.Ready.Them
	if trade.Confirmed.Me then
		confirmButton.Text = "Esperando…"
	elseif bothReady and waiting and waiting > 0 then
		confirmButton.Text = string.format("2. Confirmar (%d)", waiting)
	else
		confirmButton.Text = "2. Confirmar"
	end
	confirmButton.BackgroundColor3 = if bothReady and waiting == 0 and not trade.Confirmed.Me then UI.Colors.Good else UI.Colors.Panel
end

local function buildTrade()
	tradePanel = UI.frame({
		Name = "Trade",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.72),
		Visible = false,
	}, gui)
	UI.round(tradePanel, 16)
	UI.stroke(tradePanel, UI.Colors.Accent, 2)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(320, 320)
	constraint.MaxSize = Vector2.new(680, 560)
	constraint.Parent = tradePanel
	UI.label({ Position = UDim2.fromOffset(10, 6), Size = UDim2.new(0.5, -14, 0, 26), Text = "Tú das (pulsa para elegir)" }, tradePanel)
	UI.label({ Position = UDim2.new(0.5, 4, 0, 6), Size = UDim2.new(0.5, -14, 0, 26), Text = "Recibes" }, tradePanel)
	local function scroll(x: number): ScrollingFrame
		local s = Instance.new("ScrollingFrame")
		s.Position = UDim2.new(x, if x == 0 then 10 else 4, 0, 36)
		s.Size = UDim2.new(0.5, -14, 1, -150)
		s.BackgroundTransparency = 1
		s.BorderSizePixel = 0
		s.ScrollBarThickness = 6
		s.AutomaticCanvasSize = Enum.AutomaticSize.Y
		s.CanvasSize = UDim2.new()
		s.Parent = tradePanel
		return s
	end
	tradeMine = scroll(0)
	tradeTheirs = scroll(0.5)
	tradeStatus = UI.label({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -60), Size = UDim2.new(1, -20, 0, 50), TextWrapped = true }, tradePanel)
	local function button(x: number, text: string, color: Color3, remote: string): TextButton
		return UI.button({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(x, 6, 1, -8), Size = UDim2.new(1 / 3, -12, 0, 44), Text = text, BackgroundColor3 = color }, tradePanel, function()
			Remotes.event(remote):FireServer()
		end)
	end
	readyButton = button(0, "1. Listo", UI.Colors.Good, "TradeReady")
	confirmButton = button(1 / 3, "2. Confirmar", UI.Colors.Panel, "TradeConfirm")
	button(2 / 3, "Cancelar", UI.Colors.Bad, "TradeCancel")
end

-- No mostrar "Saquear" en tus criaturas ni "Me gusta" en tu nido (el servidor también lo
-- rechaza, pero así no confunde).
local function hideIfMine(instance: Instance)
	if not instance:IsA("ProximityPrompt") then
		return
	end
	local mine = false
	if instance.Name == "LootPrompt" then
		local model = instance:FindFirstAncestorOfClass("Model")
		mine = model ~= nil and model:GetAttribute("OwnerUserId") == player.UserId
	elseif instance.Name == "LikePrompt" then
		local nest = instance.Parent and instance.Parent.Parent
		mine = nest ~= nil and nest.Name == "Nest_" .. tostring(player:GetAttribute("NestIndex"))
	end
	if mine and not instance:GetAttribute("HiddenForOwner") then
		instance:SetAttribute("HiddenForOwner", true)
		instance.Enabled = false
		instance:GetPropertyChangedSignal("Enabled"):Connect(function()
			if instance.Enabled then
				instance.Enabled = false
			end
		end)
	end
end

function SocialController.start()
	gui = UI.screen("Social", 4)

	workspace.DescendantAdded:Connect(hideIfMine)
	local function scanNests()
		local map = workspace:FindFirstChild("Map")
		local nests = map and map:FindFirstChild("Nests")
		if nests then
			for _, descendant in nests:GetDescendants() do
				hideIfMine(descendant)
			end
		end
	end
	scanNests()
	player:GetAttributeChangedSignal("NestIndex"):Connect(scanNests)

	UI.button({
		Name = "Toggle",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 72),
		Size = UDim2.fromOffset(84, 64),
		Text = "🐦\nBandada",
	}, gui, function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			renderList()
		end
	end)

	panel = UI.frame({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.5, 0.6),
		Visible = false,
	}, gui)
	UI.round(panel, 16)
	UI.stroke(panel, UI.Colors.Good, 2)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(300, 260)
	constraint.MaxSize = Vector2.new(520, 480)
	constraint.Parent = panel
	UI.label({
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -64, 0, 40),
		Text = string.format("Bandada: hasta %d. Compartís el %d %% del Calor y, con un amigo, +%d %% de polvo.", Config.Party.MaxSize, math.floor(Config.Party.HeatShare * 100), math.floor(Config.Party.FriendDustBonus * 100)),
		TextWrapped = true,
	}, panel)
	UI.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(40, 40), Text = "✕", BackgroundColor3 = UI.Colors.Bad }, panel, function()
		panel.Visible = false
	end)
	list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(8, 56)
	list.Size = UDim2.new(1, -16, 1, -64)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel

	askPanel = UI.frame({
		Name = "Ask",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(340, 130),
		Visible = false,
	}, gui)
	UI.round(askPanel, 14)
	UI.stroke(askPanel, UI.Colors.Good, 2)
	askText = UI.label({ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 60), TextWrapped = true }, askPanel)
	local function answer(accept: boolean)
		local action = askAction
		askAction = nil
		askPanel.Visible = false
		if action then
			action(accept)
		end
	end
	UI.button({ Position = UDim2.new(0, 12, 1, -54), Size = UDim2.new(0.5, -18, 0, 44), Text = "Aceptar", BackgroundColor3 = UI.Colors.Good }, askPanel, function()
		answer(true)
	end)
	UI.button({ Position = UDim2.new(0.5, 6, 1, -54), Size = UDim2.new(0.5, -18, 0, 44), Text = "Rechazar", BackgroundColor3 = UI.Colors.Bad }, askPanel, function()
		answer(false)
	end)

	buildTrade()

	Remotes.event("PartyInvited").OnClientEvent:Connect(function(fromUserId: number, fromName: string)
		ask(string.format("🐦 %s te invita a su Bandada.", fromName), function(accept)
			Remotes.event("PartyRespond"):FireServer(fromUserId, accept)
		end)
	end)
	Remotes.event("TradeRequested").OnClientEvent:Connect(function(fromUserId: number, fromName: string)
		ask(string.format("🤝 %s quiere intercambiar criaturas contigo.", fromName), function(accept)
			Remotes.event("TradeRespond"):FireServer(fromUserId, accept)
		end)
	end)
	Remotes.event("TradeUpdated").OnClientEvent:Connect(function(view)
		trade = view
		if trade then
			panel.Visible = false
		end
		renderTrade()
		updateTradeStatus()
	end)
	Remotes.event("ProfileUpdated").OnClientEvent:Connect(function(view)
		profile = view
		if trade then
			renderTrade()
		end
	end)
	task.spawn(function()
		local ok, view = pcall(function()
			return Remotes.func("GetProfile"):InvokeServer()
		end)
		if ok and view and not profile then
			profile = view
		end
	end)

	-- Resaltar a la Bandada y mantener la lista al día.
	local function watchPlayer(other: Player)
		other:GetAttributeChangedSignal("PartyId"):Connect(function()
			refreshHighlights()
			if panel.Visible then
				renderList()
			end
		end)
		other.CharacterAdded:Connect(function()
			task.defer(refreshHighlights)
		end)
	end
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			if panel.Visible then
				renderList()
			end
		end)
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.25 then
			accumulator = 0
			updateTradeStatus()
		end
	end)
end

return SocialController
