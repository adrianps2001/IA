--!strict
-- Piezas básicas para los estilos de criatura: todas ancladas, sin colisión y sin peso.

local Parts = {}

function Parts.rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

function Parts.part(name: string, shape: Enum.PartType, size: Vector3, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = true
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- Elipsoide (bloque con malla esférica: se estira con el tamaño, una Ball no).
function Parts.blob(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local p = Parts.part(name, Enum.PartType.Block, size, color, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Mezcla un color con blanco (t = 0: igual; 1: blanco). Colores pastel.
function Parts.tint(color: Color3, t: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), t)
end

function Parts.shade(color: Color3, t: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), t)
end

return Parts
