// Rüdiger – Figur aus Einzelteilen (Stil nach Vorlage). Koordinaten: Glasblase 100 × 100, Mitte 50/50.
// Alles hier ist reine Zeichnung; die Bewegungen stehen in sprites.js.
const OUT = '#050506', FUR = '#151518', FUR2 = '#2a2a31', PINK = '#f48aa0';
let UID = 0;
const f2 = v => (+v).toFixed(2);

function fluffy(cx, cy, rx, ry, tufts, step = 2) {
  const pts = [];
  for (let a = 0; a < 360; a += step) {
    let r = 1;
    for (const [from, to, amp, period = 14] of tufts) {
      if (a >= from && a <= to) r += amp * Math.pow(Math.abs(Math.sin((a - from) * Math.PI / period)), 4) / Math.max(rx, ry);
    }
    const rad = a * Math.PI / 180;
    pts.push([cx + Math.cos(rad) * rx * r, cy + Math.sin(rad) * ry * r]);
  }
  return 'M' + pts.map(p => f2(p[0]) + ',' + f2(p[1])).join(' L') + ' Z';
}

function defs() {
  return `<radialGradient id="headShade" cx="50" cy="38" r="42" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="${FUR2}"/><stop offset="1" stop-color="${FUR}"/></radialGradient>
  <radialGradient id="iris" cx="45%" cy="62%" r="66%"><stop offset="0" stop-color="#ffec94"/><stop offset=".55" stop-color="#ffc828"/><stop offset="1" stop-color="#e08600"/></radialGradient>
  <radialGradient id="irisAngry" cx="45%" cy="62%" r="66%"><stop offset="0" stop-color="#ffd36a"/><stop offset=".55" stop-color="#f6a019"/><stop offset="1" stop-color="#cf5d00"/></radialGradient>
  <radialGradient id="pad" cx="40%" cy="35%" r="70%"><stop offset="0" stop-color="#ffb3c2"/><stop offset="1" stop-color="#e3708a"/></radialGradient>
  <linearGradient id="claw" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="#dcd7cc"/><stop offset="1" stop-color="#fffdf7"/></linearGradient>
  <linearGradient id="armShade" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#2d2d34"/><stop offset=".5" stop-color="${FUR}"/><stop offset="1" stop-color="#0a0a0c"/></linearGradient>`;
}

// ---------- Teile ----------

function ear(left, angle) {
  const m = left ? x => x : x => 100 - x;
  const base = left ? [32, 40] : [68, 40];
  const P = (pts) => pts.map(([x, y]) => `${f2(m(x))},${f2(y)}`);
  const outer = P([[20, 47], [13, 32], [11, 16], [15, 5], [17, 2], [21, 1.6], [24, 4], [32, 10], [40, 19], [46, 30]]);
  const inner = P([[22, 41], [17, 30], [16, 18], [18.5, 9], [26, 13], [33, 20], [39, 30]]);
  const t1 = P([[21, 38], [24, 32.5], [28, 30]]), t2 = P([[22.5, 42], [26.5, 37], [31.5, 35.5]]), t3 = P([[20, 31], [22, 26], [25, 23.5]]);
  return `<g transform="rotate(${angle * (left ? -1 : 1)} ${base[0]} ${base[1]})">
    <path d="M${outer[0]} C${outer[1]} ${outer[2]} ${outer[3]} C${outer[4]} ${outer[5]} ${outer[6]} C${outer[7]} ${outer[8]} ${outer[9]} Z" fill="${FUR}" stroke="${OUT}" stroke-width="1.4" stroke-linejoin="round"/>
    <path d="M${inner[0]} C${inner[1]} ${inner[2]} ${inner[3]} C${inner[4]} ${inner[5]} ${inner[6]} Z" fill="${PINK}"/>
    <path d="M${t1[0]} Q${t1[1]} ${t1[2]} M${t2[0]} Q${t2[1]} ${t2[2]} M${t3[0]} Q${t3[1]} ${t3[2]}" stroke="#f6e6ea" stroke-width="1" fill="none" stroke-linecap="round" opacity=".9"/>
  </g>`;
}

