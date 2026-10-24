--!strict
-- Tutorial de la primera partida (v3.1). Mientras el jugador no haya acabado ninguna ronda
-- (atributo RoundsPlayed = 0), un cartel le dice qué hacer en cada momento y una flecha de luz
-- le señala adónde ir. Cada paso se da por hecho cuando pasa lo que pide (cogió Calor, lo
-- depositó, subió a un árbol…), así que no hay que pulsar nada. Se puede saltar con "Saltar".
-- Todo es local: no hay remotos ni datos nuevos.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local RoundState = require(Shared.RoundState)

local UI = require(script.Parent.Parent.UI)

local player = Players.LocalPlayer

local TutorialController = {}

type Step = {
	Id: string,
	Text: string,
	-- ¿Toca este paso ahora? (según la fase y si estás en partida)
	When: () -> boolean,
	-- ¿Ya está hecho?
	Done: () -> boolean,
	-- Adónde apunta la flecha (nil = sin flecha).
	Target: (() -> Vector3?)?,
	-- Segundos como mucho (pasos que no dependen del jugador).
	MaxSeconds: number?,
}

local panel: Frame
local label: TextLabel
local progress: TextLabel
local skipped = false
local forced = false -- "Ver el tutorial otra vez" (ajustes ⚙️)
local done: { [string]: boolean } = {}
local beam: Beam?
local fromAttachment: Attachment?
local toAttachment: Attachment?
local stepStarted: { [string]: number } = {}

local function inMatch(): boolean
	return player:GetAttribute("InMatch") == true
end

local function phase(): string
	return tostring(RoundState.get("Phase") or "")
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function map(): Instance?
	return workspace:FindFirstChild("Map")
end

-- La brasa (o fuente de Calor) libre más cercana.
local function nearestSource(): Vector3?
	local root = rootPart()
	local m = map()
	local folder = m and m:FindFirstChild("HeatSources")
	if not root or not folder then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") and part.Name == "Ember" and not part:GetAttribute("Taken") and part.Transparency < 1 then
			local d = (part.Position - root.Position).Magnitude
			if d < bestDistance then
				best, bestDistance = part.Position, d
			end
		end
	end
	return best
end

local function eggPosition(): Vector3?
	local m = map()
	local egg = m and m:FindFirstChild("Egg")
	return if egg and egg:IsA("BasePart") then egg.Position else nil
end

-- El principio de la rampa más cercana (el tablón más bajo).
local function nearestRamp(): Vector3?
	local root = rootPart()
	local m = map()
	if not root or not m then
		return nil
	end
	local best, bestScore = nil, math.huge
	for _, part in m:GetDescendants() do
		if part:IsA("BasePart") and part.Name == "Ramp" and part.Position.Y < 8 then
			local d = (part.Position - root.Position).Magnitude
			if d < bestScore then
				best, bestScore = part.Position, d
			end
		end
	end
	return best
end

local function carrierPosition(): Vector3?
	local ids = string.split(tostring(RoundState.get("Carriers") or ""), ",")
	local root = rootPart()
	local best, bestDistance = nil, math.huge
	for _, id in ids do
		local other = Players:GetPlayerByUserId(tonumber(id) or 0)
		local character = other and other.Character
		local r = character and character:FindFirstChild("HumanoidRootPart")
		if other ~= player and r and r:IsA("BasePart") and root then
			local d = (r.Position - root.Position).Magnitude
			if d < bestDistance then
				best, bestDistance = r.Position, d
			end
		end
	end
	return best
end

local function isCarrier(): boolean
	for _, id in string.split(tostring(RoundState.get("Carriers") or ""), ",") do
		if tonumber(id) == player.UserId then
			return true
		end
	end
	return false
end

local STEPS: { Step } = {
	{
		Id = "play",
		Text = "👋 ¡Bienvenido! Este es tu nido: aquí lucirás tus criaturas. Pulsa ⚔️ JUGAR (abajo) para tu primera partida.",
		When = function()
			return not inMatch()
		end,
		Done = function()
			return inMatch() or player:GetAttribute("Queued") == true
		end,
	},
	{
		Id = "ember",
		Text = "🔥 Recoge brasas: son las bolitas naranjas. Sigue la flecha.",
		When = function()
			return inMatch() and phase() == "Incubation"
		end,
		Done = function()
			return (tonumber(player:GetAttribute("Heat")) or 0) > 0 or (tonumber(player:GetAttribute("Affinity")) or 0) > 0
		end,
		Target = nearestSource,
	},
	{
		Id = "deposit",
		Text = "🥚 Lleva el Calor al huevo gigante y pulsa E. Cuanto más le des, más probable es que te elija.",
		When = function()
			return inMatch() and phase() == "Incubation"
		end,
		Done = function()
			return (tonumber(player:GetAttribute("Affinity")) or 0) > 0
		end,
		Target = eggPosition,
	},
	{
		Id = "climb",
		Text = "🌳 Arriba hay brasas azules (valen el doble) y moradas (el doble otra vez). Sube por la rampa de un árbol.",
		When = function()
			return inMatch() and phase() == "Incubation"
		end,
		Done = function()
			local root = rootPart()
			return root ~= nil and root.Position.Y > 30
		end,
		Target = nearestRamp,
		MaxSeconds = 60,
	},
	{
		Id = "zip",
		Text = "🚡 Para bajar rápido: tirolinas (E en el poste de lo más alto), toboganes y setas rojas que te lanzan. ¡Sigue juntando Calor!",
		When = function()
			return inMatch() and phase() == "Incubation"
		end,
		Done = function()
			return false
		end,
		MaxSeconds = 12,
	},
	{
		Id = "hatch",
		Text = "🐣 ¡El huevo se abre! Mira la criatura en el centro: el foco busca a quién se une.",
		When = function()
			return inMatch() and phase() == "Hatch"
		end,
		Done = function()
			return phase() ~= "Hatch"
		end,
	},
	{
		Id = "chase",
		Text = "",
		When = function()
			return inMatch() and phase() == "Chase"
		end,
		Done = function()
			return phase() ~= "Chase"
		end,
		Target = function()
			return if isCarrier() then nil else carrierPosition()
		end,
	},
	{
		Id = "results",
		Text = "🏆 ¡Ya sabes jugar! Si ganas una criatura, la verás en tu nido del lobby. Si no, te llevas polvo de cáscara para huevos.",
		When = function()
			return inMatch() and (phase() == "Results" or phase() == "Loot")
		end,
		Done = function()
			return false
		end,
		MaxSeconds = 10,
	},
}

