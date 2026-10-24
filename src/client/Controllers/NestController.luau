--!strict
-- Panel del nido: criaturas y cría, incubadora, mejoras y Nueva generación, misiones y tienda.
-- Solo muestra datos y envía peticiones; el servidor valida costes y requisitos.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Cosmetics = require(Shared.Cosmetics)
local Economy = require(Shared.Economy)
local Rarity = require(Shared.Rarity)
local Remotes = require(Shared.Remotes)

local StoreController = require(script.Parent.StoreController)
local UI = require(script.Parent.Parent.UI)

local player = Players.LocalPlayer

local NestController = {}

local TABS: { string } = { "Criaturas", "Incubadora", "Mejoras", "Decorar", "Misiones", "Plaza", "🛒 Tienda" }

local panel: Frame
local content: ScrollingFrame
local footer: Frame
local tabButtons: { [string]: TextButton } = {}
local currentTab = "Criaturas"
local profile: any = nil
local selected: { string } = {}
local confirmRelease = "" -- qué liberación espera la segunda pulsación
local timeLabels: { [TextLabel]: number } = {}

local function rarityColor(name: any): Color3
	if Rarity.isValid(name) then
		return UI.rgb(Rarity.Info[name :: Rarity.RarityName].Color)
	end
	return UI.Colors.Text
end

local function row(height: number, order: number): Frame
	local f = UI.frame({ Size = UDim2.new(1, -8, 0, height), BackgroundColor3 = UI.Colors.PanelLight, LayoutOrder = order }, content)
	UI.round(f, 10)
	return f
end

local function serverNowOffset(): number
	-- Los tiempos del perfil van en os.time() del servidor; corregimos el desfase del reloj local.
	return if profile and profile.Now then profile.Now - os.time() else 0
end

local render: () -> ()

