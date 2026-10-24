--!strict
-- Tienda de la Plaza (v3.1, GDD 9.3): cosas solo estéticas que se compran con polvo de cáscara
-- (más adelante, también con Robux). Dos tipos:
-- * Hat: algo que lleva puesto tu criatura al hombro (gorro, corona, gafas…).
-- * Theme: colores y materiales de tu nido del lobby (suelo, borde, valla, arco y cartel).
-- Cada día (UTC) la tienda enseña ShopSize artículos distintos; lo comprado es tuyo para siempre.
-- Este módulo es solo datos (se prueba sin Roblox); CosmeticsModel construye los sombreros y
-- pinta los nidos.

local Cosmetics = {}

export type Kind = "Hat" | "Theme"
-- Exclusive: no sale en la rotación de la Plaza (se consigue de otra forma, como el pack de
-- inicio). Price es lo que vale en polvo (lo que se devuelve si te llega repetido).
export type Item = { Id: string, Kind: Kind, Name: string, Price: number, Icon: string, Exclusive: boolean? }

Cosmetics.ShopSize = 6

Cosmetics.Catalog = {
	{ Id = "hat_party", Kind = "Hat", Name = "Gorro de fiesta", Price = 300, Icon = "🎉" },
	{ Id = "hat_beanie", Kind = "Hat", Name = "Gorro de lana", Price = 300, Icon = "🧶" },
	{ Id = "hat_bow", Kind = "Hat", Name = "Lazo", Price = 350, Icon = "🎀" },
	{ Id = "hat_flowers", Kind = "Hat", Name = "Corona de flores", Price = 500, Icon = "🌸" },
	{ Id = "hat_glasses", Kind = "Hat", Name = "Gafas de sol", Price = 600, Icon = "🕶️" },
	{ Id = "hat_top", Kind = "Hat", Name = "Chistera", Price = 900, Icon = "🎩" },
	{ Id = "hat_pirate", Kind = "Hat", Name = "Sombrero pirata", Price = 1200, Icon = "🏴‍☠️" },
	{ Id = "hat_crown", Kind = "Hat", Name = "Coronita", Price = 1500, Icon = "👑" },
	{ Id = "hat_rookie", Kind = "Hat", Name = "Gorro de novato", Price = 500, Icon = "🐣", Exclusive = true },
	{ Id = "theme_snow", Kind = "Theme", Name = "Nido de invierno", Price = 2500, Icon = "❄️" },
	{ Id = "theme_beach", Kind = "Theme", Name = "Nido de playa", Price = 2500, Icon = "🏖️" },
	{ Id = "theme_candy", Kind = "Theme", Name = "Nido de caramelo", Price = 3500, Icon = "🍬" },
	{ Id = "theme_volcano", Kind = "Theme", Name = "Nido volcánico", Price = 5000, Icon = "🌋" },
	{ Id = "theme_space", Kind = "Theme", Name = "Nido espacial", Price = 6000, Icon = "🌌" },
} :: { Item }

local byId: { [string]: Item } = {}
for _, item in Cosmetics.Catalog do
	byId[item.Id] = item
end

function Cosmetics.get(id: any): Item?
	return if type(id) == "string" then byId[id] else nil
end

-- Los artículos de hoy: una selección que cambia cada día pero es la misma para todo el mundo.
function Cosmetics.shopToday(day: number): { Item }
	local list: { Item } = {}
	for _, item in Cosmetics.Catalog do
		if not item.Exclusive then
			table.insert(list, item)
		end
	end
	-- Barajado con una semilla del día (generador lineal sencillo, sin Random de Roblox). Se usan
	-- los bits altos: los bajos de este generador se repiten y dejaban artículos sin salir nunca.
	local seed = (day * 2654435761 + 97) % 4294967296
	for i = #list, 2, -1 do
		seed = (seed * 1664525 + 1013904223) % 4294967296
		local j = math.floor(seed / 4294967296 * i) + 1
		list[i], list[j] = list[j], list[i]
	end
	-- Siempre al menos un tema y un sombrero.
	local out: { Item }, hats, themes = {}, 0, 0
	for _, item in list do
		if #out >= Cosmetics.ShopSize then
			break
		end
		local needTheme = item.Kind == "Hat" and themes == 0 and hats >= Cosmetics.ShopSize - 1
		if not needTheme then
			table.insert(out, item)
			if item.Kind == "Hat" then
				hats += 1
			else
				themes += 1
			end
		end
	end
	return out
end

return Cosmetics
