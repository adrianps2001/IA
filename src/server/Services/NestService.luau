--!strict
-- Nido personal (GDD 5.6, 5.7, 6): parcela, producción por segundo, incubadora, cría,
-- mejoras permanentes y "Nueva generación".

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Creature = require(Shared.Creature)
local CreatureModel = require(Shared.CreatureModel)
local DecorationModel = require(Shared.DecorationModel)
local Economy = require(Shared.Economy)
local Genes = require(Shared.Genes)
local Place = require(Shared.Place)
local PlayerData = require(Shared.PlayerData)
local Rarity = require(Shared.Rarity)
local Remotes = require(Shared.Remotes)
local RoundState = require(Shared.RoundState)

local AnnouncementService = require(script.Parent.AnnouncementService)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)
local MatchService = require(script.Parent.MatchService)
local MonetizationService = require(script.Parent.MonetizationService)
local QuestService = require(script.Parent.QuestService)

type Profile = PlayerData.Profile
type Display = { Signature: string, Folder: Folder }

local NestService = {}

local random = Random.new()
local function rng(): number
	return random:NextNumber()
end

local lobbyOwners: { [number]: Player } = {} -- índice de nido del lobby -> dueño
local arenaOwners: { [number]: Player } = {} -- índice de campamento de la arena -> dueño
local lobbyDisplays: { [Player]: Display } = {}
local arenaDisplays: { [Player]: Display } = {}
local decorated: { [Player]: Display } = {}

local function newId(): string
	return HttpService:GenerateGUID(false)
end

-- Nido del lobby (el de verdad: tienda, criaturas, decoración).
function NestService.lobbyNestOf(player: Player): MapService.Nest?
	local index = player:GetAttribute("LobbyNestIndex")
	return if type(index) == "number" then MapService.LobbyNests[index] else nil
end

-- Campamento de la arena (donde apareces en la partida).
function NestService.nestOf(player: Player): MapService.Nest?
	local index = player:GetAttribute("NestIndex")
	return if type(index) == "number" then MapService.Nests[index] else nil
end

-- Dónde "vive" ahora: en la partida, su campamento; si no, su nido del lobby.
function NestService.currentNest(player: Player): MapService.Nest?
	if MatchService.inMatch(player) then
		return NestService.nestOf(player)
	end
	return NestService.lobbyNestOf(player)
end

-- Dueño de un nido del lobby (los "me gusta" se dan allí).
function NestService.ownerOf(index: number): Player?
	return lobbyOwners[index]
end

-- Índice del campamento de la arena que contiene esa posición (o nil).
function NestService.nestIndexAt(position: Vector3): number?
	for _, nest in MapService.Nests do
		local localPos = nest.Origin:PointToObjectSpace(position)
		if Vector3.new(localPos.X, 0, localPos.Z).Magnitude <= nest.Size / 2 + 1 and localPos.Y < 20 then
			return nest.Index
		end
	end
	return nil
end

