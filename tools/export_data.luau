--!strict
-- Exporta los datos del juego (Config, rarezas, genes, misiones) en JSON para la web de
-- documentación. Lo usa tools/build_docs.py; así la web nunca enseña números desfasados.
-- Uso: luau tools/export_data.luau

local ArenaLayout = require("../src/shared/ArenaLayout")
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

-- Parkour de la arena (GDD v3), ya calculado, para el mapa de la web.
local arena = ArenaLayout.get()
local links = {}
for _, link in arena.Links do
	local a, b = ArenaLayout.linkEnds(arena, link)
	table.insert(links, { Kind = link.Kind, Level = link.Level, From = { a.X, a.Z }, To = { b.X, b.Z } })
end
local trees = {}
for _, tree in arena.Trees do
	table.insert(trees, { X = tree.X, Z = tree.Z, Radius = tree.Radius, Half = ArenaLayout.deckHalf(tree), Decks = tree.Decks, Ramp = tree.Ramp, Hut = tree.Hut ~= nil })
end
local rides = {}
for _, ride in arena.Rides do
	table.insert(rides, { Kind = ride.Kind, From = { ride.From.X, ride.From.Z }, To = { ride.To.X, ride.To.Z } })
end
local trampolines = {}
for _, t in arena.Trampolines do
	table.insert(trampolines, { t.X, t.Z })
end

print(Json.encode({
	Arena = { Trees = trees, Links = links, Rides = rides, Trampolines = trampolines },
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
