--!strict
-- Calor, el recurso de ronda (GDD 5.1): fuentes repartidas por el mapa, bolsa limitada,
-- depósito en el huevo (Afinidad) y empujones a quien lleva la bolsa llena.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Genes = require(Shared.Genes)
local MapLayout = require(Shared.MapLayout)

local AnalyticsHelper = require(script.Parent.Parent.Util.Analytics)
local AnnouncementService = require(script.Parent.AnnouncementService)
local CommunityService = require(script.Parent.CommunityService)
local DataService = require(script.Parent.DataService)
local EggService = require(script.Parent.EggService)
local MapService = require(script.Parent.MapService)
local MonetizationService = require(script.Parent.MonetizationService)
local QuestService = require(script.Parent.QuestService)

type PlayerState = {
	Heat: number,
	Affinity: number,
	Offering: string?,
	LastBumped: number,
}

local HeatService = {}

local random = Random.new()
local active = false
-- Recolocan las fuentes que nadie ha cogido (se llaman al empezar cada ronda).
local relocators: { () -> () } = {}
local states: { [Player]: PlayerState } = {}

local function state(player: Player): PlayerState
	local s = states[player]
	if not s then
		s = { Heat = 0, Affinity = 0, Offering = nil :: string?, LastBumped = 0 }
		states[player] = s
	end
	return s
end

local function playerFromPart(part: BasePart): Player?
	local model = part:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return Players:GetPlayerFromCharacter(model)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function HeatService.capacity(player: Player): number
	local profile = DataService.get(player)
	local level = if profile then profile.Upgrades.Bag else 0
	return Economy.bagCapacity(level, MonetizationService.hasPass(player, "BigBag"))
end

local function sync(player: Player)
	local s = state(player)
	local capacity = HeatService.capacity(player)
	player:SetAttribute("Heat", s.Heat)
	player:SetAttribute("BagCapacity", capacity)
	player:SetAttribute("Affinity", s.Affinity)
	player:SetAttribute("Offering", s.Offering or "")
	player:SetAttribute("BagFull", s.Heat >= capacity)
end

-- Suma Calor a la bolsa respetando la capacidad. Devuelve lo que realmente entró.
function HeatService.give(player: Player, amount: number): number
	if not active then
		return 0
	end
	local s = state(player)
	local room = HeatService.capacity(player) - s.Heat
	local added = math.clamp(math.floor(amount), 0, math.max(room, 0))
	if added > 0 then
		s.Heat += added
		sync(player)
	end
	return added
end

function HeatService.affinity(player: Player): number
	return state(player).Affinity
end

function HeatService.deposit(player: Player)
	if not active then
		return
	end
	local s = state(player)
	local root = rootOf(player)
	if not root or (root.Position - MapService.EggCenter).Magnitude > Config.Heat.DepositRadius + 10 then
		return
	end

	if s.Offering then
		local offering = (Genes.Offerings :: any)[s.Offering]
		if offering then
			EggService.addOffering(offering.Slot, offering.Gene)
			AnnouncementService.server(string.format("%s ha ofrendado un %s al huevo.", player.DisplayName, tostring(offering.DisplayName)), "info")
		end
		s.Offering = nil
	end

	local amount = s.Heat
	if amount > 0 then
		s.Heat = 0
		s.Affinity += amount
		EggService.addHeat(amount)
		CommunityService.contribute(player, amount)
		DataService.addStat(player, "HeatDeposited", amount)
		QuestService.progress(player, "DepositHeat", amount)
		local profile = DataService.get(player)
		if profile and not profile.Funnel.FirstDeposit then
			profile.Funnel.FirstDeposit = true
			AnalyticsHelper.funnel(player, 2, "Primer depósito")
		end
	end
	sync(player)
end

-- Fuentes de Calor ---------------------------------------------------------------------

local function makePickup(name: string, color: Color3, size: Vector3, shape: Enum.PartType): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Parent = MapService.SourcesFolder
	return p
end

