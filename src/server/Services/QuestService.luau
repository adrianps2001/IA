--!strict
-- Misiones diarias y racha de 7 días (GDD 6). Otros servicios llaman a progress().

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Quests = require(Shared.Quests)

local AnnouncementService = require(script.Parent.AnnouncementService)
local DataService = require(script.Parent.DataService)

local QuestService = {}

-- Se asigna desde NestService para entregar el huevo de racha sin dependencia circular.
QuestService.onStreakReward = nil :: ((Player) -> ())?

function QuestService.progress(player: Player, kind: Quests.QuestKind, amount: number?)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local completed = Quests.progress(profile.Quests, kind, amount or 1)
	if completed > 0 then
		local reward = completed * Config.Quests.RewardDust
		DataService.addDust(player, reward)
		AnnouncementService.player(player, string.format("¡Misión completada! +%d Polvo de cáscara", reward), "quest")
	end
	DataService.markChanged(player)
end

local function rollover(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local streakDone = Quests.rollover(profile.Quests, Quests.dayNumber(os.time()))
	if streakDone and QuestService.onStreakReward then
		QuestService.onStreakReward(player)
		AnnouncementService.player(player, "¡Racha de 7 días! Tienes un huevo especial en la incubadora.", "rare")
	end
	DataService.markChanged(player)
end

function QuestService.init() end

function QuestService.start()
	DataService.onLoaded(function(player)
		rollover(player)
	end)
	-- Comprueba el cambio de día para quien juega a medianoche UTC.
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in game:GetService("Players"):GetPlayers() do
				rollover(player)
			end
		end
	end)
end

return QuestService
