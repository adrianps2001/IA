--!strict
-- Panel de depuración (F7) para probar en Roblox Studio. Solo aparece dentro de Studio y con
-- Config.Testing.DebugTools; el servidor vuelve a comprobarlo (DebugService).

local ContextActionService = game:GetService("ContextActionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Testing = require(Shared.Testing)

local UI = require(script.Parent.Parent.UI)

local DebugController = {}

local BUTTONS = {
	{ "🚀 Jugar ya (sin esperar a la cola)", "StartMatch" },
	{ "⏭ Saltar fase", "SkipPhase" },
	{ "🔥 Llenar la barra", "FillBar" },
	{ "🥚 Ser el portador", "BecomeCarrier" },
	{ "🪙 +1 M Monedas", "Coins" },
	{ "✨ +1000 polvo", "Dust" },
	{ "🐣 Criatura Épica", "GiveCreature", "Epic" },
	{ "🌈 Criatura Mítica", "GiveCreature", "Mythic" },
	{ "⏩ Abrir huevos ya", "HatchEggs" },
	{ "🌙 Noche de Saqueo on/off", "LootNight" },
	{ "🌍 Llenar Huevo Comunitario", "CommunityFill" },
	{ "🏆 +3 robos en el ranking", "Leaderboard" },
}

function DebugController.start()
	if not Testing.enabled("DebugTools") then
		return
	end
	local gui = UI.screen("Debug", 10)
	local panel = UI.frame({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(190, #BUTTONS * 40 + 44),
		Visible = false,
	}, gui)
	UI.round(panel, 12)
	UI.padding(panel, 6)
	UI.list(panel, 4)
	UI.label({ Size = UDim2.new(1, 0, 0, 26), Text = "🛠️ Depuración (F7)", LayoutOrder = 0 }, panel)
	for index, def in BUTTONS do
		UI.button({ Size = UDim2.new(1, 0, 0, 34), Text = def[1], LayoutOrder = index, BackgroundColor3 = UI.Colors.PanelLight }, panel, function()
			Remotes.event("DebugCommand"):FireServer(def[2], def[3])
		end)
	end
	ContextActionService:BindAction("DebugPanel", function(_, state)
		if state == Enum.UserInputState.Begin then
			panel.Visible = not panel.Visible
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.F7)
end

return DebugController
