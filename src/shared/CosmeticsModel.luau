--!strict
-- Piezas de la Tienda de la Plaza (v3.1): los sombreros de la criatura al hombro y los colores
-- de los temas de nido. Los usan el servidor (temas), el cliente (sombreros) y la galería de
-- criaturas, para que se vean igual en todas partes. El catálogo está en Cosmetics.

local Cosmetics = require("./Cosmetics")
local Parts = require("./CreatureStyles/Parts")

local CosmeticsModel = {}

export type Paint = { Color: Color3, Material: Enum.Material }

-- ------------------------------------------------------------------ temas de nido
-- Se crean al usarlos por primera vez (así este módulo se puede cargar en las pruebas, sin Roblox).
local THEMES: { [string]: { [string]: Paint } }? = nil
local function themes(): { [string]: { [string]: Paint } }
	if THEMES then
		return THEMES
	end
	local t: { [string]: { [string]: Paint } } = {
	theme_default = {
		Floor = { Color = Color3.fromRGB(110, 165, 80), Material = Enum.Material.Grass },
		Border = { Color = Color3.fromRGB(150, 120, 90), Material = Enum.Material.Cobblestone },
		Wood = { Color = Color3.fromRGB(160, 110, 70), Material = Enum.Material.Wood },
		Sign = { Color = Color3.fromRGB(110, 75, 45), Material = Enum.Material.Wood },
	},
	theme_snow = {
		Floor = { Color = Color3.fromRGB(240, 246, 255), Material = Enum.Material.Snow },
		Border = { Color = Color3.fromRGB(170, 200, 230), Material = Enum.Material.Ice },
		Wood = { Color = Color3.fromRGB(200, 225, 245), Material = Enum.Material.SmoothPlastic },
		Sign = { Color = Color3.fromRGB(90, 130, 180), Material = Enum.Material.SmoothPlastic },
	},
	theme_beach = {
		Floor = { Color = Color3.fromRGB(235, 215, 160), Material = Enum.Material.Sand },
		Border = { Color = Color3.fromRGB(90, 170, 210), Material = Enum.Material.SmoothPlastic },
		Wood = { Color = Color3.fromRGB(245, 240, 225), Material = Enum.Material.WoodPlanks },
		Sign = { Color = Color3.fromRGB(240, 120, 80), Material = Enum.Material.WoodPlanks },
	},
	theme_candy = {
		Floor = { Color = Color3.fromRGB(255, 190, 215), Material = Enum.Material.SmoothPlastic },
		Border = { Color = Color3.fromRGB(170, 235, 210), Material = Enum.Material.SmoothPlastic },
		Wood = { Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.SmoothPlastic },
		Sign = { Color = Color3.fromRGB(230, 90, 140), Material = Enum.Material.SmoothPlastic },
	},
	theme_volcano = {
		Floor = { Color = Color3.fromRGB(55, 45, 45), Material = Enum.Material.Basalt },
		Border = { Color = Color3.fromRGB(255, 110, 40), Material = Enum.Material.Neon },
		Wood = { Color = Color3.fromRGB(70, 55, 55), Material = Enum.Material.Slate },
		Sign = { Color = Color3.fromRGB(40, 30, 30), Material = Enum.Material.Basalt },
	},
	theme_space = {
		Floor = { Color = Color3.fromRGB(30, 30, 70), Material = Enum.Material.SmoothPlastic },
		Border = { Color = Color3.fromRGB(150, 90, 255), Material = Enum.Material.Neon },
		Wood = { Color = Color3.fromRGB(200, 210, 230), Material = Enum.Material.Metal },
		Sign = { Color = Color3.fromRGB(40, 40, 90), Material = Enum.Material.Metal },
	},
	}
	THEMES = t
	return t
end

-- Qué pieza del nido pinta cada parte del tema.
local NEST_PARTS: { [string]: string } = {
	Floor = "Floor",
	Border = "Border",
	FenceRail = "Wood",
	FencePost = "Wood",
	ArchPost = "Wood",
	SignBoard = "Sign",
}

function CosmeticsModel.themePaint(themeId: string?): { [string]: Paint }
	local all = themes()
	return all[themeId or "theme_default"] or all.theme_default
end

-- Pinta el modelo de un nido del lobby con un tema (nil = el de siempre).
function CosmeticsModel.paintNest(model: Instance, themeId: string?)
	local paint = CosmeticsModel.themePaint(themeId)
	for _, part in model:GetDescendants() do
		local slot = NEST_PARTS[part.Name]
		if slot and part:IsA("BasePart") then
			part.Color = paint[slot].Color
			part.Material = paint[slot].Material
		end
	end
