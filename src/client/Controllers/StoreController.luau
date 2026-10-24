--!strict
-- Tienda 🛒 (v3.3, GDD 9): botón grande a la derecha (late y lleva una burbuja cuando hay algo
-- nuevo) y una ventana propia con secciones: Destacado, Pases, Monedas, Lobby y Club. Estilo
-- "cartoon brillante": tarjetas de colores con degradado, cintas, iconos que flotan y botones
-- de precio con brillo. Los precios se preguntan a Roblox (los pone el dueño en el Creator Hub)
-- y la compra la hace la ventana de Roblox; el servidor entrega (MonetizationService).
-- Avisos en momentos útiles (Store.pickNudge): pocos, con X, y nunca en la partida.
-- Solo en el lobby: la partida es justa y el dinero se gasta fuera de ella.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Rarity = require(Shared.Rarity)
local Remotes = require(Shared.Remotes)
local Store = require(Shared.Store)

local SoundController = require(script.Parent.SoundController)
local UI = require(script.Parent.Parent.UI)

local player = Players.LocalPlayer

local StoreController = {}

local gui: ScreenGui
local button: TextButton
local badge: Frame
local window: Frame
local tabsFrame: Frame
local content: ScrollingFrame
local balanceLabel: TextLabel
local nudgeFrame: Frame
local currentSection = "Featured"
local profile: any = nil
local openedThisSession = false
local render: () -> ()

local INK = Color3.fromRGB(40, 20, 70) -- contorno oscuro de los textos y tarjetas
local WHITE = Color3.new(1, 1, 1)

-- Cosas que se animan cada frame (iconos que flotan y brillos de los botones).
local floaters: { [GuiObject]: { Base: UDim2, Phase: number } } = {}
local shines: { [UIGradient]: number } = {}

local SECTIONS = {
	{ Id = "Featured", Name = "Destacado", Icon = "🔥" },
	{ Id = "Passes", Name = "Pases", Icon = "⭐" },
	{ Id = "Coins", Name = "Monedas", Icon = "🪙" },
	{ Id = "Lobby", Name = "Lobby", Icon = "🎉" },
	{ Id = "Club", Name = "Club", Icon = "💛" },
}

-- ------------------------------------------------------------------ precios (de Roblox)
local prices: { [string]: string | false } = {}

local function priceText(offer: Store.Offer): string?
	local key = offer.Kind .. ":" .. offer.Key
	local cached = prices[key]
	if cached == nil then
		prices[key] = false
		task.spawn(function()
			local id = Store.productId(offer)
			local ok, info = pcall(function(): any
				if offer.Kind == "Club" then
					return MarketplaceService:GetSubscriptionProductInfoAsync(id :: string)
				end
				return MarketplaceService:GetProductInfoAsync(id :: number, if offer.Kind == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product)
			end)
			if ok and type(info) == "table" then
				if type(info.PriceInRobux) == "number" then
					prices[key] = "R$ " .. Store.formatThousands(info.PriceInRobux)
				elseif type(info.DisplayPrice) == "string" then
					prices[key] = info.DisplayPrice .. " /mes"
				end
				if window and window.Visible then
					render()
				end
			end
		end)
		return nil
	end
	return if cached then cached else nil
end

-- Precio en Robux como número (para el "+X % extra" de los packs).
local function robux(offer: Store.Offer): number?
	local text = priceText(offer)
	if not text then
		return nil
	end
	local digits = text:gsub("%D", "")
	return tonumber(digits)
end

local function owned(offer: Store.Offer): boolean
	if offer.Kind == "Pass" then
		return player:GetAttribute("Pass_" .. offer.Key) == true
	elseif offer.Kind == "Club" then
		return player:GetAttribute("Pass_Club") == true
	end
	return false
end

local function restricted(): boolean
	return player:GetAttribute("PaidRandomRestricted") ~= false
end

local function starterEndsAt(): number?
	return if profile and profile.Store then profile.Store.StarterEndsAt else nil
