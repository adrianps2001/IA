/* The Egg Chooses · interacción de la web de documentación.
 * Las demos reproducen en JavaScript las mismas fórmulas que los módulos Luau y usan los
 * datos reales exportados por tools/export_data.luau (bloque <script id="game-data">). */

const DATA = JSON.parse(document.getElementById("game-data").textContent);
const REPO = "https://github.com/adrianps2001/IA/blob/main/";
const CFG = DATA.Config;

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
const el = (tag, props = {}, children = []) => {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (key === "class") node.className = value;
    else if (key === "html") node.innerHTML = value;
    else if (key === "style") node.style.cssText = value;
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value);
  }
  for (const child of [].concat(children)) {
    if (child != null) node.append(child.nodeType ? child : document.createTextNode(child));
  }
  return node;
};
const fmt = (n) => Math.floor(n).toLocaleString("es-ES");
const dec = (n, digits) => n.toFixed(digits).replace(".", ",");
const pct = (p) => {
  const v = p * 100;
  if (v === 0) return "0 %";
  if (v < 0.01) return dec(v, 4) + " %";
  if (v < 1) return dec(v, 2) + " %";
  return dec(v, 1) + " %";
};
const rgb = (c) => `rgb(${c[0]},${c[1]},${c[2]})`;
const storage = {
  get(key) { try { return localStorage.getItem(key); } catch { return null; } },
  set(key, value) { try { localStorage.setItem(key, value); } catch { /* sin almacenamiento */ } },
};

/* ---------------------------------------------------------------- lógica del juego (port) */

const RARITIES = DATA.Rarities;
const RI = Object.fromEntries(RARITIES.map((r) => [r.Name, r]));
const tier = (name) => RI[name].Tier;
const fromTier = (t) => RARITIES[Math.min(Math.max(Math.floor(t), 1), RARITIES.length) - 1].Name;
const GENE = {};
for (const slot of DATA.Slots) for (const g of DATA.Genes[slot]) GENE[g.Id] = g;

// Igual que el operador % de Luau: a - floor(a/b)*b.
const lmod = (a, b) => a - Math.floor(a / b) * b;

function rarityWeights(luck = 1, min, max) {
  const minT = min ? tier(min) : 1;
  const maxT = max ? tier(max) : RARITIES.length;
  return RARITIES.map((r) => (r.Tier >= minT && r.Tier <= maxT ? r.Weight * (r.Tier > 1 ? Math.max(luck, 0) : 1) : 0));
}

function rarityChances(luck, min, max) {
  const w = rarityWeights(luck, min, max);
  const total = w.reduce((a, b) => a + b, 0);
  return Object.fromEntries(RARITIES.map((r, i) => [r.Name, total > 0 ? w[i] / total : 0]));
}

function rollRarity(rng, luck, min, max) {
  const w = rarityWeights(luck, min, max);
  const total = w.reduce((a, b) => a + b, 0);
  if (total <= 0) return fromTier(min ? tier(min) : 1);
  let pick = rng() * total;
  for (let i = 0; i < RARITIES.length; i++) {
    pick -= w[i];
    if (pick < 0) return RARITIES[i].Name;
  }
  return fromTier(max ? tier(max) : RARITIES.length);
}

const genesOfTier = (slot, t) => DATA.Genes[slot].filter((g) => tier(g.Rarity) === t);
const pickFrom = (list, rng) => list[Math.floor(rng() * list.length)] || list[0];

function rollSlot(slot, rng, maxRarity, biasId) {
  const maxT = tier(maxRarity);
  if (biasId) {
    const b = GENE[biasId];
    if (b && b.Slot === slot && tier(b.Rarity) <= maxT && rng() < DATA.BiasChance) return b.Id;
  }
  let t = tier(rollRarity(rng, 1, null, maxRarity));
  while (t >= 1) {
    const c = genesOfTier(slot, t);
    if (c.length) return pickFrom(c, rng).Id;
    t--;
  }
  return DATA.Genes[slot][0].Id;
}

function rollSet(rng, rarity, biases = {}) {
  const t = tier(rarity);
  const sigSlots = DATA.Slots.filter((s) => genesOfTier(s, t).length > 0);
  const sig = sigSlots[Math.floor(rng() * sigSlots.length)] || sigSlots[0];
  const result = {};
  for (const slot of DATA.Slots) {
    if (slot === sig) {
      const b = GENE[biases[slot]];
      result[slot] = b && b.Slot === slot && b.Rarity === rarity && rng() < DATA.BiasChance ? b.Id : pickFrom(genesOfTier(slot, t), rng).Id;
    } else {
      result[slot] = rollSlot(slot, rng, rarity, biases[slot]);
    }
  }
  return result;
}

function rarityOf(genes) {
  let best = 1;
  for (const slot of DATA.Slots) best = Math.max(best, tier(GENE[genes[slot]].Rarity));
  return fromTier(best);
}

function creatureName(genes) {
  const parts = [GENE[genes.Body].Name];
  if (genes.Pattern !== "pattern_plain") parts.push(GENE[genes.Pattern].Name);
  if (genes.Mutation !== "mut_none") parts.push(GENE[genes.Mutation].Name);
  return parts.join(" ");
}

// Creature.baseIncome (v3.2): la suma de lo que da cada una de las 5 partes según su rareza.
function baseIncome(genes) {
  let total = 0;
  for (const slot of DATA.Slots) total += RI[GENE[genes[slot]].Rarity].PartIncome;
  return total;
}

