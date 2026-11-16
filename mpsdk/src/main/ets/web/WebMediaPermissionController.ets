/** 网页媒体资源名称由 ArkWeb ProtectedResourceType 定义。 */
export const WEB_AUDIO_CAPTURE: string = 'TYPE_AUDIO_CAPTURE';

export const WEB_VIDEO_CAPTURE: string = 'TYPE_VIDEO_CAPTURE';

export interface WebMediaRequest {
  getOrigin(): string;

  getAccessibleResource(): string[];

  grant(resources: string[]): void;

  deny(): void;
}

export interface WebMediaPermissionGateway {
  assertForeground(): void;

  request(resources: string[], isCurrent: () => boolean): Promise<string[]>;
}

class PendingMediaRequest {
  readonly request: WebMediaRequest;
  readonly generation: number;
  settled: boolean = false;

  constructor(request: WebMediaRequest, generation: number) {
    this.request = request;
    this.generation = generation;
  }

  finish(resources?: string[]): void {
    if (this.settled) {
      return;
    }
    this.settled = true;
    try {
      if (resources) {
        this.request.grant(resources);
      } else {
        this.request.deny();
      }
    } catch (_) {
      // 已销毁文档的回调可能失效，不能影响其他请求清理。
    }
  }
}

/** 每个 WebView 独占：系统授权不等于向未来文档授予网页权限。 */
export class WebMediaPermissionController {
  private generation: number = 0;
  private disposed: boolean = false;
  private documentAllowed: boolean = false;
  private pending: PendingMediaRequest[] = [];
  private readonly gateway: WebMediaPermissionGateway;
  private readonly isAvailable: () => boolean;
  private readonly allowsOrigin: (origin: string) => boolean;

  constructor(gateway: WebMediaPermissionGateway, allowsOrigin: (origin: string) => boolean,
    isAvailable: () => boolean = (): boolean => true) {
    this.gateway = gateway;
    this.isAvailable = isAvailable;
    this.allowsOrigin = allowsOrigin;
  }

  beginDocument(address: string): void {
    if (this.disposed) {
      return;
    }
    this.invalidate();
    this.documentAllowed = this.allowsOrigin(address);
  }

  handle(request: WebMediaRequest): void {
    if (this.pending.some((item: PendingMediaRequest): boolean => item.request === request)) {
      return;
    }
    const item = new PendingMediaRequest(request, this.generation);
    this.pending.push(item);
    this.resolve(item);
  }

  cancel(): void {
    const allowed: boolean = this.documentAllowed;
    this.invalidate();
    this.documentAllowed = allowed;
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.invalidate();
  }

  private isCurrent(item: PendingMediaRequest): boolean {
    if (!this.isAvailable() || this.disposed || item.settled || !this.documentAllowed || item.generation !== this.generation) {
      return false;
    }
    try {
      this.gateway.assertForeground();
      return this.allowsOrigin(item.request.getOrigin());
    } catch (_) {
      return false;
    }
  }

  private async resolve(item: PendingMediaRequest): Promise<void> {
    try {
      const resources = item.request.getAccessibleResource().slice();
      if (!this.isCurrent(item) || resources.length === 0 ||
        resources.some((value: string): boolean => value !== WEB_AUDIO_CAPTURE && value !== WEB_VIDEO_CAPTURE)) {
        item.finish();
        return;
      }
      const allowed = await this.gateway.request(resources, (): boolean => this.isCurrent(item));
      if (this.isCurrent(item) && resources.every((value: string): boolean => allowed.includes(value))) {
        item.finish(resources);
      } else {
        item.finish();
      }
    } catch (_) {
      item.finish();
    } finally {
      this.pending = this.pending.filter((candidate: PendingMediaRequest): boolean => candidate !== item);
    }
  }

  private invalidate(): void {
    this.generation++;
    this.documentAllowed = false;
    const pending = this.pending;
    this.pending = [];
    pending.forEach((item: PendingMediaRequest): void => item.finish());
  }
}
