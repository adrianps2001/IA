--!strict
-- El Huevo Gigante (GDD 5.2): barra del servidor, umbrales de rareza, ofrendas que sesgan
-- genes y la tirada de la criatura al eclosionar.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Genes = require(Shared.Genes)
local Rarity = require(Shared.Rarity)
local Remotes = require(Shared.Remotes)
local RoundState = require(Shared.RoundState)

local AnnouncementService = require(script.Parent.AnnouncementService)
local MapService = require(script.Parent.MapService)
local MonetizationService = require(script.Parent.MonetizationService)

local EggService = {}

local random = Random.new()
local function rng(): number
	return random:NextNumber()
end

local bar = 0
local goal = Config.Round.BarGoalMin
local reached = 0
local biases: Genes.Biases = {}
local pendingGolden: { [Player]: { Slot: Genes.Slot, Gene: string } } = {}

local EGG_COLORS = {
	Color3.fromRGB(255, 240, 210),
	Color3.fromRGB(255, 220, 160),
	Color3.fromRGB(255, 190, 110),
	Color3.fromRGB(255, 150, 70),
	Color3.fromRGB(255, 110, 50),
}

local function updateVisual()
	local egg = MapService.Egg
	egg.Color = EGG_COLORS[reached + 1] or EGG_COLORS[#EGG_COLORS]
	local light = egg:FindFirstChildOfClass("PointLight")
	if light then
		light.Brightness = 1 + reached * 0.75
	end
end

function EggService.fraction(): number
	return if goal > 0 then math.clamp(bar / goal, 0, 1) else 0
end

function EggService.isFull(): boolean
	return bar >= goal
end

function EggService.reset(playerCount: number)
	bar = 0
	goal = Economy.barGoal(playerCount)
	reached = 0
	table.clear(biases)
	RoundState.set("Bar", 0)
	RoundState.set("BarGoal", goal)
	RoundState.set("MinRarity", "Common")
	RoundState.set("Luck", 1)
	updateVisual()
end

function EggService.addHeat(amount: number)
	if amount <= 0 then
		return
	end
	bar = math.min(goal, bar + amount)
	RoundState.set("Bar", bar)

	local minRarity, luck, index = Economy.thresholdFor(EggService.fraction())
	if index > reached then
		reached = index
		RoundState.set("MinRarity", minRarity)
		RoundState.set("Luck", luck)
		AnnouncementService.server(
			string.format(
				"¡El huevo está al %d %%! Rareza mínima: %s",
				math.floor(Config.Thresholds[index].Fraction * 100),
				Rarity.Info[minRarity].DisplayName
			),
			"threshold"
		)
		updateVisual()
	end
end

-- Una ofrenda sustituye a la anterior de la misma ranura.
function EggService.addOffering(slot: Genes.Slot, geneId: string)
	biases[slot] = geneId
end

local function serverLuck(): number
	local endsAt = RoundState.get("ServerLuckEndsAt")
	if type(endsAt) == "number" and workspace:GetServerTimeNow() < endsAt then
		return Config.ServerLuck.Luck
	end
	return 1
end

-- Tira los genes de la criatura con el estado actual de la barra.
function EggService.rollCreature(bloodMoon: boolean): Genes.GeneSet
	local minRarity, luck = Economy.thresholdFor(EggService.fraction())
	if bloodMoon then
		minRarity = Rarity.max(minRarity, Config.Events.BloodMoon.MinRarity :: Rarity.RarityName)
	end
	local rarity = Rarity.roll(rng, luck * serverLuck(), minRarity)
	return Genes.rollSet(rng, rarity, biases)
end

function EggService.init()
	MonetizationService.registerProduct("ServerLuck", function(player)
		local now = workspace:GetServerTimeNow()
		local current = RoundState.get("ServerLuckEndsAt")
		local base = if type(current) == "number" and current > now then current else now
		RoundState.set("ServerLuckEndsAt", base + Config.ServerLuck.Seconds)
		AnnouncementService.server(
			string.format("¡%s ha activado la Suerte del Servidor durante 15 minutos! Gracias 💛", player.DisplayName),
			"rare"
		)
		return true
	end)

	MonetizationService.registerProduct("GoldenOffering", function(player)
		local choice = pendingGolden[player]
		if not choice then
			return false
		end
		pendingGolden[player] = nil
		EggService.addOffering(choice.Slot, choice.Gene)
		local gene = Genes.get(choice.Gene)
		AnnouncementService.server(
			string.format("%s ha hecho una Ofrenda Dorada: %s", player.DisplayName, if gene then gene.Name else "?"),
			"info"
		)
		return true
	end)
end

function EggService.start()
	EggService.reset(1)

	-- El cliente elige gen antes de comprar la Ofrenda Dorada (un recibo no lleva parámetros).
	Remotes.event("SetGoldenOffering").OnServerEvent:Connect(function(player, geneId)
		if type(geneId) ~= "string" then
			return
		end
		local gene = Genes.get(geneId)
		-- Las Secretas no se pueden forzar con dinero.
		if gene and gene.Rarity ~= "Secret" then
			pendingGolden[player] = { Slot = gene.Slot, Gene = gene.Id }
			MonetizationService.prompt(player, "GoldenOffering")
		end
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		pendingGolden[player] = nil
	end)
end

return EggService
