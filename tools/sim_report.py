#!/usr/bin/env python3
"""Genera el informe del simulador de bots (docs/simulacion.html).

Lanza en paralelo el simulador (sim/run.luau) con la configuración de la versión 1 del GDD
(valores de BEFORE) y con la ACTUAL (v2) de src/shared/Config.luau, con las mismas semillas,
y guarda los resultados agregados dentro de la página (<script id="sim-data">).

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
# Valores de la versión 1 del GDD (antes del repaso de mecánicas). El informe compara la v1
# con la configuración actual (v2) usando las mismas semillas.
BEFORE = {
    "Round.IncubationTime": 480,
    "Round.HatchTime": 30,
    "Round.ChaseTime": 180,
    "Round.BloodMoonChaseTime": 300,
    "Round.ResultsTime": 15,
    "Round.IntermissionTime": 15,
    "Round.PlayersPerCreature": 100,
    "Round.GoldenRainSeconds": 0,
    "Round.BarGoalBase": 6000,
    "Round.BarGoalPerPlayer": 1150,
    "Chase.TapSteal": "false",
    "Chase.SecureSeconds": 25,
    "Chase.OvertimeSeconds": 45,
    "Shields.Enabled": "false",
    "ForestThieves.Enabled": "false",
    "Election.NewPlayerRounds": 0,
    "Heat.BagGamePassMultiplier": 1.5,
    "Heat.BumpSameTargetCooldown": 0,
    "Heat.NewPlayerProtectionRounds": 0,
    "Incubator.WelcomeEggSeconds": 0,
    "Favorites.Max": 0,
    "Release.BulkMaxRarity": "Common",
    "PriceScale": 1,
}

# Por qué se cambió cada valor (se muestra en la tabla del informe).
WHY = {
    "Round.IncubationTime": "La fase más larga (8 min) casi no decidía quién ganaba y se hacía repetitiva. Con 3,5 min caben el doble de rondas por sesión.",
    "Round.HatchTime": "30 s mirando una ruleta sin poder moverse era demasiado. Ahora 10 s y la cámara no se bloquea.",
    "Round.ChaseTime": "Con varias criaturas y escudos, 2 min bastan para que se asegure o se decida en la prórroga.",
    "Round.BloodMoonChaseTime": "Proporcional a la nueva persecución.",
    "Round.ResultsTime": "Los resultados se ven mientras empieza la siguiente ronda.",
    "Round.IntermissionTime": "Menos espera entre rondas.",
    "Round.PlayersPerCreature": "Una criatura más por cada 5 perseguidores (hasta 3): con 12 jugadores ya no es 11 contra 1.",
    "Round.GoldenRainSeconds": "Lluvia de brasas doradas a mitad de la incubación: un objetivo común en la fase de recoger.",
    "Round.BarGoalBase": "La meta de la barra se ajusta a la incubación más corta: sigue acabando de media entre el 55 y el 70 %.",
    "Round.BarGoalPerPlayer": "Igual que la base.",
    "Chase.TapSteal": "Robar con un toque y un tira y afloja en vez de mantener el botón (incómodo en móvil).",
    "Chase.SecureSeconds": "Con menos robos por criatura, asegurar pide un poco más.",
    "Chase.OvertimeSeconds": "Proporcional a la nueva persecución.",
    "Shields.Enabled": "Escudos de Afinidad: depositar Calor ayuda a conservar la criatura. Sustituyen al escudo de pago.",
    "ForestThieves.Enabled": "Zorros del bosque en servidores de menos de 6: tensión cuando hay pocos jugadores.",
    "Election.NewPlayerRounds": "En su primera ronda, un novato tiene el mínimo más alto (12 %).",
    "Heat.BagGamePassMultiplier": "La Bolsa Grande (+50 % de Calor) era pagar por ganar: más Calor daba más probabilidad de ser elegido.",
    "Heat.BumpSameTargetCooldown": "No se puede empujar a la misma persona una y otra vez.",
    "Heat.NewPlayerProtectionRounds": "Los novatos no pueden ser empujados en sus 5 primeras rondas.",
    "Incubator.WelcomeEggSeconds": "Huevo de bienvenida: el novato ve el ciclo del nido en 2 minutos.",
    "Favorites.Max": "3 favoritas que sobreviven a la Nueva generación.",
    "Release.BulkMaxRarity": "Casi no salen Comunes: \"liberar guardadas\" también libera Raras.",
    "PriceScale": "Con ~4,6 veces más victorias por hora, los precios en Monedas suben 2,5 veces para que la progresión del nido siga igual.",
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
    """Estadísticas de la persecución por criatura (puede haber varias por ronda)."""
    chases = [c for r in rounds for c in r["Chases"]]
    n = len(chases)
    share = lambda f: sum(1 for c in chases if f(c)) / n
    ends = Counter()
    for c in chases:
        if c["Escaped"]:
            ends["Fuga"] += 1
        elif c.get("Secured"):
            ends["Asegurada"] += 1
        elif c.get("Overtime"):
            ends["Prórroga"] += 1
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
        "Secured": share(lambda c: c.get("Secured")),
        "Overtime": share(lambda c: c.get("Overtime")),
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
    """Busca una partida con algo de todo: varias criaturas, robos, escudos y un final claro."""
    best, best_score = None, -1
    for seed in seeds:
        data = run(["repeticion", seed, 12])
        s = data["Summary"]
        chases = s["Chases"]
        if any(c["Escaped"] for c in chases):
            continue
        score = min(s["Steals"], 8) + 2 * min(s.get("ShieldBlocks", 0), 2) + (2 if s.get("Doors") else 0)
        score += 3 * sum(1 for c in chases if c.get("Secured")) + 2 * sum(1 for c in chases if c.get("Overtime"))
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
