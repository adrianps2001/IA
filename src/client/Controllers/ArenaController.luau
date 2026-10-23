--!strict
-- Parkour de la arena en el cliente (GDD v3): las setas trampolín te lanzan hacia arriba y
-- las tirolinas y los toboganes te llevan rápido hacia abajo. Lo mueve cada cliente porque
-- su personaje es suyo (la física de su personaje la calcula él); el servidor solo pone las
-- piezas (ArenaBuilder). Caer no tiene castigo: solo pierdes altura.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SoundController = require(script.Parent.SoundController)

local player = Players.LocalPlayer

local ArenaController = {}

local riding = false
local lastBounce = 0

local function character(): (Model?, Humanoid?, BasePart?)
	local model = player.Character
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if model and humanoid and root and root:IsA("BasePart") and humanoid.Health > 0 then
		return model, humanoid, root
	end
	return nil, nil, nil
end

local function isMine(hit: BasePart): boolean
	local model = player.Character
	return model ~= nil and hit:IsDescendantOf(model)
end

-- Recorre una línea de from a to a speed studs/s (tirolina o tobogán).
local function ride(from: Vector3, to: Vector3, speed: number, kind: string)
	if riding then
		return
	end
	local _, humanoid, root = character()
	if not humanoid or not root then
		return
	end
	riding = true
	SoundController.play(kind, root)
	local direction = (to - from).Unit
	local length = (to - from).Magnitude
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local facing = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	humanoid.PlatformStand = true
	local travelled = 0
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt)
		travelled += speed * dt
		if travelled >= length or not root.Parent or humanoid.Health <= 0 then
			connection:Disconnect()
			humanoid.PlatformStand = false
			if root.Parent then
				root.AssemblyLinearVelocity = facing * 12
			end
			riding = false
			return
		end
		local position = from + direction * travelled
		root.CFrame = CFrame.lookAt(position, position + facing)
		root.AssemblyLinearVelocity = direction * speed
	end)
end

local function watchTrampoline(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	instance.Touched:Connect(function(hit)
		if not isMine(hit) or os.clock() - lastBounce < 0.6 or riding then
			return
		end
		local _, _, root = character()
		if not root or root.Position.Y < instance.Position.Y then
			return -- solo desde arriba
		end
		lastBounce = os.clock()
		local power = tonumber(instance:GetAttribute("Power")) or 95
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X, power, v.Z)
		SoundController.play("Boing", root)
	end)
end

local function watchRidePrompt(instance: Instance)
	if not instance:IsA("ProximityPrompt") then
		return
	end
	instance.Triggered:Connect(function(who)
		if who ~= player then
			return
		end
		local from, to = instance:GetAttribute("RideFrom"), instance:GetAttribute("RideTo")
		if typeof(from) == "Vector3" and typeof(to) == "Vector3" then
			ride(from, to, tonumber(instance:GetAttribute("RideSpeed")) or 50, tostring(instance:GetAttribute("RideKind") or "Zipline"))
		end
	end)
end

local function watchSlide(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	instance.Touched:Connect(function(hit)
		if not isMine(hit) or riding then
			return
		end
		local from, to = instance:GetAttribute("RideFrom"), instance:GetAttribute("RideTo")
		if typeof(from) == "Vector3" and typeof(to) == "Vector3" then
			ride(from, to, tonumber(instance:GetAttribute("RideSpeed")) or 45, "Slide")
		end
	end)
end

local function bind(tag: string, callback: (Instance) -> ())
	CollectionService:GetInstanceAddedSignal(tag):Connect(callback)
	for _, instance in CollectionService:GetTagged(tag) do
		callback(instance)
	end
end

function ArenaController.start()
	bind("Trampoline", watchTrampoline)
	bind("RidePrompt", watchRidePrompt)
	bind("SlideEntry", watchSlide)
	player.CharacterAdded:Connect(function()
		riding = false
	end)
end

return ArenaController
