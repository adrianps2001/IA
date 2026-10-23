#!/usr/bin/env python3
"""Rellena docs/index.html (y docs/juego.html) con código y datos reales del proyecto.

- <pre class="code" data-file="src/..." data-fn="Nombre"> copia esa función del archivo.
- <pre class="code" data-file="src/..." data-from="texto" data-to="texto"> copia ese bloque.
- <span data-loc="src/..."> recibe el número de líneas del archivo.
- <script id="game-data"> recibe el JSON de tools/export_data.luau (Config, genes, rarezas...).

Uso:
  python3 tools/build_docs.py          # actualiza docs/index.html
  python3 tools/build_docs.py --check  # falla si la web no está al día (para la CI)

Necesita el ejecutable `luau` en el PATH (o en la variable de entorno LUAU).
"""

import html
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGES = [os.path.join(ROOT, "docs", "index.html"), os.path.join(ROOT, "docs", "juego.html")]

PRE_RE = re.compile(r'<pre class="code"([^>]*)><code class="language-(\w+)">(.*?)</code></pre>', re.S)
ATTR_RE = re.compile(r'([\w-]+)="([^"]*)"')
LOC_RE = re.compile(r'(<span data-loc="([^"]+)">)(.*?)(</span>)')
DATA_RE = re.compile(r'(<script id="game-data" type="application/json">)(.*?)(</script>)', re.S)


def read_lines(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read().split("\n")


def find_function(lines, name, path):
    starts = (f"function {name}(", f"local function {name}(", f"{name} = function(")
    for i, line in enumerate(lines):
        stripped = line.lstrip("\t ")
        if stripped.startswith(starts):
            indent = line[: len(line) - len(stripped)]
            first = i
            # Incluye los comentarios que la preceden.
            while first > 0 and lines[first - 1].startswith(indent + "--"):
                first -= 1
            for j in range(i + 1, len(lines)):
                if lines[j].rstrip() == indent + "end":
                    return first, j
            break
    raise SystemExit(f"No encuentro la función {name} en {path}")


def find_block(lines, start_text, end_text, path):
    for i, line in enumerate(lines):
        if start_text in line:
            if not end_text:
                return i, i
            # "^texto" = la primera línea que empieza exactamente por ese texto.
            anchored = end_text.startswith("^")
            target = end_text[1:] if anchored else end_text
            for j in range(i + 1, len(lines)):
                hit = lines[j].startswith(target) if anchored else target in lines[j]
                if hit:
                    return i, j
            break
    raise SystemExit(f"No encuentro el bloque '{start_text}' en {path}")


def dedent(block):
    indents = [len(l) - len(l.lstrip("\t")) for l in block if l.strip()]
    cut = min(indents) if indents else 0
    return [l[cut:] if l.strip() else "" for l in block]


def render_snippet(match):
    attrs = dict(ATTR_RE.findall(match.group(1)))
    path = attrs["data-file"]
    lines = read_lines(path)
    if "data-fn" in attrs:
        a, b = find_function(lines, attrs["data-fn"], path)
    elif "data-from" in attrs:
        a, b = find_block(lines, html.unescape(attrs["data-from"]), html.unescape(attrs.get("data-to", "")), path)
    else:
        a, b = 0, len(lines) - 1
        while b > 0 and not lines[b].strip():
            b -= 1
    attrs["data-lines"] = f"{a + 1}-{b + 1}"
    code = "\n".join(dedent(lines[a : b + 1]))
    attr_text = "".join(f' {k}="{v}"' for k, v in attrs.items())
    lang = match.group(2)
    return f'<pre class="code"{attr_text}><code class="language-{lang}">{html.escape(code, quote=False)}</code></pre>'


def render_loc(match):
    lines = read_lines(match.group(2))
    count = len([l for l in lines if l.strip()])
    return f"{match.group(1)}{count}{match.group(4)}"


def game_data():
    luau = os.environ.get("LUAU", "luau")
    result = subprocess.run(
        [luau, "tools/export_data.luau"], cwd=ROOT, capture_output=True, text=True, check=True
    )
    return result.stdout.strip().replace("</", "<\\/")


def build(source, data):
    out = PRE_RE.sub(render_snippet, source)
    out = LOC_RE.sub(render_loc, out)
    out = DATA_RE.sub(lambda m: m.group(1) + data + m.group(3), out)
    return out


def main():
    data = game_data()
    stale = []
    for page in PAGES:
        name = os.path.relpath(page, ROOT)
        with open(page, encoding="utf-8") as f:
            source = f.read()
        output = build(source, data)
        if "--check" in sys.argv:
            if output != source:
                stale.append(name)
            else:
                print(f"{name} está al día")
            continue
        with open(page, "w", encoding="utf-8") as f:
            f.write(output)
        print(f"{name} actualizado ({len(PRE_RE.findall(output))} fragmentos de código)")
    if stale:
        print(f"{', '.join(stale)} no está al día: ejecuta python3 tools/build_docs.py")
        sys.exit(1)


if __name__ == "__main__":
    main()
