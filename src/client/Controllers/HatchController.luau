--!strict
-- La eclosión (GDD 5.3, 8 y v2): 10 s. El huevo tiembla y un foco salta entre los
-- favoritos hasta pararse en cada elegido. El servidor ya decidió; aquí solo se anima.
-- Al romperse el huevo, la criatura (o criaturas) aparece en su sitio, en grande y girando,
-- para que todo el servidor la vea mientras se decide a quién se une.

local CaptureService = game:GetService("CaptureService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Creature = require(Shared.Creature)
local CreatureModel = require(Shared.CreatureModel)
local Genes = require(Shared.Genes)
local Rarity = require(Shared.Rarity)
local Remotes = require(Shared.Remotes)

local UI = require(script.Parent.Parent.UI)

local player = Players.LocalPlayer

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

-- Tamaño de la criatura revelada y separación cuando nacen varias a la vez.
local REVEAL_SCALE = 2.2
local REVEAL_SPACING = 9

-- Saca las criaturas del huevo: lo esconde (solo en este cliente) y pone los modelos sobre
-- el pedestal. Devuelve una función que lo deshace.
local function reveal(eggPart: BasePart?, picks: { any }): () -> ()
	if not eggPart then
		return function() end
	end
	local base = eggPart.Position - Vector3.new(0, eggPart.Size.Y / 2, 0)
	eggPart.LocalTransparencyModifier = 1
	local light = eggPart:FindFirstChildOfClass("PointLight")
	local models: { { Model: Model, Foot: number, Seat: Vector3 } } = {}
	for index, pick in picks do
		if Genes.isValidSet(pick.Genes) then
			local rarity = if Rarity.isValid(pick.Rarity) then pick.Rarity else "Common"
			local model = CreatureModel.build(Creature.new("reveal" .. index, pick.Genes, "Hatch", 0), REVEAL_SCALE)
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.CanCollide = false
					descendant.CanQuery = false
					descendant.CanTouch = false
				end
			end
			-- Un brillo del color de su rareza para que se vea desde lejos.
			local glow = Instance.new("PointLight")
			glow.Range = 24
			glow.Brightness = 2
			glow.Color = UI.rgb(Rarity.Info[rarity].Color)
			glow.Parent = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
			model.Name = "HatchReveal"
			model.Parent = workspace
			local offset = (index - (#picks + 1) / 2) * REVEAL_SPACING
			table.insert(models, { Model = model, Foot = CreatureModel.footOffset(model), Seat = base + Vector3.new(offset, 0, 0) })
		end
	end
	local born = os.clock()
	local spin = RunService.RenderStepped:Connect(function()
		local t = os.clock() - born
		-- Sale de un salto y luego gira despacio mirando a todos.
		local pop = math.max(0, 1 - t / 0.5)
		local hop = math.sin(math.min(t / 0.5, 1) * math.pi) * 3 * pop + math.abs(math.sin(t * 2.2)) * 0.6
		for _, entry in models do
			entry.Model:PivotTo(CFrame.new(entry.Seat + Vector3.new(0, entry.Foot + hop, 0)) * CFrame.Angles(0, t * 0.9, 0))
		end
	end)
	if light then
		light.Enabled = false
	end
	return function()
		spin:Disconnect()
		for _, entry in models do
			entry.Model:Destroy()
		end
		eggPart.LocalTransparencyModifier = 0
		if light then
			light.Enabled = true
		end
	end
end

local function show(text: string, sub: string, color: Color3?)
	title.Text = text
	title.TextColor3 = color or UI.Colors.Text
	subtitle.Text = sub
end

-- Favoritos: los 5 con más probabilidad, más los elegidos si no están entre ellos.
local function shortlist(order: { Candidate }, picks: { any }): { Candidate }
	local sorted = table.clone(order)
	table.sort(sorted, function(a: Candidate, b: Candidate)
		return a.Chance > b.Chance
	end)
	local list: { Candidate } = {}
	for i = 1, math.min(5, #sorted) do
		table.insert(list, sorted[i])
	end
	for _, pick in picks do
		local found = false
		for _, candidate in list do
			if candidate.UserId == pick.UserId then
				found = true
			end
		end
		if not found then
			for _, candidate in order do
				if candidate.UserId == pick.UserId then
					table.insert(list, candidate)
				end
			end
		end
	end
	return list
end

-- GDD v2: 10 segundos y sin bloquear la cámara (antes 30 s mirando una ruleta). El huevo se
-- agrieta, un foco salta entre los favoritos y se para en cada elegido.
local function play(data: any)
	if running then
		return
	end
	running = true
	local duration = tonumber(data.Duration) or 10
	local order: { Candidate } = data.Order or {}
	local picks: { any } = data.Picks or {}

	overlay.Visible = true
	captureButton.Visible = false
	local mine = 0
	for _, candidate in order do
		if candidate.UserId == player.UserId then
			mine = candidate.Chance
		end
	end
	chanceLabel.Text = string.format("Tu probabilidad: %.1f %%", mine * 100)

	-- Fase 1 (20 %): el huevo tiembla. La cámara sigue siendo tuya: puedes ir colocándote.
	local eggPart = egg()
	local originalCFrame = if eggPart then eggPart.CFrame else CFrame.new()
	local crackTime = duration * 0.2
	local shakeEnd = os.clock() + crackTime
	show(if #picks > 1 then string.format("¡%d CRIATURAS!", #picks) else "¿A QUIÉN ELEGIRÁ?", "El huevo se está agrietando...", UI.Colors.Accent)
	local connection = RunService.RenderStepped:Connect(function()
		if not eggPart then
			return
		end
		local remaining = shakeEnd - os.clock()
		if remaining > 0 then
			local intensity = 0.3 + (1 - remaining / crackTime) * 0.7
			eggPart.CFrame = originalCFrame * CFrame.Angles(math.rad(math.random(-10, 10) * intensity), 0, math.rad(math.random(-10, 10) * intensity))
		end
	end)
	task.wait(crackTime)
	connection:Disconnect()
	if eggPart then
		eggPart.CFrame = originalCFrame
	end
	-- ¡Crac! La criatura sale del huevo y se queda en el centro hasta que empieza la persecución.
	local hide = reveal(eggPart, picks)

	-- Fase 2 (60 %): un foco por criatura salta entre los favoritos y se para en su elegido.
	local candidates = shortlist(order, picks)
	local spots: { Part } = {}
	local perPick = duration * 0.6 / math.max(#picks, 1)
	for _, pick in picks do
		local spot = makeSpotlight()
		table.insert(spots, spot)
		local rarity: Rarity.RarityName = if Rarity.isValid(pick.Rarity) then pick.Rarity else "Common"
		local steps = math.max(#candidates * 2, 6)
		local chosenIndex = 1
		for index, candidate in candidates do
			if candidate.UserId == pick.UserId then
				chosenIndex = index
			end
		end
		-- Ajusta el número de pasos para acabar exactamente en el elegido.
		if #candidates > 0 then
			steps += (chosenIndex - (steps % #candidates) - 1) % #candidates + 1
		end
		for step = 1, steps do
			local candidate = candidates[((step - 1) % math.max(#candidates, 1)) + 1]
			local root = candidate and rootOf(candidate.UserId)
			if root then
				placeSpot(spot, root.Position)
				show(string.upper(candidate.Name), string.format("%.1f %%", candidate.Chance * 100), UI.Colors.Gold)
			end
			-- Intervalos crecientes: suspense al final.
			local t = step / steps
			task.wait((perPick / steps) * (0.4 + 1.2 * t * t))
		end
		local chosenRoot = rootOf(pick.UserId)
		if chosenRoot then
			placeSpot(spot, chosenRoot.Position)
		end
		local info = Rarity.Info[rarity]
		spot.Color = UI.rgb(info.Color)
		if pick.UserId == player.UserId then
			show("¡EL HUEVO TE HA ELEGIDO!", string.format("%s (%s) · ¡Escóndete y aguanta hasta el final!", tostring(pick.CreatureName), info.DisplayName), UI.Colors.Gold)
		else
			show(string.format("¡ELIGE A %s!", string.upper(tostring(pick.Name))), string.format("%s (%s) · ¡Róbasela!", tostring(pick.CreatureName), info.DisplayName), UI.rgb(info.Color))
		end
	end

	-- Fase 3: la revelación se queda en pantalla hasta que empieza la persecución.
	captureButton.Visible = true
	task.wait(math.max(duration * 0.2 - 0.3, 0.8))
	for _, spot in spots do
		spot:Destroy()
	end
	hide()
	TweenService:Create(title, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
	task.wait(0.3)
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
