/* The Egg Chooses · informe del simulador de bots.
 * Los datos (<script id="sim-data">) los genera tools/sim_report.py ejecutando sim/run.luau
 * con la configuración anterior y la actual del juego. */

const SIM = JSON.parse(document.getElementById("sim-data").textContent);

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
const el = (tag, props = {}, children = []) => {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === "class") node.className = v;
    else if (k === "html") node.innerHTML = v;
    else if (k === "style") node.style.cssText = v;
    else if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
    else node.setAttribute(k, v);
  }
  for (const c of [].concat(children)) if (c != null) node.append(c.nodeType ? c : document.createTextNode(c));
  return node;
};
const NS = "http://www.w3.org/2000/svg";
const svg = (tag, attrs = {}, parent) => {
  const n = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, v);
  if (parent) parent.append(n);
  return n;
};
const dec = (n, d = 1) => n.toFixed(d).replace(".", ",");
const pct = (p, d = 0) => `${dec(p * 100, d)} %`;
const big = (n) => {
  const a = Math.abs(n);
  if (a >= 1e9) return dec(n / 1e9, 1) + " mil M";
  if (a >= 1e6) return dec(n / 1e6, 1) + " M";
  if (a >= 1e4) return dec(n / 1e3, 0) + " k";
  return Math.round(n).toLocaleString("es-ES");
};

const ARCH = {
  Newbie: { label: "Novato", color: "#8f97a3" },
  Casual: { label: "Casual", color: "#4c9be8" },
  Collector: { label: "Recolector", color: "#2fa85a" },
  Thief: { label: "Ladrón", color: "#e0464d" },
  Grinder: { label: "Fiel", color: "#7b5cff" },
  Payer: { label: "Con pases", color: "#e8a400" },
};
const VARIANT = { before: "Antes", after: "Después" };
const VCOLOR = { before: "#a79cb3", after: "#ff8a2a" };

/* ---------------------------------------------------------------- tarjetas resumen */

function kpis() {
  const root = $("#kpis");
  if (!root) return;
  const b = SIM.Chase.before["12"], a = SIM.Chase.after["12"];
  const items = [
    ["La criatura se escapa", b.Escape, a.Escape, pct, false],
    ["Gana el elegido", b.ChosenWins, a.ChosenWins, pct, true],
    ["Robos por partida", b.Steals, a.Steals, (v) => dec(v, 1), false],
    ["Barra al eclosionar", b.Bar, a.Bar, pct, null],
    ["Barra llena antes de tiempo", b.EarlyFull, a.EarlyFull, pct, false],
    ["Persecución media", b.ChaseSeconds, a.ChaseSeconds, (v) => `${Math.round(v)} s`, null],
  ];
  for (const [label, before, after, f, higherIsBetter] of items) {
    let cls = "";
    if (higherIsBetter !== null) cls = (after > before) === higherIsBetter ? "good" : "bad";
    root.append(
      el("div", { class: "card kpi" }, [
        el("div", { class: "kpi-label" }, label),
        el("div", { class: "kpi-values" }, [el("span", { class: "kpi-before" }, f(before)), el("span", { class: "kpi-arrow" }, "→"), el("b", { class: `kpi-after ${cls}` }, f(after))]),
      ]),
    );
  }
}

/* ---------------------------------------------------------------- gráficas SVG */

function axisColor() {
  return getComputedStyle(document.documentElement).getPropertyValue("--muted").trim() || "#888";
}

