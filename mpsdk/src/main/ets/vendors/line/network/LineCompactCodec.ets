import {
  LineCompactEncoding,
  LineCompactLimits,
  LineCompactMessage,
  LineCompactType,
  LineRpcField
} from './LineRpcConstants';
import { LineErrorCode } from '../LineErrorCode';
import { util } from '@kit.ArkTS';
import { MiniAppError } from '../../../core/MiniAppError';

/** 标准 Thrift TApplicationException 的诊断字段；不属于业务结果 struct。 */
enum ApplicationExceptionField {
  MESSAGE = 1
}

function invalid(): MiniAppError {
  return new MiniAppError(LineErrorCode.QR_PROTOCOL_ERROR, 'LINE 扫码登录响应格式无效');
}

export class LineCompactWriter {
  private readonly bytes: number[] = [];

  byte(value: number): void {
    this.bytes.push(value);
  }

  /** previousId 属于当前 struct；显式传入，嵌套结构不会污染外层字段增量。 */
  field(id: number, type: LineCompactType, previousId: number = 0): void {
    const delta: number = id - previousId;
    if (delta > 0 && delta <= LineCompactEncoding.INLINE_MAX) {
      this.byte((delta << LineCompactEncoding.TYPE_BITS) | type);
    } else {
      this.byte(type);
      this.integer(id);
    }
  }

  uint(value: number): void {
    do {
      const part: number = value & LineCompactEncoding.VARINT_DATA_MASK;
      value = Math.floor(value / LineCompactEncoding.VARINT_BASE);
      this.byte(part | (value > 0 ? LineCompactEncoding.VARINT_CONTINUATION : 0));
    } while (value > 0);
  }

  /** Thrift 有符号整数先做 ZigZag，再写 varint；完整字段 ID 也使用此规则。 */
  integer(value: number): void {
    this.uint(value >= 0 ? value * 2 : -value * 2 - 1);
  }

  /** Split before ZigZag doubling so the full safe integer range remains exact. */
  long(value: number): void {
    if (!Number.isSafeInteger(value)) {
      throw invalid();
    }
    let magnitude: number = value >= 0 ? value : -value - 1;
    const first: number = (magnitude % 64) * 2 + (value < 0 ? 1 : 0);
    magnitude = Math.floor(magnitude / 64);
    this.byte(first | (magnitude > 0 ? LineCompactEncoding.VARINT_CONTINUATION : 0));
    while (magnitude > 0) {
      const part: number = magnitude % LineCompactEncoding.VARINT_BASE;
      magnitude = Math.floor(magnitude / LineCompactEncoding.VARINT_BASE);
      this.byte(part | (magnitude > 0 ? LineCompactEncoding.VARINT_CONTINUATION : 0));
    }
  }

  string(value: string): void {
    if (value.length === 0) {
      this.uint(0);
      return;
    }
    const bytes = new util.TextEncoder().encodeInto(value);
    this.uint(bytes.length);
    bytes.forEach((byte: number): void => {
      this.byte(byte);
    });
  }

  result(): Uint8Array {
    return new Uint8Array(this.bytes);
  }
}

export class LineCompactReader {
  private position: number = 0;
  private readonly bytes: Uint8Array;
  private readonly onInvalid: () => MiniAppError;

  /** 各服务保留自己的格式错误码；共享字节解析不会混淆 QR 与 LIFF 的公开错误。 */
  constructor(bytes: Uint8Array, onInvalid: () => MiniAppError = invalid) {
    this.bytes = bytes;
    this.onInvalid = onInvalid;
  }

  byte(): number {
    if (this.position >= this.bytes.length) {
      throw this.onInvalid();
    }
    return this.bytes[this.position++];
  }

  uint(): number {
    let result: number = 0;
    let factor: number = 1;
    for (let i: number = 0; i < LineCompactEncoding.UINT32_BYTES; i++) {
      const byte = this.byte();
      result += (byte & LineCompactEncoding.VARINT_DATA_MASK) * factor;
      if (result > LineCompactEncoding.UINT32_MAX) {
        throw this.onInvalid();
      }
      if (!(byte & LineCompactEncoding.VARINT_CONTINUATION)) {
        return result;
      }
      factor *= LineCompactEncoding.VARINT_BASE;
    }
    throw this.onInvalid();
  }

  integer(): number {
    const value = this.uint();
    return value % 2 ? -Math.floor(value / 2) - 1 : value / 2;
  }

