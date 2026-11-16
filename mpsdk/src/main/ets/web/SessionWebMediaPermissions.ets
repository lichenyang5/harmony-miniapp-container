import { MiniAppSession } from '../core/Runtime';
import { HarmonyMediaPermissionGateway } from '../capabilities/media/HarmonyMediaPermissionGateway';
import {
  WebMediaPermissionController,
  WebMediaPermissionGateway,
  WebMediaRequest
} from './WebMediaPermissionController';

/** 将通用网页媒体授权绑定到会话；厂商只负责来源策略。 */
export class SessionWebMediaPermissions {
  private readonly session: MiniAppSession;
  private readonly controller: WebMediaPermissionController;
  private disposed: boolean = false;

  constructor(session: MiniAppSession, gateway?: WebMediaPermissionGateway) {
    this.session = session;
    this.controller = new WebMediaPermissionController(
      gateway ?? new HarmonyMediaPermissionGateway(session.uiAbilityContext),
      (origin: string): boolean => this.allowsOrigin(origin),
      (): boolean => this.session.lifecycle.isForeground());
  }

  /** 在 session.beginDocument 之后调用；每一代文档都注册独立的失效清理。 */
  beginDocument(address: string): void {
    if (this.disposed) {
      return;
    }
    this.controller.beginDocument(address);
    this.session.addCleanup((): void => this.controller.beginDocument(''));
  }

  handle(request: WebMediaRequest): void {
    if (!this.session.lifecycle.isForeground()) {
      try {
        request.deny();
      } catch (_) {
      }
      return;
    }
    this.controller.handle(request);
  }

  cancel(): void {
    this.controller.cancel();
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.controller.dispose();
  }

  private allowsOrigin(origin: string): boolean {
    try {
      return this.session.getBinding().canUseMedia?.(origin) ?? false;
    } catch (_) {
      // 会话关闭、厂商策略缺失或异常时不授予媒体权限。
      return false;
    }
  }
}
