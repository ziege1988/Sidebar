// Rüdigers Bewegungen. Jede Sequenz liefert für eine Zeit t die Pose für rig.js.
// Schleifen (loop: true) laufen im runden Fenster, Gesten (wide: true) ragen aus der Blase heraus.

const clamp = x => Math.min(Math.max(x, 0), 1);
const smooth = x => { const v = clamp(x); return v * v * v * (v * (v * 6 - 15) + 10); };
const easeOut = x => 1 - Math.pow(1 - clamp(x), 3);
const easeIn = x => Math.pow(clamp(x), 3);
const easeOutBack = x => { const v = clamp(x), c1 = 1.5, c3 = c1 + 1; return 1 + c3 * Math.pow(v - 1, 3) + c1 * Math.pow(v - 1, 2); };
const lerp = (a, b, t) => a + (b - a) * t;
const bump = (t, a, b) => (t < a || t > b) ? 0 : Math.sin(Math.PI * (t - a) / (b - a));   // 0 → 1 → 0
const TAU = Math.PI * 2;

function base() {
  return { sc: 0.92, dx: 0, dy: 2, rot: 0, headDy: 0, headTilt: 0, earL: 0, earR: 0, look: [0, 0], lid: 0.06, low: 0, slant: 0, mouth: 'smile', pupil: 'normal' };
}

// ---------- Effekte ----------
function zzz(t) {
  let s = '';
  for (let i = 0; i < 3; i++) {
    const p = (t / 2.4 + i / 3) % 1;
    s += `<text x="${(66 + p * 18).toFixed(2)}" y="${(40 - p * 26).toFixed(2)}" font-size="${(7 + p * 7).toFixed(2)}" font-weight="900" font-family="Chalkboard SE, Comic Sans MS, sans-serif" fill="#ffffff" stroke="#151518" stroke-width=".6" opacity="${(1 - p).toFixed(2)}">Z</text>`;
  }
  return s;
}
function hearts(t) {
  let s = '';
  for (let i = 0; i < 2; i++) {
    const p = (t / 2.4 + i * 0.5) % 1;
    s += heart(i ? 18 : 82, 34 - p * 22, 7 + p * 3, 1 - p);
  }
  return s;
}
function steam(t) {
  let s = '';
  for (let i = 0; i < 2; i++) {
    const p = (t / 0.8 + i * 0.5) % 1;
    for (const x of [16, 84]) s += `<circle cx="${(x + (x < 50 ? -3 : 3) * p).toFixed(2)}" cy="${(28 - p * 12).toFixed(2)}" r="${(2 + p * 3).toFixed(2)}" fill="#ffffff" opacity="${((1 - p) * 0.75).toFixed(2)}"/>`;
  }
  return s;
}
function sigh(p) {
  if (p <= 0 || p >= 1) return '';
  let s = '';
  for (let i = 0; i < 3; i++) s += `<circle cx="${(58 + p * 16 + i * 3).toFixed(2)}" cy="${(72 - i * 2 - p * 3).toFixed(2)}" r="${(1.2 + i * 0.5 + p).toFixed(2)}" fill="#ffffff" opacity="${((1 - p) * 0.7).toFixed(2)}"/>`;
  return s;
}

