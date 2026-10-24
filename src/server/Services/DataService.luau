--!strict
-- Guardado de datos con bloqueo de sesión (GDD 11.1): un perfil solo puede estar abierto
-- en un servidor a la vez, lo que evita duplicar criaturas en intercambios o saltos de servidor.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Creature = require(Shared.Creature)
local Economy = require(Shared.Economy)
local PlayerData = require(Shared.PlayerData)
local Quests = require(Shared.Quests)
local Rarity = require(Shared.Rarity)
local Remotes = require(Shared.Remotes)

local Analytics = require(script.Parent.Parent.Util.Analytics)

type Profile = PlayerData.Profile

local DataService = {}

local profiles: { [Player]: Profile } = {}
local dirty: { [Player]: boolean } = {}
-- Perfiles ya liberados: un autosave que termine tarde no debe volver a tomar el bloqueo.
local released: { [Player]: boolean } = {}
-- Callbacks en tablas (no BindableEvent): un BindableEvent copiaría el perfil y los
-- cambios hechos por los suscriptores se perderían.
local loadedCallbacks: { (Player, Profile) -> () } = {}
local releasingCallbacks: { (Player, Profile) -> () } = {}

local function fire(callbacks: { (Player, Profile) -> () }, player: Player, profile: Profile)
	for _, callback in callbacks do
		local ok, err = pcall(callback, player, profile)
		if not ok then
			warn("[DataService] " .. tostring(err))
		end
	end
end

local store: DataStore? = nil
local useMemory = false

local MAX_ATTEMPTS = 5
local MAX_VIEW_CREATURES = 100

local function key(player: Player): string
	return "player_" .. player.UserId
end

local function now(): number
	return os.time()
end

local function retry<T>(label: string, fn: () -> T): (boolean, T?)
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(string.format("[DataService] %s falló (intento %d): %s", label, attempt, tostring(result)))
		task.wait(attempt * 1.5)
	end
	return false, nil
end

-- Intenta abrir el perfil tomando el bloqueo. Devuelve nil si otro servidor lo tiene.
local function acquire(player: Player): (boolean, any)
	local s = store :: DataStore
	local locked = false
	local ok, raw = retry("cargar " .. player.Name, function()
		locked = false
		return s:UpdateAsync(key(player), function(old: any)
			if type(old) == "table" and type(old.Lock) == "table" then
				local lock = old.Lock
				local fresh = type(lock.Time) == "number" and now() - lock.Time < Config.Data.LockTimeoutSeconds
				if lock.JobId ~= game.JobId and fresh then
					locked = true
					return nil -- no escribir: otro servidor tiene la sesión
				end
			end
			local data = if type(old) == "table" then old.Data else nil
			return { Data = data, Lock = { JobId = game.JobId, Time = now() } }
		end)
	end)
	if not ok then
		return false, nil
	end
	if locked then
		return false, "locked"
	end
	return true, if type(raw) == "table" then raw.Data else nil
end

local function write(player: Player, profile: Profile, release: boolean): boolean
	if useMemory then
		return true
	end
	local s = store :: DataStore
	profile.LastSeen = now()
	local written = false
	local ok = retry("guardar " .. player.Name, function()
		written = false
		return s:UpdateAsync(key(player), function(old: any)
			if type(old) == "table" and type(old.Lock) == "table" and old.Lock.JobId ~= game.JobId then
				return nil -- perdimos el bloqueo; no pisar datos de otro servidor
			end
			if not release and released[player] then
				return nil -- ya se guardó al salir; no reabrir la sesión
			end
			written = true
			return {
				Data = profile,
				Lock = if release then nil else { JobId = game.JobId, Time = now() },
			}
		end)
	end)
	return ok and written
end

-- Devuelve el bloqueo sin cambiar los datos (cuando el jugador se fue antes de terminar de cargar).
local function releaseLock(player: Player)
	if useMemory then
		return
	end
	local s = store :: DataStore
	retry("liberar " .. player.Name, function()
		return s:UpdateAsync(key(player), function(old: any)
			if type(old) ~= "table" or type(old.Lock) ~= "table" or old.Lock.JobId ~= game.JobId then
				return nil
			end
			return { Data = old.Data, Lock = nil }
		end)
	end)
end

-- Guarda y libera un perfil una sola vez, aunque se llame desde PlayerRemoving y BindToClose.
local function release(player: Player)
	local profile = profiles[player]
	if not profile or released[player] then
		return
	end
	released[player] = true
	fire(releasingCallbacks, player, profile)
	write(player, profile, true)
	profiles[player] = nil
	dirty[player] = nil
	-- Margen para que terminen los autosaves en curso; luego se olvida el jugador.
	task.delay(Config.Data.AutosaveSeconds * 3, function()
		released[player] = nil
	end)
end

