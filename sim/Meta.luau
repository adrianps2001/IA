--!strict
-- Simula semanas de juego: una población de bots entra en servidores varias veces al día,
-- juega rondas (Round.luau), cobra su nido (también sin conexión), compra mejoras, cría,
-- abre huevos, hace misiones y renace. Mide la economía y el equilibrio día a día.

local Config = require("../src/shared/Config")
local Creature = require("../src/shared/Creature")
local Economy = require("../src/shared/Economy")
local Genes = require("../src/shared/Genes")
local PlayerData = require("../src/shared/PlayerData")
local Quests = require("../src/shared/Quests")
local Rarity = require("../src/shared/Rarity")

local Archetypes = require("./Archetypes")
local Rng = require("./Rng")
local Round = require("./Round")

export type Params = {
	Seed: number,
	Population: number,
	Days: number,
	SlotsPerDay: number,
	ServerSize: number,
	Mix: { [string]: number },
}

type Player = {
	Bot: Round.Bot,
	Profile: PlayerData.Profile,
	Wins: number,
	Chosen: number,
	Rounds: number,
	FirstWinDay: number?,
	DustFromRounds: number,
	DustFromQuests: number,
	CoinsOnline: number,
	CoinsOffline: number,
	EggsHatched: number,
	Bred: number,
	Released: number,
	ChosenEggs: number,
	DustFromRelease: number,
	CoinsOnDecor: number,
	DustOnDecor: number,
}

local Meta = {}

Meta.Defaults = {
	Seed = 1,
	Population = 72,
	Days = 30,
	SlotsPerDay = 6,
	ServerSize = 12,
	Mix = Archetypes.DefaultMix,
} :: Params

local SIM_START = math.floor(1_792_000_000 / 86400) * 86400 -- un día de octubre de 2026 (UTC)

local function mean(list: { number }): number
	if #list == 0 then
		return 0
	end
	local total: number = 0
	for _, v in list do
		total += v
	end
	return total / #list
end