local function chaseText(): string
	if isCarrier() then
		return "🏃 ¡Te ha elegido a ti! Escóndete por los árboles: cada 8 s todos te ven un momento. Si la tienes al acabar, es tuya. Shift = esprint."
	end
	return "🦹 Busca al portador: brilla cada 8 s y deja una marca 📍. Toca E junto a él y quédate cerca para robársela."
end

local function clearArrow()
	if beam then
		beam.Enabled = false
	end
end

local function pointAt(target: Vector3)
	local root = rootPart()
	if not root then
		clearArrow()
		return
	end
	if not fromAttachment or fromAttachment.Parent ~= root then
		if fromAttachment then
			fromAttachment:Destroy()
		end
		local a = Instance.new("Attachment")
		a.Name = "TutorialFrom"
		a.Position = Vector3.new(0, -2.5, 0)
		a.Parent = root
		fromAttachment = a
	end
	if not toAttachment then
		local a = Instance.new("Attachment")
		a.Name = "TutorialTo"
		a.Parent = workspace.Terrain
		toAttachment = a
	end
	if not beam then
		local b = Instance.new("Beam")
		b.Name = "TutorialArrow"
		b.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 140, 40))
		b.LightEmission = 1
		b.Transparency = NumberSequence.new(0.15, 0.6)
		b.Width0 = 1.2
		b.Width1 = 0.4
		b.FaceCamera = true
		b.Segments = 12
		b.TextureMode = Enum.TextureMode.Wrap
		b.Parent = workspace.Terrain
		beam = b
	end
	local b = beam :: Beam
	local to = toAttachment :: Attachment
	to.WorldPosition = target + Vector3.new(0, 1, 0)
	b.Attachment0 = fromAttachment
	b.Attachment1 = to
	b.Enabled = true
end

local function finished(): boolean
	if forced then
		return skipped
	end
	return skipped or (tonumber(player:GetAttribute("RoundsPlayed")) or 0) > 0
end

-- Vuelve a empezar el tutorial (botón de los ajustes).
function TutorialController.restart()
	skipped = false
	forced = true
	done = {}
	stepStarted = {}
end

local function update()
	if finished() then
		panel.Visible = false
		clearArrow()
		return
	end
	local now = os.clock()
	local current: Step? = nil
	local index = 0
	for i, step in STEPS do
		if not done[step.Id] and step.When() then
			stepStarted[step.Id] = stepStarted[step.Id] or now
			local timedOut = step.MaxSeconds ~= nil and now - stepStarted[step.Id] > (step.MaxSeconds :: number)
			if step.Done() or timedOut then
				done[step.Id] = true
				if step.Id == "results" then
					forced = false
				end
			else
				current, index = step, i
				break
			end
		end
	end
	if not current then
		panel.Visible = false
		clearArrow()
		return
	end
	local step = current :: Step
	panel.Visible = true
	label.Text = if step.Id == "chase" then chaseText() else step.Text
	progress.Text = string.format("Tutorial %d/%d", index, #STEPS)
	local target = if step.Target then step.Target() else nil
	if target then
		pointAt(target)
	else
		clearArrow()
	end
end

function TutorialController.start()
	local gui = UI.screen("Tutorial", 4)
	panel = UI.frame({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 140),
		Size = UDim2.new(0.6, 0, 0, 76),
		BackgroundColor3 = Color3.fromRGB(40, 30, 50),
		BackgroundTransparency = 0.15,
		Visible = false,
	}, gui)
	UI.round(panel, 14)
	UI.stroke(panel, UI.Colors.Gold, 2)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(620, 120)
	limit.MinSize = Vector2.new(300, 60)
	limit.Parent = panel
	progress = UI.label({ Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -110, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.Colors.Gold, Text = "" }, panel)
	label = UI.label({ Position = UDim2.fromOffset(12, 22), Size = UDim2.new(1, -24, 1, -28), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Text = "" }, panel)
	UI.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 4), Size = UDim2.fromOffset(90, 24), Text = "Saltar ✕", BackgroundColor3 = UI.Colors.PanelLight }, panel, function()
		skipped = true
		update()
	end)
	-- Cada pocos fotogramas basta: no hace falta precisión.
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.25 then
			acc = 0
			update()
		end
	end)
end

return TutorialController