function electionChances(entries, minChance) {
  const result = {};
  const n = entries.length;
  if (!n) return result;
  if (minChance * n >= 1) {
    for (const e of entries) result[e.key] = 1 / n;
    return result;
  }
  const pinned = new Set();
  for (;;) {
    let freeMass = 1;
    let freeAff = 0;
    for (const e of entries) {
      if (pinned.has(e.key)) freeMass -= minChance;
      else freeAff += Math.max(e.affinity, 0);
    }
    const freeCount = entries.filter((e) => !pinned.has(e.key)).length;
    let changed = false;
    for (const e of entries) {
      if (pinned.has(e.key)) continue;
      const share = freeAff > 0 ? (freeMass * Math.max(e.affinity, 0)) / freeAff : freeMass / freeCount;
      if (share < minChance) {
        pinned.add(e.key);
        changed = true;
      } else result[e.key] = share;
    }
    if (!changed) break;
  }
  for (const key of pinned) result[key] = minChance;
  return result;
}

function thresholdFor(fraction) {
  let minRarity = "Common", luck = 1, reached = 0;
  CFG.Thresholds.forEach((t, i) => {
    if (fraction >= t.Fraction) {
      minRarity = t.MinRarity;
      luck = t.Luck;
      reached = i + 1;
    }
  });
  return { minRarity, luck, reached };
}

function consolationDust(affinity, attempts) {
  const c = CFG.Consolation;
  const a = Math.min(Math.max(attempts, 0), c.MaxStealAttempts);
  return Math.floor(c.Base + Math.max(affinity, 0) * c.PerAffinity + a * c.PerStealAttempt);
}

function walkSpeed(boots, carrier, sprint) {
  const b = Math.min(Math.max(boots, 0), CFG.Movement.BootsMaxLevel) * CFG.Movement.BootsPerLevel;
  let s = CFG.Movement.BaseWalkSpeed * (1 + b);
  if (carrier) s *= CFG.Chase.CarrierSpeedMultiplier;
  if (sprint) s *= CFG.Chase.SprintMultiplier;
  return s;
}

function questsForDay(day) {
  const n = DATA.Quests.length;
  const order = Array.from({ length: n }, (_, i) => i + 1);
  let state = lmod(day * 1103515245 + 12345, 2147483648);
  for (let i = n; i >= 2; i--) {
    state = lmod(state * 1103515245 + 12345, 2147483648);
    const j = lmod(state, i) + 1;
    [order[i - 1], order[j - 1]] = [order[j - 1], order[i - 1]];
  }
  return order.slice(0, CFG.Quests.PerDay).map((i) => DATA.Quests[i - 1]);
}

/* ---------------------------------------------------------------- dibujo de criaturas */

// Proporciones de CreatureModel.luau (BODY_SHAPES), en studs.
const BODY_SHAPES = {
  body_round: [3, 3], body_chubby: [3.6, 3], body_long: [4, 2.4], body_tiny: [2.2, 2.2],
  body_fluffy: [3.4, 3.2], body_crystal: [2.8, 3.4], body_lava: [3.2, 3], body_jelly: [3.4, 2.6],
  body_stone: [3.4, 3.4], body_cloud: [4, 2.6], body_star: [3.2, 3.2], body_void: [3.2, 3.2],
};
const NS = "http://www.w3.org/2000/svg";
const svgEl = (tag, attrs = {}) => {
  const n = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, v);
  return n;
};
let svgUid = 0;