/** Auge. o: look [x,y], lid 0…1 (oben), low 0…1 (unten), slant (+ = innen tiefer), closed, pupil, angry */
function eye(cx, cy, side, o) {
  const id = 'e' + (UID++);
  if (o.closed === 'happy') return `<path d="M${cx - 8},${cy + 2} Q${cx},${cy - 7} ${cx + 8},${cy + 2}" stroke="${OUT}" stroke-width="2.6" fill="none" stroke-linecap="round"/><path d="M${cx - 6.8},${cy + 1.4} Q${cx},${cy - 4.8} ${cx + 6.8},${cy + 1.4}" stroke="#f3b51c" stroke-width="1.1" fill="none" stroke-linecap="round"/>`;
  if (o.closed === 'sleep') return `<path d="M${cx - 8},${cy + 1} Q${cx},${cy + 6.5} ${cx + 8},${cy + 1}" stroke="#9a9c92" stroke-width="2" fill="none" stroke-linecap="round"/>`;
  const rx = 9.6, ry = 10.8, look = o.look || [0, 0];
  const lid = Math.min(Math.max(o.lid || 0, 0), 1), low = o.low || 0, slant = (o.slant || 0) * side;
  const top = cy - ry, h = 2 * ry;
  const lidY = top + lid * h, inner = slant, outer = -slant;     // innen = zur Nase hin
  const xi = cx + side * rx, xo = cx - side * rx;                 // side 1 = linkes Auge (innen rechts)
  const pw = o.pupil === 'slit' ? 1.6 : (o.pupil === 'round' ? 5 : 3.5), ph = o.pupil === 'round' ? 7.6 : 7.8;
  let s = `<defs><clipPath id="${id}"><ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}"/></clipPath></defs>
  <ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="url(#${o.angry ? 'irisAngry' : 'iris'})"/>
  <g clip-path="url(#${id})">
    <ellipse cx="${f2(cx + look[0])}" cy="${f2(cy + 0.6 + look[1])}" rx="${pw}" ry="${ph}" fill="#0b0b0c"/>
    <circle cx="${f2(cx + look[0] * 0.6 + 3)}" cy="${f2(cy - 4.2 + look[1] * 0.5)}" r="2.7" fill="#fff"/>
    <circle cx="${f2(cx + look[0] * 0.6 - 2.6)}" cy="${f2(cy + 4.6 + look[1] * 0.5)}" r="1.2" fill="#fff" opacity=".85"/>`;
  if (lid > 0.01) s += `<polygon points="${xo},${top - 4} ${xi},${top - 4} ${xi},${f2(lidY + inner)} ${xo},${f2(lidY + outer)}" fill="${FUR}"/>
    <line x1="${xo}" y1="${f2(lidY + outer)}" x2="${xi}" y2="${f2(lidY + inner)}" stroke="${OUT}" stroke-width="1.6"/>`;
  if (low > 0.01) { const ly = cy + ry - low * h; s += `<polygon points="${xo},${cy + ry + 4} ${xi},${cy + ry + 4} ${xi},${f2(ly)} ${xo},${f2(ly + 1)}" fill="${FUR}"/><line x1="${xo}" y1="${f2(ly + 1)}" x2="${xi}" y2="${f2(ly)}" stroke="${OUT}" stroke-width="1.2"/>`; }
  s += `</g><ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="none" stroke="${OUT}" stroke-width="1.3"/>`;
  return s;
}

