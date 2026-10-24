--!strict
-- Regalo diario (v3.1): botón 🎁 en el lobby que brilla cuando hay regalo y un panel con los 7
-- días de la racha. Las reglas están en DailyReward; el servidor da el premio (ClaimDaily).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local DailyReward = require(Shared.DailyReward)
local Remotes = require(Shared.Remotes)

local UI = require(script.Parent.Parent.UI)

local player = Players.LocalPlayer

local DailyController = {}

local button: TextButton
local panel: Frame
local tiles: { Frame } = {}
local claimButton: TextButton

local function state(): DailyReward.State
	return DailyReward.clean({ LastDay = player:GetAttribute("DailyLastDay"), Streak = player:GetAttribute("DailyStreak") })
end

local function today(): number
	return DailyReward.dayNumber(workspace:GetServerTimeNow())
end

local function rewardText(reward: DailyReward.Reward): string
	if reward.Dust then
		return string.format("✨ %d", reward.Dust)
	elseif reward.Coins then
		local generation = tonumber(player:GetAttribute("Generation")) or 0
		return "🪙 " .. UI.formatNumber(reward.Coins * (generation + 1))
	end
	return "🥚 Huevo"
end

local function refresh()
	local s = state()
	local ready = DailyReward.canClaim(s, today())
	local nextDay = DailyReward.nextDay(s, today())
	local inLobby = player:GetAttribute("InMatch") ~= true and player:GetAttribute("LobbyNestIndex") ~= nil
	button.Visible = inLobby and Config.DailyReward.Enabled
	button.Text = if ready then "🎁 ¡Regalo!" else "🎁 Regalo"
	button.BackgroundColor3 = if ready then UI.Colors.Accent else UI.Colors.Panel
	if not inLobby then
		panel.Visible = false
	end
	for day, tile in tiles do
		local claimed = (not ready and day <= s.Streak) or (ready and day < nextDay)
		tile.BackgroundColor3 = if ready and day == nextDay then UI.Colors.Accent elseif claimed then UI.Colors.Good else UI.Colors.PanelLight
	end
	claimButton.Text = if ready then string.format("Abrir el regalo del día %d", nextDay) else "Vuelve mañana"
	claimButton.BackgroundColor3 = if ready then UI.Colors.Good else UI.Colors.PanelLight
end

function DailyController.start()
	if not Config.DailyReward.Enabled then
		return
	end
	local gui = UI.screen("Daily", 6)
	button = UI.button({ Position = UDim2.fromOffset(12, 206), Size = UDim2.fromOffset(110, 40), Text = "🎁 Regalo", BackgroundColor3 = UI.Colors.Panel }, gui, function()
		panel.Visible = not panel.Visible
		refresh()
	end)
	panel = UI.frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 220), Visible = false }, gui)
	UI.round(panel, 16)
	UI.stroke(panel, UI.Colors.Gold, 2)
	UI.label({ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -60, 0, 30), Text = "🎁 Regalo diario", TextXAlignment = Enum.TextXAlignment.Left }, panel)
	UI.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(36, 30), Text = "✕", BackgroundColor3 = UI.Colors.PanelLight }, panel, function()
		panel.Visible = false
	end)
	UI.label({ Position = UDim2.fromOffset(12, 40), Size = UDim2.new(1, -24, 0, 20), Text = "Entra cada día seguido: el 7.º trae un huevo. Si faltas un día, vuelves al 1.", TextColor3 = UI.Colors.Muted, TextWrapped = true }, panel)
	local days = Config.DailyReward.Days
	local width = (420 - 24 - (#days - 1) * 6) / #days
	for day, reward in days do
		local tile = UI.frame({ Position = UDim2.fromOffset(12 + (day - 1) * (width + 6), 70), Size = UDim2.fromOffset(width, 80), BackgroundColor3 = UI.Colors.PanelLight, BackgroundTransparency = 0 }, panel)
		UI.round(tile, 10)
		UI.label({ Size = UDim2.new(1, 0, 0, 24), Text = "Día " .. day, TextColor3 = UI.Colors.Muted }, tile)
		UI.label({ Position = UDim2.fromOffset(2, 28), Size = UDim2.new(1, -4, 0, 44), Text = rewardText(reward :: DailyReward.Reward), TextWrapped = true }, tile)
		tiles[day] = tile
	end
	claimButton = UI.button({ Position = UDim2.new(0, 12, 1, -56), Size = UDim2.new(1, -24, 0, 44), Text = "" }, panel, function()
		if DailyReward.canClaim(state(), today()) then
			Remotes.event("ClaimDaily"):FireServer()
		end
	end)
	for _, name in { "DailyLastDay", "DailyStreak", "InMatch", "LobbyNestIndex", "Generation" } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	-- A medianoche UTC aparece el regalo nuevo sin tener que volver a entrar.
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc > 30 then
			acc = 0
			refresh()
		end
	end)
	refresh()
end

return DailyController
