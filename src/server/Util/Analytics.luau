--!strict
-- Embudo de incorporación en el panel de analítica de Roblox (GDD 11.1).
-- Pasos: 1 Entrar, 2 Primer depósito, 3 Primera eclosión, 4 Primera compra.

local AnalyticsService = game:GetService("AnalyticsService")

local Analytics = {}

function Analytics.funnel(player: Player, step: number, name: string)
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
	end)
end

return Analytics
