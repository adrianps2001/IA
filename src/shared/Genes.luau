--!strict
-- Catálogo de genes (60 al lanzamiento: 5 ranuras x 12) y tiradas (GDD 5.7).
-- Una criatura se guarda como 5 identificadores de gen; su rareza es la del gen más raro.

local Rarity = require("./Rarity")

type RarityName = Rarity.RarityName

export type Slot = "Body" | "Head" | "Pattern" | "Aura" | "Mutation"

export type Gene = {
	Id: string,
	Slot: Slot,
	Name: string,
	Rarity: RarityName,
	Color: { number },
}

export type GeneSet = {
	Body: string,
	Head: string,
	Pattern: string,
	Aura: string,
	Mutation: string,
}

export type Biases = { [Slot]: string }

local Genes = {}

Genes.Slots = { "Body", "Head", "Pattern", "Aura", "Mutation" } :: { Slot }

Genes.SlotNames = {
	Body = "Cuerpo",
	Head = "Cabeza",
	Pattern = "Patrón",
	Aura = "Aura",
	Mutation = "Mutación",
} :: { [Slot]: string }

type Row = { Id: string, Name: string, Rarity: RarityName, Color: { number } }

local function row(id: string, name: string, rarity: RarityName, color: { number }): Row
	return { Id = id, Name = name, Rarity = rarity, Color = color }
end

local CATALOG: { [Slot]: { Row } } = {
	Body = {
		row("body_round", "Redondito", "Common", { 255, 214, 150 }),
		row("body_chubby", "Gordito", "Common", { 240, 180, 120 }),
		row("body_long", "Alargado", "Common", { 200, 230, 140 }),
		row("body_tiny", "Mini", "Common", { 255, 190, 200 }),
		row("body_fluffy", "Peludo", "Common", { 245, 245, 235 }),
		row("body_crystal", "Cristalino", "Rare", { 150, 230, 255 }),
		row("body_lava", "Lava", "Rare", { 255, 90, 40 }),
		row("body_jelly", "Gelatina", "Rare", { 120, 255, 180 }),
		row("body_stone", "Pétreo", "Epic", { 130, 130, 140 }),
		row("body_cloud", "Nube", "Epic", { 230, 240, 255 }),
		row("body_star", "Estelar", "Legendary", { 255, 240, 120 }),
		row("body_void", "Vacío", "Mythic", { 40, 20, 60 }),
	},
	Head = {
		row("head_beak", "Pico", "Common", { 255, 200, 60 }),
		row("head_ears", "Orejitas", "Common", { 230, 170, 140 }),
		row("head_horn", "Cuernito", "Common", { 240, 230, 210 }),
		row("head_bunny", "Conejo", "Common", { 255, 230, 240 }),
		row("head_frog", "Rana", "Common", { 110, 200, 90 }),
		row("head_feathered", "Plumado", "Rare", { 120, 200, 255 }),
		row("head_crown", "Corona", "Rare", { 255, 210, 60 }),
		row("head_cyclops", "Cíclope", "Rare", { 200, 120, 255 }),
		row("head_dragon", "Dragón", "Epic", { 220, 60, 60 }),
		row("head_mask", "Máscara", "Epic", { 60, 60, 70 }),
		row("head_halo", "Halo", "Legendary", { 255, 255, 200 }),
		row("head_comet", "Cometa", "Mythic", { 120, 220, 255 }),
	},
	Pattern = {
		row("pattern_plain", "Liso", "Common", { 255, 255, 255 }),
		row("pattern_spots", "Moteado", "Common", { 120, 80, 50 }),
		row("pattern_stripes", "Rayado", "Common", { 60, 60, 60 }),
		row("pattern_dots", "Lunares", "Common", { 255, 120, 160 }),
		row("pattern_patch", "Parches", "Common", { 180, 140, 90 }),
		row("pattern_bone", "Óseo", "Rare", { 240, 235, 220 }),
		row("pattern_zigzag", "Zigzag", "Rare", { 255, 170, 0 }),
		row("pattern_scales", "Escamas", "Rare", { 60, 170, 120 }),
		row("pattern_runes", "Rúnico", "Epic", { 90, 200, 255 }),
		row("pattern_galaxy", "Galaxia", "Epic", { 90, 40, 160 }),
		row("pattern_gold", "Dorado", "Legendary", { 255, 200, 40 }),
		row("pattern_prism", "Prisma", "Mythic", { 255, 120, 255 }),
	},
	Aura = {
		row("aura_none", "Sin aura", "Common", { 255, 255, 255 }),
		row("aura_dust", "Polvo", "Common", { 200, 190, 170 }),
		row("aura_leaves", "Hojas", "Common", { 90, 190, 70 }),
		row("aura_bubbles", "Burbujas", "Common", { 160, 220, 255 }),
		row("aura_sparks", "Chispas", "Common", { 255, 230, 120 }),
		row("aura_fire", "Fuego", "Rare", { 255, 110, 30 }),
		row("aura_frost", "Escarcha", "Rare", { 180, 240, 255 }),
		row("aura_hearts", "Corazones", "Rare", { 255, 90, 140 }),
		row("aura_lightning", "Rayos", "Epic", { 255, 255, 90 }),
		row("aura_shadow", "Sombra", "Epic", { 50, 30, 70 }),
		row("aura_sun", "Solar", "Legendary", { 255, 190, 40 }),
		row("aura_eclipse", "Eclipse", "Mythic", { 120, 0, 40 }),
	},
	Mutation = {
		row("mut_none", "Normal", "Common", { 255, 255, 255 }),
		row("mut_big", "Gigante", "Common", { 255, 255, 255 }),
		row("mut_small", "Diminuto", "Common", { 255, 255, 255 }),
		row("mut_shiny", "Brillante", "Common", { 255, 255, 220 }),
		row("mut_twin", "Gemelo", "Rare", { 255, 255, 255 }),
		row("mut_inverted", "Invertido", "Rare", { 0, 0, 0 }),
		row("mut_glow", "Fosforito", "Rare", { 140, 255, 120 }),
		row("mut_ghost", "Fantasma", "Epic", { 220, 230, 255 }),
		row("mut_golden", "Dorado", "Epic", { 255, 200, 40 }),
		row("mut_ancient", "Ancestral", "Legendary", { 180, 150, 100 }),
		row("mut_cosmic", "Cósmico", "Mythic", { 80, 60, 200 }),
		row("mut_rainbow", "Arcoíris Eterno", "Secret", { 255, 0, 255 }),
	},
}

