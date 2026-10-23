--!strict
-- Ranking semanal de robos y salón de la fama (GDD 9 y 11). Los totales de cada semana van a
-- un OrderedDataStore propio ("Steals_W2909", "Likes_W2909"...), así el ranking se reinicia
-- solo cada lunes. Este servidor suma en local y envía cada FlushSeconds; luego lee el top.
-- Sin acceso a DataStore (Studio sin API Services) muestra solo lo de este servidor.
-- El cartel está junto al claro del huevo; los "me gusta" se dan en la entrada de cada nido.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Leaderboard = require(Shared.Leaderboard)

local AnnouncementService = require(script.Parent.AnnouncementService)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)
local NestService = require(script.Parent.NestService)

type Kind = "Steals" | "Likes"

local LeaderboardService = {}

local KINDS: { Kind } = { "Steals", "Likes" }

local week = ""
local pending: { [Kind]: { [number]: number } } = { Steals = {}, Likes = {} }
local offline: { [Kind]: { [number]: number } } = { Steals = {}, Likes = {} } -- totales locales si no hay DataStore
local unsent: { [Kind]: { [number]: number } } = { Steals = {}, Likes = {} } -- sumado aquí y aún no guardado
local tops: { [Kind]: { Leaderboard.Entry } } = { Steals = {}, Likes = {} }
local champion: Leaderboard.Entry? = nil -- ladrón número 1 de la semana pasada
local names: { [number]: string } = {}
local boardLabels: { [string]: TextLabel } = {}

local function storeFor(kind: Kind, key: string): OrderedDataStore?
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(kind .. "_" .. key)
	end)
	return if ok then store else nil
end

local function nameOf(userId: number): string
	local known = names[userId]
	if known then
		return known
	end
	local inGame = Players:GetPlayerByUserId(userId)
	if inGame then
		names[userId] = inGame.DisplayName
		return inGame.DisplayName
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if ok and type(result) == "string" then result else "#" .. userId
	names[userId] = name
	return name
end

local function readTop(store: OrderedDataStore, size: number): { Leaderboard.Entry }?
	local ok, result = pcall(function()
		local entries = {}
		local page = store:GetSortedAsync(false, size):GetCurrentPage()
		for _, item in page do
			local userId = tonumber(item.key)
			if userId then
				table.insert(entries, { UserId = userId, Value = item.value })
			end
		end
		return entries
	end)
	return if ok then result else nil
end

-- Cartel ----------------------------------------------------------------------------------

local function formatList(entries: { Leaderboard.Entry }, unit: string): string
	if #entries == 0 then
		return "Todavía nadie esta semana"
	end
	local lines = {}
	for index, entry in entries do
		table.insert(lines, string.format("%d. %s · %d %s", index, nameOf(entry.UserId), entry.Value, unit))
	end
	return table.concat(lines, "\n")
end

local function refreshBoard()
	if not boardLabels.Steals then
		return
	end
	boardLabels.Steals.Text = formatList(tops.Steals, "robos")
	boardLabels.Likes.Text = formatList(tops.Likes, "❤")
	local days = math.ceil(Leaderboard.secondsToReset(os.time()) / 86400)
	boardLabels.Footer.Text = string.format(
		"%s · se reinicia en %d día%s",
		if champion then string.format("👑 Campeón de la semana pasada: %s (%d robos)", nameOf(champion.UserId), champion.Value) else "👑 Sin campeón la semana pasada",
		days,
		if days == 1 then "" else "s"
	)
end

local function buildBoard()
	-- GDD v3: el cartel está en la plaza del lobby, mirando al portal.
	local lobby = MapService.Lobby
	if not lobby then
		return
	end
	local board = Instance.new("Part")
	board.Name = "Leaderboard"
	board.Anchored = true
	board.CanCollide = false
	board.CanQuery = false
	board.Size = Vector3.new(22, 12, 0.6)
	board.CFrame = lobby.BoardCFrame
	board.Color = Color3.fromRGB(45, 32, 28)
	board.Material = Enum.Material.Wood
	board.Parent = lobby.Folder
	for _, side in { -1, 1 } do
		local post = Instance.new("Part")
		post.Name = "Post"
		post.Anchored = true
		post.CanCollide = false
		post.Size = Vector3.new(0.8, 11, 0.8)
		post.CFrame = board.CFrame * CFrame.new(side * 10, -10.5, 0.4)
		post.Color = Color3.fromRGB(80, 55, 35)
		post.Material = Enum.Material.Wood
		post.Parent = board
	end

	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(1100, 600)
	surface.LightInfluence = 0
	surface.Parent = board
	local function label(name: string, position: UDim2, size: UDim2, text: string, color: Color3, alignment: Enum.TextXAlignment): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = position
		l.Size = size
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = color
		l.TextXAlignment = alignment
		l.TextYAlignment = Enum.TextYAlignment.Top
		l.Text = text
		l.Parent = surface
		return l
	end
	local gold = Color3.fromRGB(255, 205, 60)
	local white = Color3.fromRGB(255, 250, 240)
	label("StealsTitle", UDim2.fromScale(0.03, 0.03), UDim2.fromScale(0.45, 0.1), "🏆 Ladrones de la semana", gold, Enum.TextXAlignment.Center)
	label("LikesTitle", UDim2.fromScale(0.52, 0.03), UDim2.fromScale(0.45, 0.1), "🏡 Salón de la fama", gold, Enum.TextXAlignment.Center)
	boardLabels.Steals = label("Steals", UDim2.fromScale(0.03, 0.16), UDim2.fromScale(0.45, 0.68), "", white, Enum.TextXAlignment.Left)
	boardLabels.Likes = label("Likes", UDim2.fromScale(0.52, 0.16), UDim2.fromScale(0.45, 0.68), "", white, Enum.TextXAlignment.Left)
	boardLabels.Footer = label("Footer", UDim2.fromScale(0.03, 0.88), UDim2.fromScale(0.94, 0.09), "", gold, Enum.TextXAlignment.Center)
