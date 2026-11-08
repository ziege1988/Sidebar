// Rendert Rüdigers Sprites nach Resources/Sprites/<name>/NNNN.png und <name>.json
//   node tools/sprites/render.js
const fs = require('fs'), path = require('path');
const { chromium } = require('playwright');
const FPS = 30, PX = 440, SPAN = 220; // Bildbreite in Pixeln, 220 Rüdiger-Einheiten

(async () => {
  const dir = __dirname, out = path.join(dir, '..', '..', 'Resources', 'Sprites');
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: PX, height: PX }, deviceScaleFactor: 1 });
  await page.setContent(`<html><body style="margin:0;background:transparent"><div id="f"></div>
    <script>${fs.readFileSync(path.join(dir, 'rudi.js'), 'utf8')}</script>
    <script>${fs.readFileSync(path.join(dir, 'sprites.js'), 'utf8')}</script></body></html>`);
  for (const name of ['scratch', 'flick']) {
    const seqDir = path.join(out, name);
    fs.rmSync(seqDir, { recursive: true, force: true });
    fs.mkdirSync(seqDir, { recursive: true });
    const meta = await page.evaluate(([name, FPS]) => {
      const seq = SEQUENCES[name], n = Math.round(seq.duration * FPS), frames = [];
      for (let i = 0; i < n; i++) {
        const t = i / FPS, st = state(name, t);
        const dragging = seq.drags.some(([a, b]) => t >= a && t <= b);
        frames.push(dragging ? clawTips(st).map(([x, y]) => [+((x + 60) / 220).toFixed(4), +((y + 60) / 220).toFixed(4)]) : null);
      }
      return { frames: n, claws: frames };
    }, [name, FPS]);
    for (let i = 0; i < meta.frames; i++) {
      await page.evaluate(([name, t, PX]) => { document.getElementById('f').innerHTML = frameSVG(name, t, PX); }, [name, i / FPS, PX]);
      await page.locator('#f svg').screenshot({ path: path.join(seqDir, String(i).padStart(4, '0') + '.png'), omitBackground: true });
    }
    fs.writeFileSync(path.join(out, name + '.json'), JSON.stringify({ fps: FPS, span: SPAN / 100, frames: meta.frames, claws: meta.claws }));
    console.log(name, meta.frames, 'Bilder');
  }
  await browser.close();
})();
