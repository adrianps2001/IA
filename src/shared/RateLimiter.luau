--!strict
-- Cubo de fichas (v3.1): cada clave (jugador + remoto) puede hacer `capacity` llamadas seguidas
-- y recupera `refill` fichas por segundo. Sirve para que un tramposo no pueda saturar el
-- servidor llamando a un remoto miles de veces. Sin Roblox: se prueba en tests/run.luau.

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type Bucket = { Tokens: number, At: number }
export type RateLimiter = typeof(setmetatable({} :: { Capacity: number, Refill: number, Buckets: { [string]: Bucket } }, RateLimiter))

function RateLimiter.new(capacity: number, refillPerSecond: number): RateLimiter
	return setmetatable({ Capacity = capacity, Refill = refillPerSecond, Buckets = {} }, RateLimiter)
end

-- ¿Se permite una llamada más de `key` en el instante `now` (segundos)? Si sí, gasta una ficha.
function RateLimiter.allow(self: RateLimiter, key: string, now: number): boolean
	local bucket = self.Buckets[key]
	if not bucket then
		bucket = { Tokens = self.Capacity, At = now }
		self.Buckets[key] = bucket
	end
	bucket.Tokens = math.min(self.Capacity, bucket.Tokens + math.max(now - bucket.At, 0) * self.Refill)
	bucket.At = now
	if bucket.Tokens < 1 then
		return false
	end
	bucket.Tokens -= 1
	return true
end

-- Olvida las claves que empiezan por `prefix` (al salir un jugador).
function RateLimiter.forget(self: RateLimiter, prefix: string)
	for key in self.Buckets do
		if string.sub(key, 1, #prefix) == prefix then
			self.Buckets[key] = nil
		end
	end
end

return RateLimiter
