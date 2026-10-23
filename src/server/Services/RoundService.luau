--!strict
-- Bucle de ronda de ~12 minutos (GDD 4): Incubación -> Eclosión y Elección -> Persecución ->
-- Resultados (criatura para quien la mete en su nido, polvo de consolación para el resto).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Creature = require(Shared.Creature)
local Election = require(Shared.Election)
local Events = require(Shared.Events)
local Genes = require(Shared.Genes)
local Rarity = require(Shared.Rarity)
local Remotes = require(Shared.Remotes)
local Rewards = require(Shared.Rewards)
local RoundState = require(Shared.RoundState)
local Testing = require(Shared.Testing)

local AnalyticsHelper = require(script.Parent.Parent.Util.Analytics)
local AnnouncementService = require(script.Parent.AnnouncementService)
local ChaseService = require(script.Parent.ChaseService)
local DataService = require(script.Parent.DataService)
local EggService = require(script.Parent.EggService)
local HeatService = require(script.Parent.HeatService)
local LootService = require(script.Parent.LootService)
local NestService = require(script.Parent.NestService)
local PartyService = require(script.Parent.PartyService)
local QuestService = require(script.Parent.QuestService)

local RoundService = {}

local random = Random.new()
local function rng(): number
	return random:NextNumber()
end

local roundNumber = 0
local colorCorrection: ColorCorrectionEffect

local function setPhase(phase: string, duration: number)
	RoundState.set("Phase", phase)
	RoundState.set("PhaseEndsAt", workspace:GetServerTimeNow() + duration)
end

-- Ciclo visual (GDD 8): atardecer, eclipse en la eclosión, noche en la persecución.
local function setMood(phase: string)
	if phase == "Incubation" or phase == "Intermission" or phase == "Waiting" then
		Lighting.ClockTime = 17.6
		colorCorrection.TintColor = Color3.fromRGB(255, 235, 215)
		colorCorrection.Brightness = 0
	elseif phase == "Hatch" then
		Lighting.ClockTime = 14
		colorCorrection.TintColor = Color3.fromRGB(150, 130, 190)
		colorCorrection.Brightness = -0.15
	elseif phase == "Chase" then
		Lighting.ClockTime = 0
		colorCorrection.TintColor = if RoundState.get("BloodMoon") then Color3.fromRGB(255, 140, 140) else Color3.fromRGB(200, 210, 255)
		colorCorrection.Brightness = 0.05
	end
end

