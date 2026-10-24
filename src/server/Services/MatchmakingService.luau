--!strict
-- Emparejamiento en el lobby (GDD v3). Pisar el círculo del portal o pulsar "Jugar" te mete
-- en la cola (con tu Bandada, que nunca se separa). La partida sale:
-- * enseguida con TargetPlayers;
-- * con MinPlayers tras FillSeconds esperando a más;
-- * con los que haya tras SoloSeconds (los zorros del bosque rellenan las partidas pequeñas).
-- Después de una cuenta atrás, en el lobby real se reserva un servidor del lugar de partidas
-- y se teletransporta a todos juntos; en el modo combinado la partida se juega aquí mismo.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Place = require(Shared.Place)
local Remotes = require(Shared.Remotes)
local RoundState = require(Shared.RoundState)

local AnnouncementService = require(script.Parent.AnnouncementService)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)
local MatchService = require(script.Parent.MatchService)
local PartyService = require(script.Parent.PartyService)

local MatchmakingService = {}

type Group = { Members: { Player }, JoinedAt: number }

local queue: { Group } = {}
local launchAt: number? = nil
local launching = false
local forced = false -- depuración: salir ya con los que haya

local function groupOf(player: Player): (Group?, number?)
	for index, group in queue do
		if table.find(group.Members, player) then
			return group, index
		end
	end
	return nil, nil
end

local function count(): number
	local n = 0
	for _, group in queue do
		n += #group.Members
	end
	return n
end

local function canQueue(player: Player): boolean
	return player.Parent ~= nil and DataService.get(player) ~= nil and not MatchService.inMatch(player)
end

local function publish()
	local n = count()
	RoundState.set("QueueCount", n)
	RoundState.set("QueueLaunchAt", launchAt or 0)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("Queued", groupOf(player) ~= nil)
	end
	local lobby = MapService.Lobby
	if lobby then
		local busy = Place.kind() == "Combined" and MatchService.isRunning()
		lobby.QueueLabel.Text = if n == 0
			then "⚔️ ¡A jugar!\nPisa el círculo"
			elseif launchAt then string.format("⚔️ ¡Sale la partida!\n%d jugadores · %d s", n, math.max(0, math.ceil(launchAt - os.clock())))
			elseif busy then string.format("⚔️ %d en cola\nPartida en curso…", n)
			else string.format("⚔️ %d en cola\nEsperando a más jugadores", n)
	end
end

