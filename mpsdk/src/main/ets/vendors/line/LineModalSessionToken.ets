import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

/** LINE 主窗口的 MST 配对值，仅在当前容器原生侧保存 verifier。 */
export interface LineModalSessionToken {
  verifier: string;
  challenge: string;
}

function base64Url(bytes: Uint8Array): string {
  return new util.Base64Helper().encodeToStringSync(bytes)
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/[=\r\n]/g, '');
}

export function createLineModalSessionToken(): LineModalSessionToken {
  const encoder = new util.TextEncoder();
  const seed: string = `${util.generateRandomUUID()}-${util.generateRandomUUID()}`;
  const verifier: string = base64Url(encoder.encodeInto(seed));
  const digest = cryptoFramework.createMd('SHA256');
  digest.updateSync({ data: encoder.encodeInto(verifier) });
  return { verifier, challenge: base64Url(digest.digestSync().data) };
}