// Kratzspuren (in Bildkoordinaten, rechts neben der Blase), Fortschritt 0…1, Deckkraft
function scratchMarks(progress, alpha, debrisT) {
  if (progress <= 0 || alpha <= 0) return '';
  let s = `<g opacity="${alpha.toFixed(3)}">`;
  [0, 9, 18].forEach((o, i) => {
    const local = clamp(progress * 1.4 - i * 0.2);
    if (local <= 0) return;
    const x0 = 104 + o, y0 = 8 + o * 0.3, x1 = 122 + o, y1 = 66 - o * 0.2;
    const pts = [];
    const n = 22;
    for (let k = 0; k <= n * local; k++) {
      const q = k / n, j = Math.sin(k * 2.7 + i * 5) * 0.6;
      pts.push([lerp(x0, x1, q) + j * 0.5, lerp(y0, y1, q) + Math.sin(q * Math.PI) * 3 + j]);
    }
    if (pts.length < 2) return;
    const d = 'M' + pts.map(p => p[0].toFixed(2) + ',' + p[1].toFixed(2)).join(' L');
    s += `<path d="${d}" stroke="rgba(0,0,0,.5)" stroke-width="${7 - i * 0.6}" fill="none" stroke-linecap="round"/>`;
    s += `<path d="${d}" stroke="#f1f0ea" stroke-width="${4.4 - i * 0.4}" fill="none" stroke-linecap="round"/>`;
    s += `<path d="${d}" stroke="rgba(255,255,255,.9)" stroke-width="1.2" fill="none" stroke-linecap="round" transform="translate(-0.8 -0.6)"/>`;
    s += `<path d="${d}" stroke="rgba(120,120,120,.6)" stroke-width=".6" fill="none" stroke-dasharray="1.2 2.2"/>`;
  });
  // Splitter fliegen weg und bleiben teils liegen
  const chips = [[118, 26, 9, -6], [126, 40, 12, 2], [112, 50, 7, 8], [131, 18, 10, -9], [121, 60, 6, 10], [135, 34, 14, -2]];
  chips.forEach(([x, y, vx, vy], i) => {
    const p = clamp(debrisT);
    const fly = i < 3 ? easeOut(p) : easeOut(p) * 1.6;
    const cx = x + vx * fly, cy = y + vy * fly + 6 * p * p;
    const op = i < 3 ? 1 : 1 - p;
    if (op <= 0.02) return;
    s += `<path d="M${cx.toFixed(2)},${cy.toFixed(2)} l${1.8 + (i % 2)},${0.6} l${-0.7},${1.7} Z" fill="#efeee8" stroke="rgba(0,0,0,.35)" stroke-width=".3" opacity="${op.toFixed(2)}"/>`;
  });
  return s + '</g>';
}
function swish(p) {
  if (p <= 0 || p >= 1) return '';
  const o = (1 - p) * 0.8;
  return `<g stroke="#ffffff" stroke-width="1.4" fill="none" stroke-linecap="round" opacity="${o.toFixed(2)}">
    <path d="M90,14 Q104,20 112,38"/><path d="M84,22 Q97,28 104,44"/><path d="M96,8 Q110,14 119,30"/></g>`;
}