function drawCreature(svg, genes) {
  svg.innerHTML = "";
  const uid = ++svgUid;
  const mut = genes.Mutation;
  const scale = mut === "mut_big" ? 1.22 : mut === "mut_small" ? 0.7 : 1;
  const [bw, bh] = BODY_SHAPES[genes.Body] || [3, 3];
  const rx = bw * 17 * scale, ry = bh * 17 * scale;
  const cx = 120, cy = 140;
  let body = rgb(GENE[genes.Body].Color);
  if (mut === "mut_golden") body = "rgb(255,200,40)";
  if (mut === "mut_inverted") {
    const c = GENE[genes.Body].Color;
    body = rgb([255 - c[0], 255 - c[1], 255 - c[2]]);
  }
  const rarity = RI[rarityOf(genes)];
  const defs = svgEl("defs");
  const grad = svgEl("radialGradient", { id: `aura${uid}` });
  const auraColor = rgb(GENE[genes.Aura].Color);
  grad.append(svgEl("stop", { offset: "0%", "stop-color": auraColor, "stop-opacity": "0.75" }));
  grad.append(svgEl("stop", { offset: "100%", "stop-color": auraColor, "stop-opacity": "0" }));
  defs.append(grad);
  const shade = svgEl("radialGradient", { id: `shade${uid}`, cx: "35%", cy: "30%" });
  shade.append(svgEl("stop", { offset: "0%", "stop-color": "#fff", "stop-opacity": "0.55" }));
  shade.append(svgEl("stop", { offset: "60%", "stop-color": "#fff", "stop-opacity": "0" }));
  defs.append(shade);
  svg.append(defs);

  // Halo de rareza (Épica o más, como la PointLight del modelo 3D).
  if (rarity.Tier >= 3) svg.append(svgEl("circle", { cx, cy: cy - 20, r: 110, fill: rgb(rarity.Color), opacity: 0.1 }));

  if (genes.Aura !== "aura_none") {
    const glow = svgEl("circle", { cx, cy: cy - 15, r: Math.max(rx, ry) + 40, fill: `url(#aura${uid})` });
    glow.append(svgEl("animate", { attributeName: "r", values: `${Math.max(rx, ry) + 30};${Math.max(rx, ry) + 46};${Math.max(rx, ry) + 30}`, dur: "2.2s", repeatCount: "indefinite" }));
    svg.append(glow);
    const count = 4 + 2 * tier(GENE[genes.Aura].Rarity);
    for (let i = 0; i < count; i++) {
      const a = (i / count) * Math.PI * 2;
      const px = cx + Math.cos(a) * (rx + 22), py = cy - 10 + Math.sin(a) * (ry + 26);
      const p = svgEl("circle", { cx: px, cy: py, r: 3.2, fill: auraColor });
      p.append(svgEl("animate", { attributeName: "cy", values: `${py};${py - 16};${py}`, dur: `${1.6 + (i % 3) * 0.5}s`, repeatCount: "indefinite" }));
      p.append(svgEl("animate", { attributeName: "opacity", values: "0.2;1;0.2", dur: `${1.6 + (i % 3) * 0.5}s`, repeatCount: "indefinite" }));
      svg.append(p);
    }
  }

  const g = svgEl("g", { opacity: mut === "mut_ghost" ? 0.55 : 1 });
  svg.append(g);
  const neon = ["body_lava", "body_star", "body_void"].includes(genes.Body) || ["mut_glow", "mut_cosmic", "mut_rainbow"].includes(mut);
  g.append(svgEl("ellipse", { cx, cy: cy + ry + 4, rx: rx * 0.85, ry: 7, fill: "#000", opacity: 0.12 }));
  const bodyEl = svgEl("ellipse", {
    cx, cy, rx, ry, fill: body,
    stroke: neon ? "#fff" : "rgba(0,0,0,.25)", "stroke-width": neon ? 3 : 2,
    "fill-opacity": ["body_crystal", "body_jelly"].includes(genes.Body) ? 0.78 : 1,
  });
  if (neon) bodyEl.setAttribute("style", `filter: drop-shadow(0 0 8px ${body})`);
  if (mut === "mut_rainbow") {
    bodyEl.append(svgEl("animate", { attributeName: "fill", values: "#ff4d4d;#ffb84d;#fff04d;#4dff88;#4dc3ff;#a64dff;#ff4d4d", dur: "3s", repeatCount: "indefinite" }));
  }
  g.append(bodyEl);

  // Patrón: manchas del color del gen.
  if (genes.Pattern !== "pattern_plain") {
    const pg = GENE[genes.Pattern];
    const n = 3 + tier(pg.Rarity);
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2 + 0.4;
      g.append(svgEl("circle", {
        cx: cx + Math.cos(a) * rx * 0.58, cy: cy + 8 + Math.sin(a) * ry * 0.5, r: 7 * scale,
        fill: rgb(pg.Color), opacity: 0.9,
        style: tier(pg.Rarity) >= 4 ? `filter: drop-shadow(0 0 4px ${rgb(pg.Color)})` : "",
      }));
    }
  }
  if (mut === "mut_shiny" || mut === "mut_golden") g.append(svgEl("ellipse", { cx, cy, rx, ry, fill: `url(#shade${uid})` }));

  // Cabeza, ojos y rasgo de la cabeza.
  const hr = 22 * scale;
  const hx = cx, hy = cy - ry * 0.78;
  g.append(svgEl("circle", { cx: hx, cy: hy, r: hr, fill: body, stroke: "rgba(0,0,0,.25)", "stroke-width": 2 }));
  const head = GENE[genes.Head];
  const crestColor = rgb(head.Color);
  if (genes.Head === "head_halo") {
    g.append(svgEl("ellipse", { cx: hx, cy: hy - hr - 9, rx: hr * 0.9, ry: 6, fill: "none", stroke: crestColor, "stroke-width": 4, style: `filter: drop-shadow(0 0 6px ${crestColor})` }));
  } else if (genes.Head !== "head_beak") {
    g.append(svgEl("rect", { x: hx - 6 * scale, y: hy - hr - 16 * scale, width: 12 * scale, height: 20 * scale, rx: 5, fill: crestColor, stroke: "rgba(0,0,0,.25)" }));
  }
  if (genes.Head === "head_cyclops") {
    g.append(svgEl("circle", { cx: hx, cy: hy - 2, r: 7 * scale, fill: "#1a1a1a" }));
    g.append(svgEl("circle", { cx: hx + 2, cy: hy - 4, r: 2.2, fill: "#fff" }));
  } else {
    for (const side of [-1, 1]) {
      g.append(svgEl("circle", { cx: hx + side * 8 * scale, cy: hy - 2, r: 4.2 * scale, fill: "#1a1a1a" }));
      g.append(svgEl("circle", { cx: hx + side * 8 * scale + 1.4, cy: hy - 3.6, r: 1.4, fill: "#fff" }));
    }
  }
  if (genes.Head === "head_beak") {
    g.append(svgEl("path", { d: `M${hx - 6} ${hy + 6} L${hx + 6} ${hy + 6} L${hx} ${hy + 15} Z`, fill: crestColor }));
  }
}

/* ---------------------------------------------------------------- demos */

