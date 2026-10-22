--!strict
-- Construye en Roblox las piezas de una decoración del nido (datos en Decorations.luau).

local Decorations = require(script.Parent.Decorations)

local DecorationModel = {}

-- Construye las piezas de una decoración en el nido cuyo origen es `origin`.
function DecorationModel.build(id: string, origin: CFrame): Model?
	local pieces = Decorations.Pieces[id]
	if not pieces then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = id
	for index, piece in pieces do
		local part = Instance.new("Part")
		part.Name = string.format("%s_%d", id, index)
		part.Shape = (Enum.PartType :: any)[piece.Shape]
		part.Size = Vector3.new(piece.Size[1], piece.Size[2], piece.Size[3])
		local rot = piece.Rot or { 0, 0, 0 }
		part.CFrame = origin
			* CFrame.new(piece.Pos[1], piece.Pos[2], piece.Pos[3])
			* CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
		part.Color = Color3.fromRGB(piece.Color[1], piece.Color[2], piece.Color[3])
		part.Material = (Enum.Material :: any)[piece.Material or "SmoothPlastic"]
		part.Transparency = piece.Transparency or 0
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		if piece.Light then
			local light = Instance.new("PointLight")
			light.Range = piece.Light
			light.Color = part.Color
			light.Brightness = 1.5
			light.Parent = part
		end
		part.Parent = model
	end
	return model
end

return DecorationModel
