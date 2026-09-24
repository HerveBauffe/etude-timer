import { actions, getState, getCourseById, getUEForCourse, getLastNoteForCourse } from '../lib/state.js';
import { formatHMS, relativeDate, escapeHtml, escapeHtmlMultiline } from '../lib/format.js';
import { promptNote, promptDuration, confirmDialog } from '../lib/modal.js';

const RING_R = 130;
const CIRCUMFERENCE = 2 * Math.PI * RING_R;

let mode = 'pomodoro'; // 'pomodoro' | 'flow'

// Modèle de temps basé sur un cumul de secondes écoulées avant la pause en cours + le segment
// actif (depuis segmentStartedAt). Ça permet la pause/reprise ET le dépassement (le travail ne
// s'arrête jamais tout seul), sans avoir à recalculer une échéance à chaque fois.
const pomo = {
  phase: 'idle', // idle | work | break | longbreak | break-ended | cycle-complete
  blockIndex: 1,
  totalSeconds: 0,
  elapsedBeforePause: 0,
  segmentStartedAt: null,
  paused: false,
  overtimeNotified: false,
  courseId: null
};

const flow = { phase: 'idle', startedAt: null, reviewElapsedSeconds: 0, breakEndsAt: null, breakTotalSeconds: 0, courseId: null };

let tickHandle = null;

// ---------- Réglages ----------
function getPomodoroConfig() { return getState().data.settings.pomodoro; }
function getFlowConfig() { return getState().data.settings.flow; }

function courseLabel(courseId) {
  const course = getCourseById(courseId);
  if (!course) return '';
  const ue = getUEForCourse(courseId);
  return ue ? `${ue.name} — ${course.name}` : course.name;
}

function isBusy() {
  return (mode === 'pomodoro' && ['work', 'break', 'longbreak'].includes(pomo.phase)) ||
         (mode === 'flow' && ['working', 'review', 'break'].includes(flow.phase));
}

function getDisplayCourseId() {
  if (mode === 'pomodoro' && pomo.phase !== 'idle') return pomo.courseId;
  if (mode === 'flow' && isBusy()) return flow.courseId;
  return getState().selectedCourseId;
}

// ---------- Son + notification ----------
function playBeep() {
  try {
    const Ctx = window.AudioContext || window.webkitAudioContext;
    const ctx = new Ctx();
    const now = ctx.currentTime;
    [0, 0.18, 0.36].forEach((t, i) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.value = i === 2 ? 880 : 660;
      gain.gain.setValueAtTime(0.0001, now + t);
      gain.gain.exponentialRampToValueAtTime(0.25, now + t + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + t + 0.16);
      osc.connect(gain).connect(ctx.destination);
      osc.start(now + t);
      osc.stop(now + t + 0.2);
    });
    setTimeout(() => ctx.close(), 1200);
  } catch (err) { console.error('Bip impossible :', err); }
}

function showBanner(text, kind) {
  const el = document.createElement('div');
  el.className = 'phase-end-banner' + (kind === 'flow' ? ' flow' : '');
  el.textContent = text;
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 4000);
}

// ---------- Temps écoulé (pause/reprise) ----------
function getPomoElapsedSeconds() {
  const extra = (pomo.paused || !pomo.segmentStartedAt) ? 0 : (Date.now() - pomo.segmentStartedAt) / 1000;
  return pomo.elapsedBeforePause + extra;
}

// ---------- Tick ----------
function startTicking() {
  stopTicking();
  tickHandle = setInterval(updateTick, 500);
  updateTick();
}
function stopTicking() { if (tickHandle) clearInterval(tickHandle); tickHandle = null; }

function setDigits(text, overtime) {
  const d = document.getElementById('timerDigits');
  if (d) d.textContent = text;
  if (d) d.classList.toggle('overtime', !!overtime);
}
function setRingProgress(fraction, overtime) {
  const path = document.getElementById('timerRingProgress');
  if (!path) return;
  const f = Math.min(1, Math.max(0, fraction));
  path.setAttribute('stroke-dasharray', CIRCUMFERENCE);
  path.setAttribute('stroke-dashoffset', CIRCUMFERENCE * (1 - f));
  path.classList.toggle('overtime', !!overtime);
}
function setPhaseLabelText(text, overtime) {
  const label = document.getElementById('timerPhaseLabel');
  if (!label) return;
  label.textContent = text;
  label.classList.toggle('overtime', !!overtime);
}

