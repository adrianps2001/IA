--!strict
-- Nido personal (GDD 5.6, 5.7, 6): parcela, producción por segundo, incubadora, cría,
-- mejoras permanentes y "Nueva generación".

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Creature = require(Shared.Creature)
local CreatureModel = require(Shared.CreatureModel)
local Economy = require(Shared.Economy)
local Genes = require(Shared.Genes)
local PlayerData = require(Shared.PlayerData)
local Rarity = require(Shared.Rarity)
local Remotes = require(Shared.Remotes)

local AnnouncementService = require(script.Parent.AnnouncementService)
local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)
local MonetizationService = require(script.Parent.MonetizationService)
local QuestService = require(script.Parent.QuestService)

type Profile = PlayerData.Profile

local NestService = {}

local MAX_DISPLAYED = 12

local random = Random.new()
local function rng(): number
	return random:NextNumber()
end

local owners: { [number]: Player } = {} -- índice de nido -> dueño
local displays: { [Player]: { Signature: string, Folder: Folder } } = {}
local doorUsed: { [Player]: boolean } = {}

local function newId(): string
	return HttpService:GenerateGUID(false)
end

function NestService.nestOf(player: Player): MapService.Nest?
	local index = player:GetAttribute("NestIndex")
	if type(index) == "number" then
		return MapService.Nests[index]
	end
	return nil
end

-- Índice del nido que contiene esa posición (o nil si está fuera de todos).
function NestService.nestIndexAt(position: Vector3): number?
	for _, nest in MapService.Nests do
		local localPos = nest.Origin:PointToObjectSpace(position)
		local half = nest.Size / 2
		if math.abs(localPos.X) <= half and math.abs(localPos.Z) <= half and localPos.Y < 20 then
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

-- Muestra en el nido las criaturas que producen (hasta 12 modelos).
function NestService.refreshDisplay(player: Player)
	local profile = DataService.get(player)
	local nest = NestService.nestOf(player)
	if not profile or not nest then
		return
	end
	local active = Creature.sortByIncome(profile.Creatures)
	local slots = math.min(DataService.nestSlots(player), MAX_DISPLAYED)
	local ids = {}
	for i = 1, math.min(slots, #active) do
		table.insert(ids, active[i].Id)
	end
	local signature = table.concat(ids, ",")

	nest.Sign.Text = string.format(
		"Nido de %s\n%d criaturas · %d/s",
		player.DisplayName,
		#profile.Creatures,
		math.floor(DataService.incomePerSecond(player))
	)

	local current = displays[player]
	if current and current.Signature == signature then
		return
	end
	if current then
		current.Folder:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "Creatures"
	folder.Parent = nest.Model
	displays[player] = { Signature = signature, Folder = folder }

	local columns = 4
	local spacing = 5.5
	for i = 1, #ids do
		local creature = active[i]
		local model = CreatureModel.build(creature, 0.8)
		local col = (i - 1) % columns
		local row = math.floor((i - 1) / columns)
		local offset = CFrame.new((col - (columns - 1) / 2) * spacing, 2.6, 7 - row * spacing)
		model:PivotTo(nest.Origin * offset) -- de frente a la entrada
		model.Parent = folder
	end

end

local function assignNest(player: Player)
	for index = 1, #MapService.Nests do
		if not owners[index] then
			owners[index] = player
			player:SetAttribute("NestIndex", index)
			-- La posición viaja como atributo: con StreamingEnabled el cliente puede no tener
			-- cargado el modelo del nido cuando está lejos (la flecha del HUD la necesita).
			player:SetAttribute("NestPosition", MapService.Nests[index].Origin.Position)
			return
		end
	end
	warn("[NestService] No quedan nidos libres para " .. player.Name)
end

local function releaseNest(player: Player)
	local nest = NestService.nestOf(player)
	if nest then
		owners[nest.Index] = nil
		nest.Sign.Text = "Nido libre"
		nest.Door.CanCollide = false
		nest.Door.Transparency = 1
	end
	local display = displays[player]
	if display then
		display.Folder:Destroy()
		displays[player] = nil
	end
	doorUsed[player] = nil
end

local function spawnAtNest(player: Player, character: Model)
	local nest = NestService.nestOf(player)
	if not nest then
		return
	end
	task.defer(function()
		if character.Parent then
			character:PivotTo(nest.Spawn.CFrame * CFrame.new(0, 3, 0)) -- mirando hacia el huevo
		end
	end)
end

-- Cierra la puerta del nido 10 s, una vez por ronda (GDD 5.4).
function NestService.closeDoor(player: Player): boolean
	local nest = NestService.nestOf(player)
	if not nest or doorUsed[player] then
		return false
	end
	doorUsed[player] = true
	nest.Door.CanCollide = true
	nest.Door.Transparency = 0.4
	task.delay(Config.Chase.DoorCloseTime, function()
		nest.Door.CanCollide = false
		nest.Door.Transparency = 1
	end)
	return true
end

function NestService.resetRound()
	table.clear(doorUsed)
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
				local rarity = Rarity.roll(rng, 1, egg.MinRarity, egg.MaxRarity)
				genes = Genes.rollSet(rng, rarity)
			end
			local creature = NestService.giveCreature(player, genes :: Genes.GeneSet, egg.Kind)
			if creature then
				hatched += 1
				AnnouncementService.player(
					player,
					string.format("¡Ha nacido %s (%s)!", Creature.name(creature), Rarity.Info[creature.Rarity].DisplayName),
					"rare"
				)
				if egg.Kind == "Personal" or egg.Kind == "Streak" or egg.Kind == "Season" then
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
	profile.Creatures = {}
	profile.Coins = 0
	profile.Upgrades.Nest = 0
	player:SetAttribute("Upgrade_Nest", 0)
	DataService.markChanged(player)
	NestService.refreshDisplay(player)
	AnnouncementService.server(string.format("¡%s ha empezado la Generación %d!", player.DisplayName, profile.Generation), "rare")
end

-- Ciclo de vida ---------------------------------------------------------------------------

local function onLoaded(player: Player, profile: Profile)
	assignNest(player)
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

	-- Primera vez: un huevo común de regalo para que el nido no empiece vacío.
	if #profile.Creatures == 0 and profile.Generation == 0 and profile.Stats.RoundsPlayed == 0 then
		NestService.giveCreature(player, Genes.rollSet(rng, "Common"), "Starter")
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
	DataService.onReleasing(function(player)
		releaseNest(player)
	end)
	Players.PlayerRemoving:Connect(releaseNest)

	Remotes.event("RequestBuyEgg").OnServerEvent:Connect(buyPersonalEgg)
	Remotes.event("RequestCollectEggs").OnServerEvent:Connect(collectEggs)
	Remotes.event("RequestUpgrade").OnServerEvent:Connect(upgrade)
	Remotes.event("RequestRebirth").OnServerEvent:Connect(rebirth)
	Remotes.event("RequestBreed").OnServerEvent:Connect(function(player, idA, idB)
		if type(idA) == "string" and type(idB) == "string" then
			startBreed(player, idA, idB, false)
		end
	end)

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
