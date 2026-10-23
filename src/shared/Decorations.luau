--!strict
-- Aspecto de las decoraciones del nido (precios y Belleza en Config.Decorations). Solo datos:
-- DecorationModel construye las piezas en Roblox.
-- Las piezas no colisionan ni se pueden pulsar: decorar nunca cambia la persecución.
-- Coordenadas locales del nido: -Z es la entrada (mira al huevo), +Z la pared del fondo,
-- el suelo está en Y = 1 y la parcela mide 26 × 26.

export type Piece = {
	Shape: "Block" | "Ball" | "Cylinder",
	Size: { number },
	Pos: { number },
	Color: { number },
	Material: string?,
	Transparency: number?,
	Light: number?, -- alcance de una PointLight
	Rot: { number }?, -- grados
}

local Decorations = {}

-- Añade la pieza y su reflejo en X (para colocar parejas a ambos lados del nido).
local function mirrored(list: { Piece }, piece: Piece): { Piece }
	table.insert(list, piece)
	local copy = table.clone(piece)
	copy.Pos = { -piece.Pos[1], piece.Pos[2], piece.Pos[3] }
	table.insert(list, copy)
	return list
end

local GOLD = { 255, 200, 80 }

Decorations.Pieces = {
	lanterns = mirrored({}, { Shape = "Ball", Size = { 1.4, 1.4, 1.4 }, Pos = { 8.5, 10.8, -13 }, Color = { 255, 210, 120 }, Material = "Neon", Light = 14 }),
	flowers = (function()
		local list = {}
		for _, z in { -9, 9 } do
			mirrored(list, { Shape = "Block", Size = { 1.6, 1.6, 1.6 }, Pos = { 11.4, 1.8, z }, Color = { 160, 95, 60 }, Material = "Slate" })
			mirrored(list, { Shape = "Ball", Size = { 2, 2, 2 }, Pos = { 11.4, 3.2, z }, Color = { 255, 120, 170 }, Material = "Grass" })
		end
		return list
	end)(),
	rug = {
		{ Shape = "Block", Size = { 18, 0.1, 14 }, Pos = { 0, 1.05, 1.5 }, Color = { 170, 40, 60 }, Material = "Fabric" },
		{ Shape = "Block", Size = { 16, 0.1, 12 }, Pos = { 0, 1.09, 1.5 }, Color = GOLD, Material = "Fabric" },
		{ Shape = "Block", Size = { 15, 0.1, 11 }, Pos = { 0, 1.13, 1.5 }, Color = { 170, 40, 60 }, Material = "Fabric" },
	},
	fountain = {
		{ Shape = "Block", Size = { 5, 1.4, 5 }, Pos = { -9.5, 1.7, -9.5 }, Color = { 150, 150, 160 }, Material = "Cobblestone" },
		{ Shape = "Block", Size = { 4.2, 0.2, 4.2 }, Pos = { -9.5, 2.35, -9.5 }, Color = { 80, 170, 255 }, Material = "Glass", Transparency = 0.3 },
		{ Shape = "Block", Size = { 1, 3, 1 }, Pos = { -9.5, 3.5, -9.5 }, Color = { 150, 150, 160 }, Material = "Cobblestone" },
		{ Shape = "Ball", Size = { 1.6, 1.6, 1.6 }, Pos = { -9.5, 5.2, -9.5 }, Color = { 120, 200, 255 }, Material = "Glass", Transparency = 0.2 },
	},
	crystals = (function()
		local list = {}
		mirrored(list, { Shape = "Block", Size = { 1.4, 5, 1.4 }, Pos = { 11, 3.5, 11 }, Color = { 90, 230, 255 }, Material = "Neon", Rot = { 0, 45, 12 }, Light = 12 })
		mirrored(list, { Shape = "Block", Size = { 1, 3, 1 }, Pos = { 9.6, 2.5, 11.4 }, Color = { 170, 120, 255 }, Material = "Neon", Rot = { 0, 20, -15 } })
		return list
	end)(),
	banner = {
		{ Shape = "Block", Size = { 7, 0.4, 0.4 }, Pos = { 0, 9.4, 12.3 }, Color = GOLD, Material = "Metal" },
		{ Shape = "Block", Size = { 6, 5, 0.2 }, Pos = { 0, 6.8, 12.3 }, Color = { 110, 50, 170 }, Material = "Fabric" },
		{ Shape = "Ball", Size = { 2, 2.6, 0.3 }, Pos = { 0, 7, 12.15 }, Color = GOLD, Material = "Neon" },
	},
	statue = {
		{ Shape = "Block", Size = { 3.4, 2, 3.4 }, Pos = { 9.5, 2, -9.5 }, Color = { 235, 235, 235 }, Material = "Marble" },
		{ Shape = "Ball", Size = { 3, 3.8, 3 }, Pos = { 9.5, 4.9, -9.5 }, Color = GOLD, Material = "Metal" },
	},
	aurora = (function()
		local list = {}
		local colors = { { 80, 255, 170 }, { 90, 180, 255 }, { 200, 110, 255 } }
		for index, color in colors do
			table.insert(list, {
				Shape = "Block",
				Size = { 26, 0.3, 3 },
				Pos = { 0, 15 + index * 0.8, -6 + index * 4 },
				Color = color,
				Material = "Neon",
				Transparency = 0.55,
				Rot = { 8, 0, 0 },
			} :: Piece)
		end
		return list
	end)(),
	shells = (function()
		local list = {}
		for x = -10, 10, 4 do
			table.insert(list, { Shape = "Ball", Size = { 1.1, 1.3, 1.1 }, Pos = { x, 10.4, 13 }, Color = { 255, 240, 215 }, Material = "SmoothPlastic" } :: Piece)
		end
		return list
	end)(),
	dustlamp = {
		{ Shape = "Block", Size = { 0.5, 5, 0.5 }, Pos = { -6, 3.5, 11 }, Color = { 60, 50, 45 }, Material = "Metal" },
		{ Shape = "Ball", Size = { 1.8, 1.8, 1.8 }, Pos = { -6, 6.6, 11 }, Color = { 255, 150, 220 }, Material = "Neon", Light = 16 },
	},
	gemtree = {
		{ Shape = "Block", Size = { 1, 6, 1 }, Pos = { -11.3, 4, 1 }, Color = { 110, 75, 45 }, Material = "Wood" },
		{ Shape = "Ball", Size = { 1.6, 1.6, 1.6 }, Pos = { -11.3, 7.4, 1 }, Color = { 255, 80, 90 }, Material = "Neon" },
		{ Shape = "Ball", Size = { 1.2, 1.2, 1.2 }, Pos = { -11.3, 6.2, 2.2 }, Color = { 80, 255, 140 }, Material = "Neon" },
		{ Shape = "Ball", Size = { 1.2, 1.2, 1.2 }, Pos = { -11.3, 6.4, -0.2 }, Color = { 90, 160, 255 }, Material = "Neon", Light = 10 },
	},
	throne = {
		{ Shape = "Block", Size = { 3, 1.6, 3 }, Pos = { 11, 1.8, 1 }, Color = { 255, 245, 225 }, Material = "Marble" },
		{ Shape = "Block", Size = { 0.6, 4.5, 3 }, Pos = { 12.2, 4, 1 }, Color = { 255, 245, 225 }, Material = "Marble" },
		{ Shape = "Ball", Size = { 1, 1, 1 }, Pos = { 12.2, 6.7, 1 }, Color = GOLD, Material = "Neon" },
	},
} :: { [string]: { Piece } }

return Decorations
