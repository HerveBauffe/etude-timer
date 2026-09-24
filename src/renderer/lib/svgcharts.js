import { dateKey, monthShort, DAYS_FR_SHORT } from './format.js';

const NS = 'http://www.w3.org/2000/svg';
function el(tag, attrs = {}) {
  const e = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v);
  return e;
}

function levelForMinutes(min) {
  if (min <= 0) return 0;
  if (min < 30) return 1;
  if (min < 60) return 2;
  if (min < 120) return 3;
  return 4;
}

/**
 * Dessine une carte thermique façon calendrier de contributions.
 * @param {HTMLElement} container
 * @param {Map<string, number>} minutesByDate - clé "YYYY-MM-DD" -> minutes étudiées
 * @param {{weeks?: number}} options
 */
export function renderHeatmap(container, minutesByDate, { weeks = 53 } = {}) {
  container.innerHTML = '';
  const cell = 12, gap = 3, leftGutter = 26, topGutter = 16;

  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const endOfWeek = new Date(today);
  endOfWeek.setDate(today.getDate() + (6 - ((today.getDay() + 6) % 7))); // dimanche de la semaine courante
  const totalDays = weeks * 7;
  const start = new Date(endOfWeek);
  start.setDate(endOfWeek.getDate() - totalDays + 1);

  const width = leftGutter + weeks * (cell + gap);
  const height = topGutter + 7 * (cell + gap);

  const svg = el('svg', { viewBox: `0 0 ${width} ${height}`, width, height, role: 'img', 'aria-label': 'Carte thermique du temps de travail' });

  // Libellés des jours (lun/mer/ven)
  [0, 2, 4].forEach(dayIdx => {
    const t = el('text', {
      x: 0, y: topGutter + dayIdx * (cell + gap) + cell - 2,
      'font-size': 9, fill: 'var(--text-muted)'
    });
    t.textContent = DAYS_FR_SHORT[(dayIdx + 1) % 7];
    svg.appendChild(t);
  });

  let lastMonth = -1;
  const d = new Date(start);
  for (let w = 0; w < weeks; w++) {
    for (let day = 0; day < 7; day++) {
      const key = dateKey(d);
      if (day === 0 && d.getMonth() !== lastMonth && d <= endOfWeek) {
        lastMonth = d.getMonth();
        const t = el('text', {
          x: leftGutter + w * (cell + gap), y: 10,
          'font-size': 9, fill: 'var(--text-muted)'
        });
        t.textContent = monthShort(d.getMonth());
        svg.appendChild(t);
      }
      if (d <= today) {
        const minutes = minutesByDate.get(key) || 0;
        const level = levelForMinutes(minutes);
        const rect = el('rect', {
          x: leftGutter + w * (cell + gap),
          y: topGutter + day * (cell + gap),
          width: cell, height: cell, rx: 2,
          class: `heat-cell heat-level-${level}`
        });
        const title = el('title');
        title.textContent = `${key} — ${minutes} min`;
        rect.appendChild(title);
        svg.appendChild(rect);
      }
      d.setDate(d.getDate() + 1);
    }
  }

  container.appendChild(svg);

  // Couleurs des niveaux (définies ici pour rester proches du token --accent sans dupliquer le CSS global)
  const style = document.createElement('style');
  style.textContent = `
    .heat-level-0 { fill: var(--border); }
    .heat-level-1 { fill: color-mix(in srgb, var(--accent) 25%, var(--surface-2)); }
    .heat-level-2 { fill: color-mix(in srgb, var(--accent) 50%, var(--surface-2)); }
    .heat-level-3 { fill: color-mix(in srgb, var(--accent) 75%, var(--surface-2)); }
    .heat-level-4 { fill: var(--accent); }
  `;
  container.appendChild(style);
}

/**
 * Dessine un graphique linéaire simple (minutes étudiées par jour).
 * @param {HTMLElement} container
 * @param {{date: string, minutes: number}[]} points - triés par date croissante
 */
export function renderLineChart(container, points, { height = 220 } = {}) {
  container.innerHTML = '';
  if (!points.length) {
    const p = document.createElement('p');
    p.className = 'empty-hint';
    p.textContent = "Pas encore de données pour cette période.";
    container.appendChild(p);
    return;
  }

  const width = Math.max(container.clientWidth || 640, 320);
  const padding = { top: 16, right: 16, bottom: 26, left: 40 };
  const innerW = width - padding.left - padding.right;
  const innerH = height - padding.top - padding.bottom;

  const maxMinutes = Math.max(10, ...points.map(p => p.minutes));
  const niceMax = Math.ceil(maxMinutes / 30) * 30;

  const x = (i) => padding.left + (points.length === 1 ? innerW / 2 : (i / (points.length - 1)) * innerW);
  const y = (v) => padding.top + innerH - (v / niceMax) * innerH;

  const svg = el('svg', { viewBox: `0 0 ${width} ${height}`, width: '100%', height, role: 'img', 'aria-label': "Minutes d'étude par jour" });

  // Lignes de grille horizontales + labels
  const steps = 4;
  for (let i = 0; i <= steps; i++) {
    const v = (niceMax / steps) * i;
    const gy = y(v);
    svg.appendChild(el('line', { x1: padding.left, x2: width - padding.right, y1: gy, y2: gy, stroke: 'var(--border)', 'stroke-width': 1 }));
    const t = el('text', { x: padding.left - 8, y: gy + 3, 'font-size': 10, fill: 'var(--text-muted)', 'text-anchor': 'end' });
    t.textContent = Math.round(v);
    svg.appendChild(t);
  }

  // Aire sous la courbe
  let areaPath = `M ${x(0)} ${y(0)} `;
  points.forEach((p, i) => { areaPath += `L ${x(i)} ${y(p.minutes)} `; });
  areaPath += `L ${x(points.length - 1)} ${y(0)} Z`;
  svg.appendChild(el('path', { d: areaPath, fill: 'var(--accent-soft)', stroke: 'none' }));

  // Ligne
  let linePath = '';
  points.forEach((p, i) => { linePath += (i === 0 ? 'M' : 'L') + ` ${x(i)} ${y(p.minutes)} `; });
  svg.appendChild(el('path', { d: linePath, fill: 'none', stroke: 'var(--accent)', 'stroke-width': 2, 'stroke-linejoin': 'round', 'stroke-linecap': 'round' }));

  // Points avec info-bulle native
  const labelEvery = Math.max(1, Math.ceil(points.length / 8));
  points.forEach((p, i) => {
    const c = el('circle', { cx: x(i), cy: y(p.minutes), r: 2.5, fill: 'var(--accent)' });
    const title = el('title');
    title.textContent = `${p.date} — ${p.minutes} min`;
    c.appendChild(title);
    svg.appendChild(c);

    if (i % labelEvery === 0 || i === points.length - 1) {
      const t = el('text', { x: x(i), y: height - 6, 'font-size': 9, fill: 'var(--text-muted)', 'text-anchor': 'middle' });
      t.textContent = p.date.slice(5); // MM-JJ
      svg.appendChild(t);
    }
  });

  container.appendChild(svg);
}
