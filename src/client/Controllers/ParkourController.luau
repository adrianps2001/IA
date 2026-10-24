--!strict
-- Torre de la plaza (v3.2): cronómetro en pantalla mientras subes, puntos de control y tu mejor
-- marca. El tiempo bueno lo lleva el servidor (ParkourService); este solo lo enseña.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local UI = require(script.Parent.Parent.UI)

local player = Players.LocalPlayer

local ParkourController = {}

function ParkourController.start()
	if not Config.LobbyParkour.Enabled then
		return
	end
	local gui = UI.screen("Parkour", 4)
	local panel = UI.frame({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 230), Size = UDim2.fromOffset(260, 64), Visible = false }, gui)
	UI.round(panel, 12)
	UI.stroke(panel, UI.Colors.Gold, 2)
	local time = UI.label({ Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 32), Text = "0.00 s", TextColor3 = UI.Colors.Gold }, panel)
	local info = UI.label({ Position = UDim2.fromOffset(10, 36), Size = UDim2.new(1, -20, 0, 22), Text = "", TextColor3 = UI.Colors.Muted }, panel)
	local total = #Config.LobbyParkour.Checkpoints
	RunService.Heartbeat:Connect(function()
		local start = player:GetAttribute("ParkourStart")
		panel.Visible = type(start) == "number"
		if type(start) ~= "number" then
			return
		end
		time.Text = string.format("🏁 %.2f s", math.max(0, workspace:GetServerTimeNow() - start))
		local checkpoint = tonumber(player:GetAttribute("ParkourCheckpoint")) or 0
		local best = tonumber(player:GetAttribute("ParkourBest"))
		info.Text = string.format("Control %d/%d%s", checkpoint, total, if best then string.format(" · tu mejor: %.2f s", best) else "")
	end)
end

return ParkourController