local function median(list: { number }): number
	if #list == 0 then
		return 0
	end
	local sorted = table.clone(list)
	table.sort(sorted)
	local mid = (#sorted + 1) / 2
	return (sorted[math.floor(mid)] + sorted[math.ceil(mid)]) / 2
end

function Meta.run(params: Params)
	local rng = Rng.new(params.Seed)
	local nextCreatureId: number = 0
	local function newId(): string
		nextCreatureId += 1
		return "c" .. nextCreatureId
	end

	-- Población según la mezcla de arquetipos.
	local players: { Player } = {}
	local keys = {}
	for key in params.Mix do
		table.insert(keys, key)
	end
	table.sort(keys)
	local id: number = 0
	for _, key in keys do
		local count = math.floor(params.Population * params.Mix[key] + 0.5)
		for _ = 1, count do
			id += 1
			local arch = Archetypes.ByKey[key]
			local profile = PlayerData.default(SIM_START)
			-- Igual que NestService: una criatura común de regalo la primera vez.
			table.insert(profile.Creatures, Creature.new(newId(), Genes.rollSet(rng, "Common"), "Starter", SIM_START))
			local bot: Round.Bot = {
				Id = id,
				Name = string.format("%s %d", arch.Label, id),
				Arch = arch,
				Upgrades = profile.Upgrades,
				Payer = arch.Payer,
			}
			table.insert(players, {
				Bot = bot,
				Profile = profile,
				Wins = 0,
				Chosen = 0,
				Rounds = 0,
				FirstWinDay = nil,
				DustFromRounds = 0,
				DustFromQuests = 0,
				CoinsOnline = 0,
				CoinsOffline = 0,
				EggsHatched = 0,
				Bred = 0,
				Released = 0,
				ChosenEggs = 0,
				DustFromRelease = 0,
				CoinsOnDecor = 0,
				DustOnDecor = 0,
			})
		end
	end

	local function slots(p: Player): number
		return Economy.nestSlots(p.Profile.Upgrades.Nest, p.Bot.Payer)
	end

	local function income(p: Player): number
		return Creature.activeIncome(p.Profile.Creatures, slots(p)) * Economy.incomeMultiplier(p.Profile.Generation, p.Bot.Payer, false)
	end

	local function questProgress(p: Player, kind: Quests.QuestKind, amount: number)
		if amount <= 0 then
			return
		end
		local done = Quests.progress(p.Profile.Quests, kind, amount)
		if done > 0 then
			p.Profile.Dust += done * Config.Quests.RewardDust
			p.DustFromQuests += done * Config.Quests.RewardDust
		end
	end

	local function addEgg(p: Player, kind: string, seconds: number, minRarity: Rarity.RarityName, maxRarity: Rarity.RarityName, genes: Genes.GeneSet?, now: number)
		table.insert(p.Profile.Incubator, {
			Id = newId(),
			Kind = kind,
			Genes = genes,
			MinRarity = minRarity,
			MaxRarity = maxRarity,
			ReadyAt = now + Economy.incubationSeconds(seconds, p.Profile.Upgrades.Incubator, false),
		})
	end

	local function collectEggs(p: Player, now: number)
		local remaining = {}
		for _, egg in p.Profile.Incubator do
			if egg.ReadyAt <= now then
				local genes = egg.Genes
				if not genes then
					genes = Genes.rollSet(rng, Rarity.roll(rng, 1, egg.MinRarity, egg.MaxRarity))
				end
				table.insert(p.Profile.Creatures, Creature.new(newId(), genes :: Genes.GeneSet, egg.Kind, now))
				p.EggsHatched += 1
				if egg.Kind ~= "Breed" then
					questProgress(p, "HatchPersonal", 1)
				end
			else
				table.insert(remaining, egg)
			end
		end
		p.Profile.Incubator = remaining
	end

	-- Política de gasto de un jugador "razonable" (difiere por arquetipo en la reserva).
	local function spend(p: Player, now: number)
		local profile = p.Profile
		local arch = p.Bot.Arch
		collectEggs(p, now)

		if Economy.canRebirth(#profile.Creatures, profile.Coins, profile.Generation) then
			profile.Generation += 1
			profile.Creatures = {}
			profile.Coins = 0
			profile.Upgrades.Nest = 0
		end

		for _ = 1, 12 do
			local budget = profile.Coins * (1 - arch.Reserve)
			local order = { "Bag", "Boots", "Incubator", "Nest" }
			if #profile.Creatures > slots(p) then
				table.insert(order, 1, "Nest")
			end
			local bought = false
			for _, name in order do
				local cost = Economy.upgradeCost(name :: Economy.UpgradeName, profile.Upgrades[name])
				if cost and cost <= budget then
					profile.Coins -= cost
					profile.Upgrades[name] += 1
					bought = true
					break
				end
			end
			if not bought then
				break
			end
		end

		local free = #profile.Incubator < Economy.incubatorSlots(false)
		if free and profile.Dust >= Config.Incubator.PersonalEggCostDust * 2 then
			profile.Dust -= Config.Incubator.PersonalEggCostDust
			local range = Config.EggRanges.Personal
			addEgg(p, "Personal", Config.Incubator.PersonalEggSeconds, range.Min :: Rarity.RarityName, range.Max :: Rarity.RarityName, nil, now)
			free = false
		end
		if free and #profile.Creatures >= 2 then
			local sorted = Creature.sortByIncome(profile.Creatures)
			local a, b = sorted[1], sorted[2]
			local parentRarity = Rarity.max(a.Rarity, b.Rarity)
			local cost = Economy.breedCost(parentRarity)
			if cost <= profile.Coins * (1 - arch.Reserve) then
				profile.Coins -= cost
				local child = Genes.inherit(a.Genes, b.Genes, rng, Config.Breeding.MutationChance)
				local childRarity = Genes.rarityOf(child)
				addEgg(p, "Breed", Economy.breedSeconds(parentRarity), childRarity, childRarity, child, now)
				p.Bred += 1
				questProgress(p, "Breed", 1)
				free = false
			end
		end
		if free and profile.Dust >= Config.Incubator.PersonalEggCostDust then
			profile.Dust -= Config.Incubator.PersonalEggCostDust
			local range = Config.EggRanges.Personal
			addEgg(p, "Personal", Config.Incubator.PersonalEggSeconds, range.Min :: Rarity.RarityName, range.Max :: Rarity.RarityName, nil, now)
		end

		-- Liberar: cuando hay más de 20 guardadas, usa el botón "liberar guardadas".
		if #profile.Creatures > slots(p) + 20 then
			local released = {}
			for _, id in Economy.bulkReleaseIds(profile.Creatures, slots(p)) do
				released[id] = true
			end
			local kept = {}
			for _, c in profile.Creatures do
				if released[c.Id] then
					local dust = Economy.releaseDust(c.Rarity) or 0
					profile.Dust += dust
					p.DustFromRelease += dust
					p.Released += 1
				else
					table.insert(kept, c)
				end
			end
			profile.Creatures = kept
		end

		-- Decorar con lo que sobra: la más barata que no tenga, si cuesta como mucho un cuarto
		-- de lo que está dispuesto a gastar (de Polvo, si le queda para dos huevos personales).
		for _, def in if Config.Sinks.Decorations then Config.Decorations else {} do
			if not table.find(profile.Decorations, def.Id) then
				local cost = Economy.decorationCost(def)
				if def.Currency == "Coins" and cost <= profile.Coins * (1 - arch.Reserve) * 0.25 then
					profile.Coins -= cost
					p.CoinsOnDecor += cost
					table.insert(profile.Decorations, def.Id)
				elseif def.Currency == "Dust" and profile.Dust - cost >= Config.Incubator.PersonalEggCostDust * 2 then
					profile.Dust -= cost
					p.DustOnDecor += cost
					table.insert(profile.Decorations, def.Id)
				end
			end
		end
	end

	local function login(p: Player, now: number)
		local profile = p.Profile
		local earned = Economy.offlineEarnings(income(p), now - profile.LastSeen)
		profile.Coins += earned
		p.CoinsOffline += earned
		if Quests.rollover(profile.Quests, Quests.dayNumber(now)) then
			local range = Config.EggRanges.Streak
			addEgg(p, "Streak", 60, range.Min :: Rarity.RarityName, range.Max :: Rarity.RarityName, nil, now)
		end
		spend(p, now)
	end

	local function isBloodMoon(now: number): boolean
		local def = Config.Events.BloodMoon
		local daysSinceEpoch = math.floor(now / 86400)
		local wday = ((daysSinceEpoch + 4) % 7) + 1 -- 1 = domingo, como os.date("*t").wday
		local hour = math.floor((now % 86400) / 3600)
		return wday == def.WeekDay and hour >= def.StartHour and hour < def.StartHour + def.Hours
	end

	local rounds = {}
	local daily = {}
	local slotLength = 86400 / params.SlotsPerDay

	for day = 0, params.Days - 1 do
		for slot = 0, params.SlotsPerDay - 1 do
			local slotStart = SIM_START + day * 86400 + slot * slotLength
			local online: { Player } = {}
			for _, p in players do
				if rng() < p.Bot.Arch.SessionsPerDay / params.SlotsPerDay then
					table.insert(online, p)
				end
			end
			Rng.shuffle(rng, online)
			local servers: { { Player } } = {}
			local current: { Player } = {}
			for _, p in online do
				table.insert(current, p)
				if #current >= params.ServerSize then
					table.insert(servers, current)
					current = {} :: { Player }
				end
			end
			if #current >= 4 or (#current >= 2 and #servers == 0) then
				table.insert(servers, current)
			elseif #servers > 0 then
				for _, p in current do
					table.insert(servers[#servers], p)
				end
			end

			for _, server in servers do
				local t: number = slotStart + Rng.range(rng, 0, slotLength * 0.5)
				for _, p in server do
					login(p, t)
				end
				local maxRounds: number = 0
				for _, p in server do
					maxRounds = math.max(maxRounds, p.Bot.Arch.RoundsPerSession)
				end
				for r = 1, maxRounds do
					local members: { Player } = {}
					for _, p in server do
						if p.Bot.Arch.RoundsPerSession >= r then
							table.insert(members, p)
						end
					end
					if #members < 2 then
						break
					end
					local bots: { Round.Bot } = {}
					for _, p in members do
						table.insert(bots, p.Bot)
					end
					local summary, perBot = Round.run(bots, rng, { BloodMoon = isBloodMoon(t) })
					local duration: number = summary.DurationSeconds
					t += duration
					summary.Day = day
					table.insert(rounds, summary)
					for _, p in members do
						local result = perBot[p.Bot.Id]
						local profile = p.Profile
						local earned = income(p) * duration
						profile.Coins += earned
						p.CoinsOnline += earned
						profile.Dust += result.Dust
						p.DustFromRounds += result.Dust
						p.Rounds += 1
						profile.Stats.RoundsPlayed += 1
						profile.Stats.HeatDeposited += result.Deposited
						profile.Stats.Steals += result.Steals
						profile.Stats.StealAttempts += result.Attempts
						profile.Stats.PactsBroken += result.PactsBroken
						if result.PactKept then
							profile.Stats.PactsKept += 1
						end
						if result.Chosen then
							p.Chosen += 1
							p.Bot.RoundsSinceChosen = 0
						else
							p.Bot.RoundsSinceChosen = (p.Bot.RoundsSinceChosen or 0) + 1
						end
						if result.Genes then
							table.insert(profile.Creatures, Creature.new(newId(), result.Genes, "Hatch", t))
							p.Wins += 1
							profile.Stats.Wins += 1
							if not p.FirstWinDay then
								p.FirstWinDay = day
							end
							questProgress(p, "WinCreature", 1)
						end
						if result.Copy then
							table.insert(profile.Creatures, Creature.new(newId(), result.Copy, "Copy", t))
						end
						if result.ChosenEgg then
							local range = Config.EggRanges.Chosen
							addEgg(p, "Chosen", Config.Incubator.PersonalEggSeconds, range.Min :: Rarity.RarityName, range.Max :: Rarity.RarityName, nil, t)
							p.ChosenEggs += 1
						end
						questProgress(p, "DepositHeat", result.Deposited)
						questProgress(p, "LuckyBlock", result.LuckyBlocks)
						questProgress(p, "Steal", result.Steals)
						questProgress(p, "PlayRounds", 1)
						spend(p, t)
						profile.LastSeen = t
					end
				end
			end
		end

		-- Foto del final del día por arquetipo.
		local snapshot = { Day = day + 1, ByArch = {} :: { [string]: any } }
		local allCoins: number = 0
		for _, key in keys do
			local coins, creatures, incomes, generations, dust, wins, winners, bag, nest, best = {}, {}, {}, {}, {}, {}, 0, {}, {}, {}
			local decor, releasedList = {}, {}
			local everChosen: number = 0
			local count: number = 0
			for _, p in players do
				if p.Bot.Arch.Key == key then
					count += 1
					local profile = p.Profile
					table.insert(coins, profile.Coins)
					table.insert(creatures, #profile.Creatures)
					table.insert(incomes, income(p))
					table.insert(generations, profile.Generation)
					table.insert(dust, profile.Dust)
					table.insert(wins, p.Wins)
					table.insert(bag, profile.Upgrades.Bag)
					table.insert(nest, profile.Upgrades.Nest)
					table.insert(decor, #profile.Decorations)
					table.insert(releasedList, p.Released)
					local bestTier: number = 1
					for _, c in profile.Creatures do
						bestTier = math.max(bestTier, Rarity.tier(c.Rarity))
					end
					table.insert(best, bestTier)
					if p.Wins > 0 then
						winners += 1
					end
					if p.Chosen > 0 then
						everChosen += 1
					end
					allCoins += profile.Coins
				end
			end
			snapshot.ByArch[key] = {
				Players = count,
				Coins = mean(coins),
				CoinsMedian = median(coins),
				Creatures = mean(creatures),
				CreaturesMax = (function()
					local m: number = 0
					for _, v in creatures do
						m = math.max(m, v)
					end
					return m
				end)(),
				Income = mean(incomes),
				Generation = mean(generations),
				Dust = mean(dust),
				Wins = mean(wins),
				WinnersShare = if count > 0 then winners / count else 0,
				ChosenShare = if count > 0 then everChosen / count else 0,
				BagLevel = mean(bag),
				NestLevel = mean(nest),
				BestTier = mean(best),
				Decorations = mean(decor),
				Released = mean(releasedList),
			}
		end
		snapshot.TotalCoins = allCoins
		table.insert(daily, snapshot)
	end

	local final = {}
	for _, p in players do
		local profile = p.Profile
		local bestTier: number = 1
		local rarityCounts: { [string]: number } = {}
		for _, c in profile.Creatures do
			bestTier = math.max(bestTier, Rarity.tier(c.Rarity))
			rarityCounts[c.Rarity] = (rarityCounts[c.Rarity] or 0) + 1
		end
		table.insert(final, {
			Id = p.Bot.Id,
			Arch = p.Bot.Arch.Key,
			Rounds = p.Rounds,
			Wins = p.Wins,
			Chosen = p.Chosen,
			FirstWinDay = p.FirstWinDay,
			Creatures = #profile.Creatures,
			RarityCounts = rarityCounts,
			BestTier = bestTier,
			Coins = profile.Coins,
			Income = income(p),
			Generation = profile.Generation,
			Upgrades = profile.Upgrades,
			DustFromRounds = p.DustFromRounds,
			DustFromQuests = p.DustFromQuests,
			CoinsOnline = p.CoinsOnline,
			CoinsOffline = p.CoinsOffline,
			EggsHatched = p.EggsHatched,
			Bred = p.Bred,
			Released = p.Released,
			ChosenEggs = p.ChosenEggs,
			DustFromRelease = p.DustFromRelease,
			CoinsOnDecor = p.CoinsOnDecor,
			DustOnDecor = p.DustOnDecor,
			Decorations = #profile.Decorations,
			PactsKept = profile.Stats.PactsKept,
			PactsBroken = profile.Stats.PactsBroken,
		})
	end

	return { Params = params, Rounds = rounds, Daily = daily, Players = final }
end

return Meta
