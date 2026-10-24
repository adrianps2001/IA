--!strict
-- Tienda 🛒 (v3.3, GDD 9): qué se enseña en cada sección, el pack de inicio, el "+X % extra" de
-- los packs de Monedas y los avisos en momentos útiles. Solo datos y cuentas (se prueba sin
-- Roblox); la ventana la dibuja StoreController y lo que se compra lo entrega el servidor.
-- Reglas: nada de pago cambia la partida, lo aleatorio enseña sus probabilidades y no hay
-- cuentas atrás falsas (el pack de inicio acaba de verdad a los Config.Store.Starter.OfferDays).

local Config = require("./Config")

local Store = {}

export type Kind = "Pass" | "Product" | "Club" | "Starter"
export type Offer = {
	Key: string, -- clave de Config.GamePasses / Config.DevProducts ("Club" para la suscripción)
	Kind: Kind,
	Icon: string,
	Name: string,
	Desc: string,
	Color: { number }, -- color de la tarjeta (RGB)
	Tag: string?, -- cinta de la tarjeta ("MÁS POPULAR"…)
	Random: boolean?, -- objeto aleatorio de pago: no se enseña donde la ley lo restringe
	Coins: number?, -- packs de Monedas: cuántas da
}
export type Section = { Id: string, Name: string, Icon: string, Offers: { Offer } }

local GOLD = { 255, 196, 48 }
local GREEN = { 80, 200, 110 }
local BLUE = { 70, 160, 255 }
local PURPLE = { 170, 100, 255 }
local PINK = { 255, 100, 170 }
local ORANGE = { 255, 140, 50 }

local function coins(key: string, icon: string, tag: string?): Offer
	return {
		Key = key,
		Kind = "Product",
		Icon = icon,
		Name = string.format("%s Monedas", Store.formatThousands(Config.CoinPacks[key])),
		Desc = "Para mejoras, crías y decoración",
		Color = GOLD,
		Tag = tag,
		Coins = Config.CoinPacks[key],
	}
end

