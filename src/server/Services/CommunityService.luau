--!strict
-- Huevo Comunitario (GDD 7): todos los servidores llenan una barra global cada mes. El Calor
-- depositado en el huevo de la ronda también cuenta aquí. Lo de este servidor se acumula y se
-- envía cada FlushSeconds a un MemoryStore (una sola clave por mes, que caduca sola). Al
-- llenarse, quien aportó al menos MinContribution recibe la criatura conmemorativa del mes.
-- Sin acceso a MemoryStore (Studio sin API Services) la barra funciona solo en local.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Events = require(Shared.Events)
local PlayerData = require(Shared.PlayerData)
local RoundState = require(Shared.RoundState)

local AnnouncementService = require(script.Parent.AnnouncementService)
local DataService = require(script.Parent.DataService)
local NestService = require(script.Parent.NestService)

type Profile = PlayerData.Profile

local CommunityService = {}

local EXPIRATION = 45 * 86400 -- el máximo de MemoryStore; sobra para un mes

local map: MemoryStoreHashMap? = nil
local month = ""
local total = 0 -- último total global conocido (más lo aportado aquí desde entonces)
local pending = 0 -- aportado en este servidor y todavía no enviado
local announcedFull = false

local function enabled(): boolean
	return Config.Events.Community.Enabled
end

local function publish()
	RoundState.set("CommunityProgress", math.clamp(total / Config.Events.Community.Goal, 0, 1))
end

-- La aportación guardada es la del mes en curso; si cambió el mes, empieza de cero.
local function stateOf(profile: Profile): PlayerData.CommunityState
	if profile.Community.Month ~= month then
		profile.Community = { Month = month, Heat = 0, Claimed = false }
	end
	return profile.Community
end

local function tryClaim(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local state = stateOf(profile)
	if Events.communityEligible(state.Heat, state.Claimed, total) then
		state.Claimed = true
		DataService.markChanged(player)
		NestService.giveCreature(player, Events.communityGenes(state.Month), "Community")
		AnnouncementService.player(player, "🌍 ¡El Huevo Comunitario se ha llenado! Recibes la criatura conmemorativa del mes.", "rare")
	end
end

local function checkFull()
	if total >= Config.Events.Community.Goal then
		if not announcedFull then
			announcedFull = true
			AnnouncementService.server(
				string.format("🌍 ¡El Huevo Comunitario se ha llenado! Quien haya aportado %d de Calor este mes recibe la criatura conmemorativa.", Config.Events.Community.MinContribution),
				"rare"
			)
		end
		for _, player in Players:GetPlayers() do
			tryClaim(player)
		end
	end
end

local function rollMonth()
	local key = Events.monthKey(os.time())
	if key ~= month then
		month = key
		total = 0
		pending = 0
		announcedFull = false
	end
end

-- La llama HeatService al depositar en el huevo.
function CommunityService.contribute(player: Player, amount: number)
	if not enabled() or amount <= 0 then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end
	rollMonth()
	stateOf(profile).Heat += amount
	DataService.markChanged(player)
	pending += amount
	total += amount -- vista optimista hasta el siguiente envío
	publish()
	if total >= Config.Events.Community.Goal then
		checkFull()
	end
end

-- Herramienta de depuración (solo Studio): llena la barra en este servidor.
function CommunityService.debugFill()
	total = math.max(total, Config.Events.Community.Goal)
	publish()
	checkFull()
end

local function flush()
	rollMonth()
	local store = map
	if not store then
		return
	end
	local amount = pending
	pending = 0
	local key = month
	local ok, result = pcall(function(): any
		if amount > 0 then
			return store:UpdateAsync(key, function(old)
				return (tonumber(old) or 0) + amount
			end, EXPIRATION)
		end
		return store:GetAsync(key)
	end)
	if key ~= month then
		return -- cambió el mes mientras se enviaba
	end
	if ok then
		-- Lo aportado durante la espera sigue en pending: se suma a la vista local.
		total = math.max(tonumber(result) or 0, 0) + pending
	else
		pending += amount -- se reintenta en el siguiente envío
	end
	publish()
	checkFull()
end

function CommunityService.init()
	rollMonth()
	local ok, result = pcall(function()
		return MemoryStoreService:GetHashMap("CommunityEgg")
	end)
	if ok then
		map = result
	end
end

function CommunityService.start()
	if not enabled() then
		return
	end
	publish()
	DataService.onLoaded(function(player)
		tryClaim(player) -- por si se llenó mientras no estaba
	end)
	task.spawn(function()
		while true do
			flush()
			task.wait(Config.Events.Community.FlushSeconds)
		end
	end)
	game:BindToClose(function()
		if pending > 0 then
			flush()
		end
	end)
end

return CommunityService
