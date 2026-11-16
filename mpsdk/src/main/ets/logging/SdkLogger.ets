import BuildProfile from '../../../../BuildProfile';
import { MiniAppError } from '../core/MiniAppError';


/** 日志字段长度上限。 */
const MAX_TOKEN_LENGTH: number = BuildProfile.DEBUG ? Number.MAX_VALUE : 96;


/** SDK 内部日志级别，按严重程度递增。 */
export class SdkLogLevel {
  /** 调用开始、正常完成和常规回传。 */
  static readonly DEBUG: number = 0;
  /** 初始化、会话和页面生命周期。 */
  static readonly INFO: number = 1;
  /** 拒绝、超时、过期响应和资源清理失败。 */
  static readonly WARN: number = 2;
  /** 执行异常或容器失败。 */
  static readonly ERROR: number = 3;
  /** 关闭日志。 */
  static readonly OFF: number = 4;
}

/** 常规诊断字段；原始调试数据只通过 data 在 DEBUG 级别输出。 */
export interface SdkLogContext {
  /** 内部会话标识。 */
  sessionId?: string;

  /** 厂商标识。 */
  vendorId?: string;

  /** 原请求所属页面代次。 */
  documentId?: number;

  /** 内部请求标识。 */
  requestId?: string;

  /** 内部能力名称。 */
  capability?: string;

  /** 结构化状态码。 */
  code?: string;

  /** 操作耗时，单位毫秒。 */
  durationMs?: number;

  /** 对象、待完成请求或资源的数量。 */
  count?: number;

  /** 仅 DEBUG 使用的私有协议数据；由 HiLogSink 按 %{private}s 输出，不进入 INFO/WARN/ERROR。 */
  data?: string;
}

/** 平台日志输出端口；公共事件名与私有诊断字段分开传递。 */
export interface SdkLogSink {
  /** 将一次日志交给平台，调用方会隔离输出异常。 */
  write(level: number, event: string, details: string): void;
}

/** 内部日志门面，默认 INFO；共享运行时初始化时自动安装平台输出器。 */
export class SdkLogger {
  private static sink?: SdkLogSink;
  private static minimumLevel: number = BuildProfile.DEBUG ? SdkLogLevel.DEBUG : SdkLogLevel.INFO;

  /** 安装输出器；仅由 SDK 初始化使用，宿主无需配置。 */
  static install(sink: SdkLogSink): void {
    SdkLogger.sink = sink;
  }

  /** 内部调试时调整级别；无效数值忽略，OFF 关闭输出。 */
  static setLevel(level: number): void {
    if (Number.isInteger(level) && level >= SdkLogLevel.DEBUG && level <= SdkLogLevel.OFF) {
      SdkLogger.minimumLevel = level;
    }
  }

  /** 输出调试事件；显式传入的 data 仅在此级别记录，由平台输出器按私有字段处理。 */
  static debug(scope: string, event: string, context: SdkLogContext = {}): void {
    SdkLogger.write(SdkLogLevel.DEBUG, scope, event, context);
  }

  /** 输出关键生命周期事件。 */
  static info(scope: string, event: string, context: SdkLogContext = {}): void {
    SdkLogger.write(SdkLogLevel.INFO, scope, event, context);
  }

  /** 输出预期失败或降级事件。 */
  static warn(scope: string, event: string, context: SdkLogContext = {}): void {
    SdkLogger.write(SdkLogLevel.WARN, scope, event, context);
  }

  /** 输出异常分类码，不输出 message、stack 或 originalCause，避免携带业务数据。 */
  static error(scope: string, event: string, error: MiniAppError, context: SdkLogContext = {}): void {
    SdkLogger.write(SdkLogLevel.ERROR, scope, event, context, `${error.code}:${error.message}`);
  }

  /** 限长并移除换行，防止标识字段形成多行伪造日志。 */
  private static token(value: string | undefined): string | undefined {
    return value?.replace(/[\r\n\t]/g, ' ').slice(0, MAX_TOKEN_LENGTH);
  }

  /** 只序列化白名单字段；格式化或平台输出异常不得改变业务执行结果。 */
  private static write(level: number, scope: string, event: string, context: SdkLogContext,
    error?: string): void {
    if (!SdkLogger.sink || level < SdkLogger.minimumLevel) {
      return;
    }
    try {
      const safe: SdkLogContext = {
        sessionId: SdkLogger.token(context.sessionId),
        vendorId: SdkLogger.token(context.vendorId),
        documentId: context.documentId,
        requestId: SdkLogger.token(context.requestId),
        capability: SdkLogger.token(context.capability),
        code: SdkLogger.token(error ?? context.code),
        durationMs: context.durationMs,
        count: context.count,
        data: level === SdkLogLevel.DEBUG ? context.data : undefined
      };
      SdkLogger.sink.write(level, SdkLogger.token(scope) + '.' + SdkLogger.token(event), JSON.stringify(safe));
    } catch (_) {
      // 不递归记录日志异常，防止日志故障影响业务或形成循环。
    }
  }
}