  long(): number {
    const first: number = this.byte();
    const negative: boolean = (first & 1) !== 0;
    let value: number = (first & LineCompactEncoding.VARINT_DATA_MASK) >> 1;
    let factor: number = 64;
    let continued: boolean = (first & LineCompactEncoding.VARINT_CONTINUATION) !== 0;
    for (let i: number = 1; continued && i < LineCompactEncoding.INT64_BYTES; i++) {
      const byte = this.byte();
      value += (byte & LineCompactEncoding.VARINT_DATA_MASK) * factor;
      if (!Number.isSafeInteger(value)) {
        throw this.onInvalid();
      }
      continued = (byte & LineCompactEncoding.VARINT_CONTINUATION) !== 0;
      factor *= LineCompactEncoding.VARINT_BASE;
    }
    const result: number = negative ? -value - 1 : value;
    if (continued || !Number.isSafeInteger(result)) {
      throw this.onInvalid();
    }
    return result;
  }

  take(length: number): Uint8Array {
    if (length > this.bytes.length - this.position) {
      throw this.onInvalid();
    }
    const result = this.bytes.slice(this.position, this.position + length);
    this.position += length;
    return result;
  }

  string(): string {
    const bytes: Uint8Array = this.take(this.uint());
    try {
      return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes);
    } catch (error) {
      // 平台解码异常与越界使用同一调用方协议码，原始原因只供原生诊断。
      const failure: MiniAppError = this.onInvalid();
      throw new MiniAppError(failure.code, failure.message, error as Object);
    }
  }

  strings(): string[] {
    const count: number = this.listCount(LineCompactType.BINARY);
    const result: string[] = [];
    for (let index: number = 0; index < count; index++) {
      result.push(this.string());
    }
    return result;
  }

  integers(): number[] {
    const count: number = this.listCount(LineCompactType.I32);
    const result: number[] = [];
    for (let index: number = 0; index < count; index++) {
      result.push(this.integer());
    }
    return result;
  }

  stringMap(): Map<string, string> {
    const count = this.uint();
    if (count > LineCompactLimits.EXTRACTED_ELEMENTS) {
      throw this.onInvalid();
    }
    const result = new Map<string, string>();
    if (count === 0) {
      return result;
    }
    if (this.byte() !== LineCompactEncoding.STRING_MAP_TYPES) {
      throw this.onInvalid();
    }
    for (let i: number = 0; i < count; i++) {
      result.set(this.string(), this.string());
    }
    return result;
  }

  struct(consume: (id: number, type: number) => boolean, depth: number = 0): void {
    if (depth > LineCompactLimits.NESTING_DEPTH) {
      throw this.onInvalid();
    }
    let previous: number = 0;
    while (true) {
      const header = this.byte();
      if (header === LineCompactType.STOP) {
        return;
      }
      const type = header & LineCompactEncoding.TYPE_MASK;
      const delta = header >> LineCompactEncoding.TYPE_BITS;
      const id = delta === 0 ? this.integer() : previous + delta;
      previous = id;
      if (!consume(id, type)) {
        this.skip(type, depth + 1);
      }
    }
  }

  skip(type: number, depth: number): void {
    if (depth > LineCompactLimits.NESTING_DEPTH) {
      throw this.onInvalid();
    }
    if (type === LineCompactType.BOOLEAN_TRUE || type === LineCompactType.BOOLEAN_FALSE) {
      return;
    }
    if (type === LineCompactType.BYTE) {
      this.byte();
      return;
    }
    if (type === LineCompactType.I16 || type === LineCompactType.I32) {
      this.uint();
      return;
    }
    if (type === LineCompactType.I64) {
      for (let i: number = 0; i < LineCompactEncoding.INT64_BYTES; i++) {
        if (!(this.byte() & LineCompactEncoding.VARINT_CONTINUATION)) {
          return;
        }
      }
      throw this.onInvalid();
    }
    if (type === LineCompactType.DOUBLE) {
      this.take(LineCompactEncoding.DOUBLE_BYTES);
      return;
    }
    if (type === LineCompactType.BINARY) {
      this.take(this.uint());
      return;
    }
    if (type === LineCompactType.LIST || type === LineCompactType.SET) {
      const header = this.byte();
      const inlineCount: number = header >> LineCompactEncoding.TYPE_BITS;
      const count: number = inlineCount === LineCompactEncoding.INLINE_MAX ? this.uint() : inlineCount;
      if (count > LineCompactLimits.SKIPPED_ELEMENTS) {
        throw this.onInvalid();
      }
      for (let i: number = 0; i < count; i++) {
        this.skipElement(header & LineCompactEncoding.TYPE_MASK, depth + 1);
      }
      return;
    }
    if (type === LineCompactType.MAP) {
      const count = this.uint();
      if (count > LineCompactLimits.SKIPPED_ELEMENTS) {
        throw this.onInvalid();
      }
      if (count === 0) {
        return;
      }
      const types = this.byte();
      for (let i: number = 0; i < count; i++) {
        this.skipElement(types >> LineCompactEncoding.TYPE_BITS, depth + 1);
        this.skipElement(types & LineCompactEncoding.TYPE_MASK, depth + 1);
      }
      return;
    }
    if (type === LineCompactType.STRUCT) {
      this.struct((): boolean => false, depth + 1);
      return;
    }
    throw this.onInvalid();
  }

  finished(): boolean {
    return this.position === this.bytes.length;
  }

  listCount(elementType: number): number {
    const header: number = this.byte();
    if ((header & LineCompactEncoding.TYPE_MASK) !== elementType) {
      throw this.onInvalid();
    }
    const inlineCount: number = header >> LineCompactEncoding.TYPE_BITS;
    const count: number = inlineCount === LineCompactEncoding.INLINE_MAX ? this.uint() : inlineCount;
    if (count > LineCompactLimits.EXTRACTED_ELEMENTS) {
      throw this.onInvalid();
    }
    return count;
  }

  private skipElement(type: number, depth: number): void {
    if (type === LineCompactType.BOOLEAN_TRUE || type === LineCompactType.BOOLEAN_FALSE) {
      this.byte();
      return;
    }
    this.skip(type, depth);
  }
}


