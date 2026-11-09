// Панель в браузере: ответы root берутся с тестового стенда (tests/out/*.json).
// Panel in a browser: root answers come from the test bench (tests/out/*.json).
// node tests/panel.js [папка для скриншотов / screenshot dir]
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
const OUT = path.join(__dirname, 'out'), SHOTS = process.argv[2] || OUT;
const page_ = 'file://' + path.join(__dirname, '..', 'module', 'webroot', 'index.html');
const J = JSON.parse(fs.readFileSync(path.join(OUT, 'json.json'), 'utf8'));
const S = fs.readFileSync(path.join(OUT, 'strings.json'), 'utf8');
let bad = 0; const fail = m => { console.log('  ✗ ' + m); bad++; }, ok = m => console.log('  ✓ ' + m);

(async () => {
  const b = await chromium.launch();
  for (const [w, lang] of [[400, 'ru'], [400, 'en'], [1000, 'ru']]) {
    const p = await b.newPage({ viewport: { width: w, height: 860 }, locale: lang === 'en' ? 'en-US' : 'ru-RU' });
    const errs = []; p.on('pageerror', e => errs.push(e.message)); p.on('console', m => m.type() === 'error' && errs.push(m.text()));
    const j = JSON.parse(JSON.stringify(J)); j.conf.uiLang = lang;
    await p.addInitScript(([json, strings]) => {
      window.__calls = [];
      window.ksu = { exec(cmd, opts, cb) {
        window.__calls.push(cmd);
        const a = cmd.split(' ')[2], out = a === 'json' || a === 'live' ? json : a === 'strings' ? strings : a === 'changelog' ? '1.0.0\tПервый публичный релиз\tFirst public release' : a === 'logs' ? 'log text' : '';
        setTimeout(() => window[cb](0, out, ''), 30);
      } };
    }, [JSON.stringify(j), S]);
    await p.goto(page_); await p.waitForTimeout(900);
    const tag = `${w}_${lang}`;
    if (errs.length) fail(`${tag}: ошибки JS / JS errors: ${errs.join(' | ')}`); else ok(`${tag}: без ошибок JS / no JS errors`);
    const ov = await p.evaluate(() => document.documentElement.scrollWidth - innerWidth);
    if (ov > 0) fail(`${tag}: горизонтальная прокрутка / horizontal overflow ${ov}px`); else ok(`${tag}: нет горизонтальной прокрутки / no overflow`);
    if (lang === 'en') {
      const cyr = await p.evaluate(() => { const r = []; const tw = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); let n; while ((n = tw.nextNode())) { const s = n.textContent.trim(); if (/[А-Яа-яЁё]/.test(s) && s !== 'Русский' && n.parentElement.closest('[hidden]') === null) r.push(s); } return r; });
      if (cyr.length) fail(`${tag}: русский текст в английской панели / Russian text in English panel: ${cyr.slice(0, 5).join(' | ')}`); else ok(`${tag}: весь текст на английском / all text in English`);
    }
    const qs = await p.locator('.q').count();
    if (qs >= 18) ok(`${tag}: подсказок «?»: ${qs}`); else fail(`${tag}: мало «?»: ${qs}`);
    await p.screenshot({ path: path.join(SHOTS, `panel_${tag}.png`), fullPage: true });
    if (w === 400) {
      // «?»: подсказка у кнопки и реакция маскота / help popover at the button and mascot reaction
      await p.evaluate(() => document.querySelector('[data-help="h_mode"]').scrollIntoView({ block: 'center' }));
      await p.waitForTimeout(3600);
      await p.evaluate(() => document.querySelector('[data-help="h_mode"]').click()); await p.waitForTimeout(450);
      const pos = await p.evaluate(() => { const q = document.querySelector('[data-help="h_mode"]').getBoundingClientRect(), pp = document.getElementById('pop').getBoundingClientRect(), a = document.getElementById('popA').getBoundingClientRect();
        return { on: document.getElementById('pop').classList.contains('on'), near: Math.abs(pp.top - q.bottom) < 20 || Math.abs(pp.bottom - q.top) < 20, arrow: Math.abs((a.left + a.width / 2) - (q.left + q.width / 2)), curious: !!document.querySelector('svg.mascot.ev-curious') }; });
      if (pos.on && pos.near && pos.arrow < 8) ok(`${tag}: подсказка у кнопки, стрелка на «?» / popover anchored`); else fail(`${tag}: подсказка не у кнопки / popover misplaced ${JSON.stringify(pos)}`);
      if (pos.curious) ok(`${tag}: маскот реагирует на «?» / mascot reacts`); else fail(`${tag}: нет реакции маскота / no mascot reaction`);
      await p.screenshot({ path: path.join(SHOTS, `panel_${tag}_help.png`) });
      await p.click('#popOk'); await p.waitForTimeout(300);
      const dock = await p.evaluate(() => document.getElementById('dock').classList.contains('on'));
      if (dock) ok(`${tag}: маскот спустился в угол / mascot docked`); else fail(`${tag}: маскот не в углу / mascot not docked`);
      // применение настройки / applying a setting
      await p.evaluate(() => document.querySelector('#mode button[data-v="care"]').click()); await p.waitForTimeout(400);
      const called = await p.evaluate(() => window.__calls.some(c => c.endsWith('chgmode care')));
      if (called) ok(`${tag}: команда режима отправлена / mode command sent`); else fail(`${tag}: команда режима не ушла / mode command not sent`);
    }
    await p.close();
  }
  await b.close();
  console.log(bad ? `panel: ${bad} FAILED` : 'panel: OK');
  process.exit(bad ? 1 : 0);
})();
