--!strict
-- Anti-trampas (v3.1, Config.AntiCheat):
-- * Movimiento: en tirolinas, toboganes y setas el cliente mueve a su personaje, así que un
--   tramposo podría volar o teletransportarse. Cada pocos segundos el servidor mira cuánto se
--   ha movido cada uno (MovementRules); si va más rápido de lo posible, lo devuelve a su última
--   posición buena y le suma un aviso. Con demasiados avisos seguidos, se le echa.
-- * Remotos: Remotes.onServer ya ignora a quien llama demasiado deprisa; aquí se cuentan esas
--   llamadas y se echa a quien no para (nadie llega a eso pulsando botones).
-- Los límites son generosos: es mejor dejar pasar una trampa leve que castigar a alguien con
-- mala conexión. Todo queda en la consola del servidor para revisarlo.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local MovementRules = require(Shared.MovementRules)
local Remotes = require(Shared.Remotes)

local AntiCheatService = {}

type Track = { Position: Vector3?, At: number, GraceUntil: number, Strikes: { number }, Dropped: { number } }

local tracks: { [Player]: Track } = {}

local function track(player: Player): Track
	local t = tracks[player]
	if not t then
		local fresh: Track = { Position = nil, At = 0, GraceUntil = 0, Strikes = {}, Dropped = {} }
		tracks[player] = fresh
		return fresh
	end
	return t
end

-- Para cuando el propio servidor mueve a alguien de golpe (reaparecer, viajar…).
function AntiCheatService.allowMove(player: Player, seconds: number?)
	local t = track(player)
	t.GraceUntil = math.max(t.GraceUntil, os.clock() + (seconds or Config.AntiCheat.GraceAfterSpawn))
	t.Position = nil
end

local function strike(player: Player, reason: string)
	local t = track(player)
	local now = os.clock()
	t.Strikes = MovementRules.recentStrikes(t.Strikes, now)
	table.insert(t.Strikes, now)
	warn(string.format("[AntiCheat] %s: %s (%d avisos)", player.Name, reason, #t.Strikes))
	if #t.Strikes >= Config.AntiCheat.KickAfterStrikes then
		player:Kick("Movimiento imposible detectado. Si es un error, vuelve a entrar.")
	end
end

local function checkPlayer(player: Player, now: number)
	local character = player.Character
	local t = track(player)
	if not character then
		t.Position = nil
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		t.Position = nil
		return
	end
	local position = root.Position
	if now < t.GraceUntil or not t.Position then
		t.Position, t.At = position, now
		return
	end
	local delta = position - (t.Position :: Vector3)
	local verdict = MovementRules.check(delta.X, delta.Y, delta.Z, now - t.At)
	if verdict == "ok" then
		t.Position, t.At = position, now
		return
	end
	-- Vuelta a la última posición buena (sin velocidad, para que no siga volando).
	local back = t.Position :: Vector3
	character:PivotTo(CFrame.new(back) * root.CFrame.Rotation)
	root.AssemblyLinearVelocity = Vector3.zero
	t.At = now
	strike(player, if verdict == "tooFast" then "demasiado rápido" else "sube demasiado deprisa")
end

function AntiCheatService.init() end

function AntiCheatService.start()
	Remotes.onDropped(function(player: Player, name: string)
		local t = track(player)
		local now = os.clock()
		table.insert(t.Dropped, now)
		if #t.Dropped % 50 == 0 then
			t.Dropped = MovementRules.recentStrikes(t.Dropped, now)
			warn(string.format("[AntiCheat] %s llama demasiado a %s (%d ignoradas)", player.Name, name, #t.Dropped))
			if #t.Dropped >= Config.AntiCheat.KickAfterDropped then
				player:Kick("Demasiadas peticiones al servidor.")
			end
		end
	end)

	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			AntiCheatService.allowMove(player)
		end)
		if player.Character then
			AntiCheatService.allowMove(player)
		end
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		tracks[player] = nil
		Remotes.forget(player)
	end)

	task.spawn(function()
		while true do
			task.wait(Config.AntiCheat.CheckEvery)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				checkPlayer(player, now)
			end
		end
	end)
end

return AntiCheatService
