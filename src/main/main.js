'use strict';

const { app, BrowserWindow } = require('electron');
const path = require('path');

// En version portable Windows, electron-builder fournit PORTABLE_EXECUTABLE_DIR : le dossier où
// se trouve le .exe réellement lancé par l'utilisateur. On y redirige TOUT le dossier userData
// d'Electron (pas seulement notre data.json) — cache HTTP, cache GPU, etc. — pour qu'une version
// portable ne touche vraiment rien au profil Windows (%APPDATA%) et reste déplaçable sur une clé
// USB. Ceci doit être fait avant app.whenReady() (et avant le verrou mono-instance ci-dessous,
// qui s'appuie sur ce chemin).
if (process.env.PORTABLE_EXECUTABLE_DIR) {
  app.setPath('userData', path.join(process.env.PORTABLE_EXECUTABLE_DIR, 'EtudeTimerData'));
}

// Empêche deux instances de tourner en même temps. Sans ce verrou, lancer l'app deux fois (double-
// clic accidentel, ou une instance précédente pas encore totalement fermée) fait que les deux
// processus Chromium se disputent le même dossier de cache — c'est très exactement ce qui
// provoque l'erreur Windows "Unable to move the cache: Accès refusé (0x5)". Si une instance
// tourne déjà, celle-ci se ferme immédiatement et redonne la main à la première.
const gotSingleInstanceLock = app.requestSingleInstanceLock();
if (!gotSingleInstanceLock) {
  app.quit();
} else {

const { Store } = require('./store');
const { SyncManager } = require('./sync');
const { registerIpcHandlers } = require('./ipc');

let mainWindow = null;
let store = null;
let sync = null;
let quittingAfterSync = false;

app.on('second-instance', () => {
  if (mainWindow) {
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.show();
    mainWindow.focus();
  }
});

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1180,
    height: 760,
    minWidth: 860,
    minHeight: 560,
    backgroundColor: '#F5F6F3',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  });

  mainWindow.loadFile(path.join(__dirname, '..', 'renderer', 'index.html'));

  mainWindow.on('closed', () => { mainWindow = null; });
}

app.whenReady().then(() => {
  store = new Store();
  store.load();

  sync = new SyncManager(store, (status) => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send('sync:status-changed', status);
    }
  });

  registerIpcHandlers({ getStore: () => store, getSync: () => sync, getWindow: () => mainWindow });

  createWindow();

  // Première synchronisation au démarrage (si activée), puis démarrage du cycle automatique.
  if (store.getAll().settings.webdav.enabled) {
    sync.syncNow().finally(() => sync.start());
  }

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

// On tente une dernière synchronisation avant de quitter réellement, sans bloquer indéfiniment.
app.on('before-quit', (event) => {
  if (quittingAfterSync || !store || !sync) return;
  const cfg = store.getAll().settings.webdav;
  if (!cfg.enabled) return;

  event.preventDefault();
  quittingAfterSync = true;

  const timeout = new Promise((resolve) => setTimeout(resolve, 5000));
  Promise.race([sync.syncNow({ isQuitting: true }), timeout]).finally(() => {
    app.quit();
  });
});

} // fin du bloc "instance unique obtenue"
