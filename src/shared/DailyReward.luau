--!strict
-- Regalo diario por entrar (v3.1), sin Roblox para poder probarlo. El estado se guarda en el
-- perfil: el último día (número de día UTC) en que se reclamó y la racha actual (1 a 7).

local Config = require("./Config")

local DailyReward = {}

export type State = { LastDay: number, Streak: number }
export type Reward = { Dust: number?, Coins: number?, Egg: string? }

function DailyReward.newState(): State
	return { LastDay = -1, Streak = 0 }
end

function DailyReward.dayNumber(unixSeconds: number): number
	return math.floor(unixSeconds / 86400)
end

-- ¿Se puede reclamar hoy?
function DailyReward.canClaim(state: State, today: number): boolean
	return Config.DailyReward.Enabled and state.LastDay ~= today
end

-- Qué día de la racha toca si reclamas hoy (1 a #Days).
function DailyReward.nextDay(state: State, today: number): number
	local days = #Config.DailyReward.Days
	if state.LastDay == today - 1 and state.Streak < days then
		return state.Streak + 1
	end
	return 1
end

-- Reclama: devuelve el día de la racha y el premio, o nil si hoy ya se reclamó. Cambia state.
function DailyReward.claim(state: State, today: number): (number?, Reward?)
	if not DailyReward.canClaim(state, today) then
		return nil, nil
	end
	local day = DailyReward.nextDay(state, today)
	state.LastDay = today
	state.Streak = day
	return day, Config.DailyReward.Days[day] :: Reward
end

-- Lee el estado guardado (o uno nuevo si no es válido).
function DailyReward.clean(raw: any): State
	if type(raw) == "table" and type(raw.LastDay) == "number" and type(raw.Streak) == "number" then
		return { LastDay = math.floor(raw.LastDay), Streak = math.clamp(math.floor(raw.Streak), 0, #Config.DailyReward.Days) }
	end
	return DailyReward.newState()
end

return DailyReward
