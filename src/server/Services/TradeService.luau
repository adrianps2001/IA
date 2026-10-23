--!strict
-- Intercambio seguro de criaturas entre dos jugadores del mismo servidor (GDD 9).
-- El estado y las reglas están en Trade.luau (doble confirmación). Aquí: peticiones,
-- vistas para la interfaz y el cambio final, que es atómico. Los dos perfiles están
-- cargados en este servidor con su bloqueo de sesión (DataService), se modifican a la vez
-- sin esperas entre medias y se guardan enseguida.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Creature = require(Shared.Creature)
local PlayerData = require(Shared.PlayerData)
local Rarity = require(Shared.Rarity)
local Remotes = require(Shared.Remotes)
local Trade = require(Shared.Trade)

local AnnouncementService = require(script.Parent.AnnouncementService)
local DataService = require(script.Parent.DataService)
local NestService = require(script.Parent.NestService)

local TradeService = {}

type Session = { State: Trade.State, A: Player, B: Player }

local sessions: { [Player]: Session } = {}
local requests: { [Player]: { From: Player, At: number } } = {}

local function keyOf(player: Player): string
	return tostring(player.UserId)
end

local function describe(profile: PlayerData.Profile, ids: { string }): ({ any }, number)
	local list, creatures = {}, {}
	for _, id in ids do
		local creature = PlayerData.findCreature(profile, id)
		if creature then
			table.insert(creatures, creature)
			table.insert(list, {
				Id = creature.Id,
				Name = Creature.name(creature),
				Rarity = creature.Rarity,
				RarityName = Rarity.Info[creature.Rarity].DisplayName,
				Income = Creature.baseIncome(creature),
			})
		end
	end
	return list, Trade.value(creatures)
end

local function push(session: Session)
	local state = session.State
	local profileA, profileB = DataService.get(session.A), DataService.get(session.B)
	if not profileA or not profileB then
		return
	end
	local offerA, valueA = describe(profileA, state.Offers.A)
	local offerB, valueB = describe(profileB, state.Offers.B)
	local confirmAt = if state.ReadyAt then workspace:GetServerTimeNow() + math.max(0, state.ReadyAt + Config.Trade.ConfirmDelay - os.clock()) else nil
	for _, side in { "A", "B" } :: { Trade.Side } do
		local me = if side == "A" then session.A else session.B
		local them = if side == "A" then session.B else session.A
		local other: Trade.Side = if side == "A" then "B" else "A"
		Remotes.event("TradeUpdated"):FireClient(me, {
			Partner = them.DisplayName,
			Mine = if side == "A" then offerA else offerB,
			Theirs = if side == "A" then offerB else offerA,
			MyValue = if side == "A" then valueA else valueB,
			TheirValue = if side == "A" then valueB else valueA,
			Ready = { Me = state.Ready[side], Them = state.Ready[other] },
			Confirmed = { Me = state.Confirmed[side], Them = state.Confirmed[other] },
			ConfirmAt = confirmAt,
			MaxItems = Config.Trade.MaxItems,
		})
	end
end

local function close(session: Session, reason: string?)
	for _, player in { session.A, session.B } do
		if sessions[player] == session then
			sessions[player] = nil
			if player.Parent then
				Remotes.event("TradeUpdated"):FireClient(player, nil)
				if reason then
					AnnouncementService.player(player, reason)
				end
			end
		end
	end
end

local function names(list: { Creature.Creature }, ids: { string }): { string }
	local out = {}
	for _, id in ids do
		for _, creature in list do
			if creature.Id == id then
				table.insert(out, string.format("%s (%s)", Creature.name(creature), Rarity.Info[creature.Rarity].DisplayName))
			end
		end
	end
	return out
end

local function record(profile: PlayerData.Profile, with: Player, gave: { string }, got: { string })
	table.insert(profile.Trades, { With = with.UserId, WithName = with.DisplayName, Gave = gave, Got = got, At = os.time() })
	while #profile.Trades > Config.Trade.HistorySize do
		table.remove(profile.Trades, 1)
	end
end

