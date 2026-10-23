--!strict
-- Controles de la persecución: esprint y relevo (solo portador), respuesta a tratos
-- y ocultar los prompts que cuelgan del propio personaje (no te puedes robar a ti mismo).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local UI = require(script.Parent.Parent.UI)

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
end

return ChaseController
