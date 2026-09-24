import { actions, getState, getFolderChildren, getUEsInFolder, getCoursesForUE, getAllArchivedUEs } from '../lib/state.js';
import { promptText, confirmDialog } from '../lib/modal.js';

const collapsed = new Set(); // ids de dossiers/UE repliés
let archiveOpen = false;

function toggle(id) {
  if (collapsed.has(id)) collapsed.delete(id); else collapsed.add(id);
  renderSidebar();
}

function rowActionsHtml(buttons) {
  return `<span class="row-actions">${buttons.map(b => `<button class="icon-btn" data-action="${b.action}" data-id="${b.id}" title="${b.title}">${b.icon}</button>`).join('')}</span>`;
}

function buildCourseRow(course) {
  const state = getState();
  const selected = state.selectedCourseId === course.id;
  const row = document.createElement('div');
  row.className = 'tree-row node-course' + (selected ? ' selected' : '');
  row.innerHTML = `
    <span class="caret"></span>
    <span class="label">${escapeHtml(course.name)}</span>
    ${rowActionsHtml([
      { action: 'rename-course', id: course.id, title: 'Renommer', icon: '✎' },
      { action: 'delete-course', id: course.id, title: 'Supprimer', icon: '✕' }
    ])}
  `;
  row.addEventListener('click', (e) => {
    if (e.target.closest('.icon-btn')) return;
    actions.selectCourse(course.id);
  });
  return row;
}

function buildUENode(ue, { archived = false } = {}) {
  const courses = getCoursesForUE(ue.id);
  const isCollapsed = collapsed.has(ue.id);
  const wrap = document.createElement('div');
  wrap.className = 'tree-node';

  const row = document.createElement('div');
  row.className = 'tree-row node-ue' + (archived ? ' archived' : '');
  row.innerHTML = `
    <span class="caret">${courses.length ? (isCollapsed ? '▸' : '▾') : ''}</span>
    <span class="label">${escapeHtml(ue.name)}</span>
    ${rowActionsHtml(archived ? [
      { action: 'unarchive-ue', id: ue.id, title: 'Désarchiver', icon: '↺' },
      { action: 'delete-ue', id: ue.id, title: 'Supprimer définitivement', icon: '✕' }
    ] : [
      { action: 'add-course', id: ue.id, title: 'Ajouter un cours', icon: '+' },
      { action: 'rename-ue', id: ue.id, title: 'Renommer', icon: '✎' },
      { action: 'archive-ue', id: ue.id, title: 'Marquer comme terminée', icon: '✓' },
      { action: 'delete-ue', id: ue.id, title: 'Supprimer', icon: '✕' }
    ])}
  `;
  if (courses.length) row.addEventListener('click', (e) => { if (!e.target.closest('.icon-btn')) toggle(ue.id); });
  wrap.appendChild(row);

  if (courses.length && !isCollapsed) {
    const children = document.createElement('div');
    children.className = 'tree-children';
    courses.forEach(c => children.appendChild(buildCourseRow(c)));
    wrap.appendChild(children);
  }
  return wrap;
}

function buildFolderNode(folder) {
  const subfolders = getFolderChildren(folder.id);
  const ues = getUEsInFolder(folder.id);
  const isCollapsed = collapsed.has(folder.id);
  const hasChildren = subfolders.length > 0 || ues.length > 0;

  const wrap = document.createElement('div');
  wrap.className = 'tree-node';

  const row = document.createElement('div');
  row.className = 'tree-row node-folder';
  row.innerHTML = `
    <span class="caret">${hasChildren ? (isCollapsed ? '▸' : '▾') : ''}</span>
    <span class="label">${escapeHtml(folder.name)}</span>
    ${rowActionsHtml([
      { action: 'add-subfolder', id: folder.id, title: 'Ajouter un sous-dossier', icon: '📁' },
      { action: 'add-ue', id: folder.id, title: 'Ajouter une UE', icon: '+' },
      { action: 'rename-folder', id: folder.id, title: 'Renommer', icon: '✎' },
      { action: 'delete-folder', id: folder.id, title: 'Supprimer', icon: '✕' }
    ])}
  `;
  if (hasChildren) row.addEventListener('click', (e) => { if (!e.target.closest('.icon-btn')) toggle(folder.id); });
  wrap.appendChild(row);

  if (hasChildren && !isCollapsed) {
    const children = document.createElement('div');
    children.className = 'tree-children';
    subfolders.forEach(f => children.appendChild(buildFolderNode(f)));
    ues.forEach(u => children.appendChild(buildUENode(u)));
    wrap.appendChild(children);
  }
  return wrap;
}

