import { LineErrorCode } from '../LineErrorCode';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { MiniAppError } from '../../../core/MiniAppError';
import { LINE_QR_KEY_BYTES, LineQrKeyPair, LineQrKeySource } from './LineAccountTypes';

/** CryptoFramework 的 X25519 参数是整数；LINE 二维码使用 32 字节小端公钥。 */
export function lineX25519Bytes(value: bigint | string | number): Uint8Array {
  let numberValue: bigint;
  try {
    numberValue = BigInt(value);
  } catch (_) {
    throw new MiniAppError(LineErrorCode.LOGIN_KEY_INVALID, 'LINE 二维码密钥参数无效');
  }
  if (numberValue < 0n || numberValue >= (1n << 256n)) {
    throw new MiniAppError(LineErrorCode.LOGIN_KEY_INVALID, 'LINE 二维码密钥长度无效');
  }
  const bytes = new Uint8Array(LINE_QR_KEY_BYTES);
  for (let index: number = 0; index < LINE_QR_KEY_BYTES; index++) {
    bytes[index] = Number(numberValue & 255n);
    numberValue >>= 8n;
  }
  return bytes;
}

export class LineNativeQrKeySource implements LineQrKeySource {
  private static pending?: Promise<LineQrKeyPair>;

  private static async generate(): Promise<LineQrKeyPair> {
    try {
      const generator = cryptoFramework.createAsyKeyGenerator('X25519');
      const pair = await generator.generateKeyPair();
      try {
        const publicKey = lineX25519Bytes(pair.pubKey.getAsyKeySpec(
          cryptoFramework.AsyKeySpecItem.X25519_PK_BN));
        const privateKey = lineX25519Bytes(pair.priKey.getAsyKeySpec(
          cryptoFramework.AsyKeySpecItem.X25519_SK_BN));
        return { publicKey, privateKey };
      } finally {
        pair.priKey.clearMem();
      }
    } catch (error) {
      throw MiniAppError.from(error as Object, LineErrorCode.LOGIN_KEY_FAILED, '无法生成 LINE 安全二维码密钥');
    }
  }

  /** 对齐 APK 初始 SessionData：同一进程的扫码使用同一密钥对。 */
  async create(): Promise<LineQrKeyPair> {
    if (!LineNativeQrKeySource.pending) {
      LineNativeQrKeySource.pending = LineNativeQrKeySource.generate().catch((error: Object) => {
        LineNativeQrKeySource.pending = undefined;
        throw MiniAppError.from(error, LineErrorCode.LOGIN_KEY_FAILED, '无法生成 LINE 安全二维码密钥');
      });
    }
    const pair: LineQrKeyPair = await LineNativeQrKeySource.pending;
    return { publicKey: pair.publicKey.slice(), privateKey: pair.privateKey.slice() };
  }
}