// Barras agrupadas: categories en X, una barra por serie.
function groupedBars(container, { categories, series, format = (v) => v, max }) {
  container.innerHTML = "";
  const W = 640, H = 260, L = 46, B = 34, T = 16;
  const s = svg("svg", { viewBox: `0 0 ${W} ${H}`, class: "chart" }, container);
  const top = max ?? Math.max(...series.flatMap((x) => x.values), 1e-9) * 1.15;
  const plotW = W - L - 10, plotH = H - B - T;
  const color = axisColor();
  for (let i = 0; i <= 4; i++) {
    const y = T + plotH - (plotH * i) / 4;
    svg("line", { x1: L, x2: W - 10, y1: y, y2: y, stroke: color, "stroke-opacity": 0.25 }, s);
    svg("text", { x: L - 6, y: y + 4, "text-anchor": "end", "font-size": 11, fill: color }, s).textContent = format((top * i) / 4);
  }
  const groupW = plotW / categories.length;
  const barW = Math.min(34, (groupW * 0.7) / series.length);
  categories.forEach((cat, ci) => {
    const gx = L + ci * groupW + groupW / 2;
    svg("text", { x: gx, y: H - 12, "text-anchor": "middle", "font-size": 12, fill: color }, s).textContent = cat;
    series.forEach((ser, si) => {
      const v = ser.values[ci];
      const h = (plotH * v) / top;
      const x = gx - (series.length * barW) / 2 + si * barW;
      const rect = svg("rect", { x: x + 2, y: T + plotH - h, width: barW - 4, height: Math.max(h, 0.5), rx: 4, fill: ser.color }, s);
      svg("title", {}, rect).textContent = `${ser.name} · ${cat}: ${format(v)}`;
      if (h > 16) svg("text", { x: x + barW / 2, y: T + plotH - h - 4, "text-anchor": "middle", "font-size": 10, fill: color }, s).textContent = format(v);
    });
  });
  legend(container, series);
}

function legend(container, series) {
  const box = el("div", { class: "legend" });
  for (const ser of series) box.append(el("span", {}, [el("i", { style: `background:${ser.color}` }), ser.name]));
  container.append(box);
}

// Líneas: x = días; cada serie { name, color, values }.
function lineChart(container, { xs, series, format = (v) => v, log = false }) {
  container.innerHTML = "";
  const W = 640, H = 280, L = 58, B = 30, T = 14, R = 12;
  const s = svg("svg", { viewBox: `0 0 ${W} ${H}`, class: "chart" }, container);
  const all = series.flatMap((x) => x.values).filter((v) => !log || v > 0);
  let lo = log ? Math.max(Math.min(...all), 1) : 0;
  let hi = Math.max(...all, 1e-9);
  const tf = (v) => (log ? Math.log10(Math.max(v, lo)) : v);
  const a = tf(lo), b = tf(hi) + (log ? 0.1 : (tf(hi) - a) * 0.08);
  const plotW = W - L - R, plotH = H - B - T;
  const X = (i) => L + (plotW * (xs[i] - xs[0])) / Math.max(xs[xs.length - 1] - xs[0], 1);
  const Y = (v) => T + plotH - (plotH * (tf(v) - a)) / Math.max(b - a, 1e-9);
  const color = axisColor();
  for (let i = 0; i <= 4; i++) {
    const tv = a + ((b - a) * i) / 4;
    const v = log ? Math.pow(10, tv) : tv;
    const y = T + plotH - (plotH * i) / 4;
    svg("line", { x1: L, x2: W - R, y1: y, y2: y, stroke: color, "stroke-opacity": 0.22 }, s);
    svg("text", { x: L - 6, y: y + 4, "text-anchor": "end", "font-size": 11, fill: color }, s).textContent = format(v);
  }
  for (const d of [1, 7, 14, 21, 30]) {
    const i = xs.indexOf(d);
    if (i < 0) continue;
    const anchor = i === xs.length - 1 ? "end" : i === 0 ? "start" : "middle";
    svg("text", { x: X(i), y: H - 10, "text-anchor": anchor, "font-size": 11, fill: color }, s).textContent = `día ${d}`;
  }
  for (const ser of series) {
    const pts = ser.values.map((v, i) => `${X(i).toFixed(1)},${Y(v).toFixed(1)}`).join(" ");
    const line = svg("polyline", { points: pts, fill: "none", stroke: ser.color, "stroke-width": ser.width || 2.5, "stroke-linejoin": "round", "stroke-dasharray": ser.dash || "" }, s);
    svg("title", {}, line).textContent = `${ser.name}: ${format(ser.values[ser.values.length - 1])} el último día`;
  }
  legend(container, series);
}