// ---------- Sequenzen ----------
const SEQUENCES = {
  idle: { duration: 4.8, fps: 25, loop: true, pose(t) {
    const p = base();
    p.sc = 0.92 * (1 + 0.012 * Math.sin(TAU * t / 2.4));
    p.look = [1.8 * Math.sin(TAU * t / 4.8), 0];
    const blink = Math.max(bump(t, 1.6, 1.78), bump(t, 4.0, 4.16));
    p.lid = Math.max(0.06, blink);
    p.earR = 9 * bump(t, 3.0, 3.12) - 5 * bump(t, 3.12, 3.26);
    return p;
  }},
  sleep: { duration: 4.8, fps: 25, loop: true, pose(t) {
    const p = base();
    p.dy = 16; p.headDy = 4; p.headTilt = -7; p.closed = 'sleep'; p.earL = 8; p.earR = 8;
    p.sc = 0.92 * (1 + 0.02 * Math.sin(TAU * t / 2.4));
    p.fx = zzz(t);
    return p;
  }},
  ask: { duration: 1.6, fps: 25, loop: true, pose(t) {
    const p = base();
    p.pupil = 'round'; p.lid = 0; p.look = [0, -1.2]; p.earL = -4; p.earR = -4;
    p.headTilt = 5 * Math.sin(TAU * t / 1.6);
    p.rimL = false;
    p.wave = { x: 22 + 2 * Math.sin(TAU * t / 0.8), y: 62, rot: -8 + 20 * Math.sin(TAU * t / 0.8) };
    return p;
  }},
  purr: { duration: 2.4, fps: 25, loop: true, pose(t) {
    const p = base();
    p.closed = 'happy'; p.headTilt = 6 * Math.sin(TAU * t / 2.4); p.sc = 0.92 * (1 + 0.015 * Math.sin(TAU * t / 0.6));
    p.fx = hearts(t);
    return p;
  }},
  annoyed: { duration: 6, fps: 25, loop: true, pose(t) {
    // genervt: gerader, schwerer Blick zur Seite, Ohren seitlich – dann rollt er mit den Augen und seufzt
    const p = base();
    p.brows = 'annoyed'; p.earL = 18; p.earR = 18; p.mouth = 'side'; p.slant = 1.6; p.low = 0.16;
    p.lid = 0.44; p.look = [3.6, 0.6];
    if (t >= 1.4 && t < 2.6) {                         // Augenrollen: rechts → oben → links
      const q = smooth((t - 1.4) / 1.2), th = Math.PI * q;
      p.look = [4 * Math.cos(th), -5.8 * Math.sin(th) + 0.6 * (1 - Math.sin(th))];
      p.lid = lerp(0.44, 0.18, bump(t, 1.4, 2.6) > 0 ? Math.min(1, bump(t, 1.4, 2.6) * 1.6) : 0);
      p.low = 0.05;
      p.headTilt = -6 * bump(t, 1.4, 2.6);
      p.browRaise = 2 * bump(t, 1.4, 2.6);
    } else if (t >= 2.6 && t < 3.2) {                  // Lider fallen, Seitenblick links
      const q = smooth((t - 2.6) / 0.6);
      p.look = [lerp(-4, -3.6, q), lerp(0.6, 0.6, q)];
      p.lid = lerp(0.3, 0.48, q);
    } else if (t >= 3.2 && t < 5.2) {                  // Seufzer, dann starrt er
      p.look = [-3.6, 0.6]; p.lid = 0.48;
      p.headDy = 1.4 * bump(t, 3.2, 3.9);
      p.fx = sigh((t - 3.2) / 0.9);
    } else if (t >= 5.2) {                             // Blick langsam zurück nach rechts
      const q = smooth((t - 5.2) / 0.8);
      p.look = [lerp(-3.6, 3.6, q), 0.6]; p.lid = lerp(0.48, 0.44, q);
    }
    return p;
  }},
  angry: { duration: 1.6, fps: 25, loop: true, pose(t) {
    const p = base();
    p.brows = 'angry'; p.earL = 38 + 3 * bump(t % 0.8, 0, 0.12); p.earR = 38 + 3 * bump(t % 0.8, 0, 0.12);
    p.slant = 5.5; p.lid = 0.14; p.low = 0.12; p.pupil = 'slit'; p.angryEyes = true; p.mouth = 'hiss'; p.bristle = true;
    p.sc = 0.92 * (1.03 + 0.008 * Math.sin(TAU * t / 0.4)); p.dy = 0;   // leicht vorgebeugt, angespannt
    p.fx = steam(t);
    return p;
  }},
  intro: { duration: 3.6, fps: 30, loop: false, pose(t) {
    // taucht von unten in der Blase auf, schaut sich um und winkt
    const p = base();
    p.dy = lerp(80, 2, easeOutBack(t / 1.0));
    p.earL = -6 * bump(t, 0.7, 1.1); p.earR = -6 * bump(t, 0.7, 1.1);
    if (t < 1.0) p.lid = 0.06;
    else if (t < 1.5) p.look = [-4 * smooth((t - 1.0) / 0.3), 0];
    else if (t < 2.0) p.look = [lerp(-4, 4, smooth((t - 1.5) / 0.3)), 0];
    else {
      p.look = [lerp(4, 0, smooth((t - 2.0) / 0.3)), -1]; p.pupil = 'round'; p.lid = 0;
      const w = (t - 2.0);
      p.rimL = false;
      p.wave = { x: lerp(33, 22, smooth(w / 0.3)), y: lerp(85, 62, easeOutBack(w / 0.35)), rot: -8 + 20 * Math.sin(TAU * w / 0.8) * smooth(w / 0.3) };
    }
    return p;
  }},
  scratch: { duration: 5.0, fps: 40, loop: false, wide: true, catUntil: 2.4, pose(t) {
    const p = base();
    const e = t < 0.45 ? smooth(t / 0.45) : (t < 1.9 ? 1 : 1 - smooth((t - 1.9) / 0.5));
    p.sc = 0.92 + 0.18 * e; p.dx = 4 * e; p.dy = lerp(2, -3, e); p.rot = -8 * e; p.headTilt = -3 * e;
    // Blick und Laune
    p.lid = lerp(0.06, 0.3, e); p.slant = 1 * e; p.look = [3.2 * e, 0];
    if (t >= 0.7 && t < 1.6) { p.mouth = 'fang'; p.lid = 0.2; p.look = [3.8, -0.6]; }
    if (t >= 1.6 && t < 2.4) { p.closed = 'happy'; }
    // Arm: kommt vom Rand, holt seitlich aus, schnellt nach rechts unten, zurück
    if (t >= 0.35 && t < 1.9) {
      let ax, ay, rot, claws = 0;
      if (t < 0.8) { const q = (t - 0.35) / 0.45; ax = lerp(66, 90, easeOut(q)); ay = lerp(85, 26, easeOutBack(q)); rot = 18 * smooth(q); claws = smooth((t - 0.62) / 0.18); }
      else if (t < 1.0) { const q = easeIn((t - 0.8) / 0.2); ax = lerp(90, 103, q); ay = lerp(26, 50, q); rot = lerp(18, 50, q); claws = 1; }
      else if (t < 1.35) { const q = smooth((t - 1.0) / 0.35); ax = lerp(103, 100, q); ay = lerp(50, 47, q); rot = lerp(50, 44, q); claws = 1 - 0.4 * q; }
      else { const q = smooth((t - 1.35) / 0.55); ax = lerp(100, 66, q); ay = lerp(47, 85, q); rot = lerp(44, 0, q); claws = 0.6 * (1 - q); }
      p.arm = { x: ax, y: ay, rot, s: 1.02, claws };
      p.rimR = false;
    }
    if (t >= 2.4) p.hidden = true;
    // Spuren: erscheinen beim Treffer, bleiben 2 s stehen, verblassen
    const prog = smooth((t - 0.86) / 0.24);
    const alpha = t < 4.3 ? 1 : 1 - smooth((t - 4.3) / 0.7);
    p.marksBehind = scratchMarks(prog, alpha, (t - 0.95) / 0.8);
    p.fx = swish((t - 0.8) / 0.3);
    return p;
  }},
  flick: { duration: 2.2, fps: 40, loop: false, wide: true, catUntil: 2.2, pose(t) {
    const p = base();
    const e = 0.8 * (t < 0.4 ? smooth(t / 0.4) : (t < 1.7 ? 1 : 1 - smooth((t - 1.7) / 0.5)));
    p.sc = 0.92 + 0.18 * e; p.dx = 3 * e; p.dy = lerp(2, -2, e); p.rot = -5 * e;
    p.brows = 'annoyed'; p.earL = 20; p.earR = 20; p.lid = 0.4; p.slant = 2; p.low = 0.15; p.mouth = 'side'; p.look = [-2.5, 0.6];
    if (t >= 0.25 && t < 1.95) {
      let ax, ay, rot;
      if (t < 0.6) { const q = (t - 0.25) / 0.35; ax = lerp(66, 90, easeOut(q)); ay = lerp(85, 30, easeOutBack(q)); rot = 10 * q; }
      else if (t < 1.45) { const q = (t - 0.6) / 0.85, w = Math.sin(q * TAU * 2) * (1 - q * 0.5); ax = 90 + 7 * w; ay = 30 + 2 * Math.abs(w); rot = 10 + 26 * w; }
      else { const q = smooth((t - 1.45) / 0.5); ax = lerp(90, 66, q); ay = lerp(30, 85, q); rot = lerp(10, 0, q); }
      p.arm = { x: ax, y: ay, rot, s: 0.98, claws: 0 };
      p.rimR = false;
    }
    return p;
  }},
};


