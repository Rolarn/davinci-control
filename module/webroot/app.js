// Davinci Control — панель (WebUI по стандарту KernelSU: ksu.exec). Без библиотек.
// Davinci Control panel (KernelSU WebUI standard: ksu.exec). No libraries.
'use strict';
const T = '/data/adb/modules/davinci-control/tune.sh';
const $ = id => document.getElementById(id);
const POLL = 5000, FULL_EVERY = 30000;
let cbn = 0, inflight = 0, data = null, lastOk = 0, lastFull = 0, emaW = null, STR = {};
let LANG = (() => { try { return localStorage.getItem('dc.lang') || ''; } catch (e) { return ''; } })() || ((navigator.language || '').startsWith('ru') ? 'ru' : 'en');
const pending = {};

// ---------- язык / language ----------
function t(key, ...a) {
  let s = (I18N[LANG] && I18N[LANG][key]) ?? I18N.en[key] ?? key;
  a.forEach((v, i) => { s = s.split('{' + (i + 1) + '}').join(v); });
  return s;
}
const dec = (v, n) => { const s = Number(v).toFixed(n); return LANG === 'ru' ? s.replace('.', ',') : s; };
function msg(code, args) {  // сообщение бэкенда по коду / backend message by code
  const m = STR[code]; let s = m ? m[LANG === 'en' ? 1 : 0] : code;
  (args || []).forEach((v, i) => { if (LANG === 'ru' && /^-?\d+\.\d+$/.test(v)) v = v.replace('.', ','); s = s.split('{' + (i + 1) + '}').join(v); });
  return s;
}
function applyLang() {
  document.documentElement.lang = LANG;
  document.querySelectorAll('[data-t]').forEach(e => { e.textContent = t(e.dataset.t); });
  document.querySelectorAll('[data-label]').forEach(e => e.setAttribute('aria-label', t(e.dataset.label)));
  document.querySelectorAll('.q').forEach(e => e.setAttribute('aria-label', t('help')));
  document.querySelectorAll('svg.mascot').forEach(m => m.setAttribute('aria-label', t('mascot')));
  buildControls();
  if (data) render(data);
}
function setLang(l) {
  const n = l === 'auto' ? ((navigator.language || '').startsWith('ru') ? 'ru' : 'en') : l;
  if (n !== LANG) { LANG = n; try { localStorage.setItem('dc.lang', n); } catch (e) { /* нет хранилища */ } applyLang(); }
}

