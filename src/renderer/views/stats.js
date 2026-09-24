import { actions, getState } from '../lib/state.js';
import { formatMinutesLabel, dateKey, todayKey, monthLabel, isoWeekLabel, startOfWeek, escapeHtml } from '../lib/format.js';
import { renderHeatmap, renderLineChart } from '../lib/svgcharts.js';

let rangeDays = 90;
const now = new Date();
let monthCursor = { year: now.getFullYear(), month: now.getMonth() };

function workSessions() {
  const all = getState().data.sessions.filter(s => s.kind === 'work');
  const filter = getState().statsFilterCourseId;
  if (!filter || filter === 'all') return all;
  return all.filter(s => s.courseId === filter);
}

function sumSecondsInRange(sessions, fromKey, toKey) {
  return sessions.reduce((acc, s) => (s.date >= fromKey && s.date <= toKey) ? acc + s.seconds : acc, 0);
}

function buildCourseOptions() {
  const data = getState().data;
  const groups = new Map(); // ueId -> {ueName, courses:[]}
  for (const course of data.courses) {
    const ue = data.ues.find(u => u.id === course.ueId);
    const key = ue ? ue.id : '__none__';
    if (!groups.has(key)) groups.set(key, { ueName: ue ? ue.name : 'Sans UE', courses: [] });
    groups.get(key).courses.push(course);
  }
  let html = `<option value="all">Tous les cours</option>`;
  for (const { ueName, courses } of groups.values()) {
    html += `<optgroup label="${escapeHtml(ueName)}">`;
    for (const c of courses) html += `<option value="${c.id}">${escapeHtml(c.name)}</option>`;
    html += `</optgroup>`;
  }
  return html;
}