end

-- ------------------------------------------------------------------ sombreros
-- Dónde va el sombrero: en lo alto del cuerpo de la criatura (su PrimaryPart).
function CosmeticsModel.hatSeat(body: BasePart): CFrame
	return body.CFrame * CFrame.new(0, body.Size.Y * 0.46, 0)
end

-- Construye el sombrero `id` encima de una criatura: top es el punto más alto de su cabeza
-- (mirando hacia -Z) y w, su anchura. Devuelve la carpeta con las piezas.
function CosmeticsModel.buildHat(id: string, top: CFrame, w: number, parent: Instance): Model?
	if not Cosmetics.get(id) then
		return nil
	end
	local hat = Instance.new("Model")
	hat.Name = "Hat"
	local part, blob = Parts.part, Parts.blob
	if id == "hat_party" then
		for k = 0, 3 do
			local ring = part("PartyHat", Enum.PartType.Cylinder, Vector3.new(0.18 * w, (0.42 - k * 0.1) * w, (0.42 - k * 0.1) * w), if k % 2 == 0 then Color3.fromRGB(255, 90, 140) else Color3.fromRGB(90, 200, 255), hat)
			ring.CFrame = top * CFrame.new(0, 0.09 * w + k * 0.17 * w, 0) * CFrame.Angles(0, 0, math.rad(90))
		end
		local pom = part("Pompom", Enum.PartType.Ball, Vector3.one * 0.12 * w, Color3.fromRGB(255, 230, 90), hat)
		pom.CFrame = top * CFrame.new(0, 0.75 * w, 0)
	elseif id == "hat_beanie" then
		local cap = blob("Beanie", Vector3.new(0.62, 0.38, 0.62) * w, Color3.fromRGB(80, 140, 220), hat)
		cap.CFrame = top * CFrame.new(0, 0.08 * w, 0)
		local brim = part("BeanieBrim", Enum.PartType.Cylinder, Vector3.new(0.1 * w, 0.64 * w, 0.64 * w), Color3.fromRGB(240, 240, 250), hat)
		brim.CFrame = top * CFrame.new(0, -0.04 * w, 0) * CFrame.Angles(0, 0, math.rad(90))
		local pom = part("Pompom", Enum.PartType.Ball, Vector3.one * 0.16 * w, Color3.fromRGB(240, 240, 250), hat)
		pom.CFrame = top * CFrame.new(0, 0.3 * w, 0)
	elseif id == "hat_bow" then
		for _, side in { -1, 1 } do
			local loop = blob("Bow", Vector3.new(0.22, 0.16, 0.08) * w, Color3.fromRGB(255, 80, 120), hat)
			loop.CFrame = top * CFrame.new(side * 0.13 * w, 0.02 * w, -0.05 * w) * CFrame.Angles(0, 0, math.rad(side * 15))
		end
		local knot = blob("BowKnot", Vector3.one * 0.08 * w, Color3.fromRGB(220, 50, 90), hat)
		knot.CFrame = top * CFrame.new(0, 0.02 * w, -0.06 * w)
	elseif id == "hat_flowers" then
		local colors = { Color3.fromRGB(255, 140, 190), Color3.fromRGB(255, 230, 100), Color3.fromRGB(190, 150, 255), Color3.fromRGB(255, 255, 255) }
		for k = 0, 7 do
			local a = k * math.pi * 2 / 8
			local f = part("Flower", Enum.PartType.Ball, Vector3.one * 0.17 * w, colors[k % #colors + 1], hat)
			f.CFrame = top * CFrame.new(math.cos(a) * 0.2 * w, 0.05 * w, math.sin(a) * 0.2 * w)
		end
	elseif id == "hat_glasses" then
		-- A la altura de los ojos de las criaturas chibi (algo por encima del centro de la cara).
		for _, side in { -1, 1 } do
			local lens = blob("Lens", Vector3.new(0.27, 0.21, 0.05) * w, Color3.fromRGB(25, 25, 35), hat)
			lens.CFrame = top * CFrame.new(side * 0.24 * w, -0.38 * w, -0.43 * w) * CFrame.Angles(0, math.rad(side * -18), 0)
			lens.Reflectance = 0.4
		end
		local bridge = part("Bridge", Enum.PartType.Block, Vector3.new(0.22, 0.04, 0.04) * w, Color3.fromRGB(25, 25, 35), hat)
		bridge.CFrame = top * CFrame.new(0, -0.34 * w, -0.47 * w)
	elseif id == "hat_top" then
		local brim = part("Brim", Enum.PartType.Cylinder, Vector3.new(0.04 * w, 0.62 * w, 0.62 * w), Color3.fromRGB(30, 30, 35), hat)
		brim.CFrame = top * CFrame.new(0, 0.02 * w, 0) * CFrame.Angles(0, 0, math.rad(90))
		local crown = part("TopHat", Enum.PartType.Cylinder, Vector3.new(0.42 * w, 0.4 * w, 0.4 * w), Color3.fromRGB(30, 30, 35), hat)
		crown.CFrame = top * CFrame.new(0, 0.23 * w, 0) * CFrame.Angles(0, 0, math.rad(90))
		local band = part("Band", Enum.PartType.Cylinder, Vector3.new(0.08 * w, 0.41 * w, 0.41 * w), Color3.fromRGB(200, 40, 60), hat)
		band.CFrame = top * CFrame.new(0, 0.08 * w, 0) * CFrame.Angles(0, 0, math.rad(90))
	elseif id == "hat_pirate" then
		local base = blob("PirateHat", Vector3.new(0.78, 0.22, 0.42) * w, Color3.fromRGB(35, 30, 35), hat)
		base.CFrame = top * CFrame.new(0, 0.08 * w, 0)
		local front = blob("PirateFront", Vector3.new(0.5, 0.3, 0.12) * w, Color3.fromRGB(35, 30, 35), hat)
		front.CFrame = top * CFrame.new(0, 0.2 * w, -0.12 * w)
		local skull = part("Skull", Enum.PartType.Ball, Vector3.one * 0.1 * w, Color3.fromRGB(245, 245, 235), hat)
		skull.CFrame = top * CFrame.new(0, 0.22 * w, -0.19 * w)
	elseif id == "hat_rookie" then
		-- Media cáscara de huevo con el borde en zigzag (pack de inicio).
		local shell = blob("Eggshell", Vector3.new(0.6, 0.34, 0.6) * w, Color3.fromRGB(250, 245, 230), hat)
		shell.CFrame = top * CFrame.new(0, 0.1 * w, 0)
		for k = 0, 7 do
			local a = k * math.pi * 2 / 8
			local tooth = part("ShellTooth", Enum.PartType.Block, Vector3.new(0.12, 0.12, 0.04) * w, Color3.fromRGB(250, 245, 230), hat)
			tooth.CFrame = top * CFrame.new(math.cos(a) * 0.27 * w, 0.02 * w, math.sin(a) * 0.27 * w) * CFrame.Angles(0, -a + math.pi / 2, math.rad(45))
		end
		for _, spot in { Vector3.new(-0.12, 0.2, -0.2), Vector3.new(0.14, 0.24, -0.12), Vector3.new(0.02, 0.27, 0.16) } do
			local dot = part("ShellSpot", Enum.PartType.Ball, Vector3.one * 0.08 * w, Color3.fromRGB(255, 190, 90), hat)
			dot.CFrame = top * CFrame.new((spot :: Vector3) * w)
		end
	elseif id == "hat_crown" then
		local band = part("Crown", Enum.PartType.Cylinder, Vector3.new(0.14 * w, 0.42 * w, 0.42 * w), Color3.fromRGB(255, 205, 60), hat)
		band.CFrame = top * CFrame.new(0, 0.07 * w, 0) * CFrame.Angles(0, 0, math.rad(90))
		band.Material = Enum.Material.Metal
		for k = 0, 4 do
			local a = k * math.pi * 2 / 5
			local spike = part("CrownSpike", Enum.PartType.Block, Vector3.new(0.07, 0.14, 0.07) * w, Color3.fromRGB(255, 205, 60), hat)
			spike.CFrame = top * CFrame.new(math.cos(a) * 0.18 * w, 0.2 * w, math.sin(a) * 0.18 * w) * CFrame.Angles(0, a, math.rad(45))
			spike.Material = Enum.Material.Metal
		end
		local gem = part("Gem", Enum.PartType.Ball, Vector3.one * 0.08 * w, Color3.fromRGB(255, 60, 110), hat)
		gem.CFrame = top * CFrame.new(0, 0.08 * w, -0.21 * w)
		gem.Material = Enum.Material.Neon
	end
	hat.Parent = parent
	return hat
end

return CosmeticsModel