function brows(kind, raise = 0) {
  if (!kind) return '';
  // traurig / betröppelt: innen oben, außen unten
  if (kind === 'sad') return `<g stroke="${OUT}" stroke-width="2.4" stroke-linecap="round" fill="none">
    <path d="M28.5,${43 - raise} Q37,${41.5 - raise} 45.5,${38 - raise}"/>
    <path d="M71.5,${43 - raise} Q63,${41.5 - raise} 54.5,${38 - raise}"/></g>`;
  // genervt: gerade, innen leicht tiefer, kräftig · wütend: steil nach innen
  const d = kind === 'angry' ? 5 : 2.4;
  return `<g stroke="${OUT}" stroke-width="2.4" stroke-linecap="round" fill="none">
    <path d="M28.5,${41 - raise} Q37,${40 - raise} 45.5,${41 + d - raise}"/>
    <path d="M71.5,${41 - raise * (kind === 'oneUp' ? 3 : 1)} Q63,${40 - raise} 54.5,${41 + d - raise}"/></g>`;
}

function mouth(kind) {
  switch (kind) {
    case 'flat': return `<path d="M45.5,69 Q50,68.4 54.5,69" stroke="${OUT}" stroke-width="1.2" fill="none" stroke-linecap="round"/>`;
    case 'side': return `<path d="M44.5,70.2 Q48.5,68.2 55.5,68.8" stroke="${OUT}" stroke-width="1.3" fill="none" stroke-linecap="round"/><path d="M55.2,68.6 l1.4,-0.9" stroke="${OUT}" stroke-width="1" stroke-linecap="round"/>`;
    case 'fang': return `<path d="M44,68.5 Q47,74.5 50,69.5 Q53,74.5 56,68.5 Q55,72.8 50,73.8 Q45,72.8 44,68.5 Z" fill="#e8687f" stroke="${OUT}" stroke-width=".8"/><path d="M45.6,69.3 l1,2.6 l1,-2.2 Z M54.4,69.3 l-1,2.6 l-1,-2.2 Z" fill="#fff"/>`;
    case 'hiss': return `<path d="M43,68 Q50,80 57,68 Q50,71 43,68 Z" fill="#c9465f" stroke="${OUT}" stroke-width=".9"/><path d="M45,68.6 l1.2,3.2 l1.2,-2.6 Z M55,68.6 l-1.2,3.2 l-1.2,-2.6 Z" fill="#fff"/>`;
    case 'wide': return `<path d="M43,67.5 Q43,79.5 50,80 Q57,79.5 57,67.5 Q50,70.5 43,67.5 Z" fill="#b8344f" stroke="${OUT}" stroke-width="1"/>
      <path d="M45.2,75.6 Q50,72.6 54.8,75.6 Q53.6,79 50,79.2 Q46.4,79 45.2,75.6 Z" fill="#f06d88"/>
      <path d="M44.6,68.4 l1.1,2.8 l1.1,-2.3 Z M55.4,68.4 l-1.1,2.8 l-1.1,-2.3 Z" fill="#fff"/>`;
    case 'frown': return `<path d="M45,71.5 Q50,66.6 55,71.5" stroke="${OUT}" stroke-width="1.3" fill="none" stroke-linecap="round"/>`;
    case 'chatter': return `<path d="M43.5,69.5 l2.1,2.2 l2.1,-2.2 l2.1,2.2 l2.1,-2.2 l2.1,2.2 l2.1,-2.2 l2.1,2.2" stroke="${OUT}" stroke-width="1.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>`;
    case 'chew': return `<path d="M44.5,69 Q46.5,71.2 48.5,69.4 Q50.5,71.6 52.5,69.4 Q54.5,71.2 56,69" stroke="${OUT}" stroke-width="1.2" fill="none" stroke-linecap="round"/>`;
    case 'blep': return `<path d="M47.6,69.2 Q47.4,75.2 50,75.6 Q52.6,75.2 52.4,69.2 Z" fill="#f06d88" stroke="${OUT}" stroke-width=".8"/><path d="M50,70 v3.6" stroke="#c84a64" stroke-width=".6" stroke-linecap="round"/>
      <path d="M45.5,68 Q47.8,70.6 50,68.2 Q52.2,70.6 54.5,68" stroke="${OUT}" stroke-width="1.1" fill="none" stroke-linecap="round"/>`;
    default: return `<path d="M45.5,68 Q47.8,70.6 50,68.2 Q52.2,70.6 54.5,68" stroke="${OUT}" stroke-width="1.1" fill="none" stroke-linecap="round"/>`;
  }
}

