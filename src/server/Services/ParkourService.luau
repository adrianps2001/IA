--!strict
-- Torre de la plaza (v3.2): minijuego de parkour en el lobby para la espera de la cola.
-- Pisas la salida y empieza el tiempo; tienes que pisar los puntos de control en orden y llegar
-- a la meta de arriba. El servidor cronometra (no se fía del cliente), descarta tiempos
-- imposibles, guarda tu mejor marca y el récord del servidor, y da polvo el primer recorrido
-- del día. Si te caes al suelo, se cancela. Las plataformas salen de LobbyParkour.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local DailyReward = require(Shared.DailyReward)
local LobbyParkour = require(Shared.LobbyParkour)
local Place = require(Shared.Place)

local AnnouncementService = require(script.Parent.AnnouncementService)
local DataService = require(script.Parent.DataService)

local ParkourService = {}

type Run = { Start: number, Next: number }

local runs: { [Player]: Run } = {}
local record: { Time: number, Name: string }? = nil
local recordLabel: TextLabel? = nil
local checkpoints = LobbyParkour.checkpoints()

local COLORS = {
	Start = Color3.fromRGB(255, 150, 60),
	Step = Color3.fromRGB(235, 225, 205),
	Small = Color3.fromRGB(255, 215, 90),
	Beam = Color3.fromRGB(170, 120, 80),
	Checkpoint = Color3.fromRGB(90, 210, 110),
	Finish = Color3.fromRGB(255, 205, 60),
}

local function playerFromPart(part: BasePart): Player?
	local model = part:FindFirstAncestorOfClass("Model")
	return if model then Players:GetPlayerFromCharacter(model) else nil
end

local function cancel(player: Player, reason: string?)
	if runs[player] then
		runs[player] = nil
		player:SetAttribute("ParkourStart", nil)
		player:SetAttribute("ParkourCheckpoint", nil)
		if reason then
			AnnouncementService.player(player, reason)
		end
	end
end

local function updateRecordLabel()
	if recordLabel then
		recordLabel.Text = if record
			then string.format("🏁 Torre de la plaza\n🏆 Récord: %.2f s · %s", record.Time, record.Name)
			else "🏁 Torre de la plaza\n¡Pisa aquí y sube hasta arriba!"
	end
end

local function finish(player: Player)
	local run = runs[player]
	if not run or run.Next <= #checkpoints then
		return
	end
	local time = os.clock() - run.Start
	cancel(player)
	if time < LobbyParkour.minSeconds() then
		warn(string.format("[Parkour] Tiempo imposible de %s: %.2f s", player.Name, time))
		return
	end
	local profile = DataService.get(player)
	local text = string.format("🏁 ¡Arriba en %.2f s!", time)
	if profile then
		if profile.Parkour.Best == 0 or time < profile.Parkour.Best then
			profile.Parkour.Best = time
			player:SetAttribute("ParkourBest", time)
			text ..= " ¡Tu mejor marca!"
		end
		local today = DailyReward.dayNumber(os.time())
		if profile.Parkour.LastRewardDay ~= today and Config.LobbyParkour.DailyDust > 0 then
			profile.Parkour.LastRewardDay = today
			DataService.addDust(player, Config.LobbyParkour.DailyDust, "Gameplay:LobbyParkour")
			text ..= string.format(" +%d polvo (primera vez hoy)", Config.LobbyParkour.DailyDust)
		end
		DataService.markChanged(player)
	end
	AnnouncementService.sound(player, "Fanfare")
	AnnouncementService.player(player, text, "quest")
	if not record or time < record.Time then
		record = { Time = time, Name = player.DisplayName }
		updateRecordLabel()
		AnnouncementService.server(string.format("🏆 ¡%s bate el récord de la torre: %.2f s!", player.DisplayName, time), "rare")
	end
end