const PHASES = [
  { key: "IntermissionTime", name: "Preparados", icon: "⏳", color: "#8a7f92", text: "RoundService reinicia el huevo (EggService.reset), el Calor de todos (HeatService.resetRound) y los tratos (ChaseService.resetRound)." },
  { key: "IncubationTime", name: "Incubación", icon: "🔥", color: "#ff8a2a", text: "HeatService activa las fuentes de Calor. Cada depósito suma Afinidad (y escudos para la persecución) y llena la barra; a mitad hay una lluvia de brasas doradas. Si la barra llega al 100 % la fase termina antes." },
  { key: "HatchTime", name: "Eclosión", icon: "🥚", color: "#7b5cff", text: "Sale una criatura por cada pocos jugadores; Election elige un dueño distinto para cada una y los clientes ven los focos (10 s, sin bloquear la cámara)." },
  { key: "ChaseTime", name: "Persecución", icon: "🏃", color: "#e0464d", text: "ChaseService pone una correa a cada elegido, que huye y se esconde por el parkour; cada 8 s da la señal y todos lo ven. Robar = un toque y quedarse cerca 1,5 s (tira y afloja); el servidor cuenta el tiempo y los escudos de Afinidad bloquean un robo." },
  { key: "ResultsTime", name: "Resultados", icon: "🏆", color: "#2fa85a", text: "Quien tenga la criatura al acabar el tiempo se la queda; el elegido que la perdió recibe un Huevo del Elegido y el resto, Polvo de cáscara (si participó). Después, todos vuelven al lobby." },
];

function demoRound(root) {
  const bar = $(".timeline", root);
  const info = $(".phase-info", root);
  const moon = $("input[type=checkbox]", root);
  const btn = $(".btn", root);
  let cursor, segs = [], total = 0, timer = null;
  const dur = (p) => (p.key === "ChaseTime" && moon.checked ? CFG.Round.BloodMoonChaseTime : CFG.Round[p.key]);
  function layout() {
    bar.innerHTML = "";
    total = PHASES.reduce((a, p) => a + dur(p), 0);
    const label = (secs) => (secs < 60 ? `${secs} s` : `${dec(secs / 60, secs % 60 ? 1 : 0)} min`);
    segs = PHASES.map((p) => {
      const narrow = dur(p) / total < 0.07;
      const s = el("div", { class: "seg", title: `${p.name} · ${label(dur(p))}`, style: `flex:${dur(p)};background:${p.color}` },
        narrow ? [el("b", { style: "text-align:center" }, p.icon)] : [el("b", {}, `${p.icon} ${p.name}`), el("span", {}, label(dur(p)))]);
      s.addEventListener("click", () => (info.innerHTML = `<b>${p.name} · ${dur(p)} s.</b> ${p.text}`));
      bar.append(s);
      return s;
    });
    cursor = el("div", { class: "cursor" });
    bar.append(cursor);
    $(".total", root).textContent = `Total: ${Math.floor(total / 60)} min ${total % 60} s`;
  }
  moon.addEventListener("change", layout);
  btn.addEventListener("click", () => {
    if (timer) cancelAnimationFrame(timer);
    const start = performance.now();
    const length = 12000; // 12 s reales = una ronda
    const step = (now) => {
      const f = Math.min((now - start) / length, 1);
      cursor.style.left = `calc(${f * 100}% - 1px)`;
      let acc = 0;
      for (const p of PHASES) {
        acc += dur(p);
        if (f * total <= acc) {
          info.innerHTML = `<b>${p.name}</b> · quedan ${Math.ceil(acc - f * total)} s de la fase. ${p.text}`;
          break;
        }
      }
      if (f < 1) timer = requestAnimationFrame(step);
    };
    timer = requestAnimationFrame(step);
  });
  layout();
  info.innerHTML = "Pulsa una fase para ver qué código se ejecuta, o reproduce la ronda acelerada.";
}

function rarityOptions(select, selected) {
  for (const r of RARITIES) select.append(el("option", { value: r.Name }, r.DisplayName));
  select.value = selected;
}

function demoRarity(root) {
  const luck = $("input[name=luck]", root);
  const min = $("select[name=min]", root);
  const max = $("select[name=max]", root);
  rarityOptions(min, "Common");
  rarityOptions(max, "Secret");
  const bars = $(".bars", root);
  function render() {
    $(".luck-val", root).textContent = `x${dec(Number(luck.value), 2)}`;
    const ch = rarityChances(Number(luck.value), min.value, max.value);
    bars.innerHTML = "";
    for (const r of RARITIES) {
      const p = ch[r.Name];
      const w = p > 0 ? Math.max(Math.sqrt(p) * 100, 1.5) : 0; // raíz para que se vea lo muy raro
      bars.append(el("div", { class: "bar-row" }, [
        el("span", {}, [el("span", { class: "pill", style: `background:${rgb(r.Color)}` }, r.DisplayName)]),
        el("div", { class: "bar-track" }, el("div", { class: "bar-fill", style: `width:${w}%;background:${rgb(r.Color)}` })),
        el("span", { class: "val" }, pct(p)),
      ]));
    }
  }
  [luck, min, max].forEach((i) => i.addEventListener("input", render));
  render();
}

function demoGenes(root) {
  const tabs = $(".tabs", root);
  const grid = $(".gene-grid", root);
  let current = DATA.Slots[0];
  function render() {
    tabs.innerHTML = "";
    for (const slot of DATA.Slots) {
      tabs.append(el("button", { class: slot === current ? "on" : "", onclick: () => { current = slot; render(); } }, DATA.SlotNames[slot]));
    }
    grid.innerHTML = "";
    for (const g of DATA.Genes[current]) {
      const r = RI[g.Rarity];
      grid.append(el("span", { class: "gene-chip", title: `${g.Id} · ${r.DisplayName}` }, [
        el("i", { style: `background:${rgb(g.Color)};border-color:${rgb(r.Color)}` }),
        g.Name,
        el("span", { class: "pill", style: `background:${rgb(r.Color)}` }, r.DisplayName),
      ]));
    }
  }
  render();
}

