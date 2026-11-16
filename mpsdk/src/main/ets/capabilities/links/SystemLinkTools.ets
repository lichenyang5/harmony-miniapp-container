import { common, Want } from '@kit.AbilityKit';
import { call } from '@kit.TelephonyKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SdkLogger } from '../../logging/SdkLogger';
import { assertHostForeground } from '../../core/HostLifecycleMonitor';
import { MiniAppError } from '../../core/MiniAppError';
import { INVALID_ARGUMENT, NOT_SUPPORTED, SYSTEM_ERROR } from '../../core/MiniAppErrorCode';
import {
  SystemLinkScheme, SYSTEM_SMS_ABILITY_NAME, SYSTEM_SMS_BUNDLE_NAME, SYSTEM_SMS_CONVERSATION_PAGE
} from './SystemLinkConstants';

interface MailPanelFailure {
  code: number;
}

interface SmsContact {
  contactsName: string;
  telephone: string;
}

/** 仅打开元服务可用的系统交互界面；不直接拨号、发邮件或发送短信。 */
export class SystemLinkTools {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async open(address: string): Promise<void> {
    SdkLogger.debug('SystemLink', 'request', { data: address });
    const separator: number = address.indexOf(':');
    const scheme: string = separator < 0 ? '' : address.slice(0, separator).toLowerCase();
    if (scheme !== SystemLinkScheme.TEL && scheme !== SystemLinkScheme.MAILTO && scheme !== SystemLinkScheme.SMS) {
      throw new MiniAppError(NOT_SUPPORTED, 'System link is not supported');
    }
    const startedAt: number = Date.now();
    try {
      if (/[\u0000-\u0020\u007f\\#]/.test(address)) {
        throw new MiniAppError(INVALID_ARGUMENT, 'Invalid system link');
      }
      let value: string = address.slice(separator + 1);
      let mail: Record<string, Object> = {};
      let sms: Want | undefined;
      if (scheme === SystemLinkScheme.TEL) {
        value = this.phoneNumber(value);
      } else if (scheme === SystemLinkScheme.MAILTO) {
        mail = this.parseMail(value);
      } else {
        sms = this.parseSms(value);
      }
      SdkLogger.info('SystemLink', 'openStarted', { capability: scheme });
      // 参数准备完成后立即检查并启动，不插入异步窗口查询。
      assertHostForeground(this.context);
      if (scheme === SystemLinkScheme.TEL) {
        const supported: boolean = canIUse('SystemCapability.Applications.Contacts');
        SdkLogger.debug('SystemLink', 'dialCapabilityChecked', { code: supported ? 'SUPPORTED' : NOT_SUPPORTED });
        if (!supported) {
          throw new MiniAppError(NOT_SUPPORTED, 'Dial screen is not supported');
        }
        await call.makeCall(this.context, value);
      } else if (scheme === SystemLinkScheme.MAILTO) {
        await this.composeMail(mail);
      } else {
        // 只预填系统编辑页，由用户选择是否发送；不调用 SEND_MESSAGES 能力。
        await this.context.startAbilityForResult(sms!);
      }
      SdkLogger.info('SystemLink', 'openCompleted', { capability: scheme, durationMs: Date.now() - startedAt });
    } catch (error) {
      const failure = MiniAppError.from(error, error instanceof URIError ? INVALID_ARGUMENT : SYSTEM_ERROR,
        'Unable to open system link');
      SdkLogger.warn('SystemLink', 'openFailed', { capability: scheme,
        code: String((error as BusinessError)?.code ?? failure.code), durationMs: Date.now() - startedAt });
      SdkLogger.debug('SystemLink', 'failureDetail', { capability: scheme,
        data: String((error as BusinessError)?.code) + ':' + (error as BusinessError)?.message });
      throw failure;
    }
  }

  private phoneNumber(raw: string): string {
    const value: string = decodeURIComponent(raw);
    if (!/^\+?[0-9(). -]+$/.test(value) || !/[0-9]/.test(value)) {
      throw new MiniAppError(INVALID_ARGUMENT, 'Invalid telephone number');
    }
    return value;
  }

