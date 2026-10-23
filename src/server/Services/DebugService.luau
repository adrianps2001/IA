--!strict
-- Herramientas de depuración para probar en Roblox Studio (docs/PRUEBAS.md).
-- Solo responden si Testing.enabled("DebugTools"), es decir, dentro de Studio: en un servidor
-- publicado el remoto existe pero se ignora siempre.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Genes = require(Shared.Genes)
local Rarity = require(Shared.Rarity)
local Remotes = require(Shared.Remotes)
local RoundState = require(Shared.RoundState)
local Testing = require(Shared.Testing)

local AnnouncementService = require(script.Parent.AnnouncementService)
local ChaseService = require(script.Parent.ChaseService)
local CommunityService = require(script.Parent.CommunityService)
local DataService = require(script.Parent.DataService)
local EggService = require(script.Parent.EggService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local MatchmakingService = require(script.Parent.MatchmakingService)
local NestService = require(script.Parent.NestService)
local RoundService = require(script.Parent.RoundService)

local DebugService = {}

local random = Random.new()

local commands: { [string]: (Player, any) -> () } = {
	SkipPhase = function()
		RoundService.skipPhase()
	end,
	StartMatch = function(player)
		MatchmakingService.join(player)
		MatchmakingService.forceLaunch()
	end,
	Coins = function(player)
		DataService.addCoins(player, 1_000_000)
	end,
	Dust = function(player)
		DataService.addDust(player, 1000)
	end,
	FillBar = function()
		local goal = tonumber(RoundState.get("BarGoal")) or 0
		EggService.addHeat(goal)
	end,
	BecomeCarrier = function(player)
		if ChaseService.isActive() then
			ChaseService.debugTake(player)
		end
	end,
	GiveCreature = function(player, rarity)
		local name: Rarity.RarityName = if Rarity.isValid(rarity) then rarity else "Epic"
		NestService.giveCreature(player, Genes.rollSet(function()
			return random:NextNumber()
		end, name), "Debug")
	end,
	CommunityFill = function()
		CommunityService.debugFill()
	end,
	LootNight = function()
		RoundState.set("LootNight", not RoundState.get("LootNight"))
	end,
	Leaderboard = function(player)
		for _ = 1, 3 do
			LeaderboardService.addSteal(player)
		end
		LeaderboardService.flushNow()
	end,
	HatchEggs = function(player)
		local profile = DataService.get(player)
		if profile then
			for _, egg in profile.Incubator do
				egg.ReadyAt = os.time()
			end
			DataService.markChanged(player)
		end
	end,
}

function DebugService.init() end

function DebugService.start()
	Remotes.event("DebugCommand").OnServerEvent:Connect(function(player, name, arg)
		if not Testing.enabled("DebugTools") then
			return
		end
		local command = type(name) == "string" and commands[name]
		if command then
			command(player, arg)
			AnnouncementService.player(player, "🛠️ Depuración: " .. name)
		end
	end)
end

return DebugService