local function renderCreatures()
	if #profile.Creatures == 0 then
		UI.label({ Size = UDim2.new(1, 0, 0, 40), Text = "Aún no tienes criaturas. ¡Gana una persecución!" }, content)
	end
	-- Con una sola criatura elegida: ponerle nombre (v3.1). El servidor lo pasa por el filtro.
	if #selected == 1 then
		for _, creature in profile.Creatures do
			if creature.Id == selected[1] then
				local r = row(44, 0)
				local box = Instance.new("TextBox")
				box.Position = UDim2.fromOffset(8, 6)
				box.Size = UDim2.new(1, -196, 1, -12)
				box.BackgroundColor3 = UI.Colors.Panel
				box.TextColor3 = UI.Colors.Text
				box.PlaceholderText = "✏️ Nombre para " .. tostring(creature.Species or creature.Name)
				box.Text = creature.Nickname or ""
				box.ClearTextOnFocus = false
				box.Font = Enum.Font.GothamMedium
				box.TextScaled = true
				box.Parent = r
				UI.round(box, 8)
				UI.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -96, 0, 6), Size = UDim2.fromOffset(84, 32), Text = "Guardar", BackgroundColor3 = UI.Colors.Good }, r, function()
					Remotes.event("RenameCreature"):FireServer(creature.Id, box.Text)
				end)
				UI.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(84, 32), Text = "Quitar", BackgroundColor3 = UI.Colors.PanelLight }, r, function()
					Remotes.event("RenameCreature"):FireServer(creature.Id, "")
				end)
			end
		end
	end
	for index, creature in profile.Creatures do
		local isSelected = table.find(selected, creature.Id) ~= nil
		local r = row(48, index)
		if isSelected then
			UI.stroke(r, UI.Colors.Gold, 3)
		end
		local dot = UI.frame({ Position = UDim2.fromOffset(10, 14), Size = UDim2.fromOffset(20, 20), BackgroundColor3 = rarityColor(creature.Rarity), BackgroundTransparency = 0 }, r)
		UI.round(dot, 10)
		UI.label({ Position = UDim2.fromOffset(40, 4), Size = UDim2.new(0.55, -40, 0, 24), Text = creature.Name, TextXAlignment = Enum.TextXAlignment.Left }, r)
		UI.label({
			Position = UDim2.fromOffset(40, 26),
			Size = UDim2.new(0.55, -40, 0, 18),
			Text = (if creature.Nickname then tostring(creature.Species) .. " · " else "") .. creature.RarityName .. (if creature.InNest then " · en el nido" else " · guardada") .. (if creature.Favorite then " · ⭐ favorita" else ""),
			TextColor3 = rarityColor(creature.Rarity),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, r)
		UI.label({
			Position = UDim2.new(0.55, 0, 0, 10),
			Size = UDim2.new(0.45, -104, 0, 28),
			Text = string.format("%s/s", UI.formatNumber(creature.Income)),
			TextColor3 = UI.Colors.Gold,
			TextXAlignment = Enum.TextXAlignment.Right,
		}, r)
		local hit = Instance.new("TextButton")
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.Size = UDim2.fromScale(1, 1)
		hit.Parent = r
		hit.Activated:Connect(function()
			local at = table.find(selected, creature.Id)
			if at then
				table.remove(selected, at)
			else
				table.insert(selected, creature.Id)
				if #selected > 2 then
					table.remove(selected, 1)
				end
			end
			confirmRelease = ""
			render()
		end)
		-- Favorita: sobrevive a la Nueva generación, no se libera (🦜 elige cuál llevas al hombro).
		local star = UI.button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(40, 36),
			Text = if creature.Favorite then "⭐" else "☆",
			BackgroundColor3 = if creature.Favorite then UI.Colors.Gold else UI.Colors.Panel,
		}, r, function()
			Remotes.event("ToggleFavorite"):FireServer(creature.Id)
		end)
		star.ZIndex = 3
		-- Al hombro: la criatura que te acompaña en el lobby y en la partida.
		local shoulder = UI.button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -52, 0.5, 0),
			Size = UDim2.fromOffset(40, 36),
			Text = "🦜",
			BackgroundColor3 = if creature.Shoulder then UI.Colors.Good else UI.Colors.Panel,
		}, r, function()
			Remotes.event("SetShoulder"):FireServer(creature.Id)
		end)
		shoulder.ZIndex = 3
	end

	local hidden = (profile.TotalCreatures or #profile.Creatures) - #profile.Creatures
	if hidden > 0 then
		UI.label({
			Size = UDim2.new(1, 0, 0, 26),
			Text = string.format("…y %d criaturas más que no están entre las %d mejores", hidden, #profile.Creatures),
			TextColor3 = UI.Colors.Muted,
			LayoutOrder = #profile.Creatures + 1,
		}, content)
	end

	local breedText = "Elige 2 criaturas para criar"
	if #selected == 2 then
		local best: Rarity.RarityName = "Common"
		for _, creature in profile.Creatures do
			if table.find(selected, creature.Id) and Rarity.isValid(creature.Rarity) then
				best = Rarity.max(best, creature.Rarity)
			end
		end
		breedText = string.format("Criar (%s 🪙 · %s)", UI.formatNumber(Economy.breedCost(best)), UI.formatTime(Economy.breedSeconds(best)))
	end
	UI.button({ Size = UDim2.new(0.6, -4, 1, 0), Text = breedText, BackgroundColor3 = if #selected == 2 then UI.Colors.Good else UI.Colors.PanelLight }, footer, function()
		if #selected == 2 then
			Remotes.event("RequestBreed"):FireServer(selected[1], selected[2])
			table.clear(selected)
		end
	end)

	-- Liberar: las seleccionadas, o si no hay ninguna, las guardadas de rareza baja.
	-- Siempre pide una segunda pulsación para confirmar.
	local releaseKey: string, releaseText: string, canRelease: boolean
	if #selected > 0 then
		local dust = 0
		canRelease = true
		for _, creature in profile.Creatures do
			if table.find(selected, creature.Id) then
				if creature.ReleaseDust then
					dust += creature.ReleaseDust
				else
					canRelease = false
				end
			end
		end
		releaseKey = "sel:" .. table.concat(selected, ",")
		releaseText = if canRelease then string.format("🕊️ Liberar (+%d ✨)", dust) else "🔒 No se puede liberar"
	else
		local stored = profile.StoredRelease or { Count = 0, Dust = 0 }
		canRelease = stored.Count > 0
		releaseKey = "stored"
		releaseText = if canRelease then string.format("🕊️ Liberar %d guardadas (+%d ✨)", stored.Count, stored.Dust) else "🕊️ Nada que liberar"
	end
	local confirming = canRelease and confirmRelease == releaseKey
	UI.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.4, -4, 1, 0),
		Text = if confirming then "¿Seguro? Pulsa otra vez" else releaseText,
		BackgroundColor3 = if confirming then UI.Colors.Bad elseif canRelease then UI.Colors.PanelLight else UI.Colors.Panel,
	}, footer, function()
		if not canRelease then
			return
		end
		if confirmRelease ~= releaseKey then
			confirmRelease = releaseKey
			render()
			return
		end
		confirmRelease = ""
		if #selected > 0 then
			Remotes.event("RequestRelease"):FireServer(table.clone(selected))
			table.clear(selected)
		else
			Remotes.event("RequestReleaseStored"):FireServer()
		end
		render()
	end)