function headSVG(p) {
  let s = ear(true, p.earL || 0) + ear(false, p.earR || 0);
  const bristle = p.bristle ? 2.2 : 1;
  const puff = p.cheeks || 0;
  const furTufts = p.fur > 0 ? [[0, 360, 8.5 * p.fur, 10]] : [];
  s += `<path d="${fluffy(50, 53 + puff * 0.6, 33 + puff * 2.2, 27.5 + puff * 0.6, [[146, 214, 2.6 * bristle], [326, 358, 2.6 * bristle], [0, 34, 2.6 * bristle], [242, 298, 1.5 * bristle * 1.4], [200, 340, p.bristle ? 2.2 : 0, 9], ...furTufts])}" fill="url(#headShade)" stroke="${OUT}" stroke-width="1.5" stroke-linejoin="round"/>`;
  const eo = { look: p.look, lid: p.lid, low: p.low, slant: p.slant, closed: p.closed, pupil: p.pupil, angry: p.angryEyes };
  s += eye(37.5, 54, 1, eo) + eye(62.5, 54, -1, eo);
  s += brows(p.brows, p.browRaise || 0);
  s += `<path d="M47.6,64 Q50,62.8 52.4,64 Q51.4,66 50,66.6 Q48.6,66 47.6,64 Z" fill="${PINK}" stroke="${OUT}" stroke-width=".5"/>`;
  s += mouth(p.mouth);
  s += `<g stroke="#dadadd" stroke-width=".55" stroke-linecap="round" opacity=".9" fill="none">
    <path d="M30,64 Q18,61 6,60"/><path d="M30,66.5 Q18,66.5 7,68"/><path d="M31,69 Q20,71 10,75"/>
    <path d="M70,64 Q82,61 94,60"/><path d="M70,66.5 Q82,66.5 93,68"/><path d="M69,69 Q80,71 90,75"/></g>`;
  s += `<path d="M36,31 Q50,25.5 64,31" stroke="rgba(255,255,255,.09)" stroke-width="3" fill="none" stroke-linecap="round"/>`;
  return s;
}

function bodySVG(p = {}) {
  return `<path d="${fluffy(50, 98, 37, 24, [[180, 360, 1.2, 10], ...(p.fur > 0 ? [[180, 360, 6 * p.fur, 10]] : [])])}" fill="${FUR}" stroke="${OUT}" stroke-width="1.4"/>`;
}

function rimPaw(cx, cy, s = 1) {
  return `<g transform="translate(${f2(cx)} ${f2(cy)}) scale(${s})">
    <path d="${fluffy(0, 0, 10, 7, [[200, 340, 1.1, 12]])}" fill="${FUR2}" stroke="${OUT}" stroke-width="1.2"/>
    <path d="M-3.4,-0.5 v4 M0.2,-1.2 v4.5 M3.8,-0.5 v4" stroke="#44444c" stroke-width="1" stroke-linecap="round"/></g>`;
}

