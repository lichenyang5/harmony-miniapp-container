import { LineErrorCode } from '../LineErrorCode';
import { taskpool } from '@kit.ArkTS';
import { MiniAppError } from '../../../core/MiniAppError';
import { LinePasswordHashParameters, LinePasswordRule } from './LineRegistrationPassword';
import { lineRegistrationHashTask } from './LineRegistrationCryptoWorker';

export { LinePasswordHashParameters, LinePasswordRule } from './LineRegistrationPassword';

export interface LineRegistrationPasswordCrypto {
  hash(password: string, parameters: LinePasswordHashParameters, rules: LinePasswordRule[]): Promise<string>;
}

/** V2 always runs in taskpool; a rejected or unavailable worker never falls back to the UI thread. */
export class LineNativeRegistrationPasswordCrypto implements LineRegistrationPasswordCrypto {
  async hash(password: string, parameters: LinePasswordHashParameters, rules: LinePasswordRule[]): Promise<string> {
    try {
      const task = new taskpool.Task(lineRegistrationHashTask, password, parameters.hmacKey,
        parameters.salt, parameters.nrp, parameters.dkLen, JSON.stringify(rules));
      const result = await taskpool.execute(task) as string[];
      if (result.length !== 2 || !result[0] || result[1]) {
        throw new MiniAppError(result[1] || LineErrorCode.REGISTRATION_CRYPTO_FAILED,
          'LINE registration password hashing failed');
      }
      return result[0];
    } catch (error) {
      throw MiniAppError.from(error as Object, LineErrorCode.REGISTRATION_CRYPTO_FAILED,
        'LINE registration password hashing failed');
    }
  }
}
