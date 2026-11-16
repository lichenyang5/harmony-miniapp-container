import { DownloadFileName } from '../../../utils/DownloadFileName';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { DownloadTools } from '../../../capabilities/files/DownloadTools';
import { MiniAppError } from '../../../core/MiniAppError';
import {
  APP_IN_BACKGROUND,
  DOCUMENT_CHANGED,
  NOT_SUPPORTED,
  SYSTEM_ERROR,
  USER_CANCELLED
} from '../../../core/MiniAppErrorCode';
import { VkBridgeError } from '../VkBridgeError';
import { VkClientErrorCode } from '../VkClientErrorCode';
import { CodeReaderTools } from '../../../capabilities/media/CodeReaderTools';
import { BridgeContext } from '../../../core/Runtime';
import { ParamAssert } from '../../../utils/ParamAssert';
import { BaseVkEventHandler } from '../events/BaseVkEventHandler';
import { VkEvent } from '../events/VkEvent';

export const VK_WEB_APP_OPEN_CODE_READER: string = 'VKWebAppOpenCodeReader';

export interface VkDownloadParams {
  url: string;
  filename: string;
}

interface VkDownloadResult {
  result: boolean;
}

export interface VkCodeReaderResult {
  code_data: string;
}

/** VK 媒体协议适配，原生能力与会话状态分别管理。 */
export class VkMediaHandler implements BaseVkEventHandler {
  private static readonly confirmations: Map<common.UIAbilityContext, Promise<void>> =
    new Map<common.UIAbilityContext, Promise<void>>();
  readonly context: BridgeContext;
  private reader?: CodeReaderTools;
  private downloader?: DownloadTools;
  private disposed: boolean = false;

  constructor(context: BridgeContext) {
    this.context = context;
  }

  @VkEvent({
    name: VK_WEB_APP_OPEN_CODE_READER,
    timeout: -1
  })
  async openCodeReader(params: object): Promise<VkCodeReaderResult> {
    this.assertOpen();
    ParamAssert.assertObject(params, 'params');
    try {
      const documentId = this.context.getDocumentId();
      const value = await this.getReader().read();
      this.assertOpen();
      if (documentId !== this.context.getDocumentId()) {
        throw VkBridgeError.client(VkClientErrorCode.UNKNOWN);
      }
      if (typeof value !== 'string' || value.length === 0) {
        throw VkBridgeError.client(VkClientErrorCode.UNKNOWN);
      }
      return { code_data: value };
    } catch (error) {
      if (error instanceof VkBridgeError) {
        throw error;
      }
      if (error instanceof MiniAppError) {
        switch (error.code) {
          case APP_IN_BACKGROUND:
            throw VkBridgeError.client(VkClientErrorCode.BACKGROUND, undefined, error);
          case USER_CANCELLED:
            throw VkBridgeError.client(VkClientErrorCode.USER_DENIED, undefined, error);
          case NOT_SUPPORTED:
            throw VkBridgeError.client(VkClientErrorCode.UNSUPPORTED_PLATFORM, undefined, error);
        }
      }
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error as Object);
    }
  }

  @VkEvent({ name: 'VKWebAppDownloadFile', timeout: -1 })
  async downloadFile(params: VkDownloadParams): Promise<VkDownloadResult> {
    const documentId = this.context.getDocumentId();
    this.assertOpen();
    try {
      ParamAssert.assertObject(params, 'params');
      // 用户反馈 Android 客户端在 filename 为空时会闪退；这里主动返回参数错误，不复刻该缺陷。
      DownloadFileName.segments(params.filename);
      const accepted = await this.confirmDownload(params.filename, documentId);
      this.assertOpen();
      if (documentId !== this.context.getDocumentId()) {
        throw VkBridgeError.client(VkClientErrorCode.UNKNOWN);
      }
      if (!accepted) {
        throw VkBridgeError.client(VkClientErrorCode.USER_DENIED);
      }
      await this.getDownloader().start(params.url, params.filename);
      return { result: true };
    } catch (error) {
      if (error instanceof MiniAppError && error.code === NOT_SUPPORTED) {
        throw VkBridgeError.client(VkClientErrorCode.UNSUPPORTED_PLATFORM, undefined, error);
      }
      throw MiniAppError.from(error as Object, SYSTEM_ERROR, 'Download failed');
    }
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    const reader = this.reader;
    this.reader = undefined;
    reader?.dispose();
    this.downloader?.dispose();
    this.downloader = undefined;
  }

  private async confirmDownload(filename: string, documentId: number): Promise<boolean> {
    this.assertOpen();
    const ability = this.context.uiAbilityContext;
    const previous = VkMediaHandler.confirmations.get(ability);
    let release: () => void = (): void => {
    };
    const current = new Promise<void>((resolve) => {
      release = resolve;
    });
    VkMediaHandler.confirmations.set(ability, current);
    try {
      // 只串行确认框；SAVE 后释放队列，文件传输由各自任务并行执行。
      if (previous) {
        await previous;
      }
      this.assertOpen();
      if (documentId !== this.context.getDocumentId()) {
        throw new MiniAppError(DOCUMENT_CHANGED, 'Download request has expired');
      }
      const hostWindow = await window.getLastWindow(this.context.uiAbilityContext);
      this.assertOpen();
      if (documentId !== this.context.getDocumentId()) {
        throw new MiniAppError(DOCUMENT_CHANGED, 'Download request has expired');
      }
      return await new Promise<boolean>((resolve) => {
        hostWindow.getUIContext().showAlertDialog({
          title: $r('app.string.mpsdk_download_title'),
          message: $r('app.string.mpsdk_download_message', filename),
          primaryButton: {
            value: $r('app.string.mpsdk_download_cancel'),
            action: (): void => resolve(false)
          },
          secondaryButton: {
            value: $r('app.string.mpsdk_download_save'),
            action: (): void => resolve(true)
          },
          cancel: (): void => resolve(false)
        });
      });
    } catch (error) {
      throw MiniAppError.from(error as Object, SYSTEM_ERROR, 'Download confirmation failed');
    } finally {
      release();
      if (VkMediaHandler.confirmations.get(ability) === current) {
        VkMediaHandler.confirmations.delete(ability);
      }
    }
  }

  private getDownloader(): DownloadTools {
    if (!this.downloader) {
      const downloader = new DownloadTools(this.context.uiAbilityContext);
      this.downloader = downloader;
      this.context.addCleanup((): void => {
        if (this.downloader === downloader) {
          this.downloader = undefined;
          downloader.dispose();
        }
      });
    }
    return this.downloader;
  }

  private getReader(): CodeReaderTools {
    if (!this.reader) {
      const reader = new CodeReaderTools(this.context.uiAbilityContext);
      this.reader = reader;
      this.context.addCleanup((): void => {
        if (this.reader === reader) {
          this.reader = undefined;
          reader.dispose();
        }
      });
    }
    return this.reader;
  }

  private assertOpen(): void {
    if (this.disposed) {
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN);
    }
  }
}
