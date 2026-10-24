--!strict
-- Lista única de remotos. El servidor los crea; el cliente espera a que existan.
-- El cliente solo envía intenciones; el servidor valida todo (GDD 11.1).
-- En el servidor, los remotos se escuchan con Remotes.onServer / Remotes.onInvoke, que limitan
-- cuántas veces por segundo puede llamar cada jugador (v3.1, Config.AntiCheat).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require("./Config")
local RateLimiter = require("./RateLimiter")

local EVENTS = {
	-- servidor -> cliente
	"HatchSequence", -- espectáculo de eclosión y Elección
	"Announcement", -- avisos para todo el servidor (umbrales, Míticas, Secretas)
	"Notify", -- mensaje para un jugador
	"DealOffered", -- alguien te ofrece un trato
	"ProfileUpdated", -- vista resumida de los datos guardados
	"PartyInvited", -- te invitan a una Bandada
	"TradeRequested", -- alguien quiere intercambiar contigo
	"TradeUpdated", -- estado de tu ventana de intercambio (nil = cerrada)
	"PlaySound", -- sonido de una acción (nombre del catálogo Sounds y posición opcional)
	-- cliente -> servidor
	"RequestSprint",
	"RequestPass",
	"RespondDeal",
	"RequestUpgrade",
	"RequestBuyEgg",
	"RequestBreed",
	"RequestCollectEggs",
	"RequestRebirth",
	"RequestRelease", -- liberar 1 o 2 criaturas seleccionadas
	"RequestReleaseStored", -- liberar las guardadas de rareza baja
	"RequestBuyDecoration",
	"ToggleFavorite", -- marcar o desmarcar una criatura con ⭐
	"SetShoulder", -- elegir la criatura que llevas al hombro (o nil para quitarla)
	"SetSettings", -- guardar los ajustes del botón ⚙️
	"VisitNest", -- ir a la entrada del nido de otro jugador del lobby (UserId)
	"PartyInvite",
	"PartyRespond",
	"PartyLeave",
	"TradeRequest",
	"TradeRespond",
	"TradeSetOffer",
	"TradeReady",
	"TradeConfirm",
	"TradeCancel",
	"RequestQueue", -- entrar (true) o salir (false) de la cola de partidas
	"SetAutoRequeue", -- volver a la cola solo al acabar la partida
	"DebugCommand", -- solo Studio (Config.Testing.DebugTools)
}

local FUNCTIONS = {
	"GetProfile",
}

local Remotes = {}

local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in FUNCTIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Remotes.event(name: string): RemoteEvent
	assert(table.find(EVENTS, name), "Remoto desconocido: " .. name)
	return folder:WaitForChild(name) :: RemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	assert(table.find(FUNCTIONS, name), "Función remota desconocida: " .. name)
	return folder:WaitForChild(name) :: RemoteFunction
end

-- Límite de llamadas (solo servidor): un cubo de fichas por jugador y remoto.
local limiter = RateLimiter.new(Config.AntiCheat.RemoteCapacity, Config.AntiCheat.RemoteRefillPerSecond)
local droppedHandler: ((Player, string) -> ())? = nil

local function allowed(player: Player, name: string): boolean
	if limiter:allow(player.UserId .. ":" .. name, os.clock()) then
		return true
	end
	if droppedHandler then
		droppedHandler(player, name)
	end
	return false
end

-- Escucha un RemoteEvent en el servidor ignorando a quien llame demasiado deprisa.
function Remotes.onServer(name: string, handler: (Player, ...any) -> ()): RBXScriptConnection
	return Remotes.event(name).OnServerEvent:Connect(function(player: Player, ...: any)
		if allowed(player, name) then
			handler(player, ...)
		end
	end)
end

-- Igual para un RemoteFunction (si llama demasiado, recibe nil).
function Remotes.onInvoke(name: string, handler: (Player, ...any) -> any)
	Remotes.func(name).OnServerInvoke = function(player: Player, ...: any): any
		if allowed(player, name) then
			return handler(player, ...)
		end
		return nil
	end
end

-- Lo usa AntiCheatService para contar las llamadas ignoradas de cada jugador.
function Remotes.onDropped(handler: (Player, string) -> ())
	droppedHandler = handler
end

function Remotes.forget(player: Player)
	limiter:forget(player.UserId .. ":")
end

return Remotes