function updateTick() {
  if (mode === 'pomodoro') {
    const cfg = getPomodoroConfig();
    if (pomo.phase === 'work') {
      const elapsed = getPomoElapsedSeconds();
      const remaining = pomo.totalSeconds - elapsed;
      const N = cfg.blocksBeforeLongBreak;
      if (remaining > 0) {
        setDigits(formatHMS(remaining), false);
        setRingProgress(elapsed / pomo.totalSeconds, false);
        setPhaseLabelText(`Bloc ${pomo.blockIndex}/${N} · Travail${pomo.paused ? ' (en pause)' : ''}`, false);
      } else {
        if (!pomo.overtimeNotified) {
          pomo.overtimeNotified = true;
          playBeep();
          window.api.notifyPhaseEnd({ title: `${cfg.workMin} min atteintes`, body: courseLabel(pomo.courseId) + ' — continue ou passe à la pause quand tu veux.' });
          showBanner(`${cfg.workMin} minutes atteintes — continue si tu veux !`, 'pomodoro');
        }
        setDigits(formatHMS(elapsed), true);
        setRingProgress(1, true);
        setPhaseLabelText(`Bloc ${pomo.blockIndex}/${N} · Travail (dépassement)${pomo.paused ? ' — en pause' : ''}`, true);
      }
    } else if (pomo.phase === 'break' || pomo.phase === 'longbreak') {
      const elapsed = getPomoElapsedSeconds();
      const remaining = pomo.totalSeconds - elapsed;
      if (remaining <= 0) { naturalBreakEnd(); return; }
      setDigits(formatHMS(remaining), false);
      setRingProgress(elapsed / pomo.totalSeconds, false);
      setPhaseLabelText((pomo.phase === 'longbreak' ? 'Pause longue' : 'Pause courte') + (pomo.paused ? ' (en pause)' : ''), false);
    }
  } else if (mode === 'flow' && flow.phase === 'working') {
    setDigits(formatHMS(Math.round((Date.now() - flow.startedAt) / 1000)), false);
  } else if (mode === 'flow' && flow.phase === 'break') {
    const remaining = Math.max(0, Math.round((flow.breakEndsAt - Date.now()) / 1000));
    setDigits(formatHMS(remaining), false);
    setRingProgress(remaining / flow.breakTotalSeconds, false);
    if (remaining <= 0) stopFlowBreak('natural');
  }
}

// ---------- Pomodoro : démarrage des phases ----------
function startPhase(phaseName, totalSeconds, courseId) {
  pomo.phase = phaseName;
  pomo.totalSeconds = totalSeconds;
  pomo.elapsedBeforePause = 0;
  pomo.segmentStartedAt = Date.now();
  pomo.paused = false;
  pomo.overtimeNotified = false;
  if (courseId) pomo.courseId = courseId;
  startTicking();
  renderTimerCore();
}

function startWork() {
  const courseId = getState().selectedCourseId;
  if (!courseId) return;
  const cfg = getPomodoroConfig();
  startPhase('work', cfg.workMin * 60, courseId);
}

// ---------- Pause / Reprendre (interruption rapide, sans compter de pause) ----------
function togglePomoPause() {
  if (pomo.paused) {
    pomo.segmentStartedAt = Date.now();
    pomo.paused = false;
    startTicking();
  } else {
    pomo.elapsedBeforePause = getPomoElapsedSeconds();
    pomo.segmentStartedAt = null;
    pomo.paused = true;
    stopTicking();
  }
  renderTimerCore();
}

// ---------- Enregistrement silencieux du travail (jamais de note ici) ----------
function logWorkIfAny(completed) {
  if (pomo.phase !== 'work') return;
  const elapsed = Math.round(getPomoElapsedSeconds());
  if (elapsed < 1) return;
  const courseId = pomo.courseId;
  const end = new Date();
  const start = new Date(end.getTime() - elapsed * 1000);
  actions.addSession({ courseId, mode: 'pomodoro', kind: 'work', start: start.toISOString(), end: end.toISOString(), seconds: elapsed, completed, note: '' });
}

