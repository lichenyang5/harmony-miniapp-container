export enum LineClientRole {
  PRIMARY = 'PRIMARY',
  SECONDARY = 'SECONDARY'
}

export enum LineAccessKind {
  NONE = 'NONE',
  REGISTRATION_SESSION = 'REGISTRATION_SESSION',
  ACCOUNT = 'ACCOUNT'
}

export interface LineTransportRequest {
  path: string;

  /** Thrift RPC 方法名，仅用于协议关联/诊断；HTTP GET/POST 由路径对应的传输策略决定。 */
  method: string;
  body: Uint8Array;

  /** 扫码轮询使用 authSessionId，邮箱确认使用 verifier，账号 RPC 使用 accessToken；不得全局注入。 */
  sessionAccess?: string;
  /** Omitted only by legacy secondary callers. New callers state both identity dimensions. */
  role?: LineClientRole;
  accessKind?: LineAccessKind;
  timeoutMs?: number;
  liffId?: string;
}

export interface LineTransport {
  /** 同一账号在官方授权 WebView 中沿用的客户端标识，不包含账号凭据。 */
  readonly applicationHeader?: string;
  applicationHeaderFor?(role: LineClientRole): string;

  send(request: LineTransportRequest): Promise<Uint8Array>;
}

export type LineService = 'login' | 'poll' | 'liff' | 'channel' | 'refresh' | 'auth' | 'verification' | 'talk' |
  'registration' | 'registrationPoll' | 'accountTalk';

/** 端点与客户端标识来自宿主运行环境；SDK 负责发送官方二进制 RPC。 */
export interface LineHttpConnection {
  applicationHeader: string;
  applicationHeaderFor?(role: LineClientRole): string;
  clientHeaders?: Record<string, string>;

  endpointFor(service: LineService): Promise<string>;
}

