--!strict
-- Ensambla el modelo 3D de una criatura a partir de sus genes (GDD 8: criaturas modulares).
-- El aspecto está en CreatureStyles (GDD v3): se elige con Config.Creatures.Style
-- ("Chibi" por defecto, "Classic" las de la v1). Cambiar de estilo no toca nada más.
--
-- Modelos de un artista: si existe ReplicatedStorage.CreatureArt con un Model llamado como el
-- gen de cuerpo (body_round, body_lava...) o "Default", se usa una copia de ese modelo:
-- * debe tener PrimaryPart (el cuerpo) y mirar hacia -Z;
-- * las piezas llamadas "Body" se tiñen con el color del cuerpo, "Accent" con el de la
--   cabeza y "Pattern" con el del patrón.
-- Lo común (aura, luz, mutaciones, etiqueta) se añade igual a cualquier estilo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)
local Creature = require(script.Parent.Creature)
local Genes = require(script.Parent.Genes)
local Rarity = require(script.Parent.Rarity)
local Parts = require(script.Parent.CreatureStyles.Parts)

type Style = { build: (Model, Genes.GeneSet, number, Color3) -> BasePart }

local STYLES: { [string]: Style } = {
	Chibi = require(script.Parent.CreatureStyles.Chibi) :: Style,
	Classic = require(script.Parent.CreatureStyles.Classic) :: Style,
}

export type Options = {
	Label: boolean?, -- etiqueta flotante con nombre y rareza (por defecto, sí)
}

local CreatureModel = {}

local function fromArt(model: Model, genes: Genes.GeneSet, s: number, bodyColor: Color3): BasePart?
	local folder = ReplicatedStorage:FindFirstChild("CreatureArt")
	local template = folder and (folder:FindFirstChild(genes.Body) or folder:FindFirstChild("Default"))
	if not template or not template:IsA("Model") or not template.PrimaryPart then
		return nil
	end
	local copy = template:Clone()
	copy:ScaleTo(copy:GetScale() * s)
	local head = Genes.get(genes.Head)
	local pattern = Genes.get(genes.Pattern)
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			if descendant.Name == "Body" then
				descendant.Color = bodyColor
			elseif descendant.Name == "Accent" and head then
				descendant.Color = Parts.rgb(head.Color)
			elseif descendant.Name == "Pattern" and pattern then
				descendant.Color = Parts.rgb(pattern.Color)
			end
		end
	end
	local body = copy.PrimaryPart :: BasePart
	for _, child in copy:GetChildren() do
		child.Parent = model
	end
	copy:Destroy()
	model.PrimaryPart = body
	return body
end

-- Devuelve un modelo anclado con PrimaryPart "Body". scale permite miniaturas.
function CreatureModel.build(creature: Creature.Creature, scale: number?, options: Options?): Model
	local s = scale or 1
	local genes = creature.Genes
	local bodyGene = Genes.get(genes.Body)
	local aura = Genes.get(genes.Aura)
	local mutation = genes.Mutation

	local sizeMultiplier = if mutation == "mut_big" then 1.6 elseif mutation == "mut_small" then 0.6 else 1
	s *= sizeMultiplier

	local model = Instance.new("Model")
	model.Name = Creature.name(creature)

	local bodyColor = if bodyGene then Parts.rgb(bodyGene.Color) else Color3.new(1, 1, 1)
	if mutation == "mut_golden" then
		bodyColor = Color3.fromRGB(255, 200, 40)
	elseif mutation == "mut_inverted" then
		bodyColor = Color3.new(1 - bodyColor.R, 1 - bodyColor.G, 1 - bodyColor.B)
	end

	local bodyPart = fromArt(model, genes, s, bodyColor)
	if not bodyPart then
		local style = STYLES[Config.Creatures.Style] or STYLES.Chibi
		bodyPart = style.build(model, genes, s, bodyColor)
	end
	local body = bodyPart :: BasePart
	model.PrimaryPart = body

	-- Aura: partículas del color del gen.
	if aura and aura.Id ~= "aura_none" then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(Parts.rgb(aura.Color))
		emitter.LightEmission = 0.8
		emitter.Rate = 6 + 6 * Rarity.tier(aura.Rarity)
		emitter.Lifetime = NumberRange.new(0.8, 1.4)
		emitter.Speed = NumberRange.new(1, 3)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Size = NumberSequence.new(0.3 * s, 0)
		emitter.Parent = body
	end

	-- Agujero Negro (aura Secreta, v3.1): un anillo oscuro con borde violeta alrededor.
	if aura and aura.Id == "aura_blackhole" then
		Parts.blackHole(model, body)
	end

	-- Mutaciones visibles.
	if mutation == "mut_ghost" then
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") and p.Transparency < 1 then
				p.Transparency = math.max(p.Transparency, 0.45)
			end
		end
	elseif mutation == "mut_shiny" or mutation == "mut_golden" then
		body.Reflectance = 0.35
	elseif mutation == "mut_glow" or mutation == "mut_cosmic" or mutation == "mut_rainbow" then
		body.Material = Enum.Material.Neon
	end
	if mutation == "mut_rainbow" then
		model:SetAttribute("Rainbow", true) -- el cliente anima el color
	end

	local rarityInfo = Rarity.Info[creature.Rarity]
	if rarityInfo.Tier >= 3 then
		local light = Instance.new("PointLight")
		light.Color = Parts.rgb(rarityInfo.Color)
		light.Range = 6 + rarityInfo.Tier * 2
		light.Brightness = 1.5
		light.Parent = body
	end

	-- Etiqueta con nombre y rareza.
	if not options or options.Label ~= false then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Label"
		billboard.Size = UDim2.fromOffset(160, 40)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, body.Size.Y + 1.5, 0)
		billboard.MaxDistance = 80
		billboard.AlwaysOnTop = false
		billboard.Parent = body
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Parts.rgb(rarityInfo.Color)
		label.TextStrokeTransparency = 0.3
		label.Text = string.format("%s\n%s", model.Name, rarityInfo.DisplayName)
		label.Parent = billboard
	end

	model:SetAttribute("CreatureId", creature.Id)
	model:SetAttribute("Rarity", creature.Rarity)
	return model
end

-- Altura del pivote sobre la base del modelo: con model:PivotTo(suelo * CFrame.new(0, esto, 0))
-- la criatura queda de pie sobre el suelo.
function CreatureModel.footOffset(model: Model): number
	local cf, size = model:GetBoundingBox()
	return model:GetPivot().Position.Y - (cf.Position.Y - size.Y / 2)
end

-- Mueve el modelo entero (todas las piezas están ancladas).
function CreatureModel.place(model: Model, cframe: CFrame)
	model:PivotTo(cframe)
end

return CreatureModel
