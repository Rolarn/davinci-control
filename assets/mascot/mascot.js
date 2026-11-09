// Новый вариант: чёрный AMOLED-экран со светящимся лицом, выдвижная камера из щели в корпусе, ручки-культяпки
function mascotNew(uid, cls) {
  const arm = (x1, y1, x2, y2) => `<path d="M${x1} ${y1}L${x2} ${y2}" stroke="#0f1218" stroke-width="21" stroke-linecap="round"/><path class="strA" d="M${x1} ${y1}L${x2} ${y2}" stroke-width="15" stroke-linecap="round"/>`;
  const flake = (x, y, r) => `<g><g transform="translate(${x} ${y})"><path d="M0 -${r}V${r}M-${r * .87} -${r / 2}L${r * .87} ${r / 2}M-${r * .87} ${r / 2}L${r * .87} -${r / 2}" stroke="#bfe3ff" stroke-width="2.6" stroke-linecap="round"/></g></g>`;
  return `<svg class="mascot v2 ${cls || ''}" viewBox="0 0 200 230" role="img" aria-label="Маскот Davinci" data-state="calm">
  <defs>
    <linearGradient id="sk${uid}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" class="sa"/><stop offset="1" class="sb"/></linearGradient>
    <linearGradient id="sc${uid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#93c5fd" stop-opacity="0"/><stop offset="1" stop-color="#93c5fd" stop-opacity=".55"/></linearGradient>
    <clipPath id="cl${uid}"><rect x="55" y="56" width="90" height="128" rx="24"/></clipPath>
    <filter id="gw${uid}" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="2.3" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  </defs>
  <ellipse cx="100" cy="218" rx="46" ry="6" fill="#000" opacity=".22"/>
  <g class="all">
    <rect x="72" y="182" width="22" height="24" rx="11" class="fillB" stroke="#0f1218" stroke-width="3"/>
    <rect x="106" y="182" width="22" height="24" rx="11" class="fillB" stroke="#0f1218" stroke-width="3"/>
    <g class="armL">${arm(50, 124, 32, 146)}</g>
    <g class="armR">${arm(150, 124, 168, 146)}</g>
    <g class="body">
      <!-- выдвижная камера: низ прямоугольный и всегда остаётся внутри корпуса -->
      <g class="cam">
        <path d="M70 52V17a9 9 0 0 1 9-9h12a9 9 0 0 1 9 9v35z" fill="#1b1e25" stroke="#0f1218" stroke-width="3"/>
        <circle cx="85" cy="22" r="7.5" fill="#0a0c10" stroke="#3b4a63" stroke-width="2"/>
        <circle cx="87.5" cy="19.5" r="2" fill="#fff"/>
        <path class="camled" d="M73.5 46V18a6 6 0 0 1 6-6h11a6 6 0 0 1 6 6v28" fill="none" stroke-width="2.5"/>
        <g class="prop p-flash"><circle class="flashc" cx="85" cy="22" r="16" fill="#fff"/></g>
      </g>
      <rect class="rim" x="44" y="44" width="112" height="152" rx="30" fill="url(#sk${uid})" stroke="#0f1218" stroke-width="3.5"/>
      <rect x="69" y="42.5" width="32" height="4" rx="2" fill="#0f1218"/>
      <path class="flame" d="M49 162c12-14 5-30 15-46M151 84c-10 16-3 30-13 48" fill="none" stroke-width="3" stroke-linecap="round" opacity=".6"/>
      <rect x="154" y="80" width="5" height="22" rx="2.5" fill="#2a2f38"/>
      <rect x="154" y="108" width="5" height="13" rx="2.5" fill="#e53935"/>
      <rect x="55" y="56" width="90" height="128" rx="24" fill="#05070b"/>
      <ellipse cx="80" cy="70" rx="24" ry="7" fill="#fff" opacity=".06" transform="rotate(-20 80 70)"/>
      <g clip-path="url(#cl${uid})"><g class="prop p-scan"><g class="scanline"><rect x="55" y="40" width="90" height="22" fill="url(#sc${uid})"/><rect x="55" y="60" width="90" height="2.5" fill="#dbeafe"/></g></g></g>
      <g class="face" filter="url(#gw${uid})">
        <g class="eyes">
          <g class="eo"><g class="lids"><g class="pupils">
            <ellipse class="gl" cx="84" cy="104" rx="9.5" ry="12"/><ellipse class="gl" cx="116" cy="104" rx="9.5" ry="12"/>
            <circle cx="87.5" cy="99.5" r="2.8" fill="#fff"/><circle cx="119.5" cy="99.5" r="2.8" fill="#fff"/></g></g></g>
          <g class="e-happy"><path class="gls" d="M74 107q10-12 20 0M106 107q10-12 20 0" stroke-width="5" fill="none" stroke-linecap="round"/></g>
          <g class="e-sleep"><path class="gls" d="M75 103q9 7 18 0M107 103q9 7 18 0" stroke-width="4.5" fill="none" stroke-linecap="round"/></g>
          <g class="e-relax"><path class="gls" d="M76 98l10 6-10 6M124 98l-10 6 10 6" stroke-width="4.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/></g>
          <g class="e-tired"><path class="gl" d="M74.5 101h19a9.5 9 0 0 1-19 0zM106.5 101h19a9.5 9 0 0 1-19 0z"/></g>
          <g class="e-squint"><path class="gls" d="M74 104q10-5 20 0M106 104q10-5 20 0" stroke-width="5" fill="none" stroke-linecap="round"/></g>
          <g class="e-wink"><ellipse class="gl" cx="84" cy="104" rx="9.5" ry="12"/><circle cx="87.5" cy="99.5" r="2.8" fill="#fff"/>
            <path class="gls" d="M106 106q10-10 20 0" stroke-width="5" fill="none" stroke-linecap="round"/></g>
          <g class="brows prop"><path class="gls" d="M74 89l17-5M126 89l-17-5" stroke-width="4" stroke-linecap="round"/></g>
        </g>
        <g class="mouth" fill="none" stroke-linecap="round">
          <path class="m-smile gls" d="M94 122q6 6 12 0" stroke-width="3.8"/>
          <path class="m-big gl" d="M91 121q9 11 18 0z"/>
          <ellipse class="m-o gl" cx="100" cy="126" rx="4" ry="5"/>
          <path class="m-flat gls" d="M94 125h12" stroke-width="3.8"/>
          <path class="m-wavy gls" d="M89 125q2.75-3.5 5.5 0t5.5 0t5.5 0t5.5 0" stroke-width="3.3"/>
          <path class="m-worry gls" d="M94 127q6-5 12 0" stroke-width="3.8"/>
        </g>
        <g class="prop p-bolt"><path class="gl" d="M103 146l-11 15h8l-4 13 13-17h-8z"/></g>
        <g class="prop p-low"><rect class="gls" x="84" y="150" width="32" height="15" rx="4" fill="none" stroke-width="2.5"/><rect class="gl" x="116" y="155" width="3" height="5" rx="1"/><rect class="lowbar" x="87" y="153" width="6" height="9" rx="1.5" fill="#ff6b6b"/></g>
      </g>
    </g>
    <!-- ручной вентилятор: лопасти крутятся -->
    <g class="prop p-fan">
      <rect x="20" y="99" width="7" height="26" rx="3.5" fill="#64748b" stroke="#0f1218" stroke-width="2.5"/>
      <circle cx="23.5" cy="80" r="21" fill="#e2e8f0" stroke="#0f1218" stroke-width="3"/>
      <g class="blades"><path d="M23.5 80c-2.5-11.25 2.5-17.5 7.5-16.25s3.75 10-7.5 16.25zM23.5 80c11.25-2.5 17.5 2.5 16.25 7.5s-10 3.75-16.25-7.5zM23.5 80c2.5 11.25-2.5 17.5-7.5 16.25s-3.75-10 7.5-16.25zM23.5 80c-11.25 2.5-17.5-2.5-16.25-7.5s10-3.75 16.25 7.5z" fill="#60a5fa"/></g>
      <circle cx="23.5" cy="80" r="4" fill="#0f1218"/>
      <circle cx="23.5" cy="80" r="21" fill="none" stroke="#94a3b8" stroke-width="1.2" stroke-dasharray="2 3"/>
      <g class="wind" stroke="#bfe3ff" stroke-width="2.5" stroke-linecap="round" fill="none"><path d="M48 73q6-3 12 0"/><path d="M48 85q6 3 12 0"/></g>
    </g>
    <g class="prop p-snow">${flake(30, 62, 6)}${flake(170, 86, 5)}${flake(40, 30, 4.5)}${flake(178, 58, 4)}</g>
    <g class="prop p-sparks" fill="#fde047"><path class="spark" d="M30 70l3 7 7 3-7 3-3 7-3-7-7-3 7-3z"/><path class="spark" d="M176 176l2.5 5.5 5.5 2.5-5.5 2.5-2.5 5.5-2.5-5.5-5.5-2.5 5.5-2.5z"/><path class="spark" d="M172 54l2 4.5 4.5 2-4.5 2-2 4.5-2-4.5-4.5-2 4.5-2z"/></g>
    <g class="prop p-sweat"><path d="M160 58q6 9 0 14a5 5 0 0 1-6-6q2-4 6-8z" fill="#7dd3fc" stroke="#0f1218" stroke-width="2"/></g>
    <g class="prop p-pause badge"><circle cx="160" cy="40" r="14" fill="#38bdf8" stroke="#0f1218" stroke-width="3"/><rect x="154" y="33" width="4" height="14" rx="1.5" fill="#fff"/><rect x="162" y="33" width="4" height="14" rx="1.5" fill="#fff"/></g>
    <g class="prop p-check badge"><circle cx="160" cy="40" r="14" fill="#22c55e" stroke="#0f1218" stroke-width="3"/><path d="M153 40l5 5 9-10" stroke="#fff" stroke-width="3.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/></g>
    <g class="prop p-check2 badge"><circle cx="160" cy="40" r="14" fill="#22c55e" stroke="#0f1218" stroke-width="3"/><path d="M153 40l5 5 9-10" stroke="#fff" stroke-width="3.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/></g>
    <g class="prop p-alert"><g class="bub"><path d="M150 18h28a8 8 0 0 1 8 8v14a8 8 0 0 1-8 8h-18l-10 8 2-8a8 8 0 0 1-8-8V26a8 8 0 0 1 8-8z" fill="#fff" stroke="#0f1218" stroke-width="3"/>
      <rect x="161.5" y="23" width="5" height="14" rx="2.5" fill="#f59e0b"/><circle cx="164" cy="42" r="2.8" fill="#f59e0b"/></g></g>
    <g class="prop p-zzz" fill="#c4b5fd" font-family="Unbounded, sans-serif" font-weight="700"><text class="z" x="150" y="44" font-size="16">z</text><text class="z" x="150" y="44" font-size="13">z</text><text class="z" x="150" y="44" font-size="10">z</text></g>
  </g>
</svg>`;
}

