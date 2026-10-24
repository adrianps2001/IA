--!strict
-- Sonidos de las acciones (GDD v3). Los nombres y los audios están en Sounds.luau.
-- Casi todo se deduce aquí de lo que ya replica el servidor (atributos del jugador y de la
-- ronda): recoger Calor, depositar, bolsa llena, ser portador, tira y afloja, escudos, señal,
-- cuenta atrás, fases... Lo que solo sabe el servidor (robos, géiseres, compras) llega por el
-- remoto PlaySound. Los botones de la interfaz hacen clic.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local RoundState = require(Shared.RoundState)
local Sounds = require(Shared.Sounds)

local UI = require(script.Parent.Parent.UI)

local player = Players.LocalPlayer

local SoundController = {}

local folder: Folder

-- Grupo de sonido de los efectos: el volumen de los ajustes ⚙️ (SettingsController) lo mueve.
function SoundController.group(name: string): SoundGroup
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Volume = 1
	g.Parent = SoundService
	return g
end

-- Reproduce un sonido del catálogo. Con position (o una pieza) suena en 3D desde allí.
function SoundController.play(name: string, at: (Vector3 | BasePart)?, pitchBoost: number?)
	local def = Sounds.get(name)
	if not def then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = def.Id
	sound.Volume = def.Volume
	sound.SoundGroup = SoundController.group("Effects")
	local vary = def.Vary or 0
	sound.PlaybackSpeed = def.Pitch * (pitchBoost or 1) * (1 + (math.random() * 2 - 1) * vary)
	local holder: Instance = folder
	if typeof(at) == "Vector3" then
		local anchor = Instance.new("Attachment")
		anchor.WorldPosition = at
		anchor.Parent = workspace.Terrain
		holder = anchor
		-- Hasta 25 studs suena igual de fuerte que un sonido de interfaz; luego se apaga poco a
		-- poco (antes, con el mínimo de 10 de Roblox, los sonidos 3D quedaban muy flojos).
		sound.RollOffMinDistance = 25
		sound.RollOffMaxDistance = 120
		sound.Ended:Connect(function()
			anchor:Destroy()
		end)
	elseif typeof(at) == "Instance" then
		holder = at
		sound.RollOffMinDistance = 25
		sound.RollOffMaxDistance = 120
	end
	sound.Parent = holder
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
	task.delay(10, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local function number(value: any): number
	return tonumber(value) or 0
end

function SoundController.start()
	local f = Instance.new("Folder")
	f.Name = "SFX"
	f.Parent = SoundService
	folder = f

	UI.onClickSound = function()
		SoundController.play("Click")
	end

	Remotes.event("PlaySound").OnClientEvent:Connect(function(name: any, at: any)
		if type(name) == "string" then
			SoundController.play(name, if typeof(at) == "Vector3" then at else nil)
		end
	end)

	-- Calor: el tono sube si coges varias seguidas (combo), como en los juegos de monedas.
	local lastHeat = number(player:GetAttribute("Heat"))
	local lastAffinity = number(player:GetAttribute("Affinity"))
	local combo = 0
	local lastPickup = 0
	player:GetAttributeChangedSignal("Heat"):Connect(function()
		local heat = number(player:GetAttribute("Heat"))
		if heat > lastHeat then
			combo = if os.clock() - lastPickup < 1.5 then math.min(combo + 1, 8) else 0
			lastPickup = os.clock()
			SoundController.play("Pickup", nil, 1 + combo * 0.05)
		end
		lastHeat = heat
	end)
	player:GetAttributeChangedSignal("Affinity"):Connect(function()
		local affinity = number(player:GetAttribute("Affinity"))
		if affinity > lastAffinity then
			SoundController.play("Deposit")
		end
		lastAffinity = affinity
	end)
	player:GetAttributeChangedSignal("BagFull"):Connect(function()
		if player:GetAttribute("BagFull") then
			SoundController.play("BagFull")
		end
	end)

	-- Persecución.
	player:GetAttributeChangedSignal("IsCarrier"):Connect(function()
		if player:GetAttribute("IsCarrier") then
			SoundController.play("GotCreature")
		elseif RoundState.phase() == "Chase" then
			SoundController.play("Lost")
		end
	end)
	player:GetAttributeChangedSignal("TugEndsAt"):Connect(function()
		if player:GetAttribute("TugEndsAt") then
			SoundController.play("TugStart")
		end
	end)
	player:GetAttributeChangedSignal("BeingTugged"):Connect(function()
		if player:GetAttribute("BeingTugged") then
			SoundController.play("Alarm")
		end
	end)
	local lastShields = number(player:GetAttribute("Shields"))
	player:GetAttributeChangedSignal("Shields"):Connect(function()
		local shields = number(player:GetAttribute("Shields"))
		if shields < lastShields and RoundState.phase() == "Chase" then
			SoundController.play("ShieldBreak")
		end
		lastShields = shields
	end)
	RoundState.changed("Revealed"):Connect(function()
		if RoundState.get("Revealed") and player:GetAttribute("InMatch") then
			SoundController.play("Reveal")
		end
	end)

	-- Fases de la ronda.
	RoundState.changed("Phase"):Connect(function()
		if not player:GetAttribute("InMatch") then
			return
		end
		local phase = RoundState.phase()
		if phase == "Incubation" then
			SoundController.play("RoundStart")
		elseif phase == "Hatch" then
			SoundController.play("Hatch")
		elseif phase == "Chase" then
			SoundController.play("ChaseStart")
		elseif phase == "Results" then
			SoundController.play("Results")
		end
	end)

	-- Lobby: cola y partida encontrada.
	player:GetAttributeChangedSignal("Queued"):Connect(function()
		if player:GetAttribute("Queued") then
			SoundController.play("Queue")
		end
	end)
	RoundState.changed("QueueLaunchAt"):Connect(function()
		if number(RoundState.get("QueueLaunchAt")) > 0 and player:GetAttribute("Queued") then
			SoundController.play("MatchFound")
		end
	end)

	-- Avisos importantes.
	Remotes.event("Announcement").OnClientEvent:Connect(function(_, style: string?)
		if style == "rare" or style == "global" then
			SoundController.play("Fanfare")
		elseif style == "threshold" then
			SoundController.play("Alert")
		end
	end)
	Remotes.event("Notify").OnClientEvent:Connect(function(_, style: string?)
		if style == "quest" then
			SoundController.play("Quest")
		elseif style == "rare" then
			SoundController.play("Fanfare")
		end
	end)

	-- Cuenta atrás de los últimos 5 segundos de la incubación y la persecución.
	task.spawn(function()
		local lastSecond = -1
		while true do
			task.wait(0.1)
			local phase = RoundState.phase()
			if (phase == "Incubation" or phase == "Chase") and player:GetAttribute("InMatch") then
				local left = math.ceil(RoundState.timeLeft())
				if left <= 5 and left >= 1 and left ~= lastSecond then
					lastSecond = left
					SoundController.play("Tick", nil, if left == 1 then 1.3 else 1)
				end
			end
		end
	end)
end

return SoundController
