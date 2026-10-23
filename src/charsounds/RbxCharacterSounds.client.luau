--!strict
-- Sonidos de los personajes (GDD v3). Este script sustituye al RbxCharacterSounds de Roblox
-- (al llamarse igual, Roblox no pone el suyo): sus pasos eran un bucle de plástico que
-- chirriaba. Aquí cada zancada es un golpecito suave que depende del suelo (hierba, madera...),
-- con un poco de variación, más el salto y la caída. Los audios están en Sounds.luau.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Sounds = require(Shared:WaitForChild("Sounds"))

type Tracked = { Humanoid: Humanoid, Root: BasePart, LastStep: number, AirSince: number? }

local tracked: { [Model]: Tracked } = {}

local GRASS = {
	[Enum.Material.Grass] = true,
	[Enum.Material.LeafyGrass] = true,
	[Enum.Material.Ground] = true,
	[Enum.Material.Mud] = true,
	[Enum.Material.Sand] = true,
	[Enum.Material.Fabric] = true,
}
local WOOD = {
	[Enum.Material.Wood] = true,
	[Enum.Material.WoodPlanks] = true,
}

local function play(name: string, root: BasePart)
	local def = Sounds.get(name)
	if not def then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.Id
	sound.Volume = def.Volume
	local vary = def.Vary or 0
	sound.PlaybackSpeed = def.Pitch * (1 + (math.random() * 2 - 1) * vary)
	sound.RollOffMaxDistance = 60
	sound.Parent = root
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
end

local function watch(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
		return
	end
	local entry: Tracked = { Humanoid = humanoid, Root = root, LastStep = 0, AirSince = nil }
	tracked[character] = entry
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			play("Jump", root)
		elseif new == Enum.HumanoidStateType.Freefall then
			entry.AirSince = os.clock()
		elseif new == Enum.HumanoidStateType.Landed then
			local since = entry.AirSince
			if since and os.clock() - since > 0.35 then
				play("Land", root)
			end
			entry.AirSince = nil
		end
	end)
	character.AncestryChanged:Connect(function()
		if not character.Parent then
			tracked[character] = nil
		end
	end)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(watch)
	if player.Character then
		task.spawn(watch, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end

-- Una zancada cada ~5,5 studs recorridos (más rápido = pasos más seguidos).
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for _, entry in tracked do
		local humanoid = entry.Humanoid
		local velocity = entry.Root.AssemblyLinearVelocity
		local state = humanoid:GetState()
		local floor = humanoid.FloorMaterial
		if state == Enum.HumanoidStateType.Climbing then
			if math.abs(velocity.Y) > 1 and now - entry.LastStep > 0.35 then
				entry.LastStep = now
				play("StepWood", entry.Root)
			end
		elseif floor ~= Enum.Material.Air and state == Enum.HumanoidStateType.Running then
			local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			if speed > 1.5 then
				local interval = math.clamp(5.5 / speed, 0.22, 0.6)
				if now - entry.LastStep >= interval then
					entry.LastStep = now
					play(if GRASS[floor] then "StepGrass" elseif WOOD[floor] then "StepWood" else "StepSoft", entry.Root)
				end
			end
		end
	end
end)