local function updateAttributes(player: Player, profile: Profile)
	player:SetAttribute("Coins", math.floor(profile.Coins))
	player:SetAttribute("Dust", math.floor(profile.Dust))
	player:SetAttribute("Generation", profile.Generation)
	-- El tutorial de la primera partida (TutorialController) se ve mientras esto sea 0.
	player:SetAttribute("RoundsPlayed", profile.Stats.RoundsPlayed or 0)
	local kept, broken = profile.Stats.PactsKept, profile.Stats.PactsBroken
	local title = if broken > kept and broken >= 3 then "Traidor" elseif kept >= 3 then "Leal" else ""
	player:SetAttribute("Title", title)

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local coins = leaderstats:FindFirstChild("Monedas")
		if coins and coins:IsA("IntValue") then
			coins.Value = math.floor(profile.Coins)
		end
		local steals = leaderstats:FindFirstChild("Robos")
		if steals and steals:IsA("IntValue") then
			steals.Value = profile.Stats.Steals
		end
	end
end

local function createLeaderstats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Monedas"
	coins.Parent = folder
	local steals = Instance.new("IntValue")
	steals.Name = "Robos"
	steals.Parent = folder
	folder.Parent = player
end

local function load(player: Player)
	local raw: any = nil
	if not useMemory then
		local ok, data
		-- Al cambiar de lugar (lobby <-> partida) el servidor de origen suelta el bloqueo
		-- al salir el jugador, uno o dos segundos después de que llegue aquí.
		for _ = 1, 12 do
			ok, data = acquire(player)
			if ok or data ~= "locked" then
				break
			end
			task.wait(2)
		end
		if not ok then
			player:Kick("No pudimos cargar tus datos. Vuelve a entrar en un momento.")
			return
		end
		raw = data
	end
	if not player.Parent then
		releaseLock(player)
		return
	end
	released[player] = nil

	local profile = PlayerData.reconcile(raw, now())
	profiles[player] = profile
	createLeaderstats(player)
	updateAttributes(player, profile)
	fire(loadedCallbacks, player, profile)
	DataService.markChanged(player)
end

function DataService.get(player: Player): Profile?
	return profiles[player]
end

-- Espera a que el perfil esté cargado (o el jugador se haya ido).
function DataService.await(player: Player): Profile?
	while player.Parent and not profiles[player] do
		task.wait(0.1)
	end
	return profiles[player]
end

function DataService.onLoaded(callback: (Player, Profile) -> ())
	table.insert(loadedCallbacks, callback)
	for player, profile in profiles do
		task.spawn(callback, player, profile)
	end
end

function DataService.onReleasing(callback: (Player, Profile) -> ())
	table.insert(releasingCallbacks, callback)
end

