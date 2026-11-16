import { describe, expect, it } from '@ohos/hypium';
import { MiniAppInfo } from '../main/ets/core/MiniAppOptions';
import { DocumentScript } from '../main/ets/core/Runtime';
import { documentEndScripts, mergeDocumentStartScripts, resolveUserAgent } from '../main/ets/web/MiniAppWebConfig';

class WebConfigInfo implements MiniAppInfo {
  appId: string = 'app';
  vendor: string = 'vk';
  url: string = 'https://example.com';
  customUserAgent?: string = undefined;
  extraUserAgentParams?: Record<string, string> = undefined;
  jsOnDocStart?: string = undefined;
  jsOnDocStartRules?: string[] = undefined;
  jsOnDocEnd?: string = undefined;
  jsOnDocEndRules?: string[] = undefined;
}

function params(): Record<string, string> {
  const result: Record<string, string> = {};
  result[' channel '] = ' mini ';
  result['blank'] = ' ';
  return result;
}

export default function miniAppWebConfigTest(): void {
  describe('MiniAppWebConfig', () => {
    it('usesConfiguredStartScriptInsteadOfVendorScripts', 0, () => {
      const vendor: DocumentScript[] = [{ script: 'vendor()', scriptRules: ['vendor'] }];
      const info: WebConfigInfo = new WebConfigInfo();
      info.jsOnDocStart = 'host()';
      info.jsOnDocStartRules = [];
      const result = mergeDocumentStartScripts(vendor, info);
      expect(result.length).assertEqual(1);
      expect(result[0].script).assertEqual('host()');
      expect(result[0].scriptRules[0]).assertEqual('*');
    });

    it('ignoresBlankScriptsAndBuildsEndScript', 0, () => {
      const info: WebConfigInfo = new WebConfigInfo();
      info.jsOnDocStart = ' ';
      info.jsOnDocEnd = 'end()';
      info.jsOnDocEndRules = ['end'];
      const vendor: DocumentScript[] = [{ script: 'vendor()', scriptRules: ['vendor'] }];
      const startScripts = mergeDocumentStartScripts(vendor, info);
      vendor[0].scriptRules[0] = 'changed';
      expect(startScripts.length).assertEqual(1);
      expect(startScripts[0].script).assertEqual('vendor()');
      expect(startScripts[0].scriptRules[0]).assertEqual('vendor');
      expect(documentEndScripts(info)[0].scriptRules[0]).assertEqual('end');
    });

    it('resolvesUserAgentWithoutMutatingParams', 0, () => {
      const info: WebConfigInfo = new WebConfigInfo();
      info.customUserAgent = ' Agent ';
      info.extraUserAgentParams = params();
      expect(resolveUserAgent('base', info)).assertEqual('Agent channel/mini');
      expect(info.extraUserAgentParams[' channel ']).assertEqual(' mini ');
    });
  });
}