Genes.ById = {} :: { [string]: Gene }
Genes.BySlot = {} :: { [Slot]: { Gene } }

for _, slot in Genes.Slots do
	local list: { Gene } = {}
	for _, entry in CATALOG[slot] do
		local gene: Gene = {
			Id = entry.Id,
			Slot = slot,
			Name = entry.Name,
			Rarity = entry.Rarity,
			Color = entry.Color,
		}
		table.insert(list, gene)
		Genes.ById[gene.Id] = gene
	end
	Genes.BySlot[slot] = list
end

-- Objetos de ofrenda que se encuentran en el mapa y el gen que favorecen (GDD 5.2).
Genes.Offerings = {
	Crystal = { DisplayName = "Cristal", Slot = "Body" :: Slot, Gene = "body_crystal" },
	Feather = { DisplayName = "Pluma", Slot = "Head" :: Slot, Gene = "head_feathered" },
	Bone = { DisplayName = "Hueso", Slot = "Pattern" :: Slot, Gene = "pattern_bone" },
}

-- Probabilidad de que una ofrenda imponga su gen cuando la rareza lo permite.
Genes.BiasChance = 0.5

function Genes.get(id: string): Gene?
	return Genes.ById[id]
end

function Genes.isValidSet(genes: any): boolean
	if type(genes) ~= "table" then
		return false
	end
	for _, slot in Genes.Slots do
		local gene = Genes.ById[genes[slot]]
		if not gene or gene.Slot ~= slot then
			return false
		end
	end
	return true
end

