--!strict
-- Estilo "Chibi" (GDD v3): criaturas redondas y monas. Un cuerpo-cabeza en forma de bola con
-- barriguita clara, ojos grandes con brillo, mofletes rosas, boquita "ω", patitas, bracitos
-- y colita. Cada gen cambia un rasgo: la cabeza da orejas, cuernitos, corona, alas...; el
-- patrón, manchas o rayas en la espalda; el cuerpo, pelusa, cristales, gelatina...
-- Mirando hacia -Z. Solo piezas básicas: barato en móvil.

local Genes = require(script.Parent.Parent.Genes)
local Rarity = require(script.Parent.Parent.Rarity)
local Parts = require(script.Parent.Parts)

local Chibi = {}

local part = Parts.part
local blob = Parts.blob
local rgb = Parts.rgb

local SHAPES: { [string]: Vector3 } = {
	body_round = Vector3.new(3, 2.8, 2.8),
	body_chubby = Vector3.new(3.5, 2.7, 3.1),
	body_long = Vector3.new(2.7, 2.5, 3.5),
	body_tiny = Vector3.new(2.4, 2.3, 2.3),
	body_fluffy = Vector3.new(3.1, 2.9, 2.9),
	body_crystal = Vector3.new(2.9, 3, 2.8),
	body_lava = Vector3.new(3, 2.8, 2.8),
	body_jelly = Vector3.new(3.2, 2.6, 3),
	body_stone = Vector3.new(3.1, 2.9, 2.9),
	body_cloud = Vector3.new(3.4, 2.6, 3),
	body_star = Vector3.new(3, 2.9, 2.8),
	body_void = Vector3.new(3, 2.9, 2.8),
	body_phoenix = Vector3.new(3, 3, 2.8),
}

local BLUSH = Color3.fromRGB(255, 140, 165)
local EYE = Color3.fromRGB(35, 25, 30)
local WHITE = Color3.new(1, 1, 1)

-- Punto de la superficie del elipsoide (centro en el origen) para una latitud y longitud
-- (longitud 0 = espalda, +Z; longitud 180° = cara, -Z).
local function onSurface(size: Vector3, lat: number, lon: number): Vector3
	return Vector3.new(size.X / 2 * math.cos(lat) * math.sin(lon), size.Y / 2 * math.sin(lat), size.Z / 2 * math.cos(lat) * math.cos(lon))
end

-- Z de la cara delantera del elipsoide en (x, y).
local function faceZ(size: Vector3, x: number, y: number): number
	local a, b, c = size.X / 2, size.Y / 2, size.Z / 2
	local t = 1 - (x / a) ^ 2 - (y / b) ^ 2
	return -c * math.sqrt(math.max(t, 0))
end

-- Pieza pegada a la superficie mirando hacia fuera (para manchas y rasgos planos).
local function stick(name: string, body: BasePart, offset: Vector3, size: Vector3, color: Color3, parent: Instance): Part
	local p = blob(name, size, color, parent)
	local world = body.CFrame * CFrame.new(offset)
	p.CFrame = CFrame.lookAt(world.Position, world.Position + (world.Position - body.Position).Unit) * CFrame.Angles(0, math.pi, 0)
	return p
end

local function addEye(body: BasePart, x: number, y: number, size: number, parent: Instance, glowing: boolean)
	local bs = body.Size
	local z = faceZ(bs, x, y) + size * 0.12
	local eye = blob("Eye", Vector3.new(size, size * 1.2, size * 0.55), if glowing then WHITE else EYE, parent)
	eye.CFrame = body.CFrame * CFrame.new(x, y, z)
	if glowing then
		eye.Material = Enum.Material.Neon
		return
	end
	-- Brillo: dos puntitos blancos (el grande arriba, el pequeño abajo).
	local shine = part("Shine", Enum.PartType.Ball, Vector3.one * size * 0.38, WHITE, parent)
	shine.CFrame = eye.CFrame * CFrame.new(-size * 0.16, size * 0.22, -size * 0.22)
	shine.Material = Enum.Material.Neon
	local small = part("Shine", Enum.PartType.Ball, Vector3.one * size * 0.18, WHITE, parent)
	small.CFrame = eye.CFrame * CFrame.new(size * 0.18, -size * 0.2, -size * 0.22)
	small.Material = Enum.Material.Neon
end

