--!strict
-- Tienda de la Plaza (v3.1, GDD 9.3): sombreros para la criatura al hombro y temas para el nido
-- del lobby, solo estéticos, con polvo de cáscara. El catálogo y el dibujo están en Cosmetics;
-- aquí se compra, se equipa y se aplica (atributo PetHat para los clientes y colores del nido).

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Cosmetics = require(Shared.Cosmetics)
local CosmeticsModel = require(Shared.CosmeticsModel)
local Place = require(Shared.Place)
local Quests = require(Shared.Quests)
local Remotes = require(Shared.Remotes)

local AnnouncementService = require(script.Parent.AnnouncementService)
local DataService = require(script.Parent.DataService)
local NestService = require(script.Parent.NestService)

local ShopService = {}

-- Aplica lo que lleva puesto: sombrero (lo dibuja cada cliente) y tema de su nido del lobby.
function ShopService.apply(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	player:SetAttribute("PetHat", profile.Cosmetics.Hat)
	local nest = NestService.lobbyNestOf(player)
	if nest then
		CosmeticsModel.paintNest(nest.Model, profile.Cosmetics.Theme)
	end
end

local function buy(player: Player, id: any)
	local profile = DataService.get(player)
	local item = Cosmetics.get(id)
	if not profile or not item or not Place.hasLobby() or player:GetAttribute("InMatch") == true then
		return
	end
	local onSale = false
	for _, today in Cosmetics.shopToday(Quests.dayNumber(os.time())) do
		if today.Id == item.Id then
			onSale = true
		end
	end
	if not onSale then
		AnnouncementService.player(player, "Ese artículo no está hoy en la tienda. ¡Vuelve otro día!")
		return
	end
	if table.find(profile.Cosmetics.Owned, item.Id) then
		AnnouncementService.player(player, "Ya lo tienes.")
		return
	end
	if profile.Dust < item.Price then
		AnnouncementService.player(player, string.format("Te faltan %d de polvo de cáscara.", item.Price - math.floor(profile.Dust)))
		return
	end
	DataService.addDust(player, -item.Price, "Shop:Cosmetic_" .. item.Id)
	table.insert(profile.Cosmetics.Owned, item.Id);
	(profile.Cosmetics :: any)[item.Kind] = item.Id -- se lo pone al comprarlo
	DataService.markChanged(player)
	ShopService.apply(player)
	AnnouncementService.sound(player, "Purchase")
	AnnouncementService.player(player, string.format("%s ¡%s es tuyo!", item.Icon, item.Name), "quest")
end

local function equip(player: Player, kind: any, id: any)
	local profile = DataService.get(player)
	if not profile or (kind ~= "Hat" and kind ~= "Theme") then
		return
	end
	if id == nil then
		(profile.Cosmetics :: any)[kind] = nil
	else
		local item = Cosmetics.get(id)
		if not item or item.Kind ~= kind or not table.find(profile.Cosmetics.Owned, item.Id) then
			return
		end
		(profile.Cosmetics :: any)[kind] = item.Id
	end
	DataService.markChanged(player)
	ShopService.apply(player)
end

function ShopService.init() end

function ShopService.start()
	Remotes.onServer("BuyCosmetic", buy)
	Remotes.onServer("EquipCosmetic", equip)
	-- Después de que NestService le dé su nido (se registra antes).
	DataService.onLoaded(function(player)
		task.defer(ShopService.apply, player)
	end)
	Players.PlayerAdded:Connect(function(player)
		player:GetAttributeChangedSignal("LobbyNestIndex"):Connect(function()
			ShopService.apply(player)
		end)
	end)
end

return ShopService