end

local function serverNow(): number
	return if profile and profile.Now then os.time() + (profile.Now - (profile.ReceivedAt or os.time())) else os.time()
end

local lastPromptAt = -math.huge -- para celebrar solo lo que se acaba de comprar

local function prompt(offer: Store.Offer)
	if not Store.isConfigured(offer) or owned(offer) then
		return
	end
	lastPromptAt = os.clock()
	local id = Store.productId(offer)
	if offer.Kind == "Pass" then
		MarketplaceService:PromptGamePassPurchase(player, id :: number)
	elseif offer.Kind == "Club" then
		MarketplaceService:PromptSubscriptionPurchase(player, id :: string)
	else
		MarketplaceService:PromptProductPurchase(player, id :: number)
	end
end

local function oddsText(range: { Min: string, Max: string }): string
	local parts = {}
	local chances = Rarity.chances(1, range.Min :: Rarity.RarityName, range.Max :: Rarity.RarityName)
	for _, name in Rarity.Order do
		local chance = chances[name]
		if chance > 0 then
			table.insert(parts, string.format("%s %.1f %%", Rarity.Info[name].DisplayName, chance * 100))
		end
	end
	return table.concat(parts, " · ")
end

-- ------------------------------------------------------------------ piezas de estilo
local function gradient(parent: GuiObject, top: Color3, bottom: Color3, rotation: number?)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	g.Parent = parent
end

local function lighter(color: Color3, amount: number): Color3
	return color:Lerp(WHITE, amount)
end

local function bold(props: { [string]: any }, parent: Instance): TextLabel
	local clean = table.clone(props)
	clean.Stroke = nil
	local label = UI.label(clean, parent)
	label.TextStrokeTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = props.Stroke or 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	return label
end

-- Cambia las esquinas y el borde que pone UI.button.
local function restyle(b: GuiObject, radius: number, color: Color3, thickness: number)
	local corner = b:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, radius)
	end
	local stroke = b:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Thickness = thickness
		stroke.Transparency = 0
	end
end

-- Botón que se hunde al pulsarlo.
local function squish(target: GuiButton)
	local scale = Instance.new("UIScale")
	scale.Parent = target
	local info = TweenInfo.new(0.08, Enum.EasingStyle.Quad)
	target.MouseButton1Down:Connect(function()
		TweenService:Create(scale, info, { Scale = 0.92 }):Play()
	end)
	local function up()
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	target.MouseButton1Up:Connect(up)
	target.MouseLeave:Connect(up)
end

-- Barra de brillo que cruza un botón cada pocos segundos.
local function shine(target: GuiObject)
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Rotation = 20
	g.Offset = Vector2.new(2, 0)
	g.Parent = target
	shines[g] = math.random() * 3
end

local function priceButton(offer: Store.Offer, parent: Instance, props: { [string]: any }): TextButton
	local isOwned = owned(offer)
	local configured = Store.isConfigured(offer)
	local text = if isOwned then "✔ ¡TUYO!" elseif not configured then "Pronto" else (priceText(offer) or "R$ …")
	local color = if isOwned or not configured then Color3.fromRGB(150, 140, 170) else Color3.fromRGB(60, 205, 90)
	local b = UI.button({
		Text = "",
		BackgroundColor3 = color,
		AutoButtonColor = false,
	}, parent, function()
		prompt(offer)
	end)
	for key, value in props do
		(b :: any)[key] = value
	end
	restyle(b, 14, INK, 3)
	gradient(b, lighter(color, 0.35), color)
	bold({ Size = UDim2.new(1, -12, 1, -8), Position = UDim2.fromOffset(6, 4), Text = text }, b)
	if configured and not isOwned then
		squish(b)
		local glow = UI.frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.35, ZIndex = 2 }, b)
		UI.round(glow, 14)
		shine(glow)
	end
	return b
end

