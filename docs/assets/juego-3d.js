/* El parkour de la arena en 3D, con las medidas reales de ArenaLayout (exportadas a #game-data):
   árboles, plataformas octogonales, rampas, puentes, vigas, piedras, tirolinas, toboganes,
   setas trampolín y las brasas por niveles. Arrastrar gira; rueda o pellizco acerca. */
(function () {
  "use strict";
  var E = window.EGG, wrap = document.getElementById("map3d"), canvas = document.getElementById("map3d-canvas");
  if (!E || !wrap || !canvas) return;
  if (!window.THREE) { wrap.innerHTML = '<div class="fallback">No se ha podido cargar three.js (la librería 3D). Prueba a recargar la página.</div>'; return; }
  var T = window.THREE, A = E.D.Arena || {}, trees = A.Trees || [];
  var DW = A.DeckWidth || 5.5, SIDES = A.DeckSides || 8, MID = A.MidHeight || 66;

  var renderer;
  try { renderer = new T.WebGLRenderer({ canvas: canvas, antialias: true, alpha: true }); }
  catch (e) { wrap.innerHTML = '<div class="fallback">Tu navegador no puede dibujar 3D (WebGL).</div>'; return; }
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  var scene = new T.Scene();
  scene.fog = new T.Fog(0xcfe8ff, 380, 760);
  var camera = new T.PerspectiveCamera(45, 1, 1, 2000);
  scene.add(new T.HemisphereLight(0xffffff, 0x4a6b3a, 0.85));
  var sun = new T.DirectionalLight(0xffffff, 0.75); sun.position.set(120, 260, 80); scene.add(sun);

  function mat(color, opts) { var m = new T.MeshStandardMaterial(Object.assign({ color: color, roughness: 0.8 }, opts || {})); return m; }
  var M = {
    ground: mat(0x6fae5f), clearing: mat(0xe8d9a0), trunk: mat(0x7a4a28), deck: mat(0xc98f55), leaves: mat(0x3f8f45, { roughness: 1 }),
    rope: mat(0x5b4630), stone: mat(0x9a9aa2), beam: mat(0x8a6a48), egg: mat(0xffe7c4, { emissive: 0xff8a2a, emissiveIntensity: 0.12 }),
    ped: mat(0x5a4637), slide: mat(0x4dabf7), shroom: mat(0xe0464d), stem: mat(0xf1e3c8), hut: mat(0x9b6a3d), ramp: mat(0xb07c4a),
  };
  var groups = {};
  function group(name) { var g = new T.Group(); g.name = name; scene.add(g); groups[name] = g; return g; }
  var world = group("world"), gEmbers = group("embers"), gBlue = group("blue"), gPurple = group("purple"), gLinks = group("links"), gRides = group("rides"), gShrooms = group("shrooms");

  // Suelo y claro
  var ground = new T.Mesh(new T.CylinderGeometry(155, 155, 2, 64), M.ground); ground.position.y = -1; world.add(ground);
  var clear = new T.Mesh(new T.CylinderGeometry(25, 25, 0.3, 48), M.clearing); clear.position.y = 0.1; world.add(clear);
  var ped = new T.Mesh(new T.CylinderGeometry(11, 11, 3, 32), M.ped); ped.position.y = 1.5; world.add(ped);
  var egg = new T.Mesh(new T.SphereGeometry(1, 32, 24), M.egg); egg.scale.set(7, 9, 7); egg.position.y = 12; world.add(egg);

  // Árboles
  var deckGeo = function (half) { var g = new T.CylinderGeometry(half / Math.cos(Math.PI / SIDES), half / Math.cos(Math.PI / SIDES), 1, SIDES); g.rotateY(Math.PI / SIDES); return g; };
  trees.forEach(function (t) {
    var top = t.Decks[t.Decks.length - 1];
    var trunk = new T.Mesh(new T.CylinderGeometry(t.Radius * 0.85, t.Radius, top + 14, 14), M.trunk);
    trunk.position.set(t.X, (top + 14) / 2, t.Z); world.add(trunk);
    var crown = new T.Mesh(new T.SphereGeometry(t.Radius + DW + 6, 14, 10), M.leaves);
    crown.scale.y = 0.55; crown.position.set(t.X, top + 18, t.Z); world.add(crown);
    t.Decks.forEach(function (lv) {
      var d = new T.Mesh(deckGeo(t.Half || t.Radius + DW), M.deck); d.position.set(t.X, lv, t.Z); world.add(d);
    });
    if (t.HutLevel) {
      var hut = new T.Mesh(new T.BoxGeometry(7, 6, 7), M.hut), a = Math.atan2(t.Z, t.X) + Math.PI;
      hut.position.set(t.X + Math.cos(a) * (t.Radius + DW / 2), t.HutLevel + 3.5, t.Z + Math.sin(a) * (t.Radius + DW / 2)); world.add(hut);
    }
    if (t.Ramp) {
      // Rampa en espiral alrededor de la plataforma (como un tubo, para que se vea la subida).
      var pts = [], r = (t.Half || t.Radius + DW) + 3, turns = top / 26;
      for (var i = 0; i <= 120; i++) { var f = i / 120, ang = f * turns * Math.PI * 2; pts.push(new T.Vector3(t.X + Math.cos(ang) * r, f * top, t.Z + Math.sin(ang) * r)); }
      var ramp = new T.Mesh(new T.TubeGeometry(new T.CatmullRomCurve3(pts), 240, 1.1, 5, false), M.ramp); world.add(ramp);
    } else {
      var ladder = new T.Mesh(new T.BoxGeometry(2, top + 4, 0.6), M.beam), la = Math.atan2(-t.Z, -t.X);
      var lr = (t.Half || t.Radius + DW) + 0.5;
      ladder.position.set(t.X + Math.cos(la) * lr, (top + 4) / 2, t.Z + Math.sin(la) * lr); ladder.lookAt(t.X, (top + 4) / 2, t.Z); world.add(ladder);
    }
  });

  // Puentes, vigas y piedras
  (A.Links || []).forEach(function (l) {
    var a = new T.Vector3(l.From[0], l.Level, l.From[1]), b = new T.Vector3(l.To[0], l.Level, l.To[1]), len = a.distanceTo(b), midp = a.clone().lerp(b, 0.5);
    if (l.Kind === "Stones") {
      var n = Math.max(2, Math.round(len / 6));
      for (var i = 1; i < n; i++) { var p = a.clone().lerp(b, i / n), s = new T.Mesh(new T.CylinderGeometry(1.8, 1.8, 0.8, 8), M.stone); s.position.copy(p); s.position.y += Math.sin(i) * 1.5; gLinks.add(s); }
      return;
    }
    var w = l.Kind === "Beam" ? 1.2 : 4;
    var plank = new T.Mesh(new T.BoxGeometry(w, 0.6, len), l.Kind === "Beam" ? M.beam : M.deck);
    plank.position.copy(midp); plank.lookAt(b); gLinks.add(plank);
    if (l.Kind === "Bridge") [-1, 1].forEach(function (side) {
      var rope = new T.Mesh(new T.BoxGeometry(0.25, 0.25, len), M.rope); rope.position.copy(midp); rope.lookAt(b);
      rope.translateX(side * w / 2); rope.position.y += 2.2; gLinks.add(rope);
    });
  });

  // Tirolinas y toboganes
  (A.Rides || []).forEach(function (r) {
    var a = new T.Vector3(r.From[0], r.From[2] || 100, r.From[1]), b = new T.Vector3(r.To[0], r.To[2] || 0, r.To[1]);
    if (r.Kind === "Zipline") {
      var len = a.distanceTo(b), cable = new T.Mesh(new T.CylinderGeometry(0.25, 0.25, len, 6), mat(0x222222));
      cable.position.copy(a.clone().lerp(b, 0.5)); cable.lookAt(b); cable.rotateX(Math.PI / 2); gRides.add(cable);
      var pole = new T.Mesh(new T.CylinderGeometry(0.5, 0.5, 6, 8), M.beam); pole.position.copy(a); pole.position.y -= 1; gRides.add(pole);
    } else {
      var c = new T.CatmullRomCurve3([a, a.clone().lerp(b, 0.35).add(new T.Vector3(0, -a.y * 0.15, 6)), a.clone().lerp(b, 0.7).add(new T.Vector3(0, -a.y * 0.1, -6)), b]);
      gRides.add(new T.Mesh(new T.TubeGeometry(c, 80, 2, 8, false), M.slide));
    }
  });

  // Setas trampolín
  (A.Trampolines || []).forEach(function (p) {
    var stem = new T.Mesh(new T.CylinderGeometry(0.9, 1.1, 2.5, 10), M.stem); stem.position.set(p[0], (p[2] || 0) + 1.2, p[1]); gShrooms.add(stem);
    var cap = new T.Mesh(new T.SphereGeometry(3, 16, 10, 0, Math.PI * 2, 0, Math.PI / 2), M.shroom); cap.position.set(p[0], (p[2] || 0) + 2.4, p[1]); gShrooms.add(cap);
  });

  // Brasas por niveles
  var floaters = [];
  function ember(group, color, x, y, z, size) {
    var m = new T.Mesh(new T.SphereGeometry(size, 12, 8), new T.MeshStandardMaterial({ color: color, emissive: color, emissiveIntensity: 0.9 }));
    m.position.set(x, y + 1.6, z); m.userData.base = y + 1.6; m.userData.ph = Math.random() * 6; group.add(m); floaters.push(m);
  }
  var spots = { low: [], mid: [], top: [] };
  trees.forEach(function (t) {
    var top = t.Decks[t.Decks.length - 1], mr = t.Radius + DW / 2;
    t.Decks.forEach(function (lv) {
      var list = lv === top ? spots.top : lv >= MID ? spots.mid : spots.low;
      for (var k = 0; k < SIDES; k++) { var a = k * 2 * Math.PI / SIDES; list.push([t.X + Math.cos(a) * mr, lv, t.Z + Math.sin(a) * mr]); }
    });
  });
  function pick(list) { return list[Math.floor(Math.random() * list.length)]; }
  var H = E.C.Heat || {};
  var onTrees = (E.C.Arena && E.C.Arena.EmbersOnTrees) || 0.45;
  for (var i = 0; i < (H.Ember ? H.Ember.Count : 70); i++) {
    if (Math.random() < onTrees) { var s = pick(spots.low); ember(gEmbers, 0xff8a2a, s[0], s[1], s[2], 1); }
    else { var a = Math.random() * Math.PI * 2, r = 28 + Math.random() * 82; ember(gEmbers, 0xff8a2a, Math.cos(a) * r, 0, Math.sin(a) * r, 1); }
  }
  for (i = 0; i < (H.BlueEmber ? H.BlueEmber.Count : 0); i++) { s = pick(spots.mid); ember(gBlue, 0x3b9cff, s[0], s[1], s[2], 1.3); }
  for (i = 0; i < (H.PurpleEmber ? H.PurpleEmber.Count : 0); i++) { s = pick(spots.top); ember(gPurple, 0xb04dff, s[0], s[1], s[2], 1.6); }

  // Leyenda con capas
  var legend = document.getElementById("map3d-legend");
  [["embers", "🟠 Brasas naranjas"], ["blue", "🔵 Azules"], ["purple", "🟣 Moradas"], ["links", "🌉 Puentes"], ["rides", "🚡 Tirolinas y toboganes"], ["shrooms", "🍄 Setas"], ["spin", "🔄 Girar solo"]].forEach(function (l) {
    var b = document.createElement("button"); b.type = "button"; b.textContent = l[1];
    b.addEventListener("click", function () {
      if (l[0] === "spin") { auto = !auto; b.classList.toggle("off", !auto); return; }
      groups[l[0]].visible = !groups[l[0]].visible; b.classList.toggle("off", !groups[l[0]].visible);
    });
    legend.appendChild(b);
  });

  // Cámara orbital
  var yaw = 0.6, pitch = 0.62, radius = 330, target = new T.Vector3(0, 45, 0), auto = !E.reduced, dragging = null, pinch = 0;
  function place() {
    pitch = Math.max(0.08, Math.min(1.45, pitch)); radius = Math.max(70, Math.min(620, radius));
    camera.position.set(target.x + Math.cos(yaw) * Math.cos(pitch) * radius, target.y + Math.sin(pitch) * radius, target.z + Math.sin(yaw) * Math.cos(pitch) * radius);
    camera.lookAt(target);
  }
  var pointers = {};
  canvas.addEventListener("pointerdown", function (e) { canvas.setPointerCapture(e.pointerId); pointers[e.pointerId] = { x: e.clientX, y: e.clientY }; dragging = true; auto = false; canvas.style.cursor = "grabbing"; });
  canvas.addEventListener("pointermove", function (e) {
    var p = pointers[e.pointerId]; if (!p) return;
    var ids = Object.keys(pointers);
    if (ids.length === 2) {
      var o = pointers[ids[0] == e.pointerId ? ids[1] : ids[0]];
      var d = Math.hypot(e.clientX - o.x, e.clientY - o.y);
      if (pinch) radius *= pinch / d;
      pinch = d;
    } else {
      yaw += (e.clientX - p.x) * 0.006; pitch += (e.clientY - p.y) * 0.005;
    }
    p.x = e.clientX; p.y = e.clientY;
  });
  function up(e) { delete pointers[e.pointerId]; pinch = 0; if (!Object.keys(pointers).length) { dragging = null; canvas.style.cursor = ""; } }
  canvas.addEventListener("pointerup", up); canvas.addEventListener("pointercancel", up);
  canvas.addEventListener("wheel", function (e) { e.preventDefault(); radius *= 1 + Math.sign(e.deltaY) * 0.08; auto = false; }, { passive: false });

  function theme() {
    var dark = document.documentElement.dataset.theme ? document.documentElement.dataset.theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
    scene.fog.color.set(dark ? 0x232845 : 0xcfe8ff);
  }
  document.addEventListener("themechange", theme); theme();

  function resize() {
    var w = canvas.clientWidth, h = canvas.clientHeight;
    if (canvas.width !== Math.floor(w * renderer.getPixelRatio()) || canvas.height !== Math.floor(h * renderer.getPixelRatio())) { renderer.setSize(w, h, false); camera.aspect = w / h; camera.updateProjectionMatrix(); }
  }
  var visible = true;
  if ("IntersectionObserver" in window) new IntersectionObserver(function (es) { visible = es[0].isIntersecting; }, { rootMargin: "100px" }).observe(canvas);
  var last = performance.now();
  (function loop(now) {
    var dt = (now - last) / 1000; last = now;
    if (visible) {
      resize();
      if (auto && !dragging) yaw += dt * 0.12;
      var t = now / 1000;
      floaters.forEach(function (m) { m.position.y = m.userData.base + Math.sin(t * 2 + m.userData.ph) * 0.5; });
      egg.scale.setScalar(1); egg.scale.set(7, 9, 7).multiplyScalar(1 + Math.max(0, Math.sin(t * 3)) ** 6 * 0.05);
      place();
      renderer.render(scene, camera);
    }
    requestAnimationFrame(loop);
  })(last);
})();