// ---------- Passer directement au bloc suivant (sans note, sans logguer la pause) ----------
function skipPhase() {
  const cfg = getPomodoroConfig();
  const wasWork = pomo.phase === 'work';
  const wasLongBreak = pomo.phase === 'longbreak';
  stopTicking();

  if (wasWork) {
    logWorkIfAny(true);
    const isLongNext = pomo.blockIndex >= cfg.blocksBeforeLongBreak;
    startPhase(isLongNext ? 'longbreak' : 'break', (isLongNext ? cfg.longBreakMin : cfg.shortBreakMin) * 60);
  } else {
    if (wasLongBreak) { pomo.blockIndex = 1; } else { pomo.blockIndex += 1; }
    startPhase('work', cfg.workMin * 60);
  }
}

// ---------- Fin naturelle d'une pause (jamais loguée, ça ne sert pas) ----------
function naturalBreakEnd() {
  const wasLongBreak = pomo.phase === 'longbreak';
  stopTicking();
  playBeep();
  window.api.notifyPhaseEnd({ title: wasLongBreak ? 'Pause longue terminée' : 'Pause terminée', body: courseLabel(pomo.courseId) });
  showBanner(wasLongBreak ? 'Pause longue terminée !' : 'Pause terminée !', 'pomodoro');
  if (wasLongBreak) {
    pomo.phase = 'cycle-complete';
    pomo.blockIndex = 1;
  } else {
    pomo.blockIndex += 1;
    pomo.phase = 'break-ended';
  }
  renderTimerCore();
}

// ---------- Terminer la session d'étude (seul endroit où l'on demande une note) ----------
async function endStudySession() {
  const wasWork = pomo.phase === 'work';
  const courseId = pomo.courseId || getState().selectedCourseId;

  stopTicking();
  if (wasWork) logWorkIfAny(true);

  pomo.phase = 'idle';
  pomo.blockIndex = 1;
  pomo.paused = false;
  renderTimerView();

  if (courseId) {
    const note = await promptNote({ title: 'Où en es-tu ?', message: 'Note un repère pour reprendre plus facilement la prochaine fois (optionnel).' });
    if (note) {
      await actions.addSession({ courseId, mode: null, kind: 'note', start: new Date().toISOString(), end: new Date().toISOString(), seconds: 0, completed: true, note });
    }
  }
}

// ---------- Flow Zone (inchangé) ----------
function startFlowWork() {
  const courseId = getState().selectedCourseId;
  if (!courseId) return;
  flow.courseId = courseId;
  flow.phase = 'working';
  flow.startedAt = Date.now();
  startTicking();
  renderTimerCore();
}

function stopFlowWork() {
  stopTicking();
  flow.reviewElapsedSeconds = Math.round((Date.now() - flow.startedAt) / 1000);
  flow.phase = 'review';
  renderTimerCore();
}

async function confirmFlowReview(withBreak) {
  const noteInput = document.getElementById('flowNoteInput');
  const note = noteInput ? noteInput.value.trim() : '';
  const cfg = getFlowConfig();
  const elapsed = flow.reviewElapsedSeconds;
  const startedAt = flow.startedAt;
  const courseId = flow.courseId;

  if (withBreak) {
    const breakSeconds = Math.max(1, Math.round(elapsed * (cfg.breakPercent / 100)));
    flow.phase = 'break';
    flow.startedAt = Date.now();
    flow.breakTotalSeconds = breakSeconds;
    flow.breakEndsAt = Date.now() + breakSeconds * 1000;
    startTicking();
  } else {
    flow.phase = 'idle';
  }
  renderTimerCore();

  await actions.addSession({
    courseId, mode: 'flow', kind: 'work',
    start: new Date(startedAt).toISOString(), end: new Date(startedAt + elapsed * 1000).toISOString(),
    seconds: elapsed, completed: true, note
  });
}