end

-- Precio en Robux de un producto (lo pone el dueño en el Creator Hub; se pregunta a Roblox una
-- vez y se guarda). nil mientras no se sabe.
local robuxPrices: { [number]: number | false } = {}
local function robuxPrice(productId: number): number?
	local cached = robuxPrices[productId]
	if cached == nil then
		robuxPrices[productId] = false
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfoAsync(productId, Enum.InfoType.Product)
			end)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				robuxPrices[productId] = info.PriceInRobux
				if currentTab == "Plaza" then
					render()
				end
			end
		end)
		return nil
	end
	return if cached then cached else nil
end

-- Tienda de la Plaza (v3.1): estética con polvo (y, v3.2, con Robux si el artículo tiene
-- producto en Config.CosmeticProducts). Lo de hoy, y abajo lo que ya tienes.
local function renderPlaza()
	local cosmetics = profile.Cosmetics or { Owned = {}, Shop = {} }
	local owned = cosmetics.Owned or {}
	local function equipped(item: Cosmetics.Item): boolean
		return cosmetics[item.Kind] == item.Id
	end
	local function equipButton(r: Frame, item: Cosmetics.Item)
		local on = equipped(item)
		UI.button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(120, 34),
			Text = if on then "Quitártelo" else "Ponértelo",
			BackgroundColor3 = if on then UI.Colors.PanelLight else UI.Colors.Good,
		}, r, function()
			Remotes.event("EquipCosmetic"):FireServer(item.Kind, if on then nil else item.Id)
		end)
	end
	local info = row(40, 0)
	UI.label({ Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 1, -12), Text = string.format("🛍️ Hoy en la Plaza (cambia cada día) · tienes %s ✨", UI.formatNumber(profile.Dust or 0)), TextXAlignment = Enum.TextXAlignment.Left }, info)
	local order = 1
	for _, id in cosmetics.Shop or {} do
		local item = Cosmetics.get(id)
		if item then
			local r = row(48, order)
			order += 1
			UI.label({ Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -150, 0, 24), Text = item.Icon .. " " .. item.Name, TextXAlignment = Enum.TextXAlignment.Left }, r)
			UI.label({ Position = UDim2.fromOffset(12, 26), Size = UDim2.new(1, -150, 0, 18), Text = (if item.Kind == "Hat" then "Para tu criatura al hombro" else "Tema para tu nido"), TextColor3 = UI.Colors.Muted, TextXAlignment = Enum.TextXAlignment.Left }, r)
			if table.find(owned, item.Id) then
				equipButton(r, item)
			else
				local affordable = (profile.Dust or 0) >= item.Price
				local productId = Config.CosmeticProducts[item.Id] or 0
				UI.button({
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, if productId ~= 0 then -112 else -8, 0.5, 0),
					Size = UDim2.fromOffset(if productId ~= 0 then 100 else 120, 34),
					Text = string.format("%s ✨", UI.formatNumber(item.Price)),
					BackgroundColor3 = if affordable then UI.Colors.Accent else UI.Colors.Panel,
				}, r, function()
					Remotes.event("BuyCosmetic"):FireServer(item.Id)
				end)
				if productId ~= 0 then
					-- Con Robux: Roblox enseña su ventana de compra; si paga, el servidor lo entrega.
					local price = robuxPrice(productId)
					UI.button({
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -8, 0.5, 0),
						Size = UDim2.fromOffset(100, 34),
						Text = if price then "R$ " .. price else "R$ …",
						BackgroundColor3 = UI.Colors.Good,
					}, r, function()
						MarketplaceService:PromptProductPurchase(player, productId)
					end)
				end
			end
		end
	end
	if #owned > 0 then
		local title = row(32, order)
		order += 1
		UI.label({ Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 1, -8), Text = "🎒 Lo tuyo", TextXAlignment = Enum.TextXAlignment.Left }, title)
		for _, id in owned do
			local item = Cosmetics.get(id)
			if item then
				local r = row(44, order)
				order += 1
				UI.label({ Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -150, 1, -12), Text = item.Icon .. " " .. item.Name .. (if equipped(item) then " · puesto" else ""), TextXAlignment = Enum.TextXAlignment.Left }, r)
				equipButton(r, item)
			end
		end
	end