-- Miles con punto: 180000 → "180.000".
function Store.formatThousands(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if out:sub(1, 1) == "." then
		out = out:sub(2)
	end
	return out
end

Store.Sections = {
	{
		Id = "Passes",
		Name = "Pases",
		Icon = "⭐",
		Offers = {
			{ Key = "DoubleCoins", Kind = "Pass", Icon = "🪙", Name = "x2 Monedas", Desc = "Tu nido produce el doble. Para siempre", Color = GOLD, Tag = "MÁS POPULAR" },
			{ Key = "VipNest", Kind = "Pass", Icon = "👑", Name = "Nido VIP", Desc = "+10 ranuras, nido dorado y etiqueta VIP", Color = PURPLE },
			{ Key = "FastIncubator", Kind = "Pass", Icon = "⏩", Name = "Incubadora Rápida", Desc = "Los huevos y las crías tardan la mitad", Color = BLUE },
			{ Key = "ExtraBreedSlot", Kind = "Pass", Icon = "➕", Name = "Ranura de cría", Desc = "Dos huevos a la vez en la incubadora", Color = GREEN },
			{ Key = "EmberTrail", Kind = "Pass", Icon = "🔥", Name = "Estela de Brasas", Desc = "Chispas al correr. Solo se ve bonito", Color = ORANGE },
		},
	},
	{
		Id = "Coins",
		Name = "Monedas",
		Icon = "🪙",
		Offers = {
			coins("CoinsSmall", "🪙"),
			coins("CoinsMedium", "💰"),
			coins("CoinsLarge", "🏦", "MÁS POPULAR"),
			coins("CoinsHuge", "💎", "MEJOR VALOR"),
		},
	},
	{
		Id = "Lobby",
		Name = "Lobby",
		Icon = "🎉",
		Offers = {
			{ Key = "ServerLuck", Kind = "Product", Icon = "🍀", Name = "Suerte del Lobby", Desc = "15 min de huevos del nido con el doble de suerte para TODO el lobby", Color = GREEN, Tag = "PARA TODOS" },
			{ Key = "Fireworks", Kind = "Product", Icon = "🎆", Name = "Fuegos artificiales", Desc = "Espectáculo en la plaza con tu nombre y tu criatura en grande", Color = PINK },
			{ Key = "SeasonEgg", Kind = "Product", Icon = "🥚", Name = "Huevo de Temporada", Desc = "Un huevo de Raro a Legendario para tu incubadora", Color = BLUE, Random = true },
			{ Key = "BreedReroll", Kind = "Product", Icon = "🔁", Name = "Repetir cría", Desc = "Otra cría con los mismos padres que la última", Color = PURPLE, Random = true },
		},
	},
	{
		Id = "Club",
		Name = "Club",
		Icon = "💛",
		Offers = {
			{ Key = "Club", Kind = "Club", Icon = "💛", Name = "Club del Nido", Desc = "+20 % de Monedas del nido mientras seas socio. Se paga cada mes y se cancela cuando quieras", Color = GOLD },
		},
	},
} :: { Section }

-- Lo que aparece en el banner de arriba, por orden de preferencia (el primero que se pueda comprar).
Store.FeaturedOrder = { "Starter", "ServerLuck", "DoubleCoins", "CoinsLarge" }

Store.StarterOffer = {
	Key = "StarterPack",
	Kind = "Starter",
	Icon = "🎁",
	Name = "Pack de inicio",
	Desc = "",
	Color = PINK,
	Tag = "SOLO UNA VEZ",
} :: Offer

-- Busca una oferta por su clave.
function Store.find(key: string): Offer?
	if key == "StarterPack" or key == "Starter" then
		return Store.StarterOffer
	end
	for _, section in Store.Sections do
		for _, offer in section.Offers do
			if offer.Key == key then
				return offer
			end
		end
	end
	return nil
end

-- El número de Roblox de una oferta (0 o "" = aún no está creada en el Creator Hub).
function Store.productId(offer: Offer): number | string
	if offer.Kind == "Pass" then
		return Config.GamePasses[offer.Key] or 0
	elseif offer.Kind == "Club" then
		return Config.ClubSubscriptionId
	end
	return (Config.DevProducts :: any)[offer.Key] or 0
end

function Store.isConfigured(offer: Offer): boolean
	local id = Store.productId(offer)
	return id ~= 0 and id ~= ""
end

-- Qué trae el pack de inicio (el huevo se cambia por Monedas donde no se permite lo aleatorio).
function Store.starterContents(randomRestricted: boolean): { string }
	local s = Config.Store.Starter
	local list = {}
	if randomRestricted then
		table.insert(list, string.format("🪙 %s Monedas", Store.formatThousands(s.Coins + s.EggCoins)))
	else
		table.insert(list, string.format("🪙 %s Monedas", Store.formatThousands(s.Coins)))
		table.insert(list, "🥚 1 Huevo de Temporada")
	end
	table.insert(list, "🐣 Gorro de novato (exclusivo)")
	return list
end

-- Hasta cuándo (os.time) se ofrece el pack de inicio; nil si ya no se ofrece.
function Store.starterEndsAt(state: { FirstJoin: number, StarterBought: boolean }, now: number): number?
	if state.StarterBought then
		return nil
	end
	local ends = state.FirstJoin + Config.Store.Starter.OfferDays * 86400
	return if now < ends then ends else nil
end

-- "+X % extra" de un pack frente al pack pequeño, con los precios reales (nil si no hay o no gana).
function Store.coinBonus(amount: number, price: number, baseAmount: number, basePrice: number): number?
	if price <= 0 or basePrice <= 0 or baseAmount <= 0 then
		return nil
	end
	local bonus = math.floor(((amount / price) / (baseAmount / basePrice) - 1) * 100 + 1e-9)
	return if bonus >= 1 then bonus else nil
end

-- ------------------------------------------------------------------ avisos
-- Situación del jugador que mira el aviso (la arma el cliente con la vista del perfil).
export type NudgeContext = {
	Now: number,
	Passes: { [string]: boolean }, -- pases que ya tiene
	Slots: number,
	TotalCreatures: number,
	LongestWait: number, -- segundos que le faltan al huevo que más tarda de la incubadora
	Coins: number,
	CheapestUpgrade: number?, -- lo que cuesta la mejora más barata que aún puede subir
	StarterEndsAt: number?,
	Shown: { [string]: boolean }, -- avisos ya enseñados en esta sesión
	LastShownAt: number, -- cuándo se enseñó el último (0 = nunca)
	SessionSeconds: number, -- tiempo en el lobby en esta sesión
}
export type Nudge = { Id: string, Icon: string, Text: string, Offer: string }

local function shownCount(shown: { [string]: boolean }): number
	local n = 0
	for _ in shown do
		n += 1
	end
	return n
end

-- El aviso que toca ahora, o nil. Como mucho uno cada NudgeGap s y MaxNudges por sesión, cada
-- uno una sola vez, y solo si lo que sugiere se puede comprar.
function Store.pickNudge(ctx: NudgeContext): Nudge?
	if shownCount(ctx.Shown) >= Config.Store.MaxNudges then
		return nil
	end
	if ctx.LastShownAt > 0 and ctx.Now - ctx.LastShownAt < Config.Store.NudgeGap then
		return nil
	end
	local function ready(id: string, key: string): boolean
		local offer = Store.find(key)
		return not ctx.Shown[id] and offer ~= nil and Store.isConfigured(offer) and not ctx.Passes[key]
	end
	-- El de bienvenida, al minuto de estar en el lobby.
	if ctx.StarterEndsAt and ctx.SessionSeconds >= 60 and ready("starter", "StarterPack") then
		return { Id = "starter", Icon = "🎁", Text = "Pack de inicio: un buen empujón para empezar y un gorro exclusivo. Solo una vez", Offer = "StarterPack" }
	end
	if ctx.LongestWait >= 120 and ready("incubator", "FastIncubator") then
		return { Id = "incubator", Icon = "⏩", Text = "¿Se hace larga la espera? Con la Incubadora Rápida los huevos tardan la mitad", Offer = "FastIncubator" }
	end
	if ctx.TotalCreatures > ctx.Slots and ready("nestfull", "VipNest") then
		return { Id = "nestfull", Icon = "👑", Text = "Tienes criaturas guardadas que no producen. El Nido VIP da +10 ranuras", Offer = "VipNest" }
	end
	local cheapest = ctx.CheapestUpgrade
	if cheapest and ctx.Coins < cheapest and ready("coins", "CoinsMedium") then
		return {
			Id = "coins",
			Icon = "🪙",
			Text = string.format("Te faltan %s Monedas para tu próxima mejora", Store.formatThousands(cheapest - ctx.Coins)),
			Offer = "CoinsMedium",
		}
	end
	return nil
end

return Store