local function ribbon(text: string, parent: Instance)
	local r = UI.frame({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 8, 0, -8),
		Size = UDim2.fromOffset(118, 28),
		BackgroundColor3 = Color3.fromRGB(240, 50, 80),
		BackgroundTransparency = 0,
		Rotation = 8,
		ZIndex = 5,
	}, parent)
	UI.round(r, 8)
	UI.stroke(r, INK, 2)
	gradient(r, Color3.fromRGB(255, 110, 120), Color3.fromRGB(220, 30, 70))
	bold({ Size = UDim2.new(1, -8, 1, -6), Position = UDim2.fromOffset(4, 3), Text = text, ZIndex = 6 }, r)
end

local function floatingIcon(icon: string, parent: Instance, props: { [string]: any }): TextLabel
	local label = UI.label({ Text = icon, TextStrokeTransparency = 1 }, parent)
	for key, value in props do
		(label :: any)[key] = value
	end
	floaters[label] = { Base = label.Position, Phase = math.random() * math.pi * 2 }
	return label
end

local function card(offer: Store.Offer, parent: Instance, order: number): Frame
	local color = UI.rgb(offer.Color)
	local f = UI.frame({ BackgroundColor3 = color, BackgroundTransparency = 0, LayoutOrder = order }, parent)
	UI.round(f, 18)
	UI.stroke(f, WHITE, 3)
	gradient(f, lighter(color, 0.45), color)
	if offer.Tag then
		ribbon(offer.Tag, f)
	end
	-- Círculo claro detrás del icono.
	local halo = UI.frame({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(78, 78), BackgroundColor3 = WHITE, BackgroundTransparency = 0.55 }, f)
	UI.round(halo, 39)
	floatingIcon(offer.Icon, f, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(70, 70) })
	bold({ Position = UDim2.new(0, 8, 0, 92), Size = UDim2.new(1, -16, 0, 26), Text = offer.Name, Stroke = 2.5 }, f)
	local desc = offer.Desc
	if offer.Key == "SeasonEgg" then
		desc = oddsText(Config.EggRanges.Season)
	end
	bold({ Position = UDim2.new(0, 10, 0, 120), Size = UDim2.new(1, -20, 1, -176), Text = desc, TextWrapped = true, Stroke = 1.5, TextColor3 = Color3.fromRGB(255, 255, 240) }, f)
	-- "+X % extra" en los packs de Monedas, con los precios de verdad.
	if offer.Coins then
		local base = Store.find("CoinsSmall") :: Store.Offer
		local price, basePrice = robux(offer), robux(base)
		local bonus = if price and basePrice then Store.coinBonus(offer.Coins, price, base.Coins :: number, basePrice) else nil
		if bonus then
			local chip = UI.frame({ AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(-6, -8), Size = UDim2.fromOffset(92, 26), BackgroundColor3 = Color3.fromRGB(255, 230, 60), BackgroundTransparency = 0, Rotation = -8, ZIndex = 5 }, f)
			UI.round(chip, 8)
			UI.stroke(chip, INK, 2)
			UI.label({ Size = UDim2.new(1, -8, 1, -6), Position = UDim2.fromOffset(4, 3), Text = string.format("+%d %% extra", bonus), TextColor3 = INK, TextStrokeTransparency = 1, ZIndex = 6 }, chip)
		end
	end
	priceButton(offer, f, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -24, 0, 44) })
	return f
end

local function grid(height: number, cellHeight: number, order: number): Frame
	local holder = UI.frame({ Size = UDim2.new(1, -8, 0, height), BackgroundTransparency = 1, LayoutOrder = order }, content)
	local layout = Instance.new("UIGridLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.CellPadding = UDim2.fromOffset(14, 16)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	-- AbsoluteSize incluye la UIScale de la animación de abrir: se deshace.
	local scale = (window:FindFirstChildOfClass("UIScale") :: UIScale).Scale
	local width = math.max(content.AbsoluteSize.X / math.max(scale, 0.1) - 24, 280)
	local columns = math.clamp(math.floor((width + 14) / 190), 2, 4)
	layout.CellSize = UDim2.fromOffset(math.floor((width - 14 * (columns - 1)) / columns), cellHeight)
	layout.Parent = holder
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		holder.Size = UDim2.new(1, -8, 0, layout.AbsoluteContentSize.Y + 12)
	end)
	return holder
