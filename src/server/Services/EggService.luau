--!strict
-- El Huevo Gigante (GDD 5.2): barra del servidor, umbrales de rareza, ofrendas que sesgan
-- genes y la tirada de la criatura al eclosionar.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Genes = require(Shared.Genes)
local Rarity = require(Shared.Rarity)
local Place = require(Shared.Place)
local RoundState = require(Shared.RoundState)

local AnnouncementService = require(script.Parent.AnnouncementService)
local MapService = require(script.Parent.MapService)

local EggService = {}

local random = Random.new()
local function rng(): number
	return random:NextNumber()
end

local bar = 0
local goal = Config.Round.BarGoalMin
local reached = 0
local biases: Genes.Biases = {}

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
		AnnouncementService.match(
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

-- Tira los genes de la criatura con el estado actual de la barra. Nada de pago la cambia
-- (GDD v3.1: la Suerte se compra para los huevos del nido en el lobby, no para la partida).
function EggService.rollCreature(bloodMoon: boolean): Genes.GeneSet
	local minRarity, luck = Economy.thresholdFor(EggService.fraction())
	if bloodMoon then
		minRarity = Rarity.max(minRarity, Config.Events.BloodMoon.MinRarity :: Rarity.RarityName)
	end
	local rarity = Rarity.roll(rng, luck, minRarity)
	return Genes.rollSet(rng, rarity, biases)
end

function EggService.init() end

function EggService.start()
	if not Place.hasArena() then
		return
	end
	EggService.reset(1)
end

return EggService
