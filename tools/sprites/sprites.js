// Rüdigers Sprite-Animationen: er beugt sich vor und kratzt an der „Scheibe“ vor ihm (dem Bildschirm).
// Koordinaten in Rüdiger-Einheiten: das runde Fenster ist 100 × 100 (Mitte 50/50).
// Das Bild deckt 220 × 220 Einheiten ab (viewBox -60 … 160), damit Kopf und Pfote herausragen können.

const clamp = x => Math.min(Math.max(x, 0), 1);
const smooth = x => { const v = clamp(x); return v * v * v * (v * (v * 6 - 15) + 10); };
const easeOut = x => 1 - Math.pow(1 - clamp(x), 3);
const easeOutBack = x => { const v = clamp(x), c1 = 1.5, c3 = c1 + 1; return 1 + c3 * Math.pow(v - 1, 3) + c1 * Math.pow(v - 1, 2); };
const lerp = (a, b, t) => a + (b - a) * t;

// Zehen (Mitte der Zehenballen) relativ zur Pfotenmitte, Pfote gerade nach oben (Ballen zum Betrachter)
const TOES = [[-9.2, -7.6], [-3.3, -11.4], [3.3, -11.4], [9.2, -7.6]];

const SEQUENCES = {
  scratch: { duration: 2.8, face: 'grumpy', drags: [[0.9, 1.35], [1.55, 2.0]] },
  flick: { duration: 2.0, face: 'angry', drags: [] },
};

/** Zustand eines Bildes */
function state(name, t) {
  if (name === 'scratch') {
    const lean = t < 0.5 ? smooth(t / 0.5) : (t < 2.3 ? 1 : 1 - smooth((t - 2.3) / 0.45));
    let x = 60, y = 96, s = 0.8, claws = 0, rot = 0, pressed = false, alpha = 1;
    if (t < 0.25) { /* Pfote noch unten */ }
    else if (t < 0.75) { const p = (t - 0.25) / 0.5, e = easeOutBack(p); x = lerp(60, 54, easeOut(p)); y = lerp(96, 46, e); alpha = clamp(p * 5); s = lerp(0.8, 1.45, easeOut(p)); rot = 10 * (1 - p); }
    else if (t < 0.9) { const p = (t - 0.75) / 0.15; x = 54; y = 46; s = 1.45 + 0.04 * Math.sin(Math.PI * p); claws = easeOut(p); pressed = true; }
    else if (t < 1.35) { const p = smooth((t - 0.9) / 0.45); x = lerp(54, 52, p); y = lerp(46, 74, p); s = 1.47; claws = 1; pressed = true; rot = -3 * Math.sin(Math.PI * p); }
    else if (t < 1.55) { const p = smooth((t - 1.35) / 0.2); x = lerp(52, 61, p); y = lerp(74, 43, p); s = 1.47 - 0.1 * Math.sin(Math.PI * p); claws = 1 - 0.5 * Math.sin(Math.PI * p); rot = 4 * Math.sin(Math.PI * p); }
    else if (t < 2.0) { const p = smooth((t - 1.55) / 0.45); x = lerp(61, 59, p); y = lerp(43, 72, p); s = 1.47; claws = 1; pressed = true; rot = -3 * Math.sin(Math.PI * p); }
    else if (t < 2.5) { const p = smooth((t - 2.0) / 0.5); x = lerp(59, 60, p); y = lerp(72, 96, p); s = lerp(1.47, 0.8, p); claws = 1 - easeOut(p * 3); rot = 8 * p; alpha = 1 - clamp((p - 0.6) / 0.4); }
    return { lean, x, y, s, claws, rot, pressed, alpha, visible: t >= 0.25 && t < 2.5 };
  }
  // abfälliges Wegwedeln
  const lean = 0.8 * (t < 0.4 ? smooth(t / 0.4) : (t < 1.6 ? 1 : 1 - smooth((t - 1.6) / 0.4)));
  let x = 60, y = 96, s = 0.8, rot = 0, alpha = 1;
  if (t < 0.2) { }
  else if (t < 0.6) { const p = (t - 0.2) / 0.4; x = lerp(60, 56, easeOut(p)); y = lerp(96, 52, easeOutBack(p)); alpha = clamp(p * 5); s = lerp(0.8, 1.35, easeOut(p)); }
  else if (t < 1.35) { const p = (t - 0.6) / 0.75, w = Math.sin(p * Math.PI * 4) * (1 - p * 0.5); x = 56 + 13 * w; y = 52 + 3 * Math.abs(w); s = 1.35; rot = 24 * w; }
  else if (t < 1.8) { const p = smooth((t - 1.35) / 0.45); x = lerp(56, 60, p); y = lerp(52, 96, p); s = lerp(1.35, 0.8, p); alpha = 1 - clamp((p - 0.6) / 0.4); }
  return { lean, x, y, s, claws: 0, rot, pressed: false, alpha, visible: t >= 0.2 && t < 1.8 };
}