// ---------- kleine Bewegungen in der Ruhephase (etwa alle 20 s eine) ----------
Object.assign(SEQUENCES, {
  idle_tilt: { duration: 2.6, fps: 25, loop: false, pose(t) {
    const p = base(); const k = bump(t, 0, 2.6);
    p.headTilt = 9 * Math.min(1, k * 1.6); p.look = [1.2 * k, -0.8 * k]; p.earR = -5 * k; return p;
  }},
  idle_look: { duration: 2.8, fps: 25, loop: false, pose(t) {
    const p = base();
    if (t < 0.9) p.look = [-4 * smooth(t / 0.5), 0];
    else if (t < 1.9) p.look = [lerp(-4, 4, smooth((t - 0.9) / 0.5)), 0];
    else p.look = [lerp(4, 0, smooth((t - 1.9) / 0.6)), 0];
    p.headTilt = -3 * Math.sin(TAU * t / 2.8);
    p.lid = Math.max(0.06, bump(t, 1.3, 1.45));
    return p;
  }},
  idle_tongue: { duration: 3.0, fps: 25, loop: false, pose(t) {
    const p = base();
    if (t > 0.5 && t < 2.5) { p.mouth = 'blep'; p.lid = 0.22; p.look = [0, -0.5]; }
    p.headTilt = 5 * bump(t, 0.3, 2.7);
    return p;
  }},
  idle_slowblink: { duration: 2.0, fps: 25, loop: false, pose(t) {
    const p = base(); p.lid = Math.max(0.06, 0.95 * Math.min(1, bump(t, 0.2, 1.8) * 1.3)); return p;
  }},
  idle_ears: { duration: 1.4, fps: 25, loop: false, pose(t) {
    const p = base();
    p.earL = 12 * bump(t, 0.1, 0.35) - 6 * bump(t, 0.35, 0.55);
    p.earR = 10 * bump(t, 0.6, 0.85) - 5 * bump(t, 0.85, 1.05);
    p.look = [0.8 * Math.sin(TAU * t / 1.4), 0];
    return p;
  }},
  idle_stretch: { duration: 2.6, fps: 25, loop: false, pose(t) {
    // reckt sich kurz: Kopf hoch, Augen zu, wieder runter
    const p = base(); const k = bump(t, 0.2, 2.4);
    p.dy = 2 - 5 * k; p.headTilt = -4 * k; p.lid = Math.max(0.06, 0.8 * Math.min(1, k * 1.5)); p.mouth = k > 0.6 ? 'fang' : 'smile';
    return p;
  }},
});

