import { describe, expect, it } from '@ohos/hypium';
import { MiniAppInfo } from '../main/ets/core/MiniAppOptions';
import { snapshotMiniAppInfo } from '../main/ets/core/MiniAppInfoSnapshot';

class TestMiniAppInfo implements MiniAppInfo {
  appId: string = '';
  vendor: string = '';
  url: string = '';
  customUserAgent?: string = undefined;
  extraUserAgentParams?: Record<string, string> = undefined;
  isSyncLoad?: boolean = undefined;
  isOpenDomStorage?: boolean = undefined;
  isOpenGeolocation?: boolean = undefined;
  isOpenNewWindow?: boolean = undefined;
  jsOnDocStart?: string = undefined;
  jsOnDocStartRules?: string[] = undefined;
  jsOnDocEnd?: string = undefined;
  jsOnDocEndRules?: string[] = undefined;
  isSSLIgnore?: boolean = undefined;
}

function createUserAgentParams(channel: string): Record<string, string> {
  const params: Record<string, string> = {};
  params['channel'] = channel;
  return params;
}

export default function miniAppInfoSnapshotTest(): void {
  describe('MiniAppInfoSnapshot', () => {
    it('copiesSupportedWebFields', 0, () => {
      const source: TestMiniAppInfo = new TestMiniAppInfo();
      source.appId = 'business-app';
      source.vendor = 'vk';
      source.url = 'https://backend.example/app';
      source.customUserAgent = 'Agent';
      source.extraUserAgentParams = createUserAgentParams('mini');
      source.isSyncLoad = true;
      source.isOpenDomStorage = false;
      source.isOpenGeolocation = false;
      source.isOpenNewWindow = true;
      source.jsOnDocStart = 'start()';
      source.jsOnDocStartRules = ['https://a/*'];
      source.jsOnDocEnd = 'end()';
      source.jsOnDocEndRules = ['https://b/*'];
      source.isSSLIgnore = true;
      const result: MiniAppInfo = snapshotMiniAppInfo(source);
      expect(result.appId).assertEqual('business-app');
      expect(result.vendor).assertEqual('vk');
      expect(result.url).assertEqual('https://backend.example/app');
      expect(result.customUserAgent).assertEqual('Agent');
      expect(result.extraUserAgentParams?.channel).assertEqual('mini');
      expect(result.isSyncLoad).assertTrue();
      expect(result.isOpenDomStorage).assertFalse();
      expect(result.isOpenGeolocation).assertFalse();
      expect(result.isOpenNewWindow).assertTrue();
      expect(result.jsOnDocStart).assertEqual('start()');
      expect(result.jsOnDocStartRules?.[0]).assertEqual('https://a/*');
      expect(result.jsOnDocEnd).assertEqual('end()');
      expect(result.jsOnDocEndRules?.[0]).assertEqual('https://b/*');
      expect(result.isSSLIgnore).assertTrue();
    });

    it('clonesMutableWebFields', 0, () => {
      const source: TestMiniAppInfo = new TestMiniAppInfo();
      source.appId = 'app';
      source.vendor = 'vk';
      source.url = 'https://example.com';
      source.extraUserAgentParams = createUserAgentParams('first');
      source.jsOnDocStartRules = ['start'];
      source.jsOnDocEndRules = ['end'];
      const first: MiniAppInfo = snapshotMiniAppInfo(source);
      const sibling: MiniAppInfo = snapshotMiniAppInfo(source);
      source.extraUserAgentParams!.channel = 'source';
      source.jsOnDocStartRules![0] = 'source';
      sibling.extraUserAgentParams!.channel = 'sibling';
      sibling.jsOnDocEndRules![0] = 'sibling';
      expect(first.extraUserAgentParams?.channel).assertEqual('first');
      expect(first.jsOnDocStartRules?.[0]).assertEqual('start');
      expect(first.jsOnDocEndRules?.[0]).assertEqual('end');
    });

    it('keepsMinimalConfigCompatible', 0, () => {
      const source: TestMiniAppInfo = new TestMiniAppInfo();
      source.appId = 'app';
      source.vendor = 'vk';
      source.url = 'https://example.com';
      const result: MiniAppInfo = snapshotMiniAppInfo(source);
      expect(result.appId).assertEqual('app');
      expect(result.customUserAgent).assertUndefined();
      expect(result.jsOnDocStartRules).assertUndefined();
    });
  });
}
