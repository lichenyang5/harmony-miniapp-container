import { MiniAppInfo } from './MiniAppOptions';

function cloneStringRecord(source?: Record<string, string>): Record<string, string> | undefined {
  if (source === undefined) {
    return undefined;
  }
  const result: Record<string, string> = {};
  Object.keys(source).forEach((key: string): void => {
    result[key] = source[key];
  });
  return result;
}

function cloneStringArray(source?: string[]): string[] | undefined {
  return source === undefined ? undefined : source.slice();
}

/** 为每次容器挂载创建独立配置，避免宿主后续修改影响已创建会话。 */
export function snapshotMiniAppInfo(source: MiniAppInfo): MiniAppInfo {
  return {
    appId: source.appId,
    vendor: source.vendor,
    url: source.url,
    customUserAgent: source.customUserAgent,
    extraUserAgentParams: cloneStringRecord(source.extraUserAgentParams),
    isSyncLoad: source.isSyncLoad,
    isOpenDomStorage: source.isOpenDomStorage,
    isOpenGeolocation: source.isOpenGeolocation,
    isOpenNewWindow: source.isOpenNewWindow,
    jsOnDocStart: source.jsOnDocStart,
    jsOnDocStartRules: cloneStringArray(source.jsOnDocStartRules),
    jsOnDocEnd: source.jsOnDocEnd,
    jsOnDocEndRules: cloneStringArray(source.jsOnDocEndRules),
    isSSLIgnore: source.isSSLIgnore
  };
}