function stopFlowBreak(reason) {
  const startedAt = flow.startedAt;
  const courseId = flow.courseId;
  stopTicking();
  const elapsed = Math.round((Date.now() - startedAt) / 1000);
  const naturalEnd = reason === 'natural';
  flow.phase = 'idle';
  renderTimerCore();

  if (naturalEnd) {
    playBeep();
    window.api.notifyPhaseEnd({ title: 'Pause terminée', body: courseLabel(courseId) });
    showBanner('Pause terminée !', 'flow');
  }

  actions.addSession({
    courseId, mode: 'flow', kind: 'break',
    start: new Date(startedAt).toISOString(), end: new Date().toISOString(),
    seconds: elapsed, completed: naturalEnd, note: ''
  });
}

// ---------- Note libre / temps manuel (sans minuteur) ----------
async function quickAddNote() {
  const courseId = getState().selectedCourseId;
  if (!courseId) return;
  const text = await promptNote({ title: 'Ajouter une note', message: 'Un repère pour la prochaine fois.' });
  if (text) {
    await actions.addSession({
      courseId, mode: null, kind: 'note',
      start: new Date().toISOString(), end: new Date().toISOString(),
      seconds: 0, completed: true, note: text
    });
  }
}

async function quickAddTime() {
  const courseId = getState().selectedCourseId;
  if (!courseId) return;
  const result = await promptDuration({ title: 'Ajouter du temps manuellement', message: "Utile si tu as oublié de lancer ou d'arrêter le minuteur." });
  if (!result) return;
  const start = `${result.date}T12:00:00.000Z`;
  const end = new Date(new Date(start).getTime() + result.minutes * 60000).toISOString();
  await actions.addSession({
    courseId, mode: null, kind: 'work',
    start, end, seconds: result.minutes * 60, completed: true, note: '', date: result.date
  });
}

async function editSessionTime(sessionId) {
  const session = getState().data.sessions.find(s => s.id === sessionId);
  if (!session) return;
  const result = await promptDuration({
    title: 'Corriger cette durée',
    initialMinutes: Math.round(session.seconds / 60) || 1,
    initialDate: session.date,
    confirmLabel: 'Mettre à jour'
  });
  if (!result) return;
  await actions.updateSessionTime(sessionId, { seconds: result.minutes * 60, date: result.date });
}

// ---------- Rendu ----------
function renderLastNoteBanner(courseId) {
  const last = getLastNoteForCourse(courseId);
  if (!last) {
    return `<p class="empty-hint" style="text-align:center;max-width:440px;">Pas encore de note de reprise pour ce cours.</p>`;
  }
  return `
    <div class="card" style="max-width:460px;width:100%;">
      <div style="color:var(--text-muted);font-size:12px;margin-bottom:4px;">📝 Reprise · ${relativeDate(last.end || last.start)}</div>
      <div>${escapeHtmlMultiline(last.note)}</div>
    </div>
  `;
}

function renderSessionAndNoteLog(courseId) {
  const items = getState().data.sessions
    .filter(s => s.courseId === courseId)
    .sort((a, b) => new Date(b.end || b.start) - new Date(a.end || a.start))
    .slice(0, 8);
  if (!items.length) return '';

  const rows = items.map(s => {
    const kindLabel = s.kind === 'work' ? (s.mode === 'flow' ? 'Flow' : 'Travail') : s.kind === 'break' ? 'Pause' : 'Note';
    const dur = s.seconds > 0 ? `<span class="dur">${formatHMS(s.seconds)}</span>` : '';
    const editBtn = s.kind !== 'note' ? `<button class="icon-btn" data-edit-session="${s.id}" title="Corriger la durée">✎</button>` : '';
    const noteHtml = s.note ? `<div style="color:var(--text-muted);margin-top:3px;font-size:12.5px;">${escapeHtmlMultiline(s.note)}</div>` : '';
    return `
      <li style="align-items:flex-start;">
        <div style="flex:1;">
          <div>${kindLabel} · ${relativeDate(s.end || s.start)}</div>
          ${noteHtml}
        </div>
        ${dur}
        ${editBtn}
        <button class="icon-btn" data-del-session="${s.id}" title="Supprimer" style="margin-left:2px;">✕</button>
      </li>
    `;
  }).join('');

  return `
    <div class="session-log">
      <h3>Historique récent</h3>
      <ul>${rows}</ul>
    </div>
  `;
}

