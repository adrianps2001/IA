--!strict
-- Controles de la persecución: esprint y relevo (solo portador), respuesta a tratos
-- y ocultar los prompts que cuelgan del propio personaje (no te puedes robar a ti mismo).
-- v3.1, pistas: el portador ve "¡Un ladrón cerca!" y oye un latido más rápido cuanto más se
-- acercan; los demás ven las huellas brillantes que va dejando el portador (de cerca).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local RoundState = require(Shared.RoundState)

local UI = require(script.Parent.Parent.UI)
local SoundController = require(script.Parent.SoundController)

local player = Players.LocalPlayer

local ChaseController = {}

local carrierPanel: Frame
local dealPanel: Frame
local dealText: TextLabel
local pendingDeal: number? = nil

local function sprint()
	Remotes.event("RequestSprint"):FireServer()
end

local function pass()
	Remotes.event("RequestPass"):FireServer()
end

local function bindCarrierActions(isCarrier: boolean)
	carrierPanel.Visible = isCarrier
	if isCarrier then
		ContextActionService:BindAction("Sprint", function(_, state)
			if state == Enum.UserInputState.Begin then
				sprint()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
		ContextActionService:BindAction("Pass", function(_, state)
			if state == Enum.UserInputState.Begin then
				pass()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
	else
		ContextActionService:UnbindAction("Sprint")
		ContextActionService:UnbindAction("Pass")
	end
end

local function hideOwnPrompt(instance: Instance)
	if instance:IsA("ProximityPrompt") then
		instance.Enabled = false
		instance:GetPropertyChangedSignal("Enabled"):Connect(function()
			if instance.Enabled then
				instance.Enabled = false
			end
		end)
	end
end

local function onCharacter(character: Model)
	for _, descendant in character:GetDescendants() do
		hideOwnPrompt(descendant)
	end
	character.DescendantAdded:Connect(hideOwnPrompt)
end

-- ---------------------------------------------------------------- pistas (v3.1)
local dangerLabel: TextLabel
local footprints: Folder
local lastStep: { [Player]: number } = {}
local lastBeat = 0

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function carriers(): { Player }
	local list = {}
	for _, id in string.split(tostring(RoundState.get("Carriers") or ""), ",") do
		local p = Players:GetPlayerByUserId(tonumber(id) or 0)
		if p then
			table.insert(list, p)
		end
	end
	return list
end

-- Distancia al ladrón (o zorro) más cercano.
local function nearestThief(root: BasePart, carrierSet: { [Player]: boolean }): number
	local best = math.huge
	for _, other in Players:GetPlayers() do
		if other ~= player and not carrierSet[other] then
			local r = rootOf(other.Character)
			if r then
				best = math.min(best, (r.Position - root.Position).Magnitude)
			end
		end
	end
	local map = workspace:FindFirstChild("Map")
	local foxes = map and map:FindFirstChild("ForestThieves") or workspace:FindFirstChild("ForestThieves")
	if foxes then
		for _, fox in foxes:GetChildren() do
			local r = if fox:IsA("Model") then rootOf(fox) else nil
			if r then
				best = math.min(best, (r.Position - root.Position).Magnitude)
			end
		end
	end
	return best
end

local function footprint(position: Vector3)
	local p = Instance.new("Part")
	p.Name = "Footprint"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.1, 1.4, 1.4)
	p.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 210, 90)
	p.Transparency = 0.2
	p.Parent = footprints
	local born = os.clock()
	task.spawn(function()
		while p.Parent do
			local age = (os.clock() - born) / Config.Chase.FootprintSeconds
			if age >= 1 then
				p:Destroy()
				break
			end
			p.Transparency = 0.2 + 0.8 * age
			task.wait(0.25)
		end
	end)
end