local function pickFrom(list: { Gene }, rng: () -> number): Gene
	return list[math.floor(rng() * #list) + 1] or list[1]
end

local function genesOfTier(slot: Slot, tier: number): { Gene }
	local out = {}
	for _, gene in Genes.BySlot[slot] do
		if Rarity.tier(gene.Rarity) == tier then
			table.insert(out, gene)
		end
	end
	return out
end

-- Gen aleatorio de una ranura con rareza como mucho maxRarity.
function Genes.rollSlot(slot: Slot, rng: () -> number, maxRarity: RarityName, biasGeneId: string?): string
	local maxTier = Rarity.tier(maxRarity)
	if biasGeneId then
		local biased = Genes.ById[biasGeneId]
		if biased and biased.Slot == slot and Rarity.tier(biased.Rarity) <= maxTier and rng() < Genes.BiasChance then
			return biased.Id
		end
	end

	local tier = Rarity.tier(Rarity.roll(rng, 1, nil, maxRarity))
	while tier >= 1 do
		local candidates = genesOfTier(slot, tier)
		if #candidates > 0 then
			return pickFrom(candidates, rng).Id
		end
		tier -= 1
	end
	return Genes.BySlot[slot][1].Id
end

-- Genera los genes de una criatura de rareza exacta `rarity`: una ranura recibe un gen
-- de esa rareza (el "gen firma") y el resto se tira con rareza igual o menor.
function Genes.rollSet(rng: () -> number, rarity: RarityName, biases: Biases?): GeneSet
	local tier = Rarity.tier(rarity)
	local signatureSlots: { Slot } = {}
	for _, slot in Genes.Slots do
		if #genesOfTier(slot, tier) > 0 then
			table.insert(signatureSlots, slot)
		end
	end

	local signatureSlot = signatureSlots[math.floor(rng() * #signatureSlots) + 1] or signatureSlots[1]
	local result = {}
	for _, slot in Genes.Slots do
		if slot == signatureSlot then
			local biasId = biases and biases[slot]
			local biased = biasId and Genes.ById[biasId]
			if biased and biased.Slot == slot and biased.Rarity == rarity and rng() < Genes.BiasChance then
				result[slot] = biased.Id
			else
				result[slot] = pickFrom(genesOfTier(slot, tier), rng).Id
			end
		else
			result[slot] = Genes.rollSlot(slot, rng, rarity, biases and biases[slot])
		end
	end
	return result :: any
end

function Genes.rarityOf(genes: GeneSet): RarityName
	local best = 1
	for _, slot in Genes.Slots do
		local gene = Genes.ById[(genes :: any)[slot]]
		if gene then
			best = math.max(best, Rarity.tier(gene.Rarity))
		end
	end
	return Rarity.fromTier(best)
end

-- Cría: cada ranura hereda de uno de los padres; con mutationChance se vuelve a tirar
-- con rareza máxima un nivel por encima del mejor padre (GDD 5.7).
function Genes.inherit(a: GeneSet, b: GeneSet, rng: () -> number, mutationChance: number): GeneSet
	local parentRarity = Rarity.max(Genes.rarityOf(a), Genes.rarityOf(b))
	local mutationCap = Rarity.fromTier(math.min(Rarity.tier(parentRarity) + 1, Rarity.tier("Mythic")))
	local child = {}
	for _, slot in Genes.Slots do
		if rng() < mutationChance then
			child[slot] = Genes.rollSlot(slot, rng, mutationCap)
		else
			child[slot] = if rng() < 0.5 then (a :: any)[slot] else (b :: any)[slot]
		end
	end
	return child :: any
end

-- Copia común para el aliado de un trato: conserva los genes comunes de la criatura y
-- cambia el resto por genes comunes de la misma ranura.
function Genes.commonCopy(source: GeneSet, rng: () -> number): GeneSet
	local copy = table.clone(source) :: any
	for _, slot in Genes.Slots do
		local gene = Genes.ById[copy[slot]]
		if not gene or gene.Rarity ~= "Common" then
			copy[slot] = Genes.rollSlot(slot, rng, "Common")
		end
	end
	return copy
end

return Genes
