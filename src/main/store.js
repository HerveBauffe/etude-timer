'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { app, safeStorage } = require('electron');

const DATA_VERSION = 1;
const LOCATION_FILE_NAME = 'location.json';

// Dossier "point fixe" toujours prévisible, utilisé pour retrouver l'emplacement choisi par
// l'utilisateur (s'il en a choisi un). En version portable Windows, electron-builder place
// l'exécutable dans un dossier temporaire et fournit PORTABLE_EXECUTABLE_DIR : le dossier réel
// où se trouve le .exe lancé par l'utilisateur. On y stocke alors les données à côté de l'exe,
// comme on l'attend d'une version portable (autonome, déplaçable sur une clé USB).
function getBootstrapDir() {
  if (process.env.PORTABLE_EXECUTABLE_DIR) {
    return path.join(process.env.PORTABLE_EXECUTABLE_DIR, 'EtudeTimerData');
  }
  return app.getPath('userData');
}

function defaultData() {
  const now = new Date().toISOString();
  return {
    version: DATA_VERSION,
    updatedAt: now,
    lastSyncedAt: null,
    folders: [],
    ues: [],
    courses: [],
    sessions: [],
    settings: {
      pomodoro: { workMin: 25, shortBreakMin: 5, longBreakMin: 15, blocksBeforeLongBreak: 4 },
      flow: { breakPercent: 20 },
      webdav: {
        enabled: false,
        url: '',
        username: '',
        password: '',       // base64 (encrypted if passwordEncrypted=true, plain otherwise)
        passwordEncrypted: false,
        remotePath: '/EtudeTimer/data.json',
        autoSyncMinutes: 5
      },
      theme: 'system'
    }
  };
}

class Store {
  constructor() {
    this.bootstrapDir = getBootstrapDir();
    this.dataDir = this._resolveDataDir();
    this.filePath = path.join(this.dataDir, 'data.json');
    this.data = null;
    this.dirty = false;
  }

  _locationFilePath() {
    return path.join(this.bootstrapDir, LOCATION_FILE_NAME);
  }

  _resolveDataDir() {
    try {
      const locPath = this._locationFilePath();
      if (fs.existsSync(locPath)) {
        const parsed = JSON.parse(fs.readFileSync(locPath, 'utf-8'));
        if (parsed && parsed.dataDir && fs.existsSync(parsed.dataDir)) {
          return parsed.dataDir;
        }
      }
    } catch (err) {
      console.error("Emplacement personnalisé illisible, retour au dossier par défaut :", err);
    }
    return this.bootstrapDir;
  }

  getDataInfo() {
    return {
      filePath: this.filePath,
      dataDir: this.dataDir,
      bootstrapDir: this.bootstrapDir,
      isPortable: !!process.env.PORTABLE_EXECUTABLE_DIR,
      isCustom: path.resolve(this.dataDir) !== path.resolve(this.bootstrapDir)
    };
  }

  getFilePath() { return this.filePath; }

  // Change l'emplacement des données : copie le fichier existant (sans supprimer l'ancien) puis
  // enregistre le choix dans le fichier-pointeur, à l'emplacement fixe habituel.
  setDataDir(newDir) {
    fs.mkdirSync(newDir, { recursive: true });
    const newFilePath = path.join(newDir, 'data.json');
    if (!fs.existsSync(newFilePath) && fs.existsSync(this.filePath)) {
      fs.copyFileSync(this.filePath, newFilePath);
    }
    fs.mkdirSync(this.bootstrapDir, { recursive: true });
    fs.writeFileSync(this._locationFilePath(), JSON.stringify({ dataDir: newDir }, null, 2), 'utf-8');
    this.dataDir = newDir;
    this.filePath = newFilePath;
    this.load();
  }

  resetDataDir() {
    try { fs.unlinkSync(this._locationFilePath()); } catch (_) { /* pas de pointeur, rien à faire */ }
    this.dataDir = this.bootstrapDir;
    this.filePath = path.join(this.dataDir, 'data.json');
    this.load();
  }

