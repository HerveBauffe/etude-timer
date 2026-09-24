'use strict';

const { Notification } = require('electron');

function sendPhaseEndNotification(win, { title, body }) {
  try {
    if (Notification.isSupported()) {
      const n = new Notification({ title, body, silent: false });
      n.show();
    }
  } catch (err) {
    console.error('Notification impossible :', err);
  }

  // Ramène la fenêtre au premier plan, comme demandé (avertissement visuel au premier plan).
  try {
    if (win) {
      if (win.isMinimized()) win.restore();
      win.show();
      win.focus();
      if (process.platform === 'win32' || process.platform === 'linux') {
        win.flashFrame(true);
        setTimeout(() => { try { win.flashFrame(false); } catch (_) {} }, 3000);
      }
    }
  } catch (err) {
    console.error('Impossible de mettre la fenêtre au premier plan :', err);
  }
}

module.exports = { sendPhaseEndNotification };