local function updateHints()
	local inChase = RoundState.get("Phase") == "Chase" and player:GetAttribute("InMatch") == true
	local list = if inChase then carriers() else {}
	local carrierSet: { [Player]: boolean } = {}
	for _, c in list do
		carrierSet[c] = true
	end
	local myRoot = rootOf(player.Character)
	-- Portador: aviso y latido si un ladrón se acerca.
	if carrierSet[player] and myRoot then
		local d = nearestThief(myRoot, carrierSet)
		local range = Config.Chase.DangerRange
		dangerLabel.Visible = d < range
		if d < range then
			dangerLabel.Text = if d < Config.Chase.StealRange + 2 then "🚨 ¡Te van a robar! ¡Corre!" else "⚠️ ¡Un ladrón cerca!"
			local every = 0.35 + 0.9 * math.clamp(d / range, 0, 1)
			if os.clock() - lastBeat > every then
				lastBeat = os.clock()
				SoundController.play("Heartbeat", nil, 1.4)
			end
		end
	else
		dangerLabel.Visible = false
	end
	-- Ladrones: huellas de los portadores (solo en el suelo o en una plataforma, no en el aire).
	if not carrierSet[player] then
		for _, c in list do
			local r = rootOf(c.Character)
			local humanoid = c.Character and c.Character:FindFirstChildOfClass("Humanoid")
			if r and humanoid and humanoid.FloorMaterial ~= Enum.Material.Air and myRoot and (r.Position - myRoot.Position).Magnitude < Config.Chase.FootprintSeeRange then
				if os.clock() - (lastStep[c] or 0) > Config.Chase.FootprintEvery then
					lastStep[c] = os.clock()
					footprint(r.Position - Vector3.new(0, humanoid.HipHeight + r.Size.Y / 2 - 0.05, 0))
				end
			end
		end
	end
end

function ChaseController.start()
	local gui = UI.screen("Chase", 2)

	carrierPanel = UI.frame({
		Name = "CarrierActions",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -8, 1, -8),
		Size = UDim2.fromOffset(150, 112),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	UI.list(carrierPanel, 8)
	UI.button({ Size = UDim2.new(1, 0, 0, 50), Text = "⚡ Esprint", LayoutOrder = 1 }, carrierPanel, sprint)
	UI.button({ Size = UDim2.new(1, 0, 0, 50), Text = "🤝 Relevo", LayoutOrder = 2, BackgroundColor3 = UI.Colors.Good }, carrierPanel, pass)

	dealPanel = UI.frame({
		Name = "Deal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(340, 130),
		Visible = false,
	}, gui)
	UI.round(dealPanel, 14)
	UI.stroke(dealPanel, UI.Colors.Gold, 2)
	dealText = UI.label({ Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 60) }, dealPanel)
	local function respond(accept: boolean)
		if pendingDeal then
			Remotes.event("RespondDeal"):FireServer(pendingDeal, accept)
		end
		pendingDeal = nil
		dealPanel.Visible = false
	end
	UI.button({ Position = UDim2.new(0, 12, 1, -54), Size = UDim2.new(0.5, -18, 0, 44), Text = "Aceptar", BackgroundColor3 = UI.Colors.Good }, dealPanel, function()
		respond(true)
	end)
	UI.button({ Position = UDim2.new(0.5, 6, 1, -54), Size = UDim2.new(0.5, -18, 0, 44), Text = "Rechazar", BackgroundColor3 = UI.Colors.Bad }, dealPanel, function()
		respond(false)
	end)

	Remotes.event("DealOffered").OnClientEvent:Connect(function(fromUserId: number, fromName: string)
		pendingDeal = fromUserId
		dealText.Text = string.format("%s te ofrece un trato: si gana, te llevas el 30 %% de su polvo y una copia de la criatura.", fromName)
		dealPanel.Visible = true
		task.delay(15, function()
			if pendingDeal == fromUserId then
				respond(false)
			end
		end)
	end)

	player:GetAttributeChangedSignal("IsCarrier"):Connect(function()
		bindCarrierActions(player:GetAttribute("IsCarrier") == true)
	end)
	bindCarrierActions(player:GetAttribute("IsCarrier") == true)

	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)

	-- Pistas de la persecución.
	dangerLabel = UI.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.26, 0),
		Size = UDim2.fromOffset(420, 44),
		TextColor3 = Color3.fromRGB(255, 120, 110),
		TextStrokeTransparency = 0.2,
		Visible = false,
	}, gui)
	local f = Instance.new("Folder")
	f.Name = "Footprints"
	f.Parent = workspace
	footprints = f
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.15 then
			acc = 0
			updateHints()
		end
	end)
end

return ChaseController
