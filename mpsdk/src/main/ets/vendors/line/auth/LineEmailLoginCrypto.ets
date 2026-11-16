import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { MiniAppError } from '../../../core/MiniAppError';
import { LINE_EMAIL_AES_BLOCK_BYTES as AES_BLOCK_BYTES, LineEmailRsaKey } from './LineEmailLoginTypes';
import { LINE_X25519_KEY_BYTES } from './LineAccountTypes';
import { lineX25519Bytes } from './LineQrKeySource';
import { LineErrorCode } from '../LineErrorCode';

/** SHA-256 摘要长度；不能借用恰好同为 32 的 X25519 密钥长度。 */
const SHA256_DIGEST_BYTES: number = 32;
/** APK 使用六位十进制 PIN，包括前导零。 */
const PIN_DIGITS: number = 6;
const PIN_SPACE: number = 10**PIN_DIGITS;
/** 安全随机源每次提供一个无符号 32 位候选，通过拒绝采样避免取模偏差。 */
const PIN_RANDOM_BYTES: number = 4;
const PIN_RANDOM_SPACE: number = 2**(PIN_RANDOM_BYTES * 8);
/** PKCS#1 v1.5 至少需要 00、02、8 字节非零填充及分隔 00。 */
const RSA_PADDING_OVERHEAD: number = 11;
const RSA_BLOCK_TYPE: number = 2;
const UTF16_CHAR_MAX: number = 0xffff;

export interface LineEmailE2eeMaterial {
  publicKey: Uint8Array;
  privateKey: Uint8Array;
  secret: Uint8Array;
}

export interface LineEmailLoginCrypto {
  createPin(): string;

  createIdentity(key: LineEmailRsaKey, email: string, password: string): Promise<string>;

  createE2ee(pin: string): Promise<LineEmailE2eeMaterial>;

  confirmE2ee(privateKey: Uint8Array, peerPublic: Uint8Array,
    encryptedKeyChain: Uint8Array): Promise<Uint8Array>;
}

function invalid(): MiniAppError {
  return new MiniAppError(LineErrorCode.EMAIL_CRYPTO_FAILED, 'LINE 邮箱认证加密失败');
}

function sha256(...pieces: Uint8Array[]): Uint8Array {
  const digest = cryptoFramework.createMd('SHA256');
  pieces.forEach((piece: Uint8Array): void => digest.updateSync({ data: piece }));
  return digest.digestSync().data;
}

function utf8(value: string): Uint8Array {
  return new util.TextEncoder().encodeInto(value);
}

function xorHalves(bytes: Uint8Array): Uint8Array {
  if (bytes.length !== SHA256_DIGEST_BYTES) {
    throw invalid();
  }
  const output = new Uint8Array(AES_BLOCK_BYTES);
  for (let i: number = 0; i < AES_BLOCK_BYTES; i++) {
    output[i] = bytes[i] ^ bytes[AES_BLOCK_BYTES + i];
  }
  return output;
}

function littleEndianInt(bytes: Uint8Array): bigint {
  let result: bigint = 0n;
  for (let i: number = bytes.length - 1; i >= 0; i--) {
    result = (result << 8n) | BigInt(bytes[i]);
  }
  return result;
}

function bigEndianInt(bytes: Uint8Array): bigint {
  let result: bigint = 0n;
  for (let i: number = 0; i < bytes.length; i++) {
    result = (result << 8n) | BigInt(bytes[i]);
  }
  return result;
}

function hexInt(value: string): bigint {
  if (!value || !/^[0-9a-fA-F]+$/.test(value)) {
    throw invalid();
  }
  try {
    return BigInt('0x' + value);
  } catch (_) {
    throw invalid();
  }
}

function modPow(base: bigint, exponent: bigint, modulus: bigint): bigint {
  let result: bigint = 1n;
  let factor: bigint = base % modulus;
  let power: bigint = exponent;
  while (power > 0n) {
    if ((power & 1n) !== 0n) {
      result = (result * factor) % modulus;
    }
    factor = (factor * factor) % modulus;
    power >>= 1n;
  }
  return result;
}

async function aes(keyBytes: Uint8Array, input: Uint8Array, decrypt: boolean,
  cbcIv?: Uint8Array): Promise<Uint8Array> {
  const key = await cryptoFramework.createSymKeyGenerator('AES256').convertKey({ data: keyBytes });
  try {
    const cipher = cryptoFramework.createCipher(cbcIv ? 'AES256|CBC|PKCS7' : 'AES256|ECB|NoPadding');
    const params: cryptoFramework.IvParamsSpec | null = cbcIv ?
      { algName: 'IvParamsSpec', iv: { data: cbcIv } } : null;
    await cipher.init(decrypt ? cryptoFramework.CryptoMode.DECRYPT_MODE :
      cryptoFramework.CryptoMode.ENCRYPT_MODE, key, params);
    return (await cipher.doFinal({ data: input })).data;
  } finally {
    key.clearMem();
  }
}

/** APK 26.15.1 的登录前 RSA 与 PIN/E2EE 运算；账号密钥链明文不向上层交付。 */
export class LineNativeEmailLoginCrypto implements LineEmailLoginCrypto {
  createPin(): string {
    const upperBound: number = Math.floor(PIN_RANDOM_SPACE / PIN_SPACE) * PIN_SPACE;
    while (true) {
      const random: Uint8Array = cryptoFramework.createRandom().generateRandomSync(PIN_RANDOM_BYTES).data;
      const value: number = Number(bigEndianInt(random));
      if (value < upperBound) {
        return (value % PIN_SPACE).toString().padStart(PIN_DIGITS, '0');
      }
    }
  }

