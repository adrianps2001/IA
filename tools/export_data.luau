--!strict
-- Exporta los datos del juego (Config, rarezas, genes, misiones) en JSON para la web de
-- documentación. Lo usa tools/build_docs.py; así la web nunca enseña números desfasados.
-- Uso: luau tools/export_data.luau

local Config = require("../src/shared/Config")
local Creature = require("../src/shared/Creature")
local Economy = require("../src/shared/Economy")
local Genes = require("../src/shared/Genes")
local Quests = require("../src/shared/Quests")
local Rarity = require("../src/shared/Rarity")

local function isArray(t: { [any]: any }): boolean
	local count = 0
	for _ in t do
		count += 1
	end
	return count == #t
end

local function encode(value: any): string
	local kind = type(value)
	if kind == "nil" then
		return "null"
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "null"
		end
		if value == math.floor(value) and math.abs(value) < 1e15 then
			return string.format("%d", value)
		end
		return string.format("%.10g", value)
	elseif kind == "string" then
		local escaped = string.gsub(value, '[%c"\\]', function(c: string)
			local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r" }
			return map[c] or string.format("\\u%04x", string.byte(c))
		end)
		return '"' .. escaped .. '"'
	elseif kind == "table" then
		local parts = {}
		if isArray(value) and #value > 0 then
			for _, item in value do
				table.insert(parts, encode(item))
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for key in value do
			table.insert(keys, tostring(key))
		end
		table.sort(keys)
		for _, key in keys do
			local item = value[key]
			if item == nil then
				item = value[tonumber(key)]
			end
			table.insert(parts, encode(key) .. ":" .. encode(item))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

-- Costes de cada nivel de mejora, ya calculados con la fórmula real.
local upgradeCosts = {}
for _, name in Economy.UpgradeNames do
	local costs = {}
	local level = 0
	while true do
		local cost = Economy.upgradeCost(name, level)
		if not cost then
			break
		end
		table.insert(costs, cost)
		level += 1
	end
	upgradeCosts[name] = { DisplayName = Economy.UpgradeDisplay[name], Costs = costs }
end

local genes = {}
for _, slot in Genes.Slots do
	genes[slot] = Genes.BySlot[slot]
end

local rarities = {}
for _, name in Rarity.Order do
	table.insert(rarities, Rarity.Info[name])
end

local quests = {}
for _, def in Quests.Pool do
	table.insert(quests, { Kind = def.Kind, Goal = def.Goal, Text = string.format(def.Text, def.Goal) })
end

print(encode({
	Config = Config,
	Rarities = rarities,
	Slots = Genes.Slots,
	SlotNames = Genes.SlotNames,
	Genes = genes,
	Offerings = Genes.Offerings,
	BiasChance = Genes.BiasChance,
	UpgradeCosts = upgradeCosts,
	Quests = quests,
	GeneBonusPerTier = Creature.GeneBonusPerTier,
}))
