'use strict';

// Le paquet "webdav" (v5+) est distribué en ESM pur : on ne peut pas faire un require()
// classique depuis ce fichier CommonJS. On le charge donc à la demande via import() dynamique,
// qui fonctionne aussi bien dans un module CommonJS.
let _createClient = null;
async function loadCreateClient() {
  if (!_createClient) {
    const mod = await import('webdav');
    _createClient = mod.createClient;
  }
  return _createClient;
}

/**
 * Fusionne deux jeux de données en unissant chaque collection par id.
 * Aucune donnée n'est perdue : un enregistrement présent d'un seul côté est conservé.
 * En cas de même id modifié des deux côtés, on garde la version dont le jeu de données
 * global est le plus récemment modifié (heuristique simple, adaptée à un usage séquentiel
 * Windows/Linux plutôt que simultané).
 */
function mergeData(local, remote) {
  const localIsNewer = new Date(local.updatedAt).getTime() >= new Date(remote.updatedAt).getTime();
  const preferred = localIsNewer ? local : remote;
  const other = localIsNewer ? remote : local;

  function mergeCollection(key) {
    const byId = new Map();
    for (const item of (other[key] || [])) byId.set(item.id, item);
    for (const item of (preferred[key] || [])) byId.set(item.id, item); // preferred écrase en cas de doublon
    return Array.from(byId.values());
  }

  const merged = {
    version: preferred.version,
    updatedAt: new Date().toISOString(),
    lastSyncedAt: preferred.lastSyncedAt,
    folders: mergeCollection('folders'),
    ues: mergeCollection('ues'),
    courses: mergeCollection('courses'),
    sessions: mergeCollection('sessions'),
    settings: preferred.settings
  };
  return merged;
}

class SyncManager {
  constructor(store, onStatusChange) {
    this.store = store;
    this.onStatusChange = onStatusChange || (() => {});
    this.timer = null;
    this.syncing = false;
  }

  async _client() {
    const cfg = this.store.getAll().settings.webdav;
    if (!cfg.enabled || !cfg.url) return null;
    const password = this.store.getWebdavPasswordPlain();
    const createClient = await loadCreateClient();
    return createClient(cfg.url, { username: cfg.username, password });
  }

  _emit(status) {
    this.onStatusChange(status);
  }

  async ensureRemoteDir(client, remotePath) {
    const dir = remotePath.substring(0, remotePath.lastIndexOf('/')) || '/';
    if (dir === '' || dir === '/') return;
    try {
      const exists = await client.exists(dir);
      if (!exists) await client.createDirectory(dir, { recursive: true });
    } catch (err) {
      // Certains serveurs WebDAV n'aiment pas le recursive:true -> on tente sans.
      try { await client.createDirectory(dir); } catch (_) { /* on laisse putFileContents échouer si besoin */ }
    }
  }

  async syncNow({ isQuitting = false } = {}) {
    if (this.syncing) return { ok: false, message: 'Une synchronisation est déjà en cours.' };
    const cfg = this.store.getAll().settings.webdav;
    if (!cfg.enabled) return { ok: false, message: 'Synchronisation désactivée.' };
    if (!cfg.url) return { ok: false, message: 'Aucune URL WebDAV configurée.' };

    this.syncing = true;
    this._emit({ state: 'syncing' });

    try {
      const client = await this._client();
      const remotePath = cfg.remotePath || '/EtudeTimer/data.json';
      await this.ensureRemoteDir(client, remotePath);

      let remoteData = null;
      const remoteExists = await client.exists(remotePath);
      if (remoteExists) {
        const raw = await client.getFileContents(remotePath, { format: 'text' });
        try { remoteData = JSON.parse(raw); } catch (err) {
          throw new Error('Le fichier distant est illisible (JSON invalide).');
        }
      }

      const local = this.store.getAll();
      let finalData = local;

      if (remoteData) {
        const localDirty = !local.lastSyncedAt || new Date(local.updatedAt) > new Date(local.lastSyncedAt);
        const remoteChangedSinceLastSync = !local.lastSyncedAt || new Date(remoteData.updatedAt) > new Date(local.lastSyncedAt);

        if (remoteChangedSinceLastSync || localDirty) {
          finalData = mergeData(local, remoteData);
          this.store.replaceAll(finalData);
        }
      }

      const now = new Date().toISOString();
      await client.putFileContents(remotePath, JSON.stringify(this.store.getAll(), null, 2), { overwrite: true });
      this.store.markSynced(now);

      this._emit({ state: 'idle', lastSyncedAt: now });
      return { ok: true, lastSyncedAt: now };
    } catch (err) {
      const message = (err && err.message) ? err.message : 'Erreur de synchronisation inconnue.';
      this._emit({ state: 'error', message });
      return { ok: false, message };
    } finally {
      this.syncing = false;
    }
  }

  start() {
    this.stop();
    const cfg = this.store.getAll().settings.webdav;
    const minutes = Math.max(1, Number(cfg.autoSyncMinutes) || 5);
    this.timer = setInterval(() => {
      this.syncNow().catch(() => {});
    }, minutes * 60 * 1000);
  }

  stop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }
}

module.exports = { SyncManager, mergeData };
