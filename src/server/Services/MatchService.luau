--!strict
-- Partidas (GDD v3): quién juega la partida de este servidor y cómo se entra y se sale.
-- * Lugar "Match": juegan todos los que llegan. Se espera a los que vienen del lobby
--   (Config.Matchmaking.ArrivalTimeout), se juegan RoundsPerMatch rondas y todos vuelven
--   juntos al lobby.
-- * Modo "Combined" (Studio): el lobby y la arena comparten servidor. La partida empieza
--   cuando el emparejamiento la lanza (startLocal) y "teletransportar" es reaparecer en la
--   arena o en el lobby.
-- Los jugadores de la partida llevan el atributo InMatch (NestService los coloca y el
-- cliente cambia de interfaz).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Place = require(Shared.Place)
local RoundState = require(Shared.RoundState)

local AnnouncementService = require(script.Parent.AnnouncementService)
local DataService = require(script.Parent.DataService)
local PartyService = require(script.Parent.PartyService)

local MatchService = {}

local kind = Place.kind()
local participants: { [Player]: boolean } = {}
local running = false
local expected = 0
local firstArrival: number? = nil
-- El emparejamiento se apunta aquí para volver a meter en la cola a quien lo pidió.
local requeueCallback: ((Player) -> ())? = nil

function MatchService.kind(): Place.Kind
	return kind
end

function MatchService.inMatch(player: Player): boolean
	return participants[player] == true
end

-- Jugadores de la partida que siguen en el servidor.
function MatchService.players(): { Player }
	local list = {}
	for player in participants do
		if player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

function MatchService.isRunning(): boolean
	return running
end

function MatchService.onRequeue(callback: (Player) -> ())
	requeueCallback = callback
end

local function setInMatch(player: Player, value: boolean)
	participants[player] = if value then true else nil
	player:SetAttribute("InMatch", value)
end

-- Teletransporte con reintentos. reserved = servidor privado nuevo (una partida).
function MatchService.teleport(players: { Player }, placeId: number, data: { [string]: any }, reserved: boolean): boolean
	if #players == 0 then
		return true
	end
	-- Guardar antes de irse: el servidor de destino lee el perfil en cuanto el jugador llega
	-- (el bloqueo se suelta al salir de aquí; DataService del destino reintenta mientras tanto).
	for _, player in players do
		task.spawn(DataService.saveNow, player)
	end
	for attempt = 1, Config.Matchmaking.TeleportRetries do
		local ok, err = pcall(function()
			local options = Instance.new("TeleportOptions")
			if reserved then
				options.ReservedServerAccessCode = (TeleportService:ReserveServer(placeId))
			end
			options:SetTeleportData(data)
			TeleportService:TeleportAsync(placeId, players, options)
		end)
		if ok then
			return true
		end
		warn(string.format("[MatchService] Teletransporte fallido (intento %d): %s", attempt, tostring(err)))
		task.wait(2 * attempt)
	end
	return false
end

-- Modo combinado: el emparejamiento lanza una partida en este mismo servidor.
function MatchService.startLocal(group: { Player }): boolean
	if running or kind ~= "Combined" then
		return false
	end
	for _, player in group do
		if player.Parent then
			setInMatch(player, true)
		end
	end
	running = true
	return true
end

-- Espera a que haya partida (lo llama el bucle de rondas).
function MatchService.waitForStart()
	if kind == "Combined" then
		while not running or #MatchService.players() == 0 do
			running = running and #MatchService.players() > 0
			RoundState.set("Phase", "Waiting")
			RoundState.set("PhaseEndsAt", 0)
			task.wait(0.5)
		end
		return
	end
	-- Lugar de partida: esperar a los que vienen del lobby.
	while true do
		local loaded = 0
		for _, player in MatchService.players() do
			if DataService.get(player) then
				loaded += 1
			end
		end
		local arrived = firstArrival
		local waited = if arrived then os.clock() - arrived else 0
		local everyone = expected > 0 and loaded >= expected
		local studio = RunService:IsStudio() and loaded > 0
		if loaded > 0 and (everyone or studio or waited >= Config.Matchmaking.ArrivalTimeout) then
			running = true
			return
		end
		RoundState.set("Phase", "Waiting")
		RoundState.set("PhaseEndsAt", 0)
		task.wait(0.5)
	end
end

-- Fin de la partida: todos al lobby (o al lobby de este servidor en el modo combinado).
function MatchService.finish()
	running = false
	local players = MatchService.players()
	if kind == "Combined" then
		for _, player in players do
			setInMatch(player, false)
			local requeue = requeueCallback
			if player:GetAttribute("AutoRequeue") ~= false and requeue then
				requeue(player)
			end
		end
		return
	end
	if RunService:IsStudio() or Config.Places.Lobby == 0 then
		return -- probando el lugar de partida solo: se juega otra ronda con los mismos
	end
	local requeue = {}
	for _, player in players do
		if player:GetAttribute("AutoRequeue") ~= false then
			table.insert(requeue, player.UserId)
		end
	end
	AnnouncementService.match("🏡 ¡Fin de la partida! Volvéis al lobby…", "threshold")
	local ok = MatchService.teleport(players, Config.Places.Lobby, {
		FromMatch = true,
		Requeue = requeue,
		Parties = PartyService.groupsOf(players),
	}, false)
	if not ok then
		AnnouncementService.match("No se ha podido volver al lobby: jugamos otra ronda.", "info")
	end
end

local function onPlayer(player: Player)
	if kind ~= "Match" then
		player:SetAttribute("InMatch", false)
		return
	end
	-- Lugar de partida: todos juegan. Los datos del teletransporte dicen cuántos venían y
	-- quién iba en Bandada.
	setInMatch(player, true)
	firstArrival = firstArrival or os.clock()
	local ok, join = pcall(function()
		return player:GetJoinData()
	end)
	local data: any = if ok and type(join) == "table" then (join :: any).TeleportData else nil
	if type(data) == "table" then
		if type(data.Expected) == "number" then
			expected = math.max(expected, math.clamp(data.Expected, 1, Config.Matchmaking.MaxPlayers))
		end
		PartyService.restore(data.Parties)
	end
end

function MatchService.init() end

function MatchService.start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		participants[player] = nil
	end)
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		warn(string.format("[MatchService] %s no pudo teletransportarse: %s %s", player.Name, tostring(result), tostring(message)))
		AnnouncementService.player(player, "No se pudo cambiar de servidor. Inténtalo otra vez.")
	end)
end

return MatchService
