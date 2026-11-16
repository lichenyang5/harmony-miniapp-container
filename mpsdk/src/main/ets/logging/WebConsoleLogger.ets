import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'MPSDK.WebConsole';
const LOG_FORMAT: string = '[%{public}s] %{public}s:%{public}d %{public}s';
const CHUNK_LENGTH: number = 800;

/** 网页 console 转接，原文输出并分段，便于定位 iframe 内的脚本日志。 */
export class WebConsoleLogger {
  static write(level: MessageLevel, message: string, source: string, line: number, sessionId: string): void {
    try {
      // 与 websdk 保持一致：Log 和 Debug 均转为 HiLog DEBUG。
      for (let offset = 0; offset < Math.max(message.length, 1); offset += CHUNK_LENGTH) {
        const chunk = message.slice(offset, offset + CHUNK_LENGTH);
        switch (level) {
          case MessageLevel.Error:
            hilog.error(LOG_DOMAIN, LOG_TAG, LOG_FORMAT, sessionId, source, line, chunk);
            break;
          case MessageLevel.Warn:
            hilog.warn(LOG_DOMAIN, LOG_TAG, LOG_FORMAT, sessionId, source, line, chunk);
            break;
          case MessageLevel.Log:
          case MessageLevel.Debug:
            hilog.debug(LOG_DOMAIN, LOG_TAG, LOG_FORMAT, sessionId, source, line, chunk);
            break;
          case MessageLevel.Info:
            hilog.info(LOG_DOMAIN, LOG_TAG, LOG_FORMAT, sessionId, source, line, chunk);
            break;
        }
      }
    } catch (_) {
      // 日志输出异常不能影响 Web 回调。
    }
  }
}