function NestService.isInsideOwnNest(player: Player): boolean
	local nest = NestService.nestOf(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not nest or not root then
		return false
	end
	return NestService.nestIndexAt(root.Position) == nest.Index
end

-- Las acciones del nido (tienda, mejoras, cría, liberar, decorar...) se hacen en el lobby.
function NestService.canManage(player: Player): boolean
	return Place.hasLobby() and not MatchService.inMatch(player)
end

local function notifyRare(player: Player, creature: Creature.Creature)
	local info = Rarity.Info[creature.Rarity]
	if info.Tier >= Rarity.tier("Mythic") then
		AnnouncementService.global(
			string.format("¡%s ha conseguido una criatura %s: %s!", player.DisplayName, info.DisplayName, Creature.name(creature))
		)
	end
end

-- Añade una criatura al perfil. Se usa al ganar la persecución, al eclosionar huevos y en tratos.
function NestService.giveCreature(player: Player, genes: Genes.GeneSet, origin: string): Creature.Creature?
	local profile = DataService.get(player)
	if not profile then
		return nil
	end
	local creature = Creature.new(newId(), genes, origin, os.time())
	table.insert(profile.Creatures, creature)
	notifyRare(player, creature)
	DataService.markChanged(player)
	NestService.refreshDisplay(player)
	return creature
end

-- Al hombro (GDD v3): la criatura que elijas va contigo, en el lobby y en la partida. Si no
-- eliges ninguna, ninguna. El servidor solo publica sus genes; cada cliente dibuja el modelo
-- (CosmeticsController). Solo estética: no colisiona ni cambia nada del juego.
function NestService.updateCompanion(player: Player)
	local profile = DataService.get(player)
	local id = profile and profile.Shoulder
	local creature = if profile and id then PlayerData.findCreature(profile, id) else nil
	player:SetAttribute("CompanionGenes", if creature then HttpService:JSONEncode(creature.Genes) else nil)
end

-- Suerte del Lobby (GDD 9, v3.1): alguien la compra y, durante 15 min, los huevos del nido
-- de todos los que estén en ese lobby salen con más suerte. No toca la partida.
local function lobbyLuck(): number
	local endsAt = RoundState.get("ServerLuckEndsAt")
	if type(endsAt) == "number" and workspace:GetServerTimeNow() < endsAt then
		return Config.ServerLuck.Luck
	end
	return 1
end

-- Quita de las favoritas las criaturas que ya no tiene (liberadas, intercambiadas, saqueadas).
function NestService.onFavoritesChanged(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local valid = {}
	for _, id in profile.Favorites do
		if PlayerData.findCreature(profile, id) then
			table.insert(valid, id)
		end
	end
	profile.Favorites = valid
	if profile.Shoulder and not PlayerData.findCreature(profile, profile.Shoulder) then
		profile.Shoulder = nil -- la liberaste o la intercambiaste
	end
	NestService.updateCompanion(player)
end

-- Qué criaturas se lucen: primero las favoritas y luego las que más producen (del nido).
local function showcase(player: Player, profile: Profile, count: number): { Creature.Creature }
	local list: { Creature.Creature } = {}
	for _, id in profile.Favorites do
		local creature = PlayerData.findCreature(profile, id)
		if creature and #list < count then
			table.insert(list, creature)
		end
	end
	local active = Creature.sortByIncome(profile.Creatures)
	local slots = DataService.nestSlots(player)
	for i = 1, math.min(slots, #active) do
		if #list >= count then
			break
		end
		if not table.find(list, active[i]) then
			table.insert(list, active[i])
		end
	end
	return list
end

-- Pone las criaturas en los pedestales del nido. lootable: prompts de la Noche de Saqueo.
local function fillPedestals(player: Player, profile: Profile, nest: MapService.Nest, store: { [Player]: Display }, lootable: boolean)
	local list = showcase(player, profile, #nest.Pedestals)
	local ids = {}
	for _, creature in list do
		table.insert(ids, creature.Id)
	end
	local signature = table.concat(ids, ",") .. "|" .. table.concat(profile.Favorites, ",")
	local current = store[player]
	if current and current.Signature == signature then
		return
	end
	if current then
		current.Folder:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Creatures"
	folder.Parent = nest.Model
	store[player] = { Signature = signature, Folder = folder }

	local multiplier = Economy.incomeMultiplier(profile.Generation, player:GetAttribute("Pass_DoubleCoins") == true, player:GetAttribute("Pass_Club") == true)
	for i, pedestal in nest.Pedestals do
		local creature = list[i]
		local rim = nest.Rims[i]
		local plate = nest.Plates[i]
		if not creature then
			if rim then
				rim.Color = Color3.fromRGB(120, 120, 120)
			end
			if plate then
				plate.Text = ""
			end
			continue
		end
		local info = Rarity.Info[creature.Rarity]
		local color = Color3.fromRGB(info.Color[1], info.Color[2], info.Color[3])
		local favorite = table.find(profile.Favorites, creature.Id) ~= nil
		if rim then
			rim.Color = if favorite then Color3.fromRGB(255, 210, 60) else color
		end
		if plate then
			plate.Text = string.format("%s%s\n%s · %s/s", if favorite then "⭐ " else "", Creature.name(creature), info.DisplayName, Economy.short(Creature.baseIncome(creature) * multiplier))
			plate.TextColor3 = color
		end
		-- En el lobby la placa ya dice el nombre: sin etiqueta flotante encima.
		local model = CreatureModel.build(creature, 0.8, { Label = nest.Kind == "Arena" })
		model:SetAttribute("Idle", true) -- el cliente la anima (respira y mira alrededor)
		model:PivotTo(pedestal * CFrame.new(0, CreatureModel.footOffset(model), 0))
		model:SetAttribute("CreatureId", creature.Id)
		model:SetAttribute("OwnerUserId", player.UserId)
		if Rarity.tier(creature.Rarity) >= Rarity.tier("Legendary") then
			-- Foco desde arriba para las más raras.
			local body = model.PrimaryPart
			if body then
				local spot = Instance.new("SpotLight")
				spot.Face = Enum.NormalId.Top
				spot.Angle = 50
				spot.Range = 14
				spot.Brightness = 3
				spot.Color = color
				spot.Parent = body
			end
		end
		local body = model.PrimaryPart
		if lootable and body and Config.Events.LootNight.Enabled then
			-- Para la Noche de Saqueo: LootService activa este prompt cuando toca.
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "LootPrompt"
			prompt.ActionText = "Saquear"
			prompt.ObjectText = Creature.name(creature)
			prompt.HoldDuration = Config.Events.LootNight.HoldSeconds
			prompt.MaxActivationDistance = Config.Events.LootNight.MaxDistance - 2
			prompt.RequiresLineOfSight = false
			prompt.Enabled = false
			prompt.Parent = body
			CollectionService:AddTag(prompt, "LootPrompt")
		end
		model.Parent = folder
	end
end

local function refreshLobbyNest(player: Player, profile: Profile)
	local nest = NestService.lobbyNestOf(player)
	if not nest then
		return
	end
	local beauty = Economy.beauty(profile.Decorations)
	nest.Sign.Text = string.format(
		"Nido de %s\n%d criaturas · ❤ %d%s",
		player.DisplayName,
		#profile.Creatures,
		profile.Stats.LikesReceived or 0,
		if beauty > 0 then string.format(" · ✨ %d", beauty) else ""
	)

	local decorSignature = table.concat(profile.Decorations, ",")
	local decor = decorated[player]
	if not decor or decor.Signature ~= decorSignature then
		if decor then
			decor.Folder:Destroy()
		end
		local decorFolder = Instance.new("Folder")
		decorFolder.Name = "Decorations"
		decorFolder.Parent = nest.Model
		decorated[player] = { Signature = decorSignature, Folder = decorFolder }
		for _, id in profile.Decorations do
			local model = DecorationModel.build(id, nest.Origin)
			if model then
				model.Parent = decorFolder
			end
		end
	end

	-- El huevo del cuenco brilla si hay huevos listos para recoger.
	local egg = nest.Incubator
	if egg then
		local ready = false
		for _, entry in profile.Incubator do
			if entry.ReadyAt <= os.time() then
				ready = true
			end
		end
		egg.Material = if ready then Enum.Material.Neon else Enum.Material.SmoothPlastic
		egg.Color = if ready then Color3.fromRGB(255, 220, 120) elseif #profile.Incubator > 0 then Color3.fromRGB(250, 240, 220) else Color3.fromRGB(150, 140, 130)
		local light = egg:FindFirstChild("ReadyLight")
		if light and light:IsA("PointLight") then
			light.Enabled = ready
		end
	end

	fillPedestals(player, profile, nest, lobbyDisplays, false)
end

local function refreshArenaNest(player: Player, profile: Profile)
	local nest = NestService.nestOf(player)
	if not nest then
		return
	end
	nest.Sign.Text = player.DisplayName
	fillPedestals(player, profile, nest, arenaDisplays, true)
end

function NestService.refreshDisplay(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	-- Cualquier cambio de criaturas pasa por aquí: mantener las favoritas al día.
	NestService.onFavoritesChanged(player)
	refreshLobbyNest(player, profile)
	refreshArenaNest(player, profile)
end

local function clearDisplay(store: { [Player]: Display }, player: Player)
	local display = store[player]
	if display then
		display.Folder:Destroy()
		store[player] = nil
	end
end

local function assignLobbyNest(player: Player)
	if NestService.lobbyNestOf(player) then
		return
	end
	for index = 1, #MapService.LobbyNests do
		if not lobbyOwners[index] then
			lobbyOwners[index] = player
			player:SetAttribute("LobbyNestIndex", index)
			return
		end
	end
	warn("[NestService] No quedan nidos libres en el lobby para " .. player.Name)
end

local function releaseLobbyNest(player: Player)
	local nest = NestService.lobbyNestOf(player)
	if nest then
		lobbyOwners[nest.Index] = nil
		nest.Sign.Text = "Nido libre"
		for i, rim in nest.Rims do
			rim.Color = Color3.fromRGB(120, 120, 120)
			if nest.Plates[i] then
				nest.Plates[i].Text = ""
			end
		end
		if nest.Incubator then
			nest.Incubator.Material = Enum.Material.SmoothPlastic
			nest.Incubator.Color = Color3.fromRGB(150, 140, 130)
		end
	end
	player:SetAttribute("LobbyNestIndex", nil)
	clearDisplay(lobbyDisplays, player)
	local decor = decorated[player]
	if decor then
		decor.Folder:Destroy()
		decorated[player] = nil
	end
end

local function assignArenaNest(player: Player)
	if NestService.nestOf(player) then
		return
	end
	for index = 1, #MapService.Nests do
		if not arenaOwners[index] then
			arenaOwners[index] = player
			player:SetAttribute("NestIndex", index)
			return
		end
	end
	warn("[NestService] No quedan campamentos libres en la arena para " .. player.Name)
end

local function releaseArenaNest(player: Player)
	local nest = NestService.nestOf(player)
	if nest then
		arenaOwners[nest.Index] = nil
		nest.Sign.Text = ""
		for _, rim in nest.Rims do
			rim.Color = Color3.fromRGB(120, 120, 120)
		end
	end
	player:SetAttribute("NestIndex", nil)
	clearDisplay(arenaDisplays, player)
end

-- La flecha del HUD necesita la posición (con StreamingEnabled el modelo puede no estar cargado).
local function publishNestPosition(player: Player)
	local nest = NestService.currentNest(player)
	player:SetAttribute("NestPosition", if nest then nest.Origin.Position else nil)
end

local function spawnAtNest(player: Player, character: Model)
	local nest = NestService.currentNest(player)
	if not nest then
		return
	end
	task.defer(function()
		if character.Parent then
			character:PivotTo(nest.Spawn.CFrame * CFrame.new(0, 3, 0))
		end
	end)
end

-- Al entrar o salir de una partida (modo combinado): cambiar de nido y reaparecer allí.
local function onMatchChanged(player: Player)
	if not DataService.get(player) then
		return
	end
	if MatchService.inMatch(player) then
		assignArenaNest(player)
	else
		releaseArenaNest(player)
	end
	publishNestPosition(player)
	NestService.refreshDisplay(player)
	if player.Character then
		task.spawn(function()
			player:LoadCharacterAsync()
		end)
	end
end

-- Incubadora ------------------------------------------------------------------------------

local function incubatorSlots(player: Player): number
	return Economy.incubatorSlots(MonetizationService.hasPass(player, "ExtraBreedSlot"))
end

local function addEgg(
	player: Player,
	kind: string,
	seconds: number,
	minRarity: Rarity.RarityName,
	maxRarity: Rarity.RarityName,
	genes: Genes.GeneSet?
)
	local profile = DataService.get(player) :: Profile
	local duration = Economy.incubationSeconds(seconds, profile.Upgrades.Incubator, MonetizationService.hasPass(player, "FastIncubator"))
	table.insert(profile.Incubator, {
		Id = newId(),
		Kind = kind,
		Genes = genes,
		MinRarity = minRarity,
		MaxRarity = maxRarity,
		ReadyAt = os.time() + duration,
	})
	DataService.markChanged(player)
end

-- Premio al elegido que pierde la criatura (Rewards). Entra aunque la incubadora esté llena,
-- como el huevo de racha.
function NestService.giveChosenEgg(player: Player)
	if not DataService.get(player) then
		return
	end
	local range = Config.EggRanges.Chosen
	addEgg(player, "Chosen", Config.Incubator.PersonalEggSeconds, range.Min :: Rarity.RarityName, range.Max :: Rarity.RarityName)
end

local function buyPersonalEgg(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	if #profile.Incubator >= incubatorSlots(player) then
		AnnouncementService.player(player, "La incubadora está llena.")
		return
	end
	local cost = Config.Incubator.PersonalEggCostDust
	if profile.Dust < cost then
		AnnouncementService.player(player, "Te falta Polvo de cáscara.")
		return
	end
	DataService.addDust(player, -cost)
	local range = Config.EggRanges.Personal
	addEgg(player, "Personal", Config.Incubator.PersonalEggSeconds, range.Min :: Rarity.RarityName, range.Max :: Rarity.RarityName)
end

local function collectEggs(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local now = os.time()
	local remaining = {}
	local hatched = 0
	for _, egg in profile.Incubator do
		if egg.ReadyAt <= now then
			local genes = egg.Genes
			if not genes then
				local rarity = Rarity.roll(rng, lobbyLuck(), egg.MinRarity, egg.MaxRarity)
				genes = Genes.rollSet(rng, rarity)
			end
			local creature = NestService.giveCreature(player, genes :: Genes.GeneSet, egg.Kind)
			if creature then
				hatched += 1
				AnnouncementService.sound(player, "Hatch")
				AnnouncementService.player(
					player,
					string.format("¡Ha nacido %s (%s)!", Creature.name(creature), Rarity.Info[creature.Rarity].DisplayName),
					"rare"
				)
				if egg.Kind ~= "Breed" then
					QuestService.progress(player, "HatchPersonal", 1)
				end
			end
		else
			table.insert(remaining, egg)
		end
	end
	profile.Incubator = remaining
	if hatched == 0 then
		AnnouncementService.player(player, "Todavía no hay huevos listos.")
	end
	DataService.markChanged(player)
end

local function startBreed(player: Player, idA: string, idB: string, free: boolean): boolean
	local profile = DataService.get(player)
	if not profile or idA == idB then
		return false
	end
	local a = PlayerData.findCreature(profile, idA)
	local b = PlayerData.findCreature(profile, idB)
	if not a or not b then
		return false
	end
	if not free and #profile.Incubator >= incubatorSlots(player) then
		AnnouncementService.player(player, "La incubadora está llena.")
		return false
	end
	local parentRarity = Rarity.max(a.Rarity, b.Rarity)
	local cost = if free then 0 else Economy.breedCost(parentRarity)
	if profile.Coins < cost then
		AnnouncementService.player(player, string.format("La cría cuesta %d Monedas.", cost))
		return false
	end
	DataService.addCoins(player, -cost)
	local child = Genes.inherit(a.Genes, b.Genes, rng, Config.Breeding.MutationChance)
	local childRarity = Genes.rarityOf(child)
	addEgg(player, "Breed", Economy.breedSeconds(parentRarity), childRarity, childRarity, child)
	profile.LastBreed = { idA, idB }
	QuestService.progress(player, "Breed", 1)
	return true
end

-- Liberar criaturas y decorar (sumideros de criaturas, Monedas y Polvo) ----------------

local function releaseIds(player: Player, ids: { string }): (number, number)
	local profile = DataService.get(player)
	if not profile then
		return 0, 0
	end
	local released, dust = 0, 0
	for _, id in ids do
		local creature, index = PlayerData.findCreature(profile, id)
		local value = creature and Economy.releaseDust(creature.Rarity)
		if creature and index and value then
			table.remove(profile.Creatures, index)
			released += 1
			dust += value
		end
	end
	if released > 0 then
		DataService.addDust(player, dust)
		DataService.addStat(player, "Released", released)
		DataService.markChanged(player)
		NestService.refreshDisplay(player)
		AnnouncementService.player(player, string.format("Has liberado %d criatura%s: +%d de Polvo de cáscara.", released, if released == 1 then "" else "s", dust))
	end
	return released, dust
end

local function release(player: Player, ids: any)
	if type(ids) ~= "table" or #ids > 2 then
		return
	end
	local profile = DataService.get(player)
	local clean = {}
	for _, id in ids do
		-- Las favoritas no se liberan (hay que quitarles la estrella antes).
		if type(id) == "string" and profile and not table.find(profile.Favorites, id) then
			table.insert(clean, id)
		end
	end
	local released = releaseIds(player, clean)
	if released == 0 then
		AnnouncementService.player(player, "Esa criatura no se puede liberar (las Secretas y las favoritas ⭐ no se liberan).")
	end
end

-- Elegir la criatura del hombro (la misma otra vez = quitarla).
local function setShoulder(player: Player, id: any)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	if type(id) == "string" and PlayerData.findCreature(profile, id) and profile.Shoulder ~= id then
		profile.Shoulder = id
	else
		profile.Shoulder = nil
	end
	DataService.markChanged(player)
	NestService.updateCompanion(player)
end

-- Favoritas: marcar o desmarcar con ⭐ (como mucho Config.Favorites.Max).
local function toggleFavorite(player: Player, id: any)
	local profile = DataService.get(player)
	if not profile or type(id) ~= "string" or not PlayerData.findCreature(profile, id) then
		return
	end
	local index = table.find(profile.Favorites, id)
	if index then
		table.remove(profile.Favorites, index)
	elseif #profile.Favorites >= Config.Favorites.Max then
		AnnouncementService.player(player, string.format("Solo puedes tener %d favoritas. Quita la estrella a otra antes.", Config.Favorites.Max))
		return
	else
		table.insert(profile.Favorites, id)
	end
	DataService.markChanged(player)
	NestService.onFavoritesChanged(player)
end

local function releaseStored(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local released = releaseIds(player, Economy.bulkReleaseIds(profile.Creatures, DataService.nestSlots(player), profile.Favorites))
	if released == 0 then
		AnnouncementService.player(player, "No hay criaturas guardadas que liberar.")
	end
end

local function buyDecoration(player: Player, id: any)
	local profile = DataService.get(player)
	local def = Economy.decoration(id)
	if not profile or not def or not Config.Sinks.Decorations then
		return
	end
	if table.find(profile.Decorations, def.Id) then
		AnnouncementService.player(player, "Ya tienes esa decoración.")
		return
	end
	local cost = Economy.decorationCost(def)
	local balance = if def.Currency == "Coins" then profile.Coins else profile.Dust
	if balance < cost then
		AnnouncementService.player(player, if def.Currency == "Coins" then "No tienes Monedas suficientes." else "Te falta Polvo de cáscara.")
		return
	end
	if def.Currency == "Coins" then
		DataService.addCoins(player, -cost)
	else
		DataService.addDust(player, -cost)
	end
	table.insert(profile.Decorations, def.Id)
	AnnouncementService.sound(player, "Purchase")
	DataService.markChanged(player)
	NestService.refreshDisplay(player)
	AnnouncementService.player(player, string.format("¡%s colocada en tu nido!", def.Name), "rare")
end

-- Mejoras y Nueva generación ------------------------------------------------------------

local function upgrade(player: Player, name: any)
	local profile = DataService.get(player)
	if not profile or type(name) ~= "string" or profile.Upgrades[name] == nil then
		return
	end
	local level = profile.Upgrades[name]
	local cost = Economy.upgradeCost(name :: Economy.UpgradeName, level)
	if not cost then
		AnnouncementService.player(player, "Esa mejora ya está al máximo.")
		return
	end
	if profile.Coins < cost then
		AnnouncementService.player(player, "No tienes Monedas suficientes.")
		return
	end
	DataService.addCoins(player, -cost)
	AnnouncementService.sound(player, "Purchase")
	profile.Upgrades[name] = level + 1
	player:SetAttribute("Upgrade_" .. name, level + 1)
	DataService.markChanged(player)
	NestService.refreshDisplay(player)
end

local function rebirth(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	if not Economy.canRebirth(#profile.Creatures, profile.Coins, profile.Generation) then
		AnnouncementService.player(
			player,
			string.format(
				"Necesitas %d criaturas y %d Monedas para una Nueva generación.",
				Config.Rebirth.CreaturesNeeded,
				Economy.rebirthCoins(profile.Generation)
			)
		)
		return
	end
	profile.Generation += 1
	-- GDD v2: las favoritas sobreviven a la Nueva generación.
	profile.Creatures = Economy.keptOnRebirth(profile.Creatures, profile.Favorites)
	profile.Coins = 0
	profile.Upgrades.Nest = 0
	player:SetAttribute("Upgrade_Nest", 0)
	DataService.markChanged(player)
	NestService.refreshDisplay(player)
	AnnouncementService.server(string.format("¡%s ha empezado la Generación %d!", player.DisplayName, profile.Generation), "rare")
end

-- Ciclo de vida ---------------------------------------------------------------------------

local function onLoaded(player: Player, profile: Profile)
	if Place.hasLobby() then
		assignLobbyNest(player)
	end
	if MatchService.inMatch(player) then
		assignArenaNest(player)
	end
	publishNestPosition(player)
	NestService.updateCompanion(player)
	player:GetAttributeChangedSignal("InMatch"):Connect(function()
		onMatchChanged(player)
	end)
	for name, level in profile.Upgrades do
		player:SetAttribute("Upgrade_" .. name, level)
	end

	-- Producción sin conexión (tope de 8 h).
	local away = os.time() - profile.LastSeen
	local earned = Economy.offlineEarnings(DataService.incomePerSecond(player), away)
	if earned > 0 then
		DataService.addCoins(player, earned)
		AnnouncementService.player(player, string.format("Tu nido produjo %d Monedas mientras no estabas.", earned), "rare")
	end

	-- Primera vez: una criatura común de regalo para que el nido no empiece vacío y un huevo
	-- de bienvenida que nace en 2 minutos (GDD v2: el novato ve pronto el ciclo del nido).
	if #profile.Creatures == 0 and profile.Generation == 0 and profile.Stats.RoundsPlayed == 0 then
		NestService.giveCreature(player, Genes.rollSet(rng, "Common"), "Starter")
		if Config.Incubator.WelcomeEggSeconds > 0 and #profile.Incubator == 0 then
			local range = Config.EggRanges.Welcome
			addEgg(player, "Welcome", Config.Incubator.WelcomeEggSeconds, range.Min :: Rarity.RarityName, range.Max :: Rarity.RarityName)
			AnnouncementService.player(player, "🥚 ¡Tienes un huevo de bienvenida en la incubadora! Nace en 2 minutos.", "quest")
		end
	end

	if player.Character then
		spawnAtNest(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		spawnAtNest(player, character)
	end)
	NestService.refreshDisplay(player)
end

function NestService.init()
	QuestService.onStreakReward = function(player)
		local range = Config.EggRanges.Streak
		addEgg(player, "Streak", 60, range.Min :: Rarity.RarityName, range.Max :: Rarity.RarityName)
	end

	MonetizationService.registerProduct("ServerLuck", function(player)
		if not Place.hasLobby() then
			return false
		end
		local now = workspace:GetServerTimeNow()
		local current = RoundState.get("ServerLuckEndsAt")
		local base = if type(current) == "number" and current > now then current else now
		RoundState.set("ServerLuckEndsAt", base + Config.ServerLuck.Seconds)
		AnnouncementService.server(
			string.format("🍀 ¡%s ha activado la Suerte del Lobby! 15 min de huevos del nido con más suerte para todos. Gracias 💛", player.DisplayName),
			"rare"
		)
		return true
	end)
	MonetizationService.registerProduct("BreedReroll", function(player)
		local profile = DataService.get(player)
		if not profile or not profile.LastBreed then
			return false
		end
		return startBreed(player, profile.LastBreed[1], profile.LastBreed[2], true)
	end)

	MonetizationService.registerProduct("SeasonEgg", function(player)
		if not DataService.get(player) then
			return false
		end
		local range = Config.EggRanges.Season
		addEgg(player, "Season", 60, range.Min :: Rarity.RarityName, range.Max :: Rarity.RarityName)
		return true
	end)
end

function NestService.start()
	DataService.onLoaded(onLoaded)
	local function releaseAll(player: Player)
		releaseLobbyNest(player)
		releaseArenaNest(player)
	end
	DataService.onReleasing(function(player)
		releaseAll(player)
	end)
	Players.PlayerRemoving:Connect(releaseAll)

	-- Todo lo del nido se hace en el lobby (GDD v3); en la partida se avisa.
	local function managed(handler: (Player, ...any) -> ()): (Player, ...any) -> ()
		return function(player: Player, ...: any)
			if not NestService.canManage(player) then
				AnnouncementService.player(player, "🏡 Eso se hace en tu nido del lobby, al acabar la partida.")
				return
			end
			handler(player, ...)
		end
	end
	Remotes.event("RequestBuyEgg").OnServerEvent:Connect(managed(buyPersonalEgg))
	Remotes.event("RequestCollectEggs").OnServerEvent:Connect(managed(collectEggs))
	Remotes.event("RequestUpgrade").OnServerEvent:Connect(managed(upgrade))
	Remotes.event("RequestRebirth").OnServerEvent:Connect(managed(rebirth))
	Remotes.event("RequestRelease").OnServerEvent:Connect(managed(release))
	Remotes.event("ToggleFavorite").OnServerEvent:Connect(managed(toggleFavorite))
	Remotes.event("SetShoulder").OnServerEvent:Connect(managed(setShoulder))
	Remotes.event("RequestReleaseStored").OnServerEvent:Connect(managed(releaseStored))
	Remotes.event("RequestBuyDecoration").OnServerEvent:Connect(managed(buyDecoration))
	Remotes.event("RequestBreed").OnServerEvent:Connect(managed(function(player, idA, idB)
		if type(idA) == "string" and type(idB) == "string" then
			startBreed(player, idA, idB, false)
		end
	end))

	-- Producción por segundo. Solo actualiza el atributo; la vista completa se envía
	-- cuando cambia algo estructural.
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(1)
			tick += 1
			for _, player in Players:GetPlayers() do
				local profile = DataService.get(player)
				if profile then
					profile.Coins += DataService.incomePerSecond(player)
					player:SetAttribute("Coins", math.floor(profile.Coins))
					if tick % 10 == 0 then
						NestService.refreshDisplay(player)
						DataService.markChanged(player) -- refresca el panel (Monedas, ingresos)
					end
				end
			end
		end
	end)
end

return NestService