-- Guarda ya (sin soltar el bloqueo). Lo usan las compras para no perder lo pagado si el
-- servidor se cae antes del siguiente autosave.
function DataService.saveNow(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	return write(player, profile, false)
end

function DataService.markChanged(player: Player)
	dirty[player] = true
end

-- reason (opcional) es el motivo para la analítica: "Tipo:Artículo" (Analytics.economy).
function DataService.addCoins(player: Player, amount: number, reason: string?)
	local profile = profiles[player]
	if profile then
		profile.Coins = math.max(0, profile.Coins + amount)
		DataService.markChanged(player)
		Analytics.economy(player, "Coins", amount, reason)
	end
end

function DataService.addDust(player: Player, amount: number, reason: string?)
	local profile = profiles[player]
	if profile then
		profile.Dust = math.max(0, profile.Dust + amount)
		DataService.markChanged(player)
		Analytics.economy(player, "Dust", amount, reason)
	end
end

function DataService.addStat(player: Player, stat: string, amount: number)
	local profile = profiles[player]
	if profile then
		profile.Stats[stat] = (profile.Stats[stat] or 0) + amount
		DataService.markChanged(player)
	end
end

local function passFlag(player: Player, name: string): boolean
	return player:GetAttribute("Pass_" .. name) == true
end

function DataService.nestSlots(player: Player): number
	local profile = profiles[player]
	local level = if profile then profile.Upgrades.Nest else 0
	return Economy.nestSlots(level, passFlag(player, "VipNest"))
end

function DataService.incomePerSecond(player: Player): number
	local profile = profiles[player]
	if not profile then
		return 0
	end
	local base = Creature.activeIncome(profile.Creatures, DataService.nestSlots(player))
	return base * Economy.incomeMultiplier(profile.Generation, passFlag(player, "DoubleCoins"), passFlag(player, "Club"))
end

-- Vista resumida para la interfaz del cliente (nunca se confía en lo que devuelva el cliente).
function DataService.view(player: Player): any
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local slots = DataService.nestSlots(player)
	local multiplier = Economy.incomeMultiplier(profile.Generation, passFlag(player, "DoubleCoins"), passFlag(player, "Club"))
	local creatures = {}
	for index, creature in Creature.sortByIncome(profile.Creatures) do
		-- Solo las mejores viajan al cliente: un jugador puede acumular cientos de criaturas.
		if index > MAX_VIEW_CREATURES then
			break
		end
		table.insert(creatures, {
			Id = creature.Id,
			Name = Creature.name(creature),
			Rarity = creature.Rarity,
			RarityName = Rarity.Info[creature.Rarity].DisplayName,
			Genes = creature.Genes,
			Income = Creature.baseIncome(creature) * multiplier,
			InNest = index <= slots,
			Favorite = table.find(profile.Favorites, creature.Id) ~= nil,
			Shoulder = profile.Shoulder == creature.Id,
			ReleaseDust = Economy.releaseDust(creature.Rarity),
		})
	end

	local upgrades = {}
	for _, name in Economy.UpgradeNames do
		table.insert(upgrades, {
			Name = name,
			DisplayName = Economy.UpgradeDisplay[name],
			Level = profile.Upgrades[name] or 0,
			Cost = Economy.upgradeCost(name, profile.Upgrades[name] or 0),
		})
	end

	local quests = {}
	for _, quest in profile.Quests.List do
		table.insert(quests, {
			Text = Quests.describe(quest),
			Progress = quest.Progress,
			Goal = quest.Goal,
			Done = quest.Claimed,
		})
	end

	local eggs = {}
	for _, egg in profile.Incubator do
		table.insert(eggs, { Id = egg.Id, Kind = egg.Kind, ReadyAt = egg.ReadyAt })
	end

	local bulk = Economy.bulkReleaseIds(profile.Creatures, slots, profile.Favorites)
	local bulkDust = 0
	for _, id in bulk do
		local creature = PlayerData.findCreature(profile, id)
		bulkDust += if creature then Economy.releaseDust(creature.Rarity) or 0 else 0
	end

	local decorations = {}
	for _, def in Config.Decorations do
		table.insert(decorations, {
			Id = def.Id,
			Name = def.Name,
			Currency = def.Currency,
			Cost = Economy.decorationCost(def),
			Beauty = def.Beauty,
			Owned = table.find(profile.Decorations, def.Id) ~= nil,
		})
	end

	return {
		Coins = math.floor(profile.Coins),
		Dust = math.floor(profile.Dust),
		IncomePerSecond = DataService.incomePerSecond(player),
		Slots = slots,
		Creatures = creatures,
		TotalCreatures = #profile.Creatures,
		Upgrades = upgrades,
		Quests = quests,
		Streak = profile.Quests.Streak,
		Incubator = eggs,
		IncubatorSlots = Economy.incubatorSlots(passFlag(player, "ExtraBreedSlot")),
		PersonalEggCost = Config.Incubator.PersonalEggCostDust,
		Generation = profile.Generation,
		RebirthCoins = Economy.rebirthCoins(profile.Generation),
		RebirthCreatures = Config.Rebirth.CreaturesNeeded,
		Stats = profile.Stats,
		StoredRelease = { Count = #bulk, Dust = bulkDust },
		FavoritesMax = Config.Favorites.Max,
		Decorations = decorations,
		Beauty = Economy.beauty(profile.Decorations),
		Trades = table.move(profile.Trades, math.max(#profile.Trades - 4, 1), #profile.Trades, 1, {}),
		Settings = profile.Settings,
		Now = now(),
	}
end

function DataService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.StoreName)
	end)
	if ok then
		store = result
	end
	-- En Studio sin acceso a la API, o si el almacén no responde, se juega en memoria.
	if RunService:IsStudio() then
		local probe = ok and pcall(function()
			(store :: DataStore):GetAsync("__probe")
		end)
		if not probe then
			useMemory = true
			warn("[DataService] Sin acceso a DataStore en Studio: los datos no se guardarán.")
		end
	elseif not ok then
		useMemory = true
		warn("[DataService] DataStore no disponible: los datos no se guardarán.")
	end
end

function DataService.start()
	Analytics.setBalanceReader(function(player: Player, currency: string): number
		local profile = profiles[player]
		if not profile then
			return 0
		end
		return if currency == "Coins" then profile.Coins else profile.Dust
	end)
	Analytics.start()

	Remotes.onInvoke("GetProfile", function(player: Player)
		return DataService.view(player)
	end)
	-- Ajustes del botón ⚙️: se limpian igual que al cargar (nada fuera de rango).
	Remotes.onServer("SetSettings", function(player: Player, raw: any)
		local profile = profiles[player]
		if profile then
			profile.Settings = PlayerData.cleanSettings(raw)
			DataService.markChanged(player)
		end
	end)

	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end

	Players.PlayerRemoving:Connect(release)

	-- Empuja los cambios al cliente agrupados.
	task.spawn(function()
		local updated = Remotes.event("ProfileUpdated")
		while true do
			task.wait(0.25)
			for player in dirty do
				dirty[player] = nil
				local profile = profiles[player]
				if profile and player.Parent then
					updateAttributes(player, profile)
					updated:FireClient(player, DataService.view(player))
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveSeconds)
			for player, profile in profiles do
				task.spawn(write, player, profile, false)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				release(player)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.2)
		end
	end)
end

return DataService
