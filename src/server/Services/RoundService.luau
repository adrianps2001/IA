--!strict
-- Bucle de ronda de ~6 minutos (GDD v2 y v3): Incubación (con lluvia dorada a mitad) ->
-- Eclosión y Elección de uno o varios elegidos -> Persecución por el parkour (una por
-- criatura) -> Resultados -> (Noche de Saqueo: fase de saqueo). La criatura es para quien la
-- tenga al acabar el tiempo; polvo de consolación para el resto (si participó).
-- GDD v3: las rondas se juegan dentro de una partida (MatchService): se espera a que haya
-- partida, se juegan Config.Matchmaking.RoundsPerMatch rondas y todos vuelven al lobby.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Creature = require(Shared.Creature)
local Economy = require(Shared.Economy)
local Election = require(Shared.Election)
local Events = require(Shared.Events)
local Genes = require(Shared.Genes)
local Place = require(Shared.Place)
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
local MatchService = require(script.Parent.MatchService)
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
	for _, player in MatchService.players() do
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

-- Inactividad (GDD v2): quién se ha movido hace poco. Los inactivos no pueden ser elegidos
-- (mientras haya alguien activo) ni cobran consuelo.
local lastMoved: { [Player]: number } = {}
local lastPosition: { [Player]: Vector3 } = {}

local function isActive(player: Player): boolean
	if not Config.Election.RequireActivity then
		return true
	end
	return HeatService.affinity(player) > 0 or os.clock() - (lastMoved[player] or -math.huge) < Config.Election.ActivitySeconds
end

local function trackActivity()
	for _, player in MatchService.players() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local last = lastPosition[player]
			if not last or (root.Position - last).Magnitude > 4 then
				lastMoved[player] = os.clock()
				lastPosition[player] = root.Position
			end
		end
	end
end

-- Elige `count` jugadores distintos (uno por criatura).
local function runElection(players: { Player }, count: number): ({ Player }, { [string]: number })
	local candidates = {}
	for _, player in players do
		if isActive(player) then
			table.insert(candidates, player)
		end
	end
	if #candidates == 0 then
		candidates = players -- todos inactivos: mejor elegir a alguien que a nadie
	end
	local entries: { Election.Entry } = {}
	local byKey: { [string]: Player } = {}
	for _, player in candidates do
		local key = tostring(player.UserId)
		byKey[key] = player
		local profile = DataService.get(player)
		local waited = if profile then profile.Stats.RoundsSinceChosen or 0 else 0
		local played = if profile then profile.Stats.RoundsPlayed or 0 else 0
		table.insert(entries, { Key = key, Affinity = HeatService.affinity(player), Min = Election.minFor(waited, played) })
	end
	local keys, chances = Election.pickMany(entries, Config.Election.MinChance, count, rng)
	local chosen = {}
	for _, key in keys do
		table.insert(chosen, byKey[key])
	end
	return chosen, chances
end