// Barras apiladas al 100 %: una fila por categoría.
function stackedRows(container, rows, keys, colors) {
  container.innerHTML = "";
  for (const row of rows) {
    const total = keys.reduce((acc, k) => acc + (row.values[k] || 0), 0) || 1;
    const bar = el("div", { class: "stack" });
    for (const k of keys) {
      const v = (row.values[k] || 0) / total;
      if (v <= 0) continue;
      bar.append(el("div", { class: "stack-seg", title: `${k}: ${pct(v)}`, style: `flex:${v};background:${colors[k]}` }, v > 0.08 ? pct(v) : ""));
    }
    container.append(el("div", { class: "stack-row" }, [el("span", {}, row.label), bar]));
  }
  const box = el("div", { class: "legend" });
  for (const k of keys) box.append(el("span", {}, [el("i", { style: `background:${colors[k]}` }), k]));
  container.append(box);
}

/* ---------------------------------------------------------------- persecución */

function chaseCharts() {
  const sizes = SIM.Sizes.map(String);
  const cats = sizes.map((s) => `${s} jugadores`);
  const both = (field) => ["before", "after"].map((v) => ({ name: VARIANT[v], color: VCOLOR[v], values: sizes.map((s) => SIM.Chase[v][s][field]) }));
  groupedBars($("#chart-escape"), { categories: cats, series: both("Escape"), format: (v) => pct(v), max: 1 });
  groupedBars($("#chart-chosen"), { categories: cats, series: both("ChosenWins"), format: (v) => pct(v) });
  groupedBars($("#chart-steals"), { categories: cats, series: both("Steals"), format: (v) => dec(v, 0) });

  const endColors = { Asegurada: "#2fa85a", Prórroga: "#7b5cff", "Al acabar el tiempo": "#4c9be8", Fuga: "#e0464d" };
  const rows = [];
  for (const v of ["before", "after"]) {
    for (const s of sizes) rows.push({ label: `${VARIANT[v]} · ${s} jug.`, values: SIM.Chase[v][s].Ends });
  }
  stackedRows($("#chart-ends"), rows, Object.keys(endColors), endColors);

  // Histograma de robos (12 jugadores).
  const h = $("#chart-steals-hist");
  const series = ["before", "after"].map((v) => {
    const counts = SIM.Chase[v]["12"].StealsHistogram;
    const total = counts.reduce((x, y) => x + y, 0) || 1;
    return { name: VARIANT[v], color: VCOLOR[v], values: counts.map((c) => c / total) };
  });
  const xs = series[0].values.map((_, i) => i);
  lineChartSimple(h, xs, series);
}

function lineChartSimple(container, xs, series) {
  container.innerHTML = "";
  const W = 640, H = 220, L = 46, B = 30, T = 10;
  const s = svg("svg", { viewBox: `0 0 ${W} ${H}`, class: "chart" }, container);
  const top = Math.max(...series.flatMap((x) => x.values)) * 1.1 || 1;
  const plotW = W - L - 10, plotH = H - B - T;
  const color = axisColor();
  const X = (i) => L + (plotW * i) / (xs.length - 1);
  for (let i = 0; i <= 4; i++) {
    const y = T + plotH - (plotH * i) / 4;
    svg("line", { x1: L, x2: W - 10, y1: y, y2: y, stroke: color, "stroke-opacity": 0.22 }, s);
    svg("text", { x: L - 6, y: y + 4, "text-anchor": "end", "font-size": 11, fill: color }, s).textContent = pct((top * i) / 4);
  }
  for (const d of [0, 5, 10, 15, 20, 25, 30]) svg("text", { x: X(d), y: H - 10, "text-anchor": "middle", "font-size": 11, fill: color }, s).textContent = d === 30 ? "30+" : d;
  for (const ser of series) {
    const pts = ser.values.map((v, i) => `${X(i)},${T + plotH - (plotH * v) / top}`).join(" ");
    svg("polyline", { points: `${X(0)},${T + plotH} ${pts} ${X(xs.length - 1)},${T + plotH}`, fill: ser.color, "fill-opacity": 0.18, stroke: ser.color, "stroke-width": 2 }, s);
  }
  legend(container, series);
}

