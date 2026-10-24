--!strict
-- Ajustes del jugador (v3.1): botón ⚙️ con el volumen de efectos y de pasos, el tamaño de la
-- interfaz, ver o no las criaturas al hombro de los demás y repetir el tutorial. Se guardan en
-- el perfil (remoto SetSettings; el servidor los limpia con PlayerData.cleanSettings).
-- En el lobby, además, "👀 Mi nido" lleva la cámara a tus gradas para ver tus criaturas.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local MapLayout = require(Shared.MapLayout)
local PlayerData = require(Shared.PlayerData)
local Remotes = require(Shared.Remotes)

local UI = require(script.Parent.Parent.UI)
local CosmeticsController = require(script.Parent.CosmeticsController)
local SoundController = require(script.Parent.SoundController)
local TutorialController = require(script.Parent.TutorialController)

local player = Players.LocalPlayer

local SettingsController = {}

local settings: PlayerData.Settings = PlayerData.cleanSettings(nil)
local panel: Frame
local rows: { [string]: TextLabel } = {}
local nestButton: TextButton
local sendToken = 0

-- ---------------------------------------------------------------- aplicar
local function applyScale(gui: Instance)
	if not gui:IsA("ScreenGui") then
		return
	end
	local scale = gui:FindFirstChild("SettingsScale")
	if not scale then
		local s = Instance.new("UIScale")
		s.Name = "SettingsScale"
		s.Parent = gui
		scale = s
	end
	(scale :: UIScale).Scale = settings.UIScale
end

local function apply()
	SoundController.group("Effects").Volume = settings.Effects
	SoundController.group("Steps").Volume = settings.Steps
	CosmeticsController.setShowOthers(settings.ShowPets)
	for _, gui in player:WaitForChild("PlayerGui"):GetChildren() do
		applyScale(gui)
	end
	if rows.Effects then
		rows.Effects.Text = string.format("%d %%", math.round(settings.Effects * 100))
		rows.Steps.Text = string.format("%d %%", math.round(settings.Steps * 100))
		rows.UIScale.Text = string.format("%d %%", math.round(settings.UIScale * 100))
		rows.ShowPets.Text = if settings.ShowPets then "Sí" else "No"
	end
end

-- Guarda medio segundo después del último cambio (para no mandar un remoto por cada clic).
local function changed()
	settings = PlayerData.cleanSettings(settings)
	apply()
	sendToken += 1
	local token = sendToken
	task.delay(0.5, function()
		if token == sendToken then
			Remotes.event("SetSettings"):FireServer(settings)
		end
	end)
end

-- ---------------------------------------------------------------- ver mi nido
local viewing = false
local function viewNest(): (() -> ())?
	local index = tonumber(player:GetAttribute("LobbyNestIndex"))
	local camera = workspace.CurrentCamera
	if not index or not camera or viewing then
		return nil
	end
	viewing = true
	local origin = Vector3.new(Config.Lobby.OriginX, 0, Config.Lobby.OriginZ)
	local angle = (index / Config.Lobby.NestCount) * math.pi * 2
	local radius = MapLayout.lobbyNestRadius()
	local center = origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	local nest = CFrame.lookAt(center, origin)
	local half = Config.Lobby.NestSize / 2
	local eye = (nest * CFrame.new(0, 13, -half - 14)).Position
	local focus = (nest * CFrame.new(0, 3, 3)).Position
	local previous = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable
	TweenService:Create(camera, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { CFrame = CFrame.lookAt(eye, focus) }):Play()
	nestButton.Text = "↩ Volver"
	local function back()
		if not viewing then
			return
		end
		viewing = false
		camera.CameraType = if previous == Enum.CameraType.Scriptable then Enum.CameraType.Custom else previous
		nestButton.Text = "👀 Mi nido"
	end
	task.delay(10, back)
	return back
end

-- ---------------------------------------------------------------- interfaz
local function row(parent: Instance, order: number, title: string, key: string, minus: () -> (), plus: () -> ())
	local r = UI.frame({ Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	UI.label({ Size = UDim2.new(0.5, 0, 1, 0), Text = title, TextXAlignment = Enum.TextXAlignment.Left }, r)
	UI.button({ Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(36, 32), Text = "−", BackgroundColor3 = UI.Colors.PanelLight }, r, minus)
	rows[key] = UI.label({ Position = UDim2.new(0.5, 40, 0, 0), Size = UDim2.new(0.5, -80, 1, 0), Text = "" }, r)
	UI.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 4), Size = UDim2.fromOffset(36, 32), Text = "+", BackgroundColor3 = UI.Colors.PanelLight }, r, plus)
end

local function step(key: string, delta: number)
	return function()
		(settings :: any)[key] = math.round(((settings :: any)[key] + delta) * 100) / 100
		changed()
	end
end

function SettingsController.start()
	local gui = UI.screen("Settings", 6)
	UI.button({ Position = UDim2.fromOffset(12, 64), Size = UDim2.fromOffset(44, 44), Text = "⚙️", BackgroundColor3 = UI.Colors.Panel }, gui, function()
		panel.Visible = not panel.Visible
	end)
	local stopViewing: (() -> ())? = nil
	nestButton = UI.button({ Position = UDim2.fromOffset(12, 114), Size = UDim2.fromOffset(110, 40), Text = "👀 Mi nido", BackgroundColor3 = UI.Colors.Panel }, gui, function()
		if viewing and stopViewing then
			stopViewing()
		else
			stopViewing = viewNest()
		end
	end)
	local function updateNestButton()
		nestButton.Visible = player:GetAttribute("InMatch") ~= true and player:GetAttribute("LobbyNestIndex") ~= nil
	end
	player:GetAttributeChangedSignal("InMatch"):Connect(updateNestButton)
	player:GetAttributeChangedSignal("LobbyNestIndex"):Connect(updateNestButton)
	updateNestButton()

	panel = UI.frame({ Position = UDim2.fromOffset(64, 64), Size = UDim2.fromOffset(330, 300), Visible = false }, gui)
	UI.round(panel, 14)
	UI.padding(panel, 10)
	UI.list(panel, 4)
	UI.label({ Size = UDim2.new(1, 0, 0, 30), Text = "⚙️ Ajustes", LayoutOrder = 0 }, panel)
	row(panel, 1, "🔊 Efectos", "Effects", step("Effects", -0.1), step("Effects", 0.1))
	row(panel, 2, "👣 Pasos", "Steps", step("Steps", -0.1), step("Steps", 0.1))
	row(panel, 3, "🔠 Interfaz", "UIScale", step("UIScale", -0.1), step("UIScale", 0.1))
	row(panel, 4, "🦜 Al hombro de otros", "ShowPets", function()
		settings.ShowPets = not settings.ShowPets
		changed()
	end, function()
		settings.ShowPets = not settings.ShowPets
		changed()
	end)
	UI.button({ Size = UDim2.new(1, 0, 0, 36), Text = "🎓 Ver el tutorial otra vez", LayoutOrder = 5, BackgroundColor3 = UI.Colors.PanelLight }, panel, function()
		TutorialController.restart()
		panel.Visible = false
	end)

	player:WaitForChild("PlayerGui").ChildAdded:Connect(applyScale)
	-- Ajustes guardados.
	task.spawn(function()
		local ok, view = pcall(function()
			return Remotes.func("GetProfile"):InvokeServer()
		end)
		if ok and type(view) == "table" and view.Settings then
			settings = PlayerData.cleanSettings(view.Settings)
		end
		apply()
	end)
	apply()
end

return SettingsController
