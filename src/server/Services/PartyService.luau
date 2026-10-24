--!strict
-- Bandada (GDD 9): grupos de hasta 4 jugadores del mismo servidor que duran entre rondas.
-- Comparten una parte del Calor depositado (HeatService llama a shareHeat), se ven a
-- través de las paredes (el cliente lee el atributo PartyId) y, si hay un amigo de Roblox
-- en el grupo, ganan +10 % de Polvo de cáscara (RoundService llama a dustMultiplier).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)

local AnnouncementService = require(script.Parent.AnnouncementService)

local PartyService = {}

type Party = { Id: string, Members: { Player } }

local parties: { [string]: Party } = {}
local partyOf: { [Player]: Party } = {}
local invites: { [Player]: { From: Player, At: number } } = {}
local friendCache: { [Player]: { [number]: boolean } } = {}

local function setAttribute(party: Party?, player: Player)
	player:SetAttribute("PartyId", if party then party.Id else nil)
end

local function notifyMembers(party: Party, text: string)
	for _, member in party.Members do
		AnnouncementService.player(member, text, "quest")
	end
end

-- Miembros de la Bandada del jugador (sin él), solo los que siguen en el servidor.
function PartyService.membersOf(player: Player): { Player }
	local party = partyOf[player]
	local list = {}
	if party then
		for _, member in party.Members do
			if member ~= player and member.Parent then
				table.insert(list, member)
			end
		end
	end
	return list
end

local function isFriend(player: Player, other: Player): boolean
	local cache = friendCache[player]
	if not cache then
		cache = {}
		friendCache[player] = cache
	end
	local known = cache[other.UserId]
	if known == nil then
		-- IsFriendsWith hace una petición web: se pregunta una vez y se guarda.
		local ok, result = pcall(function()
			return player:IsFriendsWithAsync(other.UserId)
		end)
		known = ok and result == true
		cache[other.UserId] = known
	end
	return known
end

-- Multiplicador del polvo de consuelo: +10 % si hay un amigo de Roblox en la Bandada.
function PartyService.dustMultiplier(player: Player): number
	for _, member in PartyService.membersOf(player) do
		if isFriend(player, member) then
			return 1 + Config.Party.FriendDustBonus
		end
	end
	return 1
end

