--!strict
-- Lista única de remotos. El servidor los crea; el cliente espera a que existan.
-- El cliente solo envía intenciones; el servidor valida todo (GDD 11.1).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	-- servidor -> cliente
	"HatchSequence", -- espectáculo de eclosión y Elección
	"Announcement", -- avisos para todo el servidor (umbrales, Míticas, Secretas)
	"Notify", -- mensaje para un jugador
	"DealOffered", -- alguien te ofrece un trato
	"ProfileUpdated", -- vista resumida de los datos guardados
	-- cliente -> servidor
	"RequestSprint",
	"RequestPass",
	"RequestCloseDoor",
	"RespondDeal",
	"RequestUpgrade",
	"RequestBuyEgg",
	"RequestBreed",
	"RequestCollectEggs",
	"RequestRebirth",
	"SetGoldenOffering",
	"RequestRelease", -- liberar 1 o 2 criaturas seleccionadas
	"RequestReleaseStored", -- liberar las guardadas de rareza baja
	"RequestBuyDecoration",
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

return Remotes