  private parseSms(value: string): Want {
    const separator: number = value.indexOf('?');
    const recipient: string = separator < 0 ? value : value.slice(0, separator);
    const contacts: SmsContact[] = [];
    if (recipient) {
      for (const raw of recipient.split(',')) {
        contacts.push({ contactsName: '', telephone: this.phoneNumber(raw) });
      }
    }
    let body: string = '';
    if (separator >= 0) {
      for (const part of value.slice(separator + 1).split('&')) {
        const equals: number = part.indexOf('=');
        if (equals >= 0 && decodeURIComponent(part.slice(0, equals)).toLowerCase() === 'body') {
          body = decodeURIComponent(part.slice(equals + 1));
        }
      }
    }
    const want: Want = {
      bundleName: SYSTEM_SMS_BUNDLE_NAME,
      abilityName: SYSTEM_SMS_ABILITY_NAME,
      parameters: {
        contactObjects: JSON.stringify(contacts), pageFlag: SYSTEM_SMS_CONVERSATION_PAGE, content: body
      }
    };
    return want;
  }

  private parseMail(value: string): Record<string, Object> {
    if (value.startsWith('//')) {
      throw new MiniAppError(INVALID_ARGUMENT, 'Invalid mail address');
    }
    const separator: number = value.indexOf('?');
    const recipient: string = separator < 0 ? value : value.slice(0, separator);
    const params: Record<string, Object> = {};
    const recipients: string[] = recipient ? this.mailAddresses(recipient) : [];
    if (recipient) {
      params['email'] = recipients;
    }
    if (separator < 0) {
      return params;
    }
    for (const part of value.slice(separator + 1).split('&')) {
      const equals: number = part.indexOf('=');
      if (equals < 0) {
        continue;
      }
      const key: string = decodeURIComponent(part.slice(0, equals)).toLowerCase();
      const raw: string = part.slice(equals + 1);
      if (key === 'to') {
        recipients.push(...this.mailAddresses(raw));
        params['email'] = recipients;
      } else if (key === 'cc' || key === 'bcc') {
        params[key] = this.mailAddresses(raw);
      } else if (key === 'subject' || key === 'body') {
        const text: string = decodeURIComponent(raw);
        if (key === 'subject' && /[\u0000-\u001f\u007f]/.test(text)) {
          throw new MiniAppError(INVALID_ARGUMENT, 'Invalid mail subject');
        }
        // 系统 mail 面板要求 encodeURI；mailto 解码一次，保留加号和字面量百分号。
        params[key] = encodeURI(text);
      }
    }
    return params;
  }

  private mailAddresses(raw: string): string[] {
    if (!raw) {
      return [];
    }
    const addresses: string[] = decodeURIComponent(raw).split(',');
    for (let index: number = 0; index < addresses.length; index++) {
      const address: string = addresses[index];
      if (!address || /[\u0000-\u0020\u007f]/.test(address)) {
        throw new MiniAppError(INVALID_ARGUMENT, 'Invalid mail recipient');
      }
      addresses[index] = encodeURI(address);
    }
    return addresses;
  }

  private composeMail(params: Record<string, Object>): Promise<void> {
    return new Promise<void>((resolve, reject): void => {
      const callback: common.AbilityStartCallback = {
        onError: (code: number, name: string, message: string): void => {
          SdkLogger.debug('SystemLink', 'mailPanelFailed', { code: String(code), data: name + ':' + message });
          const cause: MailPanelFailure = { code };
          reject(new MiniAppError(SYSTEM_ERROR, 'Mail panel failed', cause));
        },
        onResult: (): void => resolve()
      };
      // 启动 Promise 成功只表示接受请求；继续等面板结果，以接收迟到的 onError。
      this.context.startAbilityByType('mail', params, callback).catch((error: Object): void => reject(error));
    });
  }
}
