--!strict
-- Reparto de premios al final de la ronda (GDD 5.4 y 5.5), sin dependencias de Roblox.
-- Lo usan RoundService y el simulador de bots. Desde el GDD v2 puede haber varias criaturas
-- por ronda: cada una es un "resultado" con su ganador, sus aliados y su elegido.

local Config = require("./Config")
local Economy = require("./Economy")

export type Participant = {
	Key: string,
	Affinity: number,
	StealAttempts: number,
	Active: boolean?, -- false = no hizo nada en la ronda (AFK): sin consuelo
}

-- Lo que pasó con una criatura de la ronda.
export type Outcome = {
	Winner: string?, -- nil si escapó
	Partners: { string }, -- aliados (tratos) del ganador
	Chosen: string?, -- a quién eligió el huevo para esta criatura
}

export type Reward = {
	Dust: number,
	Won: { number }, -- índices de las criaturas (Outcome) que se lleva
	Copies: { number }, -- criaturas de las que recibe una copia común (aliado del ganador)
	ChosenEgg: boolean, -- fue elegido y perdió su criatura: Huevo del Elegido
}

local Rewards = {}

local function isActive(p: Participant): boolean
	return p.Active ~= false or not Config.Election.RequireActivity
end

function Rewards.compute(participants: { Participant }, outcomes: { Outcome }): { [string]: Reward }
	local result: { [string]: Reward } = {}
	local byKey: { [string]: Participant } = {}
	for _, p in participants do
		byKey[p.Key] = p
		result[p.Key] = {
			Dust = if isActive(p) then Economy.consolationDust(p.Affinity, p.StealAttempts) else 0,
			Won = {},
			Copies = {},
			ChosenEgg = false,
		}
	end

	for index, outcome in outcomes do
		local winner = outcome.Winner
		local winnerReward = if winner then result[winner] else nil
		if winner and winnerReward then
			table.insert(winnerReward.Won, index)
			-- El ganador cobra el bonus; sus aliados, una parte de su polvo y una copia.
			local p = byKey[winner]
			local winnerDust = Config.Consolation.WinnerBonusDust + Economy.consolationDust(p.Affinity, p.StealAttempts)
			winnerReward.Dust += Config.Consolation.WinnerBonusDust
			for _, partner in outcome.Partners do
				local reward = result[partner]
				if reward and partner ~= winner then
					reward.Dust += math.floor(winnerDust * Config.Deal.DustShare)
					table.insert(reward.Copies, index)
				end
			end
		end
		-- Ser elegido siempre tiene que sentirse bien, aunque te la roben.
		local chosen = outcome.Chosen
		local chosenReward = if chosen then result[chosen] else nil
		if chosen and chosenReward and chosen ~= winner then
			chosenReward.Dust += Config.Consolation.ChosenBonusDust
			chosenReward.ChosenEgg = chosenReward.ChosenEgg or Config.Consolation.ChosenEgg
		end
	end
	return result
end

return Rewards