-- Reparte la Afinidad de un depósito. Devuelve lo que se queda quien deposita y la lista
-- de {jugador, cantidad} para el resto del grupo.
function PartyService.shareHeat(player: Player, amount: number): (number, { { Player: Player, Amount: number } })
	local others = PartyService.membersOf(player)
	local keep, each = Economy.partyShare(amount, #others)
	local shares = {}
	if each > 0 then
		for _, member in others do
			table.insert(shares, { Player = member, Amount = each })
		end
	end
	return keep, shares
end

local function leave(player: Player)
	local party = partyOf[player]
	if not party then
		return
	end
	partyOf[player] = nil
	local index = table.find(party.Members, player)
	if index then
		table.remove(party.Members, index)
	end
	if player.Parent then
		setAttribute(nil, player)
	end
	if #party.Members <= 1 then
		-- Una Bandada de uno no tiene sentido: se disuelve.
		for _, member in party.Members do
			partyOf[member] = nil
			setAttribute(nil, member)
			AnnouncementService.player(member, "Tu Bandada se ha disuelto.")
		end
		parties[party.Id] = nil
	else
		notifyMembers(party, string.format("%s ha dejado la Bandada.", player.DisplayName))
	end
end

local function invite(player: Player, userId: any)
	local target = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	if not target or target == player then
		return
	end
	-- GDD v3: las Bandadas se forman en el lobby (luego entran juntas a la partida).
	if player:GetAttribute("InMatch") == true or target:GetAttribute("InMatch") == true then
		AnnouncementService.player(player, "🏡 Las Bandadas se forman en el lobby.")
		return
	end
	local party = partyOf[player]
	if party and #party.Members >= Config.Party.MaxSize then
		AnnouncementService.player(player, "Tu Bandada está completa.")
		return
	end
	if partyOf[target] then
		AnnouncementService.player(player, target.DisplayName .. " ya está en una Bandada.")
		return
	end
	invites[target] = { From = player, At = os.clock() }
	Remotes.event("PartyInvited"):FireClient(target, player.UserId, player.DisplayName)
	AnnouncementService.player(player, "Invitación enviada a " .. target.DisplayName)
end

local function respond(player: Player, fromUserId: any, accept: any)
	local pending = invites[player]
	if not pending or pending.From.UserId ~= fromUserId or os.clock() - pending.At > Config.Party.InviteTimeout then
		return
	end
	invites[player] = nil
	local from = pending.From
	if accept ~= true or not from.Parent then
		AnnouncementService.player(from, player.DisplayName .. " ha rechazado la invitación.")
		return
	end
	if partyOf[player] then
		return
	end
	local party: Party? = partyOf[from]
	if not party then
		local created: Party = { Id = HttpService:GenerateGUID(false), Members = { from :: Player } }
		parties[created.Id] = created
		partyOf[from] = created
		setAttribute(created, from)
		party = created
	end
	assert(party)
	if #party.Members >= Config.Party.MaxSize then
		AnnouncementService.player(player, "Esa Bandada ya está completa.")
		return
	end
	table.insert(party.Members, player)
	partyOf[player] = party
	setAttribute(party, player)
	notifyMembers(party, string.format("🐦 %s se ha unido a la Bandada (%d/%d).", player.DisplayName, #party.Members, Config.Party.MaxSize))
	-- Pregunta ya quién es amigo de quién, para no esperar a la web al repartir premios.
	for _, member in party.Members do
		if member ~= player then
			task.spawn(isFriend, player, member)
			task.spawn(isFriend, member, player)
		end
	end
end

-- Bandadas al cambiar de servidor (GDD v3): se mandan en los datos del teletransporte y se
-- rehacen al llegar. groupsOf da los UserId de cada Bandada entre esos jugadores.
function PartyService.groupsOf(players: { Player }): { { number } }
	local groups: { { number } } = {}
	local seen: { [Party]: boolean } = {}
	for _, player in players do
		local party = partyOf[player]
		if party and not seen[party] then
			seen[party] = true
			local ids = {}
			for _, member in party.Members do
				if table.find(players, member) then
					table.insert(ids, member.UserId)
				end
			end
			if #ids >= 2 then
				table.insert(groups, ids)
			end
		end
	end
	return groups
end

local pendingGroups: { { number } } = {}

-- Rehace las Bandadas en cuanto hay al menos dos de sus miembros en este servidor. Se puede
-- llamar cada vez que llega alguien con los mismos grupos (no los duplica).
function PartyService.restore(groups: any)
	if type(groups) ~= "table" then
		return
	end
	for _, group in groups do
		if type(group) == "table" and #group <= Config.Party.MaxSize then
			local known = false
			for _, pending in pendingGroups do
				if pending[1] == group[1] then
					known = true
				end
			end
			if not known then
				table.insert(pendingGroups, group)
			end
		end
	end
	for _, group in pendingGroups do
		local present: { Player } = {}
		for _, id in group do
			local member = if type(id) == "number" then Players:GetPlayerByUserId(id) else nil
			if member then
				table.insert(present, member)
			end
		end
		if #present >= 2 then
			local party: Party? = nil
			for _, member in present do
				party = party or partyOf[member]
			end
			if not party then
				local created: Party = { Id = HttpService:GenerateGUID(false), Members = {} }
				parties[created.Id] = created
				party = created
			end
			assert(party)
			for _, member in present do
				if not partyOf[member] and #party.Members < Config.Party.MaxSize then
					table.insert(party.Members, member)
					partyOf[member] = party
					setAttribute(party, member)
				end
			end
		end
	end
end

function PartyService.init() end

function PartyService.start()
	Remotes.onServer("PartyInvite", invite)
	Remotes.onServer("PartyRespond", respond)
	Remotes.onServer("PartyLeave", leave)
	Players.PlayerRemoving:Connect(function(player)
		leave(player)
		invites[player] = nil
		friendCache[player] = nil
	end)
end

return PartyService