local function hatch(players: { Player }, bloodMoon: boolean): { ChaseService.Start }
	local count = Economy.creatureCount(#players)
	local chosen, chances = runElection(players, count)

	-- Ruleta: todos los jugadores con su probabilidad; el cliente enseña los favoritos.
	local order = {}
	for _, player in players do
		table.insert(order, {
			UserId = player.UserId,
			Name = player.DisplayName,
			Chance = (chances :: any)[tostring(player.UserId)] or 0,
		})
	end

	local starts: { ChaseService.Start } = {}
	local picks = {}
	local ids = {}
	for _, player in chosen do
		local genes = EggService.rollCreature(bloodMoon)
		local preview = Creature.new("preview", genes, "Hatch", os.time())
		table.insert(starts, { Chosen = player, Genes = genes })
		table.insert(ids, tostring(player.UserId))
		table.insert(picks, {
			UserId = player.UserId,
			Name = player.DisplayName,
			Genes = genes,
			CreatureName = Creature.name(preview),
			Rarity = preview.Rarity,
		})
		if Rarity.tier(preview.Rarity) >= Rarity.tier("Mythic") then
			AnnouncementService.global(string.format("¡Ha nacido una criatura %s en un servidor!", Rarity.Info[preview.Rarity].DisplayName))
		end
	end

	RoundState.set("ChosenUserIds", table.concat(ids, ","))
	RoundState.set("ChosenUserId", if chosen[1] then chosen[1].UserId else 0)
	RoundState.set("CreatureName", if picks[1] then picks[1].CreatureName else "")
	RoundState.set("CreatureRarity", if picks[1] then picks[1].Rarity else "")
	-- Suerte acumulada: los elegidos vuelven a empezar; los demás suman una ronda de espera.
	for _, player in players do
		local profile = DataService.get(player)
		if profile then
			profile.Stats.RoundsSinceChosen = if table.find(chosen, player) then 0 else (profile.Stats.RoundsSinceChosen or 0) + 1
		end
	end
	local sequence = {
		Order = order,
		Picks = picks,
		Duration = Config.Round.HatchTime,
	}
	for _, player in players do
		Remotes.event("HatchSequence"):FireClient(player, sequence)
	end

	for _, player in players do
		local profile = DataService.get(player)
		if profile and not profile.Funnel.FirstHatch then
			profile.Funnel.FirstHatch = true
			AnalyticsHelper.funnel(player, 3, "Primera eclosión")
		end
	end
	return starts
end

local function awardResults(players: { Player }, results: { ChaseService.Outcome })
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
				Active = isActive(player),
			})
		end
	end
	local outcomes: { Rewards.Outcome } = {}
	for _, result in results do
		local partnerKeys = {}
		for _, partner in result.Partners do
			table.insert(partnerKeys, tostring(partner.UserId))
		end
		table.insert(outcomes, {
			Winner = if result.Winner then tostring(result.Winner.UserId) else nil,
			Partners = partnerKeys,
			Chosen = tostring(result.Chosen.UserId),
		})
		local winner = result.Winner
		if winner then
			DataService.addStat(winner, "Wins", 1)
			QuestService.progress(winner, "WinCreature", 1)
			ChaseService.keepPacts(winner)
			local preview = Creature.new("preview", result.Genes, "Hatch", os.time())
			AnnouncementService.match(string.format("🏆 ¡%s se queda con %s!", winner.DisplayName, Creature.name(preview)), "rare")
		else
			AnnouncementService.match("Una criatura se escapó: estaba suelta al acabar el tiempo.", "info")
		end
	end
	local rewards = Rewards.compute(participants, outcomes)

	for key, reward in rewards do
		local player = byKey[key]
		for _, index in reward.Won do
			NestService.giveCreature(player, results[index].Genes, "Hatch")
			AnnouncementService.sound(player, "Win")
		end
		for _, index in reward.Copies do
			NestService.giveCreature(player, Genes.commonCopy(results[index].Genes, rng), "Copy")
			AnnouncementService.player(player, "Tu aliado ganó: recibes tu parte del polvo y una copia común.", "quest")
		end
		if reward.ChosenEgg then
			NestService.giveChosenEgg(player)
			AnnouncementService.player(player, "El huevo te eligió: te deja un Huevo del Elegido en la incubadora.", "rare")
		end
		local dust = math.floor(reward.Dust * PartyService.dustMultiplier(player))
		DataService.addDust(player, dust)
		if #reward.Won == 0 and dust > 0 then
			AnnouncementService.player(player, string.format("+%d Polvo de cáscara de consuelo", dust))
		elseif #reward.Won == 0 then
			AnnouncementService.player(player, "Sin consuelo: no has participado en la ronda.")
		end
		DataService.addStat(player, "RoundsPlayed", 1)
		QuestService.progress(player, "PlayRounds", 1)
	end
end

-- Lluvia de brasas doradas a mitad de la incubación (GDD v2): un objetivo común en mitad de
-- la fase más larga. HeatService multiplica el Calor de las brasas mientras dura.
local function scheduleGoldenRain(round: number, incubation: number)
	if Config.Round.GoldenRainSeconds <= 0 then
		return
	end
	task.delay(incubation * Config.Round.GoldenRainAt, function()
		if roundNumber ~= round or RoundState.phase() ~= "Incubation" then
			return
		end
		RoundState.set("GoldenRain", true)
		AnnouncementService.match(string.format("✨ ¡Lluvia de brasas doradas! Valen x%d durante %d s", Config.Round.GoldenRainMultiplier, Config.Round.GoldenRainSeconds), "threshold")
		task.delay(Config.Round.GoldenRainSeconds, function()
			if roundNumber == round then
				RoundState.set("GoldenRain", false)
			end
		end)
	end)
end

