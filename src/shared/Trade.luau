--!strict
-- Intercambio seguro de criaturas (GDD 9): estado de una ventana de intercambio entre dos
-- jugadores, sin Roblox. TradeService la usa en el servidor y los tests la prueban.
--
-- Doble confirmación contra estafas:
--   1. Cada uno elige lo que da. Cualquier cambio en cualquiera de las dos ofertas quita
--      el "Listo" de los dos.
--   2. Con los dos "Listos", hay que esperar ConfirmDelay segundos y los dos pulsan
--      "Confirmar". Solo entonces se hace el cambio, y el servidor vuelve a comprobar que
--      cada uno sigue teniendo lo que ofrece.

local Config = require("./Config")
local Creature = require("./Creature")

export type Side = "A" | "B"

export type State = {
	A: string, -- clave del jugador A (UserId en texto)
	B: string,
	Offers: { [string]: { string } }, -- por lado ("A" / "B"): ids de criaturas
	Ready: { [string]: boolean },
	Confirmed: { [string]: boolean },
	ReadyAt: number?, -- cuándo quedaron los dos listos
	Version: number, -- sube con cada cambio de oferta
}

local Trade = {}

function Trade.new(a: string, b: string): State
	return {
		A = a,
		B = b,
		Offers = { A = {}, B = {} },
		Ready = { A = false, B = false },
		Confirmed = { A = false, B = false },
		ReadyAt = nil,
		Version = 0,
	}
end

function Trade.sideOf(state: State, key: string): Side?
	if key == state.A then
		return "A"
	elseif key == state.B then
		return "B"
	end
	return nil
end

local function resetConfirmations(state: State)
	state.Ready.A, state.Ready.B = false, false
	state.Confirmed.A, state.Confirmed.B = false, false
	state.ReadyAt = nil
end

-- Cambia la oferta de un lado. `owned` dice si ese jugador tiene la criatura y si se puede
-- intercambiar. Devuelve false si la oferta no es válida (y no cambia nada).
function Trade.setOffer(state: State, side: Side, ids: { string }, owned: (string) -> boolean): boolean
	if #ids > Config.Trade.MaxItems then
		return false
	end
	local seen = {}
	for _, id in ids do
		if type(id) ~= "string" or seen[id] or not owned(id) then
			return false
		end
		seen[id] = true
	end
	state.Offers[side] = table.clone(ids)
	state.Version += 1
	resetConfirmations(state)
	return true
end

-- Paso 1. Hace falta que alguien ofrezca algo (no se puede "intercambiar" nada por nada).
function Trade.setReady(state: State, side: Side, now: number): boolean
	if #state.Offers.A + #state.Offers.B == 0 then
		return false
	end
	state.Ready[side] = true
	if state.Ready.A and state.Ready.B and not state.ReadyAt then
		state.ReadyAt = now
	end
	return true
end

-- Paso 2. Devuelve true cuando los dos han confirmado: hay que ejecutar el intercambio.
function Trade.confirm(state: State, side: Side, now: number): boolean
	if not (state.Ready.A and state.Ready.B) or not state.ReadyAt then
		return false
	end
	if now - state.ReadyAt < Config.Trade.ConfirmDelay then
		return false
	end
	state.Confirmed[side] = true
	return state.Confirmed.A and state.Confirmed.B
end

-- Valor estimado de una oferta (Monedas por segundo sin multiplicadores), visible para los
-- dos jugadores, para que nadie acepte sin saber lo que vale.
function Trade.value(creatures: { Creature.Creature }): number
	local total = 0
	for _, creature in creatures do
		total += Creature.baseIncome(creature)
	end
	return total
end

-- Ejecuta el cambio sobre las dos listas de criaturas. Comprueba otra vez que cada lado
-- sigue teniendo lo que ofrece; si algo falta, no cambia nada y devuelve false.
function Trade.apply(state: State, creaturesA: { Creature.Creature }, creaturesB: { Creature.Creature }): (boolean, { Creature.Creature }, { Creature.Creature })
	local function take(list: { Creature.Creature }, ids: { string }): ({ Creature.Creature }?, { Creature.Creature })
		local wanted = {}
		for _, id in ids do
			wanted[id] = true
		end
		local taken, kept = {}, {}
		for _, creature in list do
			if wanted[creature.Id] then
				table.insert(taken, creature)
				wanted[creature.Id] = nil
			else
				table.insert(kept, creature)
			end
		end
		if next(wanted) ~= nil then
			return nil, list -- falta alguna
		end
		return taken, kept
	end
	local fromA, keptA = take(creaturesA, state.Offers.A)
	local fromB, keptB = take(creaturesB, state.Offers.B)
	if not fromA or not fromB then
		return false, creaturesA, creaturesB
	end
	for _, creature in fromB do
		table.insert(keptA, creature)
	end
	for _, creature in fromA do
		table.insert(keptB, creature)
	end
	return true, keptA, keptB
end

return Trade