// ---------- связь с root / root bridge ----------
function sh(cmd, timeout = 15000) {
  return new Promise((resolve, reject) => {
    if (typeof ksu === 'undefined') { reject(new Error(t('noroot'))); return; }
    const name = 'dc_cb_' + Date.now() + '_' + (cbn++);
    const timer = setTimeout(() => { delete window[name]; reject(new Error(t('noanswer'))); }, timeout);
    window[name] = (errno, stdout, stderr) => { clearTimeout(timer); delete window[name]; resolve({ errno, stdout, stderr }); };
    try { ksu.exec(cmd, '{}', name); } catch (e) { clearTimeout(timer); delete window[name]; reject(e); }
  });
}
const host = () => (navigator.userAgent || '').replace(/Mozilla\/5\.0 /, '').replace(/['"\\$`]/g, '').slice(0, 90);
let tt;
function toast(m) { const e = $('toast'); e.textContent = m; e.classList.add('show'); clearTimeout(tt); tt = setTimeout(() => e.classList.remove('show'), 2600); }

async function load(liveOnly) {
  if (inflight && Date.now() - inflight < 20000) return;
  inflight = Date.now();
  try {
    if (!Object.keys(STR).length) { const s = await sh(`sh ${T} strings`); STR = JSON.parse(s.stdout); }
    const lite = liveOnly && data;
    const r = await sh(`sh ${T} ${lite ? 'live' : 'json'}`);
    if (r.errno !== 0) throw new Error((r.stderr || '').trim() || ('errno ' + r.errno));
    const j = JSON.parse(r.stdout);
    if (lite) Object.assign(data, j); else { data = j; lastFull = Date.now(); if (j.conf) setLang(j.conf.uiLang); }
    lastOk = Date.now();
    render(data);
  } catch (e) {
    setStatus('bad', t('st_nodata'), 'problem');
    renderProblems([{ lvl: 'bad', text: e.message }]);
  }
  inflight = 0;
}
setInterval(() => { if (document.visibilityState === 'visible') load(Date.now() - lastFull < FULL_EVERY); }, POLL);
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') { inflight = 0; load(); } });

// ---------- применение настроек / applying settings ----------
function setConf(el, cls, text) { el.className = 'conf ' + cls; el.textContent = text; }
async function apply(group, args, want, check, confEl) {
  pending[group] = { want, until: Date.now() + 6000 };
  setConf(confEl, 'wait', t('saving'));
  if (data) render(data);
  try {
    const r = await sh(`sh ${T} ${args}`);
    if (r.errno !== 0) throw new Error((r.stdout || r.stderr || '').trim());
    for (const delay of [0, 1200]) {
      await new Promise(res => setTimeout(res, delay));
      inflight = 0; await load();
      if (data && check(data)) {
        delete pending[group]; setConf(confEl, 'ok', '✓ ' + t('applied'));
        mascotFire(head, 'applied'); mascotFire(dockM, 'applied');
        setTimeout(() => { if (confEl.classList.contains('ok')) setConf(confEl, '', ''); }, 3500);
        render(data); return;
      }
    }
    setConf(confEl, 'bad', '✗ ' + t('notapplied'));
  } catch (e) { setConf(confEl, 'bad', '✗ ' + e.message); }
  delete pending[group];
  if (data) render(data);
}
function pend(g) { const p = pending[g]; if (p && p.until > Date.now()) return p.want; delete pending[g]; return undefined; }
function makeBtns(el, cls, items, onPick) {
  el.innerHTML = '';
  for (const [val, label] of items) {
    const b = document.createElement('button');
    if (cls) b.className = cls;
    b.type = 'button'; b.dataset.v = val; b.textContent = label;
    b.addEventListener('click', () => onPick(val));
    el.appendChild(b);
  }
}
function mark(el, active) { for (const b of el.children) b.classList.toggle('on', b.dataset.v === String(active)); }

const MODES = { care: { smart: 1, hot: 42 }, fast: { smart: 0, hot: 48 } };
const PROFILES = { perf: { l: 0, b: 0 }, balance: { l: 1612800, b: 0 }, eco: { l: 1324800, b: 1708800 } };
const SKIN_C = { blue: '#3f8cff', red: '#ff3d74', black: '#4a505b' };
function curProfile(cf) { for (const [k, p] of Object.entries(PROFILES)) if (p.l === cf.littleMax && p.b === (cf.bigMax || 0)) return k; return 'custom'; }
let freqsBuilt = false;
function buildControls() {
  makeBtns($('mode'), '', [['care', t('care')], ['fast', t('fast')]], k => {
    const m = MODES[k];
    if (data && data.cc && data.cc.smart === m.smart && data.conf.hot === m.hot) return;
    apply('mode', 'chgmode ' + k, k, d => d.cc && d.cc.smart === m.smart && d.conf.hot === m.hot, $('modeConf'));
  });
  makeBtns($('hot'), '', [[0, t('off')], [40, '40°'], [42, '42°'], [45, '45°'], [48, '48°']], v => {
    if (data && data.conf.hot === v) return;
    apply('hot', 'hot ' + v, v, d => d.conf.hot === v, $('hotConf'));
  });
  makeBtns($('prof'), '', Object.keys(PROFILES).map(k => [k, t('p_' + k)]), k => {
    const p = PROFILES[k];
    if (data && curProfile(data.conf) === k) return;
    apply('prof', 'profile ' + k, k, d => d.conf.littleMax === p.l && (d.conf.bigMax || 0) === p.b, $('profConf'));
  });
  makeBtns($('langSeg'), '', [['auto', t('l_auto')], ['ru', 'Русский'], ['en', 'English']], v => {
    sh(`sh ${T} lang ${v}`).then(() => { if (data) data.conf.uiLang = v; setLang(v); mark($('langSeg'), v); }).catch(e => toast(t('error', e.message)));
  });
  const sk = $('skins'); sk.innerHTML = '';
  for (const k of Object.keys(SKIN_C)) {
    const b = document.createElement('button'); b.type = 'button'; b.dataset.v = k;
    b.innerHTML = `<i style="background:${SKIN_C[k]}"></i>`; b.appendChild(document.createTextNode(t('sk_' + k)));
    b.addEventListener('click', () => { setSkin(k); sh(`sh ${T} skin ${k}`).catch(e => toast(t('error', e.message))); });
    sk.appendChild(b);
  }
  freqsBuilt = false;
}
function buildFreqs(lf, bf) {
  const lmax = lf[lf.length - 1], bmax = bf[bf.length - 1];
  makeBtns($('little'), 'chip', lf.filter(f => f >= 1017600 && f < lmax).map(f => [f, Math.floor(f / 1000) + '']).concat([[0, t('nolim')]]), v =>
    apply('little', 'little ' + (v ? Math.floor(v / 1000) : 0), v, d => d.conf.littleMax === v, $('littleConf')));
  makeBtns($('big'), 'chip', bf.filter(f => f >= 1209600 && f < bmax).map(f => [f, Math.floor(f / 1000) + '']).concat([[0, t('nolim')]]), v =>
    apply('big', 'big ' + (v ? Math.floor(v / 1000) : 0), v, d => (d.conf.bigMax || 0) === v, $('bigConf')));
  freqsBuilt = true;
}
const lim = $('lim');
const showLim = v => { $('limVal').textContent = v >= 100 ? t('nolimit') : v + '%'; $('limHint').textContent = v >= 100 ? t('lim_hint100') : t('lim_hint', v, v - 5); };
lim.addEventListener('input', () => showLim(+lim.value));
lim.addEventListener('change', () => { const v = +lim.value; apply('lim', 'limit ' + v, v, d => d.conf.limit === v, $('limConf')); });
$('full').addEventListener('click', () => { const on = !(data && data.charge.full); apply('full', on ? 'full' : 'full off', on, d => d.charge.full === on, $('fullConf')); });
for (const [id, cmd, key] of [['brC', 'brightcharge', 'bright'], ['brA', 'autobatt', 'autoBatt'], ['brS', 'saver', 'saverBatt'], ['thC', 'thermalchg', 'thermalChg'], ['usb', 'usbfast', 'usbFast'], ['alert', 'drainalert', 'drainAlert']]) {
  $(id).addEventListener('change', e => {
    let v = e.target.checked ? 1 : 0;
    if (id === 'thC') v = 1 - v;   // переключатель «выключить заводское» / the switch means “turn stock off”
    apply(id, cmd + ' ' + v, v, d => d.conf[key] === v, $(id + 'Conf') || $('limConf'));
  });
}

// ---------- окно и подсказки / sheet and help popovers ----------
function openSheet(title, node, withBtns) {
  $('mTitle').textContent = title; $('mBody').innerHTML = ''; $('mBody').appendChild(node);
  $('mBtns').style.display = withBtns ? 'grid' : 'none'; $('modal').classList.add('open');
}
$('mClose').addEventListener('click', () => $('modal').classList.remove('open'));
$('modal').addEventListener('click', e => { if (e.target.id === 'modal') $('modal').classList.remove('open'); });
$('showLogs').addEventListener('click', async () => {
  const pre = document.createElement('pre'); pre.id = 'logText'; pre.textContent = t('loading');
  openSheet(t('all_log'), pre, true);
  try { pre.textContent = (await sh(`sh ${T} logs`)).stdout; } catch (e) { pre.textContent = t('error', e.message); }
});
$('mCopy').addEventListener('click', async () => {
  const text = ($('logText') || {}).textContent || '';
  try { await navigator.clipboard.writeText(text); toast(t('copied')); return; } catch (e) { /* запасной способ / fallback */ }
  const ta = document.createElement('textarea'); ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
  document.body.appendChild(ta); ta.select(); let ok = false; try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
  ta.remove(); toast(ok ? t('copied') : t('copyfail'));
});
async function saveLog() { try { const p = (await sh(`sh ${T} savelogs '${host()}'`)).stdout.trim(); toast(t('saved_to', p.replace('/sdcard/', ''))); } catch (e) { toast(t('error', e.message)); } }
$('mSave').addEventListener('click', saveLog);
$('saveLog').addEventListener('click', saveLog);
async function showChangelog() {
  const box = document.createElement('div'); box.textContent = t('loading');
  openSheet(t('whatsnew'), box, false);
  try {
    const lines = (await sh(`sh ${T} changelog`)).stdout.trim().split('\n');
    box.textContent = '';
    lines.forEach((line, i) => {
      const [v, ru, en] = line.split('\t');
      const it = document.createElement('div'); it.className = 'ver-item';
      const b = document.createElement('b'); b.textContent = v + (i === 0 ? ' — ' + t('current') : ''); it.appendChild(b);
      it.appendChild(document.createTextNode(LANG === 'en' ? en : ru)); box.appendChild(it);
    });
  } catch (e) { box.textContent = t('error', e.message); }
}
$('whatsnew').addEventListener('click', showChangelog);
$('diagBtn').addEventListener('click', async () => {
  try { const r = (await sh(`sh ${T} diag '${host()}'`)).stdout.trim(); toast(r === 'busy' ? t('diag_busy') : t('diag_started')); inflight = 0; await load(true); } catch (e) { toast(t('error', e.message)); }
});

const pop = $('pop'), popA = $('popA');
let popFor = null;
function closePop() { if (popFor) { popFor.classList.remove('on'); pop.classList.remove('on'); popFor = null; } }
document.addEventListener('click', e => {
  const q = e.target.closest('.q');
  if (!q) { if (popFor && !e.target.closest('#pop')) closePop(); return; }
  e.preventDefault(); e.stopPropagation();
  if (popFor === q) { closePop(); return; }
  closePop();
  $('popX').textContent = t(q.dataset.help);
  const qr = q.getBoundingClientRect(), cx = qr.left + qr.width / 2;
  pop.classList.remove('above'); pop.style.top = '0px';
  const pr = pop.getBoundingClientRect(), ph = pop.offsetHeight, below = qr.bottom + 10;
  if (below + ph > innerHeight - 8 && qr.top - 10 - ph > 8) { pop.classList.add('above'); pop.style.top = (qr.top - 10 - ph) + 'px'; } else pop.style.top = below + 'px';
  popA.style.left = Math.max(14, Math.min(pr.width - 26, cx - pr.left - 6)) + 'px';
  pop.style.transformOrigin = (cx - pr.left) + 'px ' + (pop.classList.contains('above') ? '100%' : '0');
  popFor = q; q.classList.add('on'); pop.classList.add('on');
  // маскот с интересом смотрит, что это / the mascot looks curious
  mascotFire(docked ? dockM : head, 'curious'); look(cx, qr.top + qr.height / 2);
}, true);
$('popOk').addEventListener('click', e => { e.stopPropagation(); closePop(); });

// ---------- маскот: шапка и угол / mascot: header and corner ----------
const head = makeMascot('calm'); $('heroM').appendChild(head);
const dockM = makeMascot('calm'); $('dockM').appendChild(dockM);
function setSkin(k) { skinMascot(head, k); skinMascot(dockM, k); mark($('skins'), k); }
const dock = $('dock'), lad = $('ladder'), heroBox = $('hero');
const DW = 116;
let docked = false, entering = false, side = 'r', acc = 0, last = 0, cur = 'calm', t1, t2, tq = [];
const posX = s => s === 'r' ? document.documentElement.clientWidth - DW - 10 : 10;
const later = (f, ms) => tq.push(setTimeout(f, ms));
function placeDock() { dock.style.left = posX(side) + 'px'; lad.style.left = (posX(side) + DW / 2 - 11) + 'px'; }
function enter() {
  docked = true; entering = true; acc = 0;
  dock.style.transition = 'none'; placeDock(); void dock.offsetWidth; dock.style.transition = '';
  lad.classList.remove('up'); lad.classList.add('drop');
  later(() => dock.classList.add('on', 'enter'), 700);
  later(() => { dock.classList.remove('enter'); lad.classList.remove('drop'); lad.classList.add('up'); }, 2950);
  later(() => { entering = false; }, 3300);
}
function leave() { docked = false; entering = false; tq.forEach(clearTimeout); tq = []; dock.classList.remove('on', 'enter', 'hop'); lad.classList.remove('drop'); lad.classList.add('up'); }
function hop() { side = side === 'r' ? 'l' : 'r'; dock.style.left = posX(side) + 'px'; dock.classList.remove('hop'); void dock.offsetWidth; dock.classList.add('hop'); }
function idle() {
  clearTimeout(t1); clearTimeout(t2); dockM.dataset.state = cur;
  t1 = setTimeout(() => { if (!docked) return; dockM.dataset.state = 'limit'; setTimeout(() => { if (dockM.dataset.state === 'limit') dockM.dataset.state = cur; }, 2400); }, 6000);
  t2 = setTimeout(() => { if (docked) dockM.dataset.state = 'night'; }, 15000);
}
addEventListener('scroll', () => {
  const y = scrollY, H = heroBox.offsetHeight;
  if (!docked && y > H - 20) enter(); else if (docked && y < H - 140) leave();
  if (docked && !entering) { acc += Math.abs(y - last); if (acc > 520) { acc = 0; hop(); } }
  last = y; idle(); closePop();
}, { passive: true });
addEventListener('resize', () => { if (docked) placeDock(); });
dock.addEventListener('click', () => scrollTo({ top: 0, behavior: 'smooth' }));
head.addEventListener('click', () => mascotFire(head, 'tap'));
(function blink() { document.querySelectorAll('svg.mascot').forEach(m => m.classList.add('blink')); setTimeout(() => document.querySelectorAll('svg.mascot').forEach(m => m.classList.remove('blink')), 140); setTimeout(blink, 2500 + Math.random() * 3500); })();
function look(x, y) {
  document.querySelectorAll('svg.mascot').forEach(m => {
    const r = m.getBoundingClientRect(); if (!r.width) return;
    const dx = x - (r.left + r.width / 2), dy = y - (r.top + r.height * .45), d = Math.hypot(dx, dy) || 1, k = Math.min(1, d / 160);
    m.querySelectorAll('.pupils').forEach(p => { p.style.transform = `translate(${dx / d * 3 * k}px, ${dy / d * 2.8 * k}px)`; });
  });
}
addEventListener('pointerdown', e => look(e.clientX, e.clientY), { passive: true });

// ---------- проблемы и статус / problems and status ----------
function problems(d) {
  const p = [], c = d.charge, b = d.batt, cc = d.cc || {}, ok = d.ok || {};
  if (!d.daemon) p.push({ lvl: 'bad', text: t('p_daemon'), go: 'cLog' });
  if (ok.powerhint !== '3' && ok.powerhint !== '-' && ok.powerhint != null) p.push({ lvl: 'warn', text: t('p_ph', ok.powerhint), go: 'cPerf' });
  if (!c.switch) p.push({ lvl: 'bad', text: t('p_nosw'), go: 'cCharge' });
  if (cc.ok === 2) p.push({ lvl: 'warn', text: t('p_skip'), go: 'cCharge' });
  else if (cc.ok === 0 && cc.smart === 1) p.push({ lvl: 'warn', text: t('p_ccrej'), go: 'cCharge' });
  if (ok.thermal === 'nomount') p.push({ lvl: 'warn', text: t('p_nomount'), go: 'cCharge' });
  if (ok.thermal !== 'stock' && d.conf.hot === 0) p.push({ lvl: 'warn', text: t('p_noprot'), go: 'cCharge' });
  if (b.temp >= 450) p.push({ lvl: 'warn', text: t('p_hot', dec(b.temp / 10, 1), b.status === 'Charging' ? t('p_hot_chg') : t('p_hot_idle')), go: 'cNow' });
  if (d.conf.drainAlert === 1 && d.drainAlert && d.drainAlert.length === 2) p.push({ lvl: 'warn', text: t('p_drain', d.drainAlert[0], d.drainAlert[1]), go: 'cUse' });
  return p;
}
function goTo(id) { const el = $(id); el.scrollIntoView({ behavior: 'smooth', block: 'start' }); el.classList.add('flash'); setTimeout(() => el.classList.remove('flash'), 1400); }
let lastProb = '', probGo = null;
function renderProblems(list) {
  const key = JSON.stringify(list) + LANG; if (key === lastProb) return; lastProb = key;
  const box = $('problems'); box.innerHTML = '';
  probGo = list.length ? list[0].go || 'problems' : null;
  for (const pr of list) {
    const div = document.createElement('div'); div.className = 'prob ' + pr.lvl;
    const s = document.createElement('span'); s.textContent = pr.text; div.appendChild(s);
    if (pr.go) { const b = document.createElement('button'); b.type = 'button'; b.textContent = t('show'); b.addEventListener('click', () => goTo(pr.go)); div.appendChild(b); }
    box.appendChild(div);
  }
}
function setStatus(cls, text, state) {
  const s = $('headS'); s.className = 'status ' + cls; s.querySelector('span').textContent = text;
  if (state && head.dataset.state !== state) { head.dataset.state = state; cur = state; if (!dockM.dataset.state.match(/night|limit/) || !docked) dockM.dataset.state = state; }
}
$('headS').addEventListener('click', () => { if (probGo) goTo(probGo === 'problems' ? 'problems' : probGo); });

// ---------- рисование / rendering ----------
const mhz = k => Math.floor((k || 0) / 1000);
const fmtH = h => { if (!isFinite(h) || h <= 0) return '—'; if (h >= 48) return t('fmt_d', Math.round(h / 24)); const H = Math.floor(h), M = Math.round((h - H) * 60); return H ? t('fmt_hm', H, String(M).padStart(2, '0')) : t('fmt_m', M); };
const tm = s => { const d = new Date(s * 1000); return d.toLocaleDateString(LANG === 'en' ? 'en-GB' : 'ru-RU', { day: '2-digit', month: '2-digit' }) + ' ' + d.toLocaleTimeString(LANG === 'en' ? 'en-GB' : 'ru-RU', { hour: '2-digit', minute: '2-digit' }); };
function rates(h) {
  const r = { on: { drop: 0, dt: 0 }, off: { drop: 0, dt: 0 } };
  for (let i = 1; i < h.length; i++) {
    const a = h[i - 1], b = h[i], dt = b[0] - a[0];
    if (a[6] || b[6] || a[7] || dt <= 0 || dt > 12 * 3600 || b[1] > a[1]) continue;
    const k = a[5] ? 'on' : 'off'; r[k].drop += a[1] - b[1]; r[k].dt += dt;
  }
  return r;
}
function chart(svg, pts, key, lo, hi, color, threshold, now) {
  const x = s => (s - (now - 86400)) / 86400 * 300, y = v => 96 - (Math.min(hi, Math.max(lo, v)) - lo) / (hi - lo) * 92;
  let out = '';
  for (let i = 0; i < pts.length; i++) {
    if (!pts[i][4]) continue;
    const x1 = x(pts[i][0]), x2 = i + 1 < pts.length && pts[i + 1][0] - pts[i][0] < 1200 ? x(pts[i + 1][0]) : x1 + 1.5;
    out += `<rect x="${x1.toFixed(1)}" y="0" width="${Math.max(1, x2 - x1).toFixed(1)}" height="100" fill="var(--pause)"/>`;
  }
  if (threshold != null) out += `<line x1="0" x2="300" y1="${y(threshold).toFixed(1)}" y2="${y(threshold).toFixed(1)}" stroke="var(--c2)" stroke-dasharray="4 3" stroke-width="1" vector-effect="non-scaling-stroke"/>`;
  let seg = [];
  const flush = () => { if (seg.length > 1) out += `<polyline points="${seg.join(' ')}" fill="none" stroke="${color}" stroke-width="2" vector-effect="non-scaling-stroke" stroke-linejoin="round"/>`;
    else if (seg.length === 1) { const [a, b] = seg[0].split(','); out += `<circle cx="${a}" cy="${b}" r="1.6" fill="${color}"/>`; } seg = []; };
  for (let i = 0; i < pts.length; i++) { if (i && pts[i][0] - pts[i - 1][0] > 1200) flush(); seg.push(x(pts[i][0]).toFixed(1) + ',' + y(key(pts[i])).toFixed(1)); }
  flush(); svg.innerHTML = out;
}
function dist(el, rows) {
  el.innerHTML = rows && rows.length ? rows.map(([f, p]) => `<div class="dl"><span>${f} MHz</span><span class="b"><i style="width:${Math.min(100, p)}%"></i></span><span class="p">${Math.round(p)}%</span></div>`).join('') : `<div class="empty">${t('nodata')}</div>`;
}
function items(el, rows, empty) {
  el.innerHTML = '';
  if (!rows.length) { el.innerHTML = `<li class="empty"></li>`; el.firstChild.textContent = empty; return; }
  for (const [when, text] of rows) {
    const li = document.createElement('li'); const b = document.createElement('b'); b.textContent = when;
    li.appendChild(b); li.appendChild(document.createTextNode(text)); el.appendChild(li);
  }
}
const amps = (d, lvl) => d.dt && d.dt.fcc && d.dt.fcc[lvl] ? dec(d.dt.fcc[lvl] / 1e6, 1) : '';
function limiters(d) {
  const b = d.batt, bat = d.bat || {}, cc = d.cc || {}, out = [];
  const H = bat.HEALTH, DH = bat.DIE_HEALTH, ct = d.chips && d.chips.pmic;
  if (H === 'Hot' || H === 'Overheat') out.push(['hot2', t('l_overheat')]);
  else if (H === 'Warm') out.push(['hot2', t('l_warm')]);
  else if (H === 'Cool' || H === 'Cold') out.push(['hot1', t('l_cold')]);
  if (DH === 'Warm' || DH === 'Hot' || DH === 'Overheat') out.push([DH === 'Warm' ? 'hot1' : 'hot2', t('l_die', ct ? ' (' + Math.round(ct / 10) + '°)' : '')]);
  if (cc.own > 0 && cc.smart === 1) out.push(['hot1', t('l_care', cc.own, cc.max, dec(b.temp / 10, 1))]);
  else if (cc.own > 0) out.push(['', t('l_hold', cc.own, amps(d, cc.own) ? t('l_amp', amps(d, cc.own)) : '')]);
  else if (cc.lvl > 0) out.push(['hot1', t('l_stock', cc.lvl, cc.max)]);
  if (bat.INPUT_CURRENT_LIMITED === '1') {
    const u = d.usb || {}, v = +u.VOLTAGE_NOW / 1e6, a = +(u.INPUT_CURRENT_NOW || u.INPUT_CURRENT_SETTLED) / 1e6;
    out.push(['', v > 0 && a > 0 ? t('l_input', dec(v, 1), dec(a, 2), Math.round(v * a)) : t('l_input0')]);
  }
  if (bat.CHARGE_TYPE === 'Taper' || b.voltage >= 4370000) out.push(['', t('l_taper')]);
  if (!out.length) out.push(['', t('l_none')]);
  if (b.temp >= 400) out.push(['', t('l_sensor')]);
  return out;
}
function tcls(el, v, w, b) { el.classList.toggle('hot1', v >= w && v < b); el.classList.toggle('hot2', v >= b); }
const deg = v => v == null ? '—' : dec(v / 10, 1) + '°';
function row(k, v) { return `<div class="row"><span class="k">${k}</span><span class="v">${v}</span></div>`; }
const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

function render(d) {
  const b = d.batt, c = d.charge, cf = d.conf, nw = d.now, usb = d.usb || {}, bat = d.bat || {}, cc = d.cc || {};
  $('fver').textContent = (d.version || '').replace(/^v/, '');
  if (d.skin && !render.skinDone) { setSkin(d.skin); render.skinDone = true; }
  const probs = problems(d); renderProblems(probs);

  const charging = b.status === 'Charging';
  const I = Math.abs(b.current || 0) / 1000, V = (b.voltage || 0) / 1e6, W = I * V / 1000;
  emaW = emaW == null ? W : emaW * 0.7 + W * 0.3;
  const fullMah = (d.full || 4000000) / 1000;
  // статус и маскот / status and mascot
  const bad = probs.some(p => p.lvl === 'bad'), warn = probs.length > 0;
  if (bad) setStatus('bad', t('st_problem'), 'problem');
  else if (c.plugged && c.state === 'off' && c.why === 'hot') setStatus('warn', t('st_hot'), 'hotpause');
  else if (c.plugged && cc.reg === 1) setStatus('warn', t('st_hold', dec(I / 1000, 1) + ' A'), 'holding');
  else if (c.plugged && c.state === 'off') setStatus('ok', t('st_limit', cf.limit), 'limit');
  else if (c.plugged && c.full && charging) setStatus('ok', t('st_full'), 'charging');
  else if (charging) setStatus('ok', t('st_charging', dec(I / 1000, 1) + ' A'), 'charging');
  else if (warn) setStatus('warn', t('st_warn'), b.cap <= 15 ? 'low' : 'calm');
  else setStatus('ok', t('st_ok'), (d.diag || '').match(/^\d+\//) ? 'diag' : b.cap <= 15 ? 'low' : 'calm');

  if (b.cap != null) $('cap').innerHTML = `${b.cap}<small>%</small>`;
  $('capBar').style.width = (b.cap || 0) + '%';
  if (cf) { $('limMark').style.left = Math.min(99.5, cf.limit) + '%'; $('limMark').style.display = cf.limit < 100 ? 'block' : 'none'; }
  $('pwr').textContent = dec(W, 1) + (LANG === 'en' ? ' W' : ' Вт');
  $('pwrS').textContent = (charging ? t('in_batt') : t('usage')) + ` · ${Math.round(I)} ${LANG === 'en' ? 'mA' : 'мА'}`;
  $('capS').textContent = [t('st_' + b.status) || b.status, c.plugged ? t('cable') : '', cf && cf.limit < 100 ? t('limit_short', cf.limit) : ''].filter(Boolean).join(' · ');
  const h = d.history || [], rt = rates(h);
  if (charging && cf) {
    const target = c.full ? 100 : Math.min(100, cf.limit);
    $('e1l').textContent = t('to_target', target);
    $('e1').textContent = b.cap >= target ? t('ready') : fmtH((target - b.cap) / 100 * fullMah / Math.max(I, 1));
    $('e1s').textContent = t('at_speed');
  } else {
    $('e1l').textContent = t('last_now');
    $('e1').textContent = fmtH(b.cap / 100 * fullMah * V / Math.max(emaW, 0.05) / 1000);
    $('e1s').textContent = t('to_zero');
  }
  const onR = rt.on.dt >= 1200 ? rt.on.drop * 3600 / rt.on.dt : null, offR = rt.off.dt >= 1200 ? rt.off.drop * 3600 / rt.off.dt : null;
  $('e2').textContent = onR ? fmtH(b.cap / onR) : '—';
  $('e2s').textContent = offR ? t('standby', fmtH(b.cap / Math.max(offR, 0.1))) : t('collecting');
  $('tB').textContent = deg(b.temp); tcls($('tB'), b.temp / 10, 40, 45);
  $('tQ').textContent = nw.tQuiet == null ? '—' : nw.tQuiet + '°'; tcls($('tQ'), nw.tQuiet, 45, 50);
  $('tC').textContent = nw.tCpu == null ? '—' : nw.tCpu + '°'; tcls($('tC'), nw.tCpu, 70, 80);
  const ch = d.chips || {};
  $('tP').textContent = deg(ch.pmic); tcls($('tP'), (ch.pmic || 0) / 10, 45, 55);
  $('tCP').textContent = deg(ch.cp); tcls($('tCP'), (ch.cp || 0) / 10, 50, 60);
  $('tCo').textContent = deg(ch.conn); tcls($('tCo'), (ch.conn || 0) / 10, 45, 55);
  if (!cf) return;   // лёгкое обновление без настроек / live update without settings

  const st = $('cst'), full = pend('full') ?? c.full;
  if (!c.switch) { st.className = 'cst bad'; st.textContent = t('c_nosw'); }
  else if (!c.plugged) { st.className = 'cst idle'; st.textContent = t('c_nocable'); }
  else if (full) { st.className = 'cst ok'; st.textContent = t('c_full'); }
  else if (c.state === 'off' && c.why === 'hot') { st.className = 'cst warn'; st.textContent = t('c_hot', dec(b.temp / 10, 1), cf.hotResume); }
  else if (c.state === 'off') { st.className = 'cst ok'; st.textContent = t('c_lim', cf.limit); }
  else if (charging) { st.className = 'cst ok'; st.textContent = t('c_chg'); }
  else { st.className = 'cst idle'; st.textContent = t('c_idle'); }
  let rows = '';
  if (c.plugged) {
    const uv = (+usb.VOLTAGE_NOW || 0) / 1e6, ui = (+(usb.INPUT_CURRENT_NOW || usb.INPUT_CURRENT_SETTLED) || 0) / 1e6;
    const type = usb.REAL_TYPE && usb.REAL_TYPE !== 'Unknown' ? usb.REAL_TYPE : '';
    const fast = /PD|HVDCP/.test(type) || uv > 6.5 || +usb.QUICK_CHARGE_TYPE > 0 || +usb.HVDCP3_TYPE > 0;
    rows += row(t('speed'), charging ? t('w_in', dec(W, 1), Math.round(I)) : t('not_charging'));
    if (type || uv) rows += row(t('charger'), esc(`${I18N.en['ch_' + type] ? t('ch_' + type) : type || '—'}${uv ? ` · ${dec(uv, 1)} V` : ''}${ui ? ` · ${dec(ui, 2)} A` : ''}`));
    rows += row(t('fastq'), fast ? t('yes') : (type === 'USB' ? t('no_pc') : t('no_5v')));
    if (charging) rows += `<div class="row col"><span class="k">${t('limits')}</span><span class="v">${limiters(d).map(([k, x]) => k ? `<span class="${k}">• ${esc(x)}</span>` : '• ' + esc(x)).join('<br>')}</span></div>`;
    if (bat.CHARGE_TYPE && charging && I18N.en['ct_' + bat.CHARGE_TYPE]) rows += row(t('stage'), t('ct_' + bat.CHARGE_TYPE));
  }
  $('chgRows').innerHTML = rows; $('chgRows').style.display = rows ? 'block' : 'none';
  const mk = pend('mode') ?? (cc.smart === 1 ? 'care' : 'fast'); mark($('mode'), mk);
  const lv = pend('lim') ?? cf.limit;
  if (document.activeElement !== lim) { lim.value = lv; showLim(lv); }
  mark($('hot'), pend('hot') ?? cf.hot);
  const fb = $('full'); fb.className = 'btn' + (full ? ' on' : ''); fb.textContent = full ? t('full_cancel') : t('full_once');
  // файлы нагрева / thermal configs
  const th = d.ok.thermal || 'stock', want = pend('thC') ?? cf.thermalChg;
  $('thC').checked = want === 0;
  $('thC').disabled = th === 'mismatch';
  let ts = t('th_' + (th === 'module' || th === 'stock' || th === 'mismatch' || th === 'nomount' ? th : 'stock'));
  if ((want === 1 && th === 'module') || (want === 0 && th === 'stock')) ts += ' · ' + t('th_reboot');
  $('thState').textContent = ts;
  if (c.ffc == null) $('usbCtl').style.display = 'none'; else $('usb').checked = (pend('usb') ?? cf.usbFast) === 1;
  // сеансы / sessions
  items($('sess'), (d.sessions || []).slice(-6).reverse().map(l => {
    const [s0, s1, c0, c1, ma, tmax, typ, pw, mode, scr, jl] = l.split(',');
    const dur = (s1 - s0) / 3600, rate = dur > 0 ? Math.round((c1 - c0) / dur) : 0;
    const chn = typ && typ !== '?' ? (I18N.en['ch_' + typ] ? t('ch_' + typ) : typ) + (+pw > 0 ? ', ' + pw + (LANG === 'en' ? ' W' : ' Вт') : '') : '';
    return [tm(+s0), t('sess_line', c0, c1, fmtH(dur), rate, dec(ma / 1000, 1), dec(tmax / 10, 1), chn ? t('sess_ch', chn + ' · ' + t('mode_' + mode)) : ' · ' + t('mode_' + mode), +scr > 0 ? t('sess_scr', scr) : '', +jl > 0 ? t('sess_jl', jl) : '')];
  }), t('sess_none'));
  // таблица тока / current table
  const fcc = (d.dt && d.dt.fcc) || [];
  $('dtTable').innerHTML = fcc.length ? '<div class="dtt">' + fcc.slice(0, 16).map((v, i) => `<div class="${cc.lvl === i ? 'cur' : ''}">${esc(t('dt_lvl', i))}<b>${v ? dec(v / 1e6, 1) + ' A' : '0'}</b></div>`).join('') + '</div>' : `<div class="empty">${t('dt_none')}</div>`;

  // яркость / brightness
  const bl = d.bl || {};
  $('blNow').textContent = bl.raw != null && bl.max ? `${Math.round(bl.raw * 100 / bl.max)}% · ${bl.raw} / ${bl.max}` : '—';
  $('blMode').textContent = d.brMode === 1 ? t('auto') : d.brMode === 0 ? t('manual') : '—';
  $('svNow').textContent = d.saver === 1 ? t('on') : d.saver === 0 ? t('offf') : '—';
  for (const [id, key] of [['brC', 'bright'], ['brA', 'autoBatt'], ['brS', 'saverBatt'], ['alert', 'drainAlert']]) $(id).checked = (pend(id) ?? cf[key]) === 1;

  // производительность / performance
  if (!freqsBuilt && d.littleFreqs && d.littleFreqs.length && d.bigFreqs && d.bigFreqs.length) buildFreqs(d.littleFreqs, d.bigFreqs);
  const pk = pend('prof') ?? curProfile(cf); mark($('prof'), pk);
  $('profHint').textContent = pk === 'custom' ? t('p_custom') : t('ph_' + pk);
  mark($('little'), pend('little') ?? cf.littleMax); mark($('big'), pend('big') ?? (cf.bigMax || 0));
  const bmaxHw = (d.bigFreqs || [0]).slice(-1)[0];
  $('nL').textContent = t('of_mhz', mhz(nw.little), mhz(nw.littleMax));
  $('nB').innerHTML = esc(t('of_mhz', mhz(nw.big), mhz(nw.bigMax))) + (nw.bigMax < (cf.bigMax || bmaxHw) ? ` <span class="hot1">· ${t('heat')}</span>` : '');
  $('nG').textContent = t('gpu_now', Math.round((nw.gpu || 0) / 1e6), nw.gpuBusy ?? '—');
  $('erHint').hidden = !nw.er;
  if (d.dist) { dist($('dLittle'), d.dist.little); dist($('dBig'), d.dist.big); dist($('dGpu'), d.dist.gpu); }

  // расход / usage
  const setR = (id, r, rr) => { $(id).textContent = rr ? t('pph', dec(rr, 1)) : '—'; $(id + 'S').textContent = rr ? t('drop_in', r.drop, fmtH(r.dt / 3600)) : t('collecting'); };
  setR('rOn', rt.on, onR); setR('rOff', rt.off, offR);
  const oh = $('offHint'); oh.textContent = offR != null && offR > 2 ? t('off_hint', dec(offR, 1)) : ''; oh.hidden = !oh.textContent;
  chart($('gCap'), h, p => p[1], 0, 100, 'var(--c1)', cf.limit < 100 ? cf.limit : null, d.time);
  chart($('gTemp'), h, p => p[2] / 10, 20, 50, 'var(--c2)', cf.hot || null, d.time);
  if (h.length) {
    const caps = h.map(p => p[1]), temps = h.map(p => p[2] / 10);
    $('hCap').textContent = `${Math.min(...caps)}–${Math.max(...caps)}%`;
    $('hTemp').textContent = `${Math.min(...temps).toFixed(0)}–${Math.max(...temps).toFixed(0)}°`;
  } else { $('hCap').textContent = t('every5'); $('hTemp').textContent = ''; }
  const nights = (d.drain || []).map(l => l.split(',').map(Number));
  items($('drain'), nights.slice(-8).reverse().map(([end, dur, drop, mah, deep, mob, share, sims]) => [tm(end), t('night_line', '', fmtH(dur / 3600), drop, dec(drop * 3600 / dur, 1), mah > 0 ? t('night_ma', Math.round(mah * 3600 / dur)) : '', deep,
    share >= 0 ? t('night_mob', share) : '', sims >= 0 ? t('night_sim', sims) : '').replace(/^ · /, '')]), t('night_none'));
  // по неделям / by week
  const wk = {}; nights.forEach(([end, dur, , mah]) => { if (mah > 0) { const w = Math.floor((d.time - end) / 604800); if (w < 6) { (wk[w] = wk[w] || []).push(mah * 3600 / dur); } } });
  const wl = [5, 4, 3, 2, 1, 0].map(w => [w, wk[w] ? wk[w].reduce((a, x) => a + x, 0) / wk[w].length : null]);
  const wmax = Math.max(1, ...wl.map(x => x[1] || 0));
  $('weeks').innerHTML = wl.map(([w, v]) => `<div class="w${w === 0 && d.drainAlert && d.drainAlert.length ? ' hi' : ''}"><span>${v ? Math.round(v) : ''}</span><i style="height:${v ? Math.max(4, v / wmax * 56) : 2}px"></i><span>${w === 0 ? t('axnow') : '−' + w}</span></div>`).join('');
  if (d.full && d.design) $('health').textContent = t('of_mah', Math.round(d.full * 100 / d.design), Math.round(d.full / 1000), Math.round(d.design / 1000));
  $('cycles').textContent = d.cycles ?? '—';
  $('sleep').textContent = d.sleep == null ? '—' : d.sleep + '%';

  // журнал / log
  items($('events'), (d.events || []).slice(-6).reverse().map(l => { const p = l.split('\t'); return [tm(+p[0]), msg(p[1], p.slice(2))]; }), t('ev_none'));
  renderDiag(d.diag);
  mark($('langSeg'), cf.uiLang || 'auto');
}
function renderDiag(s) {
  s = s || '';
  const m = s.match(/^(\d+)\/(\d+)$/), btn = $('diagBtn');
  if (m) {
    $('dProgW').style.display = 'block'; $('dProg').style.width = Math.round(+m[1] * 100 / +m[2]) + '%';
    setConf($('dStat'), 'wait wrap', t('diag_step', m[1], m[2])); btn.disabled = true; btn.textContent = t('diag_run');
  } else {
    $('dProgW').style.display = 'none'; btn.disabled = false; btn.textContent = t('diag');
    if (s.startsWith('done:')) setConf($('dStat'), 'ok wrap', '✓ ' + t('diag_done', s.slice(5).replace('/sdcard/', '')));
    else if (s.startsWith('error:')) setConf($('dStat'), 'bad wrap', '✗ ' + s.slice(6));
  }
}

applyLang();
load();
