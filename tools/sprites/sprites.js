// Rüdigers Sprite-Animationen.
// Er streckt den Kopf aus seinem Fenster, hebt die Pfote seitlich neben dem Kopf an die „Scheibe“
// (den Bildschirm) und kratzt von oben nach unten. Der Arm hängt dabei immer an seinem Körper.
// Koordinaten in Rüdiger-Einheiten: das runde Fenster ist 100 × 100 (Mitte 50/50).
// Das Bild deckt 220 × 220 Einheiten ab (viewBox -60 … 160).

const clamp = x => Math.min(Math.max(x, 0), 1);
const smooth = x => { const v = clamp(x); return v * v * v * (v * (v * 6 - 15) + 10); };
const easeOut = x => 1 - Math.pow(1 - clamp(x), 3);
const easeOutBack = x => { const v = clamp(x), c1 = 1.3, c3 = c1 + 1; return 1 + c3 * Math.pow(v - 1, 3) + c1 * Math.pow(v - 1, 2); };
const lerp = (a, b, t) => a + (b - a) * t;
const lerpPt = (a, b, t) => [lerp(a[0], b[0], t), lerp(a[1], b[1], t)];

// Zehen (Mitte der Zehenballen) relativ zur Pfotenmitte – Pfote aufrecht, Ballen zum Betrachter
const TOES = [[-9.2, -7.6], [-3.3, -11.4], [3.3, -11.4], [9.2, -7.6]];

const SEQUENCES = {
  scratch: { duration: 2.8, face: 'grumpy', drags: [[0.85, 1.3], [1.5, 1.95]] },
  flick: { duration: 2.0, face: 'angry', drags: [] },
};

// Schulter (im Körper, vor dem Vorbeugen) – hier setzt der Arm an
const SHOULDER = [70, 86];
const REST = [73, 84];      // Pfote „zu Hause“ an der Brust

/** Vorbeugen: Rüdiger wird größer (kommt näher), Kopf ragt aus dem Fenster */
const leanScale = lean => 1 + 0.32 * lean;
const leanPoint = (p, lean) => { const s = leanScale(lean); return [50 + (p[0] - 50) * s, 100 + (p[1] - 100) * s]; };

function state(name, t) {
  if (name === 'scratch') {
    const lean = t < 0.45 ? smooth(t / 0.45) : (t < 2.35 ? 1 : 1 - smooth((t - 2.35) / 0.45));
    const home = leanPoint(REST, lean);
    const top1 = [88, 27], bottom1 = [86, 63], top2 = [95, 30], bottom2 = [93, 66];
    let pos = home, s = 0.85, claws = 0, rot = 4, pressed = false, alpha = 0;
    if (t < 0.2) { }
    else if (t < 0.7) { const p = (t - 0.2) / 0.5; pos = lerpPt(home, top1, easeOutBack(p)); s = lerp(0.85, 1.15, easeOut(p)); rot = lerp(4, 12, p); alpha = clamp(p * 5); }
    else if (t < 0.85) { const p = (t - 0.7) / 0.15; pos = top1; s = 1.15 + 0.03 * Math.sin(Math.PI * p); claws = easeOut(p); rot = 12; pressed = true; alpha = 1; }
    else if (t < 1.3) { const p = smooth((t - 0.85) / 0.45); pos = lerpPt(top1, bottom1, p); s = 1.17; claws = 1; rot = 12 - 4 * Math.sin(Math.PI * p); pressed = true; alpha = 1; }
    else if (t < 1.5) {
      // abheben und in einem kleinen Bogen neu ansetzen
      const p = smooth((t - 1.3) / 0.2), arc = Math.sin(Math.PI * p) * 3;
      pos = [lerp(bottom1[0], top2[0], p) + arc, lerp(bottom1[1], top2[1], p)]; s = 1.17 - 0.07 * Math.sin(Math.PI * p);
      claws = 1 - 0.6 * Math.sin(Math.PI * p); rot = 12 + 3 * Math.sin(Math.PI * p); alpha = 1;
    }
    else if (t < 1.95) { const p = smooth((t - 1.5) / 0.45); pos = lerpPt(top2, bottom2, p); s = 1.17; claws = 1; rot = 13 - 4 * Math.sin(Math.PI * p); pressed = true; alpha = 1; }
    else if (t < 2.45) { const p = smooth((t - 1.95) / 0.5); pos = lerpPt(bottom2, home, p); s = lerp(1.17, 0.85, p); claws = 1 - easeOut(p * 3); rot = lerp(13, 4, p); alpha = 1 - clamp((p - 0.7) / 0.3); }
    return { lean, x: pos[0], y: pos[1], s, claws, rot, pressed, alpha, visible: t >= 0.2 && t < 2.45 };
  }
  // abfälliges Wegwedeln, seitlich neben dem Kopf
  const lean = 0.85 * (t < 0.4 ? smooth(t / 0.4) : (t < 1.6 ? 1 : 1 - smooth((t - 1.6) / 0.4)));
  const home = leanPoint(REST, lean), up = [85, 38];
  let pos = home, s = 0.85, rot = 4, alpha = 0;
  if (t < 0.2) { }
  else if (t < 0.6) { const p = (t - 0.2) / 0.4; pos = lerpPt(home, up, easeOutBack(p)); s = lerp(0.85, 1.1, easeOut(p)); alpha = clamp(p * 5); }
  else if (t < 1.35) { const p = (t - 0.6) / 0.75, w = Math.sin(p * Math.PI * 4) * (1 - p * 0.5); pos = [up[0] + 7 * w, up[1] + 2 * Math.abs(w)]; s = 1.1; rot = 8 + 22 * w; alpha = 1; }
  else if (t < 1.8) { const p = smooth((t - 1.35) / 0.45); pos = lerpPt(up, home, p); s = lerp(1.1, 0.85, p); rot = lerp(8, 4, p); alpha = 1 - clamp((p - 0.7) / 0.3); }
  return { lean, x: pos[0], y: pos[1], s, claws: 0, rot, pressed: false, alpha, visible: t >= 0.2 && t < 1.8 };
}

