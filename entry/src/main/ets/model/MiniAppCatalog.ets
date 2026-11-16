import { MiniAppInfo } from 'mpsdk';

export interface DemoMiniApp extends MiniAppInfo { name: string; }

/** Only selected HTTPS vendor entry points belong in this host's catalog. */
export function isDemoMiniApp(app: DemoMiniApp): boolean {
  if (!app || typeof app.name !== 'string' || app.name.trim().length === 0 ||
    typeof app.appId !== 'string' || typeof app.url !== 'string') return false;
  if (app.vendor === 'vk') {
    return /^[0-9]+$/.test(app.appId) && app.url === 'https://vk.ru/app' + app.appId;
  }
  if (app.vendor === 'line') {
    return /^[0-9]+-[A-Za-z0-9]+$/.test(app.appId) &&
      (app.url === 'https://miniapp.line.me/' + app.appId || app.url === 'https://liff.line.me/' + app.appId);
  }
  return false;
}

export function parseCatalog(contents: string): DemoMiniApp[] {
  const apps = JSON.parse(contents) as DemoMiniApp[];
  if (!Array.isArray(apps) || apps.length === 0) throw new Error('Empty or invalid catalog');
  const keys: Set<string> = new Set();
  apps.forEach((app: DemoMiniApp): void => {
    if (!isDemoMiniApp(app)) throw new Error('Invalid mini app entry');
    const key = app.vendor + ':' + app.appId;
    if (keys.has(key)) throw new Error('Duplicate mini app entry');
    keys.add(key);
  });
  return apps;
}

/** Route parameters never forward scripts, SSL overrides or credentials to the SDK. */
export function createLaunchInfo(app: DemoMiniApp): MiniAppInfo {
  if (!isDemoMiniApp(app)) throw new Error('Invalid mini app entry');
  return { appId: app.appId, vendor: app.vendor, url: app.url,
    isSSLIgnore: false, isOpenGeolocation: false };
}
