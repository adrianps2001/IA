--!strict
-- HUD mínimo (GDD 8): bolsa, barra del servidor, temporizador de fase y flecha de objetivo.
-- También muestra avisos del servidor y notificaciones personales.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Rarity = require(Shared.Rarity)
local Remotes = require(Shared.Remotes)
local RoundState = require(Shared.RoundState)

local UI = require(script.Parent.Parent.UI)

local player = Players.LocalPlayer

local HUDController = {}

local STYLE_COLORS: { [string]: Color3 } = {
	info = UI.Colors.Text,
	threshold = UI.Colors.Accent,
	rare = UI.Colors.Gold,
	global = Color3.fromRGB(255, 120, 255),
	quest = UI.Colors.Good,
}

local gui: ScreenGui
local phaseLabel: TextLabel
local timerLabel: TextLabel
local barFill: Frame
local barLabel: TextLabel
local bagFill: Frame
local bagLabel: TextLabel
local affinityLabel: TextLabel
local coinsLabel: TextLabel
local dustLabel: TextLabel
local bannerLabel: TextLabel
local toastList: Frame
local beam: Beam
local targetAttachment: Attachment

local function buildTop()
	local top = UI.frame({
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.5, 0, 0, 74),
	}, gui)
	UI.round(top, 14)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(300, 74)
	constraint.MaxSize = Vector2.new(560, 74)
	constraint.Parent = top

	phaseLabel = UI.label({ Position = UDim2.new(0, 12, 0, 4), Size = UDim2.new(0.7, -12, 0, 28), TextXAlignment = Enum.TextXAlignment.Left }, top)
	timerLabel = UI.label({ Position = UDim2.new(0.7, 0, 0, 4), Size = UDim2.new(0.3, -12, 0, 28), TextXAlignment = Enum.TextXAlignment.Right }, top)

	local bar = UI.frame({ Position = UDim2.new(0, 12, 0, 38), Size = UDim2.new(1, -24, 0, 26), BackgroundColor3 = UI.Colors.PanelLight }, top)
	UI.round(bar, 10)
	barFill = UI.frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = UI.Colors.Accent, BackgroundTransparency = 0 }, bar)
	UI.round(barFill, 10)
	-- Marcas de los umbrales 25/50/75 %.
	for _, threshold in Config.Thresholds do
		if threshold.Fraction < 1 then
			UI.frame({
				Position = UDim2.new(threshold.Fraction, -1, 0, 0),
				Size = UDim2.new(0, 2, 1, 0),
				BackgroundColor3 = UI.Colors.Text,
				BackgroundTransparency = 0.4,
				ZIndex = 3,
			}, bar)
		end
	end
	barLabel = UI.label({ Size = UDim2.fromScale(1, 1), ZIndex = 4 }, bar)
end

local function buildCurrencies()
	local panel = UI.frame({
		Name = "Currencies",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(170, 74),
	}, gui)
	UI.round(panel, 14)
	coinsLabel = UI.label({ Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -20, 0, 30), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = UI.Colors.Gold }, panel)
	dustLabel = UI.label({ Position = UDim2.fromOffset(10, 38), Size = UDim2.new(1, -20, 0, 28), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = UI.Colors.Muted }, panel)
end

local function buildBag()
	local panel = UI.frame({
		Name = "Bag",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 8, 1, -8),
		Size = UDim2.fromOffset(220, 70),
	}, gui)
	UI.round(panel, 14)
	local bar = UI.frame({ Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 28), BackgroundColor3 = UI.Colors.PanelLight }, panel)
	UI.round(bar, 10)
	bagFill = UI.frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 110, 40), BackgroundTransparency = 0 }, bar)
	UI.round(bagFill, 10)
	bagLabel = UI.label({ Size = UDim2.fromScale(1, 1), ZIndex = 3 }, bar)
	affinityLabel = UI.label({ Position = UDim2.fromOffset(10, 40), Size = UDim2.new(1, -20, 0, 22), TextColor3 = UI.Colors.Muted }, panel)
end

local function buildMessages()
	bannerLabel = UI.label({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.new(0.8, 0, 0, 40),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}, gui)

	toastList = UI.frame({
		Name = "Toasts",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -8, 1, -90),
		Size = UDim2.fromOffset(300, 220),
		BackgroundTransparency = 1,
	}, gui)
	local layout = UI.list(toastList, 4)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
end