function MatchmakingService.join(player: Player)
	if not canQueue(player) or groupOf(player) then
		return
	end
	-- La Bandada entra entera (los que estén libres en el lobby).
	local members = { player }
	for _, member in PartyService.membersOf(player) do
		if canQueue(member) and not groupOf(member) then
			table.insert(members, member)
		end
	end
	table.insert(queue, { Members = members, JoinedAt = os.clock() })
	for _, member in members do
		AnnouncementService.player(member, if #members > 1 then "⚔️ Tu Bandada está en la cola." else "⚔️ Estás en la cola. ¡Sales enseguida!")
	end
	publish()
end

function MatchmakingService.leave(player: Player)
	local group, index = groupOf(player)
	if not group or not index then
		return
	end
	table.remove(group.Members, table.find(group.Members, player) :: number)
	if #group.Members == 0 then
		table.remove(queue, index)
	end
	if count() == 0 then
		launchAt = nil
	end
	publish()
end

-- Grupos que caben en una partida, por orden de llegada (sin partir ninguna Bandada).
local function pickGroups(): { Player }
	local players: { Player } = {}
	local i = 1
	while i <= #queue do
		local group = queue[i]
		if #players + #group.Members <= Config.Matchmaking.MaxPlayers then
			for _, member in group.Members do
				table.insert(players, member)
			end
			table.remove(queue, i)
		else
			i += 1
		end
	end
	return players
end

local function launch()
	launching = true
	forced = false
	launchAt = nil
	local players = pickGroups()
	publish()
	if #players == 0 then
		launching = false
		return
	end
	if Place.kind() == "Combined" then
		if not MatchService.startLocal(players) then
			-- Había una partida en marcha: vuelven a la cola en el mismo orden.
			table.insert(queue, 1, { Members = players, JoinedAt = os.clock() })
		end
		launching = false
		publish()
		return
	end
	for _, player in players do
		AnnouncementService.player(player, "🚀 ¡Partida encontrada! Viajando a la arena…", "threshold")
	end
	local ok = MatchService.teleport(players, Config.Places.Match, {
		Expected = #players,
		Parties = PartyService.groupsOf(players),
	}, true)
	if not ok then
		for _, player in players do
			AnnouncementService.player(player, "No se pudo crear la partida. Vuelves a la cola.")
		end
		table.insert(queue, 1, { Members = players, JoinedAt = os.clock() })
	end
	launching = false
	publish()
end

local function tick()
	-- Fuera quien se fue, quien ya está jugando o quien no ha cargado.
	for index = #queue, 1, -1 do
		local group = queue[index]
		for k = #group.Members, 1, -1 do
			if not canQueue(group.Members[k]) then
				table.remove(group.Members, k)
			end
		end
		if #group.Members == 0 then
			table.remove(queue, index)
		end
	end
	local n = count()
	if n == 0 or launching then
		launchAt = nil
		publish()
		return
	end
	local busy = Place.kind() == "Combined" and MatchService.isRunning()
	local waited = os.clock() - queue[1].JoinedAt
	local mm = Config.Matchmaking
	local ready = n >= mm.TargetPlayers or (n >= mm.MinPlayers and waited >= mm.FillSeconds) or waited >= mm.SoloSeconds
	-- En Studio no hace falta esperar tanto: sale en cuanto están todos los de la prueba en
	-- la cola o tras unos segundos.
	if Place.kind() == "Combined" and game:GetService("RunService"):IsStudio() then
		local free = 0
		for _, player in Players:GetPlayers() do
			if canQueue(player) then
				free += 1
			end
		end
		ready = n >= free or waited >= 8
	end
	if forced then
		ready = true
	end
	if busy or not ready then
		launchAt = nil
	elseif not launchAt then
		launchAt = os.clock() + (if Place.kind() == "Combined" then math.min(mm.Countdown, 3) else mm.Countdown)
	elseif os.clock() >= launchAt then
		task.spawn(launch)
	end
	publish()
end

-- Depuración (solo Studio): lanzar la partida ya, sin esperar a más jugadores.
function MatchmakingService.forceLaunch()
	forced = true
end

function MatchmakingService.init()
	RoundState.set("QueueCount", 0)
	RoundState.set("QueueLaunchAt", 0)
end

function MatchmakingService.start()
	if not Place.hasLobby() then
		return
	end
	MatchService.onRequeue(MatchmakingService.join)
	Remotes.onServer("RequestQueue", function(player, value)
		if value == true then
			MatchmakingService.join(player)
		else
			MatchmakingService.leave(player)
		end
	end)
	Remotes.onServer("SetAutoRequeue", function(player, value)
		player:SetAttribute("AutoRequeue", value == true)
	end)
	local lobby = MapService.Lobby
	if lobby then
		lobby.QueuePad.Touched:Connect(function(hit)
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if player and not groupOf(player) then
				MatchmakingService.join(player)
			end
		end)
	end

	local function onPlayer(player: Player)
		player:SetAttribute("AutoRequeue", true)
		-- Vuelve de una partida: rehacer las Bandadas y, si lo pidió, directo a la cola.
		local ok, join = pcall(function()
			return player:GetJoinData()
		end)
		local data: any = if ok and type(join) == "table" then (join :: any).TeleportData else nil
		if type(data) == "table" and data.FromMatch then
			PartyService.restore(data.Parties)
			if type(data.Requeue) == "table" and table.find(data.Requeue, player.UserId) then
				task.spawn(function()
					DataService.await(player)
					task.wait(3) -- un momento para ver el nido y las criaturas nuevas
					MatchmakingService.join(player)
				end)
			end
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(MatchmakingService.leave)

	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(tick)
			if not ok then
				warn("[MatchmakingService] " .. tostring(err))
			end
		end
	end)
end

return MatchmakingService
