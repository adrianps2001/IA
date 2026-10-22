--!strict
-- Noche de Saqueo (GDD 7): los fines de semana por la noche, durante la Incubación, se puede
-- saquear una criatura expuesta en un nido ajeno manteniendo el botón 4 s, si su dueño no
-- está dentro (defensas activas). Reglas en Events.canLoot.
-- Versión prudente por defecto (Config.Events.LootNight.OwnerLoses = false): el dueño no
-- pierde nada y el ladrón se lleva una copia común. Las Secretas son inmunes siempre.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Creature = require(Shared.Creature)
local Events = require(Shared.Events)
local Genes = require(Shared.Genes)
local PlayerData = require(Shared.PlayerData)
local RoundState = require(Shared.RoundState)

local AnnouncementService = require(script.Parent.AnnouncementService)
local DataService = require(script.Parent.DataService)
local NestService = require(script.Parent.NestService)
local QuestService = require(script.Parent.QuestService)

local LootService = {}

local random = Random.new()
local open = false
local holdStart: { [Player]: number } = {}
local lootsThisRound: { [Player]: number } = {}
local nestCooldown: { [number]: number } = {} -- UserId del dueño -> protegido hasta

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function setPromptsEnabled(value: boolean)
	for _, prompt in CollectionService:GetTagged("LootPrompt") do
		if prompt:IsA("ProximityPrompt") then
			prompt.Enabled = value
		end
	end
end

local function update()
	local shouldOpen = RoundState.get("LootNight") == true and RoundState.phase() == "Incubation"
	if shouldOpen ~= open then
		open = shouldOpen
		setPromptsEnabled(open)
		if open then
			AnnouncementService.server("🌙 ¡Noche de Saqueo! Mantén E junto a una criatura de un nido ajeno para saquearla. Quédate en tu nido para defender el tuyo.", "threshold")
		end
	end
end

local function onTriggered(prompt: ProximityPrompt, thief: Player)
	local model = prompt:FindFirstAncestorOfClass("Model")
	local ownerId = model and model:GetAttribute("OwnerUserId")
	local creatureId = model and model:GetAttribute("CreatureId")
	local owner = if type(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
	local ownerProfile = owner and DataService.get(owner)
	local thiefProfile = DataService.get(thief)
	if not open or not model or not owner or not ownerProfile or not thiefProfile or type(creatureId) ~= "string" then
		return
	end
	local creature, index = PlayerData.findCreature(ownerProfile, creatureId)
	local root = rootOf(thief)
	if not creature or not index or not root then
		return
	end
	local now = os.clock()
	local ok, reason = Events.canLoot({
		Now = now,
		HoldStartedAt = holdStart[thief],
		Distance = (root.Position - model:GetPivot().Position).Magnitude,
		IsOwner = owner == thief,
		OwnerHome = NestService.isInsideOwnNest(owner),
		Rarity = creature.Rarity,
		LootsThisRound = lootsThisRound[thief] or 0,
		NestCooldownUntil = nestCooldown[owner.UserId] or 0,
	})
	holdStart[thief] = nil
	if not ok then
		if reason then
			AnnouncementService.player(thief, reason)
		end
		return
	end

	lootsThisRound[thief] = (lootsThisRound[thief] or 0) + 1
	nestCooldown[owner.UserId] = now + Config.Events.LootNight.NestCooldown
	local name = Creature.name(creature)
	if Config.Events.LootNight.OwnerLoses then
		table.remove(ownerProfile.Creatures, index)
		DataService.markChanged(owner)
		NestService.refreshDisplay(owner)
		NestService.giveCreature(thief, creature.Genes, "Loot")
		-- La criatura cambia de dueño: se guardan los dos perfiles enseguida.
		task.spawn(DataService.saveNow, owner)
		task.spawn(DataService.saveNow, thief)
		AnnouncementService.player(owner, string.format("🌙 %s te ha saqueado %s. ¡Quédate en tu nido para defenderlo!", thief.DisplayName, name), "threshold")
	else
		NestService.giveCreature(thief, Genes.commonCopy(creature.Genes, function()
			return random:NextNumber()
		end), "Loot")
		AnnouncementService.player(owner, string.format("🌙 %s ha saqueado una copia de tu %s. Quédate en tu nido para defenderlo.", thief.DisplayName, name), "threshold")
	end
	DataService.addStat(thief, "Steals", 1)
	QuestService.progress(thief, "Steal", 1)
	AnnouncementService.server(string.format("🌙 %s ha saqueado el nido de %s.", thief.DisplayName, owner.DisplayName), "info")
end

local function watch(instance: Instance)
	if not instance:IsA("ProximityPrompt") then
		return
	end
	instance.Enabled = open
	instance.PromptButtonHoldBegan:Connect(function(player)
		holdStart[player] = os.clock()
	end)
	instance.PromptButtonHoldEnded:Connect(function(player)
		-- Soltar antes de tiempo anula el intento; si se completó, Triggered lo valida.
		local began = holdStart[player]
		if began and os.clock() - began < Config.Events.LootNight.HoldSeconds - 0.15 then
			holdStart[player] = nil
		end
	end)
	instance.Triggered:Connect(function(player)
		onTriggered(instance, player)
	end)
end

function LootService.resetRound()
	table.clear(lootsThisRound)
end

function LootService.init() end

function LootService.start()
	if not Config.Events.LootNight.Enabled then
		return
	end
	CollectionService:GetInstanceAddedSignal("LootPrompt"):Connect(watch)
	for _, prompt in CollectionService:GetTagged("LootPrompt") do
		watch(prompt)
	end
	RoundState.changed("Phase"):Connect(update)
	RoundState.changed("LootNight"):Connect(update)
	Players.PlayerRemoving:Connect(function(player)
		holdStart[player] = nil
		lootsThisRound[player] = nil
	end)
end

return LootService