end

local function renderDecorations()
	local info = row(44, 0)
	UI.label({
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 1, -12),
		Text = string.format("Belleza del nido: ✨ %d · Solo estética: no cambia la producción ni la persecución.", profile.Beauty or 0),
		TextWrapped = true,
	}, info)
	for index, def in profile.Decorations or {} do
		local r = row(50, index)
		local symbol = if def.Currency == "Coins" then "🪙" else "✨ polvo"
		UI.label({
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(0.6, -12, 1, -12),
			Text = string.format("%s · belleza +%d", def.Name, def.Beauty),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, r)
		local balance = if def.Currency == "Coins" then profile.Coins else profile.Dust
		UI.button({
			Position = UDim2.new(0.6, 0, 0, 6),
			Size = UDim2.new(0.4, -10, 1, -12),
			Text = if def.Owned then "Colocada ✔" else string.format("%s %s", UI.formatNumber(def.Cost), symbol),
			BackgroundColor3 = if def.Owned then UI.Colors.PanelLight elseif balance >= def.Cost then UI.Colors.Good else UI.Colors.Panel,
		}, r, function()
			if not def.Owned then
				Remotes.event("RequestBuyDecoration"):FireServer(def.Id)
			end
		end)
	end
end

local function renderIncubator()
	UI.label({
		Size = UDim2.new(1, 0, 0, 30),
		Text = string.format("Huevos: %d / %d", #profile.Incubator, profile.IncubatorSlots),
		LayoutOrder = 0,
	}, content)
	local offset = serverNowOffset()
	for index, egg in profile.Incubator do
		local r = row(44, index)
		local names = { Personal = "Huevo personal", Breed = "Cría", Streak = "Huevo de racha", Season = "Huevo de temporada", Chosen = "Huevo del Elegido", Welcome = "Huevo de bienvenida", Daily = "Huevo del regalo" }
		UI.label({ Position = UDim2.fromOffset(12, 6), Size = UDim2.new(0.6, -12, 1, -12), Text = "🥚 " .. (names[egg.Kind] or egg.Kind), TextXAlignment = Enum.TextXAlignment.Left }, r)
		local t = UI.label({ Position = UDim2.new(0.6, 0, 0, 6), Size = UDim2.new(0.4, -12, 1, -12), TextXAlignment = Enum.TextXAlignment.Right }, r)
		timeLabels[t] = egg.ReadyAt - offset
	end
	local half = UDim2.new(0.5, -4, 1, 0)
	UI.button({ Size = half, Text = string.format("Comprar huevo (%d ✨)", profile.PersonalEggCost) }, footer, function()
		Remotes.event("RequestBuyEgg"):FireServer()
	end)
	UI.button({ Size = half, Position = UDim2.new(0.5, 4, 0, 0), Text = "Recoger listos", BackgroundColor3 = UI.Colors.Good }, footer, function()
		Remotes.event("RequestCollectEggs"):FireServer()
	end)
end

local function renderUpgrades()
	for index, upgrade in profile.Upgrades do
		local r = row(50, index)
		UI.label({
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(0.55, -12, 1, -12),
			Text = string.format("%s · nivel %d", upgrade.DisplayName, upgrade.Level),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, r)
		local cost = upgrade.Cost
		UI.button({
			Position = UDim2.new(0.55, 0, 0, 6),
			Size = UDim2.new(0.45, -10, 1, -12),
			Text = if cost then UI.formatNumber(cost) .. " 🪙" else "Máximo",
			BackgroundColor3 = if cost and profile.Coins >= cost then UI.Colors.Good else UI.Colors.PanelLight,
		}, r, function()
			Remotes.event("RequestUpgrade"):FireServer(upgrade.Name)
		end)
	end
	local info = row(70, 100)
	UI.label({
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 1, -12),
		Text = string.format(
			"Generación %d · Nueva generación con %d criaturas y %s 🪙: reinicia el nido a cambio de +%d %% de producción para siempre.",
			profile.Generation,
			profile.RebirthCreatures,
			UI.formatNumber(profile.RebirthCoins),
			math.floor(Config.Rebirth.MultiplierPerGeneration * 100)
		),
		TextWrapped = true,
	}, info)
	UI.button({ Size = UDim2.new(1, 0, 1, 0), Text = "🌱 Nueva generación", BackgroundColor3 = UI.Colors.Accent }, footer, function()
		Remotes.event("RequestRebirth"):FireServer()
	end)
end

local function renderQuests()
	UI.label({ Size = UDim2.new(1, 0, 0, 30), Text = string.format("Racha: %d / %d días", profile.Streak, Config.Quests.StreakDays), LayoutOrder = 0 }, content)
	for index, quest in profile.Quests do
		local r = row(48, index)
		UI.label({
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(0.7, -12, 1, -12),
			Text = (if quest.Done then "✅ " else "• ") .. quest.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if quest.Done then UI.Colors.Good else UI.Colors.Text,
		}, r)
		UI.label({ Position = UDim2.new(0.7, 0, 0, 6), Size = UDim2.new(0.3, -12, 1, -12), Text = string.format("%d/%d", quest.Progress, quest.Goal), TextXAlignment = Enum.TextXAlignment.Right }, r)
	end
	local s = profile.Stats
	local stats = row(56, 100)
	UI.label({
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 1, -12),
		Text = string.format("Robos: %d · Victorias: %d · Pactos cumplidos: %d · Traiciones: %d", s.Steals, s.Wins, s.PactsKept, s.PactsBroken),
		TextWrapped = true,
		TextColor3 = UI.Colors.Muted,
	}, stats)
end

local renderedTab = ""

render = function()
	-- Conserva el scroll si se vuelve a dibujar la misma pestaña (llega una vista nueva cada 10 s).
	local scroll = if renderedTab == currentTab then content.CanvasPosition else Vector2.zero
	renderedTab = currentTab
	UI.clear(content)
	UI.clear(footer)
	table.clear(timeLabels)
	-- UI.clear solo borra GuiObjects: el UIListLayout se crea una única vez.
	if not content:FindFirstChildOfClass("UIListLayout") then
		UI.list(content, 6)
	end
	task.defer(function()
		content.CanvasPosition = scroll
	end)
	for name, button in tabButtons do
		button.BackgroundColor3 = if name == currentTab then UI.Colors.Accent else UI.Colors.PanelLight
	end
	if not profile then
		UI.label({ Size = UDim2.new(1, 0, 0, 40), Text = "Cargando..." }, content)
		return
	end
	if currentTab == "Criaturas" then
		renderCreatures()
	elseif currentTab == "Incubadora" then
		renderIncubator()
	elseif currentTab == "Mejoras" then
		renderUpgrades()
	elseif currentTab == "Decorar" then
		renderDecorations()
	elseif currentTab == "Misiones" then
		renderQuests()
	else
		renderPlaza()
	end
end

function NestController.start()
	local gui = UI.screen("Nest", 3)

	-- GDD v3: el nido se gestiona en el lobby. En la partida el botón no aparece.
	local toggle = UI.button({
		Name = "Toggle",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(84, 64),
		Text = "🥚\nNido",
	}, gui, function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			render()
		end
	end)
	local function refreshToggle()
		local lobby = player:GetAttribute("InMatch") ~= true
		toggle.Visible = lobby
		if not lobby and panel then
			panel.Visible = false
		end
	end
	player:GetAttributeChangedSignal("InMatch"):Connect(refreshToggle)
	task.defer(refreshToggle)

	panel = UI.frame({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.62, 0.7),
		Visible = false,
	}, gui)
	UI.round(panel, 16)
	UI.stroke(panel, UI.Colors.Accent, 2)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(320, 300)
	constraint.MaxSize = Vector2.new(640, 560)
	constraint.Parent = panel

	local tabs = UI.frame({ Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -64, 0, 40), BackgroundTransparency = 1 }, panel)
	UI.list(tabs, 4, true)
	if not Config.Sinks.Decorations then
		table.remove(TABS, table.find(TABS, "Decorar") :: number)
	end
	for index, name in TABS do
		tabButtons[name] = UI.button({ Size = UDim2.new(1 / #TABS, -4, 1, 0), Text = name, LayoutOrder = index }, tabs, function()
			-- (v3.3) La tienda de Robux tiene su propia ventana (botón 🛒).
			if name == "🛒 Tienda" then
				panel.Visible = false
				StoreController.open()
				return
			end
			currentTab = name
			table.clear(selected)
			confirmRelease = ""
			render()
		end)
	end
	UI.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(40, 40), Text = "✕", BackgroundColor3 = UI.Colors.Bad }, panel, function()
		panel.Visible = false
	end)

	content = Instance.new("ScrollingFrame")
	content.Position = UDim2.fromOffset(8, 56)
	content.Size = UDim2.new(1, -16, 1, -120)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 6
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new()
	content.Parent = panel

	footer = UI.frame({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -8), Size = UDim2.new(1, -16, 0, 48), BackgroundTransparency = 1 }, panel)

	Remotes.event("ProfileUpdated").OnClientEvent:Connect(function(view)
		profile = view
		if panel.Visible then
			render()
		end
	end)
	task.spawn(function()
		local ok, view = pcall(function()
			return Remotes.func("GetProfile"):InvokeServer()
		end)
		if ok and view then
			profile = view
		end
	end)

	-- Cuenta atrás de los huevos.
	task.spawn(function()
		while true do
			task.wait(1)
			for label, readyAt in timeLabels do
				if label.Parent then
					local left = readyAt - os.time()
					label.Text = if left <= 0 then "¡Listo!" else UI.formatTime(left)
					label.TextColor3 = if left <= 0 then UI.Colors.Good else UI.Colors.Text
				end
			end
		end
	end)
end

return NestController