/* ---------------------------------------------------------------- barra del huevo */

function barCharts() {
  const sizes = SIM.Sizes.map(String);
  const cats = sizes.map((s) => `${s} jugadores`);
  const series = ["before", "after"].map((v) => ({ name: VARIANT[v], color: VCOLOR[v], values: sizes.map((s) => SIM.Chase[v][s].Bar) }));
  groupedBars($("#chart-bar"), { categories: cats, series, format: (v) => pct(v), max: 1 });
  const rarColors = { Common: "#aaaaaa", Rare: "#55c85f", Epic: "#468cff" };
  const names = { Common: "Común", Rare: "Rara", Epic: "Épica" };
  const rows = [];
  for (const v of ["before", "after"]) for (const s of sizes) rows.push({ label: `${VARIANT[v]} · ${s} jug.`, values: Object.fromEntries(Object.entries(SIM.Chase[v][s].MinRarity).map(([k, n]) => [names[k], n])) });
  stackedRows($("#chart-minrarity"), rows, ["Común", "Rara", "Épica"], { Común: rarColors.Common, Rara: rarColors.Rare, Épica: rarColors.Epic });
}

/* ---------------------------------------------------------------- economía */

const METRICS = {
  CoinsMedian: { label: "Monedas guardadas (mediana)", format: big, log: true },
  Income: { label: "Producción del nido (Monedas/s)", format: (v) => big(v), log: true },
  NestLevel: { label: "Nivel del nido (máx. 17)", format: (v) => dec(v, 0) },
  BagLevel: { label: "Nivel de la bolsa (máx. 9)", format: (v) => dec(v, 0) },
  Generation: { label: "Generación (Nueva generación)", format: (v) => dec(v, 1) },
  Creatures: { label: "Criaturas por jugador", format: (v) => dec(v, 0) },
  WinnersShare: { label: "Han ganado al menos una persecución", format: (v) => pct(v) },
  ChosenShare: { label: "Han sido elegidos al menos una vez", format: (v) => pct(v) },
};

let renderEconomy = () => {};

function economy() {
  const root = $("#economy");
  if (!root) return;
  const metricSel = $("select[name=metric]", root);
  const variantSel = $("select[name=variant]", root);
  for (const [k, m] of Object.entries(METRICS)) metricSel.append(el("option", { value: k }, m.label));
  function render() {
    const m = METRICS[metricSel.value];
    const v = variantSel.value;
    const daily = SIM.Meta[v].Daily;
    const xs = daily.map((d) => d.Day);
    let series;
    if (v === "both") {
      series = [];
      for (const vv of ["before", "after"]) {
        for (const arch of ["Casual", "Grinder"]) {
          series.push({
            name: `${ARCH[arch].label} · ${VARIANT[vv]}`,
            color: ARCH[arch].color,
            dash: vv === "before" ? "5 4" : "",
            values: SIM.Meta[vv].Daily.map((d) => d.ByArch[arch]?.[metricSel.value] ?? 0),
          });
        }
      }
    } else {
      series = SIM.Archs.map((arch) => ({ name: ARCH[arch].label, color: ARCH[arch].color, values: daily.map((d) => d.ByArch[arch]?.[metricSel.value] ?? 0) }));
    }
    lineChart($(".chart-box", root), { xs: v === "both" ? SIM.Meta.after.Daily.map((d) => d.Day) : xs, series, format: m.format, log: !!m.log });
  }
  variantSel.append(el("option", { value: "after" }, "Después (valores actuales)"));
  variantSel.append(el("option", { value: "before" }, "Antes (valores originales)"));
  variantSel.append(el("option", { value: "both" }, "Comparar Casual y Fiel"));
  metricSel.addEventListener("change", render);
  variantSel.addEventListener("change", render);
  renderEconomy = render;
  render();
}