function demoCreature(root) {
  const svg = $("svg", root);
  const luck = $("input[name=luck]", root);
  const min = $("select[name=min]", root);
  const offering = $("select[name=offering]", root);
  rarityOptions(min, "Common");
  for (const [key, o] of Object.entries(DATA.Offerings)) offering.append(el("option", { value: key }, `${o.DisplayName} (${GENE[o.Gene].Name})`));
  const out = $(".lab-info", root);
  const counts = {};
  let total = 0;
  function hatch() {
    const biases = {};
    if (offering.value) {
      const o = DATA.Offerings[offering.value];
      biases[o.Slot] = o.Gene;
    }
    const rarity = rollRarity(Math.random, Number(luck.value), min.value, null);
    const genes = rollSet(Math.random, rarity, biases);
    const r = RI[rarityOf(genes)];
    counts[r.Name] = (counts[r.Name] || 0) + 1;
    total++;
    drawCreature(svg, genes);
    out.innerHTML = "";
    out.append(
      el("p", { class: "name" }, creatureName(genes)),
      el("span", { class: "pill", style: `background:${rgb(r.Color)}` }, r.DisplayName),
      el("span", { class: "muted" }, `  ${dec(baseIncome(genes), 2)} Monedas/s`),
    );
    const list = el("div", { class: "gene-list" });
    for (const slot of DATA.Slots) {
      const gene = GENE[genes[slot]];
      const gr = RI[gene.Rarity];
      list.append(el("span", { class: "muted" }, DATA.SlotNames[slot]), el("span", {}, gene.Name), el("span", { class: "pill", style: `background:${rgb(gr.Color)}` }, gr.DisplayName));
    }
    out.append(list);
    $(".tally", root).textContent = `Eclosiones: ${total} · ` + RARITIES.filter((x) => counts[x.Name]).map((x) => `${x.DisplayName} ${counts[x.Name]}`).join(" · ");
  }
  const showLuck = () => ($(".luck-val", root).textContent = `x${dec(Number(luck.value), 2)}`);
  showLuck();
  luck.addEventListener("input", showLuck);
  $(".btn", root).addEventListener("click", hatch);
  hatch();
}

function demoElection(root) {
  const list = $(".players", root);
  let players = [
    { key: "1", name: "Ana", affinity: 900 },
    { key: "2", name: "Leo", affinity: 320 },
    { key: "3", name: "Sara", affinity: 140 },
    { key: "4", name: "Tú", affinity: 0 },
    { key: "5", name: "Max", affinity: 0 },
  ];
  let nextKey = 6;
  let rows = {};
  const min = CFG.Election.MinChance;
  function chances() {
    return electionChances(players.map((p) => ({ key: p.key, affinity: p.affinity })), min);
  }
  function refresh() {
    const ch = chances();
    for (const p of players) {
      const row = rows[p.key];
      $(".aff", row).textContent = fmt(p.affinity);
      $(".chance", row).textContent = pct(ch[p.key]);
    }
    const total = players.reduce((a, p) => a + p.affinity, 0);
    $(".sum", root).textContent = `Afinidad total: ${fmt(total)} · mínimo garantizado ${pct(min)}`;
  }
  function render() {
    list.innerHTML = "";
    rows = {};
    for (const p of players) {
      const name = el("input", { type: "text", value: p.name, "aria-label": "Nombre" });
      name.addEventListener("input", () => (p.name = name.value));
      const slider = el("input", { type: "range", min: 0, max: 2000, step: 10, value: p.affinity, "aria-label": "Afinidad" });
      slider.addEventListener("input", () => { p.affinity = Number(slider.value); refresh(); });
      const remove = el("button", { class: "x", title: "Quitar", onclick: () => { if (players.length > 1) { players = players.filter((x) => x !== p); render(); } } }, "✕");
      const row = el("div", { class: "player-row" }, [name, slider, el("span", { class: "aff val" }), el("b", { class: "chance" }), remove]);
      rows[p.key] = row;
      list.append(row);
    }
    refresh();
  }
  $(".add", root).addEventListener("click", () => {
    if (players.length >= 16) return;
    players.push({ key: String(nextKey), name: `Jugador ${nextKey}`, affinity: 0 });
    nextKey++;
    render();
  });
  $(".pick", root).addEventListener("click", async (ev) => {
    const btn = ev.currentTarget;
    btn.disabled = true;
    const ch = chances();
    let roll = Math.random(), winner = players[players.length - 1];
    for (const p of players) { roll -= ch[p.key]; if (roll < 0) { winner = p; break; } }
    const order = players.map((p) => rows[p.key]);
    Object.values(rows).forEach((r) => r.classList.remove("win", "lit"));
    const wi = players.indexOf(winner);
    const steps = order.length * 3 + ((wi - (order.length * 3) % order.length) + order.length) % order.length + 1;
    for (let s = 0; s < steps; s++) {
      order.forEach((r) => r.classList.remove("lit"));
      order[s % order.length].classList.add("lit");
      const t = (s + 1) / steps;
      await new Promise((r) => setTimeout(r, 60 + 320 * t * t));
    }
    order.forEach((r) => r.classList.remove("lit"));
    rows[winner.key].classList.add("win");
    $(".result", root).textContent = `🥚 El huevo elige a ${winner.name} (tenía un ${pct(ch[winner.key])}).`;
    btn.disabled = false;
  });
  $(".sim", root).addEventListener("click", () => {
    const ch = chances();
    const wins = Object.fromEntries(players.map((p) => [p.key, 0]));
    const N = 10000;
    for (let i = 0; i < N; i++) {
      let roll = Math.random(), w = players[players.length - 1];
      for (const p of players) { roll -= ch[p.key]; if (roll < 0) { w = p; break; } }
      wins[w.key]++;
    }
    $(".result", root).textContent = "10.000 elecciones: " + players.map((p) => `${p.name} ${pct(wins[p.key] / N)}`).join(" · ");
  });
  render();
}

