import { MiniAppError } from '../../core/MiniAppError';
import { INVALID_ARGUMENT } from '../../core/MiniAppErrorCode';

/** VK 协议允许字符串或数字作为 request_id。 */
export type BridgeRequestId = string | number;

/** 统一校验 JSON 参数对象，业务处理器不再重复写类型判断。 */
export class JsonObjectReader {
  private readonly values: Record<string, Object>;

  private constructor(values: Record<string, Object>) {
    this.values = values;
  }

  static from(paramsJson: string): JsonObjectReader {
    let value: Object;
    try {
      value = JSON.parse(paramsJson) as Object;
    } catch (error) {
      throw new MiniAppError(INVALID_ARGUMENT, '参数不是合法 JSON', error as Object);
    }
    return JsonObjectReader.fromObject(value);
  }

  /** 直接校验已解析的参数，避免重复序列化和解析。 */
  static fromObject(value: Object): JsonObjectReader {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
      throw new MiniAppError(INVALID_ARGUMENT, '参数必须是 JSON 对象');
    }
    return new JsonObjectReader(value as Record<string, Object>);
  }

  requiredString(name: string): string {
    const value = this.values[name];
    if (typeof value !== 'string' || value.length === 0) {
      throw this.invalid(name);
    }
    return value;
  }

  requiredNumber(name: string): number {
    const value = this.values[name];
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      throw this.invalid(name);
    }
    return value;
  }

  optionalString(name: string, allowEmpty: boolean = false): string | undefined {
    const value = this.values[name];
    if (value === undefined) {
      return undefined;
    }
    if (typeof value !== 'string' || (!allowEmpty && value.length === 0)) {
      throw this.invalid(name);
    }
    return value;
  }

  optionalBoolean(name: string): boolean | undefined {
    const value = this.values[name];
    if (value === undefined) {
      return undefined;
    }
    if (typeof value !== 'boolean') {
      throw this.invalid(name);
    }
    return value;
  }

  optionalRequestId(name: string): BridgeRequestId | undefined {
    const value = this.values[name];
    if (value === undefined) {
      return undefined;
    }
    if (typeof value === 'string' && value.length > 0) {
      return value;
    }
    if (typeof value === 'number' && Number.isFinite(value)) {
      return value;
    }
    throw this.invalid(name);
  }

  private invalid(name: string): MiniAppError {
    return new MiniAppError(INVALID_ARGUMENT, '参数字段无效：' + name);
  }
}
