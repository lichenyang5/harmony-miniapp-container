import { LineErrorCode } from '../LineErrorCode';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { deviceInfo } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { MiniAppError } from '../../../core/MiniAppError';

const DEVICE_PREFERENCES_NAME: string = 'atomicmpsdk.line.registration.device';
const INSTALLATION_ID_KEY: string = 'installationId.v1';

export interface LineRegistrationDeviceInfo {
  udid: string;
  deviceModel: string;
}

/** Compatibility difference: udid is a random, host-installation identifier, NOT
 * Android ID or its MD5. It survives SDK/ability instances and logout, but clearing
 * host app data or reinstalling creates a new value. Server acceptance is unverified. */
export class LineRegistrationDevice {
  static get(context: common.Context): LineRegistrationDeviceInfo {
    try {
      const store = preferences.getPreferencesSync(context.getApplicationContext(), { name: DEVICE_PREFERENCES_NAME });
      const stored = store.getSync(INSTALLATION_ID_KEY, '');
      if (typeof stored !== 'string' || stored !== '' && !/^[0-9a-f]{32}$/.test(stored)) {
        throw new Error('Invalid LINE registration installation identity');
      }
      let udid: string = stored;
      if (!udid) {
        const random: Uint8Array = cryptoFramework.createRandom().generateRandomSync(16).data;
        try {
          if (random.length !== 16) {
            throw new Error('Invalid LINE registration random source');
          }
          for (let i: number = 0; i < random.length; i++) {
            udid += random[i].toString(16).padStart(2, '0');
          }
          store.putSync(INSTALLATION_ID_KEY, udid);
        } finally {
          random.fill(0);
        }
      }
      // Also flush an existing value: a previous failed flush may have left it only in Preferences memory.
      store.flushSync();
      const deviceModel: string = deviceInfo.productModel;
      if (!deviceModel) {
        throw new Error('LINE registration device model unavailable');
      }
      return { udid, deviceModel };
    } catch (error) {
      throw MiniAppError.from(error as Object, LineErrorCode.REGISTRATION_DEVICE_FAILED,
        'LINE registration device information unavailable');
    }
  }
}
