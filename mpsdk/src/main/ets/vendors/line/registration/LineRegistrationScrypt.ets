import { LineErrorCode } from '../LineErrorCode';
import { MiniAppError } from '../../../core/MiniAppError';

/** Internal RFC 7914 primitives. Never exported by the HAR entry point. */
function invalid(): MiniAppError {
  return new MiniAppError(LineErrorCode.REGISTRATION_CRYPTO_FAILED, 'LINE registration password hashing failed');
}

function rotate(value: number, bits: number): number {
  return (value >>> bits) | (value << (32 - bits));
}

function sha256(input: Uint8Array): Uint8Array {
  const constants: number[] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ];
  const state = new Uint32Array([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]);
  const padded = new Uint8Array(Math.ceil((input.length + 9) / 64) * 64);
  const words = new Uint32Array(64);
  const result = new Uint8Array(32);
  try {
    padded.set(input);
    padded[input.length] = 0x80;
    let bits: number = input.length * 8;
    for (let i: number = 0; i < 8; i++) {
      padded[padded.length - 1 - i] = bits % 256;
      bits = Math.floor(bits / 256);
    }
    for (let offset: number = 0; offset < padded.length; offset += 64) {
      for (let i: number = 0; i < 16; i++) {
        const at: number = offset + i * 4;
        words[i] = (padded[at] << 24) | (padded[at + 1] << 16) | (padded[at + 2] << 8) | padded[at + 3];
      }
      for (let i: number = 16; i < 64; i++) {
        const a: number = words[i - 15];
        const b: number = words[i - 2];
        words[i] = words[i - 16] + (rotate(a, 7) ^ rotate(a, 18) ^ (a >>> 3)) + words[i - 7] +
          (rotate(b, 17) ^ rotate(b, 19) ^ (b >>> 10));
      }
      let a: number = state[0];
      let b: number = state[1];
      let c: number = state[2];
      let d: number = state[3];
      let e: number = state[4];
      let f: number = state[5];
      let g: number = state[6];
      let h: number = state[7];
      for (let i: number = 0; i < 64; i++) {
        const t1: number = (h + (rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)) +
          ((e & f) ^ (~e & g)) + constants[i] + words[i]) | 0;
        const t2: number = ((rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)) +
          ((a & b) ^ (a & c) ^ (b & c))) | 0;
        h = g;
        g = f;
        f = e;
        e = (d + t1) | 0;
        d = c;
        c = b;
        b = a;
        a = (t1 + t2) | 0;
      }
      state[0] += a;
      state[1] += b;
      state[2] += c;
      state[3] += d;
      state[4] += e;
      state[5] += f;
      state[6] += g;
      state[7] += h;
    }
    for (let i: number = 0; i < 32; i++) {
      result[i] = state[i >>> 2] >>> (24 - (i % 4) * 8);
    }
    return result;
  } finally {
    padded.fill(0);
    words.fill(0);
    state.fill(0);
  }
}

export function lineRegistrationHmacSha256(key: Uint8Array, message: Uint8Array): Uint8Array {
  const normalized: Uint8Array = key.length > 64 ? sha256(key) : key.slice();
  const inner = new Uint8Array(64 + message.length);
  const outer = new Uint8Array(96);
  let digest: Uint8Array | undefined;
  try {
    for (let i: number = 0; i < 64; i++) {
      const byte: number = i < normalized.length ? normalized[i] : 0;
      inner[i] = byte ^ 0x36;
      outer[i] = byte ^ 0x5c;
    }
    inner.set(message, 64);
    digest = sha256(inner);
    outer.set(digest, 64);
    return sha256(outer);
  } finally {
    normalized.fill(0);
    inner.fill(0);
    outer.fill(0);
    digest?.fill(0);
  }
}

/** scrypt uses PBKDF2-HMAC-SHA256 with exactly one iteration at both ends. */
function pbkdf2(password: Uint8Array, salt: Uint8Array, length: number): Uint8Array {
  const input = new Uint8Array(salt.length + 4);
  const output = new Uint8Array(length);
  input.set(salt);
  try {
    for (let block: number = 1, offset: number = 0; offset < length; block++, offset += 32) {
      input[salt.length] = block >>> 24;
      input[salt.length + 1] = block >>> 16;
      input[salt.length + 2] = block >>> 8;
      input[salt.length + 3] = block;
      const digest: Uint8Array = lineRegistrationHmacSha256(password, input);
      output.set(digest.subarray(0, Math.min(32, length - offset)), offset);
      digest.fill(0);
    }
    return output;
  } finally {
    input.fill(0);
  }
}

function left(value: number, bits: number): number {
  return (value << bits) | (value >>> (32 - bits));
}