function milestones() {
  const table = $("#milestones");
  if (!table) return;
  const firstDay = (daily, arch, test) => {
    for (const d of daily) if (d.ByArch[arch] && test(d.ByArch[arch])) return d.Day;
    return null;
  };
  const cell = (day) => (day == null ? `<span class="muted">más de ${SIM.Params.Days}</span>` : `día ${day}`);
  let html = "<tr><th>Tipo de jugador</th><th>Nido a nivel 10</th><th>Bolsa al máximo</th><th>Primera Nueva generación</th></tr>";
  for (const arch of SIM.Archs) {
    const row = ["before", "after"].map((v) => {
      const daily = SIM.Meta[v].Daily;
      return [
        firstDay(daily, arch, (x) => x.NestLevel >= 10),
        firstDay(daily, arch, (x) => x.BagLevel >= 8.5),
        firstDay(daily, arch, (x) => x.Generation >= 1),
      ];
    });
    html += `<tr><td><i class="dot" style="background:${ARCH[arch].color}"></i>${ARCH[arch].label}</td>`;
    for (let i = 0; i < 3; i++) html += `<td>${cell(row[0][i])} → <b>${cell(row[1][i])}</b></td>`;
    html += "</tr>";
  }
  table.innerHTML = html;
}

function retention() {
  const table = $("#retention");
  if (!table) return;
  const at = (v, day, arch, field) => {
    const d = SIM.Meta[v].Daily[Math.min(day, SIM.Meta[v].Daily.length) - 1];
    return d?.ByArch[arch]?.[field] ?? 0;
  };
  const last = SIM.Params.Days;
  let html = `<tr><th>Tipo de jugador</th><th>Elegido al menos 1 vez (día 7)</th><th>Ha ganado alguna vez (día 7)</th><th>Elegido (día ${last})</th><th>Ha ganado (día ${last})</th></tr>`;
  for (const arch of SIM.Archs) {
    html += `<tr><td><i class="dot" style="background:${ARCH[arch].color}"></i>${ARCH[arch].label}</td>`;
    for (const [day, field] of [[7, "ChosenShare"], [7, "WinnersShare"], [last, "ChosenShare"], [last, "WinnersShare"]]) {
      const b = at("before", day, arch, field), a = at("after", day, arch, field);
      const cls = a > b + 0.001 ? "good" : a < b - 0.001 ? "bad" : "";
      html += `<td>${pct(b)} → <b class="${cls}">${pct(a)}</b></td>`;
    }
    html += "</tr>";
  }
  table.innerHTML = html;
}

function changesTable() {
  const table = $("#changes");
  if (!table) return;
  let html = "<tr><th>Ajuste en Config</th><th>Antes</th><th>Ahora</th><th>Por qué</th></tr>";
  for (const c of SIM.Changes) {
    const f = (v) => (typeof v === "number" ? v.toLocaleString("es-ES") : String(v));
    html += `<tr><td><code>${c.Path}</code></td><td>${f(c.Before)}</td><td><b>${f(c.After)}</b></td><td>${c.Why}</td></tr>`;
  }
  table.innerHTML = html;
}

/* ---------------------------------------------------------------- repetición */

