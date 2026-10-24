--!strict
-- Esquema de los datos guardados de cada jugador y su reparación al cargar.

local Config = require("./Config")
local Cosmetics = require("./Cosmetics")
local Creature = require("./Creature")
local DailyReward = require("./DailyReward")
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
	Decorations: { string }, -- ids de Config.Decorations compradas
	Community: CommunityState, -- aportación al Huevo Comunitario del mes
	Trades: { TradeRecord },
	Favorites: { string }, -- ids de criaturas marcadas con ⭐ (Config.Favorites.Max)
	Shoulder: string?, -- id de la criatura que llevas al hombro (nil = ninguna)
	Likes: { Week: string, Given: { number } }, -- "me gusta" dados esta semana
	Settings: Settings, -- ajustes del jugador (v3.1, botón ⚙️)
	Daily: DailyReward.State, -- regalo diario (v3.1)
	Cosmetics: CosmeticsState, -- Tienda de la Plaza: lo comprado y lo que llevas puesto (v3.1)
}

-- Ajustes (v3.1): volumen de efectos y de pasos (0 a 1), tamaño de la interfaz y si se ven
-- las criaturas al hombro de los demás (en móviles flojos conviene quitarlas).
export type Settings = { Effects: number, Steps: number, UIScale: number, ShowPets: boolean }
export type CosmeticsState = { Owned: { string }, Hat: string?, Theme: string? }

export type CommunityState = { Month: string, Heat: number, Claimed: boolean }

-- Historial de intercambios (los últimos Config.Trade.HistorySize).
export type TradeRecord = { With: number, WithName: string, Gave: { string }, Got: { string }, At: number }

local PlayerData = {}

PlayerData.Version = 1
PlayerData.MaxReceipts = 50

PlayerData.StatNames = {
	"Steals",
	"StealAttempts",
	"Wins",
	"PactsKept",
	"PactsBroken",
	"RoundsPlayed",
	"HeatDeposited",
	"RoundsSinceChosen", -- para la suerte acumulada de la Elección
	"Released", -- criaturas liberadas
	"Trades", -- intercambios completados
	"LikesReceived", -- "me gusta" recibidos en el nido (total)
}

function PlayerData.default(now: number): Profile
	local stats = {}
	for _, name in PlayerData.StatNames do
		stats[name] = 0
	end
	return {
		Version = PlayerData.Version,
		Coins = 0,
		Dust = 0,
		Upgrades = { Bag = 0, Boots = 0, Nest = 0, Incubator = 0 }, -- (v3.1: se quitó el Olfato, que no hacía nada)
		Creatures = {},
		Incubator = {},
		Generation = 0,
		Stats = stats,
		Quests = Quests.newState(Quests.dayNumber(now)),
		LastSeen = now,
		Receipts = {},
		LastBreed = nil,
		Funnel = {},
		Decorations = {},
		Community = { Month = "", Heat = 0, Claimed = false },
		Trades = {},
		Favorites = {},
		Likes = { Week = "", Given = {} },
		Settings = PlayerData.cleanSettings(nil),
		Daily = DailyReward.newState(),
		Cosmetics = { Owned = {} },
	}
end

local function number(value: any, fallback: number): number
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return fallback
end

PlayerData.SettingsLimits = { UIScale = { Min = 0.8, Max = 1.3 } }

-- Ajustes válidos a partir de lo que llegue (del DataStore o del cliente): números acotados y
-- valores por defecto para lo que falte o no tenga sentido.
function PlayerData.cleanSettings(raw: any): Settings
	local t = if type(raw) == "table" then raw else {}
	local limits = PlayerData.SettingsLimits.UIScale
	return {
		Effects = math.clamp(number(t.Effects, 1), 0, 1),
		Steps = math.clamp(number(t.Steps, 1), 0, 1),
		UIScale = math.clamp(number(t.UIScale, 1), limits.Min, limits.Max),
		ShowPets = if type(t.ShowPets) == "boolean" then t.ShowPets else true,
	}
end

local function strings(list: { any }): { string }
	local out = {}
	for _, value in list do
		if type(value) == "string" then
			table.insert(out, value)
		end
	end
	return out
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

	if type(raw.Decorations) == "table" then
		for _, id in raw.Decorations do
			if type(id) == "string" and not table.find(profile.Decorations, id) then
				table.insert(profile.Decorations, id)
			end
		end
	end

	local community = raw.Community
	if type(community) == "table" and type(community.Month) == "string" then
		profile.Community = {
			Month = community.Month,
			Heat = math.max(number(community.Heat, 0), 0),
			Claimed = community.Claimed == true,
		}
	end

	if type(raw.Trades) == "table" then
		for _, record in raw.Trades do
			if type(record) == "table" and type(record.WithName) == "string" and type(record.Gave) == "table" and type(record.Got) == "table" then
				table.insert(profile.Trades, {
					With = number(record.With, 0),
					WithName = record.WithName,
					Gave = strings(record.Gave),
					Got = strings(record.Got),
					At = number(record.At, 0),
				})
			end
		end
	end

	profile.Settings = PlayerData.cleanSettings(raw.Settings)
	profile.Daily = DailyReward.clean(raw.Daily)
	-- Estética: solo artículos que existen, sin repetir; lo puesto, solo si es tuyo y del tipo.
	local cosmetics = raw.Cosmetics
	if type(cosmetics) == "table" then
		if type(cosmetics.Owned) == "table" then
			for _, id in cosmetics.Owned do
				if Cosmetics.get(id) and not table.find(profile.Cosmetics.Owned, id) then
					table.insert(profile.Cosmetics.Owned, id)
				end
			end
		end
		for _, kind in { "Hat", "Theme" } do
			local id = cosmetics[kind]
			local item = Cosmetics.get(id)
			if item and item.Kind == kind and table.find(profile.Cosmetics.Owned, id) then
				(profile.Cosmetics :: any)[kind] = id
			end
		end
	end

	-- Al hombro: solo si la criatura existe.
	if type(raw.Shoulder) == "string" and PlayerData.findCreature(profile, raw.Shoulder) then
		profile.Shoulder = raw.Shoulder
	end
	-- Favoritas: solo ids de criaturas que existen, sin repetir y como mucho Config.Favorites.Max.
	if type(raw.Favorites) == "table" then
		for _, id in raw.Favorites do
			if type(id) == "string" and not table.find(profile.Favorites, id) and #profile.Favorites < Config.Favorites.Max and PlayerData.findCreature(profile, id) then
				table.insert(profile.Favorites, id)
			end
		end
	end

	local likes = raw.Likes
	if type(likes) == "table" and type(likes.Week) == "string" and type(likes.Given) == "table" then
		local given = {}
		for _, userId in likes.Given do
			if type(userId) == "number" then
				table.insert(given, userId)
			end
		end
		profile.Likes = { Week = likes.Week, Given = given }
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