/** Krallenspitzen (global) */
function clawTips(st) {
  const len = 7.5 * st.claws, r = st.rot * Math.PI / 180, sx = st.pressed ? 1.08 : 1;
  return TOES.map(([tx, ty]) => {
    const lx = tx * sx * 1.02, ly = ty - 4.4 - len;
    return [st.x + (lx * Math.cos(r) - ly * Math.sin(r)) * st.s, st.y + (lx * Math.sin(r) + ly * Math.cos(r)) * st.s];
  });
}

/** Arm von der Schulter zum Handgelenk – leicht angewinkelt (Ellbogen nach außen), immer am Körper */
function armSVG(st) {
  const sh = leanPoint(SHOULDER, st.lean), sc = leanScale(st.lean);
  const r = st.rot * Math.PI / 180;
  const wrist = [st.x - Math.sin(r) * -8 * st.s * -1, st.y + Math.cos(r) * 8 * st.s];
  const mid = [(sh[0] + wrist[0]) / 2, (sh[1] + wrist[1]) / 2];
  const dx = wrist[0] - sh[0], dy = wrist[1] - sh[1], len = Math.hypot(dx, dy) || 1;
  const nx = -dy / len, ny = dx / len;                 // Normale
  const out = nx > 0 ? 1 : -1;                         // Ellbogen nach außen (rechts)
  const bend = Math.min(9, len * 0.22);
  const ctrl = [mid[0] + nx * bend * out, mid[1] + ny * bend * out];
  const w0 = 9.5 * sc, w1 = 6.6 * st.s;
  const left = [], right = [];
  for (let i = 0; i <= 28; i++) {
    const q = i / 28;
    const x = (1 - q) * (1 - q) * sh[0] + 2 * (1 - q) * q * ctrl[0] + q * q * wrist[0];
    const y = (1 - q) * (1 - q) * sh[1] + 2 * (1 - q) * q * ctrl[1] + q * q * wrist[1];
    const tx = 2 * (1 - q) * (ctrl[0] - sh[0]) + 2 * q * (wrist[0] - ctrl[0]);
    const ty = 2 * (1 - q) * (ctrl[1] - sh[1]) + 2 * q * (wrist[1] - ctrl[1]);
    const tl = Math.hypot(tx, ty) || 1, px = -ty / tl, py = tx / tl;
    const w = w0 + (w1 - w0) * q + Math.sin(q * Math.PI) * 1.2;    // Muskel
    left.push([x + px * w, y + py * w]); right.push([x - px * w, y - py * w]);
  }
  const pts = [...left, ...right.reverse()].map(p => p.map(v => v.toFixed(2)).join(',')).join(' L');
  return `<g filter="url(#fur)"><path d="M${pts} Z" fill="url(#armShade)"/>` +
    // Schulter verschmilzt mit dem Körper
    `<ellipse cx="${sh[0]}" cy="${sh[1]}" rx="${w0 * 1.15}" ry="${w0}" fill="#17171a"/></g>`;
}