-- Coloca una fuente y la reaparece tras recogerla.
local function spawnSource(
	name: string,
	color: Color3,
	size: Vector3,
	shape: Enum.PartType,
	position: () -> Vector3,
	respawn: number,
	onCollect: (Player, Part) -> boolean
): Part
	local p = makePickup(name, color, size, shape)
	-- Evita aparecer dentro de un árbol o una roca, donde nadie podría cogerla.
	local function place()
		local point = position()
		for _ = 1, 8 do
			if MapService.isClear(point, 2.5) then
				break
			end
			point = position()
		end
		p.Position = point + Vector3.new(0, size.Y / 2 + 0.5, 0)
	end
	place()
	local taken = false
	table.insert(relocators, function()
		if not taken then
			place()
		end
	end)
	p.Touched:Connect(function(hit)
		if taken or not active or not hit:IsA("BasePart") then
			return
		end
		local player = playerFromPart(hit)
		if player and onCollect(player, p) then
			taken = true
			p.Transparency = 1
			task.delay(respawn, function()
				place()
				p.Transparency = 0
				taken = false
			end)
		end
	end)
	return p
end

local function spawnEmbers()
	local def = Config.Heat.Ember
	for _ = 1, def.Count do
		spawnSource("Ember", Color3.fromRGB(255, 120, 30), Vector3.new(1.4, 1.4, 1.4), Enum.PartType.Ball, function()
			return MapService.randomGroundPoint(MapLayout.SourceRing.Min, MapLayout.SourceRing.Max)
		end, def.Respawn, function(player)
			return HeatService.give(player, def.Amount) > 0
		end)
	end
end

local function spawnFireflies()
	local def = Config.Heat.Firefly
	local swamp = MapService.Zones.Swamp
	for _ = 1, def.Count do
		local fly = spawnSource("Firefly", Color3.fromRGB(230, 255, 120), Vector3.new(0.9, 0.9, 0.9), Enum.PartType.Ball, function()
			return MapService.randomPointNear(swamp, 20)
		end, def.Respawn, function(player)
			return HeatService.give(player, def.Amount) > 0
		end)
		-- Revolotean: hay que perseguirlas.
		task.spawn(function()
			while fly.Parent do
				local target = MapService.randomPointNear(swamp, 20) + Vector3.new(0, random:NextNumber(1.5, 4), 0)
				local tween = TweenService:Create(fly, TweenInfo.new(random:NextNumber(2, 4), Enum.EasingStyle.Sine), { Position = target })
				tween:Play()
				tween.Completed:Wait()
			end
		end)
	end
end

local function spawnLuckyBlocks()
	local def = Config.Heat.LuckyBlock
	for _ = 1, def.Count do
		local block = spawnSource("LuckyBlock", Color3.fromRGB(255, 210, 40), Vector3.new(3, 3, 3), Enum.PartType.Block, function()
			return MapService.randomGroundPoint(MapLayout.SourceRing.Min, MapLayout.SourceRing.Max)
		end, def.Respawn, function(player)
			local amount = random:NextInteger(def.Min, def.Max)
			local added = HeatService.give(player, amount)
			if added <= 0 then
				return false
			end
			QuestService.progress(player, "LuckyBlock", 1)
			AnnouncementService.player(player, string.format("¡Bloque de suerte! +%d Calor", added), if amount >= 40 then "rare" else "info")
			return true
		end)
		block.Material = Enum.Material.SmoothPlastic
		for _, face in Enum.NormalId:GetEnumItems() do
			local gui = Instance.new("SurfaceGui")
			gui.Face = face
			gui.CanvasSize = Vector2.new(100, 100)
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Text = "?"
			label.Font = Enum.Font.FredokaOne
			label.TextScaled = true
			label.TextColor3 = Color3.new(1, 1, 1)
			label.Parent = gui
			gui.Parent = block
		end
	end
end

