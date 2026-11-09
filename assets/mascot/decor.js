// Украшения маскота для README, релизов и праздников. / Mascot decorations for README, releases and holidays.
const NS = 'http://www.w3.org/2000/svg';
function add(parent, markup) { const g = document.createElementNS(NS, 'g'); g.innerHTML = markup; parent.appendChild(g); return g; }
const flake = (x, y, r) => `<g class="fallx" style="animation-delay:${(x % 7) / 3}s"><g transform="translate(${x} ${y})"><path d="M0 -${r}V${r}M-${r * .87} -${r / 2}L${r * .87} ${r / 2}M-${r * .87} ${r / 2}L${r * .87} -${r / 2}" stroke="#dbeafe" stroke-width="2.4" stroke-linecap="round"/></g></g>`;
const confetti = () => [[30, 40, '#f472b6'], [170, 60, '#fde047'], [40, 96, '#60a5fa'], [176, 110, '#34d399'], [24, 150, '#fb923c'], [166, 24, '#a78bfa']]
  .map(([x, y, c], i) => `<g class="fallx" style="animation-delay:${i * .4}s"><rect x="${x}" y="${y}" width="7" height="4" rx="1" fill="${c}" transform="rotate(${i * 37} ${x} ${y})"/></g>`).join('');
const HOL = {
  release: { en: "First release", name: 'Первый релиз', date: 'дата 1.0.0', text: 'Колпак и конфетти: у модуля день рождения.', state: 'limit',
    draw: m => { add(m.querySelector('.all'), `<path d="M118 46L134 8L150 46Z" fill="#a855f7" stroke="#0f1218" stroke-width="3" stroke-linejoin="round"/><path d="M123 34h22M128 22h12" stroke="#fde047" stroke-width="3"/><circle cx="134" cy="7" r="5" fill="#fde047" stroke="#0f1218" stroke-width="2"/>` + confetti()); } },
  newyear: { en: "Happy New Year", name: 'Новый год', date: '31 декабря – 7 января', text: 'Колпак Деда Мороза и снег.', state: 'limit',
    draw: m => { add(m.querySelector('.all'), `<path d="M104 50Q112 14 146 20Q164 24 160 46Z" fill="#e11d48" stroke="#0f1218" stroke-width="3" stroke-linejoin="round"/><rect x="98" y="40" width="66" height="13" rx="6.5" fill="#fff" stroke="#0f1218" stroke-width="3"/><circle cx="158" cy="17" r="7" fill="#fff" stroke="#0f1218" stroke-width="2.5"/>` + flake(26, 40, 5) + flake(178, 74, 4) + flake(36, 112, 4.5) + flake(172, 150, 5)); } },
  cosmos: { en: "Cosmonautics Day", name: 'День космонавтики', date: '12 апреля', text: 'Вокруг летает ракета.', state: 'calm',
    draw: m => { add(m.querySelector('.all'), `<g class="orbit"><g transform="translate(100 6) rotate(90)"><path d="M0 -14C7 -8 7 6 5 12H-5C-7 6 -7 -8 0 -14Z" fill="#f1f5f9" stroke="#0f1218" stroke-width="2.5"/><circle cy="-3" r="3" fill="#60a5fa" stroke="#0f1218" stroke-width="1.5"/><path d="M-5 6l-5 7h5zM5 6l5 7h-5z" fill="#ef4444" stroke="#0f1218" stroke-width="1.5"/><path class="flm" d="M-3 13q3 9 6 0z" fill="#fbbf24"/></g></g>`); } },
  coder: { en: "Programmer's Day", name: 'День программиста', date: '256-й день года (13 сентября)', text: 'Вместо рта — «&lt;/&gt;», курсор мигает.', state: 'calm',
    draw: m => { m.classList.add('coder'); add(m.querySelector('.face'), `<text x="100" y="131" text-anchor="middle" font-family="ui-monospace, Menlo, Consolas, monospace" font-weight="700" font-size="16" class="gl">&lt;/&gt;</text><rect class="cur gl" x="88" y="140" width="9" height="3"/>`); } },
  halloween: { en: "Halloween", name: 'Хэллоуин', date: '31 октября', text: 'Лицо-тыква светится оранжевым.', state: 'calm',
    draw: m => { m.classList.add('pumpkin'); m.style.setProperty('--face', '#ff9f1c'); add(m.querySelector('.face'), `<path class="gl" d="M74 110l10-16 10 16zM106 110l10-16 10 16zM84 124l5 5 5-5 6 5 6-5 5 5 5-5q-3 13-16 13t-16-13z"/>`); } },
  k20: { en: "davinci birthday", name: 'День рождения davinci', date: '28 мая (анонс Redmi K20, 2019)', text: 'Колпак с цифрами 9T.', state: 'limit',
    draw: m => { add(m.querySelector('.all'), `<path d="M118 46L134 8L150 46Z" fill="#ef4444" stroke="#0f1218" stroke-width="3" stroke-linejoin="round"/><text x="134" y="40" text-anchor="middle" font-size="11" font-weight="800" fill="#fff" font-family="system-ui">9T</text><circle cx="134" cy="7" r="5" fill="#fde047" stroke="#0f1218" stroke-width="2"/>` + confetti()); } },
};
const DECO = {
  perf: m => { m.classList.add('pose-run'); add(m.querySelector('.all'), `<g class="spd" stroke="#93c5fd" stroke-width="4" stroke-linecap="round"><path d="M4 98h20"/><path d="M0 118h24"/><path d="M8 138h16"/></g>
    <g transform="translate(166 34)"><circle r="17" fill="#0b0f16" stroke="#0f1218" stroke-width="3"/><path d="M-11 5a12 12 0 0 1 22 0" fill="none" stroke="#334155" stroke-width="4" stroke-linecap="round"/><path d="M1 -7a12 12 0 0 1 10 12" fill="none" stroke="#22c55e" stroke-width="4" stroke-linecap="round"/><g class="needle"><path d="M0 4L0 -10" stroke="#f8fafc" stroke-width="3" stroke-linecap="round"/></g><circle cy="4" r="3" fill="#f8fafc"/></g>`); },
  sun: m => { m.classList.add('pose-chill'); add(m.querySelector('.all'), `<g transform="translate(168 30)"><g class="rays" stroke="#fbbf24" stroke-width="3.5" stroke-linecap="round"><path d="M0 -21v-6M0 21v6M-21 0h-6M21 0h6M-15 -15l-4 -4M15 15l4 4M-15 15l-4 4M15 -15l4 -4"/></g><circle r="13" fill="#fde047" stroke="#0f1218" stroke-width="3"/></g>
    <g class="shades"><rect x="72" y="94" width="24" height="17" rx="7" fill="#0b0d12" class="gls" stroke-width="2.5"/><rect x="104" y="94" width="24" height="17" rx="7" fill="#0b0d12" class="gls" stroke-width="2.5"/><path d="M96 100h8" class="gls" stroke-width="2.5"/><path d="M77 99h6M109 99h6" stroke="#fff" stroke-width="2" stroke-linecap="round" opacity=".7"/></g>`); },
  stats: m => { m.classList.add('pose-point'); add(m.querySelector('.all'), `<g transform="translate(150 70)"><rect width="46" height="44" rx="8" fill="#f8fafc" stroke="#0f1218" stroke-width="3"/>
    <rect class="bar" x="8" y="12" width="8" height="24" rx="2" fill="#60a5fa"/><rect class="bar" x="19" y="20" width="8" height="16" rx="2" fill="#a78bfa" style="animation-delay:.4s"/><rect class="bar" x="30" y="8" width="8" height="28" rx="2" fill="#34d399" style="animation-delay:.8s"/><path d="M6 37h34" stroke="#94a3b8" stroke-width="2"/></g>`); },
  shield: m => { m.classList.add('pose-guard'); add(m.querySelector('.all'), `<g class="shield"><path d="M34 120l24 8v16c0 16-11 25-24 31c-13-6-24-15-24-31v-16z" fill="#22c55e" stroke="#0f1218" stroke-width="3.5" stroke-linejoin="round"/><path d="M24 148l7 7 13-14" stroke="#fff" stroke-width="4.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/></g>`); },
};
const DECO_CSS = `
@keyframes fallx { 0% { transform: translateY(-8px); opacity: 0 } 20% { opacity: 1 } 100% { transform: translateY(18px); opacity: 0 } }
.fallx { animation: fallx 2.8s linear infinite }
@keyframes orbit { to { transform: rotate(360deg) } }
.orbit { transform-box: view-box; transform-origin: 100px 118px; animation: orbit 6s linear infinite }
@keyframes flm { 0%, 100% { opacity: 1 } 50% { opacity: .4 } } .flm { animation: flm .25s linear infinite }
.mascot.hol .p-check { display: none !important }
.p-q { display: none } .mascot.ev-curious .p-q { display: inline; transform-box: view-box; transform-origin: 160px 52px; animation: qpop 1.8s cubic-bezier(.3, 1.5, .5, 1) both }
@keyframes qpop { 0% { transform: scale(0); opacity: 0 } 15% { transform: scale(1.1); opacity: 1 } 25%, 85% { transform: scale(1) } 100% { transform: scale(.6); opacity: 0 } }
.mascot.ev-curious .all { transform-box: view-box; transform-origin: 100px 210px; animation: tilt 1.8s ease-in-out both }
@keyframes tilt { 0%, 100% { transform: rotate(0) } 20%, 45% { transform: rotate(-9deg) translateY(-3px) } 60%, 85% { transform: rotate(7deg) } }
.mascot.ev-curious .cam { transform: translateY(0) !important }
.mascot.ev-curious .eo { transform-box: fill-box; transform-origin: center; animation: wide 1.8s ease-in-out both }
@keyframes wide { 0%, 100% { transform: scale(1) } 15%, 85% { transform: scale(1.18) } }
.mascot.ev-curious .mouth > * { display: none !important } .mascot.ev-curious .m-o { display: inline !important }
.mascot.v2.ev-curious .armR { animation: none; transform: rotate(-115deg) }
@keyframes spd { 0%, 100% { transform: translateX(0); opacity: .9 } 50% { transform: translateX(-6px); opacity: .4 } } .spd path { animation: spd .7s ease-in-out infinite } .spd path:nth-child(2) { animation-delay: .2s } .spd path:nth-child(3) { animation-delay: .4s }
@keyframes needle { 0%, 100% { transform: rotate(10deg) } 50% { transform: rotate(62deg) } } .needle { transform-box: view-box; transform-origin: 0 4px; animation: needle 1.6s ease-in-out infinite }
@keyframes runL { 0%, 100% { transform: rotate(-25deg) } 50% { transform: rotate(25deg) } } @keyframes runR { 0%, 100% { transform: rotate(25deg) } 50% { transform: rotate(-25deg) } }
.mascot.v2.pose-run .armL { animation: runL .5s ease-in-out infinite } .mascot.v2.pose-run .armR { animation: runR .5s ease-in-out infinite }
@keyframes bob { 50% { transform: translateY(-3px) } } .mascot.pose-run .body { animation: bob .5s ease-in-out infinite }
.mascot.v2.pose-chill .armR { animation: none; transform: rotate(-100deg) } .mascot.pose-chill .eyes { opacity: 0 }
@keyframes spinr { to { transform: rotate(360deg) } } .rays { transform-box: view-box; transform-origin: 0 0; animation: spinr 9s linear infinite }
.mascot.v2.pose-point .armR { animation: none; transform: rotate(-58deg) } .mascot.pose-point .pupils { transform: translate(3px, -2px) !important }
@keyframes barg { 0%, 100% { transform: scaleY(1) } 50% { transform: scaleY(.55) } } .bar { transform-box: fill-box; transform-origin: 50% 100%; animation: barg 2.4s ease-in-out infinite }
.mascot.v2.pose-guard .armL { animation: none; transform: rotate(10deg) } .shield { animation: bob 2.4s ease-in-out infinite }
.mascot.pumpkin .eyes, .mascot.pumpkin .mouth, .mascot.coder .mouth { display: none }
@keyframes curb { 0%, 49% { opacity: 1 } 50%, 100% { opacity: 0 } } .cur { animation: curb 1s steps(1) infinite }
`;
