import { LineAccountHeader, LineRpcPath, LineRpcTimeout } from './LineRpcConstants';
import { LineErrorCode } from '../LineErrorCode';
import { http } from '@kit.NetworkKit';
import { url } from '@kit.ArkTS';
import { MiniAppError } from '../../../core/MiniAppError';
import { LineAccessKind, LineClientRole, LineHttpConnection, LineService, LineTransport,
  LineTransportRequest } from './LineTransport';

export class LineHttpTransport implements LineTransport {
  private readonly connection: LineHttpConnection;
  private readonly hostBackoff = new Map<string, number>();

  constructor(connection: LineHttpConnection) {
    this.connection = connection;
  }

  get applicationHeader(): string {
    return this.connection.applicationHeader;
  }

  applicationHeaderFor(role: LineClientRole): string {
    if (role !== LineClientRole.PRIMARY && role !== LineClientRole.SECONDARY) {
      throw new MiniAppError(LineErrorCode.CONNECTION_CONFIG_REQUIRED, 'LINE 客户端角色无效');
    }
    const header: string | undefined = this.connection.applicationHeaderFor ?
      this.connection.applicationHeaderFor(role) :
      (role === LineClientRole.SECONDARY ? this.connection.applicationHeader : undefined);
    if (!header) {
      throw new MiniAppError(LineErrorCode.CONNECTION_CONFIG_REQUIRED, 'LINE 连接不支持客户端角色');
    }
    return header;
  }

  async send(request: LineTransportRequest): Promise<Uint8Array> {
    if (!this.connection.applicationHeader) {
      throw new MiniAppError(LineErrorCode.CONNECTION_CONFIG_REQUIRED, 'LINE 连接配置无效');
    }
    const service: LineService = this.serviceFor(request.path);
    this.validateIdentity(request, service);
    const application: string = this.applicationHeaderFor(request.role ?? LineClientRole.SECONDARY);
    const strictStatus: boolean = service === 'registration' || service === 'registrationPoll' ||
      service === 'accountTalk';
    const verification: boolean = service === 'verification';
    if (verification && !request.sessionAccess) {
      throw new MiniAppError(LineErrorCode.CONNECTION_CONFIG_REQUIRED, 'LINE 验证会话不可用');
    }
    const base: string = await this.connection.endpointFor(service);
    let target: string;
    let host: string;
    try {
      const endpoint = new url.URL(base);
      if (endpoint.protocol !== 'https:' || endpoint.username || endpoint.password ||
        endpoint.search || endpoint.hash) {
        throw new Error('invalid endpoint');
      }
      target = new url.URL(request.path, endpoint).toString();
      host = endpoint.host;
    } catch (_) {
      throw new MiniAppError(LineErrorCode.CONNECTION_CONFIG_REQUIRED, 'LINE 服务端点无效');
    }
    if (Date.now() < (this.hostBackoff.get(host) ?? 0)) {
      throw new MiniAppError(LineErrorCode.RPC_RETRY_LATER, 'LINE 服务暂时不可用');
    }
    const headers: Record<string, string> = {
      'Content-Type': 'application/x-thrift',
      'X-LPV': '1'
    };
    headers[LineAccountHeader.APPLICATION] = application;
    if (verification) {
      headers.Accept = 'application/json';
    }
    const extras: Record<string, string> | undefined = this.connection.clientHeaders;
    if (extras) {
      Object.keys(extras).forEach((key: string): void => {
        if (/^(content-type|x-line-application|x-line-access|x-line-liff-id|x-lpv)$/i.test(key)) {
          throw new MiniAppError(LineErrorCode.CONNECTION_CONFIG_REQUIRED, 'LINE 请求头配置冲突');
        }
        headers[key] = extras[key];
      });
    }
    if (request.sessionAccess) {
      headers[LineAccountHeader.ACCESS] = request.sessionAccess;
    }
    if (request.liffId) {
      headers['X-Line-Liff-Id'] = request.liffId;
    }
    const client = http.createHttp();
    let timer: number | undefined;
    try {
      const timeoutMs: number = request.timeoutMs ?? LineRpcTimeout.REQUEST_MS;
      const options: http.HttpRequestOptions = {
        method: verification ? http.RequestMethod.GET : http.RequestMethod.POST,
        header: headers,
        extraData: request.body.slice().buffer,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        readTimeout: timeoutMs,
        connectTimeout: LineRpcTimeout.CONNECT_MS,
        usingCache: false,
        usingProtocol: http.HttpProtocol.HTTP2
      };
      if (verification) {
        // GET 不附带 Thrift body；X-Line-Access 此处是临时 verifier，而非账号 Token。
        options.extraData = undefined;
      }
      const timeout = new Promise<http.HttpResponse>((_resolve, reject): void => {
        timer = setTimeout((): void => {
          reject(new MiniAppError(service === 'poll' ? LineErrorCode.QR_POLL_TIMEOUT : LineErrorCode.RPC_TIMEOUT,
            'LINE 请求超时'));
        }, timeoutMs);
      });
      const response: http.HttpResponse = await Promise.race([client.request(target, options), timeout]);
      let status: number = response.responseCode;
      if (strictStatus) {
        const responseHeaders = response.header as Record<string, string> | undefined;
        const override: string | undefined = this.header(responseHeaders, 'x-lc');
        if (status === 200 && override !== undefined && /^[+-]?\d+$/.test(override) &&
          Number(override) >= -2147483648 && Number(override) <= 2147483647) {
          status = Number(override);
        }
        if (status === 503) {
          const retry: string | undefined = this.header(responseHeaders, 'retry-after');
          const seconds: number = retry !== undefined && /^\d+$/.test(retry) ? Number(retry) : 0;
          const until: number = Date.now() + seconds * 1000;
          if (seconds > 0 && Number.isSafeInteger(until)) { this.hostBackoff.set(host, until); }
        }
      }
      if (verification && response.responseCode === 410) {
        throw new MiniAppError(LineErrorCode.EMAIL_VERIFICATION_TIMEOUT, 'LINE 主设备验证已超时');
      }
      if ((strictStatus ? status !== 200 : status < 200 || status >= 300) ||
        !(response.result instanceof ArrayBuffer)) {
        throw new MiniAppError(LineErrorCode.RPC_HTTP_FAILED, 'LINE 服务请求失败');
      }
      return new Uint8Array(response.result);
    } catch (error) {
      throw MiniAppError.from(error as Object, LineErrorCode.RPC_NETWORK_FAILED, 'LINE 网络请求失败');
    } finally {
      if (timer !== undefined) {
        clearTimeout(timer);
      }
      client.destroy();
    }
  }

