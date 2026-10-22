--!strict
-- Codificador JSON mínimo para las herramientas que corren fuera de Roblox (luau CLI).
-- Las tablas con índices 1..n se codifican como arrays; las demás como objetos con claves
-- ordenadas, así la salida es estable entre ejecuciones.

local Json = {}

local function isArray(t: { [any]: any }): boolean
	local count = 0
	for _ in t do
		count += 1
	end
	return count == #t
end

function Json.encode(value: any): string
	local kind = type(value)
	if kind == "nil" then
		return "null"
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "null"
		end
		if value == math.floor(value) and math.abs(value) < 1e15 then
			return string.format("%d", value)
		end
		return string.format("%.10g", value)
	elseif kind == "string" then
		local escaped = string.gsub(value, '[%c"\\]', function(c: string)
			local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r" }
			return map[c] or string.format("\\u%04x", string.byte(c))
		end)
		return '"' .. escaped .. '"'
	elseif kind == "table" then
		local parts = {}
		if isArray(value) and #value > 0 then
			for _, item in value do
				table.insert(parts, Json.encode(item))
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for key in value do
			table.insert(keys, tostring(key))
		end
		table.sort(keys)
		for _, key in keys do
			local item = value[key]
			if item == nil then
				item = value[tonumber(key)]
			end
			table.insert(parts, Json.encode(key) .. ":" .. Json.encode(item))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

return Json