function replay() {
  const root = $("#replay");
  const data = SIM.Replay;
  if (!root || !data) return;
  const map = $("svg", root);
  const R = 150, nestR = 128, nestSize = 26, count = 16;
  const add = (tag, attrs, parent = map) => svg(tag, attrs, parent);
  add("circle", { cx: 0, cy: 0, r: R + 10, fill: "#46573a" });
  const zones = { 45: "#3c5a46", 135: "#5aa7c8", 225: "#a8a396", 315: "#8a6a4a" };
  for (const [deg, color] of Object.entries(zones)) {
    const a = (deg * Math.PI) / 180;
    add("circle", { cx: Math.cos(a) * 82, cy: Math.sin(a) * 82, r: 23, fill: color, opacity: 0.75 });
  }
  for (let i = 1; i <= 4; i++) {
    const a = (i / 4) * Math.PI * 2 + Math.PI / 4;
    add("circle", { cx: Math.cos(a) * 58, cy: Math.sin(a) * 58, r: 4.5, fill: "#5a9fc8", stroke: "#fff" });
  }
  add("circle", { cx: 0, cy: 0, r: 25, fill: "#78644a" });
  const eggShape = add("ellipse", { cx: 0, cy: 0, rx: 7, ry: 9, fill: "#fff0d2", stroke: "#ff9a40", "stroke-width": 2 });
  const ownerOfNest = {};
  for (const n of data.Nests) ownerOfNest[n.Nest] = n;
  for (let i = 1; i <= count; i++) {
    const a = (i / count) * Math.PI * 2;
    const deg = (a * 180) / Math.PI;
    const owner = ownerOfNest[i];
    const g = add("g", { transform: `translate(${Math.cos(a) * nestR} ${Math.sin(a) * nestR}) rotate(${deg + 90})` });
    add("rect", { x: -nestSize / 2, y: -nestSize / 2, width: nestSize, height: nestSize, fill: owner ? "#b48c5a" : "#6b5a46", stroke: owner ? ARCH[owner.Arch].color : "#4a3d30", "stroke-width": owner ? 2.5 : 1 }, g);
    add("rect", { x: -4.5, y: nestSize / 2 - 1.5, width: 9, height: 3, fill: "#ffd060" }, g);
  }
  // Bots
  const dots = {};
  const indexById = {};
  data.Bots.forEach((b, i) => {
    indexById[String(b.Id)] = i;
    const g = add("g", {});
    const ring = add("circle", { r: 7, fill: "none", stroke: "#ffd23f", "stroke-width": 2.5, opacity: 0 }, g);
    const body = add("circle", { r: 4.2, fill: ARCH[b.Arch].color, stroke: "#fff", "stroke-width": 1.2 }, g);
    const heat = add("circle", { r: 0, fill: "#ff7a1f" }, g);
    svg("title", {}, body).textContent = `${b.Name}`;
    dots[i] = { g, ring, heat, bot: b };
  });
  const frames = data.Frames;
  const phaseStart = {};
  for (const f of frames) if (phaseStart[f.Phase] == null) phaseStart[f.Phase] = f.T;
  const events = data.Log.map((e) => {
    const base = e.Phase === "Persecución" ? phaseStart.Chase ?? 0 : e.Phase === "Eclosión" ? (phaseStart.Hatch ?? 0) - 1 : 0;
    return { ...e, Abs: base + e.T };
  });
  const logBox = $(".replay-log", root);
  events.forEach((e, i) => {
    const item = el("button", { class: "log-item", type: "button" }, [el("span", { class: "muted" }, `${e.Phase} · ${e.T} s`), " ", e.Text]);
    item.addEventListener("click", () => seek(e.Abs));
    e.node = item;
    logBox.append(item);
  });
  const legendBox = $(".replay-legend", root);
  for (const b of data.Bots) legendBox.append(el("span", {}, [el("i", { style: `background:${ARCH[b.Arch].color}` }), b.Name + (b.Won ? " 🏆" : b.Chosen ? " 🥚" : "")]));

  const slider = $("input[type=range]", root);
  const playBtn = $(".play", root);
  const speedSel = $("select", root);
  const info = $(".replay-info", root);
  const tMax = frames[frames.length - 1].T;
  slider.max = String(tMax);
  let t = 0, playing = false, last = 0;
  const PHASES = { Incubation: "🔥 Incubación", Hatch: "🥚 Eclosión", Chase: "🏃 Persecución", Results: "🏆 Resultados" };

  function frameAt(time) {
    let lo = 0, hi = frames.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (frames[mid].T <= time) lo = mid; else hi = mid - 1;
    }
    return lo;
  }
  function draw() {
    const i = frameAt(t);
    const f = frames[i], g = frames[Math.min(i + 1, frames.length - 1)];
    const k = g.T > f.T ? Math.min(Math.max((t - f.T) / (g.T - f.T), 0), 1) : 0;
    f.P.forEach((p, idx) => {
      const q = g.P[idx];
      const x = p[0] + (q[0] - p[0]) * k, z = p[1] + (q[1] - p[1]) * k;
      const d = dots[idx];
      d.g.setAttribute("transform", `translate(${x} ${z})`);
      d.heat.setAttribute("r", String(Math.min(p[2] / 150, 1) * 2.6));
      d.ring.setAttribute("opacity", f.C != null && indexById[String(f.C)] === idx ? "1" : "0");
    });
    const bar = f.Bar || 0;
    eggShape.setAttribute("rx", String(7 + Math.min(bar / 20000, 1) * 3));
    info.innerHTML = `<b>${PHASES[f.Phase] || f.Phase}</b> · ${Math.floor(t)} s · Calor en el huevo: ${big(bar)}`;
    slider.value = String(t);
    let current = null;
    for (const e of events) if (e.Abs <= t + 0.01) current = e;
    for (const e of events) e.node.classList.toggle("on", e === current);
  }
  function seek(time) {
    t = Math.min(Math.max(time, 0), tMax);
    draw();
  }
  function loop(now) {
    if (!playing) return;
    const dt = (now - last) / 1000;
    last = now;
    t += dt * Number(speedSel.value);
    if (t >= tMax) { t = tMax; playing = false; playBtn.textContent = "▶ Reproducir"; }
    draw();
    if (playing) requestAnimationFrame(loop);
  }
  playBtn.addEventListener("click", () => {
    playing = !playing;
    playBtn.textContent = playing ? "⏸ Pausa" : "▶ Reproducir";
    if (playing) {
      if (t >= tMax) t = 0;
      last = performance.now();
      requestAnimationFrame(loop);
    }
  });
  slider.addEventListener("input", () => seek(Number(slider.value)));
  $(".jump-chase", root).addEventListener("click", () => seek(phaseStart.Chase ?? 0));
  const s = data.Summary;
  $(".replay-summary", root).innerHTML = `Semilla ${data.Seed} · 12 bots · ${s.Steals} robos · ${s.Carriers} portadores · ${s.Secured ? "acabó <b>asegurada</b>" : s.Overtime ? "se decidió en la <b>prórroga</b>" : s.Escaped ? "la criatura <b>escapó</b>" : "ganó al acabar el tiempo"}`;
  draw();
}