end

local function heading(text: string, order: number)
	bold({ Size = UDim2.new(1, -8, 0, 34), Text = text, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order, TextColor3 = Color3.fromRGB(255, 230, 90), Stroke = 2.5 }, content)
end

local function dayHours(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 86400 then
		return string.format("%d d %d h", s // 86400, (s % 86400) // 3600)
	end
	return string.format("%d h %d min", s // 3600, (s % 3600) // 60)
end

-- Banner grande de arriba: el pack de inicio (si toca) o la oferta estrella.
local function banner(order: number)
	local ends = starterEndsAt()
	local offer: Store.Offer? = nil
	for _, key in Store.FeaturedOrder do
		local candidate = Store.find(key)
		if candidate and (candidate.Kind ~= "Starter" or ends) and Store.isConfigured(candidate) and not owned(candidate) then
			offer = candidate
			break
		end
	end
	if not offer then
		offer = Store.find("ServerLuck")
	end
	local o = offer :: Store.Offer
	local color = UI.rgb(o.Color)
	local f = UI.frame({ Size = UDim2.new(1, -16, 0, 176), BackgroundColor3 = color, BackgroundTransparency = 0, LayoutOrder = order }, content)
	UI.round(f, 22)
	UI.stroke(f, Color3.fromRGB(255, 230, 90), 4)
	gradient(f, lighter(color, 0.4), color, 0)
	if o.Tag then
		ribbon(o.Tag, f)
	end
	floatingIcon(o.Icon, f, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(120, 120) })
	bold({ Position = UDim2.fromOffset(146, 12), Size = UDim2.new(1, -160, 0, 40), Text = o.Name:upper(), TextXAlignment = Enum.TextXAlignment.Left, Stroke = 3 }, f)
	local lines: { string }
	if o.Kind == "Starter" then
		lines = Store.starterContents(restricted())
		if ends then
			table.insert(lines, "⏳ Quedan " .. dayHours(ends - serverNow()))
		end
	else
		lines = { o.Desc }
	end
	bold({ Position = UDim2.fromOffset(146, 54), Size = UDim2.new(0.62, -150, 1, -66), Text = table.concat(lines, "\n"), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextScaled = true, Stroke = 1.5 }, f)
	priceButton(o, f, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.new(0.34, 0, 0, 58) })
end

local function sectionOffers(id: string): { Store.Offer }
	for _, section in Store.Sections do
		if section.Id == id then
			local list = {}
			for _, offer in section.Offers do
				if not (offer.Random and restricted()) then
					table.insert(list, offer)
				end
			end
			return list
		end
	end
	return {}
end

local function renderOffers(list: { Store.Offer }, order: number)
	local g = grid(240, 236, order)
	for index, offer in list do
		card(offer, g, index)
	end
end

local function renderClub()
	local offer = Store.find("Club") :: Store.Offer
	local f = UI.frame({ Size = UDim2.new(1, -16, 0, 300), BackgroundColor3 = UI.rgb(offer.Color), BackgroundTransparency = 0, LayoutOrder = 1 }, content)
	UI.round(f, 22)
	UI.stroke(f, WHITE, 4)
	gradient(f, Color3.fromRGB(255, 235, 140), Color3.fromRGB(255, 160, 40))
	floatingIcon("💛", f, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(90, 90) })
	bold({ Position = UDim2.new(0, 12, 0, 104), Size = UDim2.new(1, -24, 0, 40), Text = "CLUB DEL NIDO", Stroke = 3 }, f)
	bold({ Position = UDim2.new(0, 24, 0, 148), Size = UDim2.new(1, -48, 0, 70), Text = offer.Desc, TextWrapped = true, Stroke = 1.5 }, f)
	priceButton(offer, f, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.new(0.5, 0, 0, 58) })
