--!strict
-- Estética que dibuja cada cliente (GDD v2), sin tráfico de red ni física en el servidor:
-- * Compañero: la primera favorita de cada jugador le sigue flotando. El servidor publica
--   sus genes en el atributo CompanionGenes (NestService.updateCompanion).
-- * Estela de Brasas: un rastro de chispas para quien tenga el pase (atributo Pass_EmberTrail).
-- Nada de esto da ventaja: las piezas no colisionan ni se pueden tocar.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Creature = require(Shared.Creature)
local CreatureModel = require(Shared.CreatureModel)
local Genes = require(Shared.Genes)

local CosmeticsController = {}

type Companion = { Model: Model, Source: string }

local companions: { [Player]: Companion } = {}
local folder: Folder

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function refreshCompanion(player: Player)
	local source = player:GetAttribute("CompanionGenes")
	local current = companions[player]
	if current and current.Source == source then
		return
	end
	if current then
		current.Model:Destroy()
		companions[player] = nil
	end
	if type(source) ~= "string" then
		return
	end
	local ok, genes = pcall(function()
		return HttpService:JSONDecode(source)
	end)
	if not ok or not Genes.isValidSet(genes) then
		return
	end
	local model = CreatureModel.build(Creature.new("companion", genes, "Companion", 0), 0.45)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	model.Name = "Companion_" .. player.UserId
	model.Parent = folder
	companions[player] = { Model = model, Source = source }
end

local function refreshTrail(player: Player)
	local root = rootOf(player)
	if not root then
		return
	end
	local has = player:GetAttribute("Pass_EmberTrail") == true
	local existing = root:FindFirstChild("EmberTrail")
	if has and not existing then
		local a0 = Instance.new("Attachment")
		a0.Name = "EmberTrailTop"
		a0.Position = Vector3.new(0, 0.6, 0.6)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Name = "EmberTrailBottom"
		a1.Position = Vector3.new(0, -0.8, 0.6)
		a1.Parent = root
		local trail = Instance.new("Trail")
		trail.Name = "EmberTrail"
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.5
		trail.LightEmission = 1
		trail.Color = ColorSequence.new(Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 80, 20))
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.Parent = root
	elseif not has and existing then
		existing:Destroy()
	end
end

local function watch(player: Player)
	player:GetAttributeChangedSignal("CompanionGenes"):Connect(function()
		refreshCompanion(player)
	end)
	player:GetAttributeChangedSignal("Pass_EmberTrail"):Connect(function()
		refreshTrail(player)
	end)
	player.CharacterAdded:Connect(function()
		task.defer(refreshTrail, player)
	end)
	refreshCompanion(player)
	refreshTrail(player)
end

function CosmeticsController.start()
	local f = Instance.new("Folder")
	f.Name = "Companions"
	f.Parent = workspace
	folder = f

	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		local companion = companions[player]
		if companion then
			companion.Model:Destroy()
			companions[player] = nil
		end
	end)

	-- El compañero flota detrás del hombro de su dueño y se mece un poco.
	RunService.RenderStepped:Connect(function()
		local bob = math.sin(os.clock() * 3) * 0.3
		for player, companion in companions do
			local root = rootOf(player)
			if root then
				local target = root.CFrame * CFrame.new(2.5, 1.5 + bob, 2)
				companion.Model:PivotTo(companion.Model:GetPivot():Lerp(target, 0.15))
			end
		end
	end)
end

return CosmeticsController
