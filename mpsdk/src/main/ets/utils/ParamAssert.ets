import { MiniAppError } from '../core/MiniAppError';
import { INVALID_ARGUMENT, MISSING_REQUIRED_PARAMS } from '../core/MiniAppErrorCode';

/** 运行时参数断言：必填字段省略与非法值分别报错，不取值、不转换。 */
export class ParamAssert {
  /** 默认允许空串；allowEmpty=false 时拒绝空串，不自动 trim 或转换。 */
  static assertString(value: Object | null | undefined, name: string, allowEmpty: boolean = true): void {
    ParamAssert.assertRequired(value, name);
    if (typeof value !== 'string' || (!allowEmpty && value.length === 0)) {
      throw ParamAssert.invalid(name);
    }
  }

  /** 数值必须有限，拒绝 NaN 和 Infinity。 */
  static assertNumber(value: Object | null | undefined, name: string): void {
    ParamAssert.assertRequired(value, name);
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      throw ParamAssert.invalid(name);
    }
  }

  static assertBoolean(value: Object | null | undefined, name: string): void {
    ParamAssert.assertRequired(value, name);
    if (typeof value !== 'boolean') {
      throw ParamAssert.invalid(name);
    }
  }

  /** 必须为数组且每一项都是字符串；允许空数组。 */
  static assertStringArray(value: Object | null | undefined, name: string): void {
    ParamAssert.assertRequired(value, name);
    if (!Array.isArray(value)) {
      throw ParamAssert.invalid(name);
    }
    const values = value as Object[];
    for (let index = 0; index < values.length; index++) {
      // 数组已提供，非法元素（包括空槽）属于字段值错误，而非缺参。
      if (typeof values[index] !== 'string') {
        throw ParamAssert.invalid(name);
      }
    }
  }

  /** 严格匹配字符串或数字枚举，不将数字字符串转换成数字。 */
  static assertEnum(value: Object | null | undefined, name: string,
    allowedValues: ReadonlyArray<string | number>): void {
    ParamAssert.assertRequired(value, name);
    if ((typeof value !== 'string' && typeof value !== 'number') || allowedValues.indexOf(value) < 0) {
      throw ParamAssert.invalid(name);
    }
  }

  /** 参数必须是非 null 对象，不能是数组。 */
  static assertObject(value: Object | null | undefined, name: string): void {
    ParamAssert.assertRequired(value, name);
    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
      throw ParamAssert.invalid(name);
    }
  }

  /** 可选字段只允许 undefined 表示省略，null 仍然无效。 */
  static assertOptionalString(value: Object | null | undefined, name: string, allowEmpty: boolean = true): void {
    if (value !== undefined) {
      ParamAssert.assertString(value, name, allowEmpty);
    }
  }

  static assertOptionalNumber(value: Object | null | undefined, name: string): void {
    if (value !== undefined) {
      ParamAssert.assertNumber(value, name);
    }
  }

  static assertOptionalBoolean(value: Object | null | undefined, name: string): void {
    if (value !== undefined) {
      ParamAssert.assertBoolean(value, name);
    }
  }

  private static assertRequired(value: Object | null | undefined, name: string): void {
    if (value === undefined) {
      throw new MiniAppError(MISSING_REQUIRED_PARAMS, '缺少必填参数：' + name);
    }
  }

  private static invalid(name: string): MiniAppError {
    return new MiniAppError(INVALID_ARGUMENT, '参数字段无效：' + name);
  }
}