end

render = function()
	if not window then
		return
	end
	UI.clear(content)
	table.clear(floaters)
	table.clear(shines)
	if not content:FindFirstChildOfClass("UIListLayout") then
		local layout = UI.list(content, 14)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	end
	for _, child in tabsFrame:GetChildren() do
		if child:IsA("TextButton") then
			local on = child.Name == currentSection
			child.BackgroundColor3 = if on then Color3.fromRGB(255, 215, 60) else Color3.fromRGB(110, 70, 200)
			local label = child:FindFirstChildOfClass("TextLabel")
			if label then
				label.TextColor3 = if on then INK else WHITE
			end
		end
	end
	balanceLabel.Text = string.format("🪙 %s", UI.formatNumber(profile and profile.Coins or 0))
	if currentSection == "Featured" then
		banner(1)
		heading("🔥 Lo más comprado", 2)
		local picks = {}
		for _, key in { "DoubleCoins", "CoinsLarge", "ServerLuck", "Fireworks" } do
			local offer = Store.find(key)
			if offer then
				table.insert(picks, offer)
			end
		end
		renderOffers(picks, 3)
	elseif currentSection == "Club" then
		renderClub()
	else
		renderOffers(sectionOffers(currentSection), 1)
	end
	local note = UI.label({ Size = UDim2.new(1, -16, 0, 22), LayoutOrder = 99, TextColor3 = Color3.fromRGB(230, 220, 255), Text = "Nada de la tienda te hace ganar la partida: es para tu nido y para lucirte 💛" }, content)
	note.TextStrokeTransparency = 1
	content.CanvasPosition = Vector2.zero
end

-- ------------------------------------------------------------------ ventana y botón
local function setOpen(open: boolean, section: string?)
	if section then
		currentSection = section
	end
	if open then
		openedThisSession = true
		badge.Visible = false
		window.Visible = true
		local scale = window:FindFirstChildOfClass("UIScale") :: UIScale
		scale.Scale = 0.6
		TweenService:Create(scale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		render()
	else
		window.Visible = false
	end
end

function StoreController.open(section: string?)
	setOpen(true, section)
end

-- Confeti en la pantalla al comprar algo (¡gracias!).
local function confetti()
	SoundController.play("Fanfare")
	local colors = { Color3.fromRGB(255, 90, 140), Color3.fromRGB(255, 215, 60), Color3.fromRGB(90, 200, 255), Color3.fromRGB(110, 230, 120), Color3.fromRGB(190, 120, 255) }
	for _ = 1, 60 do
		local piece = UI.frame({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.45),
			Size = UDim2.fromOffset(math.random(8, 14), math.random(12, 20)),
			BackgroundColor3 = colors[math.random(#colors)],
			BackgroundTransparency = 0,
			Rotation = math.random(0, 360),
			ZIndex = 20,
		}, gui)
		local angle = math.random() * math.pi * 2
		local distance = 0.25 + math.random() * 0.35
		local tween = TweenService:Create(piece, TweenInfo.new(1.4 + math.random() * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5 + math.cos(angle) * distance, 0.45 + math.sin(angle) * distance + 0.15),
			Rotation = piece.Rotation + math.random(-360, 360),
			BackgroundTransparency = 1,
		})
		tween.Completed:Connect(function()
			piece:Destroy()
		end)
		tween:Play()
	end
	local thanks = bold({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(420, 70), Text = "¡GRACIAS! 💛", TextColor3 = Color3.fromRGB(255, 225, 70), ZIndex = 21, Stroke = 4 }, gui)
	task.delay(1.8, function()
		thanks:Destroy()
	end)
end

local function buildButton()
	button = UI.button({
		Name = "StoreButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 114),
		Size = UDim2.fromOffset(104, 92),
		Text = "",
		BackgroundColor3 = Color3.fromRGB(255, 190, 40),
		AutoButtonColor = false,
		Visible = false,
	}, gui, function()
		setOpen(not window.Visible)
	end)
	restyle(button, 22, INK, 4)
	gradient(button, Color3.fromRGB(255, 240, 120), Color3.fromRGB(255, 150, 30))
	UI.label({ Position = UDim2.fromOffset(6, 4), Size = UDim2.new(1, -12, 0, 50), Text = "🛒", TextStrokeTransparency = 1 }, button)
	bold({ Position = UDim2.new(0, 6, 1, -36), Size = UDim2.new(1, -12, 0, 30), Text = "TIENDA", Stroke = 3 }, button)
	local glow = UI.frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.3, ZIndex = 2 }, button)
	UI.round(glow, 22)
	shine(glow)
	squish(button)
	badge = UI.frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(30, 30), BackgroundColor3 = Color3.fromRGB(240, 40, 60), BackgroundTransparency = 0, ZIndex = 4 }, button)
	UI.round(badge, 15)
	UI.stroke(badge, WHITE, 2)
	bold({ Size = UDim2.fromScale(1, 1), Text = "!", ZIndex = 5 }, badge)
