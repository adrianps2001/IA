--!strict
-- Botón de acción para móvil y tableta (v3.1). En pantallas táctiles los avisos de Roblox
-- (ProximityPrompt: recoger, depositar, robar, tirolina, géiser…) son pequeños y difíciles de
-- pulsar corriendo. Este botón grande hace "lo que toca": pulsa el aviso visible más cercano
-- (con su texto encima) y lo mantiene mientras tengas el dedo, como la tecla E.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent.Parent.UI)

local player = Players.LocalPlayer

local ActionButtonController = {}

local shown: { [ProximityPrompt]: boolean } = {}
local button: TextButton
local current: ProximityPrompt? = nil
local holding: ProximityPrompt? = nil

local function promptPosition(prompt: ProximityPrompt): Vector3?
	local parent = prompt.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif parent and parent:IsA("Model") then
		return parent:GetPivot().Position
	end
	return nil
end

local function nearest(): ProximityPrompt?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for prompt in shown do
		local position = prompt.Enabled and promptPosition(prompt)
		if position then
			local d = (position - root.Position).Magnitude
			if d < bestDistance then
				best, bestDistance = prompt, d
			end
		end
	end
	return best
end

local function release()
	if holding then
		holding:InputHoldEnd()
		holding = nil
	end
end

function ActionButtonController.start()
	-- Solo en pantallas táctiles (en PC está la tecla E y en mando, el botón de Roblox).
	if not UserInputService.TouchEnabled then
		return
	end
	local gui = UI.screen("ActionButton", 3)
	button = Instance.new("TextButton")
	button.Name = "Action"
	button.AnchorPoint = Vector2.new(1, 1)
	-- Encima del botón de saltar de Roblox (abajo a la derecha) y del panel del portador.
	button.Position = UDim2.new(1, -28, 1, -236)
	button.Size = UDim2.fromOffset(104, 104)
	button.BackgroundColor3 = UI.Colors.Accent
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.FredokaOne
	button.TextScaled = true
	button.TextWrapped = true
	button.Text = ""
	button.AutoButtonColor = true
	button.Visible = false
	button.Parent = gui
	UI.round(button, 52)
	UI.stroke(button, Color3.new(1, 1, 1), 3)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = button

	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			if current then
				release()
				holding = current
				current:InputHoldBegin()
			end
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			release()
		end
	end)

	ProximityPromptService.PromptShown:Connect(function(prompt)
		shown[prompt] = true
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		shown[prompt] = nil
		if holding == prompt then
			release()
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.15 then
			return
		end
		acc = 0
		for prompt in shown do
			if not prompt.Parent then
				shown[prompt] = nil
			end
		end
		current = holding or nearest()
		button.Visible = current ~= nil
		if current then
			button.Text = if current.ActionText ~= "" then current.ActionText else "¡Acción!"
		end
	end)
end

return ActionButtonController