function renderControlsAndPhaseLabel() {
  const controls = document.getElementById('timerControls');
  const course = getState().selectedCourseId;
  const cfg = getPomodoroConfig();

  if (mode === 'pomodoro') {
    const N = cfg.blocksBeforeLongBreak;
    if (pomo.phase === 'idle') {
      controls.innerHTML = `<button class="btn btn-primary" id="btnStart" ${course ? '' : 'disabled'}>Démarrer le bloc 1/${N} (${cfg.workMin} min)</button>`;
      document.getElementById('btnStart').addEventListener('click', startWork);
    } else if (pomo.phase === 'work' || pomo.phase === 'break' || pomo.phase === 'longbreak') {
      controls.innerHTML = `
        <button class="btn" id="btnPause">${pomo.paused ? 'Reprendre' : 'Pause'}</button>
        <button class="btn" id="btnSkip">Passer</button>
      `;
      document.getElementById('btnPause').addEventListener('click', togglePomoPause);
      document.getElementById('btnSkip').addEventListener('click', skipPhase);
    } else if (pomo.phase === 'break-ended') {
      controls.innerHTML = `<button class="btn btn-primary" id="btnStartWork">Démarrer le bloc ${pomo.blockIndex}/${N} (${cfg.workMin} min)</button>`;
      document.getElementById('btnStartWork').addEventListener('click', startWork);
    } else if (pomo.phase === 'cycle-complete') {
      controls.innerHTML = `<button class="btn btn-primary" id="btnNewCycle">Nouveau cycle</button>`;
      document.getElementById('btnNewCycle').addEventListener('click', () => { pomo.phase = 'idle'; renderTimerCore(); });
    }
  } else {
    if (flow.phase === 'idle') {
      controls.innerHTML = `<button class="btn btn-flow" id="btnFlowStart" ${course ? '' : 'disabled'}>Démarrer</button>`;
      document.getElementById('btnFlowStart').addEventListener('click', startFlowWork);
    } else if (flow.phase === 'working') {
      controls.innerHTML = `<button class="btn btn-danger" id="btnFlowStop">Arrêter</button>`;
      document.getElementById('btnFlowStop').addEventListener('click', stopFlowWork);
    } else if (flow.phase === 'break') {
      controls.innerHTML = `<button class="btn btn-danger" id="btnFlowBreakStop">Arrêter la pause</button>`;
      document.getElementById('btnFlowBreakStop').addEventListener('click', () => stopFlowBreak('manual'));
    }
  }

  // Bouton discret pour clore toute la session d'étude (c'est ici, et ici seulement,
  // que la note de reprise est proposée).
  const endWrap = document.getElementById('timerEndSession');
  if (endWrap) {
    const show = mode === 'pomodoro' && pomo.phase !== 'idle';
    endWrap.hidden = !show;
    if (show) endWrap.innerHTML = `<button class="btn btn-ghost btn-sm" id="btnEndSession">Terminer la session d'étude</button>`;
    const btn = document.getElementById('btnEndSession');
    if (btn) btn.addEventListener('click', endStudySession);
  }
}

function renderTimerCore() {
  const core = document.getElementById('timerCore');
  if (!core) return;

  if (mode === 'flow' && flow.phase === 'review') {
    const cfg = getFlowConfig();
    const breakSeconds = Math.max(1, Math.round(flow.reviewElapsedSeconds * (cfg.breakPercent / 100)));
    core.innerHTML = `
      <div class="flow-earned">
        <div>Séance terminée : <strong>${formatHMS(flow.reviewElapsedSeconds)}</strong> de travail</div>
        <div class="value">+ ${formatHMS(breakSeconds)} de pause méritée (${cfg.breakPercent}%)</div>
      </div>
      <textarea id="flowNoteInput" rows="3" placeholder="Où en es-tu ? (optionnel)"
        style="width:100%;max-width:420px;padding:9px 10px;border-radius:7px;border:1px solid var(--border);background:var(--surface-2);font-family:inherit;resize:vertical;"></textarea>
      <div class="timer-controls">
        <button class="btn" id="btnFlowNoBreak">Enregistrer sans pause</button>
        <button class="btn btn-flow" id="btnFlowWithBreak">Enregistrer et démarrer la pause</button>
      </div>
    `;
    document.getElementById('btnFlowNoBreak').addEventListener('click', () => confirmFlowReview(false));
    document.getElementById('btnFlowWithBreak').addEventListener('click', () => confirmFlowReview(true));
    return;
  }

  core.innerHTML = `
    <div class="timer-ring-wrap">
      <svg viewBox="0 0 300 300" width="300" height="300">
        <circle class="timer-ring-bg" cx="150" cy="150" r="${RING_R}"></circle>
        <circle class="timer-ring-progress ${mode === 'flow' ? 'flow' : ''}" id="timerRingProgress" cx="150" cy="150" r="${RING_R}"
          stroke-dasharray="${CIRCUMFERENCE}" stroke-dashoffset="${CIRCUMFERENCE}"></circle>
      </svg>
      <div class="timer-display">
        <div class="timer-digits" id="timerDigits">00:00</div>
        <div class="timer-phase ${mode === 'flow' ? 'flow' : ''}" id="timerPhaseLabel">${mode === 'pomodoro' ? 'Prêt à démarrer' : ''}</div>
      </div>
    </div>
    <div class="timer-controls" id="timerControls"></div>
    <div class="timer-end-session" id="timerEndSession" hidden></div>
  `;

  renderControlsAndPhaseLabel();
  updateTick();
}