  load() {
    try {
      if (fs.existsSync(this.filePath)) {
        const raw = fs.readFileSync(this.filePath, 'utf-8');
        this.data = JSON.parse(raw);
        this._migrate();
      } else {
        this.data = defaultData();
        this._writeToDisk();
      }
    } catch (err) {
      console.error('Erreur de lecture des données, initialisation par défaut :', err);
      // On ne perd jamais le fichier existant : on le renomme en .corrupt pour investigation.
      try {
        if (fs.existsSync(this.filePath)) {
          fs.copyFileSync(this.filePath, this.filePath + '.corrupt-' + Date.now());
        }
      } catch (_) { /* noop */ }
      this.data = defaultData();
      this._writeToDisk();
    }
    return this.data;
  }

  _migrate() {
    if (!this.data.version) this.data.version = DATA_VERSION;
    const def = defaultData();
    // Complète les champs manquants sans écraser les valeurs existantes (migrations douces).
    this.data.settings = Object.assign({}, def.settings, this.data.settings || {});
    this.data.settings.pomodoro = Object.assign({}, def.settings.pomodoro, this.data.settings.pomodoro || {});
    this.data.settings.flow = Object.assign({}, def.settings.flow, this.data.settings.flow || {});
    this.data.settings.webdav = Object.assign({}, def.settings.webdav, this.data.settings.webdav || {});
    for (const key of ['folders', 'ues', 'courses', 'sessions']) {
      if (!Array.isArray(this.data[key])) this.data[key] = [];
    }
  }

  getAll() {
    return this.data;
  }

  _touch() {
    this.data.updatedAt = new Date().toISOString();
    this.dirty = true;
    this._writeToDisk();
  }

  _writeToDisk() {
    try {
      fs.mkdirSync(path.dirname(this.filePath), { recursive: true });
      const tmpPath = this.filePath + '.tmp';
      fs.writeFileSync(tmpPath, JSON.stringify(this.data, null, 2), 'utf-8');
      fs.renameSync(tmpPath, this.filePath);
    } catch (err) {
      console.error('Échec de sauvegarde locale :', err);
    }
  }

  replaceAll(newData) {
    this.data = newData;
    this._migrate();
    this.dirty = true;
    this._writeToDisk();
  }

  markSynced(atISO) {
    this.data.lastSyncedAt = atISO;
    this.dirty = false;
    this._writeToDisk();
  }

  // ---------- Dossiers ----------
  addFolder(name, parentId, type) {
    const folder = { id: crypto.randomUUID(), name, parentId: parentId || null, type: type || 'custom', createdAt: new Date().toISOString() };
    this.data.folders.push(folder);
    this._touch();
    return folder;
  }

  renameFolder(id, name) {
    const f = this.data.folders.find(f => f.id === id);
    if (f) { f.name = name; this._touch(); }
    return f;
  }

  deleteFolder(id) {
    // Supprime récursivement les sous-dossiers, en remontant les UE orphelines à la racine.
    const toDelete = new Set([id]);
    let changed = true;
    while (changed) {
      changed = false;
      for (const f of this.data.folders) {
        if (f.parentId && toDelete.has(f.parentId) && !toDelete.has(f.id)) {
          toDelete.add(f.id);
          changed = true;
        }
      }
    }
    this.data.folders = this.data.folders.filter(f => !toDelete.has(f.id));
    this.data.ues.forEach(u => { if (toDelete.has(u.folderId)) u.folderId = null; });
    this._touch();
  }

  // ---------- UE ----------
  addUE(name, folderId) {
    const ue = { id: crypto.randomUUID(), name, folderId: folderId || null, archived: false, archivedAt: null, createdAt: new Date().toISOString() };
    this.data.ues.push(ue);
    this._touch();
    return ue;
  }

  renameUE(id, name) {
    const u = this.data.ues.find(u => u.id === id);
    if (u) { u.name = name; this._touch(); }
    return u;
  }

  moveUE(id, folderId) {
    const u = this.data.ues.find(u => u.id === id);
    if (u) { u.folderId = folderId || null; this._touch(); }
    return u;
  }

