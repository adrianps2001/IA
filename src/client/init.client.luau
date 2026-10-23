--!strict
-- Arranque del cliente.

local controllers = {
	require(script.Controllers.HUDController),
	require(script.Controllers.ChaseController),
	require(script.Controllers.HatchController),
	require(script.Controllers.NestController),
	require(script.Controllers.EffectsController),
	require(script.Controllers.SocialController),
	require(script.Controllers.DebugController),
	require(script.Controllers.AutopilotController),
}

for _, controller in controllers do
	controller.start()
end
