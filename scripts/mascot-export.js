// Готовые картинки маскота из исходников assets/mascot: SVG для README и релизов, PNG для превью и MMRL.
// Ready mascot images from assets/mascot sources: SVG for README and releases, PNG for previews and MMRL.
// node scripts/mascot-export.js   (нужен Playwright / needs Playwright)
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
const A = path.join(__dirname, '..', 'assets', 'mascot'), OUT = path.join(A, 'export');
fs.mkdirSync(OUT, { recursive: true });
const src = f => fs.readFileSync(path.join(A, f), 'utf8');
const CSS = src('mascot.css');

const VERSION = process.argv[2] || '1.0.0';
const jobs = {
  'readme-hero': { state: 'limit', hol: true },
  'feature-charging': { state: 'charging', hol: true },
  'feature-perf': { state: 'calm', deco: 'perf' },
  'feature-sun': { state: 'calm', deco: 'sun' },
  'feature-stats': { state: 'calm', deco: 'stats' },
  'feature-shield': { state: 'calm', deco: 'shield' },
  'faq': { state: 'calm', curious: true },
  'release-mascot': { state: 'limit', holiday: 'release' },
};

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1 });
  await p.setContent(`<html><head><style>${CSS}</style></head><body></body></html>`);
  await p.addScriptTag({ content: src('mascot.js') + '\n' + src('decor.js') });
  await p.addStyleTag({ content: await p.evaluate(() => DECO_CSS) });
  const svgs = await p.evaluate(jobs => {
    const out = {};
    for (const [name, j] of Object.entries(jobs)) {
      const m = makeMascot(j.state, 'blue');
      if (j.hol || j.deco || j.holiday) m.classList.add('hol');
      if (j.deco) DECO[j.deco](m);
      if (j.holiday) HOL[j.holiday].draw(m);
      if (j.curious) m.classList.add('ev-curious');
      document.body.appendChild(m);
      m.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
      m.removeAttribute('role');
      out[name] = m.outerHTML;
    }
    return out;
  }, jobs);
  const deco = await p.evaluate(() => DECO_CSS);
  // ev-curious в README: зацикливаем / loop the curious animation for README
  const loop = '.mascot.ev-curious .all, .mascot.ev-curious .eo, .mascot.ev-curious .p-q { animation-iteration-count: infinite !important; animation-duration: 3.2s !important }';
  for (const [name, svg] of Object.entries(svgs)) {
    const label = { 'readme-hero': 'Davinci Control mascot waving', 'feature-charging': 'Mascot charging', 'feature-perf': 'Mascot running with a speedometer', 'feature-sun': 'Mascot in sunglasses with the sun',
      'feature-stats': 'Mascot pointing at a chart', 'feature-shield': 'Mascot holding a shield', faq: 'Curious mascot', 'release-mascot': 'Mascot in a party hat' }[name];
    const s = svg.replace(/aria-label="[^"]*"/, `aria-label="${label}"`).replace('>', `><title>${label}</title><style>${CSS}\n${deco}\n${loop}</style>`);
    fs.writeFileSync(path.join(OUT, name + '.svg'), s);
  }
  // Баннер релиза 1280×400 / release banner
  const hat = svgs['release-mascot'].replace('<svg ', '<svg x="120" y="40" width="300" height="345" ');
  const banner = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1280 400" width="1280" height="400" role="img" aria-label="Davinci Control ${VERSION}">
<title>Davinci Control ${VERSION} — Первый релиз · First release</title>
<defs><radialGradient id="bg" cx="30%" cy="45%" r="80%"><stop offset="0" stop-color="#1b2740"/><stop offset="1" stop-color="#0a0d12"/></radialGradient></defs>
<style>${CSS}\n${deco}</style>
<rect width="1280" height="400" rx="24" fill="url(#bg)"/>
${hat.replace(/<svg ([^>]*)>/, (m, a) => `<svg ${a}>`)}
<text x="500" y="185" font-family="Segoe UI, Roboto, system-ui, sans-serif" font-size="68" font-weight="800" fill="#f8fafc">Davinci Control ${VERSION}</text>
<text x="502" y="245" font-family="Segoe UI, Roboto, system-ui, sans-serif" font-size="32" fill="#9fb3d1">Первый релиз · First release</text>
<text x="502" y="295" font-family="Segoe UI, Roboto, system-ui, sans-serif" font-size="24" fill="#6b7a90">Xiaomi Mi 9T / Redmi K20 (davinci)</text>
</svg>`;
  fs.writeFileSync(path.join(OUT, `release-${VERSION}.svg`), banner);

  // PNG: превью для соцсетей 1280×640, иконка 512, обложка MMRL 1024×500 / social preview, icon, MMRL cover
  const pngPage = async (w, h, html, file) => {
    const q = await b.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
    await q.setContent(`<html><head><style>html,body{margin:0;width:${w}px;height:${h}px;overflow:hidden;font-family:Segoe UI,Roboto,system-ui,sans-serif}</style></head><body>${html}</body></html>`);
    await q.waitForTimeout(300); await q.screenshot({ path: path.join(OUT, file) }); await q.close();
  };
  const still = s => s.replace('<style>', '<style>*{animation:none!important}');
  const hero = still(fs.readFileSync(path.join(OUT, 'readme-hero.svg'), 'utf8'));
  await pngPage(1280, 640, `<div style="width:1280px;height:640px;background:radial-gradient(circle at 30% 45%,#1b2740,#0a0d12 75%);display:flex;align-items:center;gap:40px;padding:0 90px;box-sizing:border-box">
    <div style="width:360px;flex:none">${hero.replace('<svg ', '<svg style="width:360px;height:auto" ')}</div>
    <div><div style="color:#f8fafc;font-size:76px;font-weight:800">Davinci Control</div>
    <div style="color:#9fb3d1;font-size:30px;margin-top:10px">Зарядка, производительность и яркость<br>Charging, performance and brightness</div>
    <div style="color:#6b7a90;font-size:26px;margin-top:22px">Magisk-модуль · Magisk module · Xiaomi Mi 9T / Redmi K20 (davinci)</div></div></div>`, 'social-preview.png');
  await pngPage(512, 512, `<div style="width:512px;height:512px;background:radial-gradient(circle at 50% 40%,#22324f,#0a0d12 75%);display:grid;place-items:center">${hero.replace('<svg ', '<svg style="width:400px;height:auto" ')}</div>`, 'icon.png');
  await pngPage(1024, 500, `<div style="width:1024px;height:500px;background:radial-gradient(circle at 30% 45%,#1b2740,#0a0d12 75%);display:flex;align-items:center;gap:30px;padding:0 70px;box-sizing:border-box">
    <div style="width:300px;flex:none">${hero.replace('<svg ', '<svg style="width:300px;height:auto" ')}</div>
    <div><div style="color:#f8fafc;font-size:60px;font-weight:800">Davinci Control</div><div style="color:#9fb3d1;font-size:26px;margin-top:8px">Mi 9T / Redmi K20 (davinci)</div></div></div>`, 'cover.png');
  await b.close();
  console.log('mascot export: ' + fs.readdirSync(OUT).join(', '));
})();