-- El cambio. Sin yields desde que se leen los perfiles hasta que se escriben.
local function execute(session: Session)
	local a, b = session.A, session.B
	local profileA, profileB = DataService.get(a), DataService.get(b)
	if not profileA or not profileB or not a.Parent or not b.Parent then
		close(session, "El intercambio se ha cancelado.")
		return
	end
	local state = session.State
	local gaveA = names(profileA.Creatures, state.Offers.A)
	local gaveB = names(profileB.Creatures, state.Offers.B)
	local ok, newA, newB = Trade.apply(state, profileA.Creatures, profileB.Creatures)
	if not ok then
		close(session, "El intercambio se ha cancelado: alguna criatura ya no está disponible.")
		return
	end
	profileA.Creatures = newA
	profileB.Creatures = newB
	record(profileA, b, gaveA, gaveB)
	record(profileB, a, gaveB, gaveA)
	DataService.addStat(a, "Trades", 1)
	DataService.addStat(b, "Trades", 1)
	DataService.markChanged(a)
	DataService.markChanged(b)
	close(session, nil)
	-- refreshDisplay también quita de las favoritas lo que se ha ido en el intercambio.
	NestService.refreshDisplay(a)
	NestService.refreshDisplay(b)
	AnnouncementService.player(a, "🤝 Intercambio completado con " .. b.DisplayName, "quest")
	AnnouncementService.player(b, "🤝 Intercambio completado con " .. a.DisplayName, "quest")
	-- Guardado inmediato de los dos: si el servidor cae, ninguno pierde ni duplica nada.
	task.spawn(DataService.saveNow, a)
	task.spawn(DataService.saveNow, b)
end

local function request(player: Player, userId: any)
	local target = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	if not target or target == player or not DataService.get(player) or not DataService.get(target) then
		return
	end
	-- GDD v3: se intercambia en el lobby, no en mitad de una partida.
	if player:GetAttribute("InMatch") == true or target:GetAttribute("InMatch") == true then
		AnnouncementService.player(player, "🏡 Los intercambios se hacen en el lobby.")
		return
	end
	if sessions[player] or sessions[target] then
		AnnouncementService.player(player, "Uno de los dos ya está intercambiando.")
		return
	end
	requests[target] = { From = player, At = os.clock() }
	Remotes.event("TradeRequested"):FireClient(target, player.UserId, player.DisplayName)
	AnnouncementService.player(player, "Petición de intercambio enviada a " .. target.DisplayName)
end

local function respond(player: Player, fromUserId: any, accept: any)
	local pending = requests[player]
	if not pending or pending.From.UserId ~= fromUserId or os.clock() - pending.At > Config.Trade.RequestTimeout then
		return
	end
	requests[player] = nil
	local from = pending.From
	if accept ~= true or not from.Parent then
		AnnouncementService.player(from, player.DisplayName .. " ha rechazado el intercambio.")
		return
	end
	if sessions[player] or sessions[from] then
		return
	end
	local session: Session = { State = Trade.new(keyOf(from), keyOf(player)), A = from, B = player }
	sessions[from] = session
	sessions[player] = session
	push(session)
end

local function sideOf(player: Player): (Session?, Trade.Side?)
	local session = sessions[player]
	if not session then
		return nil, nil
	end
	return session, Trade.sideOf(session.State, keyOf(player))
end

local function setOffer(player: Player, ids: any)
	local session, side = sideOf(player)
	local profile = DataService.get(player)
	if not session or not side or not profile or type(ids) ~= "table" then
		return
	end
	local clean = {}
	for _, id in ids do
		if type(id) == "string" then
			table.insert(clean, id)
		end
	end
	Trade.setOffer(session.State, side, clean, function(id)
		return PlayerData.findCreature(profile, id) ~= nil
	end)
	push(session)
end

local function ready(player: Player)
	local session, side = sideOf(player)
	if session and side and Trade.setReady(session.State, side, os.clock()) then
		push(session)
		if session.State.ReadyAt then
			-- Avisar a los dos cuando ya se puede confirmar.
			local version = session.State.Version
			task.delay(Config.Trade.ConfirmDelay + 0.05, function()
				if sessions[player] == session and session.State.Version == version then
					push(session)
				end
			end)
		end
	end
end

local function confirm(player: Player)
	local session, side = sideOf(player)
	if not session or not side then
		return
	end
	if Trade.confirm(session.State, side, os.clock()) then
		execute(session)
	else
		push(session)
	end
end

local function cancel(player: Player)
	local session = sessions[player]
	if session then
		close(session, player.DisplayName .. " ha cancelado el intercambio.")
	end
end

function TradeService.isTrading(player: Player): boolean
	return sessions[player] ~= nil
end

function TradeService.init() end

function TradeService.start()
	Remotes.event("TradeRequest").OnServerEvent:Connect(request)
	Remotes.event("TradeRespond").OnServerEvent:Connect(respond)
	Remotes.event("TradeSetOffer").OnServerEvent:Connect(setOffer)
	Remotes.event("TradeReady").OnServerEvent:Connect(ready)
	Remotes.event("TradeConfirm").OnServerEvent:Connect(confirm)
	Remotes.event("TradeCancel").OnServerEvent:Connect(cancel)
	Players.PlayerRemoving:Connect(function(player)
		cancel(player)
		requests[player] = nil
	end)
end

return TradeService