function demoThresholds(root) {
  const slider = $("input", root);
  const fill = $(".bar-fill", root);
  const track = $(".bar-track", root);
  for (const t of CFG.Thresholds) {
    if (t.Fraction < 1) track.append(el("div", { style: `position:absolute;top:0;bottom:0;left:${t.Fraction * 100}%;width:2px;background:var(--text);opacity:.4` }));
  }
  function render() {
    const f = Number(slider.value) / 100;
    const t = thresholdFor(f);
    fill.style.width = `${f * 100}%`;
    $(".out", root).innerHTML = `Barra al <b>${Math.round(f * 100)} %</b> → umbrales alcanzados: <b>${t.reached}</b> · rareza mínima <span class="pill" style="background:${rgb(RI[t.minRarity].Color)}">${RI[t.minRarity].DisplayName}</span> · suerte <b>x${dec(t.luck, 2)}</b>`;
  }
  slider.addEventListener("input", render);
  render();
}

function demoEconomy(root) {
  const select = $("select[name=upgrade]", root);
  for (const [key, u] of Object.entries(DATA.UpgradeCosts)) select.append(el("option", { value: key }, u.DisplayName));
  const bars = $(".bars", root);
  function renderCosts() {
    const costs = DATA.UpgradeCosts[select.value].Costs;
    const max = Math.max(...costs);
    bars.innerHTML = "";
    let acc = 0;
    costs.forEach((c, i) => {
      acc += c;
      bars.append(el("div", { class: "bar-row" }, [
        el("span", {}, `Nivel ${i} → ${i + 1}`),
        el("div", { class: "bar-track" }, el("div", { class: "bar-fill", style: `width:${(c / max) * 100}%;background:var(--p4)` })),
        el("span", { class: "val" }, fmt(c)),
      ]));
    });
    $(".acc", root).textContent = `Coste total hasta el máximo: ${fmt(acc)} Monedas`;
  }
  select.addEventListener("change", renderCosts);
  renderCosts();

  const aff = $("input[name=aff]", root), att = $("input[name=att]", root);
  const boots = $("input[name=boots]", root), carrier = $("input[name=carrier]", root), sprint = $("input[name=sprint]", root);
  function renderCalc() {
    const d = consolationDust(Number(aff.value), Number(att.value));
    $(".dust", root).innerHTML = `Afinidad <b>${aff.value}</b>, intentos de robo <b>${att.value}</b> → <b>${d}</b> de Polvo de consuelo (el ganador recibe además +${CFG.Consolation.WinnerBonusDust}).`;
    $(".speed", root).innerHTML = `Velocidad: <b>${dec(walkSpeed(Number(boots.value), carrier.checked, sprint.checked), 2)}</b> studs/s (botas nivel ${boots.value}).`;
  }
  [aff, att, boots, carrier, sprint].forEach((i) => i.addEventListener("input", renderCalc));
  renderCalc();
}

function demoQuests(root) {
  const input = $("input[type=date]", root);
  input.value = new Date().toISOString().slice(0, 10);
  function render() {
    const [y, m, d] = input.value.split("-").map(Number);
    if (!y) return;
    const day = Math.floor(Date.UTC(y, m - 1, d) / 86400000);
    const qs = questsForDay(day);
    $(".out", root).innerHTML = `<p class="muted">Día número ${day} desde 1970 (UTC):</p>` + qs.map((q) => `<div class="card" style="margin:6px 0;padding:10px 14px">📜 ${q.Text} <span class="muted">· premio ${CFG.Quests.RewardDust} de Polvo</span></div>`).join("");
  }
  input.addEventListener("input", render);
  render();
}

