--!strict
-- Ensambla el modelo 3D de una criatura a partir de sus genes (GDD 8: criaturas modulares).
-- Solo piezas primitivas: barato en móvil y miles de combinaciones con poco arte.

local Creature = require(script.Parent.Creature)
local Genes = require(script.Parent.Genes)
local Rarity = require(script.Parent.Rarity)

local CreatureModel = {}

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local function part(name: string, shape: Enum.PartType, size: Vector3, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = true
	p.Parent = parent
	return p
end

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
}

local BODY_MATERIALS: { [string]: Enum.Material } = {
	body_crystal = Enum.Material.Glass,
	body_lava = Enum.Material.Neon,
	body_jelly = Enum.Material.Glass,
	body_stone = Enum.Material.Slate,
	body_star = Enum.Material.Neon,
	body_void = Enum.Material.Neon,
}

-- Devuelve un modelo anclado con PrimaryPart "Body". scale permite miniaturas.
function CreatureModel.build(creature: Creature.Creature, scale: number?): Model
	local s = scale or 1
	local genes = creature.Genes
	local body = Genes.get(genes.Body)
	local head = Genes.get(genes.Head)
	local pattern = Genes.get(genes.Pattern)
	local aura = Genes.get(genes.Aura)
	local mutation = genes.Mutation

	local sizeMultiplier = if mutation == "mut_big" then 1.6 elseif mutation == "mut_small" then 0.6 else 1
	s *= sizeMultiplier

	local model = Instance.new("Model")
	model.Name = Creature.name(creature)

	local bodyColor = if body then rgb(body.Color) else Color3.new(1, 1, 1)
	if mutation == "mut_golden" then
		bodyColor = Color3.fromRGB(255, 200, 40)
	elseif mutation == "mut_inverted" then
		bodyColor = Color3.new(1 - bodyColor.R, 1 - bodyColor.G, 1 - bodyColor.B)
	end

	local bodyPart = part("Body", Enum.PartType.Ball, (BODY_SHAPES[genes.Body] or Vector3.new(3, 3, 3)) * s, bodyColor, model)
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

	-- Aura: partículas del color del gen.
	if aura and aura.Id ~= "aura_none" then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(rgb(aura.Color))
		emitter.LightEmission = 0.8
		emitter.Rate = 6 + 6 * Rarity.tier(aura.Rarity)
		emitter.Lifetime = NumberRange.new(0.8, 1.4)
		emitter.Speed = NumberRange.new(1, 3)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Size = NumberSequence.new(0.3 * s, 0)
		emitter.Parent = bodyPart
	end

	-- Mutaciones visibles.
	if mutation == "mut_ghost" then
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				p.Transparency = 0.45
			end
		end
	elseif mutation == "mut_shiny" or mutation == "mut_golden" then
		bodyPart.Reflectance = 0.35
	elseif mutation == "mut_glow" or mutation == "mut_cosmic" or mutation == "mut_rainbow" then
		bodyPart.Material = Enum.Material.Neon
	end
	if mutation == "mut_rainbow" then
		model:SetAttribute("Rainbow", true) -- el cliente anima el color
	end

	local rarityInfo = Rarity.Info[creature.Rarity]
	if rarityInfo.Tier >= 3 then
		local light = Instance.new("PointLight")
		light.Color = rgb(rarityInfo.Color)
		light.Range = 6 + rarityInfo.Tier * 2
		light.Brightness = 1.5
		light.Parent = bodyPart
	end

	-- Etiqueta con nombre y rareza.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(160, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, bodyPart.Size.Y + 1.5, 0)
	billboard.MaxDistance = 80
	billboard.AlwaysOnTop = false
	billboard.Parent = bodyPart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = rgb(rarityInfo.Color)
	label.TextStrokeTransparency = 0.3
	label.Text = string.format("%s\n%s", model.Name, rarityInfo.DisplayName)
	label.Parent = billboard

	model:SetAttribute("CreatureId", creature.Id)
	model:SetAttribute("Rarity", creature.Rarity)
	return model
end

-- Mueve el modelo entero (todas las piezas están ancladas).
function CreatureModel.place(model: Model, cframe: CFrame)
	model:PivotTo(cframe)
end

return CreatureModel