-- Géiseres: hacen falta dos jugadores activándolos casi a la vez.
local function spawnGeysers()
	local def = Config.Heat.Geyser
	for _, point in MapLayout.geyserPositions() do
		local pos = Vector3.new(point.X, 0, point.Z)
		local geyser = Instance.new("Part")
		geyser.Name = "Geyser"
		geyser.Shape = Enum.PartType.Cylinder
		geyser.Size = Vector3.new(1.5, 8, 8)
		geyser.CFrame = CFrame.new(pos + Vector3.new(0, 0.75, 0)) * CFrame.Angles(0, 0, math.rad(90))
		geyser.Color = Color3.fromRGB(90, 160, 200)
		geyser.Material = Enum.Material.Slate
		geyser.Anchored = true
		geyser.Parent = MapService.SourcesFolder

		local steam = Instance.new("ParticleEmitter")
		steam.Rate = 0
		steam.Speed = NumberRange.new(20, 30)
		steam.Lifetime = NumberRange.new(1, 1.6)
		steam.EmissionDirection = Enum.NormalId.Right -- el cilindro está girado
		steam.Size = NumberSequence.new(2, 5)
		steam.Transparency = NumberSequence.new(0.2, 1)
		steam.Parent = geyser

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Activar géiser (hacen falta 2)"
		prompt.ObjectText = "Géiser"
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = geyser

		local cooldownUntil = 0
		local activators: { [Player]: number } = {}
		prompt.Triggered:Connect(function(player)
			if not active then
				return
			end
			local now = os.clock()
			if now < cooldownUntil then
				AnnouncementService.player(player, "El géiser se está recargando.")
				return
			end
			activators[player] = now
			local ready = {}
			for other, at in activators do
				if now - at <= def.Window and other.Parent then
					table.insert(ready, other)
				end
			end
			if #ready < def.PlayersNeeded then
				AnnouncementService.player(player, "¡Necesitas a alguien más activando el géiser!")
				return
			end
			cooldownUntil = now + def.Cooldown
			table.clear(activators)
			steam:Emit(60)
			for _, p in ready do
				local added = HeatService.give(p, def.Amount)
				AnnouncementService.player(p, string.format("¡Géiser en equipo! +%d Calor", added))
			end
		end)
	end
end

-- Objetos de ofrenda en su zona (cristal en la cueva, pluma en el pantano, hueso en las ruinas).
local function spawnOfferings()
	local placements = {
		{ Kind = "Crystal", Zone = "CrystalCave", Color = Color3.fromRGB(140, 220, 255) },
		{ Kind = "Feather", Zone = "Swamp", Color = Color3.fromRGB(255, 255, 255) },
		{ Kind = "Bone", Zone = "Ruins", Color = Color3.fromRGB(240, 235, 220) },
	}
	for _, placement in placements do
		local item = spawnSource("Offering_" .. placement.Kind, placement.Color, Vector3.new(1.6, 2.4, 1.6), Enum.PartType.Block, function()
			return MapService.randomPointNear(MapService.Zones[placement.Zone], 14)
		end, 60, function(player)
			local s = state(player)
			if s.Offering then
				return false
			end
			s.Offering = placement.Kind
			sync(player)
			local def = (Genes.Offerings :: any)[placement.Kind]
			AnnouncementService.player(player, string.format("Has cogido un %s. Llévalo al huevo.", def.DisplayName))
			return true
		end)
		local light = Instance.new("PointLight")
		light.Color = placement.Color
		light.Range = 10
		light.Parent = item
	end
end

-- Al empujar a alguien con la bolsa llena, parte del Calor cae al suelo en brasas.
local function dropEmbers(position: Vector3, amount: number)
	local pieces = math.clamp(math.ceil(amount / 10), 1, 6)
	local each = math.floor(amount / pieces)
	for _ = 1, pieces do
		local ember = makePickup("DroppedEmber", Color3.fromRGB(255, 160, 60), Vector3.new(1.2, 1.2, 1.2), Enum.PartType.Ball)
		ember.Position = position + Vector3.new(random:NextNumber(-6, 6), 0.8, random:NextNumber(-6, 6))
		local taken = false
		ember.Touched:Connect(function(hit)
			if taken or not hit:IsA("BasePart") then
				return
			end
			local player = playerFromPart(hit)
			if player and HeatService.give(player, each) > 0 then
				taken = true
				ember:Destroy()
			end
		end)
		task.delay(20, function()
			if ember.Parent then
				ember:Destroy()
			end
		end)
	end
