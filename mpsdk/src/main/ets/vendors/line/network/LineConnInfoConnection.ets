import { LineRpcTimeout } from './LineRpcConstants';
import { LineErrorCode } from '../LineErrorCode';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { http } from '@kit.NetworkKit';
import { url, util } from '@kit.ArkTS';
import { MiniAppError } from '../../../core/MiniAppError';
import { LineClientRole, LineHttpConnection, LineService } from './LineTransport';

// conn-info 不可用时的本地缓存期限，不是服务端 Token 有效期。
const CONN_INFO_CACHE_MS: number = 600000;
const APK_VERSION: string = '26.15.1';
const DEFAULT_LEGY: string = 'https://legy.line-apps.com';
const CONN_INFO_HOSTS: string[] = ['cix.line-apps.com', 'ci.line-apps.com'];
// APK 26.15.1 的 conn-info 请求校验常量；不属于账号 Token。
const CONN_INFO_SALT: Uint8Array = Uint8Array.from([
  0x4c, 0x60, 0x5e, 0xff, 0xdf, 0x3d, 0xfc, 0x9f,
  0x21, 0x7d, 0x48, 0x17, 0x40, 0x20, 0x56, 0x91,
  0x80, 0xdc, 0x23, 0x38, 0xa5, 0x77, 0x2a, 0x80,
  0xed, 0x0a, 0xaa, 0x01, 0xbc, 0xd0, 0xa0, 0x8f
]);

/** APK 兼容标识中与设备有关的值；由实际宿主设备/既有兼容 UA 提供。 */
export interface LineConnInfoProfile {
  androidRelease: string;
  locale: string;
  localeCountry: string;
  simCountry?: string;
  profileCountry?: string;
  carrier?: string;
}

export interface LineConnInfoFetcher {
  get(address: string): Promise<string>;
}

interface ConnInfoServer {
  host: string;
  port: number;
  priority: number;
  secure: string;
}

interface ConnInfoLegy {
  wifi?: ConnInfoServer[];
  mobile?: ConnInfoServer[];
}

interface ConnInfoServers {
  legy?: ConnInfoLegy;
}

interface ConnInfoPayload {
  servers?: ConnInfoServers;
}

interface ConnInfoResponse {
  time?: number;
  expire?: number;
  payload?: ConnInfoPayload;
}

interface LineEndpointChoice {
  endpoint: string;
  expiresAt: number;
}

class LineConnInfoHttpFetcher implements LineConnInfoFetcher {
  async get(address: string): Promise<string> {
    const client = http.createHttp();
    try {
      const response = await client.request(address, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        readTimeout: LineRpcTimeout.CONN_INFO_MS,
        connectTimeout: LineRpcTimeout.CONN_INFO_MS,
        usingCache: false,
        usingProtocol: http.HttpProtocol.HTTP2
      });
      if (response.responseCode !== 200 || typeof response.result !== 'string') {
        throw new MiniAppError(LineErrorCode.CONN_INFO_HTTP_FAILED, 'LINE 连接信息请求失败');
      }
      return response.result;
    } finally {
      client.destroy();
    }
  }
}

/** 仅还原 SDK 所需的 LEGY 发现；默认地址来自 APK 内置 conn-info。 */
export class LineConnInfoConnection implements LineHttpConnection {
  readonly applicationHeader: string;
  readonly clientHeaders: Record<string, string>;
  private readonly profile: LineConnInfoProfile;
  private readonly fetcher: LineConnInfoFetcher;
  private cachedEndpoint: string = DEFAULT_LEGY;
  private expiresAt: number = 0;
  private pending?: Promise<string>;

  constructor(profile: LineConnInfoProfile, fetcher?: LineConnInfoFetcher) {
    if (!profile.androidRelease || !profile.locale || !profile.localeCountry) {
      throw new MiniAppError(LineErrorCode.CONNECTION_CONFIG_REQUIRED, 'LINE 客户端标识不完整');
    }
    this.profile = profile;
    this.fetcher = fetcher ?? new LineConnInfoHttpFetcher();
    this.applicationHeader = this.applicationHeaderFor(LineClientRole.SECONDARY);
    this.clientHeaders = { 'User-Agent': `Line/${APK_VERSION}`, 'X-LAL': profile.locale };
  }