local function addMouth(body: BasePart, y: number, scale: number, parent: Instance)
	local bs = body.Size
	local holder = part("Mouth", Enum.PartType.Block, Vector3.new(0.7, 0.45, 0.05) * scale, WHITE, parent)
	holder.Transparency = 1
	holder.CFrame = body.CFrame * CFrame.new(0, y, faceZ(bs, 0, y) - 0.05 * bs.Z)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(70, 45)
	gui.LightInfluence = 1
	gui.MaxDistance = 60
	gui.Parent = holder
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(90, 45, 50)
	label.Text = "ω"
	label.Parent = gui
end

-- Construye las piezas dentro de model y devuelve el cuerpo (la PrimaryPart).
function Chibi.build(model: Model, genes: Genes.GeneSet, s: number, bodyColor: Color3): BasePart
	local headGene = Genes.get(genes.Head)
	local patternGene = Genes.get(genes.Pattern)
	local soft = Parts.tint(bodyColor, 0.18) -- color pastel
	local size = (SHAPES[genes.Body] or SHAPES.body_round) * s
	local X, Y, Z = size.X, size.Y, size.Z

	local body = blob("Body", size, soft, model)
	model.PrimaryPart = body
	local id = genes.Body
	if id == "body_jelly" then
		body.Material = Enum.Material.Glass
		body.Transparency = 0.25
	elseif id == "body_stone" then
		body.Material = Enum.Material.Slate
	elseif id == "body_void" then
		body.Color = Color3.fromRGB(45, 30, 70)
	elseif id == "body_phoenix" then
		body.Color = Color3.fromRGB(255, 140, 60) -- sin pastel: es fuego
	end

	-- Barriguita clara (abajo, para que no tape la cara).
	local bellyY = -0.25 * Y
	local belly = blob("Belly", Vector3.new(0.56 * X, 0.42 * Y, 0.3 * Z), Parts.tint(soft, 0.55), model)
	belly.CFrame = body.CFrame * CFrame.new(0, bellyY, faceZ(size, 0, bellyY) + 0.11 * Z)
	if id == "body_jelly" then
		belly.Transparency = 0.3
	end

	-- Ojos (uno grande si es cíclope; encima de las bolitas si es rana).
	local eyeSize = 0.2 * X
	local eyeY = 0.04 * Y
	local glowing = id == "body_void"
	if genes.Head == "head_frog" then
		for _, side in { -1, 1 } do
			local bump = blob("FrogBump", Vector3.one * 0.3 * X, soft, model)
			bump.CFrame = body.CFrame * CFrame.new(side * 0.24 * X, 0.43 * Y, -0.12 * Z)
			local eye = blob("Eye", Vector3.new(0.16, 0.19, 0.08) * X, EYE, model)
			eye.CFrame = bump.CFrame * CFrame.new(0, 0.01 * X, -0.13 * X)
			local shine = part("Shine", Enum.PartType.Ball, Vector3.one * 0.06 * X, WHITE, model)
			shine.CFrame = eye.CFrame * CFrame.new(-0.03 * X, 0.04 * X, -0.04 * X)
			shine.Material = Enum.Material.Neon
		end
	elseif genes.Head == "head_cyclops" then
		addEye(body, 0, eyeY + 0.04 * Y, eyeSize * 1.5, model, glowing)
	else
		for _, side in { -1, 1 } do
			if genes.Head == "head_mask" then
				-- Antifaz: un parche oscuro alrededor de cada ojo (de ladronzuelo).
				local x = side * 0.25 * X
				stick("Mask", body, Vector3.new(x, eyeY, faceZ(size, x, eyeY) + 0.02 * Z), Vector3.new(0.34 * X, 0.32 * X, 0.06 * Z), Color3.fromRGB(55, 45, 70), model)
			end
			addEye(body, side * 0.25 * X, eyeY, eyeSize, model, glowing)
		end
	end

	-- Mofletes y boquita (o piquito).
	for _, side in { -1, 1 } do
		local x, y = side * 0.37 * X, -0.13 * Y
		local cheek = blob("Blush", Vector3.new(0.17, 0.09, 0.04) * X, BLUSH, model)
		cheek.CFrame = body.CFrame * CFrame.new(x, y, faceZ(size, x, y) + 0.01)
		cheek.Transparency = 0.15
	end
	if genes.Head == "head_beak" then
		local beak = blob("Beak", Vector3.new(0.24 * X, 0.13 * X, 0.22 * X), if headGene then rgb(headGene.Color) else Color3.fromRGB(255, 190, 60), model)
		beak.CFrame = body.CFrame * CFrame.new(0, -0.1 * Y, faceZ(size, 0, -0.1 * Y) - 0.04 * X)
	else
		addMouth(body, -0.12 * Y, X / 3, model)
	end

	-- Patitas, bracitos y colita.
	local dark = Parts.shade(soft, 0.12)
	for _, side in { -1, 1 } do
		local foot = blob("Foot", Vector3.new(0.3 * X, 0.16 * Y, 0.36 * Z), dark, model)
		foot.CFrame = body.CFrame * CFrame.new(side * 0.22 * X, -0.47 * Y, -0.16 * Z)
		local arm = blob("Arm", Vector3.new(0.16 * X, 0.24 * Y, 0.16 * X), soft, model)
		arm.CFrame = body.CFrame * CFrame.new(side * 0.47 * X, -0.12 * Y, -0.1 * Z) * CFrame.Angles(0, 0, math.rad(side * 25))
		if id == "body_stone" then
			foot.Material = Enum.Material.Slate
		end
	end
	local tail = part("Tail", Enum.PartType.Ball, Vector3.one * 0.24 * X, Parts.tint(soft, 0.3), model)
	tail.CFrame = body.CFrame * CFrame.new(0, -0.22 * Y, 0.49 * Z)

	-- Rasgo de la cabeza (color del gen).
	local hc = if headGene then rgb(headGene.Color) else soft
	local h = genes.Head
	if h == "head_ears" then
		for _, side in { -1, 1 } do
			local ear = blob("Ear", Vector3.new(0.32, 0.3, 0.16) * X, hc, model)
			ear.CFrame = body.CFrame * CFrame.new(side * 0.3 * X, 0.44 * Y, 0)
			local inner = blob("EarInner", Vector3.new(0.18, 0.16, 0.06) * X, BLUSH, model)
			inner.CFrame = ear.CFrame * CFrame.new(0, -0.02 * X, -0.07 * X)
		end
	elseif h == "head_bunny" then
		for _, side in { -1, 1 } do
			local ear = blob("Ear", Vector3.new(0.18 * X, 0.62 * Y, 0.12 * X), hc, model)
			ear.CFrame = body.CFrame * CFrame.new(side * 0.17 * X, 0.7 * Y, 0) * CFrame.Angles(0, 0, math.rad(side * -12))
			local inner = blob("EarInner", Vector3.new(0.09 * X, 0.44 * Y, 0.04 * X), BLUSH, model)
			inner.CFrame = ear.CFrame * CFrame.new(0, 0, -0.05 * X)
		end
	elseif h == "head_horn" then
		local horn = blob("Horn", Vector3.new(0.13 * X, 0.34 * Y, 0.13 * X), hc, model)
		horn.CFrame = body.CFrame * CFrame.new(0, 0.6 * Y, -0.06 * Z) * CFrame.Angles(math.rad(-12), 0, 0)
	elseif h == "head_feathered" then
		for k = -1, 1 do
			local feather = blob("Feather", Vector3.new(0.08 * X, 0.36 * Y, 0.16 * X), hc, model)
			feather.CFrame = body.CFrame * CFrame.new(k * 0.09 * X, 0.6 * Y, 0) * CFrame.Angles(0, 0, math.rad(k * -22))
		end
	elseif h == "head_crown" then
		local crown = part("Crown", Enum.PartType.Cylinder, Vector3.new(0.14 * Y, 0.44 * X, 0.44 * X), hc, model)
		crown.CFrame = body.CFrame * CFrame.new(0, 0.53 * Y, 0) * CFrame.Angles(0, 0, math.rad(90))
		crown.Material = Enum.Material.Metal
		for k = 0, 2 do
			local angle = k * math.pi * 2 / 3
			local gem = part("Gem", Enum.PartType.Ball, Vector3.one * 0.08 * X, Color3.fromRGB(255, 80, 120), model)
			gem.CFrame = body.CFrame * CFrame.new(math.cos(angle) * 0.2 * X, 0.6 * Y, math.sin(angle) * 0.2 * X)
			gem.Material = Enum.Material.Neon
		end
	elseif h == "head_dragon" then
		for _, side in { -1, 1 } do
			local horn = blob("Horn", Vector3.new(0.1 * X, 0.3 * Y, 0.1 * X), hc, model)
			horn.CFrame = body.CFrame * CFrame.new(side * 0.2 * X, 0.52 * Y, 0.05 * Z) * CFrame.Angles(math.rad(25), 0, math.rad(side * -15))
			local wing = blob("Wing", Vector3.new(0.05 * X, 0.4 * Y, 0.5 * Z), hc, model)
			wing.CFrame = body.CFrame * CFrame.new(side * 0.42 * X, 0.12 * Y, 0.3 * Z) * CFrame.Angles(0, math.rad(side * 30), math.rad(side * -35))
		end
	elseif h == "head_halo" then
		local halo = part("Halo", Enum.PartType.Cylinder, Vector3.new(0.06 * Y, 0.7 * X, 0.7 * X), hc, model)
		halo.CFrame = body.CFrame * CFrame.new(0, 0.74 * Y, 0) * CFrame.Angles(0, 0, math.rad(90))
		halo.Material = Enum.Material.Neon
	elseif h == "head_unicorn" then
		-- Cuerno en espiral (piezas cada vez más finas y de colores pastel brillantes) y crin.
		local spiral = { Color3.fromRGB(255, 190, 240), Color3.fromRGB(200, 180, 255), Color3.fromRGB(170, 230, 255), Color3.fromRGB(255, 255, 255) }
		for k = 0, 3 do
			local seg = blob("UnicornHorn", Vector3.new(0.16 - k * 0.03, 0.14, 0.16 - k * 0.03) * X, spiral[k + 1], model)
			seg.CFrame = body.CFrame * CFrame.new(0, 0.5 * Y + k * 0.11 * X, -0.1 * Z - k * 0.04 * X) * CFrame.Angles(math.rad(-20), math.rad(k * 35), 0)
			seg.Material = Enum.Material.Neon
		end
		local mane = { Color3.fromRGB(255, 160, 220), Color3.fromRGB(190, 160, 255), Color3.fromRGB(150, 220, 255), Color3.fromRGB(255, 230, 160) }
		for k = 1, 4 do
			local puff = blob("Mane", Vector3.one * 0.22 * X, mane[k], model)
			puff.CFrame = body.CFrame * CFrame.new(onSurface(size, math.rad(70 - k * 14), 0) * 0.98)
		end
	elseif h == "head_comet" then
		local stalk = part("Antenna", Enum.PartType.Block, Vector3.new(0.05 * X, 0.36 * Y, 0.05 * X), Parts.shade(soft, 0.3), model)
		stalk.CFrame = body.CFrame * CFrame.new(0, 0.62 * Y, 0)
		local star = part("Comet", Enum.PartType.Ball, Vector3.one * 0.18 * X, hc, model)
		star.CFrame = body.CFrame * CFrame.new(0, 0.82 * Y, 0)
		star.Material = Enum.Material.Neon
	end

	-- Patrón en la espalda (manchas o rayas del color del gen).
	if patternGene and patternGene.Id ~= "pattern_plain" then
		local pc = rgb(patternGene.Color)
		local neon = Rarity.tier(patternGene.Rarity) >= 4
		if patternGene.Id == "pattern_aurora" then
			-- Aurora: bandas de luz verde, turquesa y violeta por la espalda.
			local bands = { Color3.fromRGB(90, 255, 170), Color3.fromRGB(80, 220, 255), Color3.fromRGB(190, 120, 255), Color3.fromRGB(120, 255, 220) }
			for k = 0, 3 do
				local lat = math.rad(-12 + k * 16)
				local p = stick("Pattern", body, onSurface(size, lat, math.rad((k % 2) * 14 - 7)) * 0.97, Vector3.new(0.78 * X * math.cos(lat), 0.07 * Y, 0.05 * Z), bands[k + 1], model)
				p.Material = Enum.Material.Neon
				p.Transparency = 0.1
			end
		elseif patternGene.Id == "pattern_stripes" or patternGene.Id == "pattern_zigzag" then
			for k = 0, 2 do
				local lat = math.rad(-5 + k * 22)
				local p = stick("Pattern", body, onSurface(size, lat, 0) * 0.97, Vector3.new(0.7 * X * math.cos(lat), 0.08 * Y, 0.06 * Z), pc, model)
				if neon then
					p.Material = Enum.Material.Neon
				end
			end
		else
			local count = 3 + Rarity.tier(patternGene.Rarity)
			for k = 1, count do
				local lon = math.rad(-70 + 140 * (k - 1) / math.max(count - 1, 1))
				local lat = math.rad(if k % 2 == 0 then 30 else -2)
				local dot = 0.2 * X * (if k % 3 == 0 then 0.8 else 1)
				local p = stick("Pattern", body, onSurface(size, lat, lon) * 0.98, Vector3.new(dot, dot, 0.06 * X), pc, model)
				if neon then
					p.Material = Enum.Material.Neon
				end
			end
		end
	end

	-- Detalles del tipo de cuerpo.
	if id == "body_fluffy" or id == "body_cloud" then
		local puffs = if id == "body_cloud" then 6 else 8
		local puffColor = if id == "body_cloud" then Color3.fromRGB(245, 248, 255) else Parts.tint(soft, 0.2)
		for k = 0, puffs - 1 do
			local lon = k * math.pi * 2 / puffs
			if math.cos(lon) > -0.45 then -- sin tapar la cara (que mira a -Z)
				local lat = if id == "body_cloud" then math.rad(5) else math.rad(-8)
				local puff = blob("Puff", Vector3.one * 0.36 * X, puffColor, model)
				puff.CFrame = body.CFrame * CFrame.new(onSurface(size, lat, lon) * 0.92)
			end
		end
	elseif id == "body_crystal" then
		for k = -1, 1 do
			local shard = part("Crystal", Enum.PartType.Block, Vector3.new(0.16 * X, 0.42 * Y, 0.16 * X), Color3.fromRGB(150, 230, 255), model)
			shard.CFrame = body.CFrame * CFrame.new(k * 0.2 * X, 0.42 * Y, 0.22 * Z) * CFrame.Angles(math.rad(25), math.rad(45), math.rad(k * 20))
			shard.Material = Enum.Material.Glass
			shard.Transparency = 0.15
		end
	elseif id == "body_lava" then
		for k = 1, 4 do
			local crack = stick("Ember", body, onSurface(size, math.rad(10 + k * 8), math.rad(-60 + k * 30)) * 0.98, Vector3.new(0.14 * X, 0.06 * X, 0.04 * X), Color3.fromRGB(255, 150, 40), model)
			crack.Material = Enum.Material.Neon
		end
	elseif id == "body_star" then
		for k = 0, 4 do
			local angle = k * math.pi * 2 / 5
			local point = part("StarPoint", Enum.PartType.Ball, Vector3.one * 0.12 * X, Color3.fromRGB(255, 240, 140), model)
			point.CFrame = body.CFrame * CFrame.new(math.cos(angle) * 0.35 * X, 0.62 * Y, math.sin(angle) * 0.35 * X)
			point.Material = Enum.Material.Neon
		end
	elseif id == "body_long" then
		local segment = blob("Segment", Vector3.new(0.72 * X, 0.7 * Y, 0.5 * Z), soft, model)
		segment.CFrame = body.CFrame * CFrame.new(0, -0.14 * Y, 0.5 * Z)
	elseif id == "body_phoenix" then
		-- Cresta y alas de llamas, cola de fuego y chispas que suben.
		local flames = { Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 150, 40), Color3.fromRGB(255, 90, 40) }
		for k = -1, 1 do
			local flame = blob("Flame", Vector3.new(0.14 * X, 0.42 * Y, 0.14 * X), flames[k + 2], model)
			flame.CFrame = body.CFrame * CFrame.new(k * 0.13 * X, 0.55 * Y, 0.08 * Z) * CFrame.Angles(math.rad(-15), 0, math.rad(k * -20))
			flame.Material = Enum.Material.Neon
		end
		for _, side in { -1, 1 } do
			for k = 0, 2 do
				local feather = blob("FlameWing", Vector3.new(0.06 * X, (0.42 - k * 0.08) * Y, 0.3 * Z), flames[k + 1], model)
				feather.CFrame = body.CFrame * CFrame.new(side * (0.46 + k * 0.05) * X, (0.18 - k * 0.1) * Y, (0.2 + k * 0.06) * Z) * CFrame.Angles(0, math.rad(side * 25), math.rad(side * (-40 + k * 15)))
				feather.Material = Enum.Material.Neon
			end
		end
		local tailFlame = blob("FlameTail", Vector3.new(0.2 * X, 0.2 * X, 0.5 * Z), flames[2], model)
		tailFlame.CFrame = body.CFrame * CFrame.new(0, -0.1 * Y, 0.62 * Z) * CFrame.Angles(math.rad(-25), 0, 0)
		tailFlame.Material = Enum.Material.Neon
		local sparks = Instance.new("ParticleEmitter")
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 80, 30))
		sparks.LightEmission = 1
		sparks.Rate = 14
		sparks.Lifetime = NumberRange.new(0.5, 1)
		sparks.Speed = NumberRange.new(1.5, 3)
		sparks.SpreadAngle = Vector2.new(25, 25)
		sparks.Size = NumberSequence.new(0.18 * s, 0)
		sparks.Parent = body
	elseif id == "body_void" then
		local stars = Instance.new("ParticleEmitter")
		stars.Color = ColorSequence.new(WHITE)
		stars.LightEmission = 1
		stars.Rate = 8
		stars.Lifetime = NumberRange.new(0.6, 1.2)
		stars.Speed = NumberRange.new(0.2, 0.6)
		stars.Size = NumberSequence.new(0.12 * s, 0)
		stars.Parent = body
	end

	return body
end

return Chibi
