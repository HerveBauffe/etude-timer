const overlay = document.getElementById('modalOverlay');
const modal = document.getElementById('modal');

function close() {
  overlay.hidden = true;
  modal.innerHTML = '';
}

overlay.addEventListener('click', (e) => { if (e.target === overlay) close(); });
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !overlay.hidden) close(); });

export function promptText({ title, message = '', initialValue = '', confirmLabel = 'Valider', placeholder = '' }) {
  return new Promise((resolve) => {
    modal.innerHTML = `
      <h3>${title}</h3>
      ${message ? `<p>${message}</p>` : ''}
      <input type="text" id="modalInput" value="${initialValue.replace(/"/g, '&quot;')}" placeholder="${placeholder}" />
      <div class="modal-actions">
        <button class="btn" id="modalCancel">Annuler</button>
        <button class="btn btn-primary" id="modalOk">${confirmLabel}</button>
      </div>
    `;
    overlay.hidden = false;
    const input = modal.querySelector('#modalInput');
    input.focus();
    input.select();

    const finish = (value) => { close(); resolve(value); };
    modal.querySelector('#modalCancel').addEventListener('click', () => finish(null));
    modal.querySelector('#modalOk').addEventListener('click', () => finish(input.value.trim() || null));
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') finish(input.value.trim() || null);
      if (e.key === 'Escape') finish(null);
    });
  });
}

export function confirmDialog({ title, message = '', confirmLabel = 'Confirmer', danger = false }) {
  return new Promise((resolve) => {
    modal.innerHTML = `
      <h3>${title}</h3>
      ${message ? `<p>${message}</p>` : ''}
      <div class="modal-actions">
        <button class="btn" id="modalCancel">Annuler</button>
        <button class="btn ${danger ? 'btn-danger' : 'btn-primary'}" id="modalOk">${confirmLabel}</button>
      </div>
    `;
    overlay.hidden = false;
    const finish = (value) => { close(); resolve(value); };
    modal.querySelector('#modalCancel').addEventListener('click', () => finish(false));
    modal.querySelector('#modalOk').addEventListener('click', () => finish(true));
  });
}

/**
 * Modale de saisie d'une durée (minutes) et d'une date, pour ajouter ou corriger du temps
 * d'étude manuellement (ex. si on a oublié d'arrêter le minuteur).
 */
export function promptDuration({ title, message = '', initialMinutes = 25, initialDate = null, confirmLabel = 'Enregistrer' }) {
  return new Promise((resolve) => {
    const dateVal = initialDate || new Date().toISOString().slice(0, 10);
    modal.innerHTML = `
      <h3>${title}</h3>
      ${message ? `<p>${message}</p>` : ''}
      <div style="display:flex;gap:10px;margin-bottom:16px;">
        <div style="flex:1;">
          <label style="font-size:12px;color:var(--text-muted);display:block;margin-bottom:4px;">Durée (minutes)</label>
          <input type="number" id="modalMinutes" min="1" max="1440" value="${initialMinutes}"
            style="width:100%;padding:9px 10px;border-radius:7px;border:1px solid var(--border);background:var(--surface-2);" />
        </div>
        <div style="flex:1;">
          <label style="font-size:12px;color:var(--text-muted);display:block;margin-bottom:4px;">Date</label>
          <input type="date" id="modalDate" value="${dateVal}"
            style="width:100%;padding:9px 10px;border-radius:7px;border:1px solid var(--border);background:var(--surface-2);" />
        </div>
      </div>
      <div class="modal-actions">
        <button class="btn" id="modalCancel">Annuler</button>
        <button class="btn btn-primary" id="modalOk">${confirmLabel}</button>
      </div>
    `;
    overlay.hidden = false;
    const minutesInput = modal.querySelector('#modalMinutes');
    minutesInput.focus();
    minutesInput.select();

    const finish = (value) => { close(); resolve(value); };
    modal.querySelector('#modalCancel').addEventListener('click', () => finish(null));
    modal.querySelector('#modalOk').addEventListener('click', () => {
      const minutes = Number(minutesInput.value);
      const date = modal.querySelector('#modalDate').value || dateVal;
      if (!minutes || minutes <= 0) { finish(null); return; }
      finish({ minutes, date });
    });
    minutesInput.addEventListener('keydown', (e) => { if (e.key === 'Escape') finish(null); });
  });
}

/**
 * Modale de note libre avec zone de texte multi-lignes (utilisée à la fin d'une séance).
 */
export function promptNote({ title, message = '', initialValue = '', confirmLabel = 'Enregistrer', skipLabel = 'Passer' }) {
  return new Promise((resolve) => {
    modal.innerHTML = `
      <h3>${title}</h3>
      ${message ? `<p>${message}</p>` : ''}
      <textarea id="modalTextarea" rows="3" placeholder="Ex. : page 42, exercice 3, chapitre sur les intégrales..."
        style="width:100%;padding:9px 10px;border-radius:7px;border:1px solid var(--border);background:var(--surface-2);margin-bottom:16px;font-family:inherit;resize:vertical;">${initialValue}</textarea>
      <div class="modal-actions">
        <button class="btn" id="modalSkip">${skipLabel}</button>
        <button class="btn btn-primary" id="modalOk">${confirmLabel}</button>
      </div>
    `;
    overlay.hidden = false;
    const textarea = modal.querySelector('#modalTextarea');
    textarea.focus();

    const finish = (value) => { close(); resolve(value); };
    modal.querySelector('#modalSkip').addEventListener('click', () => finish(null));
    modal.querySelector('#modalOk').addEventListener('click', () => finish(textarea.value.trim()));
    textarea.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) finish(textarea.value.trim());
      if (e.key === 'Escape') finish(null);
    });
  });
}