end

local function buildWindow()
	window = UI.frame({
		Name = "Store",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.86, 0.84),
		BackgroundColor3 = Color3.fromRGB(110, 60, 210),
		BackgroundTransparency = 0,
		Visible = false,
		ZIndex = 1,
	}, gui)
	Instance.new("UIScale").Parent = window
	local limits = Instance.new("UISizeConstraint")
	limits.MinSize = Vector2.new(340, 320)
	limits.MaxSize = Vector2.new(920, 640)
	limits.Parent = window
	UI.round(window, 26)
	UI.stroke(window, WHITE, 5)
	gradient(window, Color3.fromRGB(140, 80, 240), Color3.fromRGB(60, 120, 250))

	-- Cabecera: título, saldo y cerrar.
	bold({ Position = UDim2.fromOffset(18, 10), Size = UDim2.new(0.45, -18, 0, 52), Text = "🛒 TIENDA", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 225, 70), Stroke = 4 }, window)
	local balance = UI.frame({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -78, 0, 16), Size = UDim2.fromOffset(150, 40), BackgroundColor3 = INK, BackgroundTransparency = 0.35 }, window)
	UI.round(balance, 20)
	balanceLabel = UI.label({ Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 1, -8), TextColor3 = UI.Colors.Gold, Text = "" }, balance)
	local close = UI.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), Size = UDim2.fromOffset(52, 52), Text = "✕", BackgroundColor3 = Color3.fromRGB(240, 60, 80) }, window, function()
		setOpen(false)
	end)
	restyle(close, 26, WHITE, 3)
	squish(close)

	-- Pestañas de sección (desplazables en pantallas estrechas).
	local tabsScroll = Instance.new("ScrollingFrame")
	tabsScroll.Position = UDim2.fromOffset(14, 72)
	tabsScroll.Size = UDim2.new(1, -28, 0, 50)
	tabsScroll.BackgroundTransparency = 1
	tabsScroll.BorderSizePixel = 0
	tabsScroll.ScrollBarThickness = 0
	tabsScroll.ScrollingDirection = Enum.ScrollingDirection.X
	tabsScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabsScroll.CanvasSize = UDim2.new()
	tabsScroll.Parent = window
	tabsFrame = UI.frame({ Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, tabsScroll)
	UI.list(tabsFrame, 8, true)
	for index, section in SECTIONS do
		local tab = UI.button({ Name = section.Id, Size = UDim2.fromOffset(136, 44), Text = "", LayoutOrder = index, AutoButtonColor = false }, tabsFrame, function()
			currentSection = section.Id
			render()
		end)
		restyle(tab, 22, WHITE, 3)
		UI.label({ Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 1, -12), Text = section.Icon .. " " .. section.Name, TextStrokeTransparency = 1 }, tab)
		squish(tab)
	end

	content = Instance.new("ScrollingFrame")
	content.Position = UDim2.fromOffset(10, 132)
	content.Size = UDim2.new(1, -20, 1, -142)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 8
	content.ScrollBarImageColor3 = Color3.fromRGB(255, 225, 70)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new()
	content.Parent = window
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = content
end

