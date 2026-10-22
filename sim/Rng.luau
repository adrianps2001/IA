--!strict
-- Generador pseudoaleatorio con semilla (xorshift32). La misma semilla produce siempre la
-- misma simulación, así se pueden comparar cambios de Config con los mismos "dados".

local Rng = {}

export type Rng = () -> number

function Rng.new(seed: number): Rng
	local state = bit32.bor(math.floor(math.abs(seed)) % 4294967296, 1)
	-- Calentar el generador para que semillas parecidas den secuencias distintas.
	local function nextValue(): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		return state / 4294967296
	end
	for _ = 1, 16 do
		nextValue()
	end
	return nextValue
end

function Rng.int(rng: Rng, low: number, high: number): number
	return low + math.floor(rng() * (high - low + 1))
end

function Rng.range(rng: Rng, low: number, high: number): number
	return low + rng() * (high - low)
end

function Rng.shuffle<T>(rng: Rng, list: { T }): { T }
	for i = #list, 2, -1 do
		local j = math.floor(rng() * i) + 1
		list[i], list[j] = list[j], list[i]
	end
	return list
end

return Rng
