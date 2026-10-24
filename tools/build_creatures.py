#!/usr/bin/env python3
"""Genera la galería de criaturas (docs/criaturas.html) a partir del código real del juego.

Ejecuta fuera de Roblox los estilos de criatura (src/shared/CreatureStyles) con una imitación
mínima de los tipos de Roblox (tools/RobloxMock.luau), saca las piezas de cada criatura y las
guarda dentro de la página, que las dibuja en 3D. Así se puede ver cómo quedan las criaturas
(y comparar estilos) sin abrir Studio.

Uso:
  python3 tools/build_creatures.py            # estilo de Config.Creatures.Style
  python3 tools/build_creatures.py Classic    # otro estilo

Necesita `luau` en el PATH (o en la variable de entorno LUAU).
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGE = os.path.join(ROOT, "docs", "criaturas.html")
LUAU = os.environ.get("LUAU", "luau")

MOCK_NAMES = ["Instance", "Vector3", "CFrame", "Color3", "Enum", "ColorSequence", "NumberSequence", "NumberRange", "Vector2", "UDim2"]
PRELUDE = 'local __M = require("./RobloxMock")\nlocal ' + ", ".join(MOCK_NAMES) + " = " + ", ".join(f"__M.{n}" for n in MOCK_NAMES) + "\n"

# Muestras: cada cuerpo con una cabeza distinta, y cada cabeza con varios patrones y auras.
DRIVER = r'''
local Mock = require("./RobloxMock")
local Style = require("./STYLE")
local Parts = require("./Parts")
local Cosmetics = require("./Cosmetics")
local CosmeticsModel = require("./CosmeticsModel")
local hatFor = nil
local Genes = require("./Genes")
local Creature = require("./Creature")
local Rarity = require("./Rarity")
local Json = require("./Json")

local bodies, heads, patterns, auras, mutations = {}, {}, {}, {}, {}
for _, slot in { "Body", "Head", "Pattern", "Aura", "Mutation" } do
	local list = ({ Body = bodies, Head = heads, Pattern = patterns, Aura = auras, Mutation = mutations })[slot]
	for id, gene in Genes.ById do
		if gene.Slot == slot then
			table.insert(list, gene)
		end
	end
	table.sort(list, function(a, b)
		if Rarity.tier(a.Rarity) ~= Rarity.tier(b.Rarity) then
			return Rarity.tier(a.Rarity) < Rarity.tier(b.Rarity)
		end
		return a.Id < b.Id
	end)
end

local samples = {}
local group = "Body"
local function add(body, head, pattern, aura, mutation)
	local genes = { Body = body.Id, Head = head.Id, Pattern = pattern.Id, Aura = aura.Id, Mutation = mutation.Id }
	local creature = Creature.new("demo", genes, "Demo", 0)
	local model = Mock.Instance.new("Model")
	local color = Mock.Color3.fromRGB(body.Color[1], body.Color[2], body.Color[3])
	if genes.Mutation == "mut_golden" then
		color = Mock.Color3.fromRGB(255, 200, 40)
	end
	local body = Style.build(model, genes, 1, color)
	if aura.Id == "aura_blackhole" then
		Parts.blackHole(model, body)
	end
	if hatFor then
		CosmeticsModel.buildHat(hatFor, CosmeticsModel.hatSeat(body), body.Size.X, model)
	end
	table.insert(samples, {
		Group = group,
		Name = if hatFor then (Cosmetics.get(hatFor) :: any).Icon .. " " .. (Cosmetics.get(hatFor) :: any).Name else Creature.name(creature),
		Rarity = creature.Rarity,
		RarityName = Rarity.Info[creature.Rarity].DisplayName,
		RarityColor = Rarity.Info[creature.Rarity].Color,
		Genes = { Body = body.Name, Head = head.Name, Pattern = pattern.Name },
		Parts = Mock.export(model),
	})
end
local normal = Genes.get("mut_none")
for i, body in bodies do
	add(body, heads[(i - 1) % #heads + 1], patterns[(i + 2) % #patterns + 1], auras[1], normal)
end
group = "Head"
for i, head in heads do
	add(bodies[(i * 5) % #bodies + 1], head, patterns[(i * 3) % #patterns + 1], auras[1], normal)
end
-- Las Secretas (v3.1): un gen Secreto en cada ranura, solos y juntos.
group = "Secret"
local g = Genes.get
add(g("body_phoenix"), g("head_unicorn"), g("pattern_aurora"), g("aura_blackhole"), g("mut_rainbow"))
add(g("body_phoenix"), g("head_beak"), g("pattern_plain"), g("aura_none"), normal)
add(g("body_round"), g("head_unicorn"), g("pattern_spots"), g("aura_none"), normal)
add(g("body_chubby"), g("head_ears"), g("pattern_aurora"), g("aura_none"), normal)
add(g("body_cloud"), g("head_halo"), g("pattern_galaxy"), g("aura_blackhole"), normal)
add(g("body_phoenix"), g("head_crown"), g("pattern_aurora"), g("aura_none"), normal)
-- Sombreros de la Tienda de la Plaza (v3.1) sobre criaturas comunes.
group = "Hat"
for i, item in Cosmetics.Catalog do
	if item.Kind == "Hat" then
		hatFor = item.Id
		add(bodies[(i * 3) % 5 + 1], heads[(i * 2) % 5 + 1], patterns[1], auras[1], normal)
	end
end
hatFor = nil
print(Json.encode(samples))
'''


def style_name():
    if len(sys.argv) > 1:
        return sys.argv[1]
    config = open(os.path.join(ROOT, "src", "shared", "Config.luau"), encoding="utf-8").read()
    m = re.search(r'Config\.Creatures\s*=\s*\{\s*Style\s*=\s*"(\w+)"', config)
    return m.group(1) if m else "Chibi"


def transform(source):
    source = re.sub(r"require\(script\.Parent\.Parent\.(\w+)\)", r'require("./\1")', source)
    source = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', source)
    source = source.replace("--!strict\n", "")
    return PRELUDE + source


def main():
    style = style_name()
    shared = os.path.join(ROOT, "src", "shared")
    with tempfile.TemporaryDirectory() as tmp:
        for name in ("Genes", "Rarity", "Creature"):
            shutil.copy(os.path.join(shared, f"{name}.luau"), os.path.join(tmp, f"{name}.luau"))
        shutil.copy(os.path.join(ROOT, "tools", "Json.luau"), os.path.join(tmp, "Json.luau"))
        shutil.copy(os.path.join(ROOT, "tools", "RobloxMock.luau"), os.path.join(tmp, "RobloxMock.luau"))
        shutil.copy(os.path.join(shared, "Cosmetics.luau"), os.path.join(tmp, "Cosmetics.luau"))
        cosmetics = open(os.path.join(shared, "CosmeticsModel.luau"), encoding="utf-8").read().replace('require("./CreatureStyles/Parts")', 'require("./Parts")')
        with open(os.path.join(tmp, "CosmeticsModel.luau"), "w", encoding="utf-8") as f:
            f.write(transform(cosmetics))
        for name in ("Parts", style):
            with open(os.path.join(shared, "CreatureStyles", f"{name}.luau"), encoding="utf-8") as f:
                code = transform(f.read())
            with open(os.path.join(tmp, f"{name}.luau"), "w", encoding="utf-8") as f:
                f.write(code)
        with open(os.path.join(tmp, "driver.luau"), "w", encoding="utf-8") as f:
            f.write(DRIVER.replace("STYLE", style))
        out = subprocess.run([LUAU, "driver.luau"], cwd=tmp, capture_output=True, text=True)
        if out.returncode != 0:
            sys.exit(out.stderr or out.stdout)
        samples = json.loads(out.stdout)

    with open(PAGE, encoding="utf-8") as f:
        page = f.read()
    payload = json.dumps({"Style": style, "Samples": samples}, ensure_ascii=False, separators=(",", ":"))
    page = re.sub(
        r'(<script id="creature-data" type="application/json">)(.*?)(</script>)',
        lambda m: m.group(1) + payload + m.group(3),
        page,
        flags=re.S,
    )
    with open(PAGE, "w", encoding="utf-8") as f:
        f.write(page)
    print(f"docs/criaturas.html actualizado: {len(samples)} criaturas (estilo {style})")


if __name__ == "__main__":
    main()