/* ---------------------------------------------------------------- arranque */

function setupTheme() {
  let saved = null;
  try { saved = localStorage.getItem("theme"); } catch { /* sin almacenamiento */ }
  if (saved === "light" || saved === "dark") document.documentElement.dataset.theme = saved;
  const btn = $("#theme-btn");
  if (!btn) return;
  const isDark = () => (document.documentElement.dataset.theme ? document.documentElement.dataset.theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches);
  const label = () => (btn.textContent = isDark() ? "☀️ Claro" : "🌙 Oscuro");
  label();
  btn.addEventListener("click", () => {
    const next = isDark() ? "light" : "dark";
    document.documentElement.dataset.theme = next;
    try { localStorage.setItem("theme", next); } catch { /* sin almacenamiento */ }
    label();
    renderAll();
  });
}

function renderAll() {
  chaseCharts();
  barCharts();
  renderEconomy();
}

document.addEventListener("DOMContentLoaded", () => {
  if (!SIM.Chase) {
    document.body.prepend(el("p", { class: "callout warn" }, "Faltan los datos: ejecuta python3 tools/sim_report.py"));
    return;
  }
  setupTheme();
  kpis();
  replay();
  chaseCharts();
  barCharts();
  economy();
  milestones();
  retention();
  changesTable();
  $$(".params-rounds").forEach((n) => (n.textContent = SIM.Params.Rounds));
  $$(".params-days").forEach((n) => (n.textContent = SIM.Params.Days));
  $$(".params-pop").forEach((n) => (n.textContent = SIM.Params.Population));
});
