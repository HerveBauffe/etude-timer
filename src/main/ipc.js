'use strict';

const { ipcMain } = require('electron');
const { sendPhaseEndNotification } = require('./notifications');

function registerIpcHandlers({ getStore, getSync, getWindow }) {
  const h = (channel, fn) => ipcMain.handle(channel, (event, ...args) => fn(...args));

  h('store:getAll', () => getStore().getAll());

  h('folder:add', (name, parentId, type) => getStore().addFolder(name, parentId, type));
  h('folder:rename', (id, name) => getStore().renameFolder(id, name));
  h('folder:delete', (id) => getStore().deleteFolder(id));

  h('ue:add', (name, folderId) => getStore().addUE(name, folderId));
  h('ue:rename', (id, name) => getStore().renameUE(id, name));
  h('ue:move', (id, folderId) => getStore().moveUE(id, folderId));
  h('ue:archive', (id, archived) => getStore().archiveUE(id, archived));
  h('ue:delete', (id) => getStore().deleteUE(id));

  h('course:add', (name, ueId) => getStore().addCourse(name, ueId));
  h('course:rename', (id, name) => getStore().renameCourse(id, name));
  h('course:delete', (id) => getStore().deleteCourse(id));

  h('session:add', (session) => getStore().addSession(session));
  h('session:delete', (id) => getStore().deleteSession(id));
  h('session:updateNote', (id, note) => getStore().updateSessionNote(id, note));
  h('session:updateTime', (id, patch) => getStore().updateSessionTime(id, patch));

  h('settings:update', (partial) => getStore().updateSettings(partial));
  h('settings:setWebdavPassword', (plain) => { getStore().setWebdavPassword(plain); return true; });

  h('notify:phaseEnd', (payload) => {
    sendPhaseEndNotification(getWindow(), payload);
    return true;
  });

  h('sync:now', () => getSync().syncNow());
  h('sync:restart', () => { getSync().start(); return true; });
  h('sync:stop', () => { getSync().stop(); return true; });
}

module.exports = { registerIpcHandlers };
