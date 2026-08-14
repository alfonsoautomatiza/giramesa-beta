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
    const section = document.querySelector(`[data-platform="${platform}"]`);
    const label = section?.querySelector('.recommendation');
    if (section && label) {
      section.classList.add('is-recommended');
      label.hidden = false;
    }
  }

  function disableAndroid(message) {
    const state = document.getElementById('android-state');
    const button = document.getElementById('android-download');
    state?.classList.add('is-unavailable');
    setText('android-status', message);
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

  async function loadAndroidRelease() {
    const repository = String(config.githubRepository ?? '').trim();
    if (!repositoryPattern.test(repository)) {
      disableAndroid('El repositorio de publicaciones aún no está configurado');
      return;
    }
    try {
      const response = await fetch(`https://api.github.com/repos/${repository}/releases/latest`, {
        headers: { Accept: 'application/vnd.github+json' },
      });
      if (response.status === 404) {
        disableAndroid('Todavía no hay una publicación Android disponible');
        return;
      }
      if (!response.ok) throw new Error('release-request-failed');
      const release = await response.json();
      const assets = Array.isArray(release.assets) ? release.assets : [];
      const apk = assets.find((asset) => typeof asset.name === 'string'
        && asset.name.toLowerCase().endsWith('.apk')
        && safeReleaseUrl(asset.browser_download_url, repository));
      if (!apk) {
        disableAndroid('La última publicación no contiene un APK válido');
        return;
      }

      const button = document.getElementById('android-download');
      document.getElementById('android-state')?.classList.add('is-ready');
      setText('android-status', 'Última publicación Android disponible');
      setText('android-version', release.tag_name || release.name || 'Sin versión indicada');
      setText('android-date', formatDate(release.published_at));
      setText('android-file', apk.name);
      if (button) {
        button.href = apk.browser_download_url;
        button.rel = 'noopener noreferrer';
        button.removeAttribute('aria-disabled');
        button.removeAttribute('tabindex');
        button.textContent = `Descargar ${apk.name}`;
      }

      const notes = typeof release.body === 'string' ? release.body.trim() : '';
      const panel = document.getElementById('release-notes-panel');
      if (notes && panel) {
        setText('android-notes', notes.slice(0, 6000));
        panel.hidden = false;
      }
      const checksum = checksumFromText(notes, apk.name)
        ?? await checksumFromAsset({ ...release, assets }, apk, repository);
      setText('android-checksum', checksum ?? 'No publicado');
    } catch {
      disableAndroid('No se pudo consultar GitHub. Probá de nuevo más tarde');
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
  loadAndroidRelease();
})();