function salsa8(block: Uint32Array, scratch: Uint32Array): void {
  scratch.set(block);
  for (let i: number = 0; i < 8; i += 2) {
    scratch[4] ^= left(scratch[0] + scratch[12], 7);
    scratch[8] ^= left(scratch[4] + scratch[0], 9);
    scratch[12] ^= left(scratch[8] + scratch[4], 13);
    scratch[0] ^= left(scratch[12] + scratch[8], 18);
    scratch[9] ^= left(scratch[5] + scratch[1], 7);
    scratch[13] ^= left(scratch[9] + scratch[5], 9);
    scratch[1] ^= left(scratch[13] + scratch[9], 13);
    scratch[5] ^= left(scratch[1] + scratch[13], 18);
    scratch[14] ^= left(scratch[10] + scratch[6], 7);
    scratch[2] ^= left(scratch[14] + scratch[10], 9);
    scratch[6] ^= left(scratch[2] + scratch[14], 13);
    scratch[10] ^= left(scratch[6] + scratch[2], 18);
    scratch[3] ^= left(scratch[15] + scratch[11], 7);
    scratch[7] ^= left(scratch[3] + scratch[15], 9);
    scratch[11] ^= left(scratch[7] + scratch[3], 13);
    scratch[15] ^= left(scratch[11] + scratch[7], 18);
    scratch[1] ^= left(scratch[0] + scratch[3], 7);
    scratch[2] ^= left(scratch[1] + scratch[0], 9);
    scratch[3] ^= left(scratch[2] + scratch[1], 13);
    scratch[0] ^= left(scratch[3] + scratch[2], 18);
    scratch[6] ^= left(scratch[5] + scratch[4], 7);
    scratch[7] ^= left(scratch[6] + scratch[5], 9);
    scratch[4] ^= left(scratch[7] + scratch[6], 13);
    scratch[5] ^= left(scratch[4] + scratch[7], 18);
    scratch[11] ^= left(scratch[10] + scratch[9], 7);
    scratch[8] ^= left(scratch[11] + scratch[10], 9);
    scratch[9] ^= left(scratch[8] + scratch[11], 13);
    scratch[10] ^= left(scratch[9] + scratch[8], 18);
    scratch[12] ^= left(scratch[15] + scratch[14], 7);
    scratch[13] ^= left(scratch[12] + scratch[15], 9);
    scratch[14] ^= left(scratch[13] + scratch[12], 13);
    scratch[15] ^= left(scratch[14] + scratch[13], 18);
  }
  for (let i: number = 0; i < 16; i++) {
    block[i] += scratch[i];
  }
}

function blockMix(input: Uint32Array, output: Uint32Array, block: Uint32Array,
  scratch: Uint32Array, r: number): void {
  block.set(input.subarray(input.length - 16));
  for (let i: number = 0; i < 2 * r; i++) {
    for (let k: number = 0; k < 16; k++) {
      block[k] ^= input[i * 16 + k];
    }
    salsa8(block, scratch);
    const at: number = ((i >>> 1) + (i % 2) * r) * 16;
    output.set(block, at);
  }
}

/** Explicit resource policy, not parameter substitution: 64 MiB live typed-array workspace,
 * at most 2^22 N*r*p, and at most 1024 derived bytes. Costs above this fail closed. */
export function lineRegistrationCheckCost(n: number, r: number, p: number, length: number): void {
  if (!Number.isSafeInteger(n) || n <= 1 || n > 0x40000000 || (n & (n - 1)) !== 0 ||
    !Number.isSafeInteger(r) || r < 1 || r > 255 || !Number.isSafeInteger(p) || p < 1 || p > 255 ||
    (r === 1 && n >= 65536) || !Number.isSafeInteger(length) || length < 1 || length > 1024 ||
    128 * r * (n + 4 * p + 4) + 32768 > 64 * 1024 * 1024 || n * r * p > 2**22) {
    throw invalid();
  }
}

export function lineRegistrationScrypt(password: Uint8Array, salt: Uint8Array, n: number,
  r: number, p: number, length: number): Uint8Array {
  lineRegistrationCheckCost(n, r, p, length);
  const bytes: Uint8Array = pbkdf2(password, salt, p * 128 * r);
  const size: number = 32 * r;
  const memory = new Uint32Array(n * size);
  let x = new Uint32Array(size);
  let y = new Uint32Array(size);
  const block = new Uint32Array(16);
  const scratch = new Uint32Array(16);
  try {
    for (let lane: number = 0; lane < p; lane++) {
      const offset: number = lane * size * 4;
      for (let k: number = 0; k < size; k++) {
        const at: number = offset + k * 4;
        x[k] = bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16) | (bytes[at + 3] << 24);
      }
      for (let i: number = 0; i < n; i++) {
        memory.set(x, i * size);
        blockMix(x, y, block, scratch, r);
        const swap: Uint32Array = x;
        x = y;
        y = swap;
      }
      for (let i: number = 0; i < n; i++) {
        // N is a power of two <= 2^30, so Integerify's low word suffices.
        const index: number = (x[size - 16] & (n - 1)) * size;
        for (let k: number = 0; k < size; k++) {
          x[k] ^= memory[index + k];
        }
        blockMix(x, y, block, scratch, r);
        const swap: Uint32Array = x;
        x = y;
        y = swap;
      }
      for (let k: number = 0; k < size; k++) {
        for (let byte: number = 0; byte < 4; byte++) {
          bytes[offset + k * 4 + byte] = x[k] >>> (byte * 8);
        }
      }
    }
    return pbkdf2(password, bytes, length);
  } finally {
    bytes.fill(0);
    memory.fill(0);
    x.fill(0);
    y.fill(0);
    block.fill(0);
    scratch.fill(0);
  }
}
