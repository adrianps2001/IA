--!strict
-- Misiones diarias y racha (GDD 6). El día es el número de días UTC desde 1970,
-- así todos los servidores coinciden sin depender de la hora local.

local Config = require("./Config")

export type QuestKind = "Steal" | "DepositHeat" | "Breed" | "HatchPersonal" | "WinCreature" | "LuckyBlock" | "PlayRounds"

export type Quest = {
	Kind: QuestKind,
	Goal: number,
	Progress: number,
	Claimed: boolean,
}

export type QuestState = {
	Day: number,
	List: { Quest },
	StreakDay: number, -- último día con al menos una sesión
	Streak: number,
}

local Quests = {}

Quests.Pool = {
	{ Kind = "Steal" :: QuestKind, Goal = 1, Text = "Roba la criatura %d vez" },
	{ Kind = "DepositHeat" :: QuestKind, Goal = 500, Text = "Deposita %d de Calor" },
	{ Kind = "Breed" :: QuestKind, Goal = 2, Text = "Cría %d huevos" },
	{ Kind = "HatchPersonal" :: QuestKind, Goal = 1, Text = "Abre %d huevo personal" },
	{ Kind = "WinCreature" :: QuestKind, Goal = 1, Text = "Gana %d criatura en una persecución" },
	{ Kind = "LuckyBlock" :: QuestKind, Goal = 3, Text = "Rompe %d bloques de suerte" },
	{ Kind = "PlayRounds" :: QuestKind, Goal = 3, Text = "Juega %d rondas completas" },
}

function Quests.dayNumber(unixSeconds: number): number
	return math.floor(unixSeconds / 86400)
end

function Quests.describe(quest: Quest): string
	for _, def in Quests.Pool do
		if def.Kind == quest.Kind then
			return string.format(def.Text, quest.Goal)
		end
	end
	return quest.Kind
end

-- Generador congruencial simple: misma selección para un día dado.
local function seededOrder(day: number, count: number): { number }
	local order = {}
	for i = 1, count do
		order[i] = i
	end
	local state = (day * 1103515245 + 12345) % 2147483648
	for i = count, 2, -1 do
		state = (state * 1103515245 + 12345) % 2147483648
		local j = (state % i) + 1
		order[i], order[j] = order[j], order[i]
	end
	return order
end

function Quests.forDay(day: number): { Quest }
	local order = seededOrder(day, #Quests.Pool)
	local list = {}
	for i = 1, math.min(Config.Quests.PerDay, #order) do
		local def = Quests.Pool[order[i]]
		table.insert(list, { Kind = def.Kind, Goal = def.Goal, Progress = 0, Claimed = false })
	end
	return list
end

function Quests.newState(day: number): QuestState
	return { Day = day, List = Quests.forDay(day), StreakDay = -1, Streak = 0 }
end

-- Renueva misiones si cambió el día y actualiza la racha. Devuelve true si la racha
-- acaba de completarse (día 7), para entregar el huevo especial.
function Quests.rollover(state: QuestState, today: number): boolean
	if state.Day ~= today then
		state.Day = today
		state.List = Quests.forDay(today)
	end
	if state.StreakDay == today then
		return false
	end
	if state.StreakDay == today - 1 then
		state.Streak += 1
	else
		state.Streak = 1
	end
	state.StreakDay = today
	if state.Streak >= Config.Quests.StreakDays then
		state.Streak = 0
		return true
	end
	return false
end

-- Suma progreso. Devuelve cuántas misiones se completaron con este avance.
function Quests.progress(state: QuestState, kind: QuestKind, amount: number): number
	local completed = 0
	for _, quest in state.List do
		if quest.Kind == kind and not quest.Claimed then
			local before = quest.Progress
			quest.Progress = math.min(quest.Goal, quest.Progress + amount)
			if before < quest.Goal and quest.Progress >= quest.Goal then
				quest.Claimed = true
				completed += 1
			end
		end
	end
	return completed
end

return Quests
