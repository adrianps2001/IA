--!strict
-- Estilo "Classic": las criaturas de la v1 (cuerpo, cabeza, ojos, cresta y manchas).
-- Se mantiene por si se quiere volver a él (Config.Creatures.Style = "Classic").

local Genes = require(script.Parent.Parent.Genes)
local Rarity = require(script.Parent.Parent.Rarity)
local Parts = require(script.Parent.Parts)

local Classic = {}

local part = Parts.part
local rgb = Parts.rgb

local BODY_SHAPES: { [string]: Vector3 } = {
	body_round = Vector3.new(3, 3, 3),
	body_chubby = Vector3.new(3.6, 3, 3.6),
	body_long = Vector3.new(2.4, 2.4, 4),
	body_tiny = Vector3.new(2.2, 2.2, 2.2),
	body_fluffy = Vector3.new(3.4, 3.2, 3.4),
	body_crystal = Vector3.new(2.8, 3.4, 2.8),
	body_lava = Vector3.new(3.2, 3, 3.2),
	body_jelly = Vector3.new(3.4, 2.6, 3.4),
	body_stone = Vector3.new(3.4, 3.4, 3.4),
	body_cloud = Vector3.new(4, 2.6, 3.4),
	body_star = Vector3.new(3.2, 3.2, 3.2),
	body_void = Vector3.new(3.2, 3.2, 3.2),
	body_phoenix = Vector3.new(3.2, 3.2, 3.2),
}

local BODY_MATERIALS: { [string]: Enum.Material } = {
	body_crystal = Enum.Material.Glass,
	body_lava = Enum.Material.Neon,
	body_jelly = Enum.Material.Glass,
	body_stone = Enum.Material.Slate,
	body_star = Enum.Material.Neon,
	body_void = Enum.Material.Neon,
	body_phoenix = Enum.Material.Neon,
}

-- Construye las piezas dentro de model y devuelve el cuerpo (la PrimaryPart).
function Classic.build(model: Model, genes: Genes.GeneSet, s: number, bodyColor: Color3): BasePart
	local head = Genes.get(genes.Head)
	local pattern = Genes.get(genes.Pattern)

	-- Una pieza Ball siempre es una esfera perfecta; para las formas alargadas se usa un
	-- bloque con malla esférica, que se estira con el tamaño (igual que el huevo gigante).
	local bodyPart = part("Body", Enum.PartType.Block, (BODY_SHAPES[genes.Body] or Vector3.new(3, 3, 3)) * s, bodyColor, model)
	local bodyMesh = Instance.new("SpecialMesh")
	bodyMesh.MeshType = Enum.MeshType.Sphere
	bodyMesh.Parent = bodyPart
	bodyPart.Material = BODY_MATERIALS[genes.Body] or Enum.Material.SmoothPlastic
	model.PrimaryPart = bodyPart

	local headSize = 2 * s
	local headPart = part("Head", Enum.PartType.Ball, Vector3.new(headSize, headSize, headSize), bodyColor, model)
	headPart.CFrame = bodyPart.CFrame * CFrame.new(0, bodyPart.Size.Y * 0.45, -bodyPart.Size.Z * 0.35)
	headPart.Material = bodyPart.Material

	-- Ojos
	for _, side in { -1, 1 } do
		local eye = part("Eye", Enum.PartType.Ball, Vector3.new(0.45, 0.45, 0.45) * s, Color3.new(0.05, 0.05, 0.05), model)
		eye.CFrame = headPart.CFrame * CFrame.new(side * 0.45 * s, 0.2 * s, -headSize * 0.45)
		if genes.Head == "head_cyclops" and side == 1 then
			eye:Destroy()
		end
	end

	-- Rasgo de la cabeza: una pieza con el color del gen.
	if head then
		local crest = part("Crest", Enum.PartType.Block, Vector3.new(0.6, 0.6, 0.9) * s, rgb(head.Color), model)
		if genes.Head == "head_beak" then
			crest.CFrame = headPart.CFrame * CFrame.new(0, -0.1 * s, -headSize * 0.6)
		elseif genes.Head == "head_unicorn" then
			crest.Size = Vector3.new(0.35, 1.6, 0.35) * s
			crest.CFrame = headPart.CFrame * CFrame.new(0, headSize * 0.65, -headSize * 0.2) * CFrame.Angles(math.rad(-25), 0, 0)
		elseif genes.Head == "head_halo" then
			crest.Shape = Enum.PartType.Cylinder
			crest.Size = Vector3.new(0.15, 2.2, 2.2) * s
			crest.Material = Enum.Material.Neon
			crest.CFrame = headPart.CFrame * CFrame.new(0, headSize * 0.8, 0) * CFrame.Angles(0, 0, math.rad(90))
		else
			crest.Size = Vector3.new(0.5, 1.1, 0.5) * s
			crest.CFrame = headPart.CFrame * CFrame.new(0, headSize * 0.6, 0)
		end
		if Rarity.tier(head.Rarity) >= 4 then
			crest.Material = Enum.Material.Neon
		end
	end

	-- Patrón: manchas del color del gen sobre el cuerpo.
	if pattern and pattern.Id ~= "pattern_plain" then
		local spots = 3 + Rarity.tier(pattern.Rarity)
		for i = 1, spots do
			local angle = (i / spots) * math.pi * 2
			local spot = part("Pattern", Enum.PartType.Ball, Vector3.new(0.9, 0.9, 0.9) * s, rgb(pattern.Color), model)
			spot.CFrame = bodyPart.CFrame
				* CFrame.Angles(0, angle, 0)
				* CFrame.new(0, (i % 2 - 0.5) * 0.6 * s, bodyPart.Size.X * 0.42)
			if Rarity.tier(pattern.Rarity) >= 4 then
				spot.Material = Enum.Material.Neon
			end
		end
	end

	return bodyPart
end

return Classic
