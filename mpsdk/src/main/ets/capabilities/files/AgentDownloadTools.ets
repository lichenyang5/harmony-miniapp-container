import { common } from '@kit.AbilityKit';
import { BusinessError, request } from '@kit.BasicServicesKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { MiniAppError } from '../../core/MiniAppError';
import {
  DOCUMENT_CHANGED, INVALID_ARGUMENT, NOT_SUPPORTED, SYSTEM_ERROR
} from '../../core/MiniAppErrorCode';
import { SdkLogger } from '../../logging/SdkLogger';

/** API 15 路线：系统任务下载到缓存，完成后异步转存公共下载目录。 */
export class AgentDownloadTools {
  private readonly context: common.UIAbilityContext;
  private disposed: boolean = false;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async start(url: string, filename: string): Promise<void> {
    let task: request.agent.Task | undefined;
    let job: DownloadJob | undefined;
    try {
      this.assertActive();
      const options = new picker.DocumentSaveOptions();
      options.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      const destinations = await new picker.DocumentViewPicker(this.context).save(options);
      this.assertActive();
      if (destinations.length === 0) {
        throw new MiniAppError(SYSTEM_ERROR, 'No public download directory returned');
      }
      const directory = new fileUri.FileUri(destinations[0]).path;
      // 系统负责业务参数校验；不转换、trim 或补齐网页传来的字段。
      const config: request.agent.Config = {
        action: request.agent.Action.DOWNLOAD,
        url: url,
        saveas: filename,
        mode: request.agent.Mode.BACKGROUND,
        overwrite: true
      };
      task = await request.agent.create(this.context, config);
      job = new DownloadJob(task, this.context.cacheDir, directory);
      this.assertActive();
      job.listen();
      // 从这里起任务已提交启动，不再随页面清理而撤销。
      await task.start();
      job.started();
    } catch (error) {
      if (job) {
        await job.cancel();
      } else if (task) {
        try {
          await request.agent.remove(task.tid);
        } catch (_) {
        }
      }
      if (error instanceof MiniAppError) {
        throw error;
      }
      const platformError = error as BusinessError;
      if (platformError.code === 401) {
        throw new MiniAppError(INVALID_ARGUMENT, 'System rejected download parameters', platformError);
      }
      if (platformError.code === 801) {
        throw new MiniAppError(NOT_SUPPORTED, 'System download is not supported', platformError);
      }
      throw MiniAppError.from(platformError, SYSTEM_ERROR, 'System download failed');
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

/** 不持有页面、会话或 WebView；系统回调持有对象直至任务结束。 */
class DownloadJob {
  private readonly task: request.agent.Task;
  private readonly source: string;
  private readonly directory: string;
  private readonly filename: string;
  private finishing: boolean = false;
  private active: boolean = false;
  private terminal?: boolean;
  private completion?: Promise<void>;

  constructor(task: request.agent.Task, cacheDir: string, directory: string) {
    this.task = task;
    const saveas = task.config.saveas;
    if (saveas === undefined) {
      throw new MiniAppError(SYSTEM_ERROR, 'System did not return a download path');
    }
    // 使用系统接受后的路径；公共目标只采用该路径的文件名，不传播相对路径。
    if (saveas.startsWith('file://')) {
      this.source = new fileUri.FileUri(saveas).path;
    } else if (saveas.startsWith('internal://cache/')) {
      this.source = cacheDir + '/' + saveas.substring('internal://cache/'.length);
    } else if (saveas.startsWith('internal://')) {
      this.source = cacheDir + '/' + saveas.substring('internal://'.length);
    } else {
      this.source = saveas.startsWith('/') ? saveas : cacheDir + '/' + saveas;
    }
    this.filename = new fileUri.FileUri(this.source).name;
    this.directory = directory;
  }

  listen(): void {
    this.task.on('completed', this.completed);
    this.task.on('failed', this.failed);
  }

  started(): void {
    this.active = true;
    if (this.terminal !== undefined) {
      this.finish(this.terminal);
    }
  }

  cancel(): Promise<void> {
    return this.finish(false);
  }

  private readonly completed: (progress: request.agent.Progress) => void = (): void => {
    this.onTerminal(true);
  };

  private readonly failed: (progress: request.agent.Progress) => void = (): void => {
    this.onTerminal(false);
  };

  private onTerminal(success: boolean): void {
    if (this.terminal !== undefined) {
      return;
    }
    this.terminal = success;
    if (this.active) {
      this.finish(success);
    }
  }

  private finish(success: boolean): Promise<void> {
    if (this.finishing) {
      return this.completion ?? Promise.resolve();
    }
    this.finishing = true;
    this.completion = this.settle(success);
    return this.completion;
  }

  private async settle(success: boolean): Promise<void> {
    let target: string | undefined;
    let taskDirectory: string | undefined;
    let destination: fileIo.File | undefined;
    let copied: boolean = false;
    try {
      if (success) {
        // API 15 没有排他创建文件选项；原子创建独立目录，避免覆盖已有文件。
        let suffix = 0;
        while (taskDirectory === undefined) {
          const candidate = this.directory + '/download-' + this.task.tid +
            (suffix === 0 ? '' : '-' + suffix);
          try {
            fileIo.mkdirSync(candidate);
            taskDirectory = candidate;
          } catch (error) {
            if ((error as BusinessError).code !== 13900015) {
              throw MiniAppError.from(error as Object, SYSTEM_ERROR, 'Creating download directory failed');
            }
            suffix++;
          }
        }
        target = taskDirectory + '/' + this.filename;
        destination = fileIo.openSync(target, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
        await fileIo.copyFile(this.source, destination.fd);
        copied = true;
        SdkLogger.info('AgentDownloadTools', 'downloadSaved');
      } else {
        SdkLogger.warn('AgentDownloadTools', 'downloadFailed');
      }
    } catch (error) {
      SdkLogger.error('AgentDownloadTools', 'downloadSaveFailed',
        MiniAppError.from(error as Object, SYSTEM_ERROR, 'Saving download failed'));
    } finally {
      if (destination) {
        try {
          fileIo.closeSync(destination);
        } catch (_) {
        }
      }
      try {
        this.task.off('completed', this.completed);
      } catch (_) {
      }
      try {
        this.task.off('failed', this.failed);
      } catch (_) {
      }
      // 先停止/移除系统任务，再清理其文件，避免任务继续写入。
      try {
        await request.agent.remove(this.task.tid);
        await fileIo.unlink(this.source);
      } catch (error) {
        SdkLogger.warn('AgentDownloadTools', 'downloadCleanupFailed');
      }
      if (destination && target !== undefined && !copied) {
        try {
          await fileIo.unlink(target);
        } catch (_) {
        }
      }
      // 失败时可能保留空任务目录；API 15 的 rmdir 会递归删除，不用于公共目录清理。
    }
  }
}
