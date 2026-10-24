--!strict
-- Arranque del servidor: init() de todos los servicios (sin esperas) y luego start().

local services = {
	require(script.Services.DataService),
	require(script.Services.AnnouncementService),
	require(script.Services.AntiCheatService),
	require(script.Services.MonetizationService),
	require(script.Services.MapService),
	require(script.Services.QuestService),
	require(script.Services.PartyService),
	require(script.Services.MatchService),
	require(script.Services.NestService),
	require(script.Services.CommunityService),
	require(script.Services.LootService),
	require(script.Services.TradeService),
	require(script.Services.LeaderboardService),
	require(script.Services.EggService),
	require(script.Services.HeatService),
	require(script.Services.ChaseService),
	require(script.Services.ForestService),
	require(script.Services.RoundService),
	require(script.Services.MatchmakingService),
	require(script.Services.DebugService), -- solo responde en Studio
}

for _, service in services do
	service.init()
end

for _, service in services do
	service.start()
end