end

-- "Me gusta" en los nidos ---------------------------------------------------------------

local function like(liker: Player, index: number)
	local owner = NestService.ownerOf(index)
	local profile = DataService.get(liker)
	if not owner or not profile then
		return
	end
	local state = Leaderboard.rollLikes(profile.Likes, week)
	profile.Likes = state
	local ok, reason = Leaderboard.canLike(state, liker.UserId, owner.UserId)
	if not ok then
		AnnouncementService.player(liker, reason or "")
		return
	end
	table.insert(state.Given, owner.UserId)
	DataService.markChanged(liker)
	DataService.addStat(owner, "LikesReceived", 1)
	pending.Likes[owner.UserId] = (pending.Likes[owner.UserId] or 0) + 1
	AnnouncementService.player(liker, string.format("❤ Te gusta el nido de %s.", owner.DisplayName))
	AnnouncementService.player(owner, string.format("❤ A %s le gusta tu nido.", liker.DisplayName), "quest")
end

local function buildLikePrompts()
	for _, nest in MapService.LobbyNests do
		local post = Instance.new("Part")
		post.Name = "LikePost"
		post.Anchored = true
		post.CanCollide = false
		post.CanQuery = false
		post.Transparency = 1
		post.Size = Vector3.new(1, 1, 1)
		post.CFrame = nest.Origin * CFrame.new(0, 4, -nest.Size / 2 - 2) -- delante del arco de entrada
		post.Parent = nest.Model
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "LikePrompt"
		prompt.ActionText = "Me gusta ❤"
		prompt.ObjectText = "Nido"
		prompt.KeyboardKeyCode = Enum.KeyCode.G
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = post
		local index = nest.Index
		prompt.Triggered:Connect(function(player)
			like(player, index)
		end)
	end
end

-- Ciclo -------------------------------------------------------------------------------------

function LeaderboardService.addSteal(player: Player)
	pending.Steals[player.UserId] = (pending.Steals[player.UserId] or 0) + 1
end

local function rollWeek()
	local key = Leaderboard.weekKey(os.time())
	if key == week then
		return
	end
	week = key
	for _, kind in KINDS do
		table.clear(pending[kind])
		table.clear(offline[kind])
		table.clear(unsent[kind])
		tops[kind] = {}
	end
	-- El campeón de la semana pasada sale del almacén de esa semana.
	champion = nil
	local last = storeFor("Steals", Leaderboard.previousWeekKey(os.time()))
	local top = last and readTop(last, 1)
	if top and top[1] then
		champion = top[1]
	end
end

local function flush()
	rollWeek()
	for _, kind in KINDS do
		for userId, delta in pending[kind] do
			offline[kind][userId] = (offline[kind][userId] or 0) + delta
			unsent[kind][userId] = (unsent[kind][userId] or 0) + delta
		end
		pending[kind] = {}
		local store = storeFor(kind, week)
		if store then
			for userId, delta in table.clone(unsent[kind]) do
				local ok = pcall(function()
					store:UpdateAsync(tostring(userId), function(old: any): any
						return (tonumber(old) or 0) + delta
					end)
				end)
				if ok then
					-- Durante la espera pudo sumarse más: solo se resta lo enviado.
					local left = (unsent[kind][userId] or 0) - delta
					unsent[kind][userId] = if left > 0 then left else nil
				end
			end
		end
		local stored = if store then readTop(store, Config.Leaderboard.Size) else nil
		if stored then
			tops[kind] = Leaderboard.merge(stored, unsent[kind], Config.Leaderboard.Size)
		else
			-- Sin almacén (Studio sin API Services, o un fallo puntual): lo de este servidor.
			tops[kind] = Leaderboard.merge({}, offline[kind], Config.Leaderboard.Size)
		end
	end
	refreshBoard()
end

-- Herramienta de depuración: refrescar el cartel ya (sin esperar a FlushSeconds).
function LeaderboardService.flushNow()
	task.spawn(flush)
end

function LeaderboardService.init() end

function LeaderboardService.start()
	buildBoard()
	buildLikePrompts()
	task.spawn(function()
		while true do
			flush()
			task.wait(Config.Leaderboard.FlushSeconds)
		end
	end)
	game:BindToClose(flush)
end

return LeaderboardService
