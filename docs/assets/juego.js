/* The Egg Chooses · el juego explicado. Reglas copiadas de src/shared (Election, Economy,
   Rarity, Genes, ChaseRules, Events) para que las demos den los mismos números que el juego.
   Los datos (Config, genes, rarezas, parkour) los pone tools/build_docs.py en #game-data. */
(function () {
  "use strict";

  var D = {};
  try { D = JSON.parse(document.getElementById("game-data").textContent || "{}"); } catch (e) { D = {}; }
  var C = D.Config || {};
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };

  // ------------------------------------------------------------------ utilidades
  function get(path) {
    return path.split(".").reduce(function (o, k) { return o == null ? undefined : o[k]; }, C);
  }
  var nf = new Intl.NumberFormat("es-ES");
  function num(n) { return nf.format(Math.round(n)); }
  function short(n) {
    if (n >= 1e9) return (n / 1e9).toFixed(1).replace(".", ",") + " B";
    if (n >= 1e6) return (n / 1e6).toFixed(1).replace(".", ",") + " M";
    if (n >= 1e4) return (n / 1e3).toFixed(1).replace(".", ",") + " K";
    return num(n);
  }
  function pct(x, digits) { return (x * 100).toFixed(digits == null ? 0 : digits).replace(".", ",") + " %"; }
  function dur(s) {
    var m = Math.floor(s / 60), r = Math.round(s % 60);
    if (m === 0) return r + " s";
    return r ? m + " min " + r + " s" : m + " min";
  }
  function clock(s) {
    s = Math.max(0, Math.ceil(s));
    return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
  }
  function clamp(x, a, b) { return Math.max(a, Math.min(b, x)); }
  function rgb(c) { return "rgb(" + c[0] + "," + c[1] + "," + c[2] + ")"; }
  function el(tag, props, html) {
    var e = document.createElement(tag);
    if (props) Object.keys(props).forEach(function (k) {
      if (k === "style") e.style.cssText = props[k]; else if (k === "class") e.className = props[k]; else e.setAttribute(k, props[k]);
    });
    if (html != null) e.innerHTML = html;
    return e;
  }
  function on(id, ev, fn) { var e = document.getElementById(id); if (e) e.addEventListener(ev, fn); return e; }
  function rangeOut(id, fmt) {
    var input = document.getElementById(id), out = document.getElementById(id + "-out");
    function v() { return Number(input.value); }
    function show() { if (out) out.textContent = fmt ? fmt(v()) : v(); }
    show();
    return { value: v, input: input, show: show };
  }
  var reduced = window.matchMedia && matchMedia("(prefers-reduced-motion: reduce)").matches;

  // ------------------------------------------------------------------ rarezas y genes
  var RAR = D.Rarities || [];
  var RBY = {};
  RAR.forEach(function (r) { RBY[r.Name] = r; });
  function tier(name) { return RBY[name] ? RBY[name].Tier : 1; }
  function fromTier(t) { for (var i = 0; i < RAR.length; i++) if (RAR[i].Tier === t) return RAR[i].Name; return RAR[0] && RAR[0].Name; }
  var SLOTS = D.Slots || [];
  var GENES = D.Genes || {};
  var GBY = {};
  SLOTS.forEach(function (s) { (GENES[s] || []).forEach(function (g) { GBY[g.Id] = g; }); });

  // Rarity.roll
  function rollRarity(luck, minName, maxName) {
    luck = Math.max(luck || 1, 0);
    var minT = minName ? tier(minName) : 1, maxT = maxName ? tier(maxName) : RAR.length;
    var total = 0, w = {};
    RAR.forEach(function (r) {
      var x = r.Tier >= minT && r.Tier <= maxT ? r.Weight * (r.Tier > 1 ? luck : 1) : 0;
      w[r.Name] = x; total += x;
    });
    if (total <= 0) return fromTier(minT);
    var pick = Math.random() * total;
    for (var i = 0; i < RAR.length; i++) { pick -= w[RAR[i].Name]; if (pick < 0) return RAR[i].Name; }
    return fromTier(maxT);
  }
  function rarityOdds(luck, minName, maxName) {
    var minT = minName ? tier(minName) : 1, maxT = maxName ? tier(maxName) : RAR.length, total = 0, out = {};
    RAR.forEach(function (r) { var x = r.Tier >= minT && r.Tier <= maxT ? r.Weight * (r.Tier > 1 ? luck : 1) : 0; out[r.Name] = x; total += x; });
    Object.keys(out).forEach(function (k) { out[k] = total > 0 ? out[k] / total : 0; });
    return out;
  }
  function genesOfTier(slot, t) { return (GENES[slot] || []).filter(function (g) { return tier(g.Rarity) === t; }); }
  function pickFrom(list) { return list[Math.floor(Math.random() * list.length)] || list[0]; }
  // Genes.rollSlot
  function rollSlot(slot, maxName) {
    var t = tier(rollRarity(1, null, maxName));
    while (t >= 1) { var c = genesOfTier(slot, t); if (c.length) return pickFrom(c).Id; t--; }
    return GENES[slot][0].Id;
  }
  // Genes.rollSet
  function rollSet(rarity) {
    var t = tier(rarity);
    var sig = SLOTS.filter(function (s) { return genesOfTier(s, t).length > 0; });
    var signature = pickFrom(sig);
    var out = {};
    SLOTS.forEach(function (s) { out[s] = s === signature ? pickFrom(genesOfTier(s, t)).Id : rollSlot(s, rarity); });
    return out;
  }
  function rarityOf(genes) {
    var best = 1;
    SLOTS.forEach(function (s) { var g = GBY[genes[s]]; if (g) best = Math.max(best, tier(g.Rarity)); });
    return fromTier(best);
  }
  function incomeOf(genes) {
    var bonus = 0;
    SLOTS.forEach(function (s) { var g = GBY[genes[s]]; if (g) bonus += tier(g.Rarity) - 1; });
    return RBY[rarityOf(genes)].Income * (1 + (D.GeneBonusPerTier || 0.05) * bonus);
  }
  function creatureName(genes) {
    var b = GBY[genes.Body], p = GBY[genes.Pattern], m = GBY[genes.Mutation];
    var parts = [b ? b.Name : "?"];
    if (p && p.Id !== "pattern_plain") parts.push(p.Name);
    if (m && m.Id !== "mut_none") parts.push(m.Name);
    return parts.join(" ");
  }
  // Genes.inherit
  function inherit(a, b) {
    var parent = Math.max(tier(rarityOf(a)), tier(rarityOf(b)));
    var cap = fromTier(Math.min(parent + 1, tier("Mythic")));
    var child = {}, mutated = [];
    SLOTS.forEach(function (s) {
      if (Math.random() < get("Breeding.MutationChance")) { child[s] = rollSlot(s, cap); mutated.push(s); }
      else child[s] = Math.random() < 0.5 ? a[s] : b[s];
    });
    return { genes: child, mutated: mutated };
  }

  // ------------------------------------------------------------------ reglas de la ronda
  // Election.chances
  function chances(entries, minChance) {
    var res = {}, n = entries.length;
    if (!n) return res;
    var minOf = function (e) { return e.Min != null ? e.Min : minChance; };
    var totalMin = entries.reduce(function (a, e) { return a + minOf(e); }, 0);
    if (totalMin >= 1) { entries.forEach(function (e) { res[e.Key] = minOf(e) / totalMin; }); return res; }
    var pinned = {};
    for (;;) {
      var freeMass = 1, freeAff = 0, freeCount = 0, changed = false;
      entries.forEach(function (e) { if (pinned[e.Key]) freeMass -= minOf(e); else { freeAff += Math.max(e.Affinity, 0); freeCount++; } });
      entries.forEach(function (e) {
        if (pinned[e.Key]) return;
        var share = freeAff > 0 ? freeMass * Math.max(e.Affinity, 0) / freeAff : freeMass / freeCount;
        if (share < minOf(e)) { pinned[e.Key] = true; changed = true; } else res[e.Key] = share;
      });
      if (!changed) break;
    }
    entries.forEach(function (e) { if (pinned[e.Key]) res[e.Key] = minOf(e); });
    return res;
  }
  function pickOne(entries, minChance) {
    var ch = chances(entries, minChance), roll = Math.random();
    for (var i = 0; i < entries.length; i++) { roll -= ch[entries[i].Key]; if (roll < 0) return entries[i].Key; }
    return entries[entries.length - 1].Key;
  }
  function pickMany(entries, minChance, count) {
    var rest = entries.slice(), picked = [];
    for (var i = 0; i < count && rest.length; i++) {
      var k = pickOne(rest, minChance);
      picked.push(k);
      rest = rest.filter(function (e) { return e.Key !== k; });
    }
    return picked;
  }
  function pityMin(rounds) { var e = C.Election; return Math.min(e.MinChance + e.PityPerRound * Math.max(rounds, 0), Math.max(e.PityMaxChance, e.MinChance)); }
  function creatureCount(players) { var r = C.Round; return clamp(Math.ceil((players - 1) / r.PlayersPerCreature), 1, r.MaxCreatures); }
  function barGoal(n) { var r = C.Round; return Math.max(r.BarGoalMin, r.BarGoalBase + n * r.BarGoalPerPlayer); }
  function thresholdFor(f) {
    var minR = "Common", luck = 1, reached = 0;
    (C.Thresholds || []).forEach(function (t, i) { if (f >= t.Fraction) { minR = t.MinRarity; luck = t.Luck; reached = i + 1; } });
    return { min: minR, luck: luck, reached: reached };
  }
  function shieldsFor(aff) { var s = C.Shields; return s.Enabled && s.HeatPerShield > 0 ? clamp(Math.floor(aff / s.HeatPerShield), 0, s.Max) : 0; }
  function startShields(aff, chosen, newbie) {
    if (!C.Shields.Enabled) return 0;
    return shieldsFor(aff) + (chosen ? C.Shields.ChosenBonus : 0) + (newbie ? C.Shields.NewPlayerBonus : 0);
  }
  function consolation(aff, attempts) { var c = C.Consolation; return Math.floor(c.Base + Math.max(aff, 0) * c.PerAffinity + clamp(attempts, 0, c.MaxStealAttempts) * c.PerStealAttempt); }
  function isRevealed(elapsed, remaining) {
    var c = C.Chase;
    if (remaining <= c.FinalRevealSeconds) return true;
    if (c.RevealEvery <= 0) return true;
    return elapsed % c.RevealEvery >= c.RevealEvery - c.RevealSeconds;
  }
  function bagCapacity(level) { var h = C.Heat; return h.BagBaseCapacity + clamp(level, 0, h.BagMaxLevel - 1) * h.BagCapacityPerLevel; }

  // Para las otras partes de la página (ronda en miniatura y mapa 3D).
  window.EGG = {
    D: D, C: C, get: get, num: num, short: short, pct: pct, clock: clock, dur: dur, clamp: clamp, rgb: rgb, el: el,
    RBY: RBY, GBY: GBY, tier: tier, rollRarity: rollRarity, rollSet: rollSet, rarityOf: rarityOf, creatureName: creatureName,
    chances: chances, pickMany: pickMany, pityMin: pityMin, creatureCount: creatureCount, barGoal: barGoal,
    thresholdFor: thresholdFor, startShields: startShields, consolation: consolation, isRevealed: isRevealed,
    bagCapacity: bagCapacity, reduced: reduced,
  };

  // ------------------------------------------------------------------ dibujo de criaturas (SVG)
  var svgId = 0;
  function shade(c, k) { return "rgb(" + c.map(function (x) { return clamp(Math.round(x * k), 0, 255); }).join(",") + ")"; }
  function creatureSVG(genes) {
    var id = "c" + (++svgId);
    var body = GBY[genes.Body] || {}, head = GBY[genes.Head] || {}, pat = GBY[genes.Pattern] || {}, aura = GBY[genes.Aura] || {}, mut = GBY[genes.Mutation] || {};
    var bc = (body.Color || [255, 214, 150]).slice();
    var m = mut.Id || "";
    if (m === "mut_inverted") bc = bc.map(function (x) { return 255 - x; });
    if (m === "mut_golden") bc = [255, 200, 60];
    if (m === "mut_ancient") bc = [Math.round(bc[0] * .6 + 70), Math.round(bc[1] * .55 + 50), Math.round(bc[2] * .4 + 30)];
    if (m === "mut_cosmic") bc = [60, 50, 150];
    var fill = rgb(bc), dark = shade(bc, 0.7), hc = head.Color || [255, 200, 60];
    var scale = m === "mut_big" ? 1.12 : m === "mut_small" ? 0.8 : 1;
    var b = body.Id || "body_round";
    var rx = 62, ry = 56, cy = 128;
    if (b === "body_chubby") { rx = 72; ry = 54; }
    if (b === "body_long") { rx = 50; ry = 68; cy = 122; }
    if (b === "body_tiny") { rx = 46; ry = 42; cy = 140; }
    var defs = "", out = "";
    defs += '<radialGradient id="' + id + 'g" cx="40%" cy="35%" r="70%"><stop offset="0" stop-color="#fff" stop-opacity=".55"/><stop offset=".45" stop-color="#fff" stop-opacity="0"/></radialGradient>';
    if (m === "mut_rainbow" || pat.Id === "pattern_prism") {
      defs += '<linearGradient id="' + id + 'r" x1="0" x2="1" y1="0" y2="1"><stop offset="0" stop-color="#ff5f6d"/><stop offset=".25" stop-color="#ffc371"/><stop offset=".5" stop-color="#7cf29a"/><stop offset=".75" stop-color="#5fa8ff"/><stop offset="1" stop-color="#c86bff"/>' +
        (reduced ? "" : '<animateTransform attributeName="gradientTransform" type="rotate" from="0 .5 .5" to="360 .5 .5" dur="4s" repeatCount="indefinite"/>') + "</linearGradient>";
      if (m === "mut_rainbow") fill = "url(#" + id + "r)";
    }
    // Forma del cuerpo
    var shape;
    if (b === "body_crystal") shape = '<polygon points="100,' + (cy - ry) + " " + (100 + rx) + "," + (cy - 10) + " " + (100 + rx * .7) + "," + (cy + ry) + " " + (100 - rx * .7) + "," + (cy + ry) + " " + (100 - rx) + "," + (cy - 10) + '"';
    else if (b === "body_stone") shape = '<rect x="' + (100 - rx) + '" y="' + (cy - ry) + '" width="' + rx * 2 + '" height="' + ry * 2 + '" rx="26"';
    else if (b === "body_star") shape = '<path d="M100 ' + (cy - ry - 8) + " L" + (100 + 22) + " " + (cy - 18) + " L" + (100 + rx + 6) + " " + (cy - 12) + " L" + (100 + 34) + " " + (cy + 14) + " L" + (100 + 44) + " " + (cy + ry + 4) + " L100 " + (cy + 34) + " L" + (100 - 44) + " " + (cy + ry + 4) + " L" + (100 - 34) + " " + (cy + 14) + " L" + (100 - rx - 6) + " " + (cy - 12) + " L" + (100 - 22) + " " + (cy - 18) + ' Z" stroke-linejoin="round"';
    else if (b === "body_cloud") shape = '<path d="M' + (100 - rx) + " " + (cy + 20) + " a26 26 0 0 1 14 -46 a32 32 0 0 1 56 -16 a30 30 0 0 1 50 18 a24 24 0 0 1 4 44 Z" + '"';
    else shape = '<ellipse cx="100" cy="' + cy + '" rx="' + rx + '" ry="' + ry + '"';
    defs += '<clipPath id="' + id + 'k">' + shape + "/></clipPath>";
    // Aura
    if (aura.Id && aura.Id !== "aura_none") {
      var ac = rgb(aura.Color);
      out += '<circle cx="100" cy="' + cy + '" r="' + (Math.max(rx, ry) + 22) + '" fill="' + ac + '" opacity=".22">' + (reduced ? "" : '<animate attributeName="r" values="' + (Math.max(rx, ry) + 16) + ";" + (Math.max(rx, ry) + 26) + ";" + (Math.max(rx, ry) + 16) + '" dur="2.2s" repeatCount="indefinite"/>') + "</circle>";
      for (var i = 0; i < 6; i++) {
        var a = i / 6 * Math.PI * 2, R = Math.max(rx, ry) + 18;
        out += '<circle cx="' + (100 + Math.cos(a) * R).toFixed(1) + '" cy="' + (cy + Math.sin(a) * R).toFixed(1) + '" r="4" fill="' + ac + '">' + (reduced ? "" : '<animate attributeName="opacity" values="1;.2;1" dur="' + (1.4 + i * .2) + 's" repeatCount="indefinite"/>') + "</circle>";
      }
    }
    if (m === "mut_glow") out += '<ellipse cx="100" cy="' + cy + '" rx="' + (rx + 10) + '" ry="' + (ry + 10) + '" fill="#8cff78" opacity=".35"/>';
    // Cabeza: piezas detrás del cuerpo
    var top = cy - ry, hs = rgb(hc);
    if (head.Id === "head_bunny") out += '<ellipse cx="78" cy="' + (top - 22) + '" rx="11" ry="30" fill="' + fill + '" stroke="' + dark + '" stroke-width="3"/><ellipse cx="122" cy="' + (top - 22) + '" rx="11" ry="30" fill="' + fill + '" stroke="' + dark + '" stroke-width="3"/><ellipse cx="78" cy="' + (top - 20) + '" rx="5" ry="20" fill="' + hs + '"/><ellipse cx="122" cy="' + (top - 20) + '" rx="5" ry="20" fill="' + hs + '"/>';
    if (head.Id === "head_ears") out += '<polygon points="66,' + (top + 14) + " 74," + (top - 18) + " 92," + (top + 4) + '" fill="' + hs + '" stroke="' + dark + '" stroke-width="3" stroke-linejoin="round"/><polygon points="134,' + (top + 14) + " 126," + (top - 18) + " 108," + (top + 4) + '" fill="' + hs + '" stroke="' + dark + '" stroke-width="3" stroke-linejoin="round"/>';
    if (head.Id === "head_dragon") out += '<path d="M76 ' + (top + 6) + " q-14 -26 -4 -36 q4 18 18 26" + '" fill="' + hs + '" stroke="#7a1c1c" stroke-width="3"/><path d="M124 ' + (top + 6) + " q14 -26 4 -36 q-4 18 -18 26" + '" fill="' + hs + '" stroke="#7a1c1c" stroke-width="3"/>';
    if (head.Id === "head_comet") out += '<path d="M118 ' + (top + 2) + " q40 -10 70 -44 q-28 40 -60 58 Z" + '" fill="' + hs + '" opacity=".75"/>';
    // Cuerpo
    out += '<g class="cbody">' + shape + ' fill="' + fill + '" stroke="' + dark + '" stroke-width="4"' + (m === "mut_ghost" ? ' opacity=".55"' : "") + "/>";
    // Patrón recortado al cuerpo
    var pc = rgb(pat.Color || [0, 0, 0]), pp = "";
    switch (pat.Id) {
      case "pattern_spots": pp = [[70, 110, 10], [118, 100, 8], [130, 140, 11], [86, 150, 7], [100, 125, 5]].map(function (s) { return '<circle cx="' + s[0] + '" cy="' + (s[1] + cy - 128) + '" r="' + s[2] + '" fill="' + pc + '" opacity=".55"/>'; }).join(""); break;
      case "pattern_stripes": for (var k = -2; k <= 2; k++) pp += '<rect x="' + (92 + k * 26) + '" y="0" width="10" height="260" fill="' + pc + '" opacity=".35" transform="rotate(-12 100 128)"/>'; break;
      case "pattern_dots": for (var dx = 0; dx < 6; dx++) for (var dy = 0; dy < 6; dy++) pp += '<circle cx="' + (44 + dx * 22 + (dy % 2) * 11) + '" cy="' + (70 + dy * 22) + '" r="4" fill="' + pc + '" opacity=".7"/>'; break;
      case "pattern_patch": pp = '<ellipse cx="72" cy="' + (cy - 10) + '" rx="22" ry="18" fill="' + pc + '" opacity=".6"/><ellipse cx="132" cy="' + (cy + 24) + '" rx="18" ry="14" fill="' + pc + '" opacity=".6"/>'; break;
      case "pattern_bone": pp = '<path d="M70 ' + (cy + 10) + " l60 -20 M70 " + (cy + 26) + ' l60 -20" stroke="' + pc + '" stroke-width="6" stroke-linecap="round"/>'; break;
      case "pattern_zigzag": pp = '<path d="M30 ' + (cy + 4) + " l16 -14 l16 14 l16 -14 l16 14 l16 -14 l16 14 l16 -14 l16 14 l16 -14" + '" fill="none" stroke="' + pc + '" stroke-width="7"/>'; break;
      case "pattern_scales": for (var sx = 0; sx < 7; sx++) for (var sy = 0; sy < 5; sy++) pp += '<path d="M' + (36 + sx * 20 + (sy % 2) * 10) + " " + (80 + sy * 20) + ' a10 10 0 0 0 20 0" fill="none" stroke="' + pc + '" stroke-width="3" opacity=".7"/>'; break;
      case "pattern_runes": pp = '<text x="100" y="' + (cy + 14) + '" text-anchor="middle" font-size="34" fill="' + pc + '" opacity=".75" font-family="serif">ᚱᛟᚾ</text>'; break;
      case "pattern_galaxy": pp = '<rect x="0" y="0" width="200" height="260" fill="' + pc + '" opacity=".45"/>' + [[70, 104], [128, 112], [96, 150], [140, 146], [80, 132]].map(function (s) { return '<circle cx="' + s[0] + '" cy="' + (s[1] + cy - 128) + '" r="2.5" fill="#fff"/>'; }).join(""); break;
      case "pattern_gold": pp = '<rect x="0" y="' + (cy + 12) + '" width="200" height="80" fill="' + pc + '" opacity=".55"/>'; break;
      case "pattern_prism": pp = '<rect x="0" y="0" width="200" height="260" fill="url(#' + id + 'r)" opacity=".5"/>'; break;
    }
    if (b === "body_lava") pp += '<path d="M60 ' + (cy + 30) + " q10 20 0 30 M100 " + (cy + 40) + " q8 16 0 24 M140 " + (cy + 28) + ' q8 18 0 28" stroke="#ffd04a" stroke-width="5" fill="none" opacity=".8"/>';
    if (b === "body_jelly") pp += '<ellipse cx="100" cy="' + (cy + 20) + '" rx="40" ry="16" fill="#fff" opacity=".2"/>';
    if (b === "body_fluffy") for (var f = 0; f < 10; f++) { var fa = f / 10 * Math.PI * 2; pp += '<circle cx="' + (100 + Math.cos(fa) * rx).toFixed(1) + '" cy="' + (cy + Math.sin(fa) * ry).toFixed(1) + '" r="9" fill="' + fill + '"/>'; }
    if (b === "body_void" || m === "mut_cosmic") pp += [[70, 100], [130, 120], [96, 160], [118, 92], [82, 138]].map(function (s) { return '<circle cx="' + s[0] + '" cy="' + (s[1] + cy - 128) + '" r="2" fill="#fff">' + (reduced ? "" : '<animate attributeName="opacity" values="1;.2;1" dur="1.7s" repeatCount="indefinite"/>') + "</circle>"; }).join("");
    if (m === "mut_ancient") pp += '<path d="M60 ' + (cy - 20) + " l14 12 l-6 14 l12 10 M140 " + (cy + 6) + ' l-10 12 l8 12" stroke="#5a4630" stroke-width="2.5" fill="none"/>';
    out += '<g clip-path="url(#' + id + 'k)">' + pp + '<rect x="0" y="0" width="200" height="260" fill="url(#' + id + 'g)"/></g>';
    // Cara
    var ey = cy - ry * 0.18;
    if (head.Id === "head_cyclops") out += '<circle cx="100" cy="' + ey + '" r="15" fill="#fff" stroke="#2a2233" stroke-width="3"/><circle cx="102" cy="' + (ey + 2) + '" r="8" fill="#2a2233"/><circle cx="105" cy="' + (ey - 2) + '" r="3" fill="#fff"/>';
    else if (head.Id === "head_frog") out += '<circle cx="76" cy="' + (top + 4) + '" r="15" fill="' + hs + '" stroke="' + dark + '" stroke-width="3"/><circle cx="124" cy="' + (top + 4) + '" r="15" fill="' + hs + '" stroke="' + dark + '" stroke-width="3"/><circle cx="76" cy="' + (top + 4) + '" r="7" fill="#2a2233"/><circle cx="124" cy="' + (top + 4) + '" r="7" fill="#2a2233"/>';
    else out += '<circle cx="80" cy="' + ey + '" r="9" fill="#2a2233"/><circle cx="120" cy="' + ey + '" r="9" fill="#2a2233"/><circle cx="83" cy="' + (ey - 3) + '" r="3.2" fill="#fff"/><circle cx="123" cy="' + (ey - 3) + '" r="3.2" fill="#fff"/>';
    if (head.Id === "head_mask") out += '<rect x="62" y="' + (ey - 13) + '" width="76" height="24" rx="12" fill="' + hs + '" opacity=".92"/><circle cx="80" cy="' + ey + '" r="6" fill="#fff"/><circle cx="120" cy="' + ey + '" r="6" fill="#fff"/>';
    out += '<ellipse cx="68" cy="' + (ey + 18) + '" rx="9" ry="5" fill="#ff8aa0" opacity=".55"/><ellipse cx="132" cy="' + (ey + 18) + '" rx="9" ry="5" fill="#ff8aa0" opacity=".55"/>';
    if (head.Id === "head_beak") out += '<polygon points="90,' + (ey + 14) + " 110," + (ey + 14) + " 100," + (ey + 28) + '" fill="' + hs + '" stroke="#b07a10" stroke-width="2" stroke-linejoin="round"/>';
    else if (head.Id === "head_dragon") out += '<ellipse cx="100" cy="' + (ey + 22) + '" rx="16" ry="9" fill="' + shade(bc, .85) + '" stroke="' + dark + '" stroke-width="2"/><circle cx="95" cy="' + (ey + 21) + '" r="2" fill="#2a2233"/><circle cx="105" cy="' + (ey + 21) + '" r="2" fill="#2a2233"/>';
    else out += '<path d="M92 ' + (ey + 18) + " q8 8 16 0" + '" fill="none" stroke="#2a2233" stroke-width="3" stroke-linecap="round"/>';
    // Cabeza: piezas delante
    if (head.Id === "head_horn") out += '<polygon points="92,' + (top + 6) + " 108," + (top + 6) + " 100," + (top - 24) + '" fill="' + hs + '" stroke="' + dark + '" stroke-width="3" stroke-linejoin="round"/>';
    if (head.Id === "head_feathered") out += [-16, 0, 16].map(function (o) { return '<ellipse cx="' + (100 + o) + '" cy="' + (top - 10) + '" rx="7" ry="20" fill="' + hs + '" transform="rotate(' + o + " " + (100 + o) + " " + (top + 6) + ')"/>'; }).join("");
    if (head.Id === "head_crown") out += '<path d="M76 ' + (top + 4) + " l0 -24 l12 12 l12 -18 l12 18 l12 -12 l0 24 Z" + '" fill="' + hs + '" stroke="#b07a10" stroke-width="3" stroke-linejoin="round"/>';
    if (head.Id === "head_halo") out += '<ellipse cx="100" cy="' + (top - 16) + '" rx="30" ry="8" fill="none" stroke="' + hs + '" stroke-width="6">' + (reduced ? "" : '<animate attributeName="cy" values="' + (top - 18) + ";" + (top - 12) + ";" + (top - 18) + '" dur="2s" repeatCount="indefinite"/>') + "</ellipse>";
    if (head.Id === "head_comet") out += '<circle cx="114" cy="' + (top + 2) + '" r="10" fill="' + hs + '" stroke="#fff" stroke-width="2"/>';
    out += "</g>";
    if (m === "mut_shiny" || m === "mut_golden") out += [[54, 80], [150, 96], [140, 176]].map(function (s) { return '<path d="M' + s[0] + " " + (s[1] - 9) + " l3 6 l6 3 l-6 3 l-3 6 l-3 -6 l-6 -3 l6 -3 Z" + '" fill="#fff6b0">' + (reduced ? "" : '<animate attributeName="opacity" values="1;.1;1" dur="1.3s" repeatCount="indefinite"/>') + "</path>"; }).join("");
    // Pies
    out = out.replace('<g class="cbody">', '<ellipse cx="78" cy="' + (cy + ry - 2) + '" rx="14" ry="8" fill="' + dark + '"/><ellipse cx="122" cy="' + (cy + ry - 2) + '" rx="14" ry="8" fill="' + dark + '"/><g class="cbody">');
    var g = '<g transform="translate(100 140) scale(' + scale + ') translate(-100 -140)">' + out + "</g>";
    if (m === "mut_twin") g = '<g transform="translate(36 40) scale(.62)" opacity=".9">' + out + "</g>" + '<g transform="translate(-22 -6)">' + g + "</g>";
    return '<svg viewBox="0 0 200 230" xmlns="http://www.w3.org/2000/svg"><defs>' + defs + "</defs>" + '<ellipse cx="100" cy="' + (cy + ry + 8) + '" rx="' + rx * .8 + '" ry="7" fill="#000" opacity=".1"/>' + g + "</svg>";
  }
  window.EGG.creatureSVG = creatureSVG;

  // ------------------------------------------------------------------ números en el texto
  function fillNumbers() {
    $$("[data-n]").forEach(function (e) {
      var v = get(e.getAttribute("data-n")), f = e.getAttribute("data-fmt");
      if (v == null) { e.textContent = "?"; return; }
      e.textContent = f === "min" ? dur(v) : f === "pct" ? pct(v) : typeof v === "number" ? num(v) : String(v);
    });
    var trees = (D.Arena && D.Arena.Trees) || [];
    var r = C.Round || {};
    var calc = {
      roundMin: "~" + Math.round((r.IncubationTime + r.HatchTime + r.ChaseTime + r.ResultsTime + r.IntermissionTime + 35) / 60),
      geneCount: SLOTS.reduce(function (a, s) { return a + (GENES[s] || []).length; }, 0),
      combos: short(SLOTS.reduce(function (a, s) { return a * (GENES[s] || []).length; }, 1)),
      treeCount: trees.length,
      midHeight: (D.Arena && D.Arena.MidHeight) || 66,
      communityGoal: short(get("Events.Community.Goal") || 0),
    };
    $$("[data-calc]").forEach(function (e) { var v = calc[e.getAttribute("data-calc")]; e.textContent = v == null ? "?" : v; });
  }

  // ------------------------------------------------------------------ tema, navegación y aparición
  function setupChrome() {
    var store = { get: function (k) { try { return localStorage.getItem(k); } catch (e) { return null; } }, set: function (k, v) { try { localStorage.setItem(k, v); } catch (e) { /* sin almacenamiento */ } } };
    var saved = store.get("theme");
    if (saved === "light" || saved === "dark") document.documentElement.dataset.theme = saved;
    var btn = $("#theme-btn");
    function isDark() { var t = document.documentElement.dataset.theme; return t ? t === "dark" : matchMedia("(prefers-color-scheme: dark)").matches; }
    function label() { if (btn) btn.textContent = isDark() ? "☀️" : "🌙"; }
    label();
    if (btn) btn.addEventListener("click", function () {
      var next = isDark() ? "light" : "dark";
      document.documentElement.dataset.theme = next; store.set("theme", next); label();
      document.dispatchEvent(new Event("themechange"));
    });
    var bar = $("#progress");
    window.addEventListener("scroll", function () {
      var h = document.documentElement.scrollHeight - innerHeight;
      if (bar) bar.style.width = (h > 0 ? scrollY / h * 100 : 0) + "%";
    }, { passive: true });
    var links = $$(".chips-nav a");
    if ("IntersectionObserver" in window) {
      var io = new IntersectionObserver(function (es) {
        es.forEach(function (en) {
          if (!en.isIntersecting) return;
          links.forEach(function (a) {
            var act = a.getAttribute("href") === "#" + en.target.id;
            a.classList.toggle("active", act);
            if (act && a.scrollIntoView) { var nav = a.parentNode; nav.scrollTo({ left: a.offsetLeft - nav.clientWidth / 2 + a.clientWidth / 2, behavior: "smooth" }); }
          });
        });
      }, { rootMargin: "-40% 0px -55% 0px" });
      $$(".g-section").forEach(function (s) { io.observe(s); });
      var rv = new IntersectionObserver(function (es) { es.forEach(function (en) { if (en.isIntersecting) { en.target.classList.add("in"); rv.unobserve(en.target); } }); }, { rootMargin: "0px 0px -8% 0px" });
      $$(".reveal").forEach(function (s) { rv.observe(s); });
    } else $$(".reveal").forEach(function (s) { s.classList.add("in"); });
    // Chispas de la portada
    var stage = $("#hero-egg");
    if (stage && !reduced) for (var i = 0; i < 9; i++) {
      var sp = el("span", { class: "spark", style: "left:" + (18 + Math.random() * 64) + "%;top:" + (40 + Math.random() * 40) + "%;animation-delay:" + (Math.random() * 3.2).toFixed(2) + "s;background:" + ["#ff8a2a", "#3b9cff", "#b04dff"][i % 3] + ";box-shadow:0 0 12px " + ["#ff8a2a", "#3b9cff", "#b04dff"][i % 3] });
      stage.appendChild(sp);
    }
  }

  // ------------------------------------------------------------------ bucle
  function setupLoop() {
    var svg = $("#loop-svg"), text = $("#loop-text");
    if (!svg) return;
    var r = C.Round;
    var nodes = [
      { k: "Lobby", em: "🏡", c: "#12a39a", x: 90, y: 125, t: "En el lobby cuidas tu nido: recoges Monedas, abres huevos, crías, decoras e intercambias. Llevas tu criatura al hombro. Cuando quieras, pulsas ⚔️ JUGAR." },
      { k: "Cola", em: "⏳", c: "#12a39a", x: 230, y: 45, t: "La cola junta entre " + C.Matchmaking.MinPlayers + " y " + C.Matchmaking.MaxPlayers + " jugadores (tu Bandada entra junta) y os lleva a un servidor de partida nuevo." },
      { k: "Incubación", em: "🔥", c: "#ff8a2a", x: 400, y: 30, t: dur(r.IncubationTime) + ": recoges Calor por el bosque y el parkour y lo llevas al huevo. Llenas la barra (mejores criaturas) y tu Afinidad (más probabilidad de que te elija)." },
      { k: "Eclosión", em: "🐣", c: "#7b5cff", x: 570, y: 45, t: r.HatchTime + " s: el huevo se rompe, la criatura sale en el centro y un foco elige a quién se une." },
      { k: "Persecución", em: "🏃", c: "#e0464d", x: 670, y: 125, t: dur(r.ChaseTime) + ": el elegido huye y se esconde; los demás le buscan con la señal y le roban. Gana quien la tenga al final." },
      { k: "Resultados", em: "🏆", c: "#e8a400", x: 485, y: 205, t: r.ResultsTime + " s: el ganador se lleva la criatura, los demás polvo de cáscara, y el elegido que la perdió un Huevo del Elegido." },
      { k: "Vuelta", em: "✈️", c: "#12a39a", x: 275, y: 205, t: "Vuelves a tu nido del lobby y ves lo ganado en su pedestal. Con «Seguir jugando», a la cola otra vez." },
    ];
    var ns = "http://www.w3.org/2000/svg";
    var path = "M90 125 C 120 60, 180 45, 230 45 S 340 30, 400 30 S 520 30, 570 45 S 670 80, 670 125 S 560 205, 485 205 S 340 205, 275 205 S 110 190, 90 125 Z";
    svg.innerHTML = '<path id="loop-path" d="' + path + '" fill="none" stroke="var(--border)" stroke-width="6" stroke-dasharray="2 12" stroke-linecap="round"/>';
    var p = svg.querySelector("#loop-path");
    nodes.forEach(function (n, i) {
      var g = document.createElementNS(ns, "g");
      g.setAttribute("class", "node"); g.setAttribute("tabindex", "0"); g.setAttribute("role", "button");
      g.innerHTML = '<rect x="' + (n.x - 52) + '" y="' + (n.y - 22) + '" width="104" height="44" rx="14" fill="' + n.c + '"/><text x="' + n.x + '" y="' + (n.y + 6) + '" text-anchor="middle" fill="#fff" font-family="Fredoka, Inter, sans-serif" font-size="15" font-weight="600">' + n.em + " " + n.k + "</text>";
      g.addEventListener("click", function () { select(i, true); });
      g.addEventListener("keydown", function (e) { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); select(i, true); } });
      svg.appendChild(g); n.g = g;
    });
    var dot = document.createElementNS(ns, "circle");
    dot.setAttribute("r", "9"); dot.setAttribute("fill", "#ffe7c4"); dot.setAttribute("stroke", "#ff8a2a"); dot.setAttribute("stroke-width", "3");
    svg.appendChild(dot);
    var len = p.getTotalLength(), cur = 0, held = 0;
    // Posición de cada nodo sobre el camino (el punto más cercano).
    nodes.forEach(function (n) {
      var best = 0, bd = 1e9;
      for (var s = 0; s <= len; s += 4) { var q = p.getPointAtLength(s), d = (q.x - n.x) * (q.x - n.x) + (q.y - n.y) * (q.y - n.y); if (d < bd) { bd = d; best = s; } }
      n.at = best;
    });
    var pos = 0;
    function select(i, user) {
      cur = i; text.innerHTML = "<b>" + nodes[i].em + " " + nodes[i].k + ".</b> " + nodes[i].t;
      nodes.forEach(function (n, j) { n.g.style.opacity = j === i ? "1" : ".55"; });
      if (user) { held = performance.now() + 9000; pos = nodes[i].at; }
    }
    select(0);
    var last = performance.now();
    function tick(t) {
      var dt = (t - last) / 1000; last = t;
      if (t > held && !reduced) {
        pos = (pos + dt * 70) % len;
        var next = nodes.reduce(function (best, n, j) { return Math.abs(n.at - pos) < 10 ? j : best; }, -1);
        if (next >= 0 && next !== cur) select(next);
      }
      var q = p.getPointAtLength(pos);
      dot.setAttribute("cx", q.x); dot.setAttribute("cy", q.y);
      requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
  }

  // ------------------------------------------------------------------ cola
  function setupQueue() {
    var lane = $("#queue-lane"), status = $("#q-status"), barI = $("#q-bar i");
    if (!lane) return;
    var mm = C.Matchmaking, faces = ["🙂", "😎", "🤠", "🥳", "😺", "🐸", "🦊", "🐼", "🐵", "🦁", "🐯", "🐨", "🐷", "🐙"];
    var people = [], since = 0, launchAt = 0, SPEED = 4;
    function render() {
      lane.innerHTML = "";
      people.forEach(function (p) { lane.appendChild(el("span", { title: "Jugador" }, p)); });
    }
    function add(k) { if (launchAt) return; for (var i = 0; i < k; i++) { if (!people.length) since = 0; people.push(faces[(people.length + Math.floor(Math.random() * 3)) % faces.length]); } render(); }
    on("q-add", "click", function () { add(1); });
    on("q-add4", "click", function () { add(4); });
    on("q-reset", "click", function () { people = []; launchAt = 0; since = 0; render(); });
    var last = performance.now();
    setInterval(function () {
      var now = performance.now(), dt = (now - last) / 1000 * SPEED; last = now;
      var n = people.length;
      if (launchAt) {
        launchAt -= dt;
        status.textContent = "🚀 ¡Partida encontrada! Saliendo en " + Math.max(0, Math.ceil(launchAt)) + " s…";
        barI.style.width = "100%";
        if (launchAt <= 0) { people = people.slice(Math.min(n, mm.MaxPlayers)); launchAt = 0; since = 0; render(); }
        return;
      }
      if (!n) { status.textContent = "La cola está vacía. Añade jugadores."; barI.style.width = "0"; return; }
      since += dt;
      var ready = n >= mm.TargetPlayers || (n >= mm.MinPlayers && since >= mm.FillSeconds) || since >= mm.SoloSeconds;
      if (ready) { launchAt = mm.Countdown; return; }
      var target = n >= mm.MinPlayers ? mm.FillSeconds : mm.SoloSeconds;
      barI.style.width = clamp(since / target, 0, 1) * 100 + "%";
      status.textContent = n + " en la cola · " + Math.floor(since) + " s · " + (n >= mm.MinPlayers ? "sale a los " + mm.FillSeconds + " s o con " + mm.TargetPlayers : "faltan " + (mm.MinPlayers - n) + " para " + mm.MinPlayers + " (o a los " + mm.SoloSeconds + " s con zorros)");
    }, 200);
    render();
  }

  // ------------------------------------------------------------------ Calor
  function setupHeat() {
    var h = C.Heat, box = $("#sources");
    if (box) {
      var src = [
        { em: "🟠", n: "Brasa naranja", d: h.Ember, t: "En el suelo y en los pisos bajos de los árboles." },
        { em: "🔵", n: "Brasa azul", d: h.BlueEmber, t: "Desde la mitad de los árboles hacia arriba." },
        { em: "🟣", n: "Brasa morada", d: h.PurpleEmber, t: "En la plataforma más alta de cada árbol." },
        { em: "✨", n: "Luciérnaga", d: h.Firefly, t: "Revolotean por el pantano: hay que perseguirlas." },
        { em: "❓", n: "Caja sorpresa", d: { Amount: h.LuckyBlock.Min + "–" + h.LuckyBlock.Max, Respawn: h.LuckyBlock.Respawn, Count: h.LuckyBlock.Count }, t: "Calor al azar. Una de cada cuatro sale en lo alto." },
        { em: "💨", n: "Géiser", d: { Amount: h.Geyser.Amount, Respawn: h.Geyser.Cooldown, Count: h.Geyser.Count }, t: "Necesita a 2 jugadores a la vez." },
      ];
      src.forEach(function (s) {
        if (!s.d) return;
        box.appendChild(el("div", { class: "mini-card" }, '<div class="em">' + s.em + "</div><b>" + s.n + '</b><p><span class="num">+' + s.d.Amount + "</span> de Calor · " + s.d.Count + " en el mapa · vuelve en " + s.d.Respawn + " s</p><p style=\"margin-top:4px\">" + s.t + "</p>"));
      });
    }
    // Árbol con las brasas por niveles
    var svg = $("#tiers-svg");
    if (svg) {
      var levels = (D.Arena && D.Arena.Trees && D.Arena.Trees[0] && D.Arena.Trees[0].Decks) || [22, 44, 66, 88, 110, 132];
      var mid = (D.Arena && D.Arena.MidHeight) || 66, topL = levels[levels.length - 1], H = 280, base = 290;
      var y = function (v) { return base - v / (topL + 14) * H; };
      var s = '<rect x="140" y="' + y(topL + 10) + '" width="40" height="' + (base - y(topL + 10)) + '" rx="8" fill="#8a5a33"/><ellipse cx="160" cy="' + y(topL + 12) + '" rx="70" ry="22" fill="#3f8f45" opacity=".85"/><rect x="0" y="' + base + '" width="320" height="10" fill="#5aa25e"/>';
      levels.forEach(function (lv, i) {
        var tierName = lv === topL ? "top" : lv >= mid ? "mid" : "low";
        var col = tierName === "top" ? "#b04dff" : tierName === "mid" ? "#3b9cff" : "#ff8a2a";
        var val = tierName === "top" ? h.PurpleEmber.Amount : tierName === "mid" ? h.BlueEmber.Amount : h.Ember.Amount;
        s += '<rect x="96" y="' + (y(lv) - 4) + '" width="128" height="8" rx="3" fill="#c98f55"/>';
        for (var k = 0; k < 3; k++) s += '<circle cx="' + (112 + k * 48) + '" cy="' + (y(lv) - 11) + '" r="6" fill="' + col + '" style="filter:drop-shadow(0 0 5px ' + col + ')">' + (reduced ? "" : '<animate attributeName="cy" values="' + (y(lv) - 11) + ";" + (y(lv) - 15) + ";" + (y(lv) - 11) + '" dur="' + (1.6 + k * .3 + i * .1) + 's" repeatCount="indefinite"/>') + "</circle>";
        s += '<text x="10" y="' + (y(lv) + 4) + '" font-size="12" fill="currentColor" font-family="Inter,sans-serif">' + lv + " studs</text>";
        s += '<text x="236" y="' + (y(lv) + 4) + '" font-size="13" font-weight="700" fill="' + col + '" font-family="Fredoka,Inter,sans-serif">+' + val + "</text>";
      });
      s += '<line x1="0" x2="320" y1="' + y(mid) + '" y2="' + y(mid) + '" stroke="#3b9cff" stroke-dasharray="4 4" opacity=".6"/><text x="236" y="' + (y(mid) + 18) + '" font-size="10" fill="#3b9cff" font-family="Inter,sans-serif">mitad</text>';
      for (var g = 0; g < 4; g++) s += '<circle cx="' + (30 + g * 30) + '" cy="' + (base - 6) + '" r="5" fill="#ff8a2a"/>';
      svg.innerHTML = s;
      svg.style.color = "var(--text-soft)";
    }
    // Bolsa
    var lvl = rangeOut("bag-lvl"), rain = $("#bag-rain");
    function bag() {
      lvl.show();
      var cap = bagCapacity(lvl.value()), mult = rain && rain.checked ? C.Round.GoldenRainMultiplier : 1;
      $("#bag-cap").textContent = num(cap);
      $("#bag-orange").textContent = num(Math.ceil(cap / (h.Ember.Amount * mult)));
      $("#bag-purple").textContent = num(Math.ceil(cap / (h.PurpleEmber.Amount * mult)));
    }
    lvl.input.addEventListener("input", bag); if (rain) rain.addEventListener("change", bag); bag();
  }

  // ------------------------------------------------------------------ barra
  function rarityBars(box, odds, highlight) {
    box.innerHTML = "";
    RAR.forEach(function (r) {
      var p = odds[r.Name] || 0;
      var row = el("div", { class: "b" + (highlight === r.Name ? " me" : "") }, "<span>" + r.DisplayName + '</span><div class="track"><i style="width:0;background:' + rgb(r.Color) + '"></i></div><span>' + (p > 0 && p < 0.001 ? "<0,1 %" : pct(p, p < 0.1 ? 1 : 0)) + "</span>");
      box.appendChild(row);
      requestAnimationFrame(function () { row.querySelector("i").style.width = Math.max(p > 0 ? 1.5 : 0, Math.sqrt(p) * 100) + "%"; });
    });
  }
  function setupBar() {
    var n = rangeOut("bar-n"), f = rangeOut("bar-f", function (v) { return v + " %"; }), bm = $("#bar-bm");
    if (!n.input) return;
    function upd() {
      n.show(); f.show();
      var th = thresholdFor(f.value() / 100), min = th.min;
      if (bm.checked && tier(min) < tier(get("Events.BloodMoon.MinRarity"))) min = get("Events.BloodMoon.MinRarity");
      $("#bar-goal").textContent = num(barGoal(n.value()));
      $("#bar-min").textContent = RBY[min].DisplayName;
      $("#bar-luck").textContent = "×" + String(th.luck).replace(".", ",");
      rarityBars($("#bar-odds"), rarityOdds(th.luck, min), null);
    }
    [n.input, f.input].forEach(function (i) { i.addEventListener("input", upd); }); bm.addEventListener("change", upd); upd();
    var hint = el("p", { class: "hint" }, "La barra de largo es la raíz cuadrada de la probabilidad, para que las rarezas raras se vean. Umbrales: " + (C.Thresholds || []).map(function (t) { return pct(t.Fraction) + " → mínimo " + RBY[t.MinRarity].DisplayName + ", suerte ×" + String(t.Luck).replace(".", ","); }).join(" · ") + ".");
    $("#bar-odds").parentNode.appendChild(hint);
  }

  // ------------------------------------------------------------------ elección
  function setupElection() {
    var me = rangeOut("el-me", num), n = rangeOut("el-n"), avg = rangeOut("el-avg", num), pity = rangeOut("el-pity"), nw = $("#el-new");
    if (!me.input) return;
    var entries = [], ch = {}, spinning = false;
    var names = ["Ana", "Leo", "Mía", "Hugo", "Sara", "Iker", "Noa", "Teo", "Vega", "Bruno", "Alba"];
    function build() {
      [me, n, avg, pity].forEach(function (r) { r.show(); });
      entries = [{ Key: "Tú", Affinity: me.value(), Min: nw.checked ? Math.max(C.Election.PityMaxChance, C.Election.MinChance) : pityMin(pity.value()) }];
      for (var i = 0; i < n.value(); i++) entries.push({ Key: names[i], Affinity: Math.round(avg.value() * (0.45 + 1.1 * ((i * 37) % 11) / 10)) });
      ch = chances(entries, C.Election.MinChance);
      var count = creatureCount(entries.length);
      $("#el-chance").textContent = pct(ch["Tú"], 1);
      $("#el-creatures").textContent = count;
      $("#el-shields").textContent = startShields(me.value(), true, nw.checked);
      var box = $("#el-bars"); box.innerHTML = "";
      entries.slice().sort(function (a, b) { return ch[b.Key] - ch[a.Key]; }).forEach(function (e) {
        var row = el("div", { class: "b" + (e.Key === "Tú" ? " me" : ""), "data-k": e.Key }, "<span>" + e.Key + " <small style=\"color:var(--muted)\">" + short(e.Affinity) + '</small></span><div class="track"><i style="width:' + (ch[e.Key] * 100 / Math.max.apply(null, entries.map(function (x) { return ch[x.Key]; }))) + '%;background:' + (e.Key === "Tú" ? "var(--accent)" : "var(--hatch)") + '"></i></div><span>' + pct(ch[e.Key], 1) + "</span>");
        box.appendChild(row);
      });
      $("#el-result").textContent = "";
    }
    [me, n, avg, pity].forEach(function (r) { r.input.addEventListener("input", build); });
    nw.addEventListener("change", build);
    build();
    on("el-spin", "click", function () {
      if (spinning) return;
      spinning = true;
      var picked = pickMany(entries, C.Election.MinChance, creatureCount(entries.length));
      var rows = $$("#el-bars .b"), steps = 18 + Math.floor(Math.random() * 6), k = 0;
      var target = rows.findIndex(function (r) { return r.getAttribute("data-k") === picked[0]; });
      steps += (target - steps % rows.length + rows.length) % rows.length;
      (function step() {
        rows.forEach(function (r, i) { r.classList.toggle("lit", i === k % rows.length); });
        if (k >= steps) {
          spinning = false;
          rows.forEach(function (r) { if (picked.indexOf(r.getAttribute("data-k")) >= 0) { r.classList.add("lit", "picked"); } });
          var meWon = picked.indexOf("Tú") >= 0;
          $("#el-result").textContent = meWon ? "🎉 ¡Te ha elegido!" : "Elige a " + picked.join(", ") + (picked.length > 1 ? " (" + picked.length + " criaturas)" : "");
          return;
        }
        var t = k / steps; k++;
        setTimeout(step, reduced ? 10 : 50 + 260 * t * t);
      })();
    });
  }

  // ------------------------------------------------------------------ eclosión
  function setupHatchCount() {
    var n = rangeOut("hc-n");
    if (!n.input) return;
    function upd() {
      n.show();
      var c = creatureCount(n.value());
      $("#hc-eggs").textContent = "🐣".repeat(c) + "  " + "🧍".repeat(Math.max(0, n.value() - c));
      $("#hc-text").textContent = c + (c === 1 ? " criatura" : " criaturas") + " para " + n.value() + " jugadores: " + (n.value() - c) + " perseguidores, unos " + Math.round((n.value() - c) / c * 10) / 10 + " por portador.";
    }
    n.input.addEventListener("input", upd); upd();
  }

  // ------------------------------------------------------------------ persecución
  function setupChase() {
    var track = $("#rv-track"), head = $("#rv-head"), aura = $("#rv-aura"), text = $("#rv-text");
    if (track) {
      var T = C.Round.ChaseTime, ch = C.Chase;
      for (var t = 0; t < T - ch.FinalRevealSeconds; t += ch.RevealEvery) {
        var a = t + ch.RevealEvery - ch.RevealSeconds;
        if (a >= T - ch.FinalRevealSeconds) break;
        track.appendChild(el("div", { class: "pulse", style: "left:" + a / T * 100 + "%;width:" + ch.RevealSeconds / T * 100 + "%" }));
      }
      track.appendChild(el("div", { class: "final", style: "width:" + ch.FinalRevealSeconds / T * 100 + "%" }));
      track.appendChild(el("span", { class: "lbl", style: "left:6px" }, "0:00"));
      track.appendChild(el("span", { class: "lbl", style: "right:6px" }, clock(T)));
      var playing = !reduced, elapsed = 0, last = performance.now();
      on("rv-play", "click", function (e) { playing = !playing; e.target.textContent = playing ? "⏸ Pausa" : "▶ Seguir"; });
      (function loop(now) {
        var dt = (now - last) / 1000; last = now;
        if (playing) elapsed = (elapsed + dt * 4) % T;
        head.style.left = elapsed / T * 100 + "%";
        var rem = T - elapsed, rev = isRevealed(elapsed, rem);
        aura.classList.toggle("on", rev);
        aura.textContent = rev ? "🐣" : "🌳";
        if (rem <= ch.FinalRevealSeconds) text.innerHTML = "<b>¡Últimos segundos: todos a la vista!</b> Quedan " + Math.ceil(rem) + " s";
        else if (rev) text.innerHTML = "<b>📡 ¡Señal!</b> Todos ven al portador a través de los árboles y queda una marca 📍";
        else { var nxt = ch.RevealEvery - ch.RevealSeconds - elapsed % ch.RevealEvery; text.textContent = "Escondido · le verán en " + Math.ceil(Math.min(nxt, rem - ch.FinalRevealSeconds)) + " s"; }
        requestAnimationFrame(loop);
      })(last);
    }
    // Tira y afloja
    var tug = $("#tug");
    if (tug) {
      var range = $("#tug-range"), carrier = $("#tug-carrier"), thief = $("#tug-thief"), pos = $("#tug-pos"), prog = $("#tug-prog"), msg = $("#tug-msg");
      var W = 100, R = C.Chase.StealRange, hold = C.Chase.StealHoldTime, cx = 70, holding = 0, active = false, t0 = 0, dir = 1;
      // Escala: 100 = 40 studs
      var studs = 40;
      function place() {
        carrier.style.left = "calc(" + cx + "% - 14px)";
        thief.style.left = "calc(" + pos.value + "% - 14px)";
        range.style.left = (cx - R / studs * 100) + "%"; range.style.width = (2 * R / studs * 100) + "%";
      }
      pos.addEventListener("input", place);
      on("tug-go", "click", function () {
        var d = Math.abs(pos.value - cx) / 100 * studs;
        if (d > R) { msg.textContent = "Demasiado lejos: acércate a menos de " + R + " studs."; return; }
        active = true; holding = 0; t0 = performance.now(); msg.textContent = "¡Robando! Quédate cerca…";
      });
      var last2 = performance.now();
      (function loop(now) {
        var dt = (now - last2) / 1000; last2 = now;
        // El portador intenta escaparse
        cx += dir * dt * (active ? 9 : 3);
        if (cx > 88) dir = -1; if (cx < 52) dir = 1;
        place();
        if (active) {
          var d = Math.abs(pos.value - cx) / 100 * studs;
          if (d > R) { active = false; prog.style.width = "0"; msg.textContent = "¡Se te ha escapado!"; }
          else {
            holding += dt; prog.style.width = clamp(holding / hold, 0, 1) * 100 + "%";
            if (holding >= hold) { active = false; msg.textContent = "🎉 ¡Robada! Ahora el portador eres tú (inmune " + C.Chase.ImmunityAfterSteal + " s)."; setTimeout(function () { prog.style.width = "0"; }, 1200); }
          }
        }
        requestAnimationFrame(loop);
      })(last2);
      place();
    }
    // Escudos
    var heat = rangeOut("sh-heat", num), chosen = $("#sh-chosen"), nw = $("#sh-new");
    function sh() { heat.show(); var k = startShields(heat.value(), chosen.checked, nw.checked); $("#sh-row").textContent = k ? "🛡️".repeat(k) : "Sin escudos"; }
    if (heat.input) { heat.input.addEventListener("input", sh); chosen.addEventListener("change", sh); nw.addEventListener("change", sh); sh(); }
    // Reglas
    var c = C.Chase, box = $("#chase-rules");
    if (box) [
      ["⏱️", "Ventaja", "El elegido es inmune " + c.StartImmunitySeconds + " s y los demás esperan " + c.HeadStartSeconds + " s antes de moverse."],
      ["💨", "Esprint", "Solo el portador. Shift o botón ⚡: ×" + String(c.SprintMultiplier).replace(".", ",") + " de velocidad " + c.SprintDuration + " s, cada " + c.SprintCooldown + " s."],
      ["🔁", "Relevo", "Q: el portador pasa la criatura a un aliado (Bandada o trato) que esté a menos de " + c.PassRange + " studs."],
      ["😵", "Aturdido", "A quien le roban se queda " + c.StunSeconds + " s sin moverse; el nuevo portador es inmune " + c.ImmunityAfterSteal + " s."],
      ["🏃", "Misma velocidad", "El portador corre igual que los demás: para escapar hay que usar el parkour, no las piernas."],
      ["🦊", "Zorros", "Con menos de " + get("ForestThieves.FillTo") + " jugadores salen zorros que tiran la criatura al suelo; cualquiera la puede recoger."],
      ["📍", "Marca", "Tras cada señal, los ladrones ven dónde estaba el portador y una flecha les apunta allí."],
      ["⌛", "Final", "Si la criatura está en el suelo al acabar, se escapa: nadie gana."],
    ].forEach(function (r) { box.appendChild(el("div", { class: "mini-card" }, '<div class="em">' + r[0] + "</div><b>" + r[1] + "</b><p>" + r[2] + "</p>")); });
  }

  // ------------------------------------------------------------------ parkour (tarjetas)
  function setupParkourCards() {
    var a = C.Arena || {}, box = $("#parkour-cards");
    if (!box) return;
    var trees = (D.Arena && D.Arena.Trees) || [];
    var links = (D.Arena && D.Arena.Links) || [], rides = (D.Arena && D.Arena.Rides) || [];
    var count = function (k, list) { return list.filter(function (x) { return x.Kind === k; }).length; };
    [
      ["🌀", "Rampas", trees.filter(function (t) { return t.Ramp; }).length + " árboles con rampa en espiral y barandilla; en cada piso, un rellano a la plataforma."],
      ["🪜", "Escaleras", trees.filter(function (t) { return !t.Ramp; }).length + " árboles con escalera pegada a una cara: se trepa hasta arriba del todo."],
      ["🌉", "Puentes", count("Bridge", links) + " puentes con cuerdas, " + count("Beam", links) + " vigas estrechas y " + count("Stones", links) + " caminos de piedras para saltar."],
      ["🚡", "Tirolinas", count("Zipline", rides) + " tirolinas desde lo alto (E en el poste) a " + (a.ZiplineSpeed || "?") + " studs/s."],
      ["🛝", "Toboganes", count("Slide", rides) + " toboganes: pisas la entrada y bajas deslizándote."],
      ["🍄", "Setas", ((D.Arena && D.Arena.Trampolines) || []).length + " setas trampolín que te lanzan hacia arriba."],
      ["🛖", "Escondites", trees.filter(function (t) { return t.Hut; }).length + " cabañas en los árboles grandes, copas de hojas, arbustos y troncos huecos."],
      ["🪂", "Sin daño", "Caerse no hace daño: cualquier error se arregla volviendo a subir."],
    ].forEach(function (r) { box.appendChild(el("div", { class: "mini-card" }, '<div class="em">' + r[0] + "</div><b>" + r[1] + "</b><p>" + r[2] + "</p>")); });
  }

  // ------------------------------------------------------------------ consolación
  function setupConsolation() {
    var heat = rangeOut("cs-heat", num), tries = rangeOut("cs-try");
    if (!heat.input) return;
    function upd() { heat.show(); tries.show(); $("#cs-dust").textContent = "✨ " + num(consolation(heat.value(), tries.value())) + " de polvo"; }
    heat.input.addEventListener("input", upd); tries.input.addEventListener("input", upd); upd();
  }

  // ------------------------------------------------------------------ genes
  function geneChip(slot, id, extra) {
    var g = GBY[id] || {}, r = RBY[g.Rarity] || RAR[0];
    return '<div class="gene-chip" style="border-color:' + rgb(r.Color) + '"><span style="width:14px;height:14px;border-radius:4px;flex:none;background:' + rgb(g.Color || [200, 200, 200]) + '"></span><div><small>' + (D.SlotNames ? D.SlotNames[slot] : slot) + (extra || "") + "</small>" + (g.Name || "?") + "</div></div>";
  }
  function setupGenes() {
    var grid = $("#gene-grid"), info = $("#gene-info");
    if (!grid) return;
    SLOTS.forEach(function (slot) {
      grid.appendChild(el("div", { class: "h" }, D.SlotNames ? D.SlotNames[slot] : slot));
      (GENES[slot] || []).forEach(function (g) {
        var r = RBY[g.Rarity];
        var cell = el("div", { class: "g", title: g.Name + " · " + r.DisplayName, style: "background:" + rgb(g.Color) + ";box-shadow:inset 0 -5px 0 " + rgb(r.Color) });
        cell.addEventListener("click", function () {
          $$(".gene-grid .g").forEach(function (x) { x.classList.remove("sel"); });
          cell.classList.add("sel");
          var same = (GENES[slot] || []).filter(function (x) { return x.Rarity === g.Rarity; }).length;
          info.innerHTML = "<b>" + g.Name + "</b> · " + (D.SlotNames ? D.SlotNames[slot] : slot) + ' · <span class="rarity-tag" style="background:' + rgb(r.Color) + '">' + r.DisplayName + "</span> · " + same + " gen" + (same > 1 ? "es" : "") + " de esta rareza en la ranura" + (g.Rarity === "Secret" ? " · solo sale en criaturas Secretas" : "");
        });
        grid.appendChild(cell);
      });
    });
    var leg = el("div", { class: "tally" });
    RAR.forEach(function (r) { leg.appendChild(el("span", { style: "border-color:" + rgb(r.Color) + ";color:" + rgb(r.Color) }, r.DisplayName + " · ×" + r.Income + " Monedas/s · " + (r.Weight / 10000).toFixed(r.Weight < 1000 ? 3 : 1).replace(".", ",") + " %")); });
    info.parentNode.appendChild(leg);
  }

  // ------------------------------------------------------------------ abre un huevo
  function setupEggLab() {
    var stage = $("#egg-stage"), kind = $("#egg-kind"), out = $("#egg-out"), tally = $("#egg-tally");
    if (!stage) return;
    var ER = C.EggRanges || {};
    var kinds = [
      { k: "round", n: "🥚 Huevo de la ronda (barra llena al 100 %)", roll: function () { var th = thresholdFor(1); return rollRarity(th.luck, th.min); } },
      { k: "round0", n: "🥚 Huevo de la ronda (barra a menos del 25 %)", roll: function () { return rollRarity(1); } },
      { k: "bm", n: "🌕 Huevo de la ronda con Luna de Sangre", roll: function () { var th = thresholdFor(1); return rollRarity(th.luck, tier(th.min) < tier("Epic") ? "Epic" : th.min); } },
    ];
    var names = { Personal: "🪺 Huevo personal (" + get("Incubator.PersonalEggCostDust") + " de polvo)", Season: "🎟️ Huevo de Temporada", Streak: "🔥 Huevo de racha (7 días de misiones)", Chosen: "💔 Huevo del Elegido", Welcome: "🎁 Huevo de bienvenida" };
    Object.keys(names).forEach(function (k) { if (ER[k]) kinds.push({ k: k, n: names[k] + " · " + RBY[ER[k].Min].DisplayName + " a " + RBY[ER[k].Max].DisplayName, roll: function () { return rollRarity(1, ER[k].Min, ER[k].Max); } }); });
    kinds.push({ k: "luck", n: "🍀 Huevo personal con Suerte del Lobby", roll: function () { return rollRarity(get("ServerLuck.Luck"), ER.Personal.Min, ER.Personal.Max); } });
    kinds.forEach(function (k, i) { kind.appendChild(el("option", { value: i }, k.n)); });
    var counts = {}, total = 0;
    function showTally() {
      tally.innerHTML = total ? "<span><b>" + total + "</b> abiertos</span>" : "";
      RAR.forEach(function (r) { if (counts[r.Name]) tally.appendChild(el("span", { style: "color:" + rgb(r.Color) + ";font-weight:700" }, r.DisplayName + ": " + counts[r.Name])); });
    }
    function show(genes, animate) {
      var rar = rarityOf(genes), r = RBY[rar];
      stage.innerHTML = creatureSVG(genes);
      stage.style.background = "radial-gradient(circle at 50% 45%, " + rgb(r.Color).replace("rgb", "rgba").replace(")", ",.35)") + ", var(--surface-2) 70%)";
      if (animate) { stage.classList.remove("pop"); void stage.offsetWidth; stage.classList.add("pop"); }
      out.innerHTML = '<div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap"><b style="font-family:Fredoka,Inter,sans-serif;font-size:1.35rem">' + creatureName(genes) + '</b><span class="rarity-tag" style="background:' + rgb(r.Color) + '">' + r.DisplayName + '</span><span style="color:var(--gold);font-weight:700">🪙 ' + incomeOf(genes).toFixed(1).replace(".", ",") + "/s</span></div>" +
        '<div class="genes-list">' + SLOTS.map(function (s) { return geneChip(s, genes[s]); }).join("") + "</div>";
    }
    function open(n) {
      var k = kinds[Number(kind.value)], last = null, best = null;
      for (var i = 0; i < n; i++) {
        var g = rollSet(k.roll()), rr = rarityOf(g);
        counts[rr] = (counts[rr] || 0) + 1; total++;
        last = g; if (!best || tier(rr) > tier(rarityOf(best))) best = g;
      }
      return n > 1 ? best : last;
    }
    var busy = false;
    function hatch(n) {
      if (busy) return; busy = true;
      stage.innerHTML = '<svg viewBox="0 0 200 230"><ellipse cx="100" cy="120" rx="62" ry="80" fill="#ffe7c4" stroke="#ff8a2a" stroke-width="5"/><path d="M48 118 l14 10 l12 -14 l14 16 l12 -12 l14 14 l14 -10 l16 8" fill="none" stroke="#c45a10" stroke-width="4"/></svg>';
      stage.classList.add("shake");
      setTimeout(function () { stage.classList.remove("shake"); show(open(n), true); showTally(); busy = false; }, reduced ? 50 : 700);
    }
    on("egg-open", "click", function () { hatch(1); });
    on("egg-ten", "click", function () { hatch(10); });
    show(rollSet("Rare"), false);
    // Cría
    var parents = [], row = $("#breed-row");
    function newParents() { parents = [rollSet(rollRarity(1, "Common", "Epic")), rollSet(rollRarity(1, "Common", "Epic"))]; drawBreed(null); }
    function card(genes, label, extra) {
      var r = RBY[rarityOf(genes)];
      return '<div class="mini-card" style="text-align:center"><div style="font-size:.8rem;color:var(--muted);font-weight:700">' + label + '</div><div class="creature-stage" style="aspect-ratio:1.2">' + creatureSVG(genes) + "</div><b>" + creatureName(genes) + '</b><span class="rarity-tag" style="background:' + rgb(r.Color) + '">' + r.DisplayName + "</span>" + (extra || "") + "</div>";
    }
    function drawBreed(child) {
      var top = RBY[[rarityOf(parents[0]), rarityOf(parents[1])].sort(function (a, b) { return tier(b) - tier(a); })[0]];
      var cost = Math.floor(C.Breeding.CostPerTierSquared * top.Tier * top.Tier * C.PriceScale);
      var secs = (C.BreedSeconds || {})[top.Name] || 600;
      row.innerHTML = card(parents[0], "Padre A") + card(parents[1], "Padre B") +
        (child ? card(child.genes, "Cría", child.mutated.length ? '<p style="margin-top:6px">🧬 Mutó: ' + child.mutated.map(function (s) { return D.SlotNames[s]; }).join(", ") + "</p>" : '<p style="margin-top:6px">Sin mutación</p>') : '<div class="mini-card" style="display:grid;place-items:center;text-align:center;min-height:200px"><div><div class="em">❔</div><p>Pulsa Criar</p></div></div>');
      $("#breed-info").textContent = "Cuesta " + short(cost) + " Monedas y tarda " + dur(secs) + " (según el padre más raro).";
    }
    on("breed-go", "click", function () { drawBreed(inherit(parents[0], parents[1])); });
    on("breed-new", "click", newParents);
    if (row) newParents();
  }

  // ------------------------------------------------------------------ nido
  function setupNest() {
    var box = $("#nest-counts");
    if (!box) return;
    var defaults = { Common: 12, Rare: 6, Epic: 2, Legendary: 1, Mythic: 0, Secret: 0 }, inputs = {};
    RAR.forEach(function (r) {
      var row = el("div", { class: "ctl" }, '<label><span style="color:' + rgb(r.Color) + ';font-weight:700">' + r.DisplayName + "</span><output>" + defaults[r.Name] + '</output></label><input type="range" min="0" max="30" value="' + defaults[r.Name] + '">');
      box.appendChild(row);
      inputs[r.Name] = row.querySelector("input");
      inputs[r.Name].addEventListener("input", function () { row.querySelector("output").textContent = inputs[r.Name].value; upd(); });
    });
    var lvl = rangeOut("nest-lvl"), gen = rangeOut("nest-gen"), x2 = $("#nest-x2"), club = $("#nest-club"), vip = $("#nest-vip");
    function upd() {
      lvl.show(); gen.show();
      var N = C.Nest, slots = Math.min(N.BaseSlots + lvl.value() * N.SlotsPerLevel, N.MaxSlots) + (vip.checked ? N.VipExtraSlots : 0);
      var list = [];
      RAR.forEach(function (r) { for (var i = 0; i < Number(inputs[r.Name].value); i++) list.push(r.Income * (1 + (D.GeneBonusPerTier || .05) * (r.Tier - 1))); });
      list.sort(function (a, b) { return b - a; });
      var base = list.slice(0, slots).reduce(function (a, b) { return a + b; }, 0);
      var mult = (1 + gen.value() * C.Rebirth.MultiplierPerGeneration) * (x2.checked ? 2 : 1) * (club.checked ? 1.2 : 1);
      var ps = base * mult;
      $("#nest-slots").textContent = slots + (list.length > slots ? " (" + (list.length - slots) + " fuera)" : "");
      $("#nest-sec").textContent = ps.toFixed(1).replace(".", ",");
      $("#nest-hour").textContent = short(ps * 3600);
      $("#nest-off").textContent = short(ps * N.OfflineCapHours * 3600 * N.OfflineRate);
    }
    [lvl.input, gen.input].forEach(function (i) { i.addEventListener("input", upd); });
    [x2, club, vip].forEach(function (i) { i.addEventListener("change", upd); });
    upd();
    // Mejoras
    var sel = $("#up-name"), ul = rangeOut("up-lvl"), UC = D.UpgradeCosts || {};
    var what = {
      Bag: function (l) { return "Bolsa: caben " + bagCapacity(l) + " de Calor (" + bagCapacity(l + 1) + " en el siguiente nivel)."; },
      Boots: function (l) { return "Botas: +" + Math.round(l * C.Movement.BootsPerLevel * 100) + " % de velocidad (máximo +" + Math.round(C.Movement.BootsMaxLevel * C.Movement.BootsPerLevel * 100) + " %)."; },
      Sniffer: function () { return "Olfato: en el diseño marca las fuentes de Calor más ricas. Todavía no hace nada en el juego."; },
      Nest: function (l) { return "Nido: " + Math.min(C.Nest.BaseSlots + l * C.Nest.SlotsPerLevel, C.Nest.MaxSlots) + " huecos que producen (+" + C.Nest.SlotsPerLevel + " por nivel). Se reinicia con la Nueva generación."; },
      Incubator: function (l) { return "Incubadora: huevos y crías un " + Math.round(l * C.Incubator.SpeedPerLevel * 100) + " % más rápidos."; },
    };
    Object.keys(UC).forEach(function (k) { sel.appendChild(el("option", { value: k }, UC[k].DisplayName)); });
    function up() {
      var u = UC[sel.value]; if (!u) return;
      ul.input.max = u.Costs.length; if (ul.value() > u.Costs.length) ul.input.value = u.Costs.length; ul.show();
      var l = ul.value();
      $("#up-cost").textContent = l < u.Costs.length ? short(u.Costs[l]) : "Máximo";
      $("#up-total").textContent = short(u.Costs.slice(l).reduce(function (a, b) { return a + b; }, 0));
      $("#up-what").textContent = what[sel.value] ? what[sel.value](l) : "";
    }
    sel.addEventListener("change", up); ul.input.addEventListener("input", up); up();
    // Nueva generación
    var rg = rangeOut("rb-gen");
    function rb() { rg.show(); $("#rb-cost").textContent = short(C.Rebirth.BaseCoins * (rg.value() + 1) * C.PriceScale); $("#rb-mult").textContent = "×" + String(1 + rg.value() * C.Rebirth.MultiplierPerGeneration).replace(".", ","); }
    rg.input.addEventListener("input", rb); rb();
    // Tarjetas
    var nc = $("#nest-cards"), rel = C.Release || {}, decos = C.Decorations || [];
    [
      ["🥚", "Incubadora", "Huevos personales por " + get("Incubator.PersonalEggCostDust") + " de polvo que nacen en " + dur(get("Incubator.PersonalEggSeconds")) + ". " + get("Incubator.BaseSlots") + " hueco (2 con el pase)."],
      ["⭐", "Favoritas", "Hasta " + get("Favorites.Max") + ": sobreviven a la Nueva generación y no se liberan por error."],
      ["🕊️", "Liberar", "Cambias criaturas que sobran por polvo (" + Object.keys(rel.Dust || {}).map(function (k) { return RBY[k].DisplayName + " " + rel.Dust[k]; }).join(", ") + "). Siempre te quedan al menos " + rel.KeepAtLeast + "."],
      ["🏮", "Decoración", decos.length + " piezas solo estéticas (farolillos, fuente, trono…) que suman Belleza para el salón de la fama."],
    ].forEach(function (r) { nc.appendChild(el("div", { class: "mini-card" }, '<div class="em">' + r[0] + "</div><b>" + r[1] + "</b><p>" + r[2] + "</p>")); });
  }

  // ------------------------------------------------------------------ eventos
  function setupWeek() {
    var box = $("#week");
    if (!box) return;
    var ev = C.Events || {}, bm = ev.BloodMoon || {}, ln = ev.LootNight || {};
    // Events.inWindow con días 1 = domingo (UTC)
    function inWindow(days, startHour, hours, t) {
      for (var off = 0; off <= 1; off++) {
        var d = new Date(t - off * 86400000), wday = d.getUTCDay() + 1, hour = new Date(t).getUTCHours() + new Date(t).getUTCMinutes() / 60;
        if (days.indexOf(wday) >= 0) { var from = hour + off * 24 - startHour; if (from >= 0 && from < hours) return true; }
      }
      return false;
    }
    function isBM(t) { return (bm.StartHours || []).some(function (h) { return inWindow([bm.WeekDay], h, bm.Hours, t); }); }
    function isLN(t) { return ln.Enabled && inWindow(ln.WeekDays || [], ln.StartHour, ln.Hours, t); }
    var now = new Date(), monday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - ((now.getDay() + 6) % 7));
    var dn = ["L", "M", "X", "J", "V", "S", "D"];
    box.appendChild(el("div"));
    dn.forEach(function (d) { box.appendChild(el("div", { class: "d" }, d)); });
    for (var h = 0; h < 24; h++) {
      box.appendChild(el("div", { class: "h" }, h % 3 === 0 ? String(h).padStart(2, "0") + ":00" : ""));
      for (var d = 0; d < 7; d++) {
        var t = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + d, h, 30).getTime();
        var cls = "c" + (isBM(t) ? " bm" : isLN(t) ? " ln" : "");
        var isNow = now.getTime() >= t - 1800000 && now.getTime() < t + 1800000;
        box.appendChild(el("div", { class: cls + (isNow ? " now" : ""), title: dn[d] + " " + h + ":00" + (isBM(t) ? " · Luna de Sangre" : isLN(t) ? " · Noche de Saqueo" : "") }));
      }
    }
    var tz = Intl.DateTimeFormat().resolvedOptions().timeZone || "tu zona";
    var active = isBM(now.getTime()) ? "🌕 ¡Ahora mismo hay Luna de Sangre!" : isLN(now.getTime()) ? "🌙 ¡Ahora mismo es Noche de Saqueo!" : "Ahora no hay ningún evento activo.";
    $("#week-now").textContent = active + " Horas en " + tz + " (el juego las define en UTC).";
  }

  // ------------------------------------------------------------------ tienda y pendiente
  function setupLists() {
    var shop = $("#shop");
    if (shop) [
      ["👑", "Nido VIP", "+" + get("Nest.VipExtraSlots") + " huecos, decoración dorada y etiqueta VIP.", true],
      ["🪙", "x2 Monedas", "Duplica lo que produce tu nido. Lo único que apenas toca la partida: adelanta las mejoras de bolsa y botas.", true],
      ["⏩", "Incubadora Rápida", "Huevos y crías un 50 % más rápidos.", true],
      ["➕", "Ranura de cría extra", "Dos crías a la vez.", true],
      ["🔥", "Estela de Brasas", "Rastro de chispas al correr. Solo estética.", true],
      ["🍀", "Suerte del Lobby", "15 min de suerte ×" + get("ServerLuck.Luck") + " en los huevos del nido de todo el lobby, con tu nombre en el anuncio.", true],
      ["🎟️", "Huevo de Temporada", "Rara a Legendaria, con las probabilidades a la vista antes de comprar.", true],
      ["🔁", "Repetir cría", "Vuelve a tirar la última cría con los mismos padres.", true],
      ["📅", "Club del Nido", "Suscripción: +20 % de Monedas y una decoración exclusiva al mes.", true],
      ["🛍️", "Tienda de la Plaza", "Temas de nido, pedestales, accesorios para la criatura del hombro, emotes y títulos. Rota cada día.", false],
      ["🎆", "Fuegos artificiales", "Espectáculo en la plaza con tu nombre y tu criatura.", false],
      ["🎁", "Regalos", "Comprar pases y productos para un amigo.", false],
    ].forEach(function (r) { shop.appendChild(el("div", { class: "mini-card" }, '<div class="em">' + r[0] + "</div><b>" + r[1] + ' <span class="pill ' + (r[3] ? "ok" : "no") + '">' + (r[3] ? "en el juego" : "diseñado") + "</span></b><p>" + r[2] + "</p>")); });
    var todo = $("#todo");
    if (todo) [
      ["👃", "Olfato", "La mejora se puede comprar pero todavía no hace nada."],
      ["🛍️", "Tienda de la Plaza y cosméticos", "Temas de nido, pedestales, accesorios del hombro, renombrar criaturas, fuegos artificiales y regalos."],
      ["🎓", "Tutorial", "Una primera partida guiada (rampas, tirolina, robar)."],
      ["⚖️", "Emparejamiento por nivel", "Novatos con novatos: con la persecución actual, los que persiguen poco ganan bastante menos."],
      ["🎨", "Arte definitivo", "Mapas hechos a mano, modelos de criatura de un artista, sonidos definitivos y música."],
      ["📺", "Huevo del Admin y pase de temporada", "Evento en directo y pase con recompensas estéticas."],
    ].forEach(function (r) { todo.appendChild(el("div", { class: "mini-card todo" }, '<div class="em">' + r[0] + "</div><b>" + r[1] + "</b><p>" + r[2] + "</p>")); });
  }

  // ------------------------------------------------------------------ arranque
  function safe(fn) { try { fn(); } catch (e) { if (window.console) console.error(e); } }
  [fillNumbers, setupChrome, setupLoop, setupQueue, setupHeat, setupBar, setupElection, setupHatchCount, setupChase, setupParkourCards, setupConsolation, setupGenes, setupEggLab, setupNest, setupWeek, setupLists].forEach(safe);
})();
