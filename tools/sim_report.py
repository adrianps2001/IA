#!/usr/bin/env python3
"""Genera el informe del simulador de bots (docs/simulacion.html).

Compara la versión anterior del GDD con la ACTUAL (src/shared/Config.luau). La v3 cambió las
reglas de la persecución (ya no hay nido al que llevar la criatura), así que la v2 ya no se
puede volver a simular: sus resultados están guardados en tools/sim_baseline_v2.json (son los
que dio este mismo script con la v2, con las mismas semillas y tamaños). Lanza en paralelo el
simulador (sim/run.luau) con la configuración actual y guarda los resultados agregados dentro
de la página (<script id="sim-data">).

Uso:
  python3 tools/sim_report.py                     # completo (~3-4 min con 4 núcleos)
  python3 tools/sim_report.py --rapido            # menos partidas y días, para probar
  python3 tools/sim_report.py --guardar datos.json  # además guarda los datos en un archivo
  python3 tools/sim_report.py --cargar datos.json   # no simula: reutiliza datos guardados

Necesita `luau` en el PATH (o en la variable de entorno LUAU).
"""

import json
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASELINE = os.path.join(ROOT, "tools", "sim_baseline_v2.json")
PAGE = os.path.join(ROOT, "docs", "simulacion.html")
LUAU = os.environ.get("LUAU", "luau")

LABELS = {"before": "v2", "after": "v3"}

# Qué cambió de la v2 a la v3 (valor en la v2, ruta en Config y por qué). Los que ya no
# existen en Config se muestran como "(quitado)".
CHANGES = [
    ("Chase.CarrierSpeedMultiplier", 0.9, "Sin nido al que llegar, un portador más lento acababa siempre alcanzado (el elegido solo la conservaba el 16 %). Va a la misma velocidad que los demás."),
    ("Chase.SecureSeconds", 30, "Ya no se asegura en el nido: gana quien tenga la criatura cuando se acaba el tiempo."),
    ("Chase.OvertimeSeconds", 30, "Sin nido no hay prórroga de \"el primero que llegue\"."),
    ("Chase.HomeHoldMultiplier", 1.5, "Sin defensa en casa."),
    ("Chase.IntruderSpeedMultiplier", 0.6, "Sin territorio: los nidos de la arena son solo el punto de salida."),
    ("Chase.DoorCloseTime", 10, "Sin puerta del nido."),
    ("Chase.RevealEvery", None, "Señal: cada 8 s los portadores se ven a través de los árboles durante 2 s; entre señales hay que buscarlos por el parkour."),
    ("Chase.RevealSeconds", None, "Duración de cada señal."),
    ("Chase.FinalRevealSeconds", None, "En los últimos 10 s se les ve todo el rato: final con todos a la vista."),
    ("Round.BloodMoonChaseTime", 180, "Sin prórroga, la Luna de Sangre alarga un poco menos la persecución."),
    ("Arena.EmbersOnTrees", None, "Una cuarta parte de las brasas sale en lo alto de los árboles: también se sube durante la incubación."),
]

ARCHS = ["Newbie", "Casual", "Collector", "Thief", "Grinder", "Payer"]


