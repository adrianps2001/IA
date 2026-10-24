--!strict
-- Soporte y moderación (v3.1): comandos de chat solo para administradores (AdminCommands).
-- Sirven para ayudar a un jugador sin tocar el DataStore a mano (ver su perfil, devolverle
-- Monedas o una criatura) y para echar o banear a tramposos con la BanAPI de Roblox (el ban
-- vale para todos los lugares de la experiencia). Cada uso queda en la consola del servidor.

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local AdminCommands = require(Shared.AdminCommands)
local Genes = require(Shared.Genes)
local Rarity = require(Shared.Rarity)
local Testing = require(Shared.Testing)

local AnnouncementService = require(script.Parent.AnnouncementService)
local DataService = require(script.Parent.DataService)
local NestService = require(script.Parent.NestService)

local AdminService = {}

local random = Random.new()

local function creatorId(): number
	return if game.CreatorType == Enum.CreatorType.User then game.CreatorId else 0
end

local function allowed(player: Player): boolean
	-- En Studio (con las herramientas de prueba) cualquiera puede probarlos.
	return AdminCommands.isAdmin(player.UserId, creatorId()) or Testing.enabled("DebugTools")
end

-- Busca a un jugador del servidor por nombre o nombre visible (basta con el principio).
local function find(name: string?): Player?
	if not name then
		return nil
	end
	local lower = string.lower(name)
	for _, p in Players:GetPlayers() do
		if string.lower(p.Name) == lower or string.lower(p.DisplayName) == lower then
			return p
		end
	end
	for _, p in Players:GetPlayers() do
		if string.sub(string.lower(p.Name), 1, #lower) == lower or string.sub(string.lower(p.DisplayName), 1, #lower) == lower then
			return p
		end
	end
	return nil
end

local function reply(admin: Player, text: string)
	AnnouncementService.player(admin, "🛡️ " .. text, "info")
end

local function log(admin: Player, text: string)
	warn(string.format("[Admin] %s (%d): %s", admin.Name, admin.UserId, text))
end

local handlers: { [string]: (Player, { string }) -> () } = {
	ayuda = function(admin)
		for _, line in AdminCommands.Help do
			reply(admin, line)
		end
	end,
	ver = function(admin, args)
		local target = find(args[1])
		local profile = target and DataService.get(target)
		if not target or not profile then
			reply(admin, "No encuentro a ese jugador en este servidor.")
			return
		end
		reply(admin, string.format(
			"%s (%d): %d Monedas, %d polvo, %d criaturas, generación %d, %d rondas, %d robos, %d victorias",
			target.Name,
			target.UserId,
			math.floor(profile.Coins),
			math.floor(profile.Dust),
			#profile.Creatures,
			profile.Generation,
			profile.Stats.RoundsPlayed or 0,
			profile.Stats.Steals or 0,
			profile.Stats.Wins or 0
		))
	end,
	dar = function(admin, args)
		local what = string.lower(args[1] or "")
		local target = find(args[2])
		if not target or not DataService.get(target) then
			reply(admin, "Uso: !dar monedas|polvo|criatura <jugador> <cantidad o rareza>")
			return
		end
		if what == "monedas" or what == "polvo" then
			local amount = math.floor(tonumber(args[3]) or 0)
			if amount == 0 or math.abs(amount) > 1e12 then
				reply(admin, "Cantidad no válida.")
				return
			end
			if what == "monedas" then
				DataService.addCoins(target, amount, "Gameplay:Support")
			else
				DataService.addDust(target, amount, "Gameplay:Support")
			end
			reply(admin, string.format("Hecho: %+d %s a %s.", amount, what, target.Name))
			log(admin, string.format("dar %s %d a %s", what, amount, target.Name))
		elseif what == "criatura" then
			local rarity = args[3] or "Epic"
			if not Rarity.isValid(rarity) then
				reply(admin, "Rareza no válida (Common, Rare, Epic, Legendary, Mythic, Secret).")
				return
			end
			local creature = NestService.giveCreature(target, Genes.rollSet(function()
				return random:NextNumber()
			end, rarity :: Rarity.RarityName), "Support")
			reply(admin, if creature then "Criatura entregada a " .. target.Name .. "." else "No se pudo entregar.")
			log(admin, string.format("dar criatura %s a %s", rarity, target.Name))
		else
			reply(admin, "Uso: !dar monedas|polvo|criatura <jugador> <cantidad o rareza>")
		end
	end,
	echar = function(admin, args)
		local target = find(args[1])
		if not target then
			reply(admin, "No encuentro a ese jugador.")
			return
		end
		local reason = AdminCommands.rest(args, 2)
		log(admin, string.format("echar a %s: %s", target.Name, reason))
		target:Kick(if reason ~= "" then reason else "Expulsado por un moderador.")
	end,
	ban = function(admin, args)
		local target = find(args[1])
		local hours = tonumber(args[2])
		if not target or not hours then
			reply(admin, "Uso: !ban <jugador> <horas> <motivo> (0 = para siempre)")
			return
		end
		local reason = AdminCommands.rest(args, 3)
		local ok, err = pcall(function()
			Players:BanAsync({
				UserIds = { target.UserId },
				Duration = if hours <= 0 then -1 else math.floor(hours * 3600),
				DisplayReason = if reason ~= "" then reason else "Has incumplido las normas del juego.",
				PrivateReason = string.format("Ban de %s: %s", admin.Name, reason),
				ApplyToUniverse = true,
			})
		end)
		reply(admin, if ok then "Baneado " .. target.Name .. "." else "No se pudo banear: " .. tostring(err))
		log(admin, string.format("ban a %s (%s h): %s", target.Name, tostring(hours), reason))
	end,
	desban = function(admin, args)
		local userId = tonumber(args[1])
		if not userId then
			reply(admin, "Uso: !desban <UserId>")
			return
		end
		local ok, err = pcall(function()
			Players:UnbanAsync({ UserIds = { userId }, ApplyToUniverse = true })
		end)
		reply(admin, if ok then "Desbaneado " .. userId .. "." else "No se pudo: " .. tostring(err))
		log(admin, "desban " .. userId)
	end,
	anuncio = function(admin, args)
		local text = AdminCommands.rest(args, 1)
		if text == "" then
			return
		end
		-- Hasta los avisos del equipo pasan por el filtro de texto de Roblox.
		local ok, filtered = pcall(function()
			return TextService:FilterStringAsync(text, admin.UserId):GetNonChatStringForBroadcastAsync()
		end)
		if ok then
			AnnouncementService.server("📢 " .. filtered, "rare")
			log(admin, "anuncio: " .. text)
		else
			reply(admin, "No se pudo filtrar el texto.")
		end
	end,
}

local function onChat(player: Player, message: string)
	local command = AdminCommands.parse(message)
	if not command or not allowed(player) then
		return
	end
	local handler = handlers[command.Name]
	if handler then
		task.spawn(handler, player, command.Args)
	end
end

function AdminService.init() end

function AdminService.start()
	local function watch(player: Player)
		player.Chatted:Connect(function(message)
			onChat(player, message)
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
end

return AdminService