// ---------- Ablagefach füttern & Feierabend-Wecker ----------
function paper(x, y, rot, s, o = 1) {
  return `<g transform="translate(${x.toFixed(2)} ${y.toFixed(2)}) rotate(${rot.toFixed(1)}) scale(${s.toFixed(3)})" opacity="${o.toFixed(2)}">
    <path d="M-8,-10 L4,-10 L8,-6 L8,10 L-8,10 Z" fill="#ffffff" stroke="#151518" stroke-width="1.1" stroke-linejoin="round"/>
    <path d="M4,-10 L4,-6 L8,-6" fill="#e6e6ea" stroke="#151518" stroke-width="1"/>
    <path d="M-5,-3 h9 M-5,0.5 h9 M-5,4 h6" stroke="#9aa0a8" stroke-width="1.2" stroke-linecap="round"/></g>`;
}
function crumbs(p) {
  if (p <= 0 || p >= 1) return '';
  let s = '';
  [[44, 76, -5, 6], [56, 77, 6, 5], [50, 79, 1, 8]].forEach(([x, y, vx, vy]) => {
    s += `<rect x="${(x + vx * p).toFixed(2)}" y="${(y + vy * p).toFixed(2)}" width="1.6" height="1.6" fill="#ffffff" stroke="#151518" stroke-width=".3" opacity="${(1 - p).toFixed(2)}"/>`;
  });
  return s;
}
function sparkle(x, y, p) {
  if (p <= 0 || p >= 1) return '';
  const k = Math.sin(Math.PI * p), r = 4 * k;
  return `<path d="M${x},${y - r} L${x + r * 0.25},${y - r * 0.25} L${x + r},${y} L${x + r * 0.25},${y + r * 0.25} L${x},${y + r} L${x - r * 0.25},${y + r * 0.25} L${x - r},${y} L${x - r * 0.25},${y - r * 0.25} Z" fill="#fff6c8" opacity="${k.toFixed(2)}"/>`;
}
function ringLines(t) {
  const on = Math.floor(t * 8) % 2 === 0;
  if (!on) return '';
  return `<g stroke="#ffffff" stroke-width="1.6" fill="none" stroke-linecap="round">
    <path d="M10,22 Q4,30 8,40"/><path d="M4,18 Q-4,30 2,44"/><path d="M90,22 Q96,30 92,40"/><path d="M96,18 Q104,30 98,44"/></g>`;
}
Object.assign(SEQUENCES, {
  // Datei wird über Rüdiger gezogen: Maul auf, große Augen, wippt vor Vorfreude
  eat_ready: { duration: 1.2, fps: 25, loop: true, pose(t) {
    const p = base();
    p.mouth = 'wide'; p.pupil = 'round'; p.lid = 0; p.look = [0, -2.5]; p.earL = -6; p.earR = -6;
    p.dy = 2 - 1.5 * Math.abs(Math.sin(TAU * t / 1.2));
    return p;
  }},
  // Datei fällt ins Maul, er kaut, schluckt, leckt sich die Lippen
  eat: { duration: 3.2, fps: 25, loop: false, pose(t) {
    const p = base();
    let fx = '';
    if (t < 0.55) {
      const q = easeIn(t / 0.55);
      p.mouth = 'wide'; p.pupil = 'round'; p.lid = 0; p.look = [0, lerp(-3, 1.5, q)]; p.earL = -6; p.earR = -6;
      fx += paper(50, lerp(-4, 68, q), lerp(-24, 8, q), lerp(1.25, 0.55, q));
    } else if (t < 0.65) {
      p.mouth = 'chew'; p.closed = 'happy'; p.dy = 3.5;          // Happs!
      fx += crumbs((t - 0.55) / 0.5);
    } else if (t < 1.95) {
      const c = (t - 0.65) / 0.16;
      p.closed = 'happy'; p.mouth = Math.floor(c) % 2 === 0 ? 'chew' : 'smile';
      p.cheeks = 0.6 + 0.4 * Math.abs(Math.sin(Math.PI * c));
      p.dy = 2 + 0.8 * Math.abs(Math.sin(Math.PI * c));
      p.headTilt = 3 * Math.sin(TAU * (t - 0.65) / 1.3);
      fx += crumbs((t - 0.55) / 0.5);
    } else if (t < 2.25) {
      const q = (t - 1.95) / 0.3;                                 // schlucken
      p.closed = 'happy'; p.mouth = 'smile'; p.headDy = 2.5 * Math.sin(Math.PI * q); p.cheeks = 0.6 * (1 - q);
    } else if (t < 2.8) {
      // Rülpser: Maul kurz auf, Augen halb zu, Wölkchen
      const q = (t - 2.25) / 0.55;
      p.mouth = q < 0.75 ? 'fang' : 'smile'; p.lid = 0.5; p.headTilt = -4 * Math.sin(Math.PI * q); p.headDy = -1.2 * Math.sin(Math.PI * q);
      fx += sigh(q);
    } else {
      p.mouth = 'blep'; p.lid = 0.3; p.look = [0, -0.5];
      fx += sparkle(80, 30, (t - 2.8) / 0.4);
    }
    p.fx = fx;
    return p;
  }},
  // Feierabend: wackelt wie ein Wecker
  alarm: { duration: 3.0, fps: 30, loop: false, pose(t) {
    const p = base();
    const ring = t < 2.4 ? 1 : 1 - smooth((t - 2.4) / 0.6);
    p.dx = 2.6 * Math.sin(TAU * t * 11) * ring;
    p.rot = 3.5 * Math.sin(TAU * t * 11 + 1) * ring;
    p.pupil = 'round'; p.lid = 0; p.mouth = 'fang'; p.earL = -8; p.earR = -8; p.look = [0, -1];
    p.fx = t < 2.4 ? ringLines(t) : '';
    return p;
  }},
});

if (typeof module !== 'undefined') module.exports = { SEQUENCES };
