--!strict
-- Datos de una criatura: identificador, genes y rareza derivada. Sin dependencias de Roblox.

local Genes = require("./Genes")
local Rarity = require("./Rarity")

export type Creature = {
	Id: string,
	Genes: Genes.GeneSet,
	Rarity: Rarity.RarityName,
	Origin: string, -- "Hatch" | "Breed" | "PersonalEgg" | "Copy" | "Season"
	Born: number,
	Received: number?, -- cuándo llegó por intercambio (v3.1: las Secretas no se reintercambian enseguida)
}

local Creature = {}

-- Cada gen por encima de Común suma un 5 % por nivel a la producción.
Creature.GeneBonusPerTier = 0.05

function Creature.new(id: string, genes: Genes.GeneSet, origin: string, born: number): Creature
	return {
		Id = id,
		Genes = table.clone(genes),
		Rarity = Genes.rarityOf(genes),
		Origin = origin,
		Born = born,
	}
end

function Creature.isValid(value: any): boolean
	return type(value) == "table"
		and type(value.Id) == "string"
		and Genes.isValidSet(value.Genes)
		and Rarity.isValid(value.Rarity)
end

function Creature.name(creature: Creature): string
	local body = Genes.get(creature.Genes.Body)
	local pattern = Genes.get(creature.Genes.Pattern)
	local mutation = Genes.get(creature.Genes.Mutation)
	local parts = { if body then body.Name else "?" }
	if pattern and pattern.Id ~= "pattern_plain" then
		table.insert(parts, pattern.Name)
	end
	if mutation and mutation.Id ~= "mut_none" then
		table.insert(parts, mutation.Name)
	end
	return table.concat(parts, " ")
end

-- Monedas por segundo sin multiplicadores del jugador.
function Creature.baseIncome(creature: Creature): number
	local bonusTiers = 0
	for _, slot in Genes.Slots do
		local gene = Genes.get((creature.Genes :: any)[slot])
		if gene then
			bonusTiers += Rarity.tier(gene.Rarity) - 1
		end
	end
	return Rarity.Info[creature.Rarity].Income * (1 + Creature.GeneBonusPerTier * bonusTiers)
end

-- Ordena por producción descendente; las primeras `slots` son las que están en el nido.
function Creature.sortByIncome(creatures: { Creature }): { Creature }
	local sorted = table.clone(creatures)
	table.sort(sorted, function(a: Creature, b: Creature): boolean
		local ia, ib = Creature.baseIncome(a), Creature.baseIncome(b)
		if ia == ib then
			return a.Id < b.Id
		end
		return ia > ib
	end)
	return sorted
end

function Creature.activeIncome(creatures: { Creature }, slots: number): number
	local total = 0
	for index, creature in Creature.sortByIncome(creatures) do
		if index > slots then
			break
		end
		total += Creature.baseIncome(creature)
	end
	return total
end

return Creature