-- ------------------------------------------------------------------ avisos (Store.pickNudge)
local nudgeShown: { [string]: boolean } = {}
local lastNudgeAt = 0
local lobbySince: number? = nil

local function hideNudge()
	if nudgeFrame.Visible then
		local tween = TweenService:Create(nudgeFrame, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 1, 120) })
		tween.Completed:Connect(function()
			nudgeFrame.Visible = false
		end)
		tween:Play()
	end
end

local function showNudge(nudge: Store.Nudge)
	UI.clear(nudgeFrame)
	UI.label({ Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(60, 60), Text = nudge.Icon, TextStrokeTransparency = 1 }, nudgeFrame)
	bold({ Position = UDim2.fromOffset(76, 8), Size = UDim2.new(1, -230, 1, -16), Text = nudge.Text, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Stroke = 1.5 }, nudgeFrame)
	local see = UI.button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -52, 0.5, 0), Size = UDim2.fromOffset(96, 48), Text = "¡Ver!", BackgroundColor3 = Color3.fromRGB(60, 205, 90) }, nudgeFrame, function()
		hideNudge()
		local offer = Store.find(nudge.Offer)
		local section = if offer and offer.Kind == "Pass" then "Passes" elseif offer and offer.Coins then "Coins" else "Featured"
		setOpen(true, section)
	end)
	restyle(see, 14, INK, 3)
	squish(see)
	local x = UI.button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(36, 36), Text = "✕", BackgroundColor3 = Color3.fromRGB(150, 140, 170) }, nudgeFrame, hideNudge)
	restyle(x, 18, INK, 2)
	nudgeFrame.Position = UDim2.new(0.5, 0, 1, 120)
	nudgeFrame.Visible = true
	TweenService:Create(nudgeFrame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 1, -96) }):Play()
	SoundController.play("Alert")
	task.delay(12, function()
		if nudgeFrame.Visible then
			hideNudge()
		end
	end)
end

local function checkNudge()
	if not profile or window.Visible or not button.Visible or lobbySince == nil then
		return
	end
	-- Durante el tutorial (antes de la primera partida) no se molesta.
	if (tonumber(player:GetAttribute("RoundsPlayed")) or 0) < 1 then
		return
	end
	local now = serverNow()
	local longest = 0
	for _, egg in profile.Incubator or {} do
		longest = math.max(longest, (egg.ReadyAt or 0) - now)
	end
	local cheapest: number? = nil
	for _, upgrade in profile.Upgrades or {} do
		if upgrade.Cost and (cheapest == nil or upgrade.Cost < cheapest) then
			cheapest = upgrade.Cost
		end
	end
	local passes = {}
	for key in Config.GamePasses do
		passes[key] = player:GetAttribute("Pass_" .. key) == true
	end
	local nudge = Store.pickNudge({
		Now = os.clock(),
		Passes = passes,
		Slots = profile.Slots or 0,
		TotalCreatures = profile.TotalCreatures or 0,
		LongestWait = longest,
		Coins = profile.Coins or 0,
		CheapestUpgrade = cheapest,
		StarterEndsAt = starterEndsAt(),
		Shown = nudgeShown,
		LastShownAt = lastNudgeAt,
		SessionSeconds = os.clock() - (lobbySince :: number),
	})
	if nudge then
		nudgeShown[nudge.Id] = true
		lastNudgeAt = os.clock()
		showNudge(nudge)
	end
end

