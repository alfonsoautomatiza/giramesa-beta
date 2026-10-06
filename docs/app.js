(() => {
  'use strict';

  const config = window.GIRAMESA_CONFIG ?? {};
  const repositoryPattern = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
  const testFlightPattern = /^https:\/\/testflight\.apple\.com\/join\/[A-Za-z0-9]+$/;

  function setText(id, value) {
    const element = document.getElementById(id);
    if (element) element.textContent = value;
  }

  function detectPlatform() {
    const agent = navigator.userAgent.toLowerCase();
    if (/iphone|ipad|ipod/.test(agent)) return 'ios';
    if (agent.includes('android')) return 'android';
    return null;
  }

  function markRecommendedPlatform() {
    const platform = detectPlatform();
    if (!platform) return;
    const recommendedPlatform = platform === 'ios' ? 'web' : platform;
    const section = document.querySelector(`[data-platform="${recommendedPlatform}"]`);
    const label = section?.querySelector('.recommendation');
    if (section && label) {
      section.classList.add('is-recommended');
      label.hidden = false;
    }
  }

  function disableRelease(platform, message) {
    const state = document.getElementById(`${platform}-state`);
    const button = document.getElementById(`${platform}-download`);
    state?.classList.remove('is-ready');
    state?.classList.add('is-unavailable');
    setText(`${platform}-status`, message);
    if (button) {
      button.removeAttribute('href');
      button.setAttribute('aria-disabled', 'true');
      button.setAttribute('tabindex', '-1');
      button.textContent = 'Descarga no disponible';
    }
  }

  function safeReleaseUrl(url, repository) {
    try {
      const parsed = new URL(url);
      return parsed.protocol === 'https:' && parsed.hostname === 'github.com'
        && parsed.pathname.startsWith(`/${repository}/releases/download/`);
    } catch {
      return false;
    }
  }

  function checksumFromText(text, fileName) {
    if (!text) return null;
    const escapedName = fileName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const named = new RegExp(`\\b([a-fA-F0-9]{64})\\b\\s+[*]?${escapedName}`).exec(text);
    const labeled = /SHA-?256\s*[:=]\s*`?([a-fA-F0-9]{64})`?/i.exec(text);
    return (named?.[1] ?? labeled?.[1] ?? null)?.toLowerCase() ?? null;
  }

  async function checksumFromAsset(release, apk, repository) {
    const checksumAsset = release.assets.find((asset) => {
      const name = asset.name.toLowerCase();
      return name === `${apk.name.toLowerCase()}.sha256` || name === 'sha256sums';
    });
    if (!checksumAsset || !safeReleaseUrl(checksumAsset.browser_download_url, repository)) return null;
    try {
      const response = await fetch(checksumAsset.browser_download_url, { redirect: 'follow' });
      if (!response.ok) return null;
      return checksumFromText(await response.text(), apk.name);
    } catch {
      return null;
    }
  }

  function formatDate(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return 'Fecha no disponible';
    return new Intl.DateTimeFormat('es', { day: 'numeric', month: 'long', year: 'numeric' }).format(date);
  }

  async function loadPlatformRelease(platform, assetMatches, unavailableMessage) {
    const repository = String(config.githubRepository ?? '').trim();
    if (!repositoryPattern.test(repository)) {
      disableRelease(platform, 'El repositorio de publicaciones aún no está configurado');
      return;
    }
    try {
      const response = await fetch(`https://api.github.com/repos/${repository}/releases/latest`, {
        headers: { Accept: 'application/vnd.github+json' },
      });
      if (response.status === 404) {
        disableRelease(platform, unavailableMessage);
        return;
      }
      if (!response.ok) throw new Error('release-request-failed');
      const release = await response.json();
      const assets = Array.isArray(release.assets) ? release.assets : [];
      const asset = assets.find((candidate) => typeof candidate.name === 'string'
        && assetMatches(candidate.name.toLowerCase())
        && safeReleaseUrl(candidate.browser_download_url, repository));
      if (!asset) {
        disableRelease(platform, unavailableMessage);
        return;
      }

      const button = document.getElementById(`${platform}-download`);
      document.getElementById(`${platform}-state`)?.classList.remove('is-unavailable');
      document.getElementById(`${platform}-state`)?.classList.add('is-ready');
      setText(`${platform}-status`, `Última publicación ${platform === 'android' ? 'Android' : 'Windows'} disponible`);
      setText(`${platform}-version`, release.tag_name || release.name || 'Sin versión indicada');
      setText(`${platform}-date`, formatDate(release.published_at));
      setText(`${platform}-file`, asset.name);
      if (button) {
        button.href = asset.browser_download_url;
        button.rel = 'noopener noreferrer';
        button.removeAttribute('aria-disabled');
        button.removeAttribute('tabindex');
        button.textContent = `Descargar ${asset.name}`;
      }

      if (platform === 'android') {
        const notes = typeof release.body === 'string' ? release.body.trim() : '';
        const panel = document.getElementById('release-notes-panel');
        if (notes && panel) {
          setText('android-notes', notes.slice(0, 6000));
          panel.hidden = false;
        }
        const checksum = checksumFromText(notes, asset.name)
          ?? await checksumFromAsset({ ...release, assets }, asset, repository);
        setText('android-checksum', checksum ?? 'No publicado');
      }
    } catch {
      disableRelease(platform, 'No se pudo consultar GitHub. Probá de nuevo más tarde');
    }
  }

  const HISTORY_PAGE_SIZE = 30;
  const HISTORY_MAX_PAGES = 4;
  const HISTORY_MAX_ITEMS = 100;
  const HISTORY_NOTES_LENGTH = 280;

  function safeReleasePageUrl(url, repository) {
    try {
      const parsed = new URL(url);
      return parsed.protocol === 'https:' && parsed.hostname === 'github.com'
        && !parsed.username && !parsed.password && !parsed.port
        && parsed.pathname.toLowerCase().startsWith(`/${repository.toLowerCase()}/releases/tag/`)
        ? parsed.href : null;
    } catch {
      return null;
    }
  }

  function conciseNotes(body) {
    const text = typeof body === 'string' ? body.replace(/\s+/g, ' ').trim() : '';
    return text.length > HISTORY_NOTES_LENGTH ? `${text.slice(0, HISTORY_NOTES_LENGTH).trimEnd()}…` : text;
  }

  function setHistoryStatus(message, state) {
    const status = document.getElementById('release-history-status');
    if (!status) return;
    status.textContent = message;
    status.dataset.state = state;
    status.hidden = !message;
    document.getElementById('historial')?.setAttribute('aria-busy', 'false');
  }

  function renderRelease(release, repository) {
    const item = document.createElement('li');
    item.className = 'history-item';
    const title = document.createElement('h3');
    title.textContent = String(release.name || release.tag_name || 'Versión sin nombre').slice(0, 120);
    const meta = document.createElement('p');
    meta.className = 'history-meta';
    const tag = String(release.tag_name ?? '').slice(0, 80);
    meta.textContent = [tag, formatDate(release.published_at), release.prerelease ? 'Pre-publicación' : 'Publicación estable']
      .filter(Boolean).join(' · ');
    item.append(title, meta);
    const notes = conciseNotes(release.body);
    if (notes) {
      const paragraph = document.createElement('p');
      paragraph.className = 'history-notes';
      paragraph.textContent = notes;
      item.append(paragraph);
    }
    const href = safeReleasePageUrl(release.html_url, repository);
    if (href) {
      const link = document.createElement('a');
      link.className = 'doc-link';
      link.href = href;
      link.rel = 'noopener noreferrer';
      link.textContent = `Ver ${tag || 'la publicación'} en GitHub`;
      item.append(link);
    }
    return item;
  }

  async function loadReleaseHistory() {
    const list = document.getElementById('release-history-list');
    if (!list) return;
    const repository = String(config.githubRepository ?? '').trim();
    if (!repositoryPattern.test(repository)) {
      setHistoryStatus('El repositorio de publicaciones aún no está configurado', 'unavailable');
      return;
    }
    const seen = new Set();
    const releases = [];
    let exhausted = false;
    let rateLimited = false;
    try {
      for (let page = 1; page <= HISTORY_MAX_PAGES && !exhausted; page += 1) {
        const response = await fetch(`https://api.github.com/repos/${repository}/releases?per_page=${HISTORY_PAGE_SIZE}&page=${page}`, {
          headers: { Accept: 'application/vnd.github+json' },
        });
        if (response.status === 403 || response.status === 429) {
          if (releases.length) {
            rateLimited = true;
            break;
          }
          setHistoryStatus('GitHub alcanzó el límite de consultas. Probá de nuevo en unos minutos o mirá el historial directamente en GitHub', 'unavailable');
          return;
        }
        if (!response.ok) throw new Error('history-request-failed');
        const batch = await response.json();
        if (!Array.isArray(batch)) throw new Error('history-invalid');
        for (const release of batch) {
          if (!release || typeof release !== 'object' || release.draft === true) continue;
          const key = release.id ?? release.tag_name;
          if (key === undefined || seen.has(key)) continue;
          seen.add(key);
          releases.push(release);
        }
        exhausted = batch.length < HISTORY_PAGE_SIZE;
      }
    } catch {
      if (!releases.length) {
        setHistoryStatus('No se pudo consultar el historial en GitHub. Probá de nuevo más tarde', 'unavailable');
        return;
      }
    }
    if (!releases.length) {
      setHistoryStatus('Todavía no hay publicaciones en el historial', 'empty');
      return;
    }
    const time = (release) => Date.parse(release.published_at ?? release.created_at ?? '') || 0;
    releases.sort((a, b) => time(b) - time(a));
    const shown = releases.slice(0, HISTORY_MAX_ITEMS);
    list.replaceChildren(...shown.map((release) => renderRelease(release, repository)));
    const truncated = !exhausted || releases.length > shown.length;
    if (rateLimited) {
      setHistoryStatus(`Historial parcial: GitHub alcanzó el límite de consultas tras ${shown.length} publicaciones. Probá de nuevo en unos minutos o mirá el historial completo en GitHub`, 'partial');
      return;
    }
    setHistoryStatus(truncated
      ? `Mostrando las ${shown.length} publicaciones más recientes. El historial completo está en GitHub`
      : `${shown.length} ${shown.length === 1 ? 'publicación' : 'publicaciones'} en el historial`, 'ready');
  }

  async function loadWebVersion() {
    try {
      const response = await fetch('./app/version.json', { cache: 'no-store' });
      if (!response.ok) throw new Error('version-request-failed');
      const metadata = await response.json();
      const version = String(metadata.version ?? '').trim();
      const build = String(metadata.build_number ?? '').trim();
      if (!version) throw new Error('version-missing');
      setText('web-status', `Versión ${version}${build ? ` (build ${build})` : ''} disponible`);
      setText('web-version', `${version}${build ? ` · build ${build}` : ''}`);
    } catch {
      setText('web-status', 'Lista para usar, sin instalación');
      setText('web-version', 'Versión actual');
    }
  }

  function configureTestFlight() {
    const url = String(config.testFlightUrl ?? '').trim();
    if (!testFlightPattern.test(url)) return;
    const button = document.getElementById('ios-testflight');
    const state = document.getElementById('ios-state');
    state?.classList.remove('is-unavailable');
    state?.classList.add('is-ready');
    setText('ios-status', 'Invitación oficial de TestFlight disponible');
    if (button) {
      button.href = url;
      button.rel = 'noopener noreferrer';
      button.removeAttribute('aria-disabled');
      button.removeAttribute('tabindex');
      button.textContent = 'Abrir invitación en TestFlight';
    }
  }

  markRecommendedPlatform();
  configureTestFlight();
  loadWebVersion();
  loadReleaseHistory();
  loadPlatformRelease('android', (name) => name.endsWith('.apk'), 'Todavía no hay una publicación Android disponible');
  loadPlatformRelease('windows', (name) => name.includes('windows') && name.endsWith('.zip'), 'Todavía no hay una publicación Windows disponible');
})();