/** Krallenspitzen in Rüdiger-Einheiten */
function clawTips(st) {
  const len = 7.5 * st.claws, r = st.rot * Math.PI / 180;
  return TOES.map(([tx, ty]) => {
    const lx = tx * 1.02, ly = ty - 4.4 - len;
    const sx = st.pressed ? 1.08 : 1;
    const px = lx * sx * Math.cos(r) - ly * Math.sin(r), py = lx * sx * Math.sin(r) + ly * Math.cos(r);
    return [st.x + px * st.s, st.y + py * st.s];
  });
}

/** Vorderbein + Pfote (Ballen zum Betrachter), im lokalen Pfoten-Koordinatensystem */
function pawSVG(st) {
  const pressed = st.pressed, sq = pressed ? 1.08 : 1;
  const claw = st.claws;
  const tf = `translate(${st.x} ${st.y}) rotate(${st.rot}) scale(${st.s})`;
  // Unterarm: kommt aus Rüdigers Brust – nur innerhalb des Fensters sichtbar
  let o = `<g clip-path="url(#armclip)"><g transform="${tf}"><g filter="url(#fur)"><path d="M-10.5,3 C-12,14 -12.5,26 -11,60 L11,60 C12.5,26 12,14 10.5,3 Z" fill="url(#arm)"/></g></g></g>`;
  o += `<g transform="${tf}">`;
  o += `<g filter="url(#fur)">`;
  // Pfote: weicher „Fäustling“
  o += `<ellipse cx="0" cy="-1" rx="${13.2 * sq}" ry="11.8" fill="url(#pawShade)"/>`;
  TOES.forEach(([tx, ty]) => { o += `<circle cx="${tx * sq}" cy="${ty}" r="4.9" fill="url(#pawShade)"/>`; });
  o += `</g>`;
  // Fellbüschel zwischen den Zehen
  [[-6.3, -12.2], [0, -14.2], [6.3, -12.2]].forEach(([fx, fy]) => {
    o += `<path d="M${fx * sq - 1},${fy + 2.5} q1,-3 1,-4.4 q0.4,2 1.2,4.4" fill="#0d0d0f"/>`;
  });
  // Ballen: Hauptballen dreilappig, vier Zehenballen – glänzend, an der Scheibe leicht platt
  const padFill = pressed ? 'url(#padPressed)' : 'url(#pad)';
  o += `<g transform="scale(${sq} ${pressed ? 0.96 : 1})">`;
  o += `<path d="M-7.6,4.8 C-9.4,1 -7.4,-3.6 -3.7,-3 C-2.3,-5.6 2.3,-5.6 3.7,-3 C7.4,-3.6 9.4,1 7.6,4.8 C5.6,8.4 -5.6,8.4 -7.6,4.8 Z" fill="${padFill}"/>`;
  o += `<ellipse cx="-2.2" cy="-1.4" rx="2.3" ry="1.1" fill="#fff" opacity=".45"/>`;
  TOES.forEach(([tx, ty]) => {
    o += `<ellipse cx="${tx}" cy="${ty + 0.8}" rx="3.1" ry="3.6" fill="${padFill}"/>`;
    o += `<ellipse cx="${tx - 0.9}" cy="${ty - 0.6}" rx="0.9" ry="0.6" fill="#fff" opacity=".55"/>`;
  });
  o += `</g>`;
  // Krallen: fahren aus den Zehen nach oben, leicht gebogen, halb durchsichtig
  if (claw > 0.02) {
    const len = 7.5 * claw;
    TOES.forEach(([tx, ty], i) => {
      const bx = tx * sq * 1.02, by = ty - 4.4, bend = (i - 1.5) * 0.9;
      o += `<path d="M${bx - 1.1},${by + 0.6} Q${bx - 0.9 + bend * 0.3},${by - len * 0.65} ${bx + bend},${by - len} Q${bx + 0.6 + bend * 0.2},${by - len * 0.5} ${bx + 1.1},${by + 0.6} Z" fill="url(#claw)" stroke="rgba(0,0,0,.28)" stroke-width=".25"/>`;
    });
  }
  // Lichtkante (Volumen)
  o += `<path d="M-12.4,-4 C-12,-10 -8,-14 -3,-15" stroke="rgba(255,255,255,.16)" stroke-width="1" fill="none" stroke-linecap="round"/>`;
  return o + `</g>`;
}