function HUDController.banner(text: string, style: string?)
	bannerLabel.Text = text
	bannerLabel.TextColor3 = STYLE_COLORS[style or "info"] or UI.Colors.Text
	bannerLabel.TextTransparency = 0
	bannerLabel.TextStrokeTransparency = 0.3
	local token = os.clock()
	bannerLabel:SetAttribute("Token", token)
	task.delay(4, function()
		if bannerLabel:GetAttribute("Token") == token then
			TweenService:Create(bannerLabel, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

function HUDController.toast(text: string, style: string?)
	local frame = UI.frame({ Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 0.25 }, toastList)
	UI.round(frame, 10)
	UI.label({
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -16, 1, -8),
		Text = text,
		TextColor3 = STYLE_COLORS[style or "info"] or UI.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, frame)
	task.delay(5, function()
		frame:Destroy()
	end)
	local toasts: { Instance } = {}
	for _, child in toastList:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts > 5 then
		toasts[1]:Destroy()
	end
end

local function refreshCurrencies()
	coinsLabel.Text = "🪙 " .. UI.formatNumber(tonumber(player:GetAttribute("Coins")) or 0)
	dustLabel.Text = "✨ " .. UI.formatNumber(tonumber(player:GetAttribute("Dust")) or 0) .. " polvo"
end

local function refreshBag()
	local heat = tonumber(player:GetAttribute("Heat")) or 0
	local capacity = tonumber(player:GetAttribute("BagCapacity")) or 100
	bagFill.Size = UDim2.fromScale(math.clamp(heat / math.max(capacity, 1), 0, 1), 1)
	local offering = player:GetAttribute("Offering")
	local suffix = if type(offering) == "string" and offering ~= "" then " + ofrenda" else ""
	bagLabel.Text = string.format("🔥 %d / %d%s", heat, capacity, suffix)
	affinityLabel.Text = string.format("Afinidad con el huevo: %d", tonumber(player:GetAttribute("Affinity")) or 0)
end

local function refreshBar()
	local bar = tonumber(RoundState.get("Bar")) or 0
	local goal = tonumber(RoundState.get("BarGoal")) or 1
	local fraction = math.clamp(bar / math.max(goal, 1), 0, 1)
	TweenService:Create(barFill, TweenInfo.new(0.3), { Size = UDim2.fromScale(fraction, 1) }):Play()
	local minRarity = RoundState.get("MinRarity")
	local rarityText = if type(minRarity) == "string" and Rarity.isValid(minRarity)
		then Rarity.Info[minRarity :: Rarity.RarityName].DisplayName
		else "Común"
	barLabel.Text = string.format("Huevo %d %% · mínimo %s", math.floor(fraction * 100), rarityText)
end

local function mapChild(name: string): Instance?
	local map = workspace:FindFirstChild("Map")
	return map and map:FindFirstChild(name)
end

local function playerByUserId(userId: any): Player?
	if type(userId) ~= "number" or userId == 0 then
		return nil
	end
	return Players:GetPlayerByUserId(userId)
end

-- Flecha de objetivo: un haz desde el jugador hasta lo que le toca hacer ahora.
local function currentTarget(): Vector3?
	local phase = RoundState.phase()
	if phase == "Incubation" then
		local heat = tonumber(player:GetAttribute("Heat")) or 0
		local capacity = tonumber(player:GetAttribute("BagCapacity")) or 100
		local offering = player:GetAttribute("Offering")
		if heat >= capacity * 0.5 or (type(offering) == "string" and offering ~= "") then
			local egg = mapChild("Egg")
			return if egg and egg:IsA("BasePart") then egg.Position else nil
		end
	elseif phase == "Chase" then
		if player:GetAttribute("IsCarrier") then
			local index = player:GetAttribute("NestIndex")
			local nests = mapChild("Nests")
			local nest = nests and nests:FindFirstChild("Nest_" .. tostring(index))
			local floor = nest and nest:FindFirstChild("Floor")
			return if floor and floor:IsA("BasePart") then floor.Position else nil
		end
		local carrier = playerByUserId(RoundState.get("CarrierUserId"))
		local character = carrier and carrier.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return root.Position
		end
		local creature = workspace:FindFirstChild("RoundCreature")
		if creature and creature:IsA("Model") then
			return creature:GetPivot().Position
		end
	end
	return nil
end

local function updateBeam()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local target = currentTarget()
	if not root or not target then
		beam.Enabled = false
		return
	end
	local attachment = root:FindFirstChild("TargetFrom") :: Attachment?
	if not attachment then
		local a = Instance.new("Attachment")
		a.Name = "TargetFrom"
		a.Position = Vector3.new(0, -2, 0)
		a.Parent = root
		attachment = a
	end
	beam.Attachment0 = attachment
	targetAttachment.WorldPosition = target
	beam.Enabled = true
end

function HUDController.start()
	gui = UI.screen("HUD", 1)
	buildTop()
	buildCurrencies()
	buildBag()
	buildMessages()

	local anchor = Instance.new("Part")
	anchor.Name = "TargetAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Parent = workspace.CurrentCamera
	targetAttachment = Instance.new("Attachment")
	targetAttachment.Parent = anchor
	beam = Instance.new("Beam")
	beam.Attachment1 = targetAttachment
	beam.Color = ColorSequence.new(UI.Colors.Gold)
	beam.Transparency = NumberSequence.new(0.2, 0.9)
	beam.Width0 = 1.2
	beam.Width1 = 0.2
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureSpeed = 2
	beam.Enabled = false
	beam.Parent = anchor

	for _, attribute in { "Coins", "Dust" } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshCurrencies)
	end
	for _, attribute in { "Heat", "BagCapacity", "Affinity", "Offering" } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshBag)
	end
	for _, attribute in { "Bar", "BarGoal", "MinRarity" } do
		RoundState.changed(attribute):Connect(refreshBar)
	end

	Remotes.event("Announcement").OnClientEvent:Connect(function(text: string, style: string?)
		HUDController.banner(text, style)
	end)
	Remotes.event("Notify").OnClientEvent:Connect(function(text: string, style: string?)
		HUDController.toast(text, style)
	end)

	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		accumulator = 0
		local phase = RoundState.phase()
		local name = RoundState.PhaseNames[phase] or phase
		if RoundState.get("BloodMoon") then
			name = "🌕 " .. name
		end
		phaseLabel.Text = name
		timerLabel.Text = if phase == "Waiting" then "" else UI.formatTime(RoundState.timeLeft())
		updateBeam()
	end)

	refreshCurrencies()
	refreshBag()
	refreshBar()
end

return HUDController