end

local function setupBumpPrompt(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BumpPrompt"
	prompt.ActionText = "Empujar"
	prompt.ObjectText = "Bolsa llena"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.Heat.BumpRange
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = root

	prompt.Triggered:Connect(function(bumper)
		if bumper == player or not active then
			return
		end
		local victim = state(player)
		local now = os.clock()
		if now - victim.LastBumped < Config.Heat.BumpCooldown or victim.Heat < HeatService.capacity(player) then
			return
		end
		local bumperRoot = rootOf(bumper)
		local victimRoot = rootOf(player)
		if not bumperRoot or not victimRoot or (bumperRoot.Position - victimRoot.Position).Magnitude > Config.Heat.BumpRange + 3 then
			return
		end
		victim.LastBumped = now
		local dropped = math.floor(victim.Heat * Config.Heat.BumpDropFraction)
		victim.Heat -= dropped
		sync(player)
		dropEmbers(victimRoot.Position, dropped)
		victimRoot.AssemblyLinearVelocity += (victimRoot.Position - bumperRoot.Position).Unit * 40 + Vector3.new(0, 20, 0)
		AnnouncementService.player(player, string.format("¡%s te ha empujado! Se te cayeron %d de Calor.", bumper.DisplayName, dropped))
	end)

	player:GetAttributeChangedSignal("BagFull"):Connect(function()
		prompt.Enabled = player:GetAttribute("BagFull") == true and active
	end)
end

-- Ciclo de ronda --------------------------------------------------------------------------

function HeatService.setActive(value: boolean)
	active = value
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local prompt = root and root:FindFirstChild("BumpPrompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = value and player:GetAttribute("BagFull") == true
		end
	end
	local depositPrompt = MapService.Egg:FindFirstChild("DepositPrompt")
	if depositPrompt and depositPrompt:IsA("ProximityPrompt") then
		depositPrompt.Enabled = value
	end
end

-- Al final de la ronda el Calor sin depositar se pierde (GDD 6).
function HeatService.resetRound()
	for _, relocate in relocators do
		relocate()
	end
	for player, s in states do
		s.Heat = 0
		s.Affinity = 0
		s.Offering = nil
		if player.Parent then
			sync(player)
		end
	end
end

function HeatService.init() end

function HeatService.start()
	local depositPrompt = Instance.new("ProximityPrompt")
	depositPrompt.Name = "DepositPrompt"
	depositPrompt.ActionText = "Depositar Calor"
	depositPrompt.ObjectText = "Huevo Gigante"
	depositPrompt.HoldDuration = 0
	depositPrompt.MaxActivationDistance = Config.Heat.DepositRadius
	depositPrompt.RequiresLineOfSight = false
	depositPrompt.Enabled = false
	depositPrompt.Parent = MapService.Egg
	depositPrompt.Triggered:Connect(HeatService.deposit)

	spawnEmbers()
	spawnFireflies()
	spawnLuckyBlocks()
	spawnGeysers()
	spawnOfferings()

	local function onPlayer(player: Player)
		state(player)
		player.CharacterAdded:Connect(function(character)
			setupBumpPrompt(player, character)
		end)
		if player.Character then
			task.spawn(setupBumpPrompt, player, player.Character)
		end
		task.spawn(function()
			DataService.await(player)
			if player.Parent then
				sync(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	-- Pase Auto-Depósito y refresco de capacidad tras mejorar la bolsa.
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, player in Players:GetPlayers() do
				if active and MonetizationService.hasPass(player, "AutoDeposit") then
					local s = states[player]
					local root = rootOf(player)
					if s and (s.Heat > 0 or s.Offering) and root and (root.Position - MapService.EggCenter).Magnitude <= Config.Heat.DepositRadius then
						HeatService.deposit(player)
					end
				end
				if states[player] and player:GetAttribute("BagCapacity") ~= HeatService.capacity(player) then
					sync(player)
				end
			end
		end
	end)
end

return HeatService