def run(args, overrides=None):
    cmd = [LUAU, "--codegen", "sim/run.luau", "-a", *[str(a) for a in args]]
    if overrides:
        cmd += [f"{k}={v}" for k, v in overrides.items()]
    out = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def current_config():
    out = subprocess.run([LUAU, "tools/export_data.luau"], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return json.loads(out)["Config"]


def lookup(config, path):
    value = config
    for key in path.split("."):
        value = value[key]
    return value


def mean(values):
    values = list(values)
    return sum(values) / len(values) if values else 0


def chase_stats(rounds):
    """Estadísticas de la persecución por criatura (puede haber varias por ronda)."""
    chases = [c for r in rounds for c in r["Chases"]]
    n = len(chases)
    share = lambda f: sum(1 for c in chases if f(c)) / n
    ends = Counter()
    for c in chases:
        if c["Escaped"]:
            ends["Fuga"] += 1
        elif c.get("LastChangeAgo", 99) <= 10:
            ends["Robada en los últimos 10 s"] += 1
        else:
            ends["Al acabar el tiempo"] += 1
    steals = Counter(min(c["Steals"], 30) for c in chases)
    winners = Counter(c["WinnerArch"] for c in chases if c.get("WinnerArch"))
    return {
        "Rounds": len(rounds),
        "Creatures": n / len(rounds),
        "RoundMinutes": mean(r["DurationSeconds"] for r in rounds) / 60,
        "Escape": share(lambda c: c["Escaped"]),
        "ChosenWins": share(lambda c: c["WinnerIsChosen"]),
        "LateSteal": share(lambda c: c.get("LastChangeAgo", 99) <= 10),
        "Steals": mean(c["Steals"] for c in chases),
        "Carriers": mean(c["Carriers"] for c in chases),
        "ShieldBlocks": mean(r.get("ShieldBlocks", 0) for r in rounds),
        "FoxDrops": mean(r.get("FoxDrops", 0) for r in rounds),
        "ChaseSeconds": mean(r.get("ChaseSeconds", 180) for r in rounds),
        "Bar": mean(r["BarFraction"] for r in rounds),
        "EarlyFull": mean(1 if r["EarlyFull"] else 0 for r in rounds),
        "Incubation": mean(r["IncubationSeconds"] for r in rounds),
        "MinRarity": dict(Counter(r["MinRarity"] for r in rounds)),
        "Rarity": dict(Counter(c["Rarity"] for c in chases)),
        "Ends": dict(ends),
        "StealsHistogram": [steals.get(i, 0) for i in range(31)],
        "WinnerArch": {k: v / n for k, v in winners.items()},
        "Geysers": mean(r["Geysers"] for r in rounds),
        "Bumps": mean(r["Bumps"] for r in rounds),
    }


def meta_stats(meta):
    daily = []
    for snap in meta["Daily"]:
        daily.append({"Day": snap["Day"], "ByArch": snap["ByArch"]})
    players = meta["Players"]
    by_arch = defaultdict(list)
    for p in players:
        by_arch[p["Arch"]].append(p)
    summary = {}
    for arch, ps in by_arch.items():
        summary[arch] = {
            "Players": len(ps),
            "Rounds": mean(p["Rounds"] for p in ps),
            "Wins": mean(p["Wins"] for p in ps),
            "Chosen": mean(p["Chosen"] for p in ps),
            "Creatures": mean(p["Creatures"] for p in ps),
            "Generation": mean(p["Generation"] for p in ps),
            "CoinsOnline": mean(p["CoinsOnline"] for p in ps),
            "CoinsOffline": mean(p["CoinsOffline"] for p in ps),
            "DustFromRounds": mean(p["DustFromRounds"] for p in ps),
            "DustFromQuests": mean(p["DustFromQuests"] for p in ps),
            "EggsHatched": mean(p["EggsHatched"] for p in ps),
            "Bred": mean(p["Bred"] for p in ps),
            "Released": mean(p.get("Released", 0) for p in ps),
            "CoinsOnDecor": mean(p.get("CoinsOnDecor", 0) for p in ps),
            "DustOnDecor": mean(p.get("DustOnDecor", 0) for p in ps),
            "Hours": mean(p.get("PlaySeconds", 0) for p in ps) / 3600,
            "WinsPerHour": sum(p["Wins"] for p in ps) / max(sum(p.get("PlaySeconds", 0) for p in ps) / 3600, 1e-9),
            "ChosenPerHour": sum(p["Chosen"] for p in ps) / max(sum(p.get("PlaySeconds", 0) for p in ps) / 3600, 1e-9),
            "SessionsWithWin": sum(p.get("SessionsWithWin", 0) for p in ps) / max(sum(p.get("Sessions", 0) for p in ps), 1),
        }
    hours = sum(p.get("PlaySeconds", 0) for p in players) / 3600
    totals = {
        "WinsPerHour": sum(p["Wins"] for p in players) / max(hours, 1e-9),
        "SessionsWithWin": sum(p.get("SessionsWithWin", 0) for p in players) / max(sum(p.get("Sessions", 0) for p in players), 1),
        "Generation": mean(p["Generation"] for p in players),
        "Creatures": mean(p["Creatures"] for p in players),
    }
    return {
        "Daily": daily,
        "Summary": summary,
        "Totals": totals,
        "MaxCreatures": max(p["Creatures"] for p in players),
        "Rounds": len(meta["Rounds"]),
        "Elapsed": meta.get("ElapsedSeconds", 0),
    }


def pick_replay(seeds):
    """Busca una partida con algo de todo: varias criaturas, robos, escudos y un final reñido."""
    best, best_score = None, -1
    for seed in seeds:
        data = run(["repeticion", seed, 12])
        s = data["Summary"]
        chases = s["Chases"]
        if any(c["Escaped"] for c in chases):
            continue
        score = min(s["Steals"], 8) + 2 * min(s.get("ShieldBlocks", 0), 2)
        score += 2 * sum(1 for c in chases if c.get("LastChangeAgo", 99) <= 15)
        if score > best_score:
            best, best_score = data, score
    return best


def option(name):
    if name in sys.argv:
        index = sys.argv.index(name)
        if index + 1 < len(sys.argv):
            return sys.argv[index + 1]
    return None


def inject(data):
    with open(PAGE, encoding="utf-8") as f:
        page = f.read()
    payload = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    page = re.sub(
        r'(<script id="sim-data" type="application/json">)(.*?)(</script>)',
        lambda m: m.group(1) + payload + m.group(3),
        page,
        flags=re.S,
    )
    with open(PAGE, "w", encoding="utf-8") as f:
        f.write(page)
    print(f"docs/simulacion.html actualizado ({len(payload) // 1024} KB de datos)")


def main():
    cached = option("--cargar")
    if cached:
        with open(cached, encoding="utf-8") as f:
            inject(json.load(f))
        return
    quick = "--rapido" in sys.argv
    rounds = 40 if quick else 150
    days = 6 if quick else 30
    population = 36 if quick else 60
    sizes = [4, 8, 12, 16]

    with open(BASELINE, encoding="utf-8") as f:
        baseline = json.load(f)

    jobs = {}
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 2) as pool:
        # Lo más lento primero para aprovechar los núcleos.
        jobs["meta-after"] = pool.submit(run, ["meta", 7, days, population])
        for size in sizes:
            jobs[f"chase-after-{size}"] = pool.submit(run, ["lote-json", 101, rounds, size])
        jobs["replay"] = pool.submit(pick_replay, range(1, 13))
        jobs["config"] = pool.submit(current_config)
        results = {name: job.result() for name, job in jobs.items()}

    config = results["config"]
    changes = []
    for path, before, why in CHANGES:
        try:
            after = lookup(config, path)
        except (KeyError, TypeError):
            after = "(quitado)"
        changes.append({"Path": path, "Before": before if before is not None else "(no existía)", "After": after, "Why": why})

    data = {
        "Quick": quick,
        "Sizes": sizes,
        "Archs": ARCHS,
        "Labels": LABELS,
        "Chase": {
            "before": baseline["Chase"],
            "after": {str(size): chase_stats(results[f"chase-after-{size}"]["Rounds"]) for size in sizes},
        },
        "Meta": {"before": baseline["Meta"], "after": meta_stats(results["meta-after"])},
        "Replay": results["replay"],
        "Changes": changes,
        "Params": {"Rounds": rounds, "Days": days, "Population": population},
    }

    save = option("--guardar")
    if save:
        with open(save, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
    inject(data)


if __name__ == "__main__":
    main()