/** Ein ganzes Bild als SVG (durchsichtiger Hintergrund – die App zeichnet das Fenster selbst) */
function frameSVG(name, t, px) {
  const seq = SEQUENCES[name], st = state(name, t);
  const scale = 1 + 0.32 * st.lean;
  const lean = `translate(50 100) scale(${scale}) translate(-50 -100)`;
  const bust = bustInner(seq.face);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${px}" height="${px}" viewBox="-60 -60 220 220">
  <defs>
    <clipPath id="win"><circle cx="50" cy="50" r="48.5"/></clipPath>
    <clipPath id="armclip"><circle cx="50" cy="50" r="49"/></clipPath>
    <clipPath id="head"><rect x="-100" y="-100" width="300" height="171"/></clipPath>
    <filter id="fur" x="-30%" y="-30%" width="160%" height="160%">
      <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="7" result="n"/>
      <feDisplacementMap in="SourceGraphic" in2="n" scale="1.7" xChannelSelector="R" yChannelSelector="G"/>
    </filter>
    <filter id="drop" x="-40%" y="-40%" width="180%" height="180%"><feDropShadow dx="1" dy="2.5" stdDeviation="2.4" flood-color="#000" flood-opacity=".38"/></filter>
    <filter id="soft" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="1.2" stdDeviation="1.4" flood-color="#000" flood-opacity=".2"/></filter>
    <linearGradient id="arm" x1="-12" y1="0" x2="12" y2="0" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#2c2c31"/><stop offset=".45" stop-color="#17171a"/><stop offset="1" stop-color="#08080a"/></linearGradient>
    <radialGradient id="pawShade" cx="-4" cy="-9" r="22" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#34343a"/><stop offset=".55" stop-color="#18181b"/><stop offset="1" stop-color="#0b0b0d"/></radialGradient>
    <radialGradient id="pad" cx="40%" cy="35%" r="70%"><stop offset="0" stop-color="#fdc4d1"/><stop offset="1" stop-color="#d97f97"/></radialGradient>
    <radialGradient id="padPressed" cx="45%" cy="40%" r="70%"><stop offset="0" stop-color="#fed6df"/><stop offset="1" stop-color="#e796aa"/></radialGradient>
    <linearGradient id="claw" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="#d9d6cf"/><stop offset="1" stop-color="#fbfaf6"/></linearGradient>
  </defs>
  <g clip-path="url(#win)"><g transform="${lean}">${bust}</g></g>
  <g filter="url(#soft)"><g transform="${lean}"><g clip-path="url(#head)">${bust}</g></g></g>
  ${st.visible ? `${st.pressed ? `<ellipse cx="${st.x}" cy="${st.y - 2 * st.s}" rx="${17 * st.s}" ry="${15 * st.s}" fill="rgba(255,255,255,.16)" filter="blur(2px)"/>` : ''}<g filter="url(#drop)" opacity="${st.alpha}">${pawSVG(st)}</g>` : ''}
</svg>`;
}

if (typeof module !== 'undefined') module.exports = { SEQUENCES, state, clawTips, frameSVG };
