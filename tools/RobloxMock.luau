--!nocheck
-- Imitación mínima de los tipos de Roblox (Vector3, CFrame, Color3, Instance, Enum...) para
-- ejecutar fuera de Roblox el código que construye modelos (los estilos de criatura) y sacar
-- sus piezas. La usa tools/build_creatures.py para la galería docs/criaturas.html.
-- Solo implementa lo que usan esos módulos.

local M = {}

-- Vector3 ----------------------------------------------------------------------------------
local V = {}
V.__index = function(v, key)
	if key == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif key == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return M.Vector3.new(v.X / m, v.Y / m, v.Z / m)
	end
	return V[key]
end
local function vec(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, __vector = true }, V)
end
V.__add = function(a, b)
	return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V.__sub = function(a, b)
	return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V.__unm = function(a)
	return vec(-a.X, -a.Y, -a.Z)
end
V.__mul = function(a, b)
	if type(a) == "number" then
		return vec(b.X * a, b.Y * a, b.Z * a)
	elseif type(b) == "number" then
		return vec(a.X * b, a.Y * b, a.Z * b)
	end
	return vec(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V.__div = function(a, b)
	if type(b) == "number" then
		return vec(a.X / b, a.Y / b, a.Z / b)
	end
	return vec(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
function V.Cross(a, b)
	return vec(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V.Lerp(a, b, t)
	return a + (b - a) * t
end
M.Vector3 = { new = vec, one = vec(1, 1, 1), zero = vec(0, 0, 0) }

-- CFrame: posición + matriz de rotación (columnas: derecha, arriba, atrás) -----------------
local C = {}
C.__index = function(cf, key)
	if key == "Position" then
		return cf.P
	elseif key == "RightVector" then
		return vec(cf.R[1], cf.R[4], cf.R[7])
	elseif key == "UpVector" then
		return vec(cf.R[2], cf.R[5], cf.R[8])
	elseif key == "LookVector" then
		return vec(-cf.R[3], -cf.R[6], -cf.R[9])
	end
	return C[key]
end
local function cframe(p, r)
	return setmetatable({ P = p, R = r }, C)
end
local IDENTITY = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
local function mulR(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			r[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
		end
	end
	return r
end
local function rotate(r, v)
	return vec(r[1] * v.X + r[2] * v.Y + r[3] * v.Z, r[4] * v.X + r[5] * v.Y + r[6] * v.Z, r[7] * v.X + r[8] * v.Y + r[9] * v.Z)
end
C.__mul = function(a, b)
	if getmetatable(b) == V then
		return a.P + rotate(a.R, b)
	end
	return cframe(a.P + rotate(a.R, b.P), mulR(a.R, b.R))
end
function C.Lerp(a, b, t)
	return cframe(a.P:Lerp(b.P, t), b.R)
end
local function angles(rx, ry, rz)
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	local Rx = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
	local Ry = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local Rz = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
	return mulR(mulR(Rx, Ry), Rz)
end
M.CFrame = {
	new = function(x, y, z)
		if type(x) == "table" then
			return cframe(x, IDENTITY)
		end
		return cframe(vec(x or 0, y or 0, z or 0), IDENTITY)
	end,
	Angles = function(rx, ry, rz)
		return cframe(vec(0, 0, 0), angles(rx, ry, rz))
	end,
	lookAt = function(at, target)
		local look = (target - at).Unit
		local up = vec(0, 1, 0)
		if math.abs(look:Dot(up)) > 0.999 then
			up = vec(0, 0, 1)
		end
		local right = look:Cross(up).Unit
		local up2 = right:Cross(look)
		return cframe(at, { right.X, up2.X, -look.X, right.Y, up2.Y, -look.Y, right.Z, up2.Z, -look.Z })
	end,
}

-- Color3 -------------------------------------------------------------------------------------
local Col = {}
Col.__index = Col
local function color(r, g, b)
	return setmetatable({ R = r, G = g, B = b }, Col)
end
function Col.Lerp(a, b, t)
	return color(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
M.Color3 = {
	new = color,
	fromRGB = function(r, g, b)
		return color(r / 255, g / 255, b / 255)
	end,
}

-- Enum: Enum.PartType.Ball -> "Ball" ---------------------------------------------------------
M.Enum = setmetatable({}, {
	__index = function(_, group)
		return setmetatable({}, {
			__index = function(_, item)
				return item
			end,
		})
	end,
})

-- Instance: tabla de propiedades con hijos ---------------------------------------------------
local I = {}
I.__index = function(inst, key)
	local props = rawget(inst, "__props")
	if key == "Position" and props.CFrame then
		return props.CFrame.P
	end
	local method = I[key]
	if method then
		return method
	end
	return props[key]
end
I.__newindex = function(inst, key, value)
	local props = rawget(inst, "__props")
	if key == "Parent" then
		local old = props.Parent
		if old then
			local list = rawget(old, "__children")
			for i, c in list do
				if c == inst then
					table.remove(list, i)
					break
				end
			end
		end
		if value then
			table.insert(rawget(value, "__children"), inst)
		end
	end
	if key == "Size" and value and props.Shape == "Ball" then
		local m = math.min(value.X, value.Y, value.Z)
		value = vec(m, m, m)
	end
	props[key] = value
end
function I.GetChildren(inst)
	return table.clone(rawget(inst, "__children"))
end
function I.GetDescendants(inst)
	local out = {}
	local function walk(node)
		for _, c in rawget(node, "__children") do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(inst)
	return out
end
function I.IsA(inst, class)
	local name = rawget(inst, "ClassName")
	if class == "BasePart" then
		return name == "Part" or name == "TrussPart"
	end
	return name == class
end
function I.SetAttribute(inst, key, value)
	rawget(inst, "__props")["@" .. key] = value
end
function I.FindFirstChild(inst, name)
	for _, c in rawget(inst, "__children") do
		if c.Name == name then
			return c
		end
	end
	return nil
end
function I.Destroy(inst)
	inst.Parent = nil
end
M.Instance = {
	new = function(className)
		local inst = setmetatable({ ClassName = className, __props = { Name = className, Transparency = 0 }, __children = {} }, I)
		if className == "Part" then
			inst.Shape = "Block"
			inst.Size = vec(4, 1, 2)
			inst.CFrame = M.CFrame.new(0, 0, 0)
			inst.Color = color(0.6, 0.6, 0.6)
			inst.Material = "Plastic"
		end
		return inst
	end,
}

local function passthrough(...)
	return { ... }
end
M.ColorSequence = { new = passthrough }
M.NumberSequence = { new = passthrough }
M.NumberRange = { new = passthrough }
M.Vector2 = { new = passthrough }
M.UDim2 = { new = passthrough, fromScale = passthrough, fromOffset = passthrough }

-- Exporta las piezas de un modelo construido (para dibujarlo en la web).
function M.export(model)
	local parts = {}
	for _, inst in model:GetDescendants() do
		if inst.ClassName == "Part" then
			local mesh = inst:FindFirstChild("SpecialMesh")
			local text = nil
			for _, child in inst:GetDescendants() do
				if child.ClassName == "TextLabel" then
					text = child.Text
				end
			end
			local cf = inst.CFrame
			table.insert(parts, {
				Name = inst.Name,
				Shape = if mesh then "Sphere" else inst.Shape,
				Size = { inst.Size.X, inst.Size.Y, inst.Size.Z },
				Pos = { cf.P.X, cf.P.Y, cf.P.Z },
				Rot = cf.R,
				Color = { inst.Color.R, inst.Color.G, inst.Color.B },
				Transparency = inst.Transparency or 0,
				Material = inst.Material,
				Text = text,
			})
		end
	end
	return parts
end

return M
