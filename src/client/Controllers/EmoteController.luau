--!strict
-- Emotes con la criatura al hombro (v3.2): botón 💃 con los emotes de Emotes.List. Se pide al
-- servidor (PlayEmote), que lo publica para todos; CosmeticsController hace la animación.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Emotes = require(Shared.Emotes)
local Remotes = require(Shared.Remotes)

local UI = require(script.Parent.Parent.UI)

local player = Players.LocalPlayer

local EmoteController = {}

function EmoteController.start()
	local gui = UI.screen("Emotes", 6)
	local panel = UI.frame({ Position = UDim2.fromOffset(130, 252), Size = UDim2.fromOffset(200, #Emotes.List * 42 + 12), Visible = false }, gui)
	UI.round(panel, 12)
	UI.padding(panel, 6)
	UI.list(panel, 6)
	local button = UI.button({ Position = UDim2.fromOffset(12, 252), Size = UDim2.fromOffset(110, 40), Text = "💃 Emotes", BackgroundColor3 = UI.Colors.Panel }, gui, function()
		panel.Visible = not panel.Visible
	end)
	for index, emote in Emotes.List do
		UI.button({ Size = UDim2.new(1, 0, 0, 36), Text = emote.Icon .. " " .. emote.Name, LayoutOrder = index, BackgroundColor3 = UI.Colors.PanelLight }, panel, function()
			Remotes.event("PlayEmote"):FireServer(emote.Id)
			panel.Visible = false
		end)
	end
	-- Solo si llevas una criatura al hombro (si no, no hay a quién animar).
	local function update()
		button.Visible = player:GetAttribute("CompanionGenes") ~= nil
		if not button.Visible then
			panel.Visible = false
		end
	end
	player:GetAttributeChangedSignal("CompanionGenes"):Connect(update)
	update()
end

return EmoteController