  async createIdentity(key: LineEmailRsaKey, email: string, password: string): Promise<string> {
    if (!key.keynm || !key.sessionKey || !email || !password ||
      key.sessionKey.length > UTF16_CHAR_MAX || email.length > UTF16_CHAR_MAX ||
      password.length > UTF16_CHAR_MAX) {
      throw invalid();
    }
    const modulus: bigint = hexInt(key.nvalue);
    const exponent: bigint = hexInt(key.evalue);
    if (modulus <= 0n || exponent <= 0n) {
      throw invalid();
    }
    const size: number = Math.ceil(modulus.toString(2).length / 8);
    // ab5/j adds one UTF-16 length character before each input; ab5/k casts each char to one byte.
    const identity: string = String.fromCharCode(key.sessionKey.length) + key.sessionKey +
      String.fromCharCode(email.length) + email +
      String.fromCharCode(password.length) + password;
    if (identity.length + RSA_PADDING_OVERHEAD > size) {
      throw invalid();
    }
    const block = new Uint8Array(size);
    try {
      block[1] = RSA_BLOCK_TYPE;
      const payloadStart: number = size - identity.length;
      for (let i: number = 0; i < identity.length; i++) {
        block[payloadStart + i] = identity.charCodeAt(i) & 255;
      }
      // PKCS#1 v1.5 type 2: 00 02 || nonzero random padding || 00 || payload.
      const random = cryptoFramework.createRandom();
      for (let i: number = 2; i < payloadStart - 1; i++) {
        let byte: number = 0;
        while (byte === 0) {
          byte = random.generateRandomSync(1).data[0];
        }
        block[i] = byte;
      }
      const encrypted: bigint = modPow(bigEndianInt(block), exponent, modulus);
      let hex: string = encrypted.toString(16);
      if (hex.length % 2 === 1) {
        hex = '0' + hex;
      }
      return hex;
    } finally {
      block.fill(0);
    }
  }

  async createE2ee(pin: string): Promise<LineEmailE2eeMaterial> {
    if (pin.length !== PIN_DIGITS || !/^\d+$/.test(pin)) {
      throw invalid();
    }
    try {
      // Each email attempt owns a fresh X25519 pair; QR-process cache must not be shared.
      const pair = await cryptoFramework.createAsyKeyGenerator('X25519').generateKeyPair();
      let privateKey: Uint8Array | undefined;
      let material: LineEmailE2eeMaterial | undefined;
      try {
        const publicKey = lineX25519Bytes(pair.pubKey.getAsyKeySpec(cryptoFramework.AsyKeySpecItem.X25519_PK_BN));
        privateKey = lineX25519Bytes(pair.priKey.getAsyKeySpec(cryptoFramework.AsyKeySpecItem.X25519_SK_BN));
        const pinHash: Uint8Array = sha256(utf8(pin));
        let secret: Uint8Array;
        try {
          secret = await aes(pinHash, publicKey, false);
        } finally {
          pinHash.fill(0);
        }
        material = { publicKey, privateKey, secret };
      } finally {
        try {
          pair.priKey.clearMem();
        } catch (error) {
          material?.privateKey.fill(0);
          material?.secret.fill(0);
          throw MiniAppError.from(error as Object, LineErrorCode.EMAIL_CRYPTO_FAILED, 'LINE E2EE 私钥释放失败');
        } finally {
          if (!material) {
            privateKey?.fill(0);
          }
        }
      }
      return material!;
    } catch (error) {
      throw MiniAppError.from(error as Object, LineErrorCode.EMAIL_CRYPTO_FAILED, 'LINE E2EE 初始化失败');
    }
  }

  async confirmE2ee(privateKey: Uint8Array, peerPublic: Uint8Array,
    encryptedKeyChain: Uint8Array): Promise<Uint8Array> {
    if (privateKey.length !== LINE_X25519_KEY_BYTES || peerPublic.length !== LINE_X25519_KEY_BYTES ||
      encryptedKeyChain.length === 0 || encryptedKeyChain.length % AES_BLOCK_BYTES !== 0) {
      throw invalid();
    }
    try {
      const ownSpec: cryptoFramework.X25519PriKeySpec = {
        algName: 'X25519', specType: cryptoFramework.AsyKeySpecType.PRIVATE_KEY_SPEC,
        sk: littleEndianInt(privateKey)
      };
      const peerSpec: cryptoFramework.X25519PubKeySpec = {
        algName: 'X25519', specType: cryptoFramework.AsyKeySpecType.PUBLIC_KEY_SPEC,
        pk: littleEndianInt(peerPublic)
      };
      const privateObject = await cryptoFramework.createAsyKeyGeneratorBySpec(ownSpec).generatePriKey();
      let shared: Uint8Array;
      try {
        const publicObject = await cryptoFramework.createAsyKeyGeneratorBySpec(peerSpec).generatePubKey();
        shared = (await cryptoFramework.createKeyAgreement('X25519')
          .generateSecret(privateObject, publicObject)).data;
      } finally {
        privateObject.clearMem();
      }
      const key: Uint8Array = sha256(shared, utf8('Key'));
      try {
        const iv: Uint8Array = xorHalves(sha256(shared, utf8('IV')));
        const proofInput: Uint8Array = xorHalves(sha256(encryptedKeyChain));
        const proof: Uint8Array = await aes(key, proofInput, false);
        const clearChain: Uint8Array = await aes(key, encryptedKeyChain, true, iv);
        clearChain.fill(0);
        return proof;
      } finally {
        shared.fill(0);
        key.fill(0);
      }
    } catch (error) {
      throw MiniAppError.from(error as Object, LineErrorCode.EMAIL_CRYPTO_FAILED, 'LINE E2EE 验证失败');
    }
  }
}
