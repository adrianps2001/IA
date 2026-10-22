--!strict
-- El espectáculo de 30 s (GDD 5.3 y 8): el huevo tiembla, un foco recorre a los jugadores
-- como una ruleta y se para en el elegido. El servidor ya decidió; aquí solo se anima.

local CaptureService = game:GetService("CaptureService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Rarity = require(Shared.Rarity)
local Remotes = require(Shared.Remotes)

local UI = require(script.Parent.Parent.UI)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local HatchController = {}

type Candidate = { UserId: number, Name: string, Chance: number }

local overlay: Frame
local title: TextLabel
local subtitle: TextLabel
local chanceLabel: TextLabel
local captureButton: TextButton
local running = false

local function egg(): BasePart?
	local map = workspace:FindFirstChild("Map")
	local part = map and map:FindFirstChild("Egg")
	return if part and part:IsA("BasePart") then part else nil
end

local function rootOf(userId: number): BasePart?
	local target = Players:GetPlayerByUserId(userId)
	local character = target and target.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function makeSpotlight(): Part
	local spot = Instance.new("Part")
	spot.Name = "ElectionSpotlight"
	spot.Anchored = true
	spot.CanCollide = false
	spot.CanQuery = false
	spot.CanTouch = false
	spot.Shape = Enum.PartType.Cylinder
	spot.Size = Vector3.new(60, 7, 7)
	spot.Material = Enum.Material.Neon
	spot.Color = Color3.fromRGB(255, 230, 140)
	spot.Transparency = 0.6
	spot.Parent = workspace
	return spot
end

local function placeSpot(spot: Part, position: Vector3)
	-- Cilindro vertical: el eje X del cilindro apunta hacia arriba.
	spot.CFrame = CFrame.new(position + Vector3.new(0, 28, 0)) * CFrame.Angles(0, 0, math.rad(90))
end

local function show(text: string, sub: string, color: Color3?)
	title.Text = text
	title.TextColor3 = color or UI.Colors.Text
	subtitle.Text = sub
end

local function play(data: any)
	if running then
		return
	end
	running = true
	local duration = tonumber(data.Duration) or 30
	local order: { Candidate } = data.Order or {}
	local chosenId: number = tonumber(data.ChosenUserId) or 0
	local rarity: Rarity.RarityName = if Rarity.isValid(data.Rarity) then data.Rarity else "Common"
	local info = Rarity.Info[rarity]

	overlay.Visible = true
	captureButton.Visible = false
	local mine = 0
	for _, candidate in order do
		if candidate.UserId == player.UserId then
			mine = candidate.Chance
		end
	end
	chanceLabel.Text = string.format("Tu probabilidad: %.1f %%", mine * 100)

	-- Fase 1 (60 %): el huevo tiembla y la cámara orbita.
	local eggPart = egg()
	local originalCFrame = if eggPart then eggPart.CFrame else CFrame.new()
	camera.CameraType = Enum.CameraType.Scriptable
	local shakeEnd = os.clock() + duration * 0.6
	show("¿A QUIÉN ELEGIRÁ?", "El huevo se está agrietando...", UI.Colors.Accent)
	local angle = 0
	local connection = RunService.RenderStepped:Connect(function(dt)
		if not eggPart then
			return
		end
		angle += dt * 0.4
		local center = originalCFrame.Position
		camera.CFrame = CFrame.lookAt(center + Vector3.new(math.cos(angle) * 34, 14, math.sin(angle) * 34), center)
		local remaining = shakeEnd - os.clock()
		if remaining > 0 then
			local intensity = 0.15 + (1 - remaining / (duration * 0.6)) * 0.6
			eggPart.CFrame = originalCFrame * CFrame.Angles(
				math.rad(math.random(-10, 10) * intensity),
				0,
				math.rad(math.random(-10, 10) * intensity)
			)
		end
	end)
	task.wait(duration * 0.6)
	connection:Disconnect()
	if eggPart then
		eggPart.CFrame = originalCFrame
	end

	-- Fase 2 (30 %): ruleta con un foco que se va frenando hasta el elegido.
	local spot = makeSpotlight()
	local rouletteTime = duration * 0.3
	local steps = math.max(#order * 3, 12)
	local chosenIndex = 1
	for index, candidate in order do
		if candidate.UserId == chosenId then
			chosenIndex = index
		end
	end
	-- Ajusta el número de pasos para acabar exactamente en el elegido.
	if #order > 0 then
		steps += (chosenIndex - (steps % #order) - 1) % #order + 1
	end
	for step = 1, steps do
		local candidate = order[((step - 1) % math.max(#order, 1)) + 1]
		local root = candidate and rootOf(candidate.UserId)
		if root then
			placeSpot(spot, root.Position)
			camera.CFrame = CFrame.lookAt(root.Position + Vector3.new(0, 12, 18), root.Position)
			show(string.upper(candidate.Name), string.format("%.1f %%", candidate.Chance * 100), UI.Colors.Gold)
		end
		-- Intervalos crecientes: suspense al final.
		local t = step / steps
		local interval = (rouletteTime / steps) * (0.4 + 1.2 * t * t)
		task.wait(interval)
	end

	-- Fase 3: revelación.
	local chosenRoot = rootOf(chosenId)
	if chosenRoot then
		placeSpot(spot, chosenRoot.Position)
		camera.CFrame = CFrame.lookAt(chosenRoot.Position + Vector3.new(0, 8, 14), chosenRoot.Position)
	end
	spot.Color = UI.rgb(info.Color)
	local creatureName = tostring(data.CreatureName or "")
	if chosenId == player.UserId then
		show("¡EL HUEVO TE HA ELEGIDO!", string.format("%s (%s) · ¡Corre a tu nido!", creatureName, info.DisplayName), UI.Colors.Gold)
	else
		show(
			string.format("¡EL HUEVO ELIGE A %s!", string.upper(tostring(data.ChosenName or "?"))),
			string.format("%s (%s) · ¡Róbasela!", creatureName, info.DisplayName),
			UI.rgb(info.Color)
		)
	end
	captureButton.Visible = true
	task.wait(math.max(duration - duration * 0.9 - 0.2, 1.5))

	spot:Destroy()
	camera.CameraType = Enum.CameraType.Custom
	TweenService:Create(title, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
	task.wait(0.5)
	title.TextTransparency = 0
	overlay.Visible = false
	running = false
end

function HatchController.start()
	local gui = UI.screen("Hatch", 5)
	overlay = UI.frame({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, gui)
	title = UI.label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.12, 0), Size = UDim2.new(0.9, 0, 0, 70), TextStrokeTransparency = 0 }, overlay)
	subtitle = UI.label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.12, 74), Size = UDim2.new(0.8, 0, 0, 36), TextStrokeTransparency = 0.2 }, overlay)
	chanceLabel = UI.label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.92, 0),
		Size = UDim2.new(0.6, 0, 0, 32),
		TextColor3 = UI.Colors.Muted,
	}, overlay)
	captureButton = UI.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.84, 0),
		Size = UDim2.fromOffset(200, 48),
		Text = "📸 Captura",
		Visible = false,
	}, overlay, function()
		pcall(function()
			CaptureService:CaptureScreenshot(function(contentId)
				CaptureService:PromptSaveCapturesToGallery({ contentId }, function() end)
			end)
		end)
	end)

	Remotes.event("HatchSequence").OnClientEvent:Connect(function(data)
		task.spawn(play, data)
	end)
end

return HatchController
