import { LineErrorCode } from '../LineErrorCode';
import { MiniAppError } from '../../../core/MiniAppError';
import { lineRegistrationHash, LinePasswordHashParameters, LinePasswordRule } from './LineRegistrationPassword';

/** Only primitives cross taskpool's API 15 serialization boundary. No closure or UI context. */
@Concurrent
export function lineRegistrationHashTask(password: string, hmacKey: string, salt: string,
  nrp: string, dkLen: number, rulesJson: string): string[] {
  try {
    const parameters: LinePasswordHashParameters = { hmacKey, salt, nrp, dkLen };
    const rules: LinePasswordRule[] = JSON.parse(rulesJson) as LinePasswordRule[];
    return [lineRegistrationHash(password, parameters, rules), ''];
  } catch (error) {
    return ['', error instanceof MiniAppError ? error.code : LineErrorCode.REGISTRATION_CRYPTO_FAILED];
  }
}