local function playRound()
	roundNumber += 1
	RoundState.set("Round", roundNumber)

	local bloodMoon = RoundService.isBloodMoon()
	RoundState.set("BloodMoon", bloodMoon)
	RoundState.set("LootNight", Events.isLootNight(os.time()) or Testing.enabled("ForceLootNight"))
	RoundState.set("GoldenRain", false)
	LootService.resetRound()

	-- Preparados
	ChaseService.resetRound()
	HeatService.resetRound()
	EggService.reset(#readyPlayers())
	RoundState.set("ChosenUserId", 0)
	RoundState.set("ChosenUserIds", "")
	RoundState.set("CarrierUserId", 0)
	RoundState.set("Carriers", "")
	local intermission = Testing.duration(Config.Round.IntermissionTime)
	setPhase("Intermission", intermission)
	setMood("Intermission")
	if bloodMoon then
		AnnouncementService.match(string.format("🌕 ¡LUNA DE SANGRE! Huevos de rareza mínima Épica y persecución de %s.", secondsText(Config.Round.BloodMoonChaseTime)), "rare")
	end
	waitPhase(intermission)

	-- Incubación (en Studio, más corta: Config.Testing.TimeScale)
	local incubation = Testing.duration(Config.Round.IncubationTime)
	setPhase("Incubation", incubation)
	setMood("Incubation")
	HeatService.setActive(true)
	scheduleGoldenRain(roundNumber, incubation)
	waitPhase(incubation, EggService.isFull)
	HeatService.setActive(false)
	RoundState.set("GoldenRain", false)

	local players = readyPlayers()
	if #players == 0 then
		return
	end

	-- Eclosión y Elección: una criatura por cada pocos jugadores (Economy.creatureCount).
	setPhase("Hatch", Config.Round.HatchTime)
	setMood("Hatch")
	local starts = hatch(players, bloodMoon)
	waitPhase(Config.Round.HatchTime)

	-- Si un elegido se fue durante la eclosión, su criatura va a otro jugador presente.
	players = readyPlayers()
	local valid: { ChaseService.Start } = {}
	for _, start in starts do
		if start.Chosen.Parent then
			table.insert(valid, start)
		else
			local taken = {}
			for _, s in valid do
				table.insert(taken, s.Chosen)
			end
			local pool = {}
			for _, player in players do
				if not table.find(taken, player) then
					table.insert(pool, player)
				end
			end
			local replacement = runElection(pool, 1)[1]
			if replacement then
				table.insert(valid, { Chosen = replacement, Genes = start.Genes })
			end
		end
	end
	if #valid == 0 then
		return
	end

	-- Persecución
	local chaseTime = Testing.duration(if bloodMoon then Config.Round.BloodMoonChaseTime else Config.Round.ChaseTime)
	setPhase("Chase", chaseTime)
	setMood("Chase")
	local names = {}
	for _, start in valid do
		table.insert(names, start.Chosen.DisplayName)
	end
	AnnouncementService.match(
		string.format(
			"¡El huevo ha elegido a %s! Quien la tenga dentro de %s, se la queda. ¡Robád%s!",
			table.concat(names, " y a "),
			secondsText(math.floor(chaseTime)),
			if #valid == 1 then "sela" else "selas"
		),
		"threshold"
	)
	ChaseService.begin(valid, function(player)
		local isChosen = false
		for _, start in valid do
			if start.Chosen == player then
				isChosen = true
			end
		end
		local profile = DataService.get(player)
		local played = if profile then profile.Stats.RoundsPlayed or 0 else 0
		return Economy.startShields(HeatService.affinity(player), isChosen, played)
	end, chaseTime)
	if Config.Chase.HeadStartSeconds > 0 then
		AnnouncementService.match(string.format("¡Los elegidos tienen %d s de ventaja!", Config.Chase.HeadStartSeconds), "info")
	end
	waitPhase(chaseTime, ChaseService.isOver)

	-- Resultados
	local results = ChaseService.finish()
	local resultsTime = Testing.duration(Config.Round.ResultsTime)
	setPhase("Results", resultsTime)
	setMood("Incubation")
	awardResults(readyPlayers(), results)
	waitPhase(resultsTime)

	-- Noche de Saqueo: fase propia tras los resultados (GDD v2).
	if RoundState.get("LootNight") and Config.Events.LootNight.Enabled then
		local loot = Testing.duration(Config.Events.LootNight.PhaseSeconds)
		setPhase("Loot", loot)
		waitPhase(loot)
	end
end

function RoundService.init()
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "RoundMood"
	colorCorrection.Parent = Lighting
	RoundState.set("Phase", "Waiting")
	RoundState.set("PhaseEndsAt", 0)
	RoundState.set("CarrierUserId", 0)
	RoundState.set("Carriers", "")
	RoundState.set("ChosenUserId", 0)
	RoundState.set("ChosenUserIds", "")
	RoundState.set("BloodMoon", false)
	RoundState.set("GoldenRain", false)
	RoundState.set("ServerLuckEndsAt", 0)
end

function RoundService.start()
	Players.PlayerAdded:Connect(function(player)
		AnalyticsHelper.funnel(player, 1, "Entrar")
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastMoved[player] = nil
		lastPosition[player] = nil
	end)
	task.spawn(function()
		while true do
			trackActivity()
			task.wait(5)
		end
	end)

	if not Place.hasArena() then
		return -- en el lugar del lobby no se juegan rondas
	end
	task.spawn(function()
		while true do
			-- Esperar a que haya partida (cola del lobby o jugadores que llegan).
			MatchService.waitForStart()
			for _ = 1, Config.Matchmaking.RoundsPerMatch do
				if #readyPlayers() < Config.Round.MinPlayers then
					break
				end
				local ok, err = pcall(playRound)
				if not ok then
					warn("[RoundService] Error en la ronda: " .. tostring(err))
					HeatService.setActive(false)
					pcall(ChaseService.finish)
					task.wait(3)
				end
			end
			setPhase("Waiting", 0)
			setMood("Waiting")
			MatchService.finish()
			task.wait(1)
		end
	end)
end

return RoundService