local function buildNudge()
	nudgeFrame = UI.frame({
		Name = "StoreNudge",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 120),
		Size = UDim2.new(0.9, 0, 0, 76),
		BackgroundColor3 = Color3.fromRGB(120, 70, 220),
		BackgroundTransparency = 0,
		Visible = false,
		ZIndex = 3,
	}, gui)
	local limits = Instance.new("UISizeConstraint")
	limits.MaxSize = Vector2.new(520, 76)
	limits.Parent = nudgeFrame
	UI.round(nudgeFrame, 20)
	UI.stroke(nudgeFrame, WHITE, 3)
	gradient(nudgeFrame, Color3.fromRGB(160, 100, 250), Color3.fromRGB(90, 70, 220))
end

-- ------------------------------------------------------------------ arranque
local function refreshVisible()
	local inLobby = player:GetAttribute("InMatch") ~= true and player:GetAttribute("LobbyNestIndex") ~= nil
	button.Visible = inLobby
	if not inLobby then
		window.Visible = false
		nudgeFrame.Visible = false
		lobbySince = nil
	elseif lobbySince == nil then
		lobbySince = os.clock()
	end
	badge.Visible = not openedThisSession
end

local function setProfile(view: any)
	if type(view) ~= "table" then
		return
	end
	local hadStarter = profile and profile.Store and profile.Store.StarterBought == false
	view.ReceivedAt = os.time()
	profile = view
	if hadStarter and view.Store and view.Store.StarterBought == true and os.clock() - lastPromptAt < 300 then
		confetti() -- el pack de inicio acaba de llegar
	end
	if window.Visible then
		render()
	end
end

function StoreController.start()
	gui = UI.screen("Store", 6)
	buildButton()
	buildWindow()
	buildNudge()

	player:GetAttributeChangedSignal("InMatch"):Connect(refreshVisible)
	player:GetAttributeChangedSignal("LobbyNestIndex"):Connect(refreshVisible)
	task.defer(refreshVisible)

	-- Un pase recién comprado: confeti y la tarjeta pasa a "¡TUYO!".
	local known: { [string]: boolean } = {}
	player.AttributeChanged:Connect(function(name)
		if name:sub(1, 5) == "Pass_" or name == "PaidRandomRestricted" then
			local value = player:GetAttribute(name) == true
			if value and known[name] == false and os.clock() - lastPromptAt < 300 then
				confetti()
			end
			known[name] = value
			if window.Visible then
				render()
			end
		end
	end)
	for key in Config.GamePasses do
		known["Pass_" .. key] = player:GetAttribute("Pass_" .. key) == true
	end
	known.Pass_Club = player:GetAttribute("Pass_Club") == true

	Remotes.event("ProfileUpdated").OnClientEvent:Connect(setProfile)
	task.spawn(function()
		local ok, view = pcall(function()
			return Remotes.func("GetProfile"):InvokeServer()
		end)
		if ok then
			setProfile(view)
		end
	end)

	-- Animaciones: el botón late, los iconos flotan y los brillos cruzan los botones.
	local badgeScale = Instance.new("UIScale")
	badgeScale.Parent = badge
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		if button.Visible then
			button.Rotation = math.sin(t * 2.2) * 3
			badgeScale.Scale = 1 + math.max(math.sin(t * 4), 0) * 0.18
		end
		if window.Visible then
			for label, info in floaters do
				label.Position = info.Base + UDim2.fromOffset(0, math.sin(t * 2 + info.Phase) * 4)
			end
		end
		for g, phase in shines do
			-- Cada 3 s cruza una vez (offset de -1 a 1), el resto del tiempo fuera.
			local k = ((t + phase) % 3) / 0.7
			g.Offset = Vector2.new(if k <= 1 then -1 + k * 2 else 2, 0)
		end
	end)

	-- Al girar el móvil o cambiar el tamaño de la ventana, las columnas se recalculan.
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if window.Visible then
				render()
			end
		end)
	end

	task.spawn(function()
		while true do
			task.wait(15)
			checkNudge()
		end
	end)
end

return StoreController
