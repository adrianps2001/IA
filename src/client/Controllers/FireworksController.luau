--!strict
-- Fuegos artificiales (v3.3, producto de la tienda 🛒): cuando alguien los compra, el servidor
-- avisa a todos (remoto Fireworks) y cada cliente dibuja el espectáculo sobre la plaza del
-- lobby: cohetes que suben y estallan, un cartel enorme con el nombre del comprador y su
-- criatura del hombro gigante girando en el cielo. Solo efectos: nada colisiona.

local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local CosmeticsModel = require(Shared.CosmeticsModel)
local Creature = require(Shared.Creature)
local CreatureModel = require(Shared.CreatureModel)
local Genes = require(Shared.Genes)
local Remotes = require(Shared.Remotes)

local SoundController = require(script.Parent.SoundController)

local FireworksController = {}

local COLORS = {
	Color3.fromRGB(255, 80, 120),
	Color3.fromRGB(255, 210, 60),
	Color3.fromRGB(80, 200, 255),
	Color3.fromRGB(120, 240, 120),
	Color3.fromRGB(200, 120, 255),
	Color3.fromRGB(255, 150, 60),
}

local function center(): Vector3
	return Vector3.new(Config.Lobby.OriginX, 0, Config.Lobby.OriginZ)
end

local function effectPart(parent: Instance, position: Vector3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.Position = position
	p.Parent = parent
	return p
end

-- Un cohete: sube con estela y estalla en una bola de chispas de un color.
local function rocket(folder: Instance, from: Vector3, to: Vector3)
	local color = COLORS[math.random(#COLORS)]
	local head = effectPart(folder, from)
	head.Transparency = 0
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.one * 0.8
	head.Material = Enum.Material.Neon
	head.Color = color
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.4, 0)
	a1.Position = Vector3.new(0, -0.4, 0)
	a0.Parent, a1.Parent = head, head
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	trail.Lifetime = 0.5
	trail.LightEmission = 1
	trail.Parent = head
	local flight = 0.9 + math.random() * 0.5
	local tween = TweenService:Create(head, TweenInfo.new(flight, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = to })
	tween.Completed:Connect(function()
		head.Transparency = 1
		local burst = Instance.new("ParticleEmitter")
		burst.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
		burst.LightEmission = 1
		burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
		burst.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		burst.Lifetime = NumberRange.new(1.2, 1.8)
		burst.Speed = NumberRange.new(22, 30)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Drag = 2.5
		burst.Acceleration = Vector3.new(0, -8, 0)
		burst.Rate = 0
		burst.Parent = head
		burst:Emit(90)
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 40
		light.Brightness = 4
		light.Parent = head
		TweenService:Create(light, TweenInfo.new(0.8), { Brightness = 0 }):Play()
		SoundController.play("Firework", to)
		Debris:AddItem(head, 2.5)
	end)
	tween:Play()
end

local function show(data: any)
	if type(data) ~= "table" then
		return
	end
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		return
	end
	local seconds = Config.Store.FireworksSeconds
	local folder = Instance.new("Folder")
	folder.Name = "Fireworks"
	folder.Parent = lobby
	local sky = center() + Vector3.new(0, 82, 0)

	-- Cartel con el nombre.
	local anchor = effectPart(folder, sky + Vector3.new(0, 22, 0))
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromScale(60, 14)
	board.LightInfluence = 0
	board.AlwaysOnTop = false
	board.MaxDistance = 600
	board.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 225, 70)
	label.TextStrokeTransparency = 0
	label.Text = string.format("🎆 ¡%s! 🎆", tostring(data.Name or "?"))
	label.Parent = board

	-- La criatura del hombro, gigante y girando.
	local model: Model? = nil
	if type(data.Genes) == "string" then
		local ok, genes = pcall(function()
			return HttpService:JSONDecode(data.Genes)
		end)
		if ok and Genes.isValidSet(genes) then
			local built = CreatureModel.build(Creature.new("fireworks", genes, "Fireworks", 0), 6)
			local body = built.PrimaryPart
			if type(data.Hat) == "string" and body then
				CosmeticsModel.buildHat(data.Hat, CosmeticsModel.hatSeat(body), body.Size.X, built)
			end
			for _, d in built:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanTouch = false
					d.CanQuery = false
				end
			end
			built.Parent = folder
			model = built
		end
	end

	local started = os.clock()
	task.spawn(function()
		while os.clock() - started < seconds do
			local m = model
			if m then
				local t = os.clock() - started
				m:PivotTo(CFrame.new(sky + Vector3.new(0, math.sin(t * 1.5) * 2, 0)) * CFrame.Angles(0, t * 0.8, 0))
			end
			task.wait()
		end
	end)
	task.spawn(function()
		while os.clock() - started < seconds - 2 do
			for _ = 1, math.random(2, 4) do
				local angle = math.random() * math.pi * 2
				local r = 30 + math.random() * 40
				local base = center() + Vector3.new(math.cos(angle) * r, 2, math.sin(angle) * r)
				rocket(folder, base, base + Vector3.new(math.random(-8, 8), 60 + math.random() * 40, math.random(-8, 8)))
			end
			task.wait(0.6 + math.random() * 0.5)
		end
	end)
	SoundController.play("Fanfare")
	Debris:AddItem(folder, seconds + 3)
end

function FireworksController.start()
	Remotes.event("Fireworks").OnClientEvent:Connect(show)
end

return FireworksController
