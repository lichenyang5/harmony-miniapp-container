import { LineErrorCode } from '../LineErrorCode';
import { MiniAppError } from '../../../core/MiniAppError';
import { lineRegistrationCheckCost, lineRegistrationHmacSha256, lineRegistrationScrypt } from './LineRegistrationScrypt';

export interface LinePasswordHashParameters {
  hmacKey: string;
  salt: string;
  nrp: string;
  dkLen: number;
}

export interface LinePasswordRule {
  patterns: string[];
  message: string;
}

function invalid(): MiniAppError {
  return new MiniAppError(LineErrorCode.REGISTRATION_CRYPTO_FAILED, 'LINE registration password hashing failed');
}

function unsupported(): MiniAppError {
  return new MiniAppError(LineErrorCode.REGISTRATION_RULE_UNSUPPORTED, 'Unsupported LINE registration password rule');
}

function base64Encode(bytes: Uint8Array): string {
  const alphabet: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let result: string = '';
  for (let i: number = 0; i < bytes.length; i += 3) {
    const value: number = (bytes[i] << 16) | ((bytes[i + 1] || 0) << 8) | (bytes[i + 2] || 0);
    result += alphabet[(value >>> 18) & 63] + alphabet[(value >>> 12) & 63] +
      (i + 1 < bytes.length ? alphabet[(value >>> 6) & 63] : '=') +
      (i + 2 < bytes.length ? alphabet[value & 63] : '=');
  }
  return result;
}

function base64Decode(value: string): Uint8Array {
  // Only canonical RFC 4648 input, with optional omitted padding. No whitespace or ignored garbage.
  if (typeof value !== 'string' || value.length > 8192 ||
    !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}(?:==)?|[A-Za-z0-9+/]{3}=?)?$/.test(value)) {
    throw invalid();
  }
  const alphabet: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const data: string = value.replace(/=+$/, '');
  const result = new Uint8Array(Math.floor(data.length * 6 / 8));
  let bits: number = 0;
  let count: number = 0;
  let offset: number = 0;
  for (let i: number = 0; i < data.length; i++) {
    bits = (bits << 6) | alphabet.indexOf(data[i]);
    count += 6;
    if (count >= 8) {
      count -= 8;
      result[offset++] = bits >>> count;
    }
  }
  if (base64Encode(result).replace(/=+$/, '') !== data) {
    result.fill(0);
    throw invalid();
  }
  return result;
}

/** Java UTF-8 replaces malformed UTF-16 with '?', rather than TextEncoder's U+FFFD. */
function passwordBytes(value: string): Uint8Array {
  const output: number[] = [];
  for (let i: number = 0; i < value.length; i++) {
    let point: number = value.charCodeAt(i);
    if (point >= 0xd800 && point <= 0xdbff) {
      const next: number = value.charCodeAt(i + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        point = 0x10000 + ((point - 0xd800) << 10) + next - 0xdc00;
        i++;
      } else {
        point = 0x3f;
      }
    } else if (point >= 0xdc00 && point <= 0xdfff) {
      point = 0x3f;
    }
    if (point < 0x80) {
      output.push(point);
    } else if (point < 0x800) {
      output.push(0xc0 | (point >>> 6), 0x80 | (point & 63));
    } else if (point < 0x10000) {
      output.push(0xe0 | (point >>> 12), 0x80 | ((point >>> 6) & 63), 0x80 | (point & 63));
    } else {
      output.push(0xf0 | (point >>> 18), 0x80 | ((point >>> 12) & 63),
        0x80 | ((point >>> 6) & 63), 0x80 | (point & 63));
    }
  }
  const result = new Uint8Array(output);
  output.fill(0);
  return result;
}

/** Java syntax compatibility pass; checkPatternComplexity further limits evaluation
 * to a bounded flat subset with leading lookaheads. Fail closed for Java extensions,
 * backreferences, nested/intersected classes and possessive quantifiers. */
function compatiblePattern(pattern: string): string {
  if (typeof pattern !== 'string' || pattern.length > 1024 || pattern.includes('&&') ||
    /\(\?(?![:=!])/.test(pattern) || /(?:[+*?]|\})\+/.test(pattern)) {
    throw unsupported();
  }
  let result: string = '';
  let inClass: boolean = false;
  for (let i: number = 0; i < pattern.length; i++) {
    const character: string = pattern[i];
    if (character === '\\') {
      const escaped: string = pattern[++i];
      if (!escaped || /[A-Za-z0-9]/.test(escaped) && !'dDwWfnrtxu'.includes(escaped) ||
        escaped === 'u' && pattern[i + 1] === '{') {
        // Java's \s differs from ECMAScript whitespace; support it outside classes explicitly.
        if (!inClass && (escaped === 's' || escaped === 'S')) {
          result += escaped === 's' ? '[ \\t\\n\\x0B\\f\\r]' : '[^ \\t\\n\\x0B\\f\\r]';
          continue;
        }
        throw unsupported();
      }
      result += '\\' + escaped;
    } else if (character === '[') {
      if (inClass) {
        throw unsupported();
      }
      inClass = true;
      result += character;
    } else if (character === ']') {
      if (pattern[i - 1] === '[' || pattern[i - 1] === '^' && pattern[i - 2] === '[') {
        throw unsupported();
      }
      inClass = false;
      result += character;
    } else if (character === '.' && !inClass) {
      result += '[^\\n\\r\\u0085\\u2028\\u2029]';
    } else {
      result += character;
    }
  }
  if (inClass) {
    throw unsupported();
  }
  return result;
}