  applicationHeaderFor(role: LineClientRole): string {
    if (role !== LineClientRole.PRIMARY && role !== LineClientRole.SECONDARY) {
      throw new MiniAppError(LineErrorCode.CONNECTION_CONFIG_REQUIRED, 'LINE 客户端角色无效');
    }
    const client: string = role === LineClientRole.PRIMARY ? 'ANDROID' : 'ANDROIDSECONDARY';
    const release: string = this.profile.androidRelease.replace(/\t/g, '');
    if (!release) {
      throw new MiniAppError(LineErrorCode.CONNECTION_CONFIG_REQUIRED, 'LINE 客户端标识不完整');
    }
    return `${client}\t${APK_VERSION}\tAndroid OS\t${release}`;
  }

  async endpointFor(_service: LineService): Promise<string> {
    if (Date.now() < this.expiresAt) {
      return this.cachedEndpoint;
    }
    if (!this.pending) {
      this.pending = this.refresh().finally((): void => {
        this.pending = undefined;
      });
    }
    return this.pending;
  }

  private signature(time: string, regions: string, carrier: string): string {
    const encoder = new util.TextEncoder();
    const digest = cryptoFramework.createMd('MD5');
    digest.updateSync({ data: encoder.encodeInto('Android_OS' + APK_VERSION + regions + time + carrier) });
    digest.updateSync({ data: CONN_INFO_SALT });
    return Array.from(digest.digestSync().data).map((byte: number): string =>
    byte.toString(16).padStart(2, '0')).join('');
  }

  private requestUrl(host: string): string {
    const time: string = Math.floor(Date.now() / 1000).toString();
    const regions: string = [this.profile.simCountry ?? '', this.profile.profileCountry ?? '',
      this.profile.localeCountry].join('-');
    const carrier: string = this.profile.carrier ?? '';
    const target = new url.URL(`https://${host}/R4`);
    target.params.set('type', 'Android_OS');
    target.params.set('version', APK_VERSION);
    target.params.set('regions', regions);
    target.params.set('carrier', carrier);
    target.params.set('time', time);
    target.params.set('key', this.signature(time, regions, carrier));
    return target.toString();
  }

  private parse(text: string): LineEndpointChoice {
    let parsed: ConnInfoResponse;
    try {
      parsed = JSON.parse(text) as ConnInfoResponse;
    } catch (_) {
      throw new MiniAppError(LineErrorCode.CONN_INFO_INVALID, 'LINE 连接信息格式无效');
    }
    const servers: ConnInfoServer[] | undefined = parsed.payload?.servers?.legy?.wifi ??
      parsed.payload?.servers?.legy?.mobile;
    if (!Array.isArray(servers) || servers.length === 0) {
      throw new MiniAppError(LineErrorCode.CONN_INFO_INVALID, 'LINE 连接信息缺少 LEGY 服务');
    }
    const eligible: ConnInfoServer[] = servers.filter((server: ConnInfoServer): boolean =>
    server !== null && typeof server === 'object' && !Array.isArray(server) &&
      typeof server.host === 'string' && /^[a-z0-9.-]+$/i.test(server.host) &&
      server.secure === 'tls' && server.port === 443 && Number.isInteger(server.priority));
    eligible.sort((a: ConnInfoServer, b: ConnInfoServer): number => a.priority - b.priority);
    if (eligible.length === 0) {
      throw new MiniAppError(LineErrorCode.CONN_INFO_INVALID, 'LINE 连接信息缺少安全端点');
    }
    const expiry: number = typeof parsed.time === 'number' && typeof parsed.expire === 'number' ?
      (parsed.time + parsed.expire) * 1000 : Date.now() + CONN_INFO_CACHE_MS;
    return { endpoint: `https://${eligible[0].host}`, expiresAt: expiry };
  }

  private async refresh(): Promise<string> {
    for (const host of CONN_INFO_HOSTS) {
      try {
        const result = this.parse(await this.fetcher.get(this.requestUrl(host)));
        this.cachedEndpoint = result.endpoint;
        this.expiresAt = result.expiresAt;
        return this.cachedEndpoint;
      } catch (_) { /* 下一个 APK 候选；全部失败时使用内置默认 LEGY。 */
      }
    }
    this.expiresAt = Date.now() + CONN_INFO_CACHE_MS;
    return this.cachedEndpoint;
  }
}
