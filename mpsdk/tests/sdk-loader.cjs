const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const ts = require(process.env.TYPESCRIPT_PATH || 'typescript');
const crypto = require('node:crypto');
global.KeyboardAvoidMode = { DEFAULT: 0, NONE: 1 };

// Real SDK and test sources; only platform dependencies are substituted.
function createLoader(
  hypium = {},
  scanBarcode = {},
  appWindow = {
    async getLastWindow() {
      return { isWindowShowing: () => true };
    }
  },
  contact = {},
  canUse = () => true,
  buildProfile = { DEBUG: false },
  platformOverrides = {}
) {
  const cache = new Map();
  const prefStores = new Map();
  const preferencesStub = {
    getPreferences: async (_context, options) => {
      const name = options && options.name ? options.name : 'default';
      if (!prefStores.has(name)) {
        const values = new Map();
        prefStores.set(name, {
          get: async (key, defaultValue) => (values.has(key) ? values.get(key) : defaultValue),
          put: async (key, value) => {
            values.set(key, value);
          },
          flush: async () => {},
          delete: async (key) => {
            values.delete(key);
          }
        });
      }
      return prefStores.get(name);
    }
  };
  const kits = {
    '@kit.ArkWeb': { webview: { WebviewController: class {} } },
    '@kit.LocalizationKit': {},
    '@kit.ArkTS': {
      util: {
        generateRandomUUID: () => crypto.randomUUID(),
        TextEncoder: class { encodeInto(input) { return new TextEncoder().encode(input); } },
        Base64Helper: class { encodeToStringSync(bytes) { return Buffer.from(bytes).toString('base64'); } },
        TextDecoder: {
          create: (encoding, options) => ({
            decodeToString: (bytes) => new TextDecoder(encoding, options).decode(bytes)
          })
        }
      }
    },
    '@ohos/hypium': hypium,
    '@kit.CryptoArchitectureKit': {
      cryptoFramework: {
        createMd(algorithm) {
          const hash = crypto.createHash(algorithm);
          return { updateSync: blob => { hash.update(blob.data); }, digestSync: () => ({ data: new Uint8Array(hash.digest()) }) };
        }
      }
    },
    '@kit.ScanKit': { scanBarcode, scanCore: { ScanType: { ALL: 0, QR_CODE: 11 } } },
    '@kit.ContactsKit': { contact },
    '@kit.PerformanceAnalysisKit': { hilog: { debug() {}, info() {}, warn() {}, error() {} } },
    '@kit.AbilityKit': {
      UIAbility: class UIAbility {},
      AbilityLifecycleCallback: class AbilityLifecycleCallback {},
      abilityAccessCtrl: { createAtManager: () => ({}), GrantStatus: { PERMISSION_GRANTED: 0, PERMISSION_DENIED: -1 } }
    },
    '@kit.BasicServicesKit': { deviceInfo: { sdkApiVersion: 22 } },
    '@ohos.deviceInfo': { default: { sdkApiVersion: 22, brand: 'test-brand', productModel: 'test-model' } },
    '@kit.CoreFileKit': {},
    '@kit.ArkData': { preferences: preferencesStub },
    '@kit.NetworkKit': {},
    '@kit.ArkUI': { window: appWindow, promptAction: {} },
    '@kit.CameraKit': { camera: {} },
    '@kit.TelephonyKit': { call: {} },
    '@kit.SensorServiceKit': {
      vibrator: {},
      sensor: {
        SensorId: { ACCELEROMETER: 1, GYROSCOPE: 2, ORIENTATION: 256 },
        on() {},
        off() {}
      }
    }
  };
  for (const [name, override] of Object.entries(platformOverrides)) {
    kits[name] = { ...kits[name], ...override };
  }
  function load(file) {
    if (file.endsWith('BuildProfile.ets')) return { default: buildProfile };
    // Dialog controller uses real source; only the ArkUI builder is substituted.
    if (file.endsWith('LineRegistrationView.ets')) return { lineRegistrationBuilder: { builder() {} } };
    if (file.endsWith('LineRegistrationWebView.ets')) return { lineRegistrationWebBuilder: { builder() {} } };
    if (file.endsWith('LineDialogView.ets')) return { lineDialogBuilder: { builder() {} } };
    if (file.endsWith('LineBrowserView.ets')) return { lineBrowserBuilder: { builder() {} } };
    if (file.endsWith('LineScanResultView.ets')) return { lineScanResultBuilder: { builder() {} } };
    if (file.endsWith('LineConsentView.ets')) return { lineConsentBuilder: { builder() {} } };
    if (file.endsWith('LineLoginView.ets')) return {
      lineLoginBuilder: { builder() {} },
      LineLoginViewModel: class {
        update(state) { this.state = state; }
        clearSecrets() {}
      }
    };
    // ArkUI sheet cannot render in Node; substitute the controller so handler chains stay loadable.
    if (file.endsWith('PersonalCardSheet.ets')) {
      if (!cache.has(file)) {
        cache.set(file, {
          exports: {
            PersonalCardSheetTools: class PersonalCardSheetTools {
              constructor() {}
              async open() {
                throw new Error('Personal card sheet is unavailable in Node regression');
              }
              dispose() {}
            }
          }
        });
      }
      return cache.get(file).exports;
    }
    if (!fs.existsSync(file)) file = file.replace(/\.ets$/, '.ts');
    if (cache.has(file)) return cache.get(file).exports;
    const module = { exports: {} };
    cache.set(file, module);
    const js = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
      fileName: file.replace(/\.ets$/, '.ts'),
      compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS, experimentalDecorators: true }
    }).outputText;
    let evaluate;
    try {
      evaluate = new Function('require', 'module', 'exports', 'getContext', 'canIUse', '$r', 'ObservedV2', 'Trace', js);
    } catch (error) {
      error.message = `${file}: ${error.message}`;
      throw error;
    }
    evaluate(
      (id) => {
        if (kits[id]) return kits[id];
        assert.ok(id.startsWith('.'), `Unexpected platform dependency: ${id}`);
        return load(path.resolve(path.dirname(file), id + '.ets'));
      },
      module,
      module.exports,
      () => ({ applicationInfo: { accessTokenId: 1 } }),
      canUse,
      (name, ...params) => ({ name, params }),
      value => value,
      () => {}
    );
    return module.exports;
  }
  return (relative) => load(path.resolve(__dirname, '../src', relative + '.ets'));
}

module.exports = { createLoader };