  archiveUE(id, archived) {
    const u = this.data.ues.find(u => u.id === id);
    if (u) {
      u.archived = !!archived;
      u.archivedAt = u.archived ? new Date().toISOString() : null;
      this._touch();
    }
    return u;
  }

  deleteUE(id) {
    this.data.ues = this.data.ues.filter(u => u.id !== id);
    this.data.courses = this.data.courses.filter(c => c.ueId !== id);
    this._touch();
  }

  // ---------- Cours ----------
  addCourse(name, ueId) {
    const course = { id: crypto.randomUUID(), name, ueId, createdAt: new Date().toISOString() };
    this.data.courses.push(course);
    this._touch();
    return course;
  }

  renameCourse(id, name) {
    const c = this.data.courses.find(c => c.id === id);
    if (c) { c.name = name; this._touch(); }
    return c;
  }

  deleteCourse(id) {
    this.data.courses = this.data.courses.filter(c => c.id !== id);
    this._touch();
  }

  // ---------- Sessions (blocs de temps) ----------
  addSession(session) {
    const s = {
      id: crypto.randomUUID(),
      courseId: session.courseId,
      mode: session.mode,           // 'pomodoro' | 'flow' | null (note libre)
      kind: session.kind,           // 'work' | 'break' | 'note'
      start: session.start,
      end: session.end,
      seconds: Math.max(0, Math.round(session.seconds || 0)),
      completed: !!session.completed,
      date: session.date || session.start.slice(0, 10),
      note: typeof session.note === 'string' ? session.note.trim() : ''
    };
    this.data.sessions.push(s);
    this._touch();
    return s;
  }

  deleteSession(id) {
    this.data.sessions = this.data.sessions.filter(s => s.id !== id);
    this._touch();
  }

  updateSessionNote(id, note) {
    const s = this.data.sessions.find(s => s.id === id);
    if (s) { s.note = (note || '').trim(); this._touch(); }
    return s;
  }

  updateSessionTime(id, { seconds, date } = {}) {
    const s = this.data.sessions.find(s => s.id === id);
    if (!s) return null;
    if (typeof seconds === 'number' && seconds >= 0) s.seconds = Math.round(seconds);
    if (date) s.date = date;
    const anchor = date ? `${date}T12:00:00.000Z` : s.start;
    s.start = anchor;
    s.end = new Date(new Date(anchor).getTime() + s.seconds * 1000).toISOString();
    this._touch();
    return s;
  }

  // ---------- Réglages ----------
  updateSettings(partial) {
    this.data.settings = Object.assign({}, this.data.settings, partial);
    if (partial.pomodoro) this.data.settings.pomodoro = Object.assign({}, this.data.settings.pomodoro, partial.pomodoro);
    if (partial.flow) this.data.settings.flow = Object.assign({}, this.data.settings.flow, partial.flow);
    if (partial.webdav) this.data.settings.webdav = Object.assign({}, this.data.settings.webdav, partial.webdav);
    this._touch();
    return this.data.settings;
  }

  setWebdavPassword(plainPassword) {
    const webdav = this.data.settings.webdav;
    if (!plainPassword) {
      webdav.password = '';
      webdav.passwordEncrypted = false;
    } else if (safeStorage.isEncryptionAvailable()) {
      webdav.password = safeStorage.encryptString(plainPassword).toString('base64');
      webdav.passwordEncrypted = true;
    } else {
      webdav.password = plainPassword;
      webdav.passwordEncrypted = false;
    }
    this._touch();
  }

  getWebdavPasswordPlain() {
    const webdav = this.data.settings.webdav;
    if (!webdav.password) return '';
    if (webdav.passwordEncrypted) {
      try {
        return safeStorage.decryptString(Buffer.from(webdav.password, 'base64'));
      } catch (err) {
        console.error('Impossible de déchiffrer le mot de passe WebDAV :', err);
        return '';
      }
    }
    return webdav.password;
  }
}

module.exports = { Store, defaultData, DATA_VERSION };
