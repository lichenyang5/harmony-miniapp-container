import { DocumentScript, MiniAppSession } from '../../../core/Runtime';
import { MiniAppError } from '../../../core/MiniAppError';
import { DOCUMENT_CHANGED, SESSION_CLOSED } from '../../../core/MiniAppErrorCode';
import { LineErrorCode } from '../LineErrorCode';
import { LineAdapter } from '../LineAdapter';
import { createLineModalSessionToken, LineModalSessionToken } from '../LineModalSessionToken';
import { createLineMstScript } from '../script/LineMstScript';
import { LineWebLoginNavigation, LineWebLoginWindow } from '../weblogin/LineWebLoginTypes';
import { setLineWebLoginParameters, validateLineWebLoginReturn } from '../weblogin/LineWebLoginUrl';

/** 一个 LIFF WebView 的 MST 所有者；脚本从当前 pair 派生，不另存可变副本。 */
export class LineLiffDocument implements LineWebLoginWindow {
  private readonly isSubwindow: boolean;
  private readonly session: MiniAppSession;
  private mst?: LineModalSessionToken;
  /** 加载代次包含拒绝回跳；不能仅用 MST 引用判断回滚归属。 */
  private loadGeneration: number = 0;
  private disposed: boolean = false;

  constructor(session: MiniAppSession, isSubwindow: boolean) {
    this.session = session;
    this.isSubwindow = isSubwindow;
    if (!isSubwindow) {
      this.mst = createLineModalSessionToken();
    }
  }

  getDocumentId(): number {
    return this.session.getDocumentId();
  }

  isCurrent(documentId: number): boolean {
    return !this.disposed && !this.session.isClosed() && this.session.lifecycle.isForeground() &&
      documentId === this.session.getDocumentId();
  }

  getMst(): LineModalSessionToken | undefined {
    return this.mst ? { verifier: this.mst.verifier, challenge: this.mst.challenge } : undefined;
  }

  getScripts(): DocumentScript[] {
    if (!this.mst) {
      return [];
    }
    const liffId = this.session.getAdapter<LineAdapter>().getLiffId(this.session);
    // 先确认协议身份，再生成存储脚本；入口别名不能作为真实 ID 的兜底。
    return liffId ? [createLineMstScript(liffId, this.mst.challenge)] : [];
  }

  prepare(address: string, approved: boolean, documentId: number): LineWebLoginNavigation {
    this.assertCurrent(documentId);
    validateLineWebLoginReturn(address);
    const next = approved ? createLineModalSessionToken() : undefined;
    const parameters: Record<string, string> = {};
    if (next) {
      if (this.isSubwindow) {
        parameters.mst_verifier = next.verifier;
        parameters.msit = '';
      } else {
        parameters.mst_challenge = next.challenge;
      }
    }
    const target: string = next ? setLineWebLoginParameters(address, parameters) : address;
    const navigation: LineWebLoginNavigation = {
      url: target,
      load: async (): Promise<void> => {
        this.assertCurrent(documentId);
        const generation: number = ++this.loadGeneration;
        const previous = this.mst;
        if (next) {
          this.mst = next;
        }
        try {
          await this.session.load({ url: target }, documentId, this.getScripts());
        } catch (error) {
          // 后续加载（包括沿用 pair 的拒绝回跳）及 dispose 不受旧任务失败影响。
          if (next && !this.disposed && generation === this.loadGeneration && this.mst === next) {
            this.mst = previous;
          }
          throw MiniAppError.from(error as Object, LineErrorCode.WEB_LOGIN_FAILED, 'Unable to load LINE web login');
        }
      }
    };
    return navigation;
  }

  dispose(): void {
    this.disposed = true;
    this.mst = undefined;
  }

  private assertCurrent(documentId: number): void {
    if (this.disposed || this.session.isClosed()) {
      throw new MiniAppError(SESSION_CLOSED, 'LINE document is closed');
    }
    if (!this.isCurrent(documentId)) {
      throw new MiniAppError(DOCUMENT_CHANGED, 'LINE document changed');
    }
  }
}
