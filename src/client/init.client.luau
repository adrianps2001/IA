--!strict
-- Arranque del cliente.

local controllers = {
	require(script.Controllers.SoundController),
	require(script.Controllers.HUDController),
	require(script.Controllers.ChaseController),
	require(script.Controllers.HatchController),
	require(script.Controllers.NestController),
	require(script.Controllers.EffectsController),
	require(script.Controllers.SocialController),
	require(script.Controllers.CosmeticsController),
	require(script.Controllers.ArenaController),
	require(script.Controllers.TutorialController),
	require(script.Controllers.SettingsController),
	require(script.Controllers.ActionButtonController),
	require(script.Controllers.DailyController),
	require(script.Controllers.DebugController),
	require(script.Controllers.AutopilotController),
}

for _, controller in controllers do
	controller.start()
end
