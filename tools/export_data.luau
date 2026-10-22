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

local Json = require("./Json")

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

print(Json.encode({
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
