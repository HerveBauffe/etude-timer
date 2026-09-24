import { init, subscribe, getState, actions } from './lib/state.js';
import { applyTheme } from './lib/theme.js';
import { renderSidebar, initSidebar } from './views/sidebar.js';
import { renderTimerView, initTimerView } from './views/timer.js';
import { renderStatsView } from './views/stats.js';
import { renderSettingsView } from './views/settings.js';

const TABS = ['timer', 'stats', 'settings'];

function showTab(tab) {
  actions.setActiveTab(tab);
  TABS.forEach(t => {
    document.getElementById(`view-${t}`).hidden = (t !== tab);
  });
  document.querySelectorAll('.tab').forEach(btn => {
    const active = btn.dataset.tab === tab;
    btn.setAttribute('aria-selected', String(active));
  });
}

function initTabs() {
  document.querySelectorAll('.tab').forEach(btn => {
    btn.addEventListener('click', () => showTab(btn.dataset.tab));
  });
}

function renderAll() {
  renderSidebar();
  renderTimerView();
  renderStatsView();
  renderSettingsView();
  updateSyncIndicator();
}

function updateSyncIndicator(status) {
  const dot = document.getElementById('syncDot');
  const label = document.getElementById('syncLabel');
  const webdav = getState().data.settings.webdav;

  if (!webdav.enabled) {
    dot.className = 'sync-dot';
    label.textContent = 'Sync désactivée';
    return;
  }
  if (status?.state === 'syncing') {
    dot.className = 'sync-dot syncing';
    label.textContent = 'Synchronisation…';
  } else if (status?.state === 'error') {
    dot.className = 'sync-dot error';
    label.textContent = 'Erreur de synchro';
  } else {
    dot.className = 'sync-dot ok';
    const last = status?.lastSyncedAt || getState().data.lastSyncedAt;
    label.textContent = last
      ? `Synchronisé à ${new Date(last).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}`
      : 'Sync activée';
  }
}

async function bootstrap() {
  await init();
  applyTheme(getState().data.settings.theme);

  initTabs();
  initSidebar();
  initTimerView();

  subscribe(() => renderAll());
  window.api.onSyncStatusChanged((status) => updateSyncIndicator(status));

  showTab('timer');
  renderAll();
}

bootstrap();