  private header(headers: Record<string, string> | undefined, name: string): string | undefined {
    if (!headers) { return undefined; }
    const key: string | undefined = Object.keys(headers).find((key: string): boolean => key.toLowerCase() === name);
    return key === undefined ? undefined : String(headers[key]);
  }

  private validateIdentity(request: LineTransportRequest, service: LineService): void {
    const registration: boolean = service === 'registration' || service === 'registrationPoll';
    const explicit: boolean = request.accessKind !== undefined;
    let valid: boolean = true;
    if (registration) {
      valid = request.role === LineClientRole.PRIMARY && request.accessKind ===
        (service === 'registration' ? LineAccessKind.NONE : LineAccessKind.REGISTRATION_SESSION);
    } else if (service === 'accountTalk') {
      valid = request.role !== undefined && request.accessKind === LineAccessKind.ACCOUNT;
    } else if (request.role === LineClientRole.PRIMARY && !explicit) {
      valid = false;
    }
    if (explicit) {
      valid = valid && (request.role === LineClientRole.PRIMARY || request.role === LineClientRole.SECONDARY);
      switch (request.accessKind) {
        case LineAccessKind.NONE:
          valid = valid && request.sessionAccess === undefined;
          break;
        case LineAccessKind.REGISTRATION_SESSION:
          valid = valid && service === 'registrationPoll' && !!request.sessionAccess;
          break;
        case LineAccessKind.ACCOUNT:
          valid = valid && !!request.sessionAccess && (service === 'accountTalk' || service === 'liff' ||
            service === 'channel' || service === 'refresh');
          break;
        default: valid = false;
      }
    }
    if (!valid || (explicit && request.liffId !== undefined && service !== 'liff')) {
      throw new MiniAppError(LineErrorCode.CONNECTION_CONFIG_REQUIRED, 'LINE 请求身份与服务不匹配');
    }
  }

  /** 一处定义路径白名单和服务归属，避免新增路径后漏改校验或错误归入扫码服务。 */
  private serviceFor(path: string): LineService {
    switch (path) {
      case LineRpcPath.REGISTRATION:
        return 'registration';
      case LineRpcPath.REGISTRATION_POLL:
        return 'registrationPoll';
      case LineRpcPath.ACCOUNT_TALK:
        return 'accountTalk';
      case LineRpcPath.LOGIN:
        return 'login';
      case LineRpcPath.POLL:
        return 'poll';
      case LineRpcPath.LIFF:
        return 'liff';
      case LineRpcPath.CHANNEL:
        return 'channel';
      case LineRpcPath.REFRESH:
        return 'refresh';
      case LineRpcPath.AUTH:
        return 'auth';
      case LineRpcPath.IDENTITY:
        return 'talk';
      case LineRpcPath.EMAIL_VERIFY:
      case LineRpcPath.EMAIL_VERIFY_PLAIN:
        return 'verification';
      default:
        throw new MiniAppError(LineErrorCode.CONNECTION_CONFIG_REQUIRED, 'LINE 连接配置无效');
    }
  }
}
