--!strict
-- Pequeñas utilidades para construir la interfaz por código con un estilo común
-- ("juguete brillante": formas redondas, colores saturados, texto grande para móvil).

local Players = game:GetService("Players")

local UI = {}

UI.Colors = {
	Panel = Color3.fromRGB(30, 24, 40),
	PanelLight = Color3.fromRGB(52, 42, 68),
	Accent = Color3.fromRGB(255, 170, 60),
	Gold = Color3.fromRGB(255, 205, 60),
	Good = Color3.fromRGB(90, 210, 110),
	Bad = Color3.fromRGB(235, 80, 80),
	Text = Color3.fromRGB(255, 250, 240),
	Muted = Color3.fromRGB(190, 180, 200),
}

UI.Font = Enum.Font.FredokaOne

function UI.screen(name: string, order: number?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = order or 0
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

function UI.round(instance: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 12)
	corner.Parent = instance
end

function UI.stroke(instance: GuiObject, color: Color3?, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Color3.new(0, 0, 0)
	stroke.Thickness = thickness or 2
	stroke.Transparency = 0.3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance
end

function UI.frame(props: { [string]: any }, parent: Instance?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = UI.Colors.Panel
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
	for key, value in props do
		(f :: any)[key] = value
	end
	f.Parent = parent
	return f
end

function UI.label(props: { [string]: any }, parent: Instance?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = UI.Font
	l.TextColor3 = UI.Colors.Text
	l.TextScaled = true
	l.TextStrokeTransparency = 0.6
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

function UI.button(props: { [string]: any }, parent: Instance?, onClick: (() -> ())?): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = UI.Colors.Accent
	b.Font = UI.Font
	b.TextColor3 = UI.Colors.Text
	b.TextScaled = true
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	for key, value in props do
		(b :: any)[key] = value
	end
	UI.round(b, 10)
	UI.stroke(b)
	b.Parent = parent
	if onClick then
		b.Activated:Connect(function()
			onClick()
		end)
	end
	return b
end

function UI.padding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
end

function UI.list(parent: Instance, padding: number?, horizontal: boolean?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding or 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	layout.Parent = parent
	return layout
end

function UI.clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function UI.rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

function UI.formatNumber(n: number): string
	local value = math.floor(n)
	if value >= 1e9 then
		return string.format("%.1fB", value / 1e9)
	elseif value >= 1e6 then
		return string.format("%.1fM", value / 1e6)
	elseif value >= 1e4 then
		return string.format("%.1fK", value / 1e3)
	end
	return tostring(value)
end

function UI.formatTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	if s >= 3600 then
		return string.format("%d:%02d:%02d", s // 3600, (s % 3600) // 60, s % 60)
	end
	return string.format("%d:%02d", s // 60, s % 60)
end

return UI
