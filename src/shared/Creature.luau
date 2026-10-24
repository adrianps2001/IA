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
	Nickname: string?, -- nombre que le puso su dueño (v3.1, ya pasado por el filtro de texto de Roblox)
}

local Creature = {}

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

-- Nombre que se enseña: el que le puso su dueño o, si no tiene, el de su especie.
function Creature.displayName(creature: Creature): string
	local nick = creature.Nickname
	if nick and nick ~= "" then
		return nick
	end
	return Creature.name(creature)
end

Creature.NicknameMax = 20

-- Limpia un nombre escrito por el jugador: sin espacios de más ni saltos de línea, y como mucho
-- NicknameMax letras. "" quita el nombre. nil si no es texto. (El filtro de Roblox va después,
-- en el servidor: esto solo pone orden.)
function Creature.cleanNickname(text: any): string?
	if type(text) ~= "string" then
		return nil
	end
	local clean = string.gsub(text, "[%c]", " ")
	clean = string.gsub(clean, "%s+", " ")
	clean = string.match(clean, "^%s*(.-)%s*$") or ""
	if (utf8.len(clean) or 0) > Creature.NicknameMax then
		local cut = utf8.offset(clean, Creature.NicknameMax + 1)
		clean = if cut then string.sub(clean, 1, cut - 1) else clean
	end
	return clean
end

-- Monedas por segundo sin multiplicadores del jugador (v3.2): la suma de lo que da cada una de
-- sus 5 partes según la rareza de esa parte (Rarity.Info[...].PartIncome). Antes salía solo de
-- la rareza más alta; ahora una Épica con el resto de partes raras produce más que una Épica
-- con todo lo demás común.
function Creature.baseIncome(creature: Creature): number
	local total = 0
	for _, slot in Genes.Slots do
		local gene = Genes.get((creature.Genes :: any)[slot])
		local rarity: Rarity.RarityName = if gene then gene.Rarity else "Common"
		total += Rarity.Info[rarity].PartIncome
	end
	return total
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