/** Bounded backtracking subset: flat alternatives with at most one repeated atom
 * per branch. Groups are limited to leading, non-nested lookaheads, checked once
 * at the initial position. Each lookahead body has the same one-repeat budget.
 * This intentionally rejects even safe grouped/adjacent repetitions rather than
 * trying to prove overlap or implement a general Java Pattern complexity analyzer. */
function checkLinearPattern(pattern: string, start: number, end: number, allowAlternatives: boolean): void {
  let inClass: boolean = false;
  let repetitions: number = 0;
  for (let i: number = start; i < end; i++) {
    const character: string = pattern[i];
    if (character === '\\') {
      i++;
      continue;
    }
    if (character === '[') {
      inClass = true;
    } else if (character === ']') {
      inClass = false;
    } else if (!inClass) {
      if (character === '(' || character === ')') {
        throw unsupported();
      }
      if (character === '|') {
        if (!allowAlternatives) {
          throw unsupported();
        }
        repetitions = 0;
      } else if (character === '*' || character === '+' || character === '?' || character === '{') {
        repetitions++;
        if (repetitions > 1) {
          throw unsupported();
        }
        if (character === '{') {
          const close: number = pattern.indexOf('}', i + 1);
          const bounds: string = pattern.substring(i + 1, close);
          if (close < 0 || close >= end || !/^\d+(?:,\d*)?$/.test(bounds)) {
            throw unsupported();
          }
          const limits: string[] = bounds.split(',');
          if (Number(limits[0]) > 4096 || limits.length > 1 && limits[1] !== '' && Number(limits[1]) > 4096) {
            throw unsupported();
          }
          i = close;
        }
        if (pattern[i + 1] === '?') {
          i++;
        }
      }
    }
  }
}

function checkPatternComplexity(pattern: string): void {
  let start: number = pattern[0] === '^' ? 1 : 0;
  while (pattern.substring(start, start + 3) === '(?=' || pattern.substring(start, start + 3) === '(?!') {
    const body: number = start + 3;
    let close: number = body;
    let inClass: boolean = false;
    for (; close < pattern.length; close++) {
      const character: string = pattern[close];
      if (character === '\\') {
        close++;
      } else if (character === '[') {
        inClass = true;
      } else if (character === ']') {
        inClass = false;
      } else if (!inClass && character === '(') {
        throw unsupported();
      } else if (!inClass && character === ')') {
        break;
      }
    }
    if (close >= pattern.length) {
      throw unsupported();
    }
    checkLinearPattern(pattern, body, close, false);
    start = close + 1;
  }
  checkLinearPattern(pattern, start, pattern.length, true);
}

function validateRules(password: string, rules: LinePasswordRule[]): void {
  if (!Array.isArray(rules) || rules.length > 32) {
    throw unsupported();
  }
  let valid: boolean = true;
  for (let i: number = 0; i < rules.length; i++) {
    const rule: LinePasswordRule = rules[i];
    if (!rule || !Array.isArray(rule.patterns) || rule.patterns.length > 16 || typeof rule.message !== 'string') {
      throw unsupported();
    }
    for (let j: number = 0; j < rule.patterns.length; j++) {
      const pattern: string = compatiblePattern(rule.patterns[j]);
      checkPatternComplexity(rule.patterns[j]);
      let expression: RegExp;
      try {
        // End assertion forbids ECMAScript '$' accepting a position before a trailing newline.
        expression = new RegExp('^(?:' + pattern + ')$(?![\\s\\S])', 'u');
      } catch (_) {
        throw unsupported();
      }
      if (!expression.test(password)) {
        valid = false;
      }
    }
  }
  if (!valid) {
    // Server rule messages are private data, not user-facing SDK diagnostics.
    throw new MiniAppError(LineErrorCode.REGISTRATION_PASSWORD_INVALID, 'LINE registration password does not meet rules');
  }
}

/** Pure internal entry point used only by the worker and real-source vector tests. */
export function lineRegistrationHash(password: string, parameters: LinePasswordHashParameters,
  rules: LinePasswordRule[]): string {
  if (typeof password !== 'string' || password.length > 4096 || !parameters ||
    typeof parameters.nrp !== 'string' || !/^[0-9a-fA-F]{1,8}$/.test(parameters.nrp)) {
    throw invalid();
  }
  const value: number = Number.parseInt(parameters.nrp, 16);
  const exponent: number = value >>> 16;
  // No Java shift-count wrapping or int overflow; reject instead of weakening the cost.
  if (value > 0x7fffffff || exponent < 1 || exponent > 30) {
    throw invalid();
  }
  const n: number = 2**exponent;
  const r: number = (value >>> 8) & 255;
  const p: number = value & 255;
  lineRegistrationCheckCost(n, r, p, parameters.dkLen);
  validateRules(password, rules);
  const key: Uint8Array = base64Decode(parameters.hmacKey);
  let salt: Uint8Array | undefined;
  let bytes: Uint8Array | undefined;
  let secret: Uint8Array | undefined;
  let derived: Uint8Array | undefined;
  try {
    if (key.length === 0) {
      throw invalid();
    }
    salt = base64Decode(parameters.salt);
    bytes = passwordBytes(password);
    secret = lineRegistrationHmacSha256(key, bytes);
    derived = lineRegistrationScrypt(secret, salt, n, r, p, parameters.dkLen);
    return '$s0$' + parameters.nrp + '$' + parameters.salt + '$' + base64Encode(derived);
  } finally {
    key.fill(0);
    salt?.fill(0);
    bytes?.fill(0);
    secret?.fill(0);
    derived?.fill(0);
  }
}