/** Pfote (Ballen zum Betrachter) */
function pawSVG(st) {
  const pressed = st.pressed, sq = pressed ? 1.08 : 1, claw = st.claws;
  let o = `<g transform="translate(${st.x} ${st.y}) rotate(${st.rot}) scale(${st.s})">`;
  o += `<g filter="url(#fur)">`;
  o += `<ellipse cx="0" cy="-1" rx="${13.2 * sq}" ry="11.8" fill="url(#pawShade)"/>`;
  o += `<path d="M-9,4 C-9.5,9 -7,12 -6.5,13 L6.5,13 C7,12 9.5,9 9,4 Z" fill="#141416"/>`;
  TOES.forEach(([tx, ty]) => { o += `<circle cx="${tx * sq}" cy="${ty}" r="4.9" fill="url(#pawShade)"/>`; });
  o += `</g>`;
  [[-6.3, -12.2], [0, -14.2], [6.3, -12.2]].forEach(([fx, fy]) => {
    o += `<path d="M${fx * sq - 1},${fy + 2.5} q1,-3 1,-4.4 q0.4,2 1.2,4.4" fill="#0d0d0f"/>`;
  });
  const padFill = pressed ? 'url(#padPressed)' : 'url(#pad)';
  o += `<g transform="scale(${sq} ${pressed ? 0.96 : 1})">`;
  o += `<path d="M-7.6,4.8 C-9.4,1 -7.4,-3.6 -3.7,-3 C-2.3,-5.6 2.3,-5.6 3.7,-3 C7.4,-3.6 9.4,1 7.6,4.8 C5.6,8.4 -5.6,8.4 -7.6,4.8 Z" fill="${padFill}"/>`;
  o += `<ellipse cx="-2.2" cy="-1.4" rx="2.3" ry="1.1" fill="#fff" opacity=".45"/>`;
  TOES.forEach(([tx, ty]) => {
    o += `<ellipse cx="${tx}" cy="${ty + 0.8}" rx="3.1" ry="3.6" fill="${padFill}"/>`;
    o += `<ellipse cx="${tx - 0.9}" cy="${ty - 0.6}" rx="0.9" ry="0.6" fill="#fff" opacity=".55"/>`;
  });
  o += `</g>`;
  if (claw > 0.02) {
    const len = 7.5 * claw;
    TOES.forEach(([tx, ty], i) => {
      const bx = tx * sq * 1.02, by = ty - 4.4, bend = (i - 1.5) * 0.9;
      o += `<path d="M${bx - 1.1},${by + 0.6} Q${bx - 0.9 + bend * 0.3},${by - len * 0.65} ${bx + bend},${by - len} Q${bx + 0.6 + bend * 0.2},${by - len * 0.5} ${bx + 1.1},${by + 0.6} Z" fill="url(#claw)" stroke="rgba(0,0,0,.28)" stroke-width=".25"/>`;
    });
  }
  o += `<path d="M-12.4,-4 C-12,-10 -8,-14 -3,-15" stroke="rgba(255,255,255,.16)" stroke-width="1" fill="none" stroke-linecap="round"/>`;
  return o + `</g>`;
}

function frameSVG(name, t, px) {
  const seq = SEQUENCES[name], st = state(name, t);
  const sc = leanScale(st.lean);
  const lean = `translate(50 100) scale(${sc}) translate(-50 -100)`;
  const bust = bustInner(seq.face);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${px}" height="${px}" viewBox="-60 -60 220 220">
  <defs>
    <clipPath id="win"><circle cx="50" cy="50" r="48.5"/></clipPath>
    <clipPath id="head"><rect x="-100" y="-100" width="300" height="171"/></clipPath>
    <filter id="fur" x="-30%" y="-30%" width="160%" height="160%">
      <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="7" result="n"/>
      <feDisplacementMap in="SourceGraphic" in2="n" scale="1.6" xChannelSelector="R" yChannelSelector="G"/>
    </filter>
    <filter id="drop" x="-40%" y="-40%" width="180%" height="180%"><feDropShadow dx="1" dy="2.2" stdDeviation="2.2" flood-color="#000" flood-opacity=".35"/></filter>
    <filter id="soft" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="1.2" stdDeviation="1.4" flood-color="#000" flood-opacity=".2"/></filter>
    <linearGradient id="armShade" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#2c2c31"/><stop offset=".45" stop-color="#17171a"/><stop offset="1" stop-color="#08080a"/></linearGradient>
    <radialGradient id="pawShade" cx="-4" cy="-9" r="22" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#34343a"/><stop offset=".55" stop-color="#18181b"/><stop offset="1" stop-color="#0b0b0d"/></radialGradient>
    <radialGradient id="pad" cx="40%" cy="35%" r="70%"><stop offset="0" stop-color="#fdc4d1"/><stop offset="1" stop-color="#d97f97"/></radialGradient>
    <radialGradient id="padPressed" cx="45%" cy="40%" r="70%"><stop offset="0" stop-color="#fed6df"/><stop offset="1" stop-color="#e796aa"/></radialGradient>
    <linearGradient id="claw" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="#d9d6cf"/><stop offset="1" stop-color="#fbfaf6"/></linearGradient>
  </defs>
  <g clip-path="url(#win)"><g transform="${lean}">${bust}</g></g>
  <g filter="url(#soft)"><g transform="${lean}"><g clip-path="url(#head)">${bust}</g></g></g>
  ${st.visible ? `<g opacity="${st.alpha}">
     ${st.pressed ? `<ellipse cx="${st.x}" cy="${st.y - 2 * st.s}" rx="${15 * st.s}" ry="${13 * st.s}" fill="rgba(255,255,255,.14)" filter="blur(2px)"/>` : ''}
     <g filter="url(#drop)">${armSVG(st)}${pawSVG(st)}</g></g>` : ''}
</svg>`;
}

if (typeof module !== 'undefined') module.exports = { SEQUENCES, state, clawTips, frameSVG };