const SKINS = {
  blue:  { a: '#3f8cff', b: '#0b1d5c', c: '#8fd3ff' },
  red:   { a: '#ff3d74', b: '#6b0d2c', c: '#ffc2d3' },
  black: { a: '#4a505b', b: '#17191e', c: '#6b7280', rim: '#5d6573' },
};

// Создать маскота: состояние и цвет корпуса. / Create a mascot with a state and a body colour.
let MASCOT_UID = 0;
function makeMascot(state, skin) {
  const wrap = document.createElement('span');
  wrap.innerHTML = mascotNew('m' + (MASCOT_UID++));
  const svg = wrap.firstElementChild;
  svg.dataset.state = state || 'calm';
  const g = document.createElementNS('http://www.w3.org/2000/svg', 'g');
  g.innerHTML = '<g class="p-q"><path d="M150 18h28a8 8 0 0 1 8 8v14a8 8 0 0 1-8 8h-18l-10 8 2-8a8 8 0 0 1-8-8V26a8 8 0 0 1 8-8z" fill="#fff" stroke="#0f1218" stroke-width="3"/><text x="164" y="42" text-anchor="middle" font-family="system-ui" font-weight="900" font-size="20" fill="#3b82f6">?</text></g>';
  svg.querySelector('.all').appendChild(g);
  skinMascot(svg, skin || 'blue');
  return svg;
}
function skinMascot(m, k) {
  const s = SKINS[k] || SKINS.blue;
  m.querySelectorAll('.sa').forEach(e => e.setAttribute('stop-color', s.a));
  m.querySelectorAll('.sb').forEach(e => e.setAttribute('stop-color', s.b));
  m.querySelectorAll('.fillA').forEach(e => e.setAttribute('fill', s.a));
  m.querySelectorAll('.fillB').forEach(e => e.setAttribute('fill', s.b));
  m.querySelectorAll('.strA').forEach(e => e.setAttribute('stroke', s.a));
  m.querySelectorAll('.flame').forEach(e => e.setAttribute('stroke', s.c));
  m.querySelectorAll('.rim').forEach(e => e.setAttribute('stroke', s.rim || '#0f1218'));
}
// Событие-анимация: tap, applied, curious. / one-shot animation.
function mascotFire(m, ev) {
  m.classList.remove('ev-' + ev); void m.getBoundingClientRect(); m.classList.add('ev-' + ev);
  clearTimeout(m['_t' + ev]); m['_t' + ev] = setTimeout(() => m.classList.remove('ev-' + ev), ev === 'tap' ? 650 : ev === 'curious' ? 1900 : 1100);
}
