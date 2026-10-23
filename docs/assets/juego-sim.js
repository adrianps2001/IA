/* Una ronda en miniatura: vista cenital con las reglas del juego (barra, umbrales, Elección,
   señal del portador, robo por toque, escudos, inmunidad, zorros) y bots sencillos. */
(function () {
  "use strict";
  var E = window.EGG;
  var canvas = document.getElementById("sim-canvas");
  if (!E || !canvas || !E.C.Round) return;
  var C = E.C, D = E.D, ctx = canvas.getContext("2d");
  var R = C.Round, CH = C.Chase, H = C.Heat;
  var MAPR = 150, DT = 0.1;
  var PARKOUR = 1.08, SIGHT = 30; // ventaja del portador en el parkour y lo que se ve entre los árboles
  var trees = (D.Arena && D.Arena.Trees) || [];
  var DW = (D.Arena && D.Arena.DeckWidth) || 5.5, SIDES = (D.Arena && D.Arena.DeckSides) || 8, MID = (D.Arena && D.Arena.MidHeight) || 66;
  var PHASES = [
    { k: "Incubation", n: "🔥 Incubación", d: R.IncubationTime, c: "#ff8a2a" },
    { k: "Hatch", n: "🐣 Eclosión", d: R.HatchTime, c: "#7b5cff" },
    { k: "Chase", n: "🏃 Persecución", d: R.ChaseTime, c: "#e0464d" },
    { k: "Results", n: "🏆 Resultados", d: R.ResultsTime, c: "#e8a400" },
  ];
  var COLORS = ["#ff6b6b", "#4dabf7", "#51cf66", "#fcc419", "#cc5de8", "#ff922b", "#20c997", "#f06595", "#94d82d", "#5c7cfa", "#e8590c", "#868e96"];
  var NAMES = ["Tú", "Ana", "Leo", "Mía", "Hugo", "Sara", "Iker", "Noa", "Teo", "Vega", "Bruno", "Alba"];
  var ZONES = { Swamp: 45, CrystalCave: 135, Ruins: 225, Bridge: 315 };

  function rnd(a, b) { return a + Math.random() * (b - a); }
  function dist(a, b) { var dx = a.x - b.x, dz = a.z - b.z; return Math.sqrt(dx * dx + dz * dz); }
  function polar(deg, r) { var a = deg * Math.PI / 180; return { x: Math.cos(a) * r, z: Math.sin(a) * r }; }
  function treeClear(x, z, pad) { for (var i = 0; i < trees.length; i++) { var t = trees[i], dx = x - t.X, dz = z - t.Z; if (dx * dx + dz * dz < Math.pow(t.Radius + DW + pad, 2)) return false; } return true; }
  function groundPoint(min, max) {
    for (var i = 0; i < 30; i++) { var a = Math.random() * Math.PI * 2, r = Math.sqrt(rnd(min * min, max * max)), x = Math.cos(a) * r, z = Math.sin(a) * r; if (treeClear(x, z, 2)) return { x: x, z: z, y: 0 }; }
    return { x: 0, z: min, y: 0 };
  }
  // Caras de las plataformas por altura, como ArenaLayout.deckSpotsByTier.
  var tiers = { low: [], mid: [], top: [] };
  trees.forEach(function (t) {
    var top = t.Decks[t.Decks.length - 1], mid = t.Radius + DW / 2;
    t.Decks.forEach(function (lv) {
      var list = lv === top ? tiers.top : lv >= MID ? tiers.mid : tiers.low;
      for (var k = 0; k < SIDES; k++) { var a = k * 2 * Math.PI / SIDES; list.push({ x: t.X + Math.cos(a) * mid, z: t.Z + Math.sin(a) * mid, y: lv, tree: t }); }
    });
  });
  function spot(list) { var s = list[Math.floor(Math.random() * list.length)]; return { x: s.x, z: s.z, y: s.y, tree: s.tree }; }

  var S; // estado de la ronda
  var playing = false, speed = 8, nPlayers = 8;
  var imgCache = {};
  function creatureImage(genes) {
    var key = JSON.stringify(genes);
    if (imgCache[key]) return imgCache[key];
    var img = new Image();
    img.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(E.creatureSVG(genes).replace(/<animate[^>]*\/>|<animateTransform[^>]*\/>/g, ""));
    imgCache[key] = img;
    return img;
  }

  function log(text) {
    var box = document.getElementById("sim-log");
    if (!box) return;
    var line = document.createElement("div");
    line.innerHTML = '<b style="color:var(--muted)">' + E.clock(S.phase === 0 ? PHASES[0].d - S.t : PHASES[S.phase].d - S.t) + "</b> " + text;
    box.prepend(line);
    while (box.children.length > 60) box.removeChild(box.lastChild);
  }

  function makeSource(kind) {
    var s = { kind: kind, taken: false, back: 0 };
    place(s);
    return s;
  }
  function place(s) {
    var p;
    if (s.kind === "ember") p = Math.random() < (C.Arena ? C.Arena.EmbersOnTrees : 0.45) && tiers.low.length ? spot(tiers.low) : groundPoint(28, 110);
    else if (s.kind === "blue") p = spot(tiers.mid);
    else if (s.kind === "purple") p = spot(tiers.top);
    else if (s.kind === "lucky") p = Math.random() < (C.Arena ? C.Arena.LuckyOnTrees : 0.25) ? spot(tiers.low.concat(tiers.mid)) : groundPoint(28, 110);
    else { var z = polar(ZONES.Swamp, 82); p = { x: z.x + rnd(-20, 20), z: z.z + rnd(-20, 20), y: 0 }; }
    s.x = p.x; s.z = p.z; s.y = p.y || 0; s.tree = p.tree || null;
  }
  function value(s) {
    var gold = S.rain > 0 ? R.GoldenRainMultiplier : 1;
    if (s.kind === "ember") return H.Ember.Amount * gold;
    if (s.kind === "blue") return H.BlueEmber.Amount * gold;
    if (s.kind === "purple") return H.PurpleEmber.Amount * gold;
    if (s.kind === "fly") return H.Firefly.Amount;
    return Math.floor(rnd(H.LuckyBlock.Min, H.LuckyBlock.Max + 1));
  }
  function respawnOf(kind) { return kind === "ember" ? H.Ember.Respawn : kind === "blue" ? H.BlueEmber.Respawn : kind === "purple" ? H.PurpleEmber.Respawn : kind === "fly" ? H.Firefly.Respawn : H.LuckyBlock.Respawn; }

  function reset() {
    var n = nPlayers;
    S = { phase: 0, t: 0, bar: 0, goal: E.barGoal(n), reached: 0, rain: 0, rainDone: false, sources: [], players: [], foxes: [], chases: [], dropped: [], hatch: null, markers: [], elapsed: 0 };
    var add = function (kind, count) { for (var i = 0; i < count; i++) S.sources.push(makeSource(kind)); };
    add("ember", H.Ember.Count); add("blue", H.BlueEmber ? H.BlueEmber.Count : 0); add("purple", H.PurpleEmber ? H.PurpleEmber.Count : 0);
    add("lucky", H.LuckyBlock.Count); add("fly", H.Firefly.Count);
    for (var i = 0; i < n; i++) {
      var a = i / n * Math.PI * 2, bag = Math.floor(rnd(0, 6)), boots = Math.floor(rnd(0, 8));
      S.players.push({
        i: i, name: NAMES[i], color: COLORS[i], me: i === 0, x: Math.cos(a) * 128, z: Math.sin(a) * 128, y: 0,
        heat: 0, cap: E.bagCapacity(bag), aff: 0, speed: C.Movement.BaseWalkSpeed * (1 + boots * C.Movement.BootsPerLevel),
        greed: rnd(0.55, 0.95), climber: Math.random(), target: null, climb: 0, stun: 0, immune: 0, shields: 0, attempts: 0,
        pity: Math.floor(rnd(0, 5)), sprint: 0, sprintReady: 0, tug: null, tugT: 0, know: null, wander: null,
      });
    }
    var box = document.getElementById("sim-log"); if (box) box.innerHTML = "";
    log("Empieza la incubación: a por Calor. La meta de la barra es <b>" + E.num(S.goal) + "</b> con " + n + " jugadores.");
    drawPhases(); side(true);
  }

  // ---------------------------------------------------------------- incubación
  function moveTo(p, tx, tz, dt, mult) {
    var dx = tx - p.x, dz = tz - p.z, d = Math.sqrt(dx * dx + dz * dz);
    if (d < 0.01) return 0;
    var step = Math.min(d, p.speed * (mult || 1) * dt);
    p.x += dx / d * step; p.z += dz / d * step;
    var r = Math.sqrt(p.x * p.x + p.z * p.z); if (r > MAPR) { p.x *= MAPR / r; p.z *= MAPR / r; }
    return d - step;
  }
  function incubate(dt) {
    var total = PHASES[0].d;
    if (!S.rainDone && S.t >= total * R.GoldenRainAt) { S.rain = R.GoldenRainSeconds; S.rainDone = true; log("🌧️ <b>¡Lluvia de brasas doradas!</b> Las brasas valen el doble " + R.GoldenRainSeconds + " s."); }
    if (S.rain > 0) S.rain -= dt;
    S.sources.forEach(function (s) {
      if (s.taken && S.t >= s.back) { s.taken = false; place(s); }
      if (s.kind === "fly" && !s.taken) { s.x += rnd(-1, 1) * 3 * dt; s.z += rnd(-1, 1) * 3 * dt; }
    });
    var left = total - S.t;
    S.players.forEach(function (p) {
      if (p.climb > 0) { p.climb -= dt; if (p.climb > 0) return; }
      var wantsDeposit = p.heat >= p.cap * p.greed || (left < 25 && p.heat > 0);
      if (wantsDeposit) {
        p.target = null; p.y = 0;
        if (moveTo(p, 0, 0, dt) < (H.DepositRadius - 4)) {
          S.bar += p.heat; p.aff += p.heat; p.heat = 0;
          var th = E.thresholdFor(Math.min(S.bar / S.goal, 1));
          if (th.reached > S.reached) { S.reached = th.reached; log("📈 Barra al <b>" + E.pct((C.Thresholds[th.reached - 1] || {}).Fraction || 1) + "</b>: mínimo " + E.RBY[th.min].DisplayName + ", suerte ×" + String(th.luck).replace(".", ",") + "."); }
        }
        return;
      }
      if (!p.target || p.target.taken) {
        var best = null, bs = 1e9;
        S.sources.forEach(function (s) {
          if (s.taken) return;
          var v = s.kind === "purple" ? 4 : s.kind === "blue" ? 2 : s.kind === "lucky" ? 4 : s.kind === "fly" ? 1.6 : 1;
          var climbCost = s.y * (1.6 - p.climber);
          var sc = (dist(p, s) + climbCost) / v * (0.8 + Math.random() * 0.4);
          if (sc < bs) { bs = sc; best = s; }
        });
        p.target = best;
      }
      var s = p.target;
      if (!s) return;
      if (moveTo(p, s.x, s.z, dt) < 2) {
        if (s.y > 0 && p.y < s.y) { p.climb = s.y / 11; p.y = s.y; return; } // subir por la rampa
        if (p.heat >= p.cap) return;
        var v = value(s);
        p.heat = Math.min(p.cap, p.heat + v);
        s.taken = true; s.back = S.t + respawnOf(s.kind); p.target = null;
        if (s.kind === "purple" && p.me) log("🟣 Has cogido una brasa morada: +" + v + ".");
        if (s.y === 0) p.y = 0;
      }
    });
  }

  // ---------------------------------------------------------------- eclosión
  function startHatch() {
    var entries = S.players.map(function (p) { return { Key: String(p.i), Affinity: p.aff, Min: E.pityMin(p.pity) }; });
    var ch = E.chances(entries, C.Election.MinChance);
    var count = E.creatureCount(S.players.length);
    var picks = E.pickMany(entries, C.Election.MinChance, count).map(Number);
    var th = E.thresholdFor(Math.min(S.bar / S.goal, 1));
    var creatures = picks.map(function () { var g = E.rollSet(E.rollRarity(th.luck, th.min)); return { genes: g, name: E.creatureName(g), rarity: E.rarityOf(g), img: creatureImage(g) }; });
    var order = S.players.slice().sort(function (a, b) { return ch[String(b.i)] - ch[String(a.i)]; }).slice(0, 5).map(function (p) { return p.i; });
    picks.forEach(function (k) { if (order.indexOf(k) < 0) order.push(k); });
    S.hatch = { ch: ch, picks: picks, creatures: creatures, order: order, spot: null };
    S.players.forEach(function (p) { p.target = null; p.climb = 0; p.y = 0; });
    log("🐣 ¡El huevo se rompe! " + (count > 1 ? count + " criaturas." : "Sale <b>" + creatures[0].name + "</b> (" + E.RBY[creatures[0].rarity].DisplayName + ")."));
  }
  function hatchStep() {
    var h = S.hatch, T = PHASES[1].d, per = T * 0.6 / h.picks.length;
    var i = Math.min(Math.floor((S.t - T * 0.2) / per), h.picks.length - 1);
    if (S.t < T * 0.2) { h.spot = null; return; }
    var local = (S.t - T * 0.2 - i * per) / per;
    if (local >= 1 || S.t > T * 0.8) { h.spot = h.picks[i]; return; }
    var steps = Math.max(h.order.length * 2, 6), k = Math.floor(Math.sqrt(local) * steps);
    h.spot = h.order[k % h.order.length];
  }
  function startChase() {
    var h = S.hatch;
    S.chases = h.picks.map(function (k, j) {
      var p = S.players[k];
      return { carrier: p, chosen: p, creature: h.creatures[j], dropped: null };
    });
    var now = 0;
    S.players.forEach(function (p) {
      var chosen = h.picks.indexOf(p.i) >= 0;
      p.shields = E.startShields(p.aff, chosen, false);
      p.stun = chosen ? 0 : CH.HeadStartSeconds;
      p.immune = chosen ? CH.StartImmunitySeconds : 0;
      p.know = null; p.wander = null;
    });
    S.chases.forEach(function (c) { log("🎯 El huevo elige a <b style=\"color:" + c.carrier.color + "\">" + c.carrier.name + "</b> (" + E.pct(h.ch[String(c.carrier.i)], 1) + ")" + (c.carrier.shields ? " con " + "🛡️".repeat(c.carrier.shields) : "") + "."); });
    S.foxes = [];
    var ft = C.ForestThieves;
    if (ft && ft.Enabled && S.players.length < ft.FillTo) {
      var nf = Math.min(ft.MaxCount, ft.FillTo - S.players.length);
      for (var f = 0; f < nf; f++) { var a = rnd(0, Math.PI * 2); S.foxes.push({ x: Math.cos(a) * 140, z: Math.sin(a) * 140, speed: C.Movement.BaseWalkSpeed * ft.SpeedMultiplier, stun: CH.HeadStartSeconds + 2 }); }
      log("🦊 Salen " + nf + " zorros del bosque (hay menos de " + ft.FillTo + " jugadores).");
    }
    S.elapsed = 0; S.markers = [];
    log("🏃 ¡Persecución! " + E.dur(PHASES[2].d) + ": gana quien la tenga al final.");
  }

  // ---------------------------------------------------------------- persecución
  function carrierOf(p) { for (var i = 0; i < S.chases.length; i++) if (S.chases[i].carrier === p) return S.chases[i]; return null; }
  function hideSpot(p, from) {
    var best = null, bs = -1;
    trees.forEach(function (t) {
      var pt = { x: t.X, z: t.Z };
      var minD = from.reduce(function (m, o) { return Math.min(m, dist(pt, o)); }, 1e9);
      var sc = minD - dist(p, pt) * 0.6 + rnd(0, 20);
      if (sc > bs) { bs = sc; best = t; }
    });
    return best;
  }
  function chase(dt) {
    var T = PHASES[2].d;
    S.elapsed = S.t;
    var remaining = T - S.t, revealed = E.isRevealed(S.elapsed, remaining);
    if (revealed && !S.wasRevealed) S.chases.forEach(function (c) { if (c.carrier) S.markers.push({ x: c.carrier.x, z: c.carrier.z, t: S.t }); });
    if (revealed && remaining > CH.FinalRevealSeconds && !S.wasRevealed) S.pulses = (S.pulses || 0) + 1;
    if (remaining <= CH.FinalRevealSeconds && !S.finalLogged) { S.finalLogged = true; log("⏳ ¡Últimos " + CH.FinalRevealSeconds + " s: todos a la vista!"); }
    S.wasRevealed = revealed;
    S.revealed = revealed;
    S.markers = S.markers.filter(function (m) { return S.t - m.t < CH.RevealEvery * 1.5; });

    S.players.forEach(function (p) {
      p.stun = Math.max(0, p.stun - dt); p.immune = Math.max(0, p.immune - dt); p.sprint = Math.max(0, p.sprint - dt); p.sprintReady = Math.max(0, p.sprintReady - dt);
      if (p.stun > 0) return;
      var mult = p.sprint > 0 ? CH.SprintMultiplier : 1;
      var mine = carrierOf(p);
      var thieves = S.players.filter(function (o) { return o !== p && !carrierOf(o); }).concat(S.foxes);
      if (mine) {
        var near = thieves.reduce(function (m, o) { return Math.min(m, dist(p, o)); }, 1e9);
        if (near < 26 && p.sprintReady <= 0) { p.sprint = CH.SprintDuration; p.sprintReady = CH.SprintCooldown; }
        if (near < 22) {
          // Huye en dirección contraria a los ladrones cercanos (y sin salirse del mapa).
          var fx = 0, fz = 0;
          thieves.forEach(function (o) { var d = dist(p, o); if (d < 45) { fx += (p.x - o.x) / (d * d + 1); fz += (p.z - o.z) / (d * d + 1); } });
          var r0 = Math.sqrt(p.x * p.x + p.z * p.z); if (r0 > 115) { fx -= p.x / r0 * 0.02; fz -= p.z / r0 * 0.02; }
          var fl = Math.sqrt(fx * fx + fz * fz) || 1;
          moveTo(p, p.x + fx / fl * 20, p.z + fz / fl * 20, dt, mult * PARKOUR);
          p.hide = null;
          return;
        }
        if (!p.hide || (p.hideT || 0) <= 0) { p.hide = hideSpot(p, thieves); p.hideT = rnd(10, 22); }
        p.hideT -= dt;
        var t = p.hide;
        if (!t) return;
        var ang = Math.atan2(p.z - t.Z, p.x - t.X);
        // En el juego el portador usa atajos, tirolinas y toboganes: aquí se imita con algo más de velocidad.
        moveTo(p, t.X + Math.cos(ang) * (t.Radius + DW), t.Z + Math.sin(ang) * (t.Radius + DW), dt, mult * PARKOUR);
        return;
      }
      // Ladrón: va a por el portador más cercano que pueda ver, o a la última marca.
      var goal = null, gd = 1e9;
      S.chases.forEach(function (c) {
        var target = c.carrier || c.dropped;
        if (!target) return;
        var d = dist(p, target), sees = c.dropped || revealed || d < SIGHT;
        if (sees && d < gd) { gd = d; goal = { x: target.x, z: target.z, c: c }; }
      });
      if (goal) p.know = { x: goal.x, z: goal.z };
      if (!goal && S.markers.length) { var m = S.markers[S.markers.length - 1]; goal = { x: m.x, z: m.z }; }
      if (!goal && p.know) goal = p.know;
      if (!goal) { if (!p.wander || dist(p, p.wander) < 4) p.wander = { x: rnd(-110, 110), z: rnd(-110, 110) }; goal = p.wander; }
      var left = moveTo(p, goal.x, goal.z, dt, mult);
      if (!goal.c && left < 3) { p.know = null; if (S.markers.length && dist(p, S.markers[S.markers.length - 1]) < 4) S.markers.pop(); }
      // Recoger una criatura del suelo
      S.chases.forEach(function (c) {
        if (c.dropped && dist(p, c.dropped) < 5) {
          c.dropped = null; c.carrier = p; p.immune = CH.ImmunityAfterSteal;
          log("🙌 <b style=\"color:" + p.color + "\">" + p.name + "</b> recoge " + c.creature.name + " del suelo.");
        }
      });
      // Robo por toque: aguantar cerca StealHoldTime
      var victim = null;
      S.chases.forEach(function (c) { if (c.carrier && c.carrier !== p && dist(p, c.carrier) <= CH.StealRange) victim = c; });
      if (!victim) { if (p.tug) p.retry = 2; p.tug = null; p.tugT = 0; return; }
      if (p.retry > 0) { p.retry -= dt; return; }
      if (p.tug !== victim) { p.tug = victim; p.tugT = 0; p.attempts++; }
      p.tugT += dt;
      if (p.tugT >= CH.StealHoldTime) {
        var old = victim.carrier;
        p.tug = null; p.tugT = 0;
        if (old.immune > 0) return;
        if (old.shields > 0) {
          old.shields--; old.immune = CH.ImmunityAfterSteal;
          log("🛡️ " + p.name + " rompe un escudo de <b style=\"color:" + old.color + "\">" + old.name + "</b>.");
          return;
        }
        victim.carrier = p; p.immune = CH.ImmunityAfterSteal; old.stun = CH.StunSeconds; old.hide = null; p.hide = null;
        log("💥 <b style=\"color:" + p.color + "\">" + p.name + "</b> le roba " + victim.creature.name + " a " + old.name + ".");
      }
    });
    // Zorros
    S.foxes.forEach(function (f) {
      f.stun = Math.max(0, f.stun - dt);
      if (f.stun > 0) return;
      var best = null, bd = 1e9;
      S.chases.forEach(function (c) { if (c.carrier) { var d = dist(f, c.carrier); if (d < bd) { bd = d; best = c; } } });
      if (!best) return;
      var dx = best.carrier.x - f.x, dz = best.carrier.z - f.z, d = Math.sqrt(dx * dx + dz * dz) || 1;
      f.x += dx / d * Math.min(d, f.speed * dt); f.z += dz / d * Math.min(d, f.speed * dt);
      if (d < 4 && best.carrier.immune <= 0) {
        var old = best.carrier;
        best.dropped = { x: old.x + rnd(-3, 3), z: old.z + rnd(-3, 3) }; best.carrier = null;
        old.stun = CH.StunSeconds; old.hide = null; f.stun = 15;
        log("🦊 ¡Un zorro tira al suelo la criatura de " + old.name + "! Cualquiera puede cogerla.");
      }
    });
  }
  function endChase() {
    S.chases.forEach(function (c) {
      if (c.carrier) log("🏆 <b style=\"color:" + c.carrier.color + "\">" + c.carrier.name + "</b> se queda con <b>" + c.creature.name + "</b>" + (c.carrier === c.chosen ? " (¡el elegido la ha conservado!)" : "") + ".");
      else log("💨 " + c.creature.name + " estaba en el suelo y se escapa.");
      if (c.chosen !== c.carrier) log("💔 " + c.chosen.name + " la perdió: recibe polvo extra y un Huevo del Elegido.");
    });
    var me = S.players[0], won = S.chases.some(function (c) { return c.carrier === me; });
    if (!won) log("✨ Tú: " + E.num(E.consolation(me.aff, me.attempts)) + " de polvo de consolación (" + E.num(me.aff) + " de Calor, " + me.attempts + " intentos de robo).");
  }

  // ---------------------------------------------------------------- bucle
  function nextPhase() {
    var ph = PHASES[S.phase].k;
    if (ph === "Incubation") { S.phase = 1; S.t = 0; startHatch(); }
    else if (ph === "Hatch") { S.phase = 2; S.t = 0; startChase(); }
    else if (ph === "Chase") { S.phase = 3; S.t = 0; endChase(); }
    else { reset(); }
    drawPhases();
  }
  function step(dt) {
    S.t += dt;
    var ph = PHASES[S.phase].k;
    if (ph === "Incubation") incubate(dt);
    else if (ph === "Hatch") hatchStep();
    else if (ph === "Chase") chase(dt);
    if (S.t >= PHASES[S.phase].d) nextPhase();
  }

  // ---------------------------------------------------------------- dibujo
  function drawPhases() {
    var box = document.getElementById("sim-phases");
    if (!box) return;
    box.innerHTML = "";
    PHASES.forEach(function (p, i) {
      var d = document.createElement("div");
      d.style.cssText = "flex:" + Math.max(p.d, 30) + ";background:" + p.c;
      d.textContent = p.n;
      if (i === S.phase) d.className = "now";
      box.appendChild(d);
    });
  }
  var sideTimer = 0;
  function side(force) {
    sideTimer -= 1;
    if (!force && sideTimer > 0) return;
    sideTimer = 6;
    var ph = PHASES[S.phase];
    document.getElementById("sim-phase").textContent = ph.n;
    document.getElementById("sim-time").textContent = E.clock(ph.d - S.t);
    var f = Math.min(S.bar / S.goal, 1), th = E.thresholdFor(f);
    document.getElementById("sim-bar-text").textContent = E.pct(f) + " (" + E.num(S.bar) + " / " + E.num(S.goal) + ")";
    document.getElementById("sim-min").textContent = E.RBY[th.min].DisplayName;
    var bi = document.querySelector("#sim-bar i"); bi.style.width = f * 100 + "%";
    var bar = document.getElementById("sim-bar");
    if (!bar.querySelector(".tick")) (C.Thresholds || []).forEach(function (t) { var k = document.createElement("span"); k.className = "tick"; k.style.left = t.Fraction * 100 + "%"; bar.appendChild(k); });
    var entries = S.players.map(function (p) { return { Key: String(p.i), Affinity: p.aff, Min: E.pityMin(p.pity) }; });
    var ch = S.hatch && S.phase > 0 ? S.hatch.ch : E.chances(entries, C.Election.MinChance);
    var box = document.getElementById("sim-players");
    box.innerHTML = S.players.slice().sort(function (a, b) { return ch[String(b.i)] - ch[String(a.i)]; }).map(function (p) {
      var c = carrierOf(p), tag = c ? " 🐣" : "", sh = S.phase >= 2 && p.shields ? " " + "🛡️".repeat(p.shields) : "";
      var extra = S.phase === 0 ? "🔥" + E.num(p.heat) + "/" + p.cap : "";
      return '<div class="row"><span class="who"><span class="dot" style="background:' + p.color + (p.me ? ";box-shadow:0 0 0 2px var(--text)" : "") + '"></span>' + (p.me ? "<b>Tú</b>" : p.name) + tag + sh + ' <small style="color:var(--muted)">' + extra + '</small></span><span class="chance-bar"><i style="width:' + Math.min(100, ch[String(p.i)] * 250) + '%"></i></span><span style="min-width:48px;text-align:right;font-weight:600">' + E.pct(ch[String(p.i)], 1) + "</span></div>";
    }).join("");
  }

  var W = canvas.width, scale = W / (2 * (MAPR + 6));
  function sx(x) { return W / 2 + x * scale; }
  function sz(z) { return W / 2 + z * scale; }
  function circle(x, z, r, fill, stroke, lw) { ctx.beginPath(); ctx.arc(sx(x), sz(z), r, 0, Math.PI * 2); if (fill) { ctx.fillStyle = fill; ctx.fill(); } if (stroke) { ctx.lineWidth = lw || 2; ctx.strokeStyle = stroke; ctx.stroke(); } }
  function draw(now) {
    var ph = PHASES[S.phase].k;
    ctx.clearRect(0, 0, W, W);
    var night = ph === "Chase" ? 0.25 : ph === "Hatch" ? 0.12 : 0;
    var g = ctx.createRadialGradient(W / 2, W / 2, 10, W / 2, W / 2, W / 2);
    g.addColorStop(0, "#7fbf6a"); g.addColorStop(1, "#3f7a45");
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(W / 2, W / 2, (MAPR + 4) * scale, 0, Math.PI * 2); ctx.fill();
    // zonas
    Object.keys(ZONES).forEach(function (k) {
      var p = polar(ZONES[k], 82), col = { Swamp: "rgba(60,120,90,.35)", CrystalCave: "rgba(120,200,255,.25)", Ruins: "rgba(200,190,160,.3)", Bridge: "rgba(140,100,60,.25)" }[k];
      circle(p.x, p.z, 23 * scale, col);
    });
    circle(0, 0, 25 * scale, "rgba(240,225,170,.55)");
    // árboles
    trees.forEach(function (t) {
      var r = (t.Radius + DW) * scale;
      ctx.save(); ctx.translate(sx(t.X), sz(t.Z));
      ctx.beginPath();
      for (var k = 0; k < SIDES; k++) { var a = (k + 0.5) * 2 * Math.PI / SIDES, rr = r / Math.cos(Math.PI / SIDES); ctx[k ? "lineTo" : "moveTo"](Math.cos(a) * rr, Math.sin(a) * rr); }
      ctx.closePath(); ctx.fillStyle = "#c98f55"; ctx.fill(); ctx.strokeStyle = "rgba(0,0,0,.2)"; ctx.lineWidth = 1; ctx.stroke();
      ctx.beginPath(); ctx.arc(0, 0, t.Radius * scale, 0, Math.PI * 2); ctx.fillStyle = "#6e4526"; ctx.fill();
      ctx.restore();
    });
    // fuentes
    if (ph === "Incubation") S.sources.forEach(function (s) {
      if (s.taken) return;
      var col = s.kind === "ember" ? (S.rain > 0 ? "#ffd43b" : "#ff8a2a") : s.kind === "blue" ? "#3b9cff" : s.kind === "purple" ? "#b04dff" : s.kind === "fly" ? "#e9ff7a" : "#ffd23f";
      if (s.kind === "lucky") { ctx.fillStyle = col; ctx.fillRect(sx(s.x) - 4, sz(s.z) - 4, 8, 8); ctx.strokeStyle = "#8a6d00"; ctx.strokeRect(sx(s.x) - 4, sz(s.z) - 4, 8, 8); return; }
      ctx.shadowColor = col; ctx.shadowBlur = s.kind === "ember" ? 6 : 12;
      circle(s.x, s.z, s.kind === "purple" ? 4.2 : s.kind === "blue" ? 3.6 : s.kind === "fly" ? 2.4 : 3, col);
      ctx.shadowBlur = 0;
    });
    // huevo o criaturas
    var pulse = 1 + Math.sin(now / 1000 * (3 + S.bar / S.goal * 6)) * 0.04;
    if (ph === "Incubation" || (ph === "Hatch" && S.t < PHASES[1].d * 0.2)) {
      var shake = ph === "Hatch" ? rnd(-2, 2) : 0;
      ctx.save(); ctx.translate(sx(0) + shake, sz(0)); ctx.scale(pulse, pulse);
      ctx.beginPath(); ctx.ellipse(0, 0, 18, 23, 0, 0, Math.PI * 2); ctx.fillStyle = "#ffe7c4"; ctx.fill(); ctx.lineWidth = 3; ctx.strokeStyle = "#ff8a2a"; ctx.stroke();
      ctx.restore();
    } else if (ph === "Hatch" && S.hatch) {
      S.hatch.creatures.forEach(function (c, j) { var off = (j - (S.hatch.creatures.length - 1) / 2) * 52; if (c.img.complete) ctx.drawImage(c.img, sx(0) + off - 30, sz(0) - 34, 60, 69); });
    }
    // marcas de la señal
    if (ph === "Chase") S.markers.forEach(function (m) { ctx.font = "16px sans-serif"; ctx.textAlign = "center"; ctx.fillText("📍", sx(m.x), sz(m.z) - 2); });
    if (night) { ctx.fillStyle = "rgba(10,10,40," + night + ")"; ctx.beginPath(); ctx.arc(W / 2, W / 2, (MAPR + 4) * scale, 0, Math.PI * 2); ctx.fill(); }
    // foco de la eclosión
    if (ph === "Hatch" && S.hatch && S.hatch.spot != null) {
      var sp = S.players[S.hatch.spot];
      var gr = ctx.createRadialGradient(sx(sp.x), sz(sp.z), 2, sx(sp.x), sz(sp.z), 30);
      gr.addColorStop(0, "rgba(255,240,170,.9)"); gr.addColorStop(1, "rgba(255,240,170,0)");
      ctx.fillStyle = gr; ctx.beginPath(); ctx.arc(sx(sp.x), sz(sp.z), 30, 0, Math.PI * 2); ctx.fill();
    }
    // tira y afloja
    if (ph === "Chase") S.players.forEach(function (p) {
      if (!p.tug || !p.tug.carrier) return;
      ctx.strokeStyle = "rgba(224,70,77,.9)"; ctx.lineWidth = 2 + 3 * p.tugT / CH.StealHoldTime; ctx.setLineDash([4, 3]);
      ctx.beginPath(); ctx.moveTo(sx(p.x), sz(p.z)); ctx.lineTo(sx(p.tug.carrier.x), sz(p.tug.carrier.z)); ctx.stroke(); ctx.setLineDash([]);
    });
    // criaturas en el suelo
    S.chases.forEach(function (c) { if (c.dropped) { ctx.font = "18px sans-serif"; ctx.textAlign = "center"; ctx.fillText("🐣", sx(c.dropped.x), sz(c.dropped.z) + 6); } });
    // jugadores
    S.players.forEach(function (p) {
      var c = ph === "Chase" ? carrierOf(p) : null;
      var r = 7;
      if (c) {
        if (S.revealed) { ctx.shadowColor = "#ffd23f"; ctx.shadowBlur = 22; circle(p.x, p.z, 13, "rgba(255,210,63,.55)"); ctx.shadowBlur = 0; }
        else { ctx.setLineDash([3, 3]); circle(p.x, p.z, 12, null, "rgba(255,255,255,.7)", 1.5); ctx.setLineDash([]); }
      }
      if (p.immune > 0 && ph === "Chase") circle(p.x, p.z, 10, null, "rgba(120,200,255,.9)", 2);
      ctx.globalAlpha = p.stun > 0 && ph === "Chase" ? 0.45 : p.climb > 0 ? 0.7 : 1;
      circle(p.x, p.z, r, p.color, p.me ? "#fff" : "rgba(0,0,0,.35)", p.me ? 3 : 1.5);
      ctx.globalAlpha = 1;
      ctx.fillStyle = "#fff"; ctx.font = "bold 9px Inter, sans-serif"; ctx.textAlign = "center"; ctx.fillText(p.name[0], sx(p.x), sz(p.z) + 3);
      if (ph === "Incubation" && p.heat > 0) { ctx.strokeStyle = "#ff8a2a"; ctx.lineWidth = 2.5; ctx.beginPath(); ctx.arc(sx(p.x), sz(p.z), 10, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * p.heat / p.cap); ctx.stroke(); }
      if (p.y > 0 && ph === "Incubation") { ctx.fillStyle = "rgba(255,255,255,.9)"; ctx.font = "9px Inter, sans-serif"; ctx.fillText("↑" + p.y, sx(p.x), sz(p.z) - 11); }
      if (c) { ctx.font = "15px sans-serif"; ctx.fillText("🐣", sx(p.x), sz(p.z) - 10); if (p.shields) { ctx.font = "10px sans-serif"; ctx.fillText("🛡️".repeat(p.shields), sx(p.x), sz(p.z) + 19); } }
    });
    S.foxes.forEach(function (f) { ctx.font = "17px sans-serif"; ctx.textAlign = "center"; ctx.fillText("🦊", sx(f.x), sz(f.z) + 6); });
    // textos grandes
    if (ph === "Chase" && S.revealed) { ctx.fillStyle = "rgba(255,210,63,.95)"; ctx.font = "bold 18px Fredoka, Inter, sans-serif"; ctx.textAlign = "center"; ctx.fillText(PHASES[2].d - S.t <= CH.FinalRevealSeconds ? "¡Todos a la vista!" : "📡 ¡Señal!", W / 2, 28); }
    if (ph === "Incubation" && S.rain > 0) { ctx.fillStyle = "#ffd43b"; ctx.font = "bold 16px Fredoka, Inter, sans-serif"; ctx.textAlign = "center"; ctx.fillText("🌧️ Lluvia dorada", W / 2, 26); }
    if (ph === "Results") { ctx.fillStyle = "rgba(0,0,0,.45)"; ctx.fillRect(0, W / 2 - 40, W, 80); ctx.fillStyle = "#fff"; ctx.font = "bold 22px Fredoka, Inter, sans-serif"; ctx.textAlign = "center"; ctx.fillText(S.chases.map(function (c) { return c.carrier ? "🏆 " + c.carrier.name : "💨 se escapó"; }).join(" · "), W / 2, W / 2 + 8); }
  }

  var last = performance.now(), acc = 0;
  function frame(now) {
    var dt = Math.min((now - last) / 1000, 0.1); last = now;
    if (playing) {
      acc += dt * speed;
      var n = 0;
      while (acc >= DT && n < 400) { step(DT); acc -= DT; n++; }
      side(false);
    }
    draw(now);
    requestAnimationFrame(frame);
  }

  var playBtn = document.getElementById("sim-play");
  playBtn.addEventListener("click", function () { playing = !playing; playBtn.textContent = playing ? "⏸ Pausa" : "▶ Jugar"; });
  document.getElementById("sim-skip").addEventListener("click", function () { nextPhase(); side(true); });
  document.getElementById("sim-reset").addEventListener("click", function () { reset(); });
  var sp = document.getElementById("sim-speed"), spo = document.getElementById("sim-speed-out");
  sp.addEventListener("input", function () { speed = Number(sp.value); spo.textContent = "×" + speed; });
  var np = document.getElementById("sim-n"), npo = document.getElementById("sim-n-out");
  np.addEventListener("input", function () { nPlayers = Number(np.value); npo.textContent = nPlayers; reset(); });

  // Empieza sola cuando se ve (y se para al salir de pantalla para no gastar).
  reset();
  if ("IntersectionObserver" in window && !E.reduced) {
    var started = false;
    new IntersectionObserver(function (es) {
      es.forEach(function (en) {
        if (en.isIntersecting && !started) { started = true; playing = true; playBtn.textContent = "⏸ Pausa"; }
      });
    }, { threshold: 0.4 }).observe(canvas);
  }
  requestAnimationFrame(frame);
  window.EGG.sim = { state: function () { return S; }, step: step, reset: reset };
})();