function renderStatCards(sessions) {
  const today = todayKey();
  const weekStart = dateKey(startOfWeek(new Date()));
  const monthStart = `${monthCursor.year}-${String(now.getMonth() + 1).padStart(2, '0')}-01`;
  const thisMonthStart = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-01`;

  const todaySec = sumSecondsInRange(sessions, today, today);
  const weekSec = sumSecondsInRange(sessions, weekStart, today);
  const monthSec = sumSecondsInRange(sessions, thisMonthStart, today);

  return `
    <div class="stats-grid">
      <div class="card stat-card">
        <div class="stat-label">Aujourd'hui</div>
        <div class="stat-value accent">${formatMinutesLabel(todaySec)}</div>
      </div>
      <div class="card stat-card">
        <div class="stat-label">Cette semaine</div>
        <div class="stat-value accent">${formatMinutesLabel(weekSec)}</div>
      </div>
      <div class="card stat-card">
        <div class="stat-label">Ce mois-ci</div>
        <div class="stat-value accent">${formatMinutesLabel(monthSec)}</div>
      </div>
    </div>
  `;
}

function buildMinutesByDateMap(sessions) {
  const map = new Map();
  for (const s of sessions) {
    map.set(s.date, (map.get(s.date) || 0) + s.seconds / 60);
  }
  for (const [k, v] of map) map.set(k, Math.round(v));
  return map;
}

function buildDailySeries(sessions, days) {
  const map = buildMinutesByDateMap(sessions);
  const series = [];
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() - (days - 1));
  for (let i = 0; i < days; i++) {
    const key = dateKey(d);
    series.push({ date: key, minutes: Math.round(map.get(key) || 0) });
    d.setDate(d.getDate() + 1);
  }
  return series;
}

function buildMonthWeeks(sessions, year, month) {
  const first = new Date(year, month, 1);
  const last = new Date(year, month + 1, 0);
  const weekMap = new Map(); // weekLabel -> {label, from, to, seconds}

  for (const s of sessions) {
    const d = new Date(s.date + 'T00:00:00');
    if (d < first || d > last) continue;
    const ws = startOfWeek(d);
    const label = isoWeekLabel(ws);
    if (!weekMap.has(label)) {
      const we = new Date(ws); we.setDate(ws.getDate() + 6);
      weekMap.set(label, { label, from: new Date(ws), to: we, seconds: 0 });
    }
    weekMap.get(label).seconds += s.seconds;
  }
  return Array.from(weekMap.values()).sort((a, b) => a.from - b.from);
}

function monthTotalSeconds(sessions, year, month) {
  const first = `${year}-${String(month + 1).padStart(2, '0')}-01`;
  const last = new Date(year, month + 1, 0);
  const lastKey = dateKey(last);
  return sumSecondsInRange(sessions, first, lastKey);
}

function fmtShortDate(d) { return `${d.getDate()}/${d.getMonth() + 1}`; }

export function renderStatsView() {
  const container = document.getElementById('view-stats');
  if (!container) return;
  const sessions = workSessions();

  container.innerHTML = `
    <h1>Statistiques</h1>
    <p class="subtitle">Ton temps de travail effectif (les pauses ne sont pas comptées).</p>

    <div class="filter-row">
      <label for="statsFilterCourse" style="color:var(--text-muted);font-size:13px;">Filtrer :</label>
      <select id="statsFilterCourse">${buildCourseOptions()}</select>
    </div>

    ${renderStatCards(sessions)}

    <div class="section-title">Activité de l'année</div>
    <div class="card">
      <div class="heatmap-scroll" id="heatmapContainer"></div>
      <div class="heatmap-legend">
        Moins <span class="swatch" style="background:var(--border)"></span>
        <span class="swatch" style="background:color-mix(in srgb, var(--accent) 25%, var(--surface-2))"></span>
        <span class="swatch" style="background:color-mix(in srgb, var(--accent) 50%, var(--surface-2))"></span>
        <span class="swatch" style="background:color-mix(in srgb, var(--accent) 75%, var(--surface-2))"></span>
        <span class="swatch" style="background:var(--accent)"></span> Plus
      </div>
    </div>

    <div class="section-title" style="display:flex;align-items:center;justify-content:space-between;">
      <span>Minutes étudiées par jour</span>
      <select id="rangeSelect" style="padding:5px 8px;border-radius:6px;border:1px solid var(--border);background:var(--surface);">
        <option value="30" ${rangeDays === 30 ? 'selected' : ''}>30 derniers jours</option>
        <option value="90" ${rangeDays === 90 ? 'selected' : ''}>90 derniers jours</option>
        <option value="365" ${rangeDays === 365 ? 'selected' : ''}>365 derniers jours</option>
      </select>
    </div>
    <div class="card"><div id="lineChartContainer"></div></div>

    <div class="section-title" style="display:flex;align-items:center;justify-content:space-between;">
      <span>Détail mensuel</span>
      <div style="display:flex;align-items:center;gap:10px;">
        <button class="icon-btn" id="prevMonth">‹</button>
        <strong id="monthLabel" style="min-width:120px;text-align:center;"></strong>
        <button class="icon-btn" id="nextMonth">›</button>
      </div>
    </div>
    <div class="card">
      <div class="stat-label" style="margin-bottom:10px;">Total du mois : <strong id="monthTotal" style="color:var(--text);font-family:var(--font-mono);"></strong></div>
      <table class="week-table">
        <thead><tr><th>Semaine</th><th>Période</th><th class="dur">Temps</th></tr></thead>
        <tbody id="weekTableBody"></tbody>
      </table>
    </div>
  `;

  document.getElementById('statsFilterCourse').value = getState().statsFilterCourseId;
  document.getElementById('statsFilterCourse').addEventListener('change', (e) => {
    actions.setStatsFilterCourse(e.target.value);
  });

  document.getElementById('rangeSelect').addEventListener('change', (e) => {
    rangeDays = Number(e.target.value);
    renderStatsView();
  });

  document.getElementById('prevMonth').addEventListener('click', () => {
    monthCursor.month -= 1;
    if (monthCursor.month < 0) { monthCursor.month = 11; monthCursor.year -= 1; }
    renderStatsView();
  });
  document.getElementById('nextMonth').addEventListener('click', () => {
    monthCursor.month += 1;
    if (monthCursor.month > 11) { monthCursor.month = 0; monthCursor.year += 1; }
    renderStatsView();
  });

  // Carte thermique
  renderHeatmap(document.getElementById('heatmapContainer'), buildMinutesByDateMap(sessions));

  // Graphique linéaire
  renderLineChart(document.getElementById('lineChartContainer'), buildDailySeries(sessions, rangeDays));

  // Détail mensuel
  document.getElementById('monthLabel').textContent = monthLabel(monthCursor.year, monthCursor.month);
  document.getElementById('monthTotal').textContent = formatMinutesLabel(monthTotalSeconds(sessions, monthCursor.year, monthCursor.month));
  const weeks = buildMonthWeeks(sessions, monthCursor.year, monthCursor.month);
  const tbody = document.getElementById('weekTableBody');
  if (!weeks.length) {
    tbody.innerHTML = `<tr><td colspan="3" class="empty-hint">Aucune activité ce mois-ci.</td></tr>`;
  } else {
    tbody.innerHTML = weeks.map(w => `
      <tr>
        <td>${w.label}</td>
        <td>${fmtShortDate(w.from)} – ${fmtShortDate(w.to)}</td>
        <td class="dur">${formatMinutesLabel(w.seconds)}</td>
      </tr>
    `).join('');
  }
}
