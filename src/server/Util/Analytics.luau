--!strict
-- Analítica en el panel de Roblox (GDD 11.1; v3.1 amplía el embudo):
-- * Embudo de incorporación: 1 Entrar, 2 Primer depósito, 3 Primera eclosión, 4 Primera compra.
-- * Economía (LogEconomyEvent): de dónde salen y en qué se gastan las Monedas y el polvo. Se
--   agrupa por jugador y motivo y se envía cada FLUSH segundos, porque Roblox limita cuántos
--   eventos se pueden mandar (la producción del nido, por ejemplo, cambia cada segundo).
-- * Eventos de partida (LogCustomEvent): rondas, robos, quién gana, criaturas raras.
-- Todo va en pcall: si la analítica falla, el juego sigue.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

local Analytics = {}

local FLUSH = 60

function Analytics.funnel(player: Player, step: number, name: string)
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
	end)
end

-- Motivo: "Tipo:Artículo". El tipo es uno de los de Roblox (Gameplay, Shop, IAP, TimedReward,
-- Onboarding…); el artículo, lo que se compró o de dónde vino ("Upgrade_Bag", "Release"...).
type Pending = { Amount: number, Currency: string, Source: boolean, Kind: string, Sku: string }
local pending: { [Player]: { [string]: Pending } } = {}

function Analytics.economy(player: Player, currency: string, amount: number, reason: string?)
	if amount == 0 then
		return
	end
	local kind, sku = string.match(reason or "Gameplay:Other", "^(%w+):?(.*)$")
	local source = amount > 0
	local key = string.format("%s|%s|%s|%s", currency, if source then "+" else "-", kind or "Gameplay", sku or "")
	local list = pending[player]
	if not list then
		list = {}
		pending[player] = list
	end
	local entry = list[key]
	if not entry then
		entry = { Amount = 0, Currency = currency, Source = source, Kind = kind or "Gameplay", Sku = if sku and sku ~= "" then sku else "Other" }
		list[key] = entry
	end
	entry.Amount += math.abs(amount)
end

local balances: ((Player, string) -> number)? = nil
-- DataService le dice cómo leer el saldo actual (para no depender de él aquí).
function Analytics.setBalanceReader(reader: (Player, string) -> number)
	balances = reader
end

local function flushPlayer(player: Player)
	local list = pending[player]
	pending[player] = nil
	if not list then
		return
	end
	for _, entry in list do
		local amount = math.floor(entry.Amount)
		if amount > 0 then
			local balance = if balances then (balances :: (Player, string) -> number)(player, entry.Currency) else 0
			pcall(function()
				local kind = (Enum.AnalyticsEconomyTransactionType :: any)[entry.Kind]
				AnalyticsService:LogEconomyEvent(
					player,
					if entry.Source then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink,
					entry.Currency,
					amount,
					math.floor(balance),
					if kind then kind.Name else entry.Kind,
					entry.Sku
				)
			end)
		end
	end
end

-- Evento con nombre y valor (aparece en Analytics → Custom events).
function Analytics.event(player: Player, name: string, value: number?, fields: { [string]: string }?)
	pcall(function()
		local custom = nil
		if fields then
			custom = {}
			local slot = 1
			for k, v in fields do
				if slot > 3 then
					break
				end
				custom[(Enum.AnalyticsCustomFieldKeys :: any)["CustomField0" .. slot].Name] = k .. ":" .. v
				slot += 1
			end
		end
		AnalyticsService:LogCustomEvent(player, name, value or 1, custom)
	end)
end

function Analytics.start()
	task.spawn(function()
		while true do
			task.wait(FLUSH)
			for player in pending do
				if player.Parent then
					flushPlayer(player)
				else
					pending[player] = nil
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(flushPlayer)
end

return Analytics
