import { MiniAppSession } from '../core/Runtime';
import {
  GeolocationPermissionGateway,
  HarmonyGeolocationPermissionGateway
} from '../capabilities/permissions/HarmonyGeolocationPermissionGateway';

export interface WebGeolocationRequest {
  readonly origin: string;

  finish(allow: boolean): void;
}

class PendingGeolocationRequest {
  readonly request: WebGeolocationRequest;
  readonly generation: number;
  settled: boolean = false;

  constructor(request: WebGeolocationRequest, generation: number) {
    this.request = request;
    this.generation = generation;
  }

  finish(allow: boolean): void {
    if (this.settled) {
      return;
    }
    this.settled = true;
    try {
      this.request.finish(allow);
    } catch (_) { /* 文档已销毁时继续清理其他请求。 */
    }
  }
}

/** 每个视图独占定位请求；取消、切页与会话关闭后不交付迟到授权。 */
export class SessionWebGeolocationPermissions {
  private readonly session: MiniAppSession;
  private readonly gateway: GeolocationPermissionGateway;
  private generation: number = 0;
  private documentAllowed: boolean = false;
  private disposed: boolean = false;
  private pending: PendingGeolocationRequest[] = [];

  constructor(session: MiniAppSession, gateway?: GeolocationPermissionGateway) {
    this.session = session;
    this.gateway = gateway ?? new HarmonyGeolocationPermissionGateway(session.uiAbilityContext);
  }

  /** 在 session.beginDocument 后调用，注册本代文档的失效清理。 */
  beginDocument(address: string): void {
    if (this.disposed) {
      return;
    }
    this.invalidateDocument();
    this.documentAllowed = this.allowsOrigin(address);
    this.session.addCleanup((): void => this.invalidateDocument());
  }

  handle(request: WebGeolocationRequest): void {
    if (this.pending.some((item: PendingGeolocationRequest): boolean => item.request === request)) {
      return;
    }
    const item = new PendingGeolocationRequest(request, this.generation);
    this.pending.push(item);
    this.resolve(item);
  }

  /** ArkWeb onGeolocationHide 取消当前请求，但当前文档仍可重新请求。 */
  cancel(): void {
    this.generation++;
    const pending = this.pending;
    this.pending = [];
    pending.forEach((item: PendingGeolocationRequest): void => item.finish(false));
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.invalidateDocument();
  }

  private invalidateDocument(): void {
    this.documentAllowed = false;
    this.cancel();
  }

  private allowsOrigin(origin: string): boolean {
    try {
      return this.session.getBinding().canUseGeolocation?.(origin) ?? false;
    } catch (_) {
      return false;
    }
  }

  private isCurrent(item: PendingGeolocationRequest): boolean {
    if (!this.session.lifecycle.isForeground() || this.disposed || !this.documentAllowed || item.settled || item.generation !== this.generation) {
      return false;
    }
    try {
      this.gateway.assertForeground();
      return this.allowsOrigin(item.request.origin);
    } catch (_) {
      return false;
    }
  }

  private async resolve(item: PendingGeolocationRequest): Promise<void> {
    try {
      if (!this.isCurrent(item)) {
        item.finish(false);
        return;
      }
      const allowed = await this.gateway.request((): boolean => this.isCurrent(item));
      item.finish(allowed && this.isCurrent(item));
    } catch (_) {
      item.finish(false);
    } finally {
      this.pending = this.pending.filter((candidate: PendingGeolocationRequest): boolean => candidate !== item);
    }
  }
}