export function renderTimerView() {
  const container = document.getElementById('view-timer');
  if (!container) return;
  const displayCourseId = getDisplayCourseId();
  const course = displayCourseId ? getCourseById(displayCourseId) : null;
  const ue = course ? getUEForCourse(displayCourseId) : null;
  const busy = isBusy();

  container.innerHTML = `
    <h1>Minuteur</h1>
    <p class="subtitle">Choisis un cours dans la barre latérale, puis lance une session.</p>
    <div class="timer-layout">
      <div class="mode-switch">
        <button class="${mode === 'pomodoro' ? 'active pomodoro' : ''}" id="modeBtnPomodoro" ${busy ? 'disabled' : ''}>Pomodoro</button>
        <button class="${mode === 'flow' ? 'active flow' : ''}" id="modeBtnFlow" ${busy ? 'disabled' : ''}>Flow Zone</button>
      </div>

      <div class="course-picker">
        ${course
          ? `Cours actif : <strong>${escapeHtml(ue ? ue.name + ' — ' : '')}${escapeHtml(course.name)}</strong>${busy ? '' : ` <button class="icon-btn" id="btnQuickNote" title="Ajouter une note">📝 Note</button> <button class="icon-btn" id="btnQuickTime" title="Ajouter du temps manuellement">⏱ Temps</button>`}`
          : `Sélectionne un cours dans la barre latérale pour commencer.`}
      </div>

      ${course && !busy ? renderLastNoteBanner(displayCourseId) : ''}

      <div id="timerCore"></div>

      ${course ? renderSessionAndNoteLog(displayCourseId) : ''}
    </div>
  `;

  const modePomodoroBtn = document.getElementById('modeBtnPomodoro');
  const modeFlowBtn = document.getElementById('modeBtnFlow');
  if (modePomodoroBtn) modePomodoroBtn.addEventListener('click', () => { mode = 'pomodoro'; renderTimerView(); });
  if (modeFlowBtn) modeFlowBtn.addEventListener('click', () => { mode = 'flow'; renderTimerView(); });
  const quickNoteBtn = document.getElementById('btnQuickNote');
  if (quickNoteBtn) quickNoteBtn.addEventListener('click', quickAddNote);
  const quickTimeBtn = document.getElementById('btnQuickTime');
  if (quickTimeBtn) quickTimeBtn.addEventListener('click', quickAddTime);

  renderTimerCore();
}

export function initTimerView() {
  document.getElementById('view-timer').addEventListener('click', (e) => {
    const delBtn = e.target.closest('[data-del-session]');
    if (delBtn) {
      e.stopPropagation();
      confirmDialog({ title: 'Supprimer cet élément ?', message: 'Cette action est définitive.', confirmLabel: 'Supprimer', danger: true })
        .then(ok => { if (ok) actions.deleteSession(delBtn.dataset.delSession); });
      return;
    }
    const editBtn = e.target.closest('[data-edit-session]');
    if (editBtn) {
      e.stopPropagation();
      editSessionTime(editBtn.dataset.editSession);
    }
  });
}