/** Erhobene Pfote, Ballen zum Betrachter, Krallen oben */
function raisedPaw(x, y, rot, s, claws) {
  let o = `<g transform="translate(${f2(x)} ${f2(y)}) rotate(${f2(rot)}) scale(${f2(s)})">
    <path d="${fluffy(0, 0, 11.5, 10.5, [[190, 350, 1.3, 12]])}" fill="${FUR}" stroke="${OUT}" stroke-width="1.3"/>
    <path d="M-6,3.5 C-7.5,0 -5,-3 -2.5,-2.2 C-1.4,-4.2 1.4,-4.2 2.5,-2.2 C5,-3 7.5,0 6,3.5 C4.5,6.2 -4.5,6.2 -6,3.5 Z" fill="url(#pad)" stroke="${OUT}" stroke-width=".6"/>
    <ellipse cx="-1.6" cy="-0.6" rx="1.6" ry=".8" fill="#fff" opacity=".45"/>`;
  [[-7.4, -5.8], [-2.6, -9], [2.6, -9], [7.4, -5.8]].forEach(([tx, ty]) => {
    o += `<ellipse cx="${tx}" cy="${ty}" rx="2.5" ry="2.9" fill="url(#pad)" stroke="${OUT}" stroke-width=".5"/>`;
    if (claws > 0.02) o += `<path d="M${tx - 1},${ty - 2.4} Q${f2(tx - 0.6)},${f2(ty - 2.4 - 5 * claws)} ${f2(tx + 1.2)},${f2(ty - 2.6 - 6.5 * claws)} Q${f2(tx + 0.9)},${f2(ty - 3 - 3 * claws)} ${tx + 1},${ty - 2.4} Z" fill="url(#claw)" stroke="${OUT}" stroke-width=".45"/>`;
  });
  return o + `</g>`;
}

/** Arm von der Schulter zur Pfote, Ellbogen leicht nach außen */
function armSVG(sx, sy, px, py, w0 = 10, w1 = 7.5, bendDir = 1) {
  const dx = px - sx, dy = py - sy, L = Math.hypot(dx, dy) || 1, nx = -dy / L, ny = dx / L;
  const c = [(sx + px) / 2 + nx * 5 * bendDir, (sy + py) / 2 + ny * 5 * bendDir];
  const A = [], B = [];
  for (let i = 0; i <= 24; i++) {
    const q = i / 24, x = (1 - q) ** 2 * sx + 2 * (1 - q) * q * c[0] + q * q * px, y = (1 - q) ** 2 * sy + 2 * (1 - q) * q * c[1] + q * q * py;
    const tx = 2 * (1 - q) * (c[0] - sx) + 2 * q * (px - c[0]), ty = 2 * (1 - q) * (c[1] - sy) + 2 * q * (py - c[1]), tl = Math.hypot(tx, ty) || 1;
    const w = w0 + (w1 - w0) * q + Math.sin(q * Math.PI) * 1.2;
    A.push([x - ty / tl * w, y + tx / tl * w]); B.push([x + ty / tl * w, y - tx / tl * w]);
  }
  return `<path d="M${[...A, ...B.reverse()].map(p => f2(p[0]) + ',' + f2(p[1])).join(' L')} Z" fill="url(#armShade)" stroke="${OUT}" stroke-width="1.3"/>`;
}

function heart(x, y, s, o) {
  return `<path opacity="${f2(o)}" fill="#ff6f8c" stroke="${OUT}" stroke-width=".6" d="M${x},${y + s * .35} C${x - s * .15},${y + s * .1} ${x - s * .5},${y + s * .15} ${x - s * .5},${y - s * .15} A${s * .25},${s * .25} 0 0 1 ${x},${y - s * .15} A${s * .25},${s * .25} 0 0 1 ${x + s * .5},${y - s * .15} C${x + s * .5},${y + s * .15} ${x + s * .15},${y + s * .1} ${x},${y + s * .35} Z"/>`;
}

/** Glas vorne: Rand und Lichtreflexe (liegt über dem, was IN der Blase ist) */
function glassFront() {
  return `<circle cx="50" cy="50" r="47.6" fill="none" stroke="rgba(255,255,255,.72)" stroke-width="1.6"/>
  <path d="M17,31 Q25,14 43,7.5" stroke="rgba(255,255,255,.78)" stroke-width="2.6" fill="none" stroke-linecap="round"/>
  <path d="M13,41 Q13.8,37 15.4,33.6" stroke="rgba(255,255,255,.6)" stroke-width="1.7" fill="none" stroke-linecap="round"/>
  <path d="M84,74 Q80,81 73,86" stroke="rgba(255,255,255,.22)" stroke-width="1.6" fill="none" stroke-linecap="round"/>`;
}