local function build()
	local c = Config.Lobby
	local origin = Vector3.new(c.OriginX, 0, c.OriginZ)
	local folder = Instance.new("Folder")
	folder.Name = "PlazaTower"
	folder.Parent = workspace:FindFirstChild("Lobby") or workspace -- LobbyBuilder crea workspace.Lobby
	for _, p in LobbyParkour.platforms() do
		local part = Instance.new("Part")
		part.Name = "Tower" .. p.Kind
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = Vector3.new(p.Size.X, p.Size.Y, p.Size.Z)
		-- Las vigas van a lo largo del recorrido (tangentes al círculo).
		part.CFrame = CFrame.new(origin + Vector3.new(p.Position.X, p.Position.Y, p.Position.Z)) * CFrame.Angles(0, -p.Angle, 0)
		part.Color = COLORS[p.Kind]
		part.Material = if p.Kind == "Beam" then Enum.Material.Wood elseif p.Kind == "Finish" or p.Kind == "Checkpoint" then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part:SetAttribute("Index", p.Index)
		part.Parent = folder
		if p.Kind == "Start" then
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromOffset(300, 70)
			gui.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
			gui.MaxDistance = 120
			gui.Parent = part
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.FredokaOne
			label.TextScaled = true
			label.TextColor3 = Color3.fromRGB(255, 240, 200)
			label.TextStrokeTransparency = 0.2
			label.Parent = gui
			recordLabel = label
			updateRecordLabel()
			part.Touched:Connect(function(hit)
				local player = playerFromPart(hit)
				if player and player:GetAttribute("InMatch") ~= true then
					-- Pisar la salida (otra vez) reinicia el tiempo.
					runs[player] = { Start = os.clock(), Next = 1 }
					player:SetAttribute("ParkourStart", workspace:GetServerTimeNow())
					player:SetAttribute("ParkourCheckpoint", 0)
				end
			end)
		elseif p.Kind == "Checkpoint" then
			part.Touched:Connect(function(hit)
				local player = playerFromPart(hit)
				local run = player and runs[player]
				if player and run and checkpoints[run.Next] == p.Index then
					run.Next += 1
					player:SetAttribute("ParkourCheckpoint", run.Next - 1)
					AnnouncementService.sound(player, "Quest")
				end
			end)
		elseif p.Kind == "Finish" then
			part.Touched:Connect(function(hit)
				local player = playerFromPart(hit)
				if player then
					finish(player)
				end
			end)
		end
	end
end

function ParkourService.init() end

function ParkourService.start()
	if not Config.LobbyParkour.Enabled or not Place.hasLobby() then
		return
	end
	task.defer(build) -- después de que MapService construya el lobby
	DataService.onLoaded(function(player, profile)
		player:SetAttribute("ParkourBest", if profile.Parkour.Best > 0 then profile.Parkour.Best else nil)
	end)
	Players.PlayerRemoving:Connect(function(player)
		runs[player] = nil
	end)
	-- Caerse al suelo, irse a una partida o tardar demasiado cancela el recorrido.
	task.spawn(function()
		local origin = Vector3.new(Config.Lobby.OriginX, 0, Config.Lobby.OriginZ)
		local start = LobbyParkour.platforms()[1].Position
		local startPos = origin + Vector3.new(start.X, 0, start.Z)
		while true do
			task.wait(0.5)
			for player, run in runs do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if player:GetAttribute("InMatch") == true or not root or not root:IsA("BasePart") then
					cancel(player)
				elseif os.clock() - run.Start > Config.LobbyParkour.MaxSeconds then
					cancel(player, "⏱️ Se acabó el tiempo de la torre. ¡Vuelve a la salida!")
				elseif root.Position.Y < origin.Y + 4 and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(startPos.X, 0, startPos.Z)).Magnitude > 8 then
					cancel(player, "💥 ¡Te caíste de la torre! Vuelve a la salida para intentarlo otra vez.")
				end
			end
		end
	end)
end

return ParkourService
