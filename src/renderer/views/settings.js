import { actions, getState, init } from '../lib/state.js';
import { applyTheme } from '../lib/theme.js';

let passwordTouched = false;
let lastSyncMessage = null; // {ok, message}
let dataLocationMessage = null; // {ok, message}

function n(val, fallback) {
  const num = Number(val);
  return Number.isFinite(num) && num > 0 ? num : fallback;
}

function formatLastSynced(iso) {
  if (!iso) return 'Jamais synchronisé';
  const d = new Date(iso);
  return `Dernière synchro : ${d.toLocaleDateString('fr-FR')} à ${d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}`;
}

export async function renderSettingsView() {
  const container = document.getElementById('view-settings');
  if (!container) return;
  const settings = getState().data.settings;
  const p = settings.pomodoro, f = settings.flow, w = settings.webdav;
  const dataInfo = await window.api.getDataInfo();

  container.innerHTML = `
    <h1>Réglages</h1>
    <p class="subtitle">Ajuste le minuteur et la synchronisation à ta façon.</p>

    <div class="settings-section">
      <h2>Pomodoro</h2>
      <p class="desc">4 blocs de travail, chaque phase démarrée manuellement.</p>
      <div class="field-row">
        <label>Durée d'un bloc de travail</label>
        <input type="number" id="workMin" min="1" max="180" value="${p.workMin}" /> min
      </div>
      <div class="field-row">
        <label>Pause courte</label>
        <input type="number" id="shortBreakMin" min="1" max="60" value="${p.shortBreakMin}" /> min
      </div>
      <div class="field-row">
        <label>Pause longue</label>
        <input type="number" id="longBreakMin" min="1" max="120" value="${p.longBreakMin}" /> min
      </div>
      <div class="field-row">
        <label>Blocs avant la pause longue</label>
        <input type="number" id="blocksBeforeLongBreak" min="2" max="8" value="${p.blocksBeforeLongBreak}" />
      </div>
    </div>

    <div class="settings-section">
      <h2>Flow Zone</h2>
      <p class="desc">La pause méritée est calculée à partir du temps de travail.</p>
      <div class="field-row">
        <label>Pourcentage de pause</label>
        <input type="number" id="breakPercent" min="1" max="100" value="${f.breakPercent}" /> %
      </div>
    </div>

    <div class="settings-section">
      <h2>Apparence</h2>
      <div class="theme-choice">
        <button class="btn ${settings.theme === 'system' ? 'active' : ''}" data-theme="system">Système</button>
        <button class="btn ${settings.theme === 'light' ? 'active' : ''}" data-theme="light">Clair</button>
        <button class="btn ${settings.theme === 'dark' ? 'active' : ''}" data-theme="dark">Sombre</button>
      </div>
    </div>

    <div class="settings-section">
      <h2>Emplacement des données</h2>
      <p class="desc">
        ${dataInfo.isPortable
          ? "Version portable détectée : les données sont stockées à côté de l'exécutable par défaut (pas dans ton profil Windows), pour rester déplaçables avec l'app."
          : "Par défaut, les données sont stockées dans le dossier de profil de l'application."}
        Tu peux choisir un autre dossier à tout moment (clé USB, dossier synchronisé, autre disque...).
      </p>
      <div class="field-row stacked">
        <label>Fichier actuel</label>
        <code style="display:block;padding:9px 10px;border-radius:7px;border:1px solid var(--border);background:var(--surface-2);font-size:12.5px;word-break:break-all;">${dataInfo.filePath}</code>
        <span class="field-hint">${dataInfo.isCustom ? 'Emplacement personnalisé.' : 'Emplacement par défaut.'}</span>
      </div>
      <div class="settings-actions">
        <button class="btn" id="btnOpenDataFolder">Ouvrir le dossier</button>
        <button class="btn" id="btnChooseDataFolder">Choisir un autre dossier…</button>
        ${dataInfo.isCustom ? `<button class="btn btn-ghost" id="btnResetDataFolder">Revenir au dossier par défaut</button>` : ''}
      </div>
      <p class="settings-status ${dataLocationMessage ? (dataLocationMessage.ok ? 'ok' : 'error') : ''}">
        ${dataLocationMessage ? dataLocationMessage.message : ''}
      </p>
    </div>

    <div class="settings-section">
      <h2>Synchronisation WebDAV (Nextcloud)</h2>
      <p class="desc">Garde tes données à jour entre plusieurs ordinateurs. Le mot de passe est chiffré sur ce poste quand c'est possible.</p>
      <div class="field-row">
        <label>Activer la synchronisation</label>
        <label class="toggle">
          <input type="checkbox" id="webdavEnabled" ${w.enabled ? 'checked' : ''} />
          <span class="track"></span>
        </label>
      </div>
      <div class="field-row stacked">
        <label for="webdavUrl">URL WebDAV</label>
        <input type="url" id="webdavUrl" value="${w.url || ''}" placeholder="https://mon-nextcloud.exemple.com/remote.php/dav/files/MON_UTILISATEUR/" />
        <span class="field-hint">Nextcloud : Paramètres → Sécurité, pour créer un mot de passe d'application dédié.</span>
      </div>
      <div class="field-row">
        <label for="webdavUsername">Identifiant</label>
        <input type="text" id="webdavUsername" value="${w.username || ''}" />
      </div>
      <div class="field-row">
        <label for="webdavPassword">Mot de passe</label>
        <input type="password" id="webdavPassword" placeholder="${w.password ? '••••••••' : 'Mot de passe ou mot de passe d’application'}" />
      </div>
      <div class="field-row">
        <label for="webdavRemotePath">Chemin distant</label>
        <input type="text" id="webdavRemotePath" value="${w.remotePath || '/EtudeTimer/data.json'}" />
      </div>
      <div class="field-row">
        <label for="webdavAutoSync">Fréquence de synchro auto.</label>
        <input type="number" id="webdavAutoSync" min="1" max="120" value="${w.autoSyncMinutes || 5}" /> min
      </div>
      <div class="settings-actions">
        <button class="btn" id="btnSaveWebdav">Enregistrer</button>
        <button class="btn btn-primary" id="btnSyncNow">Synchroniser maintenant</button>
      </div>
      <p class="settings-status ${lastSyncMessage ? (lastSyncMessage.ok ? 'ok' : 'error') : ''}" id="syncStatusText">
        ${lastSyncMessage ? lastSyncMessage.message : formatLastSynced(getState().data.lastSyncedAt)}
      </p>
    </div>
  `;

  document.getElementById('btnOpenDataFolder').addEventListener('click', () => window.api.openDataFolder());

  document.getElementById('btnChooseDataFolder').addEventListener('click', async () => {
    const result = await window.api.chooseDataFolder();
    if (result.canceled) return;
    if (result.ok) {
      dataLocationMessage = { ok: true, message: 'Dossier mis à jour. Tes données ont été copiées vers ce nouvel emplacement (l\'ancien fichier est conservé tel quel).' };
      await init();
    } else {
      dataLocationMessage = { ok: false, message: `Impossible de changer de dossier : ${result.message}` };
    }
    renderSettingsView();
  });

  const resetBtn = document.getElementById('btnResetDataFolder');
  if (resetBtn) {
    resetBtn.addEventListener('click', async () => {
      await window.api.resetDataFolder();
      dataLocationMessage = { ok: true, message: 'Retour au dossier par défaut.' };
      await init();
      renderSettingsView();
    });
  }

  // Pomodoro (sauvegarde au blur/changement)
  const savePomodoro = () => actions.updateSettings({
    pomodoro: {
      workMin: n(document.getElementById('workMin').value, p.workMin),
      shortBreakMin: n(document.getElementById('shortBreakMin').value, p.shortBreakMin),
      longBreakMin: n(document.getElementById('longBreakMin').value, p.longBreakMin),
      blocksBeforeLongBreak: n(document.getElementById('blocksBeforeLongBreak').value, p.blocksBeforeLongBreak)
    }
  });
  ['workMin', 'shortBreakMin', 'longBreakMin', 'blocksBeforeLongBreak'].forEach(id => {
    document.getElementById(id).addEventListener('change', savePomodoro);
  });

  document.getElementById('breakPercent').addEventListener('change', (e) => {
    actions.updateSettings({ flow: { breakPercent: n(e.target.value, f.breakPercent) } });
  });

  container.querySelectorAll('[data-theme]').forEach(btn => {
    btn.addEventListener('click', () => {
      const theme = btn.dataset.theme;
      applyTheme(theme);
      actions.updateSettings({ theme });
    });
  });

  document.getElementById('webdavPassword').addEventListener('input', () => { passwordTouched = true; });

  document.getElementById('btnSaveWebdav').addEventListener('click', async () => {
    const partial = {
      webdav: {
        enabled: document.getElementById('webdavEnabled').checked,
        url: document.getElementById('webdavUrl').value.trim(),
        username: document.getElementById('webdavUsername').value.trim(),
        remotePath: document.getElementById('webdavRemotePath').value.trim() || '/EtudeTimer/data.json',
        autoSyncMinutes: n(document.getElementById('webdavAutoSync').value, 5)
      }
    };
    await actions.updateSettings(partial);
    if (passwordTouched) {
      const pw = document.getElementById('webdavPassword').value;
      await actions.setWebdavPassword(pw);
      passwordTouched = false;
    }
    await window.api.syncRestart();
    lastSyncMessage = { ok: true, message: 'Réglages enregistrés.' };
    renderSettingsView();
  });

  document.getElementById('btnSyncNow').addEventListener('click', async () => {
    const btn = document.getElementById('btnSyncNow');
    btn.disabled = true;
    const statusEl = document.getElementById('syncStatusText');
    statusEl.className = 'settings-status';
    statusEl.textContent = 'Synchronisation en cours…';
    const result = await actions.syncNow();
    lastSyncMessage = result.ok
      ? { ok: true, message: `Synchronisé avec succès (${new Date(result.lastSyncedAt).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}).` }
      : { ok: false, message: `Échec de la synchronisation : ${result.message}` };
    renderSettingsView();
  });
}
