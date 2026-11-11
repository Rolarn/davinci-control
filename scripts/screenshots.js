// Скриншоты панели для README из данных тестового стенда (tests/out). / Panel screenshots for README from bench data.
const { chromium } = require('playwright'); const fs = require('fs'), path = require('path');
const R = path.join(__dirname, '..'), OUT = path.join(R, 'docs', 'screenshots');
const J = JSON.parse(fs.readFileSync(path.join(R, 'tests/out/json.json'), 'utf8')), S = fs.readFileSync(path.join(R, 'tests/out/strings.json'), 'utf8');
J.daemon = true; J.ok.thermal = 'module'; J.drainAlert = [];
(async () => {
  const b = await chromium.launch();
  for (const lang of ['ru', 'en']) {
    const p = await b.newPage({ viewport: { width: 380, height: 780 }, deviceScaleFactor: 2, colorScheme: 'dark', locale: lang === 'en' ? 'en-US' : 'ru-RU' });
    const j = { ...J, conf: { ...J.conf, uiLang: lang } };
    await p.addInitScript(([j, s]) => { window.ksu = { exec(c, o, cb) { const a = c.split(' ')[2]; setTimeout(() => window[cb](0, a === 'strings' ? s : j, ''), 10); } }; }, [JSON.stringify(j), S]);
    await p.goto('file://' + path.join(R, 'module/webroot/index.html')); await p.waitForTimeout(1200);
    const sfx = lang === 'en' ? '.en' : '';
    await p.screenshot({ path: path.join(OUT, `panel-1${sfx}.png`) });
    for (const [n, id] of [[2, 'cCharge'], [3, 'cUse']]) {
      await p.evaluate(id => { document.getElementById('dock').style.display = 'none'; document.getElementById('ladder').style.display = 'none'; scrollTo(0, document.getElementById(id).offsetTop - 8); }, id);
      await p.waitForTimeout(400);
      await p.waitForTimeout(300); await p.screenshot({ path: path.join(OUT, `panel-${n}${sfx}.png`) });
    }
    await p.close();
  }
  await b.close(); console.log('screenshots:', fs.readdirSync(OUT).join(', '));
})();