function demoHeartbeat(root) {
  const slider = $("input", root);
  const egg = $(".egg-beat", root);
  let phase = 0, last = performance.now();
  function frame(now) {
    const dt = Math.min((now - last) / 1000, 0.1);
    last = now;
    const f = Number(slider.value) / 100;
    const bpm = 50 + 100 * f;
    phase += (dt * bpm) / 60;
    const beat = Math.pow(Math.max(0, Math.sin(phase * Math.PI * 2)), 6);
    const s = 1 + beat * (0.03 + 0.05 * f);
    egg.setAttribute("transform", `translate(100 120) scale(${s}) translate(-100 -120)`);
    $(".out", root).textContent = `Barra ${Math.round(f * 100)} % → ${Math.round(bpm)} latidos por minuto, tamaño máximo +${dec((0.03 + 0.05 * f) * 100, 1)} %`;
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}

function demoMap(root) {
  const svg = $("svg", root);
  const R = 150, nestR = 128, zoneR = 82;
  const add = (tag, attrs, parent = svg) => { const n = svgEl(tag, attrs); parent.append(n); return n; };
  add("circle", { cx: 0, cy: 0, r: R + 10, fill: "#4a5c3a" });
  add("circle", { cx: 0, cy: 0, r: R + 8, fill: "none", stroke: "#fff", "stroke-dasharray": "4 4", opacity: 0.5 });
  const zones = { Swamp: [45, "#3c5a46"], CrystalCave: [135, "#5aa7c8"], Ruins: [225, "#a8a396"], Bridge: [315, "#8a6a4a"] };
  for (const [, [deg, color]] of Object.entries(zones)) {
    const a = (deg * Math.PI) / 180;
    add("circle", { cx: Math.cos(a) * zoneR, cy: Math.sin(a) * zoneR, r: 23, fill: color, opacity: 0.6 });
  }
  for (let i = 1; i <= 4; i++) {
    const a = (i / 4) * Math.PI * 2 + Math.PI / 4;
    add("circle", { cx: Math.cos(a) * 58, cy: Math.sin(a) * 58, r: 4.5, fill: "#5a9fc8", stroke: "#fff" });
  }
  add("circle", { cx: 0, cy: 0, r: 25, fill: "#78644a" });
  add("ellipse", { cx: 0, cy: 0, rx: 7, ry: 9, fill: "#fff0d2", stroke: "#ff9a40", "stroke-width": 2 });
  // Campamentos de salida.
  for (let i = 1; i <= CFG.Nest.Count; i++) {
    const a = (i / CFG.Nest.Count) * Math.PI * 2;
    add("circle", { cx: Math.cos(a) * nestR, cy: Math.sin(a) * nestR, r: 10, fill: "#b48c5a", stroke: "#6e553c", "stroke-width": 1.5 });
  }
  const arena = DATA.Arena;
  if (!arena) return;
  const tip = $(".map-tip", root);
  // Árboles: plataforma cuadrada y tronco.
  arena.Trees.forEach((t, i) => {
    const g = add("g", { style: "cursor:pointer" });
    // Plataforma octogonal (apotema t.Half).
    const corner = t.Half / Math.cos(Math.PI / 8);
    const pts = [];
    for (let k = 0; k < 8; k++) {
      const a = (k + 0.5) * Math.PI / 4;
      pts.push(`${t.X + Math.cos(a) * corner},${t.Z + Math.sin(a) * corner}`);
    }
    add("polygon", { points: pts.join(" "), fill: "#8a6a4a", opacity: 0.8 }, g);
    add("circle", { cx: t.X, cy: t.Z, r: t.Radius, fill: "#5a3d28", stroke: "#e88a4a", "stroke-width": 1.2 }, g);
    if (t.Ramp) add("circle", { cx: t.X, cy: t.Z, r: t.Half / Math.cos(Math.PI / 8) + 2.8, fill: "none", stroke: "#d9b07a", "stroke-width": 2.5, "stroke-dasharray": "3 2", opacity: 0.8 }, g);
    const decks = t.Decks.map((d) => `${d}`).join(", ");
    g.addEventListener("mouseenter", () => (tip.textContent = `Árbol ${i + 1}: ${t.Decks.length} pisos, a ${decks} studs de altura · ${t.Ramp ? "rampa en espiral con barandilla" : "escalera de mano"}${t.Hut ? " · cabaña para esconderse" : ""}.`));
  });
  const colors = { Bridge: ["#d9b07a", 3.5, ""], Beam: ["#5a3d28", 1.6, ""], Stones: ["#9aa3a8", 2.5, "2 4"] };
  for (const l of arena.Links) {
    const [color, width, dash] = colors[l.Kind];
    add("line", { x1: l.From[0], y1: l.From[1], x2: l.To[0], y2: l.To[1], stroke: color, "stroke-width": width, "stroke-dasharray": dash, "stroke-linecap": "round" });
  }
  for (const r of arena.Rides) {
    add("line", { x1: r.From[0], y1: r.From[1], x2: r.To[0], y2: r.To[1], stroke: "#4c9be8", "stroke-width": 1.4, "stroke-dasharray": r.Kind === "Zipline" ? "5 3" : "", "marker-end": "" });
    add("circle", { cx: r.To[0], cy: r.To[1], r: 1.8, fill: "#4c9be8" });
  }
  for (const [x, z] of arena.Trampolines) add("circle", { cx: x, cy: z, r: 2.6, fill: "#e0464d", stroke: "#fff", "stroke-width": 0.8 });
}

const DEMOS = {
  round: demoRound, rarity: demoRarity, genes: demoGenes, creature: demoCreature,
  election: demoElection, thresholds: demoThresholds, economy: demoEconomy,
  quests: demoQuests, heartbeat: demoHeartbeat, map: demoMap,
};

/* ---------------------------------------------------------------- árbol de archivos */

function buildTree() {
  const root = $("#file-tree");
  if (!root) return;
  const articles = $$("article[data-path]", $("#file-docs"));
  const list = $(".tree-list", root);
  const detail = $(".tree-detail", root);
  let lastDir = null;
  let totalLoc = 0;
  function show(article, button) {
    $$("button", list).forEach((b) => b.classList.remove("on"));
    button.classList.add("on");
    detail.innerHTML = "";
    detail.append(
      el("h4", {}, article.dataset.path),
      el("div", { class: "where" }, [article.dataset.where, " · ", el("a", { href: REPO + article.dataset.path, target: "_blank", rel: "noopener" }, "ver en GitHub")]),
    );
    detail.append(...Array.from(article.cloneNode(true).childNodes));
  }
  articles.forEach((article, i) => {
    const path = article.dataset.path;
    const dir = path.includes("/") ? path.slice(0, path.lastIndexOf("/") + 1) : "/";
    if (dir !== lastDir) {
      list.append(el("div", { class: "dir" }, dir));
      lastDir = dir;
    }
    const loc = $("span[data-loc]", article);
    if (loc) totalLoc += Number(loc.textContent) || 0;
    const btn = el("button", {}, path.slice(dir === "/" ? 0 : dir.length));
    btn.addEventListener("click", () => show(article, btn));
    list.append(btn);
    if (i === 0) show(article, btn);
  });
  const stat = $("#stat-loc");
  if (stat) stat.textContent = fmt(totalLoc);
}

/* ---------------------------------------------------------------- código y diagramas */

function enhanceCode() {
  for (const pre of $$("pre.code")) {
    const file = pre.dataset.file;
    const [a, b] = (pre.dataset.lines || "1-1").split("-").map(Number);
    const box = el("div", { class: "codebox" });
    pre.replaceWith(box);
    const copy = el("button", { type: "button" }, "Copiar");
    copy.addEventListener("click", async () => {
      try {
        await navigator.clipboard.writeText(pre.textContent);
        copy.textContent = "¡Copiado!";
      } catch {
        copy.textContent = "No se pudo";
      }
      setTimeout(() => (copy.textContent = "Copiar"), 1400);
    });
    box.append(
      el("div", { class: "codebox-head" }, [
        el("span", { class: "file" }, file),
        el("span", { class: "lines" }, `líneas ${a}–${b}`),
        el("span", { class: "spacer" }),
        copy,
        el("a", { href: `${REPO}${file}#L${a}-L${b}`, target: "_blank", rel: "noopener" }, "GitHub ↗"),
      ]),
      pre,
    );
    if (window.hljs) window.hljs.highlightElement($("code", pre));
    if (b - a > 30) {
      box.classList.add("collapsed");
      const more = el("button", { class: "expand", type: "button" }, `Mostrar las ${b - a + 1} líneas`);
      more.addEventListener("click", () => {
        const collapsed = box.classList.toggle("collapsed");
        more.textContent = collapsed ? `Mostrar las ${b - a + 1} líneas` : "Mostrar menos";
      });
      box.append(more);
    }
  }
  for (const code of $$(".compare pre code, pre.lua-plain code")) if (window.hljs) window.hljs.highlightElement(code);
}

let mermaidLib = null;
const isDark = () => {
  const forced = document.documentElement.dataset.theme;
  if (forced) return forced === "dark";
  return window.matchMedia("(prefers-color-scheme: dark)").matches;
};

async function renderDiagrams() {
  const nodes = $$(".mermaid");
  if (!nodes.length) return;
  try {
    if (!mermaidLib) mermaidLib = (await import("https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.esm.min.mjs")).default;
    for (const n of nodes) {
      if (!n.dataset.src) n.dataset.src = n.textContent;
      n.removeAttribute("data-processed");
      n.textContent = n.dataset.src;
    }
    mermaidLib.initialize({ startOnLoad: false, theme: isDark() ? "dark" : "neutral", fontFamily: "Inter, sans-serif", securityLevel: "strict" });
    await mermaidLib.run({ nodes });
  } catch (err) {
    for (const n of nodes) n.classList.add("plain");
    console.warn("No se pudieron dibujar los diagramas", err);
  }
}

/* ---------------------------------------------------------------- navegación */

function setupNavigation() {
  const links = $$(".toc ul a");
  const byId = Object.fromEntries(links.map((a) => [a.getAttribute("href").slice(1), a]));
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        links.forEach((a) => a.classList.remove("active"));
        const link = byId[entry.target.id];
        if (link) {
          link.classList.add("active");
          link.scrollIntoView({ block: "nearest" });
        }
      }
    }
  }, { rootMargin: "-20% 0px -70% 0px" });
  $$("section.topic[id]").forEach((s) => observer.observe(s));

  const progress = $("#progress");
  const onScroll = () => {
    const max = document.documentElement.scrollHeight - innerHeight;
    progress.style.transform = `scaleX(${max > 0 ? scrollY / max : 0})`;
  };
  addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  $("#menu-btn").addEventListener("click", () => document.body.classList.toggle("menu-open"));
  $$(".sidebar a").forEach((a) => a.addEventListener("click", () => document.body.classList.remove("menu-open")));

  const reveal = new IntersectionObserver((entries) => {
    for (const entry of entries) if (entry.isIntersecting) { entry.target.classList.add("seen"); reveal.unobserve(entry.target); }
  }, { rootMargin: "0px 0px -8% 0px" });
  $$(".card, .demo, .callout, .table-wrap").forEach((n) => { n.classList.add("reveal"); reveal.observe(n); });
}