function escapeHtml(str) {
  return String(str).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

export function renderSidebar() {
  const tree = document.getElementById('tree');
  const rootFolders = getFolderChildren(null);
  const rootUEs = getUEsInFolder(null);

  tree.innerHTML = '';
  if (!rootFolders.length && !rootUEs.length) {
    const hint = document.createElement('p');
    hint.className = 'empty-hint';
    hint.textContent = "Aucune UE pour l'instant. Crée un dossier (ex. une année) ou une UE directement avec les boutons ci-dessus.";
    tree.appendChild(hint);
  } else {
    rootFolders.forEach(f => tree.appendChild(buildFolderNode(f)));
    rootUEs.forEach(u => tree.appendChild(buildUENode(u)));
  }

  const archived = getAllArchivedUEs();
  document.getElementById('archiveCount').textContent = archived.length;
  document.getElementById('archiveCaret').textContent = archiveOpen ? '▾' : '▸';
  const archiveTree = document.getElementById('archiveTree');
  archiveTree.hidden = !archiveOpen;
  if (archiveOpen) {
    archiveTree.innerHTML = '';
    if (!archived.length) {
      const hint = document.createElement('p');
      hint.className = 'empty-hint';
      hint.textContent = 'Aucune UE archivée.';
      archiveTree.appendChild(hint);
    } else {
      archived.forEach(u => archiveTree.appendChild(buildUENode(u, { archived: true })));
    }
  }
}

async function handleTreeAction(action, id) {
  switch (action) {
    case 'add-subfolder': {
      const name = await promptText({ title: 'Nouveau sous-dossier', placeholder: 'Ex. Quadrimestre 1' });
      if (name) await actions.addFolder(name, id, 'custom');
      break;
    }
    case 'add-ue': {
      const name = await promptText({ title: 'Nouvelle UE', placeholder: "Ex. Analyse mathématique" });
      if (name) await actions.addUE(name, id);
      break;
    }
    case 'rename-folder': {
      const folder = getState().data.folders.find(f => f.id === id);
      const name = await promptText({ title: 'Renommer le dossier', initialValue: folder?.name || '' });
      if (name) await actions.renameFolder(id, name);
      break;
    }
    case 'delete-folder': {
      const ok = await confirmDialog({ title: 'Supprimer ce dossier ?', message: 'Les sous-dossiers seront supprimés. Les UE qu\'ils contiennent seront déplacées à la racine, pas supprimées.', confirmLabel: 'Supprimer', danger: true });
      if (ok) await actions.deleteFolder(id);
      break;
    }
    case 'add-course': {
      const name = await promptText({ title: 'Nouveau cours', placeholder: 'Ex. Cours magistral' });
      if (name) await actions.addCourse(name, id);
      break;
    }
    case 'rename-ue': {
      const ue = getState().data.ues.find(u => u.id === id);
      const name = await promptText({ title: "Renommer l'UE", initialValue: ue?.name || '' });
      if (name) await actions.renameUE(id, name);
      break;
    }
    case 'archive-ue': {
      const ok = await confirmDialog({ title: 'Marquer cette UE comme terminée ?', message: "Elle sera déplacée dans les archives. Ton historique de temps reste intact.", confirmLabel: 'Terminer' });
      if (ok) await actions.archiveUE(id, true);
      break;
    }
    case 'unarchive-ue': {
      await actions.archiveUE(id, false);
      break;
    }
    case 'delete-ue': {
      const ok = await confirmDialog({ title: 'Supprimer cette UE ?', message: 'Ses cours et tout son historique de temps seront définitivement supprimés.', confirmLabel: 'Supprimer', danger: true });
      if (ok) await actions.deleteUE(id);
      break;
    }
    case 'rename-course': {
      const course = getState().data.courses.find(c => c.id === id);
      const name = await promptText({ title: 'Renommer le cours', initialValue: course?.name || '' });
      if (name) await actions.renameCourse(id, name);
      break;
    }
    case 'delete-course': {
      const ok = await confirmDialog({ title: 'Supprimer ce cours ?', message: 'Tout son historique de temps sera définitivement supprimé.', confirmLabel: 'Supprimer', danger: true });
      if (ok) await actions.deleteCourse(id);
      break;
    }
  }
}

export function initSidebar() {
  document.getElementById('btnAddFolder').addEventListener('click', async () => {
    const name = await promptText({ title: 'Nouveau dossier', placeholder: "Ex. Année 1" });
    if (name) await actions.addFolder(name, null, 'custom');
  });
  document.getElementById('btnAddRootUE').addEventListener('click', async () => {
    const name = await promptText({ title: 'Nouvelle UE', placeholder: 'Ex. Analyse mathématique' });
    if (name) await actions.addUE(name, null);
  });
  document.getElementById('archiveToggle').addEventListener('click', () => {
    archiveOpen = !archiveOpen;
    renderSidebar();
  });

  document.getElementById('sidebar').addEventListener('click', (e) => {
    const btn = e.target.closest('.icon-btn[data-action]');
    if (!btn) return;
    e.stopPropagation();
    handleTreeAction(btn.dataset.action, btn.dataset.id);
  });
}
