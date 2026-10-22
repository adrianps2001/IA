--!strict
-- Avisos para el servidor y anuncios globales en todos los servidores (GDD 7: Míticas y Secretas).

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local TOPIC = "TheEggChoosesGlobal"

local AnnouncementService = {}

local announcement: RemoteEvent
local notify: RemoteEvent

-- style: "info" | "threshold" | "rare" | "global"
function AnnouncementService.server(text: string, style: string?)
	announcement:FireAllClients(text, style or "info")
end

function AnnouncementService.player(player: Player, text: string, style: string?)
	notify:FireClient(player, text, style or "info")
end

function AnnouncementService.global(text: string)
	AnnouncementService.server(text, "global")
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:PublishAsync(TOPIC, { Text = text, JobId = game.JobId })
		end)
		if not ok then
			warn("[AnnouncementService] " .. tostring(err))
		end
	end)
end

function AnnouncementService.init()
	announcement = Remotes.event("Announcement")
	notify = Remotes.event("Notify")
end

function AnnouncementService.start()
	task.spawn(function()
		pcall(function()
			MessagingService:SubscribeAsync(TOPIC, function(message)
				local data = message.Data
				if type(data) == "table" and type(data.Text) == "string" and data.JobId ~= game.JobId then
					if #Players:GetPlayers() > 0 then
						AnnouncementService.server(string.sub(data.Text, 1, 200), "global")
					end
				end
			end)
		end)
	end)
end

return AnnouncementService
