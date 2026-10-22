--!strict
-- Reparto de premios al final de la ronda (GDD 5.4 y 5.5), sin dependencias de Roblox.
-- Lo usan RoundService y el simulador de bots.

local Config = require("./Config")
local Economy = require("./Economy")

export type Participant = {
	Key: string,
	Affinity: number,
	StealAttempts: number,
}

export type Reward = {
	Dust: number,
	Creature: boolean, -- se lleva la criatura de la ronda
	Copy: boolean, -- recibe una copia común (aliado del ganador)
	ChosenEgg: boolean, -- fue el elegido y perdió la criatura: Huevo del Elegido
}

local Rewards = {}

-- winnerKey es nil si la criatura escapó. partnerKeys son los aliados del ganador.
-- chosenKey es a quien eligió el huevo: si no acaba ganando, recibe un premio de consolación
-- especial (ser elegido siempre tiene que sentirse bien, aunque te la roben).
function Rewards.compute(participants: { Participant }, winnerKey: string?, partnerKeys: { string }, chosenKey: string?): { [string]: Reward }
	local result: { [string]: Reward } = {}
	local winnerDust = 0
	for _, p in participants do
		if p.Key == winnerKey then
			winnerDust = Config.Consolation.WinnerBonusDust + Economy.consolationDust(p.Affinity, p.StealAttempts)
		end
	end

	for _, p in participants do
		local reward: Reward = { Dust = 0, Creature = false, Copy = false, ChosenEgg = false }
		if p.Key == winnerKey then
			reward.Dust = winnerDust
			reward.Creature = true
		else
			reward.Dust = Economy.consolationDust(p.Affinity, p.StealAttempts)
			if winnerKey and table.find(partnerKeys, p.Key) then
				reward.Dust += math.floor(winnerDust * Config.Deal.DustShare)
				reward.Copy = true
			end
			if p.Key == chosenKey then
				reward.Dust += Config.Consolation.ChosenBonusDust
				reward.ChosenEgg = Config.Consolation.ChosenEgg
			end
		end
		result[p.Key] = reward
	end
	return result
end

return Rewards
