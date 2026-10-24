--!strict
-- Las seis rarezas, su orden, peso base y lenguaje visual (GDD 5.7 y 8).

export type RarityName = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Secret"

export type RarityInfo = {
	Name: RarityName,
	Tier: number,
	DisplayName: string,
	Weight: number, -- sobre 1.000.000
	-- Monedas por segundo que da CADA parte (gen) de esta rareza (v3.2): una criatura suma las
	-- de sus 5 partes. Calculado para que, de media, cada rareza produzca casi lo mismo que antes
	-- (5 partes comunes = 1/s, una Épica normal ~18/s, una Secreta ~2.700/s).
	PartIncome: number,
	Color: { number }, -- RGB 0-255
}

local Rarity = {}

local ORDER: { RarityName } = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
Rarity.Order = ORDER

local INFO: { [RarityName]: RarityInfo } = {
	Common = { Name = "Common", Tier = 1, DisplayName = "Común", Weight = 600_000, PartIncome = 0.2, Color = { 170, 170, 170 } },
	Rare = { Name = "Rare", Tier = 2, DisplayName = "Rara", Weight = 280_000, PartIncome = 1.75, Color = { 85, 200, 95 } },
	Epic = { Name = "Epic", Tier = 3, DisplayName = "Épica", Weight = 95_000, PartIncome = 11, Color = { 70, 140, 255 } },
	Legendary = { Name = "Legendary", Tier = 4, DisplayName = "Legendaria", Weight = 22_000, PartIncome = 60, Color = { 170, 85, 255 } },
	Mythic = { Name = "Mythic", Tier = 5, DisplayName = "Mítica", Weight = 2_980, PartIncome = 300, Color = { 255, 150, 40 } },
	Secret = { Name = "Secret", Tier = 6, DisplayName = "Secreta", Weight = 20, PartIncome = 2700, Color = { 255, 60, 60 } },
}
Rarity.Info = INFO

function Rarity.tier(name: RarityName): number
	return Rarity.Info[name].Tier
end

function Rarity.fromTier(tier: number): RarityName
	local clamped = math.clamp(math.floor(tier), 1, #Rarity.Order)
	return Rarity.Order[clamped]
end

function Rarity.max(a: RarityName, b: RarityName): RarityName
	return if Rarity.tier(a) >= Rarity.tier(b) then a else b
end

function Rarity.isValid(name: any): boolean
	return type(name) == "string" and Rarity.Info[name :: RarityName] ~= nil
end

-- Probabilidad de cada rareza con esos parámetros (para mostrarlas antes de comprar, GDD 9.6).
function Rarity.chances(luck: number?, minRarity: RarityName?, maxRarity: RarityName?): { [RarityName]: number }
	local luckValue = math.max(luck or 1, 0)
	local minTier = if minRarity then Rarity.tier(minRarity) else 1
	local maxTier = if maxRarity then Rarity.tier(maxRarity) else #Rarity.Order
	local weights: { [RarityName]: number } = {}
	local total = 0
	for _, name in Rarity.Order do
		local info = Rarity.Info[name]
		local weight = 0
		if info.Tier >= minTier and info.Tier <= maxTier then
			weight = info.Weight * (if info.Tier > 1 then luckValue else 1)
		end
		weights[name] = weight
		total += weight
	end
	local result: { [RarityName]: number } = {}
	for name, weight in weights do
		result[name] = if total > 0 then weight / total else 0
	end
	return result
end

-- Elige una rareza. La suerte multiplica el peso de todo lo que no es Común;
-- minRarity y maxRarity recortan el rango posible.
function Rarity.roll(rng: () -> number, luck: number?, minRarity: RarityName?, maxRarity: RarityName?): RarityName
	local luckValue = math.max(luck or 1, 0)
	local minTier = if minRarity then Rarity.tier(minRarity) else 1
	local maxTier = if maxRarity then Rarity.tier(maxRarity) else #Rarity.Order

	local total = 0
	local weights = {}
	for _, name in Rarity.Order do
		local info = Rarity.Info[name]
		local weight = 0
		if info.Tier >= minTier and info.Tier <= maxTier then
			weight = info.Weight * (if info.Tier > 1 then luckValue else 1)
		end
		weights[name] = weight
		total += weight
	end

	if total <= 0 then
		return Rarity.fromTier(minTier)
	end

	local pick = rng() * total
	for _, name in Rarity.Order do
		pick -= weights[name]
		if pick < 0 then
			return name
		end
	end
	return Rarity.fromTier(maxTier)
end

return Rarity
