--!strict
-- Tienda 🛒 (v3.3, GDD 9): lo que se entrega de las ofertas nuevas. El resto de productos y
-- pases los entregan sus sistemas (NestService, MonetizationService…); el cobro y los recibos
-- son de MonetizationService.
-- * Pack de inicio: Monedas + Huevo de Temporada (o más Monedas donde no se permite lo
--   aleatorio de pago) + el Gorro de novato. Una sola vez (se apunta en el perfil).
-- * Fuegos artificiales: espectáculo en la plaza del lobby con tu nombre y tu criatura del
--   hombro; lo dibuja cada cliente. Si se compran varios, van en cola.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Place = require(Shared.Place)
local Remotes = require(Shared.Remotes)

local AnnouncementService = require(script.Parent.AnnouncementService)
local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local NestService = require(script.Parent.NestService)
local ShopService = require(script.Parent.ShopService)

local StoreService = {}

type Show = { Name: string, Genes: string?, Hat: string? }
local queue: { Show } = {}
local running = false

local function runShows()
	if running then
		return
	end
	running = true
	task.spawn(function()
		while #queue > 0 do
			local show = table.remove(queue, 1) :: Show
			Remotes.event("Fireworks"):FireAllClients(show)
			task.wait(Config.Store.FireworksSeconds)
		end
		running = false
	end)
end

local function giveStarter(player: Player): boolean
	local profile = DataService.get(player)
	if not profile then
		return false
	end
	local s = Config.Store.Starter
	local restricted = player:GetAttribute("PaidRandomRestricted") ~= false
	DataService.addCoins(player, s.Coins + (if restricted then s.EggCoins else 0), "IAP:StarterPack")
	if not restricted then
		NestService.grantEgg(player, "Season", "Season")
	end
	ShopService.grantItem(player, s.Hat)
	profile.Store.StarterBought = true
	DataService.markChanged(player)
	AnnouncementService.player(player, "🎁 ¡Pack de inicio entregado! Mira tus Monedas, la incubadora y tu Gorro de novato 🐣", "quest")
	return true
end

local function giveFireworks(player: Player): boolean
	if not Place.hasLobby() then
		return false -- Roblox lo vuelve a intentar cuando esté en un lobby
	end
	table.insert(queue, {
		Name = player.DisplayName,
		Genes = player:GetAttribute("CompanionGenes") :: string?,
		Hat = player:GetAttribute("PetHat") :: string?,
	})
	local wait = (#queue - 1) * Config.Store.FireworksSeconds
	AnnouncementService.server(
		if wait > 0
			then string.format("🎆 ¡%s ha comprado fuegos artificiales! Empiezan en %d s en la plaza", player.DisplayName, wait)
			else string.format("🎆 ¡Fuegos artificiales de %s en la plaza! Mirad al cielo", player.DisplayName),
		"rare"
	)
	runShows()
	return true
end

function StoreService.init()
	MonetizationService.registerProduct("StarterPack", giveStarter)
	MonetizationService.registerProduct("Fireworks", giveFireworks)
end

-- El estado del pack de inicio viaja en la vista del perfil (DataService.view).
function StoreService.start() end

return StoreService
