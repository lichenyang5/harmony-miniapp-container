import { webview } from '@kit.ArkWeb';
import { DocumentScript, WebEndpoint, WebLoadRequest } from '../core/Runtime';
import { MiniAppError } from '../core/MiniAppError';
import { DOCUMENT_CHANGED, SYSTEM_ERROR, WEB_SCRIPT_FAILED } from '../core/MiniAppErrorCode';
import { SdkLogger } from '../logging/SdkLogger';

/** 将 ArkWeb 控制器适配为运行时使用的脚本执行端口。 */
export class ArkWebEndpoint implements WebEndpoint {
  private controller: webview.WebviewController;
  private readonly installScripts: (scripts: DocumentScript[]) => Promise<void>;

  /** 保存当前 WebView 控制器，由容器在控制器就绪后创建。 */
  constructor(controller: webview.WebviewController, installScripts: (scripts: DocumentScript[]) => Promise<void>) {
    this.controller = controller;
    this.installScripts = installScripts;
  }

  async load(request: WebLoadRequest, scripts: DocumentScript[], isCurrent: () => boolean = (): boolean => true): Promise<void> {
    let stage: string = 'DOCUMENT_SCRIPTS';
    try {
      await this.installScripts(scripts);
      if (!isCurrent()) {
        throw new MiniAppError(DOCUMENT_CHANGED, 'WebView document changed while installing scripts');
      }
      stage = 'LOAD_URL';
      if (request.headers && request.headers.length > 0) {
        this.controller.loadUrl(request.url, request.headers.map((header): webview.WebHeader =>
          ({ headerKey: header.name, headerValue: header.value })));
      } else {
        this.controller.loadUrl(request.url);
      }
    } catch (error) {
      SdkLogger.debug('WebView', 'loadFailed', {
        code: stage,
        data: error instanceof Error ? `${error.name}: ${error.message}\n${error.stack ?? ''}` : String(error)
      });
      throw MiniAppError.from(error as Object, SYSTEM_ERROR, 'Unable to load WebView');
    }
  }

  /** 执行脚本并返回平台结果；平台同步异常和异步拒绝统一转换为 SDK 异常。 */
  async evaluate(script: string): Promise<string> {
    try {
      return await this.controller.runJavaScript(script);
    } catch (error) {
      throw MiniAppError.from(error as Object, WEB_SCRIPT_FAILED, '执行小程序回调脚本失败');
    }
  }

  /** 暂停当前 ArkWeb 内的全部音视频；平台异常统一转换为 SDK 异常。 */
  pauseAllMedia(): void {
    try {
      this.controller.pauseAllMedia();
    } catch (error) {
      throw MiniAppError.from(error as Object, SYSTEM_ERROR, '暂停小程序网页媒体失败');
    }
  }
}