function setupTheme() {
  const saved = storage.get("theme");
  if (saved === "light" || saved === "dark") document.documentElement.dataset.theme = saved;
  const btn = $("#theme-btn");
  const label = () => (btn.textContent = isDark() ? "☀️ Claro" : "🌙 Oscuro");
  label();
  btn.addEventListener("click", () => {
    const next = isDark() ? "light" : "dark";
    document.documentElement.dataset.theme = next;
    storage.set("theme", next);
    label();
    renderDiagrams();
  });
}

function fillStats() {
  for (const n of $$("[data-stat]")) {
    const key = n.dataset.stat;
    if (key === "genes") n.textContent = DATA.Slots.reduce((a, s) => a + DATA.Genes[s].length, 0);
    if (key === "rarities") n.textContent = RARITIES.length;
    if (key === "round") n.textContent = Math.round(PHASES.reduce((a, p) => a + CFG.Round[p.key], 0) / 60);
    if (key === "players") n.textContent = CFG.Matchmaking ? CFG.Matchmaking.MaxPlayers : CFG.Round.MaxPlayers;
  }
  for (const n of $$("[data-cfg]")) {
    const value = n.dataset.cfg.split(".").reduce((o, k) => (o == null ? o : o[k]), CFG);
    n.textContent = typeof value === "number" ? value.toLocaleString("es-ES") : String(value);
  }
}

document.addEventListener("DOMContentLoaded", () => {
  setupTheme();
  enhanceCode();
  buildTree();
  fillStats();
  for (const node of $$("[data-demo]")) {
    try {
      DEMOS[node.dataset.demo](node);
    } catch (err) {
      console.error("Demo", node.dataset.demo, err);
    }
  }
  setupNavigation();
  renderDiagrams();
});
