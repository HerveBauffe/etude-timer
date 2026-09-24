'use strict';

const { contextBridge, ipcRenderer } = require('electron');

const invoke = (channel) => (...args) => ipcRenderer.invoke(channel, ...args);

contextBridge.exposeInMainWorld('api', {
  getAll: invoke('store:getAll'),

  addFolder: invoke('folder:add'),
  renameFolder: invoke('folder:rename'),
  deleteFolder: invoke('folder:delete'),

  addUE: invoke('ue:add'),
  renameUE: invoke('ue:rename'),
  moveUE: invoke('ue:move'),
  archiveUE: invoke('ue:archive'),
  deleteUE: invoke('ue:delete'),

  addCourse: invoke('course:add'),
  renameCourse: invoke('course:rename'),
  deleteCourse: invoke('course:delete'),

  addSession: invoke('session:add'),
  deleteSession: invoke('session:delete'),
  updateSessionNote: invoke('session:updateNote'),
  updateSessionTime: invoke('session:updateTime'),

  updateSettings: invoke('settings:update'),
  setWebdavPassword: invoke('settings:setWebdavPassword'),

  notifyPhaseEnd: invoke('notify:phaseEnd'),

  syncNow: invoke('sync:now'),
  syncRestart: invoke('sync:restart'),
  syncStop: invoke('sync:stop'),

  getDataInfo: invoke('data:getInfo'),
  chooseDataFolder: invoke('data:chooseFolder'),
  resetDataFolder: invoke('data:resetFolder'),
  openDataFolder: invoke('data:openFolder'),

  onSyncStatusChanged: (callback) => {
    const listener = (event, status) => callback(status);
    ipcRenderer.on('sync:status-changed', listener);
    return () => ipcRenderer.removeListener('sync:status-changed', listener);
  }
});
