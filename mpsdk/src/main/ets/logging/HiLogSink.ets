import { hilog } from '@kit.PerformanceAnalysisKit';
import { SdkLogLevel, SdkLogSink } from './SdkLogger';


/** 平台业务域。 */
const LOG_DOMAIN: number = 0x0000;

/** SDK 平台日志标签。 */
const LOG_TAG: string = 'MPSDK';

/** 公开事件、私有上下文格式。 */
const LOG_FORMAT: string = '%{public}s %{private}s';


/** HiLog 实现：固定 MPSDK 标签，事件名公开，诊断上下文使用平台隐私格式。 */
export class HiLogSink implements SdkLogSink {
  /** 输出单行事件，不使用参考实现的边框或人为生成的异常堆栈。 */
  write(level: number, event: string, details: string): void {
    switch (level) {
      case SdkLogLevel.DEBUG:
        hilog.debug(LOG_DOMAIN, LOG_TAG, LOG_FORMAT, event, details);
        break;
      case SdkLogLevel.INFO:
        hilog.info(LOG_DOMAIN, LOG_TAG, LOG_FORMAT, event, details);
        break;
      case SdkLogLevel.WARN:
        hilog.warn(LOG_DOMAIN, LOG_TAG, LOG_FORMAT, event, details);
        break;
      case SdkLogLevel.ERROR:
        hilog.error(LOG_DOMAIN, LOG_TAG, LOG_FORMAT, event, details);
        break;
    }
  }
}