/**
 * Ganzes Bild. p = Pose (siehe sprites.js). wide = Gestenbild (Teile ragen aus der Blase).
 * Ebenen: Katze in der Blase → Glas vorne → was aus der Blase ragt (Kopf/Ohren/Arm) → Effekte.
 * Die Blase selbst (Glasfarbe, Leuchten) zeichnet die App darunter.
 */
function frameSVG(p, px, span) {
  const wide = span > 1;
  const id = 'f' + (UID++);
  const T = `translate(50 100) scale(${f2(p.sc || 1)}) translate(-50 -100) translate(${f2(p.dx || 0)} ${f2(p.dy || 0)}) rotate(${f2(p.rot || 0)} 50 74)`;
  const H = `translate(0 ${f2(p.headDy || 0)}) rotate(${f2(p.headTilt || 0)} 50 74)`;
  const cat = `${bodySVG(p)}<g transform="${H}">${headSVG(p)}</g>`;
  const half = 50 * span, view = `${50 - half} ${50 - half} ${2 * half} ${2 * half}`;
  let s = `<svg xmlns="http://www.w3.org/2000/svg" width="${px}" height="${px}" viewBox="${view}"><defs>${defs()}
    <clipPath id="${id}in"><circle cx="50" cy="50" r="47.4"/></clipPath>
    <clipPath id="${id}rim"><circle cx="50" cy="50" r="51"/></clipPath>
    <mask id="${id}out"><rect x="-100" y="-100" width="400" height="400" fill="#fff"/><circle cx="50" cy="50" r="47.4" fill="#000"/></mask>
    <clipPath id="${id}head"><rect x="-100" y="-120" width="300" height="196"/></clipPath>
    <filter id="${id}sh" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="1.4" stdDeviation="1.4" flood-color="#000" flood-opacity=".3"/></filter></defs>`;
  if (p.marksBehind) s += p.marksBehind;
  if (!p.hidden) {
    // 1. in der Blase
    s += `<g clip-path="url(#${id}in)"><g transform="${T}">${cat}</g></g>`;
    // 2. Glas vorne
    s += glassFront();
    // 3. Pfoten auf dem Rand (vor dem Glas)
    let paws = '';
    if (p.rimL !== false) paws += rimPaw(p.rimLx || 33, p.rimLy || 85, 1.05);
    if (p.rimR !== false) paws += rimPaw(p.rimRx || 67, p.rimRy || 85, 1.05);
    s += `<g clip-path="url(#${id}rim)"><g transform="${T}">${paws}</g></g>`;
    // 4. was aus der Blase ragt (vor Glas und Rand)
    if (wide) s += `<g mask="url(#${id}out)" filter="url(#${id}sh)"><g transform="${T}"><g clip-path="url(#${id}head)"><g transform="${H}">${headSVG(p)}</g></g></g></g>`;
    // 5. winkende Pfote / Arm
    if (p.wave) s += `<g transform="${T}">${armSVG(36, 86, p.wave.x, p.wave.y + 7, 8.5, 6.8, -1)}${raisedPaw(p.wave.x, p.wave.y, p.wave.rot, 0.82, 0)}</g>`;
    if (p.arm) s += `<g transform="${T}" filter="url(#${id}sh)">${armSVG(64, 84, p.arm.x - 4, p.arm.y + 8)}${raisedPaw(p.arm.x, p.arm.y, p.arm.rot, p.arm.s || 1, p.arm.claws || 0)}</g>`;
  }
  if (p.fx) s += p.fx;
  return s + `</svg>`;
}

if (typeof module !== 'undefined') module.exports = { frameSVG, heart };
