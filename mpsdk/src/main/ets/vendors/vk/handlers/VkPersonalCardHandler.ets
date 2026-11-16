import { contact } from '@kit.ContactsKit';
import { BridgeContext } from '../../../core/Runtime';
import { MiniAppError } from '../../../core/MiniAppError';
import { APP_IN_BACKGROUND, INVALID_ARGUMENT, NOT_SUPPORTED, USER_CANCELLED } from '../../../core/MiniAppErrorCode';
import { ParamAssert } from '../../../utils/ParamAssert';
import { ContactSelectionTools } from '../../../capabilities/contacts/ContactSelectionTools';
import { PersonalCardSheetTools } from '../../../capabilities/contacts/PersonalCardSheet';
import {
  PersonalCardAddressValue,
  PersonalCardEntry,
  PersonalCardStore
} from '../../../capabilities/contacts/PersonalCardStore';
import { BaseVkEventHandler } from '../events/BaseVkEventHandler';
import { VkEvent } from '../events/VkEvent';
import { VkBridgeError } from '../VkBridgeError';
import { VkClientErrorCode } from '../VkClientErrorCode';

export const VK_WEB_APP_GET_PERSONAL_CARD: string = 'VKWebAppGetPersonalCard';

const PERSONAL_CARD_TYPES: ReadonlyArray<string> = ['phone', 'email', 'address'];

export interface VkPersonalCardParams {
  type?: string[];
}

export interface VkPersonalCardPlace {
  name: string;
}

export interface VkPersonalCardAddress {
  country?: VkPersonalCardPlace;
  city?: VkPersonalCardPlace;
  specified_address?: string;
  postal_code?: string;
}

export interface VkPersonalCardResult {
  phone?: string;
  email?: string;
  address?: VkPersonalCardAddress;
}

/** 资料来自用户在本机通讯录中明确选择的联系人，不含 VK 数字地区 id，也不等同 VK 账号侧已存卡片。 */
export class VkPersonalCardHandler implements BaseVkEventHandler {
  readonly context: BridgeContext;
  private picker?: ContactSelectionTools;
  private sheet?: PersonalCardSheetTools;
  private disposed: boolean = false;

  constructor(context: BridgeContext) {
    this.context = context;
  }

