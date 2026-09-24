const listeners = new Set();

const state = {
  data: null,           // copie locale des données (folders, ues, courses, sessions, settings)
  selectedCourseId: null,
  activeTab: 'timer',
  statsFilterCourseId: 'all'
};

function notify() {
  for (const fn of listeners) fn(state);
}

export function subscribe(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

export function getState() { return state; }

export async function init() {
  state.data = await window.api.getAll();
  notify();
}

function refreshFrom(result) {
  // Beaucoup de handlers renvoient l'entité modifiée ; on relit tout depuis le disque
  // pour rester simple et toujours cohérent (le volume de données reste modeste).
  return window.api.getAll().then(data => { state.data = data; notify(); return result; });
}

export const actions = {
  setActiveTab(tab) { state.activeTab = tab; notify(); },
  selectCourse(courseId) { state.selectedCourseId = courseId; notify(); },
  setStatsFilterCourse(courseId) { state.statsFilterCourseId = courseId; notify(); },

  async addFolder(name, parentId, type) { return window.api.addFolder(name, parentId, type).then(refreshFrom); },
  async renameFolder(id, name) { return window.api.renameFolder(id, name).then(refreshFrom); },
  async deleteFolder(id) { return window.api.deleteFolder(id).then(refreshFrom); },

  async addUE(name, folderId) { return window.api.addUE(name, folderId).then(refreshFrom); },
  async renameUE(id, name) { return window.api.renameUE(id, name).then(refreshFrom); },
  async moveUE(id, folderId) { return window.api.moveUE(id, folderId).then(refreshFrom); },
  async archiveUE(id, archived) { return window.api.archiveUE(id, archived).then(refreshFrom); },
  async deleteUE(id) {
    if (state.selectedCourseId) {
      const course = state.data.courses.find(c => c.id === state.selectedCourseId);
      if (course && course.ueId === id) state.selectedCourseId = null;
    }
    return window.api.deleteUE(id).then(refreshFrom);
  },

  async addCourse(name, ueId) { return window.api.addCourse(name, ueId).then(refreshFrom); },
  async renameCourse(id, name) { return window.api.renameCourse(id, name).then(refreshFrom); },
  async deleteCourse(id) {
    if (state.selectedCourseId === id) state.selectedCourseId = null;
    return window.api.deleteCourse(id).then(refreshFrom);
  },

  async addSession(session) { return window.api.addSession(session).then(refreshFrom); },
  async deleteSession(id) { return window.api.deleteSession(id).then(refreshFrom); },
  async updateSessionNote(id, note) { return window.api.updateSessionNote(id, note).then(refreshFrom); },
  async updateSessionTime(id, patch) { return window.api.updateSessionTime(id, patch).then(refreshFrom); },

  async updateSettings(partial) { return window.api.updateSettings(partial).then(refreshFrom); },
  async setWebdavPassword(plain) { return window.api.setWebdavPassword(plain); },

  async syncNow() { const r = await window.api.syncNow(); await refreshFrom(r); return r; }
};

// ---------- Sélecteurs ----------
export function getFolderChildren(folderId) {
  return state.data.folders.filter(f => (f.parentId || null) === (folderId || null));
}
export function getUEsInFolder(folderId, { archived = false } = {}) {
  return state.data.ues.filter(u => (u.folderId || null) === (folderId || null) && !!u.archived === archived);
}
export function getCoursesForUE(ueId) {
  return state.data.courses.filter(c => c.ueId === ueId);
}
export function getUEForCourse(courseId) {
  const course = state.data.courses.find(c => c.id === courseId);
  if (!course) return null;
  return state.data.ues.find(u => u.id === course.ueId) || null;
}
export function getCourseById(id) {
  return state.data.courses.find(c => c.id === id) || null;
}
export function getAllArchivedUEs() {
  return state.data.ues.filter(u => u.archived);
}

export function getLastNoteForCourse(courseId) {
  const notes = state.data.sessions
    .filter(s => s.courseId === courseId && s.note)
    .sort((a, b) => new Date(b.end || b.start) - new Date(a.end || a.start));
  return notes[0] || null;
}

export function getNoteHistoryForCourse(courseId, limit = 8) {
  return state.data.sessions
    .filter(s => s.courseId === courseId && s.note)
    .sort((a, b) => new Date(b.end || b.start) - new Date(a.end || a.start))
    .slice(0, limit);
}

export function getRecentSessionsForCourse(courseId, limit = 6) {
  return state.data.sessions
    .filter(s => s.courseId === courseId && s.kind !== 'note')
    .sort((a, b) => new Date(b.end || b.start) - new Date(a.end || a.start))
    .slice(0, limit);
}
