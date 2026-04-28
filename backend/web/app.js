/* ─── State ─── */
const state = {
  baseUrl: '',
  apiKey: '',
  projects: [],
  statsInterval: null,
  projectsInterval: null,
  detailProjectId: null,
  detailTab: 'stats',
};

/* ─── DOM Cache ─── */
const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

/* ─── Storage ─── */
function loadCredentials() {
  const saved = localStorage.getItem('sm_creds');
  if (saved) {
    try {
      const c = JSON.parse(saved);
      if (c.url && c.key) {
        $('#server-url').value = c.url;
        $('#api-key').value = c.key;
        return { url: c.url, key: c.key };
      }
    } catch (_) {}
  }
  return null;
}
function saveCredentials(url, key) {
  localStorage.setItem('sm_creds', JSON.stringify({ url, key }));
}
function clearCredentials() {
  localStorage.removeItem('sm_creds');
}

/* ─── Navigation ─── */
function showLogin() {
  $('#login-screen').classList.remove('hidden');
  $('#dashboard-screen').classList.add('hidden');
}
function showDashboard() {
  $('#login-screen').classList.add('hidden');
  $('#dashboard-screen').classList.remove('hidden');
}

/* ─── Connection ─── */
async function connect() {
  const url = $('#server-url').value.trim().replace(/\/+$/, '');
  const key = $('#api-key').value.trim();

  if (!url || !key) {
    showLoginError('URL und API-Key erforderlich');
    return;
  }

  const btn = $('#connect-btn');
  btn.disabled = true;
  btn.querySelector('.btn-text').classList.add('hidden');
  btn.querySelector('.btn-loader').classList.remove('hidden');
  $('#login-error').classList.add('hidden');

  try {
    const res = await fetch(`${url}/health`, { signal: AbortSignal.timeout(5000) });
    const data = await res.json();
    if (data.status !== 'ok') throw new Error('Server nicht erreichbar');

    // Verify API key
    const projRes = await fetch(`${url}/projects`, {
      headers: { 'X-API-Key': key },
      signal: AbortSignal.timeout(5000),
    });
    if (projRes.status === 401) throw new Error('Ungültiger API-Key');
    if (!projRes.ok) throw new Error('Verbindungsfehler');

    state.baseUrl = url;
    state.apiKey = key;
    saveCredentials(url, key);

    $('#server-name').textContent = new URL(url).hostname || 'Server';
    $('#server-url-display').textContent = url.replace(/^https?:\/\//, '');
    $('#health-dot').className = 'status-dot online';

    showDashboard();
    startAutoRefresh();
  } catch (e) {
    showLoginError(e.message);
  } finally {
    btn.disabled = false;
    btn.querySelector('.btn-text').classList.remove('hidden');
    btn.querySelector('.btn-loader').classList.add('hidden');
  }
}

function disconnect() {
  stopAutoRefresh();
  clearCredentials();
  showLogin();
  $('#server-url').focus();
}

function showLoginError(msg) {
  const el = $('#login-error');
  el.textContent = msg;
  el.classList.remove('hidden');
}

function toggleApiKey() {
  const input = $('#api-key');
  input.type = input.type === 'password' ? 'text' : 'password';
}

/* ─── Auto Refresh ─── */
function startAutoRefresh() {
  refreshAll();
  state.statsInterval = setInterval(fetchStats, 10000);
  state.projectsInterval = setInterval(fetchProjects, 10000);
}
function stopAutoRefresh() {
  clearInterval(state.statsInterval);
  clearInterval(state.projectsInterval);
  state.statsInterval = null;
  state.projectsInterval = null;
}
async function refreshAll() {
  await Promise.all([fetchStats(), fetchProjects()]);
}

/* ─── API Helper ─── */
async function apiGet(path) {
  const res = await fetch(`${state.baseUrl}${path}`, {
    headers: { 'X-API-Key': state.apiKey },
  });
  const body = await res.json();
  if (!body.success) throw new Error(body.error || 'API Error');
  return body.data;
}

async function apiPost(path, data = {}) {
  const res = await fetch(`${state.baseUrl}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-API-Key': state.apiKey },
    body: JSON.stringify(data),
  });
  const body = await res.json();
  if (!body.success) throw new Error(body.error || 'API Error');
  return body.data;
}

/* ─── Format Helpers ─── */
function formatBytes(bytes) {
  if (!bytes || bytes === 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return `${(bytes / Math.pow(1024, i)).toFixed(1)} ${units[i]}`;
}

function formatDuration(seconds) {
  if (!seconds || seconds < 0) return '0m';
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  let parts = [];
  if (d > 0) parts.push(`${d}d`);
  if (h > 0) parts.push(`${h}h`);
  parts.push(`${m}m`);
  return parts.join(' ');
}

function statusColor(status) {
  const map = { running: '#4ADE80', stopped: '#6B7280', crashed: '#EF4444', restarting: '#FB923C', failed: '#991B1B' };
  return map[status] || '#8888AA';
}

function statusIcon(status) {
  const map = { running: '▶', stopped: '⏹', crashed: '✕', restarting: '⟳', failed: '⚠' };
  return map[status] || '?';
}

function statusLabel(status) {
  const map = { running: 'Läuft', stopped: 'Gestoppt', crashed: 'Crash', restarting: 'Restartet...', failed: 'Fehlgeschlagen' };
  return map[status] || status;
}

function formatTime(iso) {
  if (!iso) return '';
  try { return iso.substring(11, 19); } catch { return iso; }
}

/* ─── System Stats ─── */
async function fetchStats() {
  try {
    const stats = await apiGet('/system/stats');
    renderStats(stats);
    $('#stats-timestamp').textContent = new Date().toLocaleTimeString('de-DE');
  } catch (_) {}
}

function renderStats(s) {
  // CPU
  const cpuPct = s.cpu.percent;
  $('#cpu-value').textContent = `${cpuPct}%`;
  $('#cpu-bar').style.width = `${cpuPct}%`;
  $('#cpu-detail').textContent = `${s.cpu.core_count_logical} Cores · Load: ${s.cpu.load_average_1m}, ${s.cpu.load_average_5m}, ${s.cpu.load_average_15m}`;

  // RAM
  const memPct = s.memory.percent;
  $('#ram-value').textContent = `${memPct}%`;
  $('#ram-bar').style.width = `${memPct}%`;
  $('#ram-detail').textContent = `${formatBytes(s.memory.used)} / ${formatBytes(s.memory.total)}`;

  // Disk (main /)
  const rootDisk = s.disk.find(d => d.mount_point === '/') || s.disk[0];
  if (rootDisk) {
    const diskPct = rootDisk.percent;
    $('#disk-value').textContent = `${diskPct}%`;
    $('#disk-bar').style.width = `${diskPct}%`;
    $('#disk-detail').textContent = `${formatBytes(rootDisk.used)} / ${formatBytes(rootDisk.total)}`;
  }

  // Disk mounts detail
  if (s.disk.length > 1) {
    $('#disk-detail-section').classList.remove('hidden');
    const el = $('#disk-mounts');
    el.innerHTML = s.disk.map(d => `
      <div class="disk-item">
        <span class="disk-mount">${d.mount_point}</span>
        <span class="disk-size">${d.device.split('/').pop() || d.fstype}</span>
        <div class="disk-bar"><div class="disk-bar-fill" style="width:${d.percent}%"></div></div>
        <span class="disk-pct">${d.percent}%</span>
        <span class="disk-size">${formatBytes(d.used)} / ${formatBytes(d.total)}</span>
      </div>
    `).join('');
  } else {
    $('#disk-detail-section').classList.add('hidden');
  }

  // Uptime
  $('#uptime-value').textContent = formatDuration(s.uptime_seconds);
  $('#uptime-detail').textContent = `${s.process_count} Prozesse · ${s.hostname}`;

  // Network
  $('#net-sent').textContent = formatBytes(s.network.bytes_sent);
  $('#net-recv').textContent = formatBytes(s.network.bytes_recv);
  $('#process-count').textContent = s.process_count;
}

/* ─── Projects ─── */
async function fetchProjects() {
  try {
    const projects = await apiGet('/projects');
    state.projects = projects;
    renderProjects();
    $('#projects-loading').classList.add('hidden');
    $('#projects-error').classList.add('hidden');
    if (projects.length === 0) {
      $('#projects-empty').classList.remove('hidden');
      $('#projects-list').classList.add('hidden');
    } else {
      $('#projects-empty').classList.add('hidden');
      $('#projects-list').classList.remove('hidden');
    }
  } catch (e) {
    $('#projects-loading').classList.add('hidden');
    $('#projects-error').classList.remove('hidden');
    $('#projects-error').textContent = `Fehler: ${e.message}`;
  }
}

function renderProjects() {
  const running = state.projects.filter(p => p.status === 'running').length;
  const crashed = state.projects.filter(p => p.status === 'crashed' || p.status === 'failed').length;
  $('#project-summary').textContent = `${state.projects.length} · ${running} · ${crashed}`;

  const el = $('#projects-list');
  el.innerHTML = state.projects.map(p => {
    const sc = statusColor(p.status);
    return `
      <div class="project-card" onclick="openDetail(${p.id})">
        <div class="project-card-header">
          <div class="project-icon" style="background:${sc}22;color:${sc}">${statusIcon(p.status)}</div>
          <div class="project-info">
            <div class="project-name">${esc(p.name)}</div>
            <div class="project-meta">
              <span class="project-type-badge">${p.type.toUpperCase()}</span>
              <span class="status-badge">
                <span class="status-dot-sm" style="background:${sc}"></span>
                ${statusLabel(p.status)}
              </span>
              <span>· Uptime: ${calcUptime(p)}</span>
            </div>
          </div>
          <div style="display:flex;align-items:center;gap:6px;">
            ${p.restart_count > 0 ? `<span class="restart-count-badge">${p.restart_count}/${p.max_restarts}</span>` : ''}
            <button class="action-btn" onclick="event.stopPropagation();doAction(${p.id},'start')" ${p.status === 'running' ? 'disabled' : ''} title="Start">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="${p.status === 'running' ? '#555' : '#4ADE80'}" stroke="none"><path d="M8 5v14l11-7z"/></svg>
            </button>
            <button class="action-btn" onclick="event.stopPropagation();doAction(${p.id},'stop')" ${p.status !== 'running' && p.status !== 'restarting' ? 'disabled' : ''} title="Stop">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="${p.status !== 'running' && p.status !== 'restarting' ? '#555' : '#EF4444'}" stroke="none"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>
            </button>
            <button class="action-btn" onclick="event.stopPropagation();doAction(${p.id},'restart')" ${p.status !== 'running' && p.status !== 'stopped' ? 'disabled' : ''} title="Restart">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="${p.status !== 'running' && p.status !== 'stopped' ? '#555' : '#FB923C'}" stroke-width="2.5"><path d="M21.5 2v6h-6M2.5 22v-6h6M2 12a10 10 0 0 1 18.07-5.07M22 12a10 10 0 0 1-18.07 5.07"/></svg>
            </button>
            <button class="action-btn" onclick="event.stopPropagation();openDetail(${p.id})" title="Details">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#8888AA" stroke-width="2"><circle cx="12" cy="12" r="1"/><circle cx="12" cy="5" r="1"/><circle cx="12" cy="19" r="1"/></svg>
            </button>
          </div>
        </div>
      </div>
    `;
  }).join('');
}

function calcUptime(p) {
  let total = p.total_uptime_seconds || 0;
  if (p.status === 'running' && p.last_started_at) {
    try {
      const started = new Date(p.last_started_at + (p.last_started_at.endsWith('Z') ? '' : 'Z'));
      total += Math.floor((Date.now() - started.getTime()) / 1000);
    } catch (_) {}
  }
  return formatDuration(total);
}

function esc(s) {
  const d = document.createElement('div');
  d.textContent = s;
  return d.innerHTML;
}

/* ─── Project Actions ─── */
async function doAction(id, action) {
  try {
    await apiPost(`/projects/${id}/${action}`);
    await fetchProjects();
    if (state.detailProjectId === id) refreshDetail();
  } catch (e) {
    alert(`Fehler: ${e.message}`);
  }
}

/* ─── Add Project ─── */
function toggleProjectType() {
  const type = $('#add-type').value;
  if (type === 'shell') {
    $('#add-shell-fields').classList.remove('hidden');
    $('#add-docker-fields').classList.add('hidden');
  } else {
    $('#add-shell-fields').classList.add('hidden');
    $('#add-docker-fields').classList.remove('hidden');
  }
}

function showAddProject() {
  $('#add-modal').classList.remove('hidden');
  $('#add-name').value = '';
  $('#add-error').classList.add('hidden');
  toggleProjectType();
  setTimeout(() => $('#add-name').focus(), 100);
}

function closeAdd() {
  $('#add-modal').classList.add('hidden');
}

async function createProject(e) {
  e.preventDefault();
  const type = $('#add-type').value;
  let config = {};
  if (type === 'shell') {
    config.command = $('#add-command').value.trim();
    const cwd = $('#add-cwd').value.trim();
    if (cwd) config.cwd = cwd;
  } else {
    config.container_name = $('#add-container').value.trim();
    const img = $('#add-image').value.trim();
    if (img) config.image = img;
    const opts = $('#add-run-opts').value.trim();
    if (opts) config.run_command = opts;
  }

  const payload = {
    name: $('#add-name').value.trim(),
    type,
    config,
    max_restarts: parseInt($('#add-restarts').value),
  };

  try {
    await apiPost('/projects', payload);
    closeAdd();
    await fetchProjects();
  } catch (e) {
    $('#add-error').textContent = e.message;
    $('#add-error').classList.remove('hidden');
  }
}

/* ─── Detail Modal ─── */
async function openDetail(id) {
  state.detailProjectId = id;
  state.detailTab = 'stats';
  $('#detail-modal').classList.remove('hidden');

  // Get project from state
  const p = state.projects.find(pj => pj.id === id);
  if (!p) return;

  $('#detail-name').textContent = p.name;
  $('#detail-type').textContent = `${p.type.toUpperCase()} · PID: ${p.pid || '-'}`;

  await refreshDetail();
}

async function refreshDetail() {
  const id = state.detailProjectId;
  if (!id) return;

  // Fetch fresh data
  try {
    const [project, stats, logs, events] = await Promise.all([
      apiGet(`/projects/${id}`),
      apiGet(`/projects/${id}/stats`),
      apiGet(`/projects/${id}/logs?lines=50`),
      apiGet(`/projects/${id}/events`),
    ]);

    // Update state project
    const idx = state.projects.findIndex(p => p.id === id);
    if (idx >= 0) state.projects[idx] = project;

    renderDetail(project, stats, logs, events);
  } catch (e) {
    $('#detail-body').innerHTML = `<div class="error-card">Fehler: ${e.message}</div>`;
  }
}

function renderDetail(project, stats, logs, events) {
  const sc = statusColor(project.status);

  let html = `
    <div class="detail-actions">
      <button class="detail-action-btn start" onclick="doAction(${project.id},'start')" ${project.status === 'running' ? 'disabled' : ''}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" stroke="none"><path d="M8 5v14l11-7z"/></svg> Start
      </button>
      <button class="detail-action-btn stop" onclick="doAction(${project.id},'stop')" ${project.status !== 'running' && project.status !== 'restarting' ? 'disabled' : ''}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" stroke="none"><rect x="6" y="6" width="12" height="12" rx="2"/></svg> Stop
      </button>
      <button class="detail-action-btn restart" onclick="doAction(${project.id},'restart')" ${project.status !== 'running' && project.status !== 'stopped' ? 'disabled' : ''}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M21.5 2v6h-6M2.5 22v-6h6M2 12a10 10 0 0 1 18.07-5.07M22 12a10 10 0 0 1-18.07 5.07"/></svg> Restart
      </button>
    </div>
    <div class="detail-tabs">
      <button class="detail-tab ${state.detailTab === 'stats' ? 'active' : ''}" onclick="switchDetailTab('stats')">Statistiken</button>
      <button class="detail-tab ${state.detailTab === 'logs' ? 'active' : ''}" onclick="switchDetailTab('logs')">Logs</button>
      <button class="detail-tab ${state.detailTab === 'events' ? 'active' : ''}" onclick="switchDetailTab('events')">Events</button>
    </div>
  `;

  const tabContent = state.detailTab;

  if (tabContent === 'stats') {
    const s = stats || { total_uptime_seconds: 0, current_uptime_seconds: 0, total_crashes: 0, total_restarts: 0 };
    html += `
      <div class="detail-stats-grid">
        <div class="detail-stat">
          <div class="detail-stat-label">Status</div>
          <div class="detail-stat-value" style="color:${sc}">${statusLabel(project.status)}</div>
        </div>
        <div class="detail-stat">
          <div class="detail-stat-label">Gesamte Uptime</div>
          <div class="detail-stat-value">${formatDuration(s.total_uptime_seconds || project.total_uptime_seconds || 0)}</div>
        </div>
        <div class="detail-stat">
          <div class="detail-stat-label">Crashes</div>
          <div class="detail-stat-value" style="color:${(s.total_crashes || 0) > 0 ? '#EF4444' : '#8888AA'}">${s.total_crashes || 0}</div>
        </div>
        <div class="detail-stat">
          <div class="detail-stat-label">Restarts</div>
          <div class="detail-stat-value" style="color:${(s.total_restarts || 0) > 0 ? '#FB923C' : '#8888AA'}">${s.total_restarts || 0}</div>
        </div>
      </div>
    `;
    if (s.last_crash) {
      html += `<div class="error-card" style="margin-top:12px;">Letzter Crash: ${formatTime(s.last_crash.timestamp)} — ${esc(s.last_crash.message || '')}</div>`;
    }
  } else if (tabContent === 'logs') {
    html += `<div class="log-view">${logs && logs.length ? esc(logs.join('\n')) : 'Keine Logs'}</div>`;
  } else {
    // Events
    if (events && events.length) {
      html += events.map(e => {
        const ec = statusColor(e.type === 'crash' ? 'crashed' : e.type === 'recovered' ? 'running' : e.type === 'start' ? 'running' : e.type === 'stop' ? 'stopped' : e.type === 'restart' ? 'restarting' : 'crashed');
        return `
          <div class="event-item">
            <div class="event-icon" style="background:${ec}22;color:${ec}">
              ${e.type === 'crash' || e.type === 'failed_permanent' ? '✕' : e.type === 'recovered' ? '✓' : e.type === 'start' ? '▶' : e.type === 'stop' ? '⏹' : '⟳'}
            </div>
            <div class="event-info">
              <div class="event-type" style="color:${ec}">${eventLabel(e.type)}</div>
              ${e.message ? `<div class="event-msg">${esc(e.message)}</div>` : ''}
            </div>
            <div class="event-time">${formatTime(e.timestamp)}</div>
          </div>
        `;
      }).join('');
    } else {
      html += '<div class="empty-state"><p>Keine Events</p></div>';
    }
  }

  $('#detail-body').innerHTML = html;
}

function eventLabel(type) {
  const map = {
    start: 'Gestartet', stop: 'Gestoppt', restart: 'Neustart',
    crash: 'Crash', recovered: 'Erholt', failed_permanent: 'Dauerhaft fehlgeschlagen'
  };
  return map[type] || type;
}

function switchDetailTab(tab) {
  state.detailTab = tab;
  refreshDetail();
}

function closeDetail() {
  state.detailProjectId = null;
  $('#detail-modal').classList.add('hidden');
}

/* ─── Init ─── */
document.addEventListener('DOMContentLoaded', () => {
  const creds = loadCredentials();
  if (creds) {
    // Try auto-connect
    connect();
  } else {
    showLogin();
    $('#server-url').focus();
  }

  // Enter key in API key field
  $('#api-key').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') connect();
  });
  $('#server-url').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') $('#api-key').focus();
  });
});
