'use strict';

const { app, BrowserWindow } = require('electron');
const path = require('path');

const { Store } = require('./store');
const { SyncManager } = require('./sync');
const { registerIpcHandlers } = require('./ipc');

let mainWindow = null;
let store = null;
let sync = null;
let quittingAfterSync = false;

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
