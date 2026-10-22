#!/usr/bin/env python3
"""Genera el informe del simulador de bots (docs/simulacion.html).

Lanza en paralelo el simulador (sim/run.luau) con la configuración ANTERIOR a los ajustes
(valores de BEFORE) y con la ACTUAL de src/shared/Config.luau, con las mismas semillas, y
guarda los resultados agregados dentro de la página (<script id="sim-data">).

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
PAGE = os.path.join(ROOT, "docs", "simulacion.html")
LUAU = os.environ.get("LUAU", "luau")

# Valores que tenía Config antes de ajustarlo con el simulador.
BEFORE = {
    "Round.BarGoalBase": 0,
    "Round.BarGoalPerPlayer": 600,
    "Chase.HomeHoldMultiplier": 1,
    "Chase.SecureSeconds": 0,
    "Chase.IntruderSpeedMultiplier": 1,
    "Chase.HomeCarrierFullSpeed": "false",
    "Chase.StunSeconds": 0,
    "Chase.HeadStartSeconds": 0,
    "Chase.StartImmunitySeconds": 3,
    "Chase.OvertimeSeconds": 0,
    "Election.PityPerRound": 0,
    "Election.PityMaxChance": 0.02,
    "Nest.OfflineRate": 1,
    "Upgrades.Bag.Growth": 1.7,
    "Upgrades.Boots.Growth": 1.75,
    "Upgrades.Sniffer.BaseCost": 2500,
    "Upgrades.Nest.Growth": 1.55,
    "Upgrades.Incubator.Growth": 2,
    "Rebirth.BaseCoins": 1000000,
    "Breeding.CostPerTierSquared": 100,
}

# Por qué se cambió cada valor (se muestra en la tabla del informe).
WHY = {
    "Round.BarGoalBase": "La barra se llenaba siempre antes de tiempo: ahora acaba de media entre el 55 y el 70 %.",
    "Round.BarGoalPerPlayer": "Junto con la base, sirve igual para 4 que para 16 jugadores (las fuentes de Calor son fijas).",
    "Chase.HomeHoldMultiplier": "Robar dentro del nido del portador cuesta más: defender en casa tiene sentido.",
    "Chase.SecureSeconds": "Aguantar 25 s seguidos en tu nido asegura la criatura: final claro y con tensión.",
    "Chase.IntruderSpeedMultiplier": "Los intrusos van más lentos en un nido ajeno: el nido es territorio del dueño.",
    "Chase.HomeCarrierFullSpeed": "En su nido, el portador no sufre la penalización de velocidad.",
    "Chase.StunSeconds": "Quien sufre un robo queda aturdido 2 s: corta los robos en cadena.",
    "Chase.HeadStartSeconds": "El elegido sale con 4 s de ventaja mientras los demás ven la revelación.",
    "Chase.StartImmunitySeconds": "El elegido tiene 10 s de inmunidad inicial para llegar a casa.",
    "Chase.OvertimeSeconds": "Prórroga de gol de oro: casi elimina las fugas por robos en el último segundo.",
    "Election.PityPerRound": "Suerte acumulada: cada ronda sin ser elegido sube tu mínimo un 2 %.",
    "Election.PityMaxChance": "Tope de la suerte acumulada (12 %).",
    "Nest.OfflineRate": "Sin conexión se cobra el 25 %: la producción offline inflaba la economía.",
    "Upgrades.Bag.Growth": "Curva más empinada: barata al principio, meta de semanas al final.",
    "Upgrades.Boots.Growth": "Curva más empinada.",
    "Upgrades.Sniffer.BaseCost": "Precio acorde a la nueva economía.",
    "Upgrades.Nest.Growth": "El nido al máximo pasa de 1 día a 2-4 semanas según el jugador.",
    "Upgrades.Incubator.Growth": "Curva más empinada.",
    "Rebirth.BaseCoins": "La Nueva generación pasa a ser una meta de semanas.",
    "Breeding.CostPerTierSquared": "Criar vuelve a ser una decisión (antes era gratis en la práctica).",
}

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
    n = len(rounds)
    share = lambda f: sum(1 for r in rounds if f(r)) / n
    ends = Counter()
    for r in rounds:
        if r["Escaped"]:
            ends["Fuga"] += 1
        elif r.get("Secured"):
            ends["Asegurada"] += 1
        elif r.get("Overtime"):
            ends["Prórroga"] += 1
        else:
            ends["Al acabar el tiempo"] += 1
    steals = Counter(min(r["Steals"], 30) for r in rounds)
    winners = Counter(r["WinnerArch"] for r in rounds if r.get("WinnerArch"))
    return {
        "Rounds": n,
        "Escape": share(lambda r: r["Escaped"]),
        "ChosenWins": share(lambda r: r["WinnerIsChosen"]),
        "Secured": share(lambda r: r.get("Secured")),
        "Overtime": share(lambda r: r.get("Overtime")),
        "Steals": mean(r["Steals"] for r in rounds),
        "Carriers": mean(r["Carriers"] for r in rounds),
        "ChaseSeconds": mean(r.get("ChaseSeconds", 180) for r in rounds),
        "Bar": mean(r["BarFraction"] for r in rounds),
        "EarlyFull": share(lambda r: r["EarlyFull"]),
        "Incubation": mean(r["IncubationSeconds"] for r in rounds),
        "MinRarity": dict(Counter(r["MinRarity"] for r in rounds)),
        "Rarity": dict(Counter(r["Rarity"] for r in rounds)),
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
        }
    return {
        "Daily": daily,
        "Summary": summary,
        "MaxCreatures": max(p["Creatures"] for p in players),
        "Rounds": len(meta["Rounds"]),
        "Elapsed": meta.get("ElapsedSeconds", 0),
    }


def pick_replay(seeds):
    """Busca una partida con algo de todo: robos, y que acabe asegurada o en prórroga."""
    best, best_score = None, -1
    for seed in seeds:
        data = run(["repeticion", seed, 12])
        s = data["Summary"]
        score = min(s["Steals"], 8) + (4 if s.get("Secured") else 0) + (3 if s.get("Overtime") else 0) + (2 if s.get("Doors") else 0)
        if not s["Escaped"] and score > best_score:
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

    jobs = {}
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 2) as pool:
        # Lo más lento primero para aprovechar los núcleos.
        jobs["meta-before"] = pool.submit(run, ["meta", 7, days, population], BEFORE)
        jobs["meta-after"] = pool.submit(run, ["meta", 7, days, population])
        for size in sizes:
            jobs[f"chase-before-{size}"] = pool.submit(run, ["lote-json", 101, rounds, size], BEFORE)
            jobs[f"chase-after-{size}"] = pool.submit(run, ["lote-json", 101, rounds, size])
        jobs["replay"] = pool.submit(pick_replay, range(1, 13))
        jobs["config"] = pool.submit(current_config)
        results = {name: job.result() for name, job in jobs.items()}

    config = results["config"]
    changes = []
    for path, before in BEFORE.items():
        after = lookup(config, path)
        changes.append({"Path": path, "Before": before, "After": after, "Why": WHY.get(path, "")})

    data = {
        "Quick": quick,
        "Sizes": sizes,
        "Archs": ARCHS,
        "Chase": {
            variant: {str(size): chase_stats(results[f"chase-{variant}-{size}"]["Rounds"]) for size in sizes}
            for variant in ("before", "after")
        },
        "Meta": {variant: meta_stats(results[f"meta-{variant}"]) for variant in ("before", "after")},
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