local function readyPlayers(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if DataService.get(player) then
			table.insert(list, player)
		end
	end
	return list
end

function RoundService.isBloodMoon(): boolean
	return Events.isBloodMoon(os.time())
end

local skipRequested = false

-- Herramienta de depuración (solo Studio): termina la fase actual.
function RoundService.skipPhase()
	skipRequested = true
end

-- Espera hasta que acabe el tiempo o se cumpla la condición.
local function waitPhase(duration: number, stopEarly: (() -> boolean)?)
	local endsAt = os.clock() + duration
	skipRequested = false
	while os.clock() < endsAt do
		if skipRequested or (stopEarly and stopEarly()) then
			skipRequested = false
			return
		end
		task.wait(0.25)
	end
end

local function secondsText(seconds: number): string
	return if seconds >= 60 and seconds % 60 == 0 then string.format("%d minutos", seconds // 60) else string.format("%d segundos", seconds)
end

local function runElection(players: { Player }): (Player?, { [string]: number })
	local entries = {}
	local byKey: { [string]: Player } = {}
	for _, player in players do
		local key = tostring(player.UserId)
		byKey[key] = player
		local profile = DataService.get(player)
		local waited = if profile then profile.Stats.RoundsSinceChosen or 0 else 0
		table.insert(entries, { Key = key, Affinity = HeatService.affinity(player), Min = Election.pityMin(waited) })
	end
	local chosenKey, chances = Election.pick(entries, Config.Election.MinChance, rng)
	return if chosenKey then byKey[chosenKey] else nil, chances
end

local function hatch(players: { Player }, bloodMoon: boolean): (Player?, Genes.GeneSet)
	local genes = EggService.rollCreature(bloodMoon)
	local chosen, chances = runElection(players)
	local preview = Creature.new("preview", genes, "Hatch", os.time())

	-- Orden de la ruleta: todos los jugadores con su probabilidad.
	local order = {}
	for _, player in players do
		table.insert(order, {
			UserId = player.UserId,
			Name = player.DisplayName,
			Chance = (chances :: any)[tostring(player.UserId)] or 0,
		})
	end

	RoundState.set("ChosenUserId", if chosen then chosen.UserId else 0)
	-- Suerte acumulada: el elegido vuelve a empezar; los demás suman una ronda de espera.
	for _, player in players do
		local profile = DataService.get(player)
		if profile then
			profile.Stats.RoundsSinceChosen = if player == chosen then 0 else (profile.Stats.RoundsSinceChosen or 0) + 1
		end
	end
	RoundState.set("CreatureName", Creature.name(preview))
	RoundState.set("CreatureRarity", preview.Rarity)
	Remotes.event("HatchSequence"):FireAllClients({
		Order = order,
		ChosenUserId = if chosen then chosen.UserId else 0,
		ChosenName = if chosen then chosen.DisplayName else "",
		Genes = genes,
		CreatureName = Creature.name(preview),
		Rarity = preview.Rarity,
		Duration = Config.Round.HatchTime,
	})

	for _, player in players do
		local profile = DataService.get(player)
		if profile and not profile.Funnel.FirstHatch then
			profile.Funnel.FirstHatch = true
			AnalyticsHelper.funnel(player, 3, "Primera eclosión")
		end
	end

	if Rarity.tier(preview.Rarity) >= Rarity.tier("Mythic") then
		AnnouncementService.global(string.format("¡Ha nacido una criatura %s en un servidor!", Rarity.Info[preview.Rarity].DisplayName))
	end
	return chosen, genes
end

local function awardResults(players: { Player }, result: ChaseService.ChaseResult, chosen: Player)
	local genes = result.Genes
	-- Si el ganador se fue justo al acabar, la criatura cuenta como escapada.
	local winner = if result.Winner and result.Winner.Parent and genes then result.Winner else nil

	local participants: { Rewards.Participant } = {}
	local byKey: { [string]: Player } = {}
	for _, player in players do
		if player.Parent then
			local key = tostring(player.UserId)
			byKey[key] = player
			table.insert(participants, {
				Key = key,
				Affinity = HeatService.affinity(player),
				StealAttempts = ChaseService.stealAttempts(player),
			})
		end
	end
	local partnerKeys = {}
	for _, partner in result.Partners do
		table.insert(partnerKeys, tostring(partner.UserId))
	end
	local rewards = Rewards.compute(participants, if winner then tostring(winner.UserId) else nil, partnerKeys, tostring(chosen.UserId))

	if winner and genes then
		DataService.addStat(winner, "Wins", 1)
		QuestService.progress(winner, "WinCreature", 1)
		ChaseService.keepPacts(winner)
		AnnouncementService.server(
			string.format("🏆 ¡%s se queda con %s!", winner.DisplayName, tostring(RoundState.get("CreatureName") or "la criatura")),
			"rare"
		)
	else
		AnnouncementService.server("La criatura se escapó: nadie la tenía en su nido al acabar el tiempo.", "info")
	end

	for key, reward in rewards do
		local player = byKey[key]
		if reward.Creature and genes then
			NestService.giveCreature(player, genes, "Hatch")
		elseif reward.Copy and genes then
			NestService.giveCreature(player, Genes.commonCopy(genes, rng), "Copy")
			AnnouncementService.player(player, "Tu aliado ganó: recibes tu parte del polvo y una copia común.", "quest")
		end
		if reward.ChosenEgg then
			NestService.giveChosenEgg(player)
			AnnouncementService.player(player, "El huevo te eligió: te deja un Huevo del Elegido en la incubadora.", "rare")
		end
		local dust = math.floor(reward.Dust * PartyService.dustMultiplier(player))
		DataService.addDust(player, dust)
		if not reward.Creature then
			AnnouncementService.player(player, string.format("+%d Polvo de cáscara de consuelo", dust))
		end
		DataService.addStat(player, "RoundsPlayed", 1)
		QuestService.progress(player, "PlayRounds", 1)
	end
end

local function playRound()
	roundNumber += 1
	RoundState.set("Round", roundNumber)

	local bloodMoon = RoundService.isBloodMoon()
	RoundState.set("BloodMoon", bloodMoon)
	RoundState.set("LootNight", Events.isLootNight(os.time()) or Testing.enabled("ForceLootNight"))
	LootService.resetRound()

	-- Preparados
	ChaseService.resetRound()
	HeatService.resetRound()
	EggService.reset(#readyPlayers())
	RoundState.set("ChosenUserId", 0)
	RoundState.set("CarrierUserId", 0)
	local intermission = Testing.duration(Config.Round.IntermissionTime)
	setPhase("Intermission", intermission)
	setMood("Intermission")
	if bloodMoon then
		AnnouncementService.server("🌕 ¡LUNA DE SANGRE! Huevos de rareza mínima Épica y persecución de 5 minutos.", "rare")
	end
	waitPhase(intermission)

	-- Incubación (en Studio, más corta: Config.Testing.TimeScale)
	local incubation = Testing.duration(Config.Round.IncubationTime)
	setPhase("Incubation", incubation)
	setMood("Incubation")
	HeatService.setActive(true)
	waitPhase(incubation, EggService.isFull)
	HeatService.setActive(false)

	local players = readyPlayers()
	if #players == 0 then
		return
	end

	-- Eclosión y Elección
	setPhase("Hatch", Config.Round.HatchTime)
	setMood("Hatch")
	local chosen, genes = hatch(players, bloodMoon)
	waitPhase(Config.Round.HatchTime)

	-- Si el elegido se fue durante el espectáculo, se repite la Elección entre los presentes.
	players = readyPlayers()
	if not chosen or not chosen.Parent then
		chosen = runElection(players)
	end
	if not chosen then
		return
	end

	-- Persecución
	local chaseTime = Testing.duration(if bloodMoon then Config.Round.BloodMoonChaseTime else Config.Round.ChaseTime)
	setPhase("Chase", chaseTime)
	setMood("Chase")
	AnnouncementService.server(string.format("¡El huevo ha elegido a %s! Tenéis %s para robársela.", chosen.DisplayName, secondsText(math.floor(chaseTime))), "threshold")
	ChaseService.begin(chosen, genes)
	if Config.Chase.HeadStartSeconds > 0 then
		AnnouncementService.server(string.format("¡%s tiene %d s de ventaja!", chosen.DisplayName, Config.Chase.HeadStartSeconds), "info")
	end
	waitPhase(chaseTime, ChaseService.isOver)

	-- Prórroga (gol de oro): si el portador no está en su nido, gana el primero que llegue.
	if ChaseService.startOvertime() then
		local overtime = Testing.duration(Config.Chase.OvertimeSeconds)
		setPhase("Overtime", overtime)
		AnnouncementService.server("⚡ ¡PRÓRROGA! Gana el primero que meta la criatura en su nido.", "threshold")
		waitPhase(overtime, ChaseService.isOver)
	end

	-- Resultados
	local result = ChaseService.finish()
	local results = Testing.duration(Config.Round.ResultsTime)
	setPhase("Results", results)
	setMood("Incubation")
	awardResults(readyPlayers(), result, chosen)
	waitPhase(results)
end

function RoundService.init()
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "RoundMood"
	colorCorrection.Parent = Lighting
	RoundState.set("Phase", "Waiting")
	RoundState.set("PhaseEndsAt", 0)
	RoundState.set("CarrierUserId", 0)
	RoundState.set("ChosenUserId", 0)
	RoundState.set("BloodMoon", false)
	RoundState.set("ServerLuckEndsAt", 0)
end

function RoundService.start()
	Players.PlayerAdded:Connect(function(player)
		AnalyticsHelper.funnel(player, 1, "Entrar")
	end)

	task.spawn(function()
		while true do
			if #readyPlayers() < Config.Round.MinPlayers then
				setPhase("Waiting", 0)
				setMood("Waiting")
				task.wait(1)
			else
				local ok, err = pcall(playRound)
				if not ok then
					warn("[RoundService] Error en la ronda: " .. tostring(err))
					HeatService.setActive(false)
					pcall(ChaseService.finish)
					task.wait(3)
				end
			end
		end
	end)
end

return RoundService
