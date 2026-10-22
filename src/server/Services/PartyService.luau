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

function PartyService.init() end

function PartyService.start()
	Remotes.event("PartyInvite").OnServerEvent:Connect(invite)
	Remotes.event("PartyRespond").OnServerEvent:Connect(respond)
	Remotes.event("PartyLeave").OnServerEvent:Connect(leave)
	Players.PlayerRemoving:Connect(function(player)
		leave(player)
		invites[player] = nil
		friendCache[player] = nil
	end)
end

return PartyService
