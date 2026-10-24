--!strict
-- Game passes, productos de consumo y recibos idempotentes (GDD 9).
-- Regla ética: ninguna compra garantiza ser elegido ni ganar la persecución.
-- Productos aleatorios de pago: solo se ofrecen si PolicyService lo permite (atributo
-- PaidRandomRestricted).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local PlayerData = require(Shared.PlayerData)

local DataService = require(script.Parent.DataService)

-- Devuelve true si el producto se entregó; false para que Roblox lo reintente más tarde.
type ProductHandler = (player: Player) -> boolean

local MonetizationService = {}

local handlers: { [number]: ProductHandler } = {}

-- Los pases se guardan como atributos "Pass_<Nombre>" para que cualquier servicio los lea.
local function refreshPasses(player: Player)
	for name, id in Config.GamePasses do
		if id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
			end)
			player:SetAttribute("Pass_" .. name, ok and owns == true)
		else
			player:SetAttribute("Pass_" .. name, false)
		end
	end
	local club = false
	if Config.ClubSubscriptionId ~= "" then
		local ok, status = pcall(function()
			return MarketplaceService:GetUserSubscriptionStatusAsync(player, Config.ClubSubscriptionId)
		end)
		club = ok and type(status) == "table" and status.IsSubscribed == true
	end
	player:SetAttribute("Pass_Club", club)

	-- En algunos países están restringidos los objetos aleatorios de pago (huevos, repetir
	-- cría). Si no se puede consultar, se asume restringido: es la opción segura.
	local ok, policy = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	local restricted = not ok or type(policy) ~= "table" or policy.ArePaidRandomItemsRestricted ~= false
	player:SetAttribute("PaidRandomRestricted", restricted)
end

function MonetizationService.hasPass(player: Player, name: string): boolean
	return player:GetAttribute("Pass_" .. name) == true
end

-- Registra qué hace un producto de consumo. name es la clave de Config.DevProducts.
function MonetizationService.registerProduct(name: string, handler: ProductHandler)
	local id = (Config.DevProducts :: any)[name]
	if type(id) == "number" and id ~= 0 then
		handlers[id] = handler
	end
end

-- Igual, pero con el número del producto (para listas de productos, como la Tienda de la Plaza).
function MonetizationService.registerProductId(id: number, handler: ProductHandler)
	if id ~= 0 then
		handlers[id] = handler
	end
end

function MonetizationService.prompt(player: Player, name: string)
	local id = (Config.DevProducts :: any)[name]
	if type(id) == "number" and id ~= 0 then
		MarketplaceService:PromptProductPurchase(player, id)
	end
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = DataService.get(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local receiptId = tostring(receipt.PurchaseId)
	if PlayerData.hasReceipt(profile, receiptId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local handler = handlers[receipt.ProductId]
	if not handler then
		warn("[MonetizationService] Producto sin handler: " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(handler, player)
	if not ok or not granted then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	PlayerData.addReceipt(profile, receiptId)
	if not profile.Funnel.FirstPurchase then
		profile.Funnel.FirstPurchase = true
	end
	DataService.markChanged(player)
	-- Guardar antes de confirmar: si el guardado falla, Roblox reintentará el recibo y el
	-- registro de recibos evitará entregarlo dos veces.
	if not DataService.saveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.init()
	-- Paquetes de Monedas: se gestionan aquí porque no dependen de otro sistema.
	for name, amount in Config.CoinPacks do
		MonetizationService.registerProduct(name, function(player)
			DataService.addCoins(player, amount, "IAP:" .. name)
			return true
		end)
	end
end

function MonetizationService.start()
	Players.PlayerAdded:Connect(refreshPasses)
	for _, player in Players:GetPlayers() do
		task.spawn(refreshPasses, player)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _passId, purchased)
		if purchased then
			refreshPasses(player)
			DataService.markChanged(player)
		end
	end)

	MarketplaceService.ProcessReceipt = processReceipt
end

return MonetizationService
