import { DownloadFileName } from '../../utils/DownloadFileName';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { SdkLogger } from '../../logging/SdkLogger';
import { MiniAppError } from '../../core/MiniAppError';
import { DOCUMENT_CHANGED, INVALID_ARGUMENT, NOT_SUPPORTED, SYSTEM_ERROR } from '../../core/MiniAppErrorCode';

/** HTTP 流式下载；请求发起后由独立任务负责文件和网络资源。 */
export class DownloadTools {
  private readonly context: common.UIAbilityContext;
  private disposed: boolean = false;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async start(url: string, filename: string): Promise<void> {
    try {
      this.assertActive();
      const parts = DownloadFileName.segments(filename);
      const options = new picker.DocumentSaveOptions();
      options.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      const destinations = await new picker.DocumentViewPicker(this.context).save(options);
      this.assertActive();
      if (destinations.length === 0) {
        throw new MiniAppError(SYSTEM_ERROR, 'No public download directory returned');
      }
      let directory = new fileUri.FileUri(destinations[0]).path;
      for (let i = 0; i < parts.length - 1; i++) {
        directory += '/' + parts[i];
        try {
          fileIo.mkdirSync(directory);
        } catch (error) {
          if ((error as BusinessError).code !== 13900015 || !fileIo.statSync(directory).isDirectory()) {
            throw MiniAppError.from(error as Object, SYSTEM_ERROR, 'Creating download folder failed');
          }
        }
      }
      const name = parts[parts.length - 1];
      const dot = name.lastIndexOf('.');
      const hasExtension = dot > 0 && dot < name.length - 1;
      const stem = hasExtension ? name.substring(0, dot) : name;
      const extension = hasExtension ? name.substring(dot) : '';
      let target = directory + '/' + name;
      let index = 1;
      while (fileIo.accessSync(target)) {
        target = directory + '/' + stem + '-' + (index++) + extension;
      }
      // Selection and open are synchronous, so SDK calls in this process cannot claim the same name.
      await new HttpDownloadJob(target).start(url);
    } catch (error) {
      if (error instanceof MiniAppError) {
        throw error;
      }
      const cause = error as BusinessError;
      if (cause.code === 401) {
        throw new MiniAppError(INVALID_ARGUMENT, 'System rejected download parameters', cause);
      }
      if (cause.code === 801) {
        throw new MiniAppError(NOT_SUPPORTED, 'HTTP download is not supported', cause);
      }
      throw MiniAppError.from(cause, SYSTEM_ERROR, 'HTTP download failed');
    }
  }

  dispose(): void {
    this.disposed = true;
  }

  private assertActive(): void {
    if (this.disposed) {
      throw new MiniAppError(DOCUMENT_CHANGED, 'Download request has expired');
    }
  }
}

/** 不持有会话；逐块写入，避免缓存整个文件或积压异步写入队列。 */
class HttpDownloadJob {
  private static nextId: number = 0;
  private readonly logId: string = 'download-' + ++HttpDownloadJob.nextId;
  private receivedBytes: number = 0;
  private totalBytes?: number;
  private lastProgressAt?: number;
  private lastLoggedBytes: number = -1;
  private readonly target: string;
  private file?: fileIo.File;
  private client?: http.HttpRequest;
  private ended: boolean = false;
  private status?: number;
  private finished: boolean = false;
  private resolve?: () => void;
  private reject?: (error: Object) => void;

  constructor(target: string) {
    this.target = target;
  }

  start(url: string): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      this.resolve = resolve;
      this.reject = reject;
      try {
        this.file = fileIo.openSync(this.target, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
        this.client = http.createHttp();
        this.client.on('dataReceive', this.receive);
        this.client.on('dataEnd', this.end);
        this.client.on('dataReceiveProgress', this.progress);
        SdkLogger.info('DownloadTools', 'downloadStarted', { requestId: this.logId });
        this.client.requestInStream(url, { method: http.RequestMethod.GET, usingCache: false })
          .then((status: number): void => {
            if (this.finished) {
              return;
            }
            this.status = status;
            if (status < 200 || status >= 300) {
              this.finish(new MiniAppError(SYSTEM_ERROR, 'HTTP response was unsuccessful'));
            } else {
              this.tryComplete();
            }
          }).catch((error: Object): void => this.finish(error));
      } catch (error) {
        this.finish(error as Object);
      }
    });
  }

  private readonly progress = (info: http.DataReceiveProgressInfo): void => {
    if (this.finished) {
      return;
    }
    this.receivedBytes = info.receiveSize;
    this.totalBytes = info.totalSize > 0 ? info.totalSize : undefined;
    const now = Date.now();
    if (this.lastProgressAt !== undefined && now - this.lastProgressAt < 1000) {
      return;
    }
    if (this.lastLoggedBytes === this.receivedBytes) {
      return;
    }
    this.lastProgressAt = now;
    this.lastLoggedBytes = this.receivedBytes;
    SdkLogger.info('DownloadTools', this.progressText('downloadProgress'), { requestId: this.logId });
  };

  private readonly receive = (chunk: ArrayBuffer): void => {
    if (this.finished || !this.file) {
      return;
    }
    try {
      let offset = 0;
      while (offset < chunk.byteLength) {
        const written = fileIo.writeSync(this.file.fd, offset === 0 ? chunk : chunk.slice(offset));
        if (written <= 0) {
          throw new MiniAppError(SYSTEM_ERROR, 'Writing download made no progress');
        }
        offset += written;
      }
    } catch (error) {
      this.finish(error as Object);
    }
  };

  private readonly end = (): void => {
    this.ended = true;
    this.tryComplete();
  };

  private tryComplete(): void {
    if (this.ended && this.status !== undefined && this.status >= 200 && this.status < 300) {
      this.finish();
    }
  }

  /** 下载专用进度只在本模块格式化，不扩展公共日志上下文。 */
  private progressText(event: string): string {
    if (this.totalBytes === undefined) {
      return `${event} ${this.receivedBytes} bytes`;
    }
    const percent = Math.min(100, Math.floor(this.receivedBytes * 100 / this.totalBytes));
    return `${event} ${this.receivedBytes}/${this.totalBytes} bytes (${percent}%)`;
  }

  private finish(error?: Object): void {
    if (this.finished) {
      return;
    }
    this.finished = true;
    if (this.client) {
      try {
        this.client.off('dataReceive', this.receive);
      } catch (_) {
      }
      try {
        this.client.off('dataEnd', this.end);
      } catch (_) {
      }
      try {
        this.client.off('dataReceiveProgress', this.progress);
      } catch (_) {
      }
      try {
        this.client.destroy();
      } catch (_) {
      }
    }
    if (this.file) {
      try {
        fileIo.closeSync(this.file);
      } catch (closeError) {
        error = error ?? closeError as Object;
      }
      if (error !== undefined) {
        try {
          fileIo.unlinkSync(this.target);
        } catch (_) {
        }
      }
    }
    if (error !== undefined) {
      SdkLogger.warn('DownloadTools', this.progressText('downloadFailed'), { requestId: this.logId });
      this.reject?.(error);
    } else {
      SdkLogger.info('DownloadTools', this.progressText('downloadCompleted'), { requestId: this.logId });
      this.resolve?.();
    }
  }
}
