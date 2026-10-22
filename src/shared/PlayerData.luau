--!strict
-- Esquema de los datos guardados de cada jugador y su reparación al cargar.

local Creature = require("./Creature")
local Genes = require("./Genes")
local Quests = require("./Quests")
local Rarity = require("./Rarity")

export type IncubatorEgg = {
	Id: string,
	Kind: string, -- "Breed" | "Personal" | "Streak" | "Season"
	Genes: Genes.GeneSet?, -- las crías ya tienen genes decididos
	MinRarity: Rarity.RarityName,
	MaxRarity: Rarity.RarityName,
	ReadyAt: number,
}

export type Profile = {
	Version: number,
	Coins: number,
	Dust: number,
	Upgrades: { [string]: number },
	Creatures: { Creature.Creature },
	Incubator: { IncubatorEgg },
	Generation: number,
	Stats: { [string]: number },
	Quests: Quests.QuestState,
	LastSeen: number,
	Receipts: { string },
	LastBreed: { string }?,
	Funnel: { [string]: boolean },
}

local PlayerData = {}

PlayerData.Version = 1
PlayerData.MaxReceipts = 50

PlayerData.StatNames = { "Steals", "StealAttempts", "Wins", "PactsKept", "PactsBroken", "RoundsPlayed", "HeatDeposited" }

function PlayerData.default(now: number): Profile
	local stats = {}
	for _, name in PlayerData.StatNames do
		stats[name] = 0
	end
	return {
		Version = PlayerData.Version,
		Coins = 0,
		Dust = 0,
		Upgrades = { Bag = 0, Boots = 0, Sniffer = 0, Nest = 0, Incubator = 0 },
		Creatures = {},
		Incubator = {},
		Generation = 0,
		Stats = stats,
		Quests = Quests.newState(Quests.dayNumber(now)),
		LastSeen = now,
		Receipts = {},
		LastBreed = nil,
		Funnel = {},
	}
end

local function number(value: any, fallback: number): number
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return fallback
end

-- Rellena campos que falten y descarta datos corruptos sin perder lo válido.
function PlayerData.reconcile(raw: any, now: number): Profile
	local profile = PlayerData.default(now)
	if type(raw) ~= "table" then
		return profile
	end

	profile.Coins = math.max(number(raw.Coins, 0), 0)
	profile.Dust = math.max(number(raw.Dust, 0), 0)
	profile.Generation = math.max(math.floor(number(raw.Generation, 0)), 0)
	profile.LastSeen = number(raw.LastSeen, now)

	if type(raw.Upgrades) == "table" then
		for name in profile.Upgrades do
			profile.Upgrades[name] = math.max(math.floor(number(raw.Upgrades[name], 0)), 0)
		end
	end

	if type(raw.Stats) == "table" then
		for _, name in PlayerData.StatNames do
			profile.Stats[name] = math.max(number(raw.Stats[name], 0), 0)
		end
	end

	if type(raw.Creatures) == "table" then
		for _, creature in raw.Creatures do
			if Creature.isValid(creature) then
				-- La rareza siempre se recalcula a partir de los genes.
				creature.Rarity = Genes.rarityOf(creature.Genes)
				table.insert(profile.Creatures, creature)
			end
		end
	end

	if type(raw.Incubator) == "table" then
		for _, egg in raw.Incubator do
			if
				type(egg) == "table"
				and type(egg.Id) == "string"
				and type(egg.Kind) == "string"
				and Rarity.isValid(egg.MinRarity)
				and Rarity.isValid(egg.MaxRarity)
				and (egg.Genes == nil or Genes.isValidSet(egg.Genes))
			then
				egg.ReadyAt = number(egg.ReadyAt, now)
				table.insert(profile.Incubator, egg)
			end
		end
	end

	local q = raw.Quests
	if type(q) == "table" and type(q.List) == "table" then
		profile.Quests.Day = math.floor(number(q.Day, profile.Quests.Day))
		profile.Quests.StreakDay = math.floor(number(q.StreakDay, -1))
		profile.Quests.Streak = math.floor(number(q.Streak, 0))
		local list = {}
		for _, quest in q.List do
			if type(quest) == "table" and type(quest.Kind) == "string" then
				table.insert(list, {
					Kind = quest.Kind,
					Goal = math.max(number(quest.Goal, 1), 1),
					Progress = math.max(number(quest.Progress, 0), 0),
					Claimed = quest.Claimed == true,
				})
			end
		end
		if #list > 0 then
			profile.Quests.List = list
		end
	end

	if type(raw.Receipts) == "table" then
		for _, receipt in raw.Receipts do
			if type(receipt) == "string" then
				table.insert(profile.Receipts, receipt)
			end
		end
	end

	if type(raw.LastBreed) == "table" and type(raw.LastBreed[1]) == "string" and type(raw.LastBreed[2]) == "string" then
		profile.LastBreed = { raw.LastBreed[1], raw.LastBreed[2] }
	end

	if type(raw.Funnel) == "table" then
		for key, value in raw.Funnel do
			if type(key) == "string" and value == true then
				profile.Funnel[key] = true
			end
		end
	end

	return profile
end

function PlayerData.findCreature(profile: Profile, id: string): (Creature.Creature?, number?)
	for index, creature in profile.Creatures do
		if creature.Id == id then
			return creature, index
		end
	end
	return nil, nil
end

function PlayerData.hasReceipt(profile: Profile, receiptId: string): boolean
	return table.find(profile.Receipts, receiptId) ~= nil
end

function PlayerData.addReceipt(profile: Profile, receiptId: string)
	table.insert(profile.Receipts, receiptId)
	while #profile.Receipts > PlayerData.MaxReceipts do
		table.remove(profile.Receipts, 1)
	end
end

return PlayerData