  @VkEvent({ name: VK_WEB_APP_GET_PERSONAL_CARD, timeout: -1 })
  async getPersonalCard(params: VkPersonalCardParams): Promise<VkPersonalCardResult> {
    this.assertOpen();
    ParamAssert.assertObject(params, 'params');
    const requested = this.assertTypes(params.type);
    try {
      const documentId = this.context.getDocumentId();
      const saved = await PersonalCardStore.load(this.context.uiAbilityContext, this.context.appId);
      this.assertOpen();
      const choice = await this.getSheet().open(saved,
        requested.indexOf('phone') >= 0, requested.indexOf('email') >= 0, requested.indexOf('address') >= 0,
        (): Promise<PersonalCardEntry | undefined> => this.prefillFromContacts());
      this.assertOpen();
      if (documentId !== this.context.getDocumentId()) {
        throw VkBridgeError.client(VkClientErrorCode.UNKNOWN);
      }
      const result = this.mapResult(choice.entry, requested);
      await PersonalCardStore.add(this.context.uiAbilityContext, this.context.appId, choice.entry);
      return result;
    } catch (error) {
      if (error instanceof VkBridgeError) {
        throw error;
      }
      if (error instanceof MiniAppError) {
        switch (error.code) {
          case USER_CANCELLED:
            throw VkBridgeError.client(VkClientErrorCode.USER_DENIED, undefined, error);
          case APP_IN_BACKGROUND:
            throw VkBridgeError.client(VkClientErrorCode.BACKGROUND, undefined, error);
          case NOT_SUPPORTED:
            throw VkBridgeError.client(VkClientErrorCode.UNSUPPORTED_PLATFORM, undefined, error);
        }
      }
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN, undefined, error as Object);
    }
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    const picker = this.picker;
    this.picker = undefined;
    picker?.dispose();
    const sheet = this.sheet;
    this.sheet = undefined;
    sheet?.dispose();
  }

  private assertTypes(value: Object | null | undefined): string[] {
    ParamAssert.assertStringArray(value, 'type');
    const values = value as string[];
    if (values.length === 0) {
      throw new MiniAppError(INVALID_ARGUMENT, '参数字段无效：type');
    }
    const requested: string[] = [];
    for (let index = 0; index < values.length; index++) {
      ParamAssert.assertEnum(values[index], 'type', PERSONAL_CARD_TYPES);
      if (requested.indexOf(values[index]) < 0) {
        requested.push(values[index]);
      }
    }
    return requested;
  }

  private mapResult(entry: PersonalCardEntry, requested: string[]): VkPersonalCardResult {
    const result: VkPersonalCardResult = {};
    if (requested.indexOf('phone') >= 0 && entry.phone.length > 0) {
      result.phone = entry.phone;
    }
    if (requested.indexOf('email') >= 0 && entry.email.length > 0) {
      result.email = entry.email;
    }
    if (requested.indexOf('address') >= 0 && entry.address !== undefined) {
      const address = this.mapAddress(entry.address);
      if (address !== undefined) {
        result.address = address;
      }
    }
    return result;
  }

  private mapAddress(value: PersonalCardAddressValue): VkPersonalCardAddress | undefined {
    const address: VkPersonalCardAddress = {};
    if (this.nonEmpty(value.specifiedAddress)) {
      address.specified_address = value.specifiedAddress;
    }
    if (this.nonEmpty(value.postalCode)) {
      address.postal_code = value.postalCode;
    }
    if (this.nonEmpty(value.city)) {
      const city: VkPersonalCardPlace = { name: value.city };
      address.city = city;
    }
    if (this.nonEmpty(value.country)) {
      const country: VkPersonalCardPlace = { name: value.country };
      address.country = country;
    }
    if (address.specified_address === undefined && address.postal_code === undefined &&
      address.city === undefined && address.country === undefined) {
      return undefined;
    }
    return address;
  }

  private nonEmpty(value: string | undefined): boolean {
    return typeof value === 'string' && value.length > 0;
  }

  private async prefillFromContacts(): Promise<PersonalCardEntry | undefined> {
    const selected = await this.getPicker().selectContact();
    return this.contactToEntry(selected);
  }

  private contactToEntry(selected: contact.Contact): PersonalCardEntry {
    const entry = new PersonalCardEntry();
    const phones = selected.phoneNumbers;
    if (phones !== undefined && phones.length > 0 && typeof phones[0].phoneNumber === 'string') {
      entry.phone = phones[0].phoneNumber;
    }
    const emails = selected.emails;
    if (emails !== undefined && emails.length > 0 && typeof emails[0].email === 'string') {
      entry.email = emails[0].email;
    }
    const postalAddresses = selected.postalAddresses;
    if (postalAddresses !== undefined && postalAddresses.length > 0) {
      const source = postalAddresses[0];
      const address = new PersonalCardAddressValue();
      if (this.nonEmpty(source.street)) {
        address.specifiedAddress = source.street as string;
      } else if (this.nonEmpty(source.postalAddress)) {
        address.specifiedAddress = source.postalAddress as string;
      }
      if (this.nonEmpty(source.postcode)) {
        address.postalCode = source.postcode as string;
      }
      if (this.nonEmpty(source.city)) {
        address.city = source.city as string;
      }
      if (this.nonEmpty(source.country)) {
        address.country = source.country as string;
      }
      if (address.specifiedAddress.length > 0 || address.postalCode.length > 0 ||
        address.city.length > 0 || address.country.length > 0) {
        entry.address = address;
      }
    }
    return entry;
  }

  private getPicker(): ContactSelectionTools {
    if (!this.picker) {
      const picker = new ContactSelectionTools(this.context.uiAbilityContext);
      this.picker = picker;
      this.context.addCleanup((): void => {
        if (this.picker === picker) {
          this.picker = undefined;
          picker.dispose();
        }
      });
    }
    return this.picker;
  }

  private getSheet(): PersonalCardSheetTools {
    if (!this.sheet) {
      const sheet = new PersonalCardSheetTools(this.context.uiAbilityContext);
      this.sheet = sheet;
      this.context.addCleanup((): void => {
        if (this.sheet === sheet) {
          this.sheet = undefined;
          sheet.dispose();
        }
      });
    }
    return this.sheet;
  }

  private assertOpen(): void {
    if (this.disposed) {
      throw VkBridgeError.client(VkClientErrorCode.UNKNOWN);
    }
  }
}