/** 校验完整 envelope 后才由调用方处理业务错误，防止残缺响应被当作有效拒绝。 */
export class LineCompactCodec {
  /** 读取消息头之后的标准异常 struct；完整性错误由调用方映射，私有文案仅作为原生 cause。 */
  static readApplicationExceptionCause(reader: LineCompactReader, onInvalid: () => MiniAppError): Error | undefined {
    let message: string | undefined;
    reader.struct((id: number, type: number): boolean => {
      if (id !== ApplicationExceptionField.MESSAGE || type !== LineCompactType.BINARY) {
        return false;
      }
      if (message !== undefined) {
        throw onInvalid();
      }
      message = reader.string();
      return true;
    });
    if (!reader.finished()) {
      throw onInvalid();
    }
    return message === undefined ? undefined : new Error(message);
  }

  static response(bytes: Uint8Array, method: string, sequence: number,
    parseSuccess: (reader: LineCompactReader) => void,
    parseFailure: (reader: LineCompactReader) => void): boolean {
    if (bytes.length > LineCompactLimits.MESSAGE_BYTES) {
      throw invalid();
    }
    const reader = new LineCompactReader(bytes);
    if (reader.byte() !== LineCompactMessage.PROTOCOL_ID) {
      throw invalid();
    }
    const versionType = reader.byte();
    if ((versionType & LineCompactMessage.VERSION_MASK) !== LineCompactMessage.VERSION || reader.uint() !== sequence ||
      reader.string() !== method) {
      throw invalid();
    }
    if ((versionType >> LineCompactMessage.TYPE_SHIFT) === LineCompactMessage.EXCEPTION) {
      throw new MiniAppError(LineErrorCode.QR_APPLICATION_ERROR, 'LINE RPC 请求被拒绝',
        LineCompactCodec.readApplicationExceptionCause(reader, invalid));
    }
    if ((versionType >> LineCompactMessage.TYPE_SHIFT) !== LineCompactMessage.REPLY) {
      throw invalid();
    }
    let success: boolean = false;
    let failure: boolean = false;
    reader.struct((id: number, type: number): boolean => {
      if (type !== LineCompactType.STRUCT) {
        if (id === LineRpcField.SUCCESS || id === LineRpcField.ERROR) {
          throw invalid();
        }
        return false;
      }
      if (id === LineRpcField.SUCCESS) {
        if (success) {
          throw invalid();
        }
        parseSuccess(reader);
        success = true;
        return true;
      }
      if (id === LineRpcField.ERROR) {
        if (failure) {
          throw invalid();
        }
        parseFailure(reader);
        failure = true;
        return true;
      }
      return false;
    });
    if (!reader.finished() || success === failure) {
      throw invalid();
    }
    return success;
  }
}
