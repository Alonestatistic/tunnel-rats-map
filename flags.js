// DayZ flags and armbands (every Flag_* / Armband_* in the game's types.xml).
// Each icon is a simplified drawing (60x40), not the game texture. `c` = preset colours taken from the flag, main colour first.
(() => {
  const emo = (bg, e, s = 24) => `<rect width="60" height="40" fill="${bg}"/><text x="30" y="22" font-size="${s}" text-anchor="middle" dominant-baseline="middle">${e}</text>`;
  const txt = (bg, t, fg, s = 15, extra = '') => `<rect width="60" height="40" fill="${bg}"/>${extra}<text x="30" y="21" font-size="${s}" font-weight="900" font-family="Arial Black,Arial,sans-serif" fill="${fg}" text-anchor="middle" dominant-baseline="middle">${t}</text>`;
  const rays = (cx, cy, col, n = 12, len = 80) => {
    let s = '';
    for (let i = 0; i < n; i += 2) {
      const a0 = i / n * Math.PI * 2, a1 = (i + 1) / n * Math.PI * 2;
      s += `<polygon points="${cx},${cy} ${(cx + Math.cos(a0) * len).toFixed(1)},${(cy + Math.sin(a0) * len).toFixed(1)} ${(cx + Math.cos(a1) * len).toFixed(1)},${(cy + Math.sin(a1) * len).toFixed(1)}" fill="${col}"/>`;
    }
    return s;
  };
  const star = (cx, cy, r, col) => {
    const p = [];
    for (let i = 0; i < 10; i++) { const a = -Math.PI / 2 + i * Math.PI / 5, rr = i % 2 ? r * .42 : r; p.push((cx + Math.cos(a) * rr).toFixed(1) + ',' + (cy + Math.sin(a) * rr).toFixed(1)); }
    return `<polygon points="${p.join(' ')}" fill="${col}"/>`;
  };
  const F = [
    ['APA', 'Asian Pacific Alliance', ['#c0392b', '#c9a25a', '#2a1a14'], `<rect width="60" height="40" fill="#c9a25a"/>${rays(30, 20, '#b8362b', 16)}<circle cx="30" cy="20" r="9" fill="#2a1a14"/><circle cx="30" cy="20" r="5" fill="none" stroke="#c0392b" stroke-width="2"/>`],
    ['Altis', 'Altis', ['#2e8b3a', '#f2c230', '#111111'], `<rect width="60" height="40" fill="#2e8b3a"/><rect width="60" height="20" fill="#1f6b2a"/><polygon points="0,0 36,20 0,40" fill="#f2c230"/><polygon points="0,4 29,20 0,36" fill="#111"/>`],
    ['BabyDeer', 'Baby Deer', ['#b07a45', '#9c9a92'], emo('#9c9a92', '🦌')],
    ['Bear', 'Bear', ['#a32a1c', '#6e1a12', '#4a3020'], emo('#6e1a12', '🐻')],
    ['Bohemia', 'Bohemia Interactive', ['#d42a2a', '#eeeeea', '#111111'], txt('#eeeeea', 'BI', '#111', 20, '<circle cx="30" cy="20" r="14" fill="none" stroke="#d42a2a" stroke-width="2.5"/>')],
    ['BrainZ', 'BrainZ', ['#e05a7a', '#d6d3cc', '#111111'], emo('#d6d3cc', '🧠')],
    ['CDF', 'Chernarus Defence Forces', ['#e6a400', '#1e6b1e'], `<rect width="60" height="20" fill="#e6a400"/><rect y="20" width="60" height="20" fill="#1e6b1e"/>`],
    ['CHEL', 'CHEL', ['#e2561c', '#e8e2d8', '#111111'], txt('#e8e2d8', 'CHEL', '#d4401a', 15, '<rect x="2" y="2" width="56" height="36" fill="none" stroke="#e2561c" stroke-width="3"/>')],
    ['CMC', 'Chernarus Mining Corp.', ['#d4b000', '#111111'], txt('#c9a600', 'CMC', '#111', 17, '<polygon points="18,12 30,4 42,12" fill="none" stroke="#111" stroke-width="2"/>')],
    ['Cannibals', 'Cannibals', ['#e8e8e8', '#111111', '#8a1010'], emo('#111', '💀')],
    ['Chedaki', 'ChDKZ (Chedaki)', ['#d42020', '#111111'], `<rect width="60" height="40" fill="#111"/><rect y="31" width="60" height="9" fill="#d42020"/>${star(30, 16, 11, '#d42020')}`],
    ['Chernarus', 'Republic of Chernarus', ['#1d8b35', '#f0f0f0', '#f5d000'], `<rect width="60" height="40" fill="#1d6b2a"/><polygon points="0,40 60,26 60,29 0,40" fill="#f0f0f0"/><polygon points="0,40 60,33 60,36 0,40" fill="#f0f0f0"/><polygon points="0,40 60,40 60,39" fill="#f0f0f0"/>${star(10, 10, 6, '#f5d000')}`],
    ['Crook', 'Crook', ['#2f5db0', '#d8d8e8'], emo('#1d3e7a', '❄️', 20)],
    ['DayZ', 'DayZ', ['#e0e0e0', '#111111'], txt('#111', 'DAYZ', '#ddd', 16)],
    ['HunterZ', 'Zombie Hunters', ['#dddddd', '#111111'], `<rect width="60" height="40" fill="#111"/><circle cx="30" cy="20" r="13" fill="none" stroke="#ddd" stroke-width="2.5"/><path d="M30 3v34M13 20h34" stroke="#ddd" stroke-width="1.5"/><circle cx="30" cy="20" r="3" fill="#d22"/>`],
    ['Livonia', 'Livonia', ['#1c4fb0', '#f0f0f0', '#e08a00'], `<rect width="20" height="40" fill="#1c3f8a"/><rect x="20" width="20" height="40" fill="#eee"/><rect x="40" width="20" height="40" fill="#d88a00"/><circle cx="30" cy="20" r="5" fill="#1c3f8a"/>`],
    ['LivoniaArmy', 'Livonian Defence Force', ['#c8a050', '#1c2a44'], `<rect width="60" height="40" fill="#1c2a44"/><path d="M14 30L46 10M14 10L46 30" stroke="#8a6a3a" stroke-width="3"/><circle cx="30" cy="20" r="8" fill="#c8a050"/><circle cx="30" cy="20" r="4" fill="#1c2a44"/>`],
    ['LivoniaPolice', 'Livonia Police', ['#c8a040', '#141a2e'], `<rect width="60" height="40" fill="#141a2e"/>${star(30, 17, 10, '#c8a040')}<rect x="17" y="27" width="26" height="6" fill="#141a2e" stroke="#c8a040" stroke-width="1"/>`],
    ['NAPA', 'National Party (NAPA)', ['#2a7a2a', '#111111', '#d0c820'], `<rect width="30" height="40" fill="#111"/><rect x="30" width="30" height="40" fill="#1f5a1f"/><path d="M8 28L22 12M8 12L22 28" stroke="#d0c820" stroke-width="2.5"/>${star(15, 8, 3.5, '#d0c820')}`],
    ['NSahrani', 'North Sahrani', ['#e08a10', '#111111', '#c02020'], `<rect width="60" height="40" fill="#c87a10"/><polygon points="0,0 60,0 0,40" fill="#111"/><circle cx="34" cy="20" r="7" fill="none" stroke="#c02020" stroke-width="3"/>`],
    ['Pirates', 'Pirates', ['#eeeeee', '#111111'], emo('#111', '☠️')],
    ['RSTA', 'RSTA', ['#9ab0b0', '#2a3436'], `<rect width="60" height="40" fill="#2a3436"/><text x="30" y="21" font-size="16" font-weight="900" font-family="Arial Black,Arial" fill="#3e4c4e" text-anchor="middle" dominant-baseline="middle">RSTA</text><circle cx="38" cy="20" r="8" fill="none" stroke="#c0c8c8" stroke-width="1.8"/><path d="M8 21h44" stroke="#c0c8c8" stroke-width="2.5"/>`],
    ['Refuge', 'Refuge', ['#d8c090', '#33465a'], txt('#33465a', 'REFUGE', '#d8c090', 11)],
    ['Rex', 'Rex', ['#7a4ad0', '#3a1e6a', '#f0f0f0'], `<rect width="60" height="40" fill="#3a1e6a"/><circle cx="30" cy="20" r="12" fill="#f0f0f0"/><text x="30" y="21" font-size="16" text-anchor="middle" dominant-baseline="middle">🐶</text>${star(8, 8, 2.5, '#fff')}${star(52, 33, 2.5, '#fff')}`],
    ['Rooster', 'Rooster', ['#c02020', '#a8a8b0', '#e8c020'], emo('#a8a8b0', '🐓')],
    ['SSahrani', 'South Sahrani', ['#1080a0', '#f0f0f0', '#3a7a20'], `<rect width="60" height="40" fill="#0f5a74"/><rect x="20" width="20" height="40" fill="#eee"/><circle cx="30" cy="20" r="6" fill="#3a7a20"/>`],
    ['Sakhal', 'Sakhal', ['#c41e2a', '#1e3c96', '#f0f0f0'], `<rect width="60" height="40" fill="#f0f0f0"/><rect y="26" width="60" height="14" fill="#1e3c96"/><circle cx="30" cy="22" r="10" fill="#c41e2a"/><polygon points="21,26 30,14 39,26" fill="#111"/><path d="M0 30q7.5 -3 15 0t15 0t15 0t15 0" stroke="#fff" stroke-width="1.5" fill="none"/>`],
    ['Snake', 'Snake', ['#c09a48', '#1a1a1a'], emo('#1a1a1a', '🐍')],
    ['TEC', 'TEC', ['#a8b040', '#1f2a1a'], txt('#1f2a1a', '✶TEC', '#9aa040', 15)],
    ['UEC', 'United Earth Coalition', ['#c8d0d0', '#1a2224'], `<rect width="60" height="40" fill="#1a2224"/><polygon points="0,6 24,20 0,34" fill="#c8d0d0"/><path d="M24 20L60 4M24 20L60 14M24 20L60 26M24 20L60 36" stroke="#c8d0d0" stroke-width="2.5"/>`],
    ['White', 'White', ['#f2f2ee', '#bbbbb5'], `<rect width="60" height="40" fill="#ecebe6"/>`],
    ['Wolf', 'Wolf', ['#3048a8', '#121a40', '#9a9a9a'], emo('#121a40', '🐺')],
    ['Zagorky', 'Zagorky', ['#c82828', '#2a2a2a'], `<rect width="60" height="40" fill="#2a2a2a"/><rect y="30" width="60" height="10" fill="#c82828"/><text x="30" y="18" font-size="18" text-anchor="middle" dominant-baseline="middle">👥</text>`],
    ['Zenit', 'Zenit Radio', ['#e8d040', '#2a2a10'], `<rect width="60" height="40" fill="#2a2a10"/><circle cx="30" cy="20" r="13" fill="none" stroke="#e8d040" stroke-width="2"/>${star(30, 20, 10, '#e8d040')}`],
    // plain-colour armbands
    ['Black', 'Black armband', ['#2a2a2a'], `<rect width="60" height="40" fill="#151515"/>`],
    ['Blue', 'Blue armband', ['#2f6bff'], `<rect width="60" height="40" fill="#2456c8"/>`],
    ['Green', 'Green armband', ['#2fb83a'], `<rect width="60" height="40" fill="#2f8f2f"/>`],
    ['Orange', 'Orange armband', ['#ff7a00'], `<rect width="60" height="40" fill="#ff7a00"/>`],
    ['Pink', 'Pink armband', ['#ff5fb0'], `<rect width="60" height="40" fill="#ff5fb0"/>`],
    ['Red', 'Red armband', ['#e02a2a'], `<rect width="60" height="40" fill="#d92a2a"/>`],
    ['Yellow', 'Yellow armband', ['#f2d000'], `<rect width="60" height="40" fill="#f2d000"/>`],
  ];
  window.FLAGS = F.map(([id, name, c, body]) => ({ id, name, c, svg: `<svg class="flagsvg" viewBox="0 0 60 40" xmlns="http://www.w3.org/2000/svg">${body}<rect width="60" height="40" fill="none" stroke="#000" stroke-opacity=".45" stroke-width="2"/></svg>` }));
  window.FLAG = Object.fromEntries(window.FLAGS.map(f => [f.id, f]));
})();
