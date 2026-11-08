// Rendert alle Sequenzen nach Resources/Sprites/<name>/NNNN.png + <name>.json
//   node tools/sprites/render.js [name …]
const fs = require('fs'), path = require('path');
const { chromium } = require('playwright');

(async () => {
  const dir = __dirname, out = path.join(dir, '..', '..', 'Resources', 'Sprites');
  const only = process.argv.slice(2);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 600, height: 600 }, deviceScaleFactor: 1 });
  await page.setContent(`<html><body style="margin:0;background:transparent"><div id="f"></div>
    <script>${fs.readFileSync(path.join(dir, 'rig.js'), 'utf8')}</script>
    <script>${fs.readFileSync(path.join(dir, 'sprites.js'), 'utf8')}</script></body></html>`);
  const names = await page.evaluate(() => Object.keys(SEQUENCES));
  for (const name of names) {
    if (only.length && !only.includes(name)) continue;
    const info = await page.evaluate(n => { const s = SEQUENCES[n]; return { duration: s.duration, fps: s.fps, loop: !!s.loop, wide: !!s.wide, catUntil: s.catUntil || s.duration }; }, name);
    const span = info.wide ? 2.2 : 1.3;
    const px = info.wide ? 440 : 320;
    const n = Math.round(info.duration * info.fps);
    const seqDir = path.join(out, name);
    fs.rmSync(seqDir, { recursive: true, force: true });
    fs.mkdirSync(seqDir, { recursive: true });
    for (let i = 0; i < n; i++) {
      await page.evaluate(([name, t, px, span]) => { document.getElementById('f').innerHTML = frameSVG(SEQUENCES[name].pose(t), px, span); }, [name, i / info.fps, px, span]);
      await page.locator('#f svg').screenshot({ path: path.join(seqDir, String(i).padStart(4, '0') + '.png'), omitBackground: true });
    }
    fs.writeFileSync(path.join(out, name + '.json'), JSON.stringify({ fps: info.fps, frames: n, loop: info.loop, span, catUntil: info.catUntil }));
    console.log(name, n, 'Bilder');
  }
  await browser.close();
})();
