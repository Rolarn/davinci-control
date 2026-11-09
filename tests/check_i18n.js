// Проверка переводов: одинаковые ключи, нет пустых, все используемые ключи существуют.
// Translation check: same keys, none empty, every used key exists.
const fs = require('fs'), path = require('path'), vm = require('vm');
const W = path.join(__dirname, '..', 'module', 'webroot');
const ctx = {}; vm.createContext(ctx); vm.runInContext(fs.readFileSync(path.join(W, 'i18n.js'), 'utf8') + '\nthis.I18N = I18N;', ctx);
const { ru, en } = ctx.I18N; let bad = 0;
const fail = m => { console.log('  ✗ ' + m); bad++; };
for (const k of Object.keys(ru)) { if (!(k in en)) fail('нет в en / missing in en: ' + k); if (!String(ru[k]).trim()) fail('пусто ru: ' + k); }
for (const k of Object.keys(en)) { if (!(k in ru)) fail('нет в ru / missing in ru: ' + k); if (!String(en[k]).trim()) fail('пусто en: ' + k); if (/[А-Яа-яЁё]/.test(en[k]) && !['Русский'].includes(en[k])) fail('кириллица в en / Cyrillic in en: ' + k); }
for (const k of Object.keys(ru)) { const a = (ru[k].match(/\{\d\}/g) || []).sort().join(), b = (en[k].match(/\{\d\}/g) || []).sort().join(); if (a !== b) fail('разные {n}: ' + k); }
const html = fs.readFileSync(path.join(W, 'index.html'), 'utf8'), js = fs.readFileSync(path.join(W, 'app.js'), 'utf8');
const used = new Set([...html.matchAll(/data-(?:t|help|label)="([^"]+)"/g)].map(m => m[1]).concat([...js.matchAll(/\bt\('([a-z_0-9]+)'/g)].map(m => m[1])));
for (const k of used) if (!k.endsWith('_') && !(k in ru)) fail('ключ не найден / key not found: ' + k);
// строки бэкенда / backend strings
const tsv = fs.readFileSync(path.join(W, '..', 'strings.tsv'), 'utf8').split('\n').filter(l => l && !l.startsWith('#'));
for (const l of tsv) { const [c, r, e] = l.split('\t'); if (!r || !e) fail('strings.tsv: нет перевода / missing translation: ' + c); else if (/[А-Яа-яЁё]/.test(e)) fail('strings.tsv: кириллица в en: ' + c); }
console.log(bad ? `i18n: ${bad} FAILED` : `i18n: OK (${Object.keys(ru).length} ключей / keys, ${tsv.length} строк бэкенда / backend strings)`);
process.exit(bad ? 1 : 0);
